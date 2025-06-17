//+------------------------------------------------------------------+
//|                    Enhanced_MT5_Telegram_Discord_Tracker.mq5     |
//|                                                   Trade Tracker EA |
//|                                Sends alerts to Telegram & Discord |
//+------------------------------------------------------------------+
#property copyright "Enhanced Trade Tracker EA with Discord"
#property version   "4.0"
#property strict

// Telegram Input parameters
input string TelegramBotToken = "7165263301:AAGAVwbK938E3WXuqpFQAl1P9RoWrAHm52s"; // Telegram Bot Token
input string TelegramChatID = "6501082183"; // Telegram Chat ID

// Discord Input parameters
input string DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1376805063191957514/tc0kMuoEI4clgSS_oYwSCrvCkyuVKfDF9ySR1Dz8NFhK_LV7x7FSeDauHlKRIDAkREzH"; // Discord Webhook URL
input bool ENABLE_DISCORD_ALERTS = true; // Enable Discord alerts

// Alert Configuration
input bool EnableTradeAlerts = true; // Enable trade open/close alerts
input bool EnableModifyAlerts = true; // Enable SL/TP modify alerts
input bool EnableDailySummary = true; // Enable daily P/L summary
input string SummaryTime = "23:59"; // Daily summary time (HH:MM)
input bool EnableSounds = true; // Enable sound notifications
input string BotName = "SMC Hybrid"; // Bot display name
input bool EnableDetailedMessages = true; // Enable detailed formatting
input int MessageRetryAttempts = 3; // Number of retry attempts for failed messages

// Global variables
datetime lastSummaryDate = 0;
double dayStartBalance = 0;
int totalPositions = 0;
ulong trackedPositions[];
double trackedSL[];
double trackedTP[];
datetime lastMessageTime = 0;
int telegramMessageCount = 0;
int discordMessageCount = 0;

// Structure for tracking position data and message IDs
struct PositionData
{
    ulong ticket;
    string symbol;
    double volume;
    double openPrice;
    double sl;
    double tp;
    ENUM_POSITION_TYPE type;
    datetime openTime;
    string telegramMessageId;
};

// Array to store position data with message IDs
PositionData positionsData[];

//+------------------------------------------------------------------+
//| Discord Alert Class                                              |
//+------------------------------------------------------------------+
class CDiscordAlert
{
private:
    string webhook_url;
    string bot_name;
    
public:
    CDiscordAlert(string url, string name) : webhook_url(url), bot_name(name) {}
    
    // Send basic message to Discord
    bool SendMessage(string message, string emoji = "📊")
    {
        if(!ENABLE_DISCORD_ALERTS) return false;
        
        string json_payload = CreateJsonPayload(message, emoji);
        return SendWebhookRequest(json_payload);
    }
    
    // Send trade alert matching Telegram format
    bool SendTradeAlert(string message, string emoji = "📊")
    {
        if(!ENABLE_DISCORD_ALERTS || !EnableTradeAlerts) return false;
        return SendMessage(message, emoji);
    }
    
    // Send modify alert
    bool SendModifyAlert(string message, string emoji = "⚙️")
    {
        if(!ENABLE_DISCORD_ALERTS || !EnableModifyAlerts) return false;
        return SendMessage(message, emoji);
    }
    
    // Send market news/event
    bool SendMarketEvent(string event_title, string description, string impact = "MEDIUM")
    {
        string emoji = "📰";
        if(impact == "HIGH") emoji = "🚨";
        else if(impact == "LOW") emoji = "ℹ️";
        
        string message = StringFormat(
            "**MARKET EVENT** %s\n"
            "📢 **Title:** %s\n"
            "📝 **Description:** %s\n"
            "⚡ **Impact:** %s\n"
            "🕐 **Time:** %s",
            emoji,
            event_title,
            description,
            impact,
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
        );
        
        return SendMessage(message, emoji);
    }

private:
    // Create JSON payload for Discord webhook
    string CreateJsonPayload(string message, string emoji)
    {
        // Convert Telegram markdown to Discord markdown
        string discord_message = ConvertToDiscordMarkdown(message);
        
        // Escape JSON special characters
        string escaped_message = EscapeJsonString(discord_message);
        
        // Create simple JSON without embeds to avoid formatting issues
        string json = StringFormat(
            "{\"username\":\"%s %s\",\"content\":\"%s\"}",
            emoji, bot_name,
            escaped_message
        );
        
        return json;
    }
    
