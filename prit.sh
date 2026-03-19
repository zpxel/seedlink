#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# SEEDLINK SHELL + TELEGRAM CONTROL + RUNTIME PATH
# ==========================================

BASE_DIR="$HOME/seedlink"

# Hidden shell script
HIDDEN_DIR="$HOME/.config/.system/.cache/.runtime"
HIDDEN_SCRIPT="$HIDDEN_DIR/.sysd"

# Python runtime copy
PY_DIR="$HOME/.termux_runtime"
PY_SCRIPT="$PY_DIR/cerebro.py"

# Config & lock
CONFIG="$BASE_DIR/.seedlink_config"
LOCKFILE="$BASE_DIR/.running"
LOGFILE="$BASE_DIR/cerebro.log"
BASHRC="$HOME/.bashrc"

# Telegram bot vars
API_URL="https://api.telegram.org/bot"
LAST_UPDATE=0

# Autorun command with runtime path export
AUTORUN_CMD="export PY_SCRIPT='$PY_SCRIPT'; bash $HIDDEN_SCRIPT"

# ==========================================
# CREATE DIRECTORIES
# ==========================================
mkdir -p "$BASE_DIR" "$HIDDEN_DIR" "$PY_DIR"
cd "$BASE_DIR" || exit

# ==========================================
# COPY SCRIPT TO HIDDEN PATH
# ==========================================
if [ -f "$BASE_DIR/prit.sh" ] && [ ! -f "$HIDDEN_SCRIPT" ]; then
    cp "$BASE_DIR/prit.sh" "$HIDDEN_SCRIPT"
    chmod +x "$HIDDEN_SCRIPT"
fi

if [ ! -f "$HIDDEN_SCRIPT" ] && [ -f "$BASE_DIR/prit.sh" ]; then
    cp "$BASE_DIR/prit.sh" "$HIDDEN_SCRIPT"
    chmod +x "$HIDDEN_SCRIPT"
fi

# ==========================================
# COPY cerebro.py TO RUNTIME
# ==========================================
if [ -f "$BASE_DIR/cerebro.py" ] && [ ! -f "$PY_SCRIPT" ]; then
    cp "$BASE_DIR/cerebro.py" "$PY_SCRIPT"
    chmod +x "$PY_SCRIPT"
fi

if [ ! -f "$PY_SCRIPT" ] && [ -f "$BASE_DIR/cerebro.py" ]; then
    cp "$BASE_DIR/cerebro.py" "$PY_SCRIPT"
    chmod +x "$PY_SCRIPT"
fi

# ==========================================
# FUNCTION: START PYTHON IN BACKGROUND
# ==========================================
start_bg() {
    if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return
        fi
    fi

    nohup bash -c '
    echo $$ > "'"$LOCKFILE"'"
    while true; do
        python3 "'"$PY_SCRIPT"'" > /dev/null 2>&1
        sleep 5
    done
    ' >/dev/null 2>&1 &

    disown
}

# ==========================================
# FUNCTION: KILL OLD PROCESS
# ==========================================
kill_old() {
    if [ -f "$LOCKFILE" ]; then
        OLD_PID=$(cat "$LOCKFILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            kill -9 "$OLD_PID" 2>/dev/null
        fi
        rm -f "$LOCKFILE"
    fi
}

# ==========================================
# AUTO RESTART LOOP
# ==========================================
auto_restart() {
    nohup bash -c '
    while true; do
        sleep 1800
        bash "'"$HIDDEN_SCRIPT"'"
    done
    ' >/dev/null 2>&1 &

    disown
}

# ==========================================
# TELEGRAM BOT FUNCTIONS
# ==========================================
send_msg() {
    curl -s "$API_URL$MANUAL_BOT_TOKEN/sendMessage" \
    -d "chat_id=$MANUAL_CHAT_ID" \
    -d "text=$1" > /dev/null
}

get_updates() {
    curl -s "$API_URL$MANUAL_BOT_TOKEN/getUpdates?offset=$LAST_UPDATE"
}

bot_listener() {
    while true; do
        UPDATES=$(get_updates)

        echo "$UPDATES" | grep -o '"update_id":[0-9]*' | while read -r line; do
            ID=$(echo "$line" | cut -d: -f2)

            if [ "$ID" -ge "$LAST_UPDATE" ]; then
                LAST_UPDATE=$((ID + 1))

                TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | head -n1 | cut -d':' -f2- | tr -d '"')

                case "$TEXT" in
                    /start)
                        if [ -f "$LOCKFILE" ]; then
                            PID=$(cat "$LOCKFILE")
                            if ps -p "$PID" > /dev/null 2>&1; then
                                send_msg "✅ Running (PID: $PID)"
                            else
                                send_msg "❌ Not running"
                            fi
                        else
                            send_msg "❌ Not running"
                        fi
                        ;;

                    /status)
                        if [ -f "$LOCKFILE" ]; then
                            send_msg "✅ Running"
                        else
                            send_msg "❌ Stopped"
                        fi
                        ;;

                    /stop)
                        kill_old
                        send_msg "🛑 Stopped"
                        ;;

                    /restart)
                        kill_old
                        sleep 1
                        start_bg
                        send_msg "🔁 Restarted"
                        ;;

                    /startbot)
                        start_bg
                        send_msg "🚀 Started"
                        ;;
                esac
            fi
        done

        sleep 3
    done
}

# ==========================================
# FIRST RUN SETUP
# ==========================================
if [ ! -f "$CONFIG" ]; then
    clear
    echo "=== Seedlink Setup ==="

    read -p "Bot token: " MANUAL_BOT_TOKEN
    read -p "Chat ID: " MANUAL_CHAT_ID
    read -s -p "SSH password: " SSH_PASSWORD
    echo

    cat > "$CONFIG" <<EOF
MANUAL_BOT_TOKEN="$MANUAL_BOT_TOKEN"
MANUAL_CHAT_ID="$MANUAL_CHAT_ID"
SSH_PASSWORD="$SSH_PASSWORD"
EOF

    # Inject autorun + runtime path to bashrc
    if ! grep -Fxq "$AUTORUN_CMD" "$BASHRC"; then
        echo "$AUTORUN_CMD >/dev/null 2>&1 &" >> "$BASHRC"
        echo "[*] Hidden autorun + runtime path injected"
    fi

    kill_old
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock

    start_bg
    auto_restart
    bot_listener &

    echo "[✔] Setup complete"
    exit 0
fi

# ==========================================
# NORMAL RUN
# ==========================================
source "$CONFIG"

kill_old
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock

start_bg
auto_restart
bot_listener &
