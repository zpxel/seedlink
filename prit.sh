#!/data/data/com.termux/files/usr/bin/bash

BASE_DIR="$HOME/seedlink"
CONFIG="$BASE_DIR/.seedlink_config"
LOCKFILE="$BASE_DIR/.running"
LOGFILE="$BASE_DIR/cerebro.log"
BASHRC="$HOME/.bashrc"
AUTORUN_CMD="bash $BASE_DIR/prit.sh"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# ------------------------------
# FUNCTION: START PYTHON IN BACKGROUND
# ------------------------------
start_bg() {
    # Only start if not already running
    if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return
        fi
    fi

    echo " "
    nohup bash -c '
    echo $$ > "'"$LOCKFILE"'"
    while true; do
        python3 "'"$BASE_DIR"'/cerebro.py" > /dev/null 2>&1
        sleep 5
    done
    ' >/dev/null 2>&1 &
    disown
}

# ------------------------------
# FUNCTION: KILL OLD PROCESS
# ------------------------------
kill_old() {
    if [ -f "$LOCKFILE" ]; then
        OLD_PID=$(cat "$LOCKFILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            kill -9 "$OLD_PID" 2>/dev/null
        fi
        rm -f "$LOCKFILE"
    fi
}

# ------------------------------
# FUNCTION: AUTO-RESTART SHELL EVERY 30MIN
# ------------------------------
auto_restart() {
    nohup bash -c '
    while true; do
        sleep 1800
        bash "'"$BASE_DIR"'/prit.sh"
    done
    ' >/dev/null 2>&1 &
    disown
}

# ------------------------------
# FIRST-TIME RUN SETUP
# ------------------------------
if [ ! -f "$CONFIG" ]; then
    clear
    echo "=== Seedlink First Time Setup ==="

    read -p "Enter manual bot token (leave empty to skip): " MANUAL_BOT_TOKEN
    read -p "Enter manual chat ID (leave empty to skip): " MANUAL_CHAT_ID
    read -s -p "Enter SSH password: " SSH_PASSWORD
    echo

    # Save config
    cat > "$CONFIG" <<EOF
MANUAL_BOT_TOKEN="$MANUAL_BOT_TOKEN"
MANUAL_CHAT_ID="$MANUAL_CHAT_ID"
SSH_PASSWORD="$SSH_PASSWORD"
EOF

    # Register autorun in .bashrc (once)
    if ! grep -Fxq "$AUTORUN_CMD" "$BASHRC"; then
        echo "$AUTORUN_CMD" >> "$BASHRC"
        echo "[*] Added auto-run to ~/.bashrc"
    fi

    # Start Python immediately
    kill_old
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
    start_bg
    auto_restart

    echo "[✔] Setup complete! cerebro.py running in background"
    echo "[✔] Logs: $LOGFILE"
    echo "[✔] Auto-run will trigger on next Termux open"
    exit 0
fi

# ------------------------------
# SUBSEQUENT RUNS (AUTO)
# ------------------------------

# Load saved config silently
source "$CONFIG"
export MANUAL_BOT_TOKEN
export MANUAL_CHAT_ID
export SSH_PASSWORD

# Kill old process (ensure only one)
kill_old

# Wake lock
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock

# Start Python in background
start_bg
auto_restart