    // Convert Telegram markdown to Discord markdown
    string ConvertToDiscordMarkdown(string text)
    {
        string result = text;
        // Discord uses ** for bold instead of *
        StringReplace(result, "*", "**");
        // Remove any Telegram-specific formatting
        StringReplace(result, "─────────────────────────", "━━━━━━━━━━━━━━━━━━━━━━━━━");
        return result;
    }
    
    // Helper function to escape JSON strings
    string EscapeJsonString(string str)
    {
        string result = str;
        StringReplace(result, "\\", "\\\\");  // Escape backslashes first
        StringReplace(result, "\"", "\\\"");  // Escape quotes
        StringReplace(result, "\n", "\\n");   // Escape newlines
        StringReplace(result, "\r", "\\r");   // Escape carriage returns
        StringReplace(result, "\t", "\\t");   // Escape tabs
        return result;
    }
    
    // Send HTTP request to Discord webhook
    bool SendWebhookRequest(string json_data)
    {
        char post[], result[];
        string headers;
        
        // Rate limiting for Discord
        static datetime lastDiscordMessage = 0;
        if(TimeCurrent() - lastDiscordMessage < 1) 
        {
            Sleep(1100); // Wait 1.1 seconds between Discord messages
        }
        lastDiscordMessage = TimeCurrent();
        
        // Debug: Print the JSON being sent
        Print("📤 Sending Discord JSON: ", json_data);
        
        // Convert string to char array
        StringToCharArray(json_data, post, 0, WHOLE_ARRAY, CP_UTF8);
        ArrayResize(post, ArraySize(post)-1); // Remove null terminator
        
        // Set headers
        headers = "Content-Type: application/json\r\n";
        headers += "User-Agent: MT5-Discord-Tracker/4.0\r\n";
        
        // Send POST request
        int timeout = 5000; // 5 seconds timeout
        int res = WebRequest("POST", webhook_url, headers, timeout, post, result, headers);
        
        // Debug: Print response
        if(ArraySize(result) > 0)
        {
            string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
            Print("📥 Discord Response: ", response);
        }
        
        if(res == 200 || res == 204)
        {
            Print("✅ Discord alert sent successfully");
            discordMessageCount++;
            return true;
        }
        else if(res == 429) // Rate limited
        {
            Print("⏰ Rate limited by Discord, waiting...");
            Sleep(5000); // Wait 5 seconds for Discord rate limit
            return false;
        }
        else
        {
            Print("❌ Failed to send Discord alert. HTTP Code: ", res);
            return false;
        }
    }
};

// Global Discord alert object
CDiscordAlert* discord_alert;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate Telegram settings
    if(TelegramBotToken == "" || TelegramChatID == "")
    {
        Alert("❌ Telegram Bot Token and Chat ID are required!");
        return INIT_FAILED;
    }
    
    // Initialize Discord alert
    discord_alert = new CDiscordAlert(DISCORD_WEBHOOK_URL, BotName);
    
    // Initialize daily tracking
    dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    lastSummaryDate = TimeCurrent();
    
    // Get current positions for tracking
    InitializePositionTracking();
    
    Print("Enhanced MT5 Telegram + Discord Tracker initialized successfully");
    
    // Send startup message to both platforms
    string startMessage = "✅ *MT5 Trade Tracker Started*\n";
    startMessage += "Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n";
    startMessage += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    startMessage += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
    startMessage += "─────────────────────────";
    
    SendTelegramMessage(startMessage, "");
    discord_alert.SendMessage(startMessage, "🚀");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    string stopMessage = "*MT5 Trade Tracker Stopped*\n";
    stopMessage += "Reason: " + GetUninitReasonText(reason) + "\n";
    stopMessage += "Telegram Messages: " + IntegerToString(telegramMessageCount) + "\n";
    stopMessage += "Discord Messages: " + IntegerToString(discordMessageCount) + "\n";
    stopMessage += "Runtime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
    stopMessage += "─────────────────────────";
    
    SendTelegramMessage(stopMessage, "");
    
    if(discord_alert != NULL)
    {
        discord_alert.SendMessage(stopMessage, "⏹️");
        delete discord_alert;
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastCheck = 0;
    
    // Throttle checks to prevent spam (check every second)
    if(TimeCurrent() - lastCheck < 1) return;
    lastCheck = TimeCurrent();
    
    CheckNewPositions();
    CheckPositionModifications();
    CheckClosedPositions();
    CheckDailySummary();
}

