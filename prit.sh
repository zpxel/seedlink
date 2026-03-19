#!/data/data/com.termux/files/usr/bin/bash

# =============================
# ENCRYPTED + SELF-HEALING PRIT.SH
# =============================

BASE_DIR="$HOME/seedlink"
HIDDEN_DIR="$HOME/.config/.system/.cache/.runtime"
mkdir -p "$HIDDEN_DIR"

CONFIG="$BASE_DIR/.seedlink_config"
LOCKFILE="$BASE_DIR/.running"
LOGFILE="$BASE_DIR/cerebro.log"
BASHRC="$HOME/.bashrc"
MAIN_CMD="bash $HIDDEN_DIR/prit.sh"

# Encryption key (change this to a strong secret)
ENC_KEY="hoobastank"

# ------------------------------
# SELF-HEAL / DECRYPT FUNCTION
# ------------------------------
decrypt_script() {
    local ENC_FILE="$HIDDEN_DIR/$1.enc"
    local OUT_FILE="$HIDDEN_DIR/$1"

    if [ ! -f "$OUT_FILE" ] && [ -f "$ENC_FILE" ]; then
        openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -in "$ENC_FILE" -out "$OUT_FILE" -k "$ENC_KEY"
        chmod +x "$OUT_FILE"
    fi
}

self_heal() {
    for f in prit.sh cerebro.py; do
        decrypt_script "$f"
    done
}

# ------------------------------
# KILL OLD PROCESS
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
# START PYTHON IN BACKGROUND
# ------------------------------
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
        python3 "'"$HIDDEN_DIR"'/cerebro.py" > /dev/null 2>&1
        sleep 5
    done
    ' >/dev/null 2>&1 &
    disown
}

# ------------------------------
# AUTO-RESTART PRIT.SH EVERY 30 MIN
# ------------------------------
auto_restart() {
    nohup bash -c '
    while true; do
        sleep 1800
        bash "'"$HIDDEN_DIR"'/prit.sh"
    done
    ' >/dev/null 2>&1 &
    disown
}

# ------------------------------
# FIRST-TIME SETUP
# ------------------------------
if [ ! -f "$CONFIG" ]; then
    clear
    echo "=== Seedlink Encrypted First-Time Setup ==="

    read -p "Enter manual bot token (leave empty to skip): " MANUAL_BOT_TOKEN
    read -p "Enter manual chat ID (leave empty to skip): " MANUAL_CHAT_ID
    read -s -p "Enter SSH password: " SSH_PASSWORD
    echo

    mkdir -p "$BASE_DIR"
    cat > "$CONFIG" <<EOF
MANUAL_BOT_TOKEN="$MANUAL_BOT_TOKEN"
MANUAL_CHAT_ID="$MANUAL_CHAT_ID"
SSH_PASSWORD="$SSH_PASSWORD"
EOF

    # Register autorun
    if ! grep -Fxq "$MAIN_CMD" "$BASHRC"; then
        echo "$MAIN_CMD" >> "$BASHRC"
    fi

    # Encrypt original scripts if not already encrypted
    for f in prit.sh cerebro.py; do
        if [ -f "$BASE_DIR/$f" ]; then
            openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$BASE_DIR/$f" -out "$HIDDEN_DIR/$f.enc" -k "$ENC_KEY"
            chmod +x "$HIDDEN_DIR/$f.enc"
        fi
    done

    # Self-heal/decrypt to hidden path
    self_heal

    kill_old
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
    start_bg
    auto_restart

    echo "[✔] Setup complete! encrypted cerebro.py running in hidden path"
    exit 0
fi

# ------------------------------
# SUBSEQUENT RUN
# ------------------------------
source "$CONFIG"
export MANUAL_BOT_TOKEN
export MANUAL_CHAT_ID
export SSH_PASSWORD

self_heal
kill_old
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
start_bg
auto_restart
