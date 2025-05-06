import MetaTrader5 as mt5
import time
import discord
from discord.ext import commands, tasks
import threading
from datetime import datetime
import tkinter as tk
from tkinter import ttk, scrolledtext
import pandas as pd
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import matplotlib.pyplot as plt
from matplotlib.dates import DateFormatter
import numpy as np
import asyncio

# Discord bot configuration
DISCORD_TOKEN = "MTM2ODk3NzIwNTc4NjU3NTAxMQ.Gsn1HV.bKxQxAGO7q1DP7wehLoMzDj3-4VoPq35GiGfSE"
CHANNEL_ID = "368978046857515182"  # Updated channel ID

class MT5OrderTracker:
    def __init__(self):
        self.connected = False
        self.orders = {}  # Track open orders
        self.positions = {}  # Track open positions
        self.history = {}  # Track position history for profit tracking
        self.discord_bot = None
        self.bot_thread = None
        self.gui = None
        self.tracking_active = False
        self.symbols = []  # Will store all available symbols
        
    def connect(self):
        """Connect to MT5 terminal"""
        if not mt5.initialize():
            print(f"MT5 initialize() failed, error code = {mt5.last_error()}")
            return False
        
        self.connected = True
        print(f"Connected to MT5: {mt5.terminal_info()}")
        
        # Get all available symbols
        symbols_info = mt5.symbols_get()
        self.symbols = [symbol.name for symbol in symbols_info]
        
        return True
    
    def start_discord_bot(self):
        """Start Discord bot in a separate thread"""
        self.bot_thread = threading.Thread(target=self._run_discord_bot)
        self.bot_thread.daemon = True
        self.bot_thread.start()
        
    def _run_discord_bot(self):
        """Run the Discord bot"""
        # Create intents without privileged intents
        intents = discord.Intents.default()
        # Explicitly disable privileged intents
        intents.message_content = False
        intents.presences = False
        intents.members = False
        
        bot = commands.Bot(command_prefix='!', intents=intents)
        self.discord_bot = bot
        
        @bot.event
        async def on_ready():
            print(f'Discord bot logged in as {bot.user}')
            track_orders.start()
            if self.gui:
                self.gui.update_status(f"Discord bot connected as {bot.user}")
        
        @tasks.loop(seconds=5)
        async def track_orders():
            if self.tracking_active:
                await self.check_orders_and_positions()
        
        try:
            bot.run(DISCORD_TOKEN)
        except discord.errors.PrivilegedIntentsRequired:
            print("ERROR: Privileged intents are required but not enabled in Discord Developer Portal")
            print("Please go to https://discord.com/developers/applications/ and enable the required intents")
            if self.gui:
                self.gui.log_message("ERROR: Discord bot failed to start - Privileged intents required", is_error=True)
        except Exception as e:
            print(f"Error starting Discord bot: {e}")
            if self.gui:
                self.gui.log_message(f"ERROR: Discord bot failed to start - {e}", is_error=True)
    
    async def send_discord_message(self, message):
        """Send message to Discord channel"""
        if self.discord_bot:
            try:
                channel = self.discord_bot.get_channel(int(CHANNEL_ID))
                if channel:
                    await channel.send(message)
                    if self.gui:
                        self.gui.log_message(f"Discord message sent: {message[:50]}...")
                else:
                    error_msg = f"Could not find channel with ID {CHANNEL_ID}"
                    print(error_msg)
                    if self.gui:
                        self.gui.log_message(error_msg, is_error=True)
            except Exception as e:
                print(f"Error sending Discord message: {e}")
                if self.gui:
                    self.gui.log_message(f"Error sending Discord message: {e}", is_error=True)
        else:
            error_msg = "Discord bot not initialized"
            print(error_msg)
            if self.gui:
                self.gui.log_message(error_msg, is_error=True)
    
    async def check_orders_and_positions(self):
        """Check for new orders and position updates across all symbols"""
        if not self.connected:
            return
        
        # Check for new orders (all symbols)
        orders = mt5.orders_get()
        current_orders = {}
        
        if orders:
            for order in orders:
                order_id = order.ticket
                current_orders[order_id] = order
                
                # New order detected
                if order_id not in self.orders:
                    message = (
                        f"🔔 **New Order Placed**\n"
                        f"Symbol: {order.symbol}\n"
                        f"Type: {'Buy' if order.type == mt5.ORDER_TYPE_BUY else 'Sell'}\n"
                        f"Volume: {order.volume}\n"
                        f"Price: {order.price_open}\n"
                        f"Time: {datetime.fromtimestamp(order.time_setup)}"
                    )
                    await self.send_discord_message(message)
                    if self.gui:
                        self.gui.log_message(f"New order detected: {order.symbol} {order.ticket}")
        
        # Check for closed orders
        for order_id in list(self.orders.keys()):
            if order_id not in current_orders:
                order = self.orders[order_id]
                message = (
                    f"🔔 **Order Closed/Executed**\n"
                    f"Symbol: {order.symbol}\n"
                    f"Order ID: {order_id}"
                )
                await self.send_discord_message(message)
                if self.gui:
                    self.gui.log_message(f"Order closed: {order.symbol} {order_id}")
        
        self.orders = current_orders
        
        # Check positions (all symbols)
        positions = mt5.positions_get()
        current_positions = {}
        
        if positions:
            for position in positions:
                position_id = position.ticket
                current_positions[position_id] = position
                
                # New position or updated position
                if position_id not in self.positions:
                    message = (
                        f"🔔 **New Position Opened**\n"
                        f"Symbol: {position.symbol}\n"
                        f"Type: {'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell'}\n"
                        f"Volume: {position.volume}\n"
                        f"Open Price: {position.price_open}\n"
                        f"SL: {position.sl}\n"
                        f"TP: {position.tp}\n"
                        f"Time: {datetime.fromtimestamp(position.time)}"
                    )
                    await self.send_discord_message(message)
                    
                    # Add to history for tracking
                    self.history[position_id] = {
                        'symbol': position.symbol,
                        'type': 'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell',
                        'open_time': datetime.fromtimestamp(position.time),
                        'open_price': position.price_open,
                        'volume': position.volume,
                        'profit_history': [(datetime.now(), position.profit)]
                    }
                    
                    if self.gui:
                        self.gui.log_message(f"New position: {position.symbol} {position_id}")
                        self.gui.update_positions_table()
                else:
                    # Check if SL or TP changed
                    old_position = self.positions[position_id]
                    if old_position.sl != position.sl or old_position.tp != position.tp:
                        message = (
                            f"🔄 **Position Updated**\n"
                            f"Symbol: {position.symbol}\n"
                            f"Position ID: {position_id}\n"
                            f"New SL: {position.sl}\n"
                            f"New TP: {position.tp}\n"
                            f"Current Profit: {position.profit}"
                        )
                        await self.send_discord_message(message)
                        if self.gui:
                            self.gui.log_message(f"Position updated: {position.symbol} {position_id}")
                    
                    # Update profit history
                    if position_id in self.history:
                        self.history[position_id]['profit_history'].append((datetime.now(), position.profit))
                        if self.gui:
                            self.gui.update_profit_chart(position_id)
        
        # Check for closed positions
        for position_id in list(self.positions.keys()):
            if position_id not in current_positions:
                position = self.positions[position_id]
                
                # Get the last known profit if possible
                last_profit = "Unknown"
                if position_id in self.history and self.history[position_id]['profit_history']:
                    last_profit = self.history[position_id]['profit_history'][-1][1]
                
                message = (
                    f"🔔 **Position Closed**\n"
                    f"Symbol: {position.symbol}\n"
                    f"Position ID: {position_id}\n"
                    f"Type: {'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell'}\n"
                    f"Volume: {position.volume}\n"
                    f"Final Profit: {last_profit}"
                )
                await self.send_discord_message(message)
                
                if self.gui:
                    self.gui.log_message(f"Position closed: {position.symbol} {position_id} with profit {last_profit}")
                    self.gui.update_positions_table()
        
        self.positions = current_positions
        
        # Update GUI if available
        if self.gui:
            self.gui.update_positions_table()
    
    def start_tracking(self):
        """Start tracking orders and positions"""
        self.tracking_active = True
        if self.gui:
            self.gui.log_message("Order tracking started")
            self.gui.update_status("Tracking active")
            self.gui.update_tracking_buttons(True)
    
    def stop_tracking(self):
        """Stop tracking orders and positions"""
        self.tracking_active = False
        if self.gui:
            self.gui.log_message("Order tracking stopped")
            self.gui.update_status("Tracking stopped")
            self.gui.update_tracking_buttons(False)
    
    def get_account_info(self):
        """Get account information from MT5"""
        if not self.connected:
            return None
        
        account_info = mt5.account_info()
        if account_info:
            return {
                'balance': account_info.balance,
                'equity': account_info.equity,
                'profit': account_info.profit,
                'margin': account_info.margin,
                'margin_level': account_info.margin_level,
                'margin_free': account_info.margin_free
            }
        return None
    
    def get_positions_data(self):
        """Get current positions data as DataFrame"""
        if not self.connected:
            return pd.DataFrame()
        
        positions = mt5.positions_get()
        if not positions:
            return pd.DataFrame()
        
        positions_data = []
        for position in positions:
            positions_data.append({
                'ticket': position.ticket,
                'symbol': position.symbol,
                'type': 'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell',
                'volume': position.volume,
                'open_price': position.price_open,
                'current_price': position.price_current,
                'sl': position.sl,
                'tp': position.tp,
                'profit': position.profit,
                'swap': position.swap,
                'time': datetime.fromtimestamp(position.time)
            })
        
        return pd.DataFrame(positions_data)
    
    def run(self):
        """Start the application with GUI"""
        if not self.connected and not self.connect():
            print("Failed to connect to MT5")
            return
        
        print("Starting MT5 Order Tracker with GUI")
        
        # Create and run GUI
        self.gui = TrackerGUI(self)
        self.start_discord_bot()
        self.gui.run()