//+------------------------------------------------------------------+
//| Initialize position tracking arrays                              |
//+------------------------------------------------------------------+
void InitializePositionTracking()
{
    int positions = PositionsTotal();
    ArrayResize(trackedPositions, positions);
    ArrayResize(trackedSL, positions);
    ArrayResize(trackedTP, positions);
    ArrayResize(positionsData, positions);
    
    totalPositions = 0;
    
    for(int i = 0; i < positions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            trackedPositions[totalPositions] = ticket;
            trackedSL[totalPositions] = PositionGetDouble(POSITION_SL);
            trackedTP[totalPositions] = PositionGetDouble(POSITION_TP);
            
            // Store position data
            positionsData[totalPositions].ticket = ticket;
            positionsData[totalPositions].symbol = PositionGetString(POSITION_SYMBOL);
            positionsData[totalPositions].volume = PositionGetDouble(POSITION_VOLUME);
            positionsData[totalPositions].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            positionsData[totalPositions].sl = PositionGetDouble(POSITION_SL);
            positionsData[totalPositions].tp = PositionGetDouble(POSITION_TP);
            positionsData[totalPositions].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            positionsData[totalPositions].openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            totalPositions++;
        }
    }
    
    ArrayResize(trackedPositions, totalPositions);
    ArrayResize(trackedSL, totalPositions);
    ArrayResize(trackedTP, totalPositions);
    ArrayResize(positionsData, totalPositions);
}

//+------------------------------------------------------------------+
//| Calculate pips between two prices                                |
//+------------------------------------------------------------------+
double CalculatePips(string symbol, double price1, double price2)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // For cryptocurrencies (BTC, ETH, etc.)
    if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0 || 
       StringFind(symbol, "LTC") >= 0 || StringFind(symbol, "XRP") >= 0)
    {
        // For crypto, use whole points as "pips"
        return MathAbs(price1 - price2);
    }
    // For Gold/Silver
    else if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "XAG") >= 0)
    {
        // For metals, 1 pip = 0.01 for XAUUSD, 0.001 for XAGUSD
        if(StringFind(symbol, "XAU") >= 0)
            return MathAbs(price1 - price2) / 0.01;
        else
            return MathAbs(price1 - price2) / 0.001;
    }
    // For forex pairs (excluding JPY pairs)
    else if(digits == 5 || digits == 3)
    {
        return MathAbs(price1 - price2) / (point * 10);
    }
    // For JPY pairs and others
    else
    {
        return MathAbs(price1 - price2) / point;
    }
}

//+------------------------------------------------------------------+
//| Get position data by ticket                                     |
//+------------------------------------------------------------------+
int GetPositionDataIndex(ulong ticket)
{
    for(int i = 0; i < ArraySize(positionsData); i++)
    {
        if(positionsData[i].ticket == ticket)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Check for new positions                                          |
//+------------------------------------------------------------------+
void CheckNewPositions()
{
    int currentPositions = PositionsTotal();
    
    if(currentPositions > totalPositions)
    {
        // Find new positions
        for(int i = 0; i < currentPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
                // Check if this is a new position
                bool isNew = true;
                for(int j = 0; j < totalPositions; j++)
                {
                    if(trackedPositions[j] == ticket)
                    {
                        isNew = false;
                        break;
                    }
                }
                
                if(isNew && EnableTradeAlerts)
                {
                    SendTradeOpenAlert(ticket);
                    if(EnableSounds) PlaySound("alert.wav");
                    Sleep(500); // Small delay to prevent rapid-fire alerts
                }
            }
        }
        
        // Update tracking arrays
        InitializePositionTracking();
    }
}

//+------------------------------------------------------------------+
//| Check for position modifications                                 |
//+------------------------------------------------------------------+
void CheckPositionModifications()
{
    if(!EnableModifyAlerts) return;
    
    for(int i = 0; i < totalPositions; i++)
    {
        if(PositionSelectByTicket(trackedPositions[i]))
        {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            string symbol = PositionGetString(POSITION_SYMBOL);
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            
            bool slChanged = MathAbs(currentSL - trackedSL[i]) > SymbolInfoDouble(symbol, SYMBOL_POINT);
            bool tpChanged = MathAbs(currentTP - trackedTP[i]) > SymbolInfoDouble(symbol, SYMBOL_POINT);
            
            if(slChanged || tpChanged)
            {
                SendPositionModifyAlert(trackedPositions[i], trackedSL[i], trackedTP[i], currentSL, currentTP);
                trackedSL[i] = currentSL;
                trackedTP[i] = currentTP;
                
                // Update position data
                int idx = GetPositionDataIndex(trackedPositions[i]);
                if(idx >= 0)
                {
                    positionsData[idx].sl = currentSL;
                    positionsData[idx].tp = currentTP;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for closed positions                                       |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
    int currentPositions = PositionsTotal();
    
    if(currentPositions < totalPositions)
    {
        // Check recent history for closed trades
        datetime fromTime = TimeCurrent() - 300; // Last 5 minutes
        if(HistorySelect(fromTime, TimeCurrent()))
        {
            int deals = HistoryDealsTotal();
            for(int i = deals - 1; i >= 0; i--)
            {
                ulong dealTicket = HistoryDealGetTicket(i);
                if(dealTicket > 0)
                {
                    ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                    datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                    
                    // Only process recent exit deals
                    if(dealEntry == DEAL_ENTRY_OUT && dealTime > TimeCurrent() - 60 && EnableTradeAlerts)
                    {
                        SendTradeCloseAlert(dealTicket);
                        if(EnableSounds) 
                        {
                            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                            if(profit > 0)
                                PlaySound("ok.wav");
                            else
                                PlaySound("timeout.wav");
                        }
                        Sleep(500); // Prevent spam
                    }
                }
            }
        }
        
        // Update tracking
        InitializePositionTracking();
    }
}

//+------------------------------------------------------------------+
//| Send trade open alert to both platforms                         |
//+------------------------------------------------------------------+
void SendTradeOpenAlert(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    string typeEmoji = (type == POSITION_TYPE_BUY) ? "🟢" : "🔴";
    string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    
    // Calculate pips for SL and TP
    string slPips = "";
    string tpPips = "";
    
    if(sl > 0)
        slPips = " [" + DoubleToString(CalculatePips(symbol, openPrice, sl), 1) + " Pips]";
    
    if(tp > 0)
        tpPips = " [" + DoubleToString(CalculatePips(symbol, tp, openPrice), 1) + " Pips]";
    
    // Create message in new format
    string message = "📊 " + symbol + "  | 🔔New Trade Signal🔔\n";
    message += typeEmoji + " " + typeStr + " | " + DoubleToString(volume, 2) + " lots @ " + DoubleToString(openPrice, digits) + " 🎯\n";
    
    if(sl > 0)
        message += "SL: " + DoubleToString(sl, digits) + slPips + "\n";
    else
        message += "SL: *Not Set*\n";
        
    if(tp > 0)
        message += "TP: " + DoubleToString(tp, digits) + tpPips + "\n";
    else
        message += "TP: *Not Set*\n";
    
    // Send to Telegram
    string messageId = SendTelegramMessage(message, "");
    // Store message ID for future replies
    int idx = GetPositionDataIndex(ticket);
    if(idx >= 0)
        positionsData[idx].telegramMessageId = messageId;
    
    // Send to Discord
    discord_alert.SendTradeAlert(message, typeEmoji);
}

//+------------------------------------------------------------------+
//| Send position modify alert to both platforms                    |
//+------------------------------------------------------------------+
void SendPositionModifyAlert(ulong ticket, double oldSL, double oldTP, double newSL, double newTP)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    string typeEmoji = (type == POSITION_TYPE_BUY) ? "🟢" : "🔴";
    string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    
    // Create modified message
    string message = "📊 " + symbol + "  | ⚙️Modified⚙️\n";
    message += typeEmoji + " " + typeStr + " | " + DoubleToString(volume, 2) + " lots @ " + DoubleToString(openPrice, digits) + " 🎯\n";
    
    // Only show changed values
    if(MathAbs(newSL - oldSL) > SymbolInfoDouble(symbol, SYMBOL_POINT))
    {
        if(oldSL > 0)
            message += "🗑️ Old SL: " + DoubleToString(oldSL, digits) + "\n";
        else
            message += "🗑️ Old SL: *Not Set*\n";
            
        if(newSL > 0)
        {
            string slPips = " [" + DoubleToString(CalculatePips(symbol, openPrice, newSL), 1) + " Pips]";
            message += "👉 New SL: " + DoubleToString(newSL, digits) + slPips + "\n";
        }
        else
            message += "👉 New SL: *Not Set*\n";
    }
    
    if(MathAbs(newTP - oldTP) > SymbolInfoDouble(symbol, SYMBOL_POINT))
    {
        if(oldTP > 0)
            message += "🗑️ Old TP: " + DoubleToString(oldTP, digits) + "\n";
        else
            message += "🗑️ Old TP: *Not Set*\n";
            
        if(newTP > 0)
        {
            string tpPips = " [" + DoubleToString(CalculatePips(symbol, newTP, openPrice), 1) + " Pips]";
            message += "👉 New TP: " + DoubleToString(newTP, digits) + tpPips + "\n";
        }
        else
            message += "👉 New TP: *Not Set*\n";
    }
    
    // Send as reply if we have the original message ID
    int idx = GetPositionDataIndex(ticket);
    string replyToMessageId = "";
    if(idx >= 0 && positionsData[idx].telegramMessageId != "")
        replyToMessageId = positionsData[idx].telegramMessageId;
    
    SendTelegramMessage(message, replyToMessageId);
    discord_alert.SendModifyAlert(message, "⚙️");
}

//+------------------------------------------------------------------+
//| Send trade close alert to both platforms                        |
//+------------------------------------------------------------------+
void SendTradeCloseAlert(ulong dealTicket)
{
    string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
    ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
    datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Get the position ticket to retrieve original data
    ulong positionTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    
    // Find position data
    int idx = GetPositionDataIndex(positionTicket);
    string replyToMessageId = "";
    double openPrice = 0;
    double sl = 0;
    double tp = 0;
    ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
    
    if(idx >= 0)
    {
        openPrice = positionsData[idx].openPrice;
        sl = positionsData[idx].sl;
        tp = positionsData[idx].tp;
        type = positionsData[idx].type;
        replyToMessageId = positionsData[idx].telegramMessageId;
    }
    
    string typeEmoji = (type == POSITION_TYPE_BUY) ? "🟢" : "🔴";
    string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    
    string message = "";
    string closeEmoji = "🔒";
    
    if(reason == DEAL_REASON_TP)
    {
        message = "📊 " + symbol + "  | 🏆 Take Profit Hit ✅\n";
        closeEmoji = "🏆";
    }
    else if(reason == DEAL_REASON_SL)
    {
        message = "📊 " + symbol + "  | 🛡️ Stoploss Hit ❌\n";
        closeEmoji = "🛡️";
    }
    else
    {
        message = "📊 " + symbol + "  | 🔒Trade Closed🔒\n";
    }
    
    message += typeEmoji + " " + typeStr + " | " + DoubleToString(volume, 2) + " lots @ " + DoubleToString(openPrice, digits) + " 🎯\n";
    
    // Add SL and TP info
    if(sl > 0)
    {
        string slPips = " [" + DoubleToString(CalculatePips(symbol, openPrice, sl), 1) + " Pips]";
        message += "SL: " + DoubleToString(sl, digits) + slPips + "\n";
    }
    else
        message += "SL: *Not Set*\n";
        
    if(tp > 0)
    {
        string tpPips = " [" + DoubleToString(CalculatePips(symbol, tp, openPrice), 1) + " Pips]";
        message += "TP: " + DoubleToString(tp, digits) + tpPips + "\n";
    }
    else
        message += "TP: *Not Set*\n";
    
    // Add P&L
    if(profit >= 0)
        message += "PnL: 💰$" + DoubleToString(profit, 2) + "\n";
    else
        message += "PnL: -$" + DoubleToString(MathAbs(profit), 2) + "❌\n";
    
    SendTelegramMessage(message, replyToMessageId);
    discord_alert.SendTradeAlert(message, closeEmoji);
}

//+------------------------------------------------------------------+
//| Check for daily summary                                          |
//+------------------------------------------------------------------+
void CheckDailySummary()
{
    if(!EnableDailySummary) return;
    
    MqlDateTime currentTime, lastSummary;
    TimeToStruct(TimeCurrent(), currentTime);
    TimeToStruct(lastSummaryDate, lastSummary);
    
    // Parse summary time
    string timeParts[];
    StringSplit(SummaryTime, StringGetCharacter(":", 0), timeParts);
    int summaryHour = (int)StringToInteger(timeParts[0]);
    int summaryMinute = (int)StringToInteger(timeParts[1]);
    
    if(currentTime.day != lastSummary.day && 
       currentTime.hour >= summaryHour && 
       currentTime.min >= summaryMinute)
    {
        SendDailySummary();
        lastSummaryDate = TimeCurrent();
        dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }
}

//+------------------------------------------------------------------+
//| Send daily summary to both platforms                            |
//+------------------------------------------------------------------+
void SendDailySummary()
{
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPL = currentBalance - dayStartBalance;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    
    // Get daily statistics from history
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    HistorySelect(dayStart, TimeCurrent());
    
    int totalTrades = 0;
    int winningTrades = 0;
    int losingTrades = 0;
    double totalProfit = 0;
    double bestTrade = 0;
    double worstTrade = 0;
    
    int deals = HistoryDealsTotal();
    for(int i = 0; i < deals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket > 0)
        {
            ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(dealEntry == DEAL_ENTRY_OUT)
            {
                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                totalProfit += profit;
                totalTrades++;
                
                if(profit > 0) winningTrades++;
                else if(profit < 0) losingTrades++;
                
                if(profit > bestTrade) bestTrade = profit;
                if(profit < worstTrade) worstTrade = profit;
            }
        }
    }
    
    // Create summary message
    string message = "📊 *DAILY TRADING SUMMARY*\n";
    message += "*Date:* " + TimeToString(TimeCurrent(), TIME_DATE) + "\n\n";
    message += "💰 *Performance Overview:*\n";
    
    if(dailyPL >= 0)
        message += "Daily P/L: +$" + DoubleToString(dailyPL, 2) + "✅\n";
    else
        message += "Daily P/L: -$" + DoubleToString(MathAbs(dailyPL), 2) + "❌\n";
        
    message += "Balance: $" + DoubleToString(currentBalance, 2) + "\n";
    message += "Equity: $" + DoubleToString(equity, 2) + "\n";
    message += "Free Margin: $" + DoubleToString(freeMargin, 2) + "\n";
    
    if(marginLevel > 0) 
        message += "Margin Level: " + DoubleToString(marginLevel, 2) + "%\n";
    
    message += "\n📈 *Trading Statistics:*\n";
    message += "Total Trades: " + IntegerToString(totalTrades) + "\n";
    message += "Winning Trades: " + IntegerToString(winningTrades) + "✅\n";
    message += "Losing Trades: " + IntegerToString(losingTrades) + "❌\n";
    
    if(totalTrades > 0)
    {
        double winRate = (double)winningTrades / totalTrades * 100;
        message += "Win Rate: " + DoubleToString(winRate, 1) + "%\n";
        message += "Best Trade: +$" + DoubleToString(bestTrade, 2) + "\n";
        message += "Worst Trade: -$" + DoubleToString(MathAbs(worstTrade), 2) + "\n";
    }
    
    message += "\n📊 *Current Status:*\n";
    message += "Active Positions: " + IntegerToString(PositionsTotal()) + "\n";
    message += "Telegram Messages: " + IntegerToString(telegramMessageCount) + "\n";
    message += "Discord Messages: " + IntegerToString(discordMessageCount) + "\n";
    message += "─────────────────────────";
    
    SendTelegramMessage(message, "");
    discord_alert.SendMessage(message, "📊");
}

//+------------------------------------------------------------------+
//| Send message to Telegram with retry logic                        |
//+------------------------------------------------------------------+
string SendTelegramMessage(string message, string replyToMessageId = "")
{
    if(TelegramBotToken == "" || TelegramChatID == "") return "";
    
    string headers = "Content-Type: application/json\r\n";
    headers += "User-Agent: MT5-Telegram-Tracker/4.0\r\n";
    
    // Rate limiting check for Telegram (30 messages per second max)
    static datetime lastTelegramMessage = 0;
    if(TimeCurrent() - lastTelegramMessage < 1) 
    {
        Sleep(1100); // Wait 1.1 seconds between Telegram messages
    }
    lastTelegramMessage = TimeCurrent();
    
    // Escape special characters for Telegram markdown
    string escapedMessage = EscapeTelegramString(message);
    
    // Create Telegram API URL
    string telegramURL = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
    
    // Create JSON payload for Telegram
    string json = "{";
    json += "\"chat_id\":\"" + TelegramChatID + "\",";
    json += "\"text\":\"" + escapedMessage + "\",";
    json += "\"parse_mode\":\"Markdown\",";
    json += "\"disable_web_page_preview\":true";
    
    // Add reply_to_message_id if provided
    if(replyToMessageId != "" && StringToInteger(replyToMessageId) > 0)
    {
        json += ",\"reply_to_message_id\":" + replyToMessageId;
    }
    
    json += "}";
    
    char data[];
    StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);
    
    bool success = false;
    int attempts = 0;
    string messageId = "";
    
    while(!success && attempts < MessageRetryAttempts)
    {
        attempts++;
        
        char result[];
        string resultHeaders;
        int timeout = 15000; // 15 second timeout for Telegram
        
        int res = WebRequest("POST", telegramURL, headers, timeout, data, result, resultHeaders);
        
        if(res == 200)
        {
            success = true;
            telegramMessageCount++;
            
            // Parse message ID from response
            string response = CharArrayToString(result);
            int messageIdStart = StringFind(response, "\"message_id\":");
            if(messageIdStart >= 0)
            {
                messageIdStart += 13; // Length of "\"message_id\":"
                int messageIdEnd = StringFind(response, ",", messageIdStart);
                if(messageIdEnd < 0) messageIdEnd = StringFind(response, "}", messageIdStart);
                if(messageIdEnd > messageIdStart)
                {
                    messageId = StringSubstr(response, messageIdStart, messageIdEnd - messageIdStart);
                }
            }
            
            Print("✅ Telegram message sent successfully (attempt ", attempts, "), Message ID: ", messageId);
        }
        else if(res == -1)
        {
            int lastError = GetLastError();
            Print("❌ Telegram API error (attempt ", attempts, "): Code ", lastError);
            if(attempts < MessageRetryAttempts) Sleep(2000 * attempts); // Exponential backoff
        }
        else if(res == 429) // Rate limited
        {
            Print("⏰ Rate limited by Telegram (attempt ", attempts, "), waiting...");
            Sleep(10000); // Wait 10 seconds for Telegram rate limit
        }
        else
        {
            Print("❌ Telegram HTTP error (attempt ", attempts, "): ", res);
            string response = CharArrayToString(result);
            Print("Response: ", response);
            
            // Check for specific Telegram errors
            if(StringFind(response, "chat not found") >= 0)
            {
                Print("❌ Telegram Chat ID not found or bot not added to chat");
                break; // Don't retry for invalid chat ID
            }
            else if(StringFind(response, "bot was blocked") >= 0)
            {
                Print("❌ Bot was blocked by user");
                break; // Don't retry if blocked
            }
            
            if(attempts < MessageRetryAttempts) Sleep(1000 * attempts);
        }
    }
    
    if(!success)
    {
        Print("❌ Failed to send Telegram message after ", MessageRetryAttempts, " attempts");
        Print("JSON payload length: ", StringLen(json));
    }
    
    return messageId;
}

//+------------------------------------------------------------------+
//| Escape special characters for Telegram Markdown                 |
//+------------------------------------------------------------------+
string EscapeTelegramString(string str)
{
    // For Telegram, we don't need to escape most characters when using parse_mode Markdown
    // Just return the string as-is to preserve emojis and formatting
    return str;
}

//+------------------------------------------------------------------+
//| Get uninitialization reason text                                 |
//+------------------------------------------------------------------+
string GetUninitReasonText(int reason)
{
    switch(reason)
    {
        case REASON_PROGRAM: return "EA stopped by user";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Chart symbol/period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "EA parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "Template changed";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason (" + IntegerToString(reason) + ")";
    }
}