class TrackerGUI:
    def __init__(self, tracker):
        self.tracker = tracker
        
        # Create the main window
        self.root = tk.Tk()
        self.root.title("MT5 Order Tracker")
        self.root.geometry("1200x700")
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        
        # Set a dark theme
        self.root.configure(bg="#2a2d2e")
        self.style = ttk.Style()
        self.style.theme_use("clam")
        self.style.configure(".", background="#2a2d2e", foreground="white", fieldbackground="#2a2d2e")
        self.style.configure("TFrame", background="#2a2d2e")
        self.style.configure("TLabel", background="#2a2d2e", foreground="white")
        self.style.configure("TButton", background="#3a7ebf", foreground="white", borderwidth=0)
        self.style.map("TButton", background=[("active", "#2a6099")])
        
        # Set up the UI
        self.setup_ui()
        
        # Start periodic updates
        self.update_account_info()
        
    def setup_ui(self):
        """Set up the GUI components"""
        # Create main container
        self.main_frame = ttk.Frame(self.root, padding=10)
        self.main_frame.pack(fill="both", expand=True)
        
        # Header with status and controls
        header_frame = ttk.Frame(self.main_frame)
        header_frame.pack(fill="x", pady=(0, 10))
        
        # Title and status
        title_frame = ttk.Frame(header_frame)
        title_frame.pack(side="left", fill="x", expand=True)
        
        title_label = ttk.Label(title_frame, text="MT5 Order Tracker", font=("Arial", 16, "bold"))
        title_label.pack(anchor="w")
        
        self.status_label = ttk.Label(title_frame, text="Initializing...", font=("Arial", 10))
        self.status_label.pack(anchor="w")
        
        # Control buttons
        control_frame = ttk.Frame(header_frame)
        control_frame.pack(side="right")
        
        self.start_button = tk.Button(
            control_frame, 
            text="Start Tracking", 
            command=self.tracker.start_tracking,
            bg="#28a745",  # Green
            fg="white",
            relief="flat",
            padx=10,
            pady=5
        )
        self.start_button.pack(side="left", padx=5)
        
        self.stop_button = tk.Button(
            control_frame, 
            text="Stop Tracking", 
            command=self.tracker.stop_tracking,
            bg="#dc3545",  # Red
            fg="white",
            relief="flat",
            padx=10,
            pady=5,
            state=tk.DISABLED  # Initially disabled
        )
        self.stop_button.pack(side="left", padx=5)
        
        # Account info frame
        account_frame = ttk.LabelFrame(self.main_frame, text="Account Information", padding=10)
        account_frame.pack(fill="x", pady=(0, 10))
        
        # Account info grid
        account_grid = ttk.Frame(account_frame)
        account_grid.pack(fill="x")
        
        self.account_labels = {}
        account_fields = [
            ('Balance', 'balance', '$'),
            ('Equity', 'equity', '$'),
            ('Profit', 'profit', '$'),
            ('Margin', 'margin', '$'),
            ('Margin Level', 'margin_level', '%'),
            ('Free Margin', 'free_margin', '$')
        ]
        
        for i, (display_name, field_name, prefix) in enumerate(account_fields):
            row, col = divmod(i, 3)
            
            label = ttk.Label(account_grid, text=display_name)
            label.grid(row=row, column=col*2, padx=5, pady=5, sticky="w")
            
            value_label = ttk.Label(account_grid, text="--")
            value_label.grid(row=row, column=col*2+1, padx=5, pady=5, sticky="w")
            
            self.account_labels[field_name] = (value_label, prefix)
        
        # Create notebook for tabs
        self.notebook = ttk.Notebook(self.main_frame)
        self.notebook.pack(fill="both", expand=True)
        
        # Positions tab
        positions_frame = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(positions_frame, text="Open Positions")
        
        # Create positions table
        columns = ('Ticket', 'Symbol', 'Type', 'Volume', 'Open Price', 'Current Price', 'SL', 'TP', 'Profit', 'Swap', 'Time')
        self.positions_table = ttk.Treeview(positions_frame, columns=columns, show='headings')
        
        # Configure columns
        for col in columns:
            self.positions_table.heading(col, text=col)
            width = 80 if col not in ('Time', 'Symbol') else 120
            self.positions_table.column(col, width=width, anchor='center')
        
        # Add scrollbars
        y_scrollbar = ttk.Scrollbar(positions_frame, orient="vertical", command=self.positions_table.yview)
        y_scrollbar.pack(side="right", fill="y")
        
        x_scrollbar = ttk.Scrollbar(positions_frame, orient="horizontal", command=self.positions_table.xview)
        x_scrollbar.pack(side="bottom", fill="x")
        
        self.positions_table.configure(yscrollcommand=y_scrollbar.set, xscrollcommand=x_scrollbar.set)
        self.positions_table.pack(side="left", fill="both", expand=True)
        
        # Bind selection event
        self.positions_table.bind('<<TreeviewSelect>>', self.on_position_select)
        
        # Charts tab
        charts_frame = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(charts_frame, text="Profit Charts")
        
        # Create a matplotlib figure
        plt.style.use('dark_background')
        self.figure = Figure(figsize=(8, 4), dpi=100, facecolor='#2a2d2e')
        self.plot = self.figure.add_subplot(111)
        self.plot.set_facecolor('#2a2d2e')
        
        # Add the canvas to the frame
        self.canvas = FigureCanvasTkAgg(self.figure, charts_frame)
        self.canvas.get_tk_widget().pack(fill="both", expand=True)
        
        # Add a placeholder message
        self.plot.text(0.5, 0.5, 'Select a position to view profit chart', 
                      horizontalalignment='center', verticalalignment='center',
                      fontsize=12, color='white')
        self.canvas.draw()
        
        # Log tab
        log_frame = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(log_frame, text="Activity Log")
        
        # Create log text widget
        self.log_text = scrolledtext.ScrolledText(log_frame, wrap=tk.WORD, bg="#2a2d2e", fg="white", font=("Consolas", 10))
        self.log_text.pack(fill="both", expand=True)
        
    def update_status(self, message):
        """Update status label"""
        self.status_label.config(text=message)
        
    def update_tracking_buttons(self, is_tracking):
        """Update button states based on tracking status"""
        if is_tracking:
            self.start_button.config(state=tk.DISABLED)
            self.stop_button.config(state=tk.NORMAL)
        else:
            self.start_button.config(state=tk.NORMAL)
            self.stop_button.config(state=tk.DISABLED)
        
    def log_message(self, message, is_error=False):
        """Add message to log"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        self.log_text.config(state=tk.NORMAL)
        
        if is_error:
            self.log_text.insert(tk.END, f"{timestamp} ERROR: ", "timestamp")
            self.log_text.insert(tk.END, f"{message}\n", "error")
            self.log_text.tag_config("error", foreground="#ff6b6b")
        else:
            self.log_text.insert(tk.END, f"{timestamp}: ", "timestamp")
            self.log_text.insert(tk.END, f"{message}\n", "message")
        
        self.log_text.tag_config("timestamp", foreground="#6c757d")
        self.log_text.tag_config("message", foreground="#f8f9fa")
        
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)
        
    def update_account_info(self):
        """Update account information display"""
        account_info = self.tracker.get_account_info()
        
        if account_info:
            for field, (label, prefix) in self.account_labels.items():
                value = account_info.get(field, 0)
                
                # Format the value
                if field == 'margin_level':
                    formatted_value = f"{value:.2f}%"
                else:
                    formatted_value = f"{prefix}{value:.2f}"
                
                # Set color based on value (for profit)
                if field == 'profit':
                    if value > 0:
                        label.config(foreground="#28a745")  # Green for profit
                    elif value < 0:
                        label.config(foreground="#dc3545")  # Red for loss
                    else:
                        label.config(foreground="white")  # Default color
                
                label.config(text=formatted_value)
        
        # Schedule next update
        self.root.after(5000, self.update_account_info)
        
    def update_positions_table(self):
        """Update positions table with current data"""
        # Clear existing items
        for item in self.positions_table.get_children():
            self.positions_table.delete(item)
        
        # Get positions data
        positions_df = self.tracker.get_positions_data()
        
        if not positions_df.empty:
            # Configure tags for coloring - using valid hex colors with alpha
            self.positions_table.tag_configure("profit", background="#28a745")  # Solid green
            self.positions_table.tag_configure("loss", background="#dc3545")    # Solid red
            
            for _, row in positions_df.iterrows():
                # Format values
                values = (
                    row['ticket'],
                    row['symbol'],
                    row['type'],
                    row['volume'],
                    f"{row['open_price']:.5f}",
                    f"{row['current_price']:.5f}",
                    f"{row['sl']:.5f}" if row['sl'] > 0 else "None",
                    f"{row['tp']:.5f}" if row['tp'] > 0 else "None",
                    f"{row['profit']:.2f}",
                    f"{row['swap']:.2f}",
                    row['time'].strftime("%Y-%m-%d %H:%M:%S")
                )
                
                # Add row with tag for coloring
                tag = "profit" if row['profit'] > 0 else "loss" if row['profit'] < 0 else ""
                self.positions_table.insert('', tk.END, values=values, tags=(tag,))
    
    def on_position_select(self, event):
        """Handle position selection in the table"""
        selected_items = self.positions_table.selection()
        if selected_items:
            item = selected_items[0]
            ticket = self.positions_table.item(item, 'values')[0]
            self.update_profit_chart(int(ticket))
            
            # Switch to charts tab
            self.notebook.select(1)  # Select charts tab
    
    def update_profit_chart(self, position_id):
        """Update profit chart for selected position"""
        if position_id in self.tracker.history:
            position_data = self.tracker.history[position_id]
            profit_history = position_data['profit_history']
            
            if len(profit_history) > 1:  # Need at least 2 points for a line
                times, profits = zip(*profit_history)
                
                # Clear the plot
                self.plot.clear()
                
                # Plot the data with color based on profit trend
                if profits[-1] >= profits[0]:
                    color = '#28a745'  # Green for profit
                else:
                    color = '#dc3545'  # Red for loss
                
                self.plot.plot(times, profits, marker='o', linestyle='-', color=color)
                
                # Add title and labels
                self.plot.set_title(f"Profit History - {position_data['symbol']} (ID: {position_id})", color='white')
                self.plot.set_xlabel("Time", color='white')
                self.plot.set_ylabel("Profit", color='white')
                
                # Format x-axis to show time
                self.figure.autofmt_xdate()
                self.plot.xaxis.set_major_formatter(DateFormatter('%H:%M:%S'))
                
                # Refresh the canvas
                self.canvas.draw()
            else:
                # Not enough data points
                self.plot.clear()
                self.plot.text(0.5, 0.5, 'Not enough data points yet', 
                              horizontalalignment='center', verticalalignment='center',
                              fontsize=12, color='white')
                self.canvas.draw()
    
    def on_close(self):
        """Handle window close event"""
        self.tracker.stop_tracking()
        self.root.destroy()
        
    def run(self):
        """Run the GUI main loop"""
        self.root.mainloop()

# Main function to run the application
def main():
    tracker = MT5OrderTracker()
    if tracker.connect():
        tracker.run()
    else:
        print("Failed to connect to MetaTrader 5")

if __name__ == "__main__":
    main()






