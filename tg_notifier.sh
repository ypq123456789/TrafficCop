#!/bin/bash

CONFIG_FILE="/root/tg_notifier_config.txt"
LOG_FILE="/root/traffic_monitor.log"
LAST_NOTIFICATION_FILE="/tmp/last_traffic_notification"
SCRIPT_PATH=$(readlink -f "\$0")
CRON_LOG="/root/tg_notifier_cron.log"

# 读取配置
read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# 写入配置
write_config() {
    cat > "$CONFIG_FILE" << EOF
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
EOF
    echo "配置已保存到 $CONFIG_FILE"
}

# 初始配置
initial_config() {
    echo "请输入Telegram Bot Token:"
    read -r TG_BOT_TOKEN
    echo "请输入Telegram Chat ID:"
    read -r TG_CHAT_ID
    write_config
}

send_telegram_message() {
    local message="\$1"
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown"
}

check_and_notify() {
    if grep -q "使用 TC 模式限速" "$LOG_FILE"; then
        if [ ! -f "$LAST_NOTIFICATION_FILE" ] || [ "$(cat "$LAST_NOTIFICATION_FILE")" != "限速" ]; then
            local message="⚠️ 流量警告：已达到限制，已启动 TC 模式限速。"
            send_telegram_message "$message"
            echo "限速" > "$LAST_NOTIFICATION_FILE"
        fi
    elif grep -q "系统将在 1 分钟后关机" "$LOG_FILE"; then
        if [ ! -f "$LAST_NOTIFICATION_FILE" ] || [ "$(cat "$LAST_NOTIFICATION_FILE")" != "关机" ]; then
            local message="🚨 严重警告：流量已严重超出限制，系统将在 1 分钟后关机。"
            send_telegram_message "$message"
            echo "关机" > "$LAST_NOTIFICATION_FILE"
        fi
    elif grep -q "流量正常，清除所有限制" "$LOG_FILE"; then
        if [ -f "$LAST_NOTIFICATION_FILE" ]; then
            local message="✅ 通知：流量已恢复正常水平，所有限制已清除。"
            send_telegram_message "$message"
            rm "$LAST_NOTIFICATION_FILE"
        fi
    fi
}

add_to_crontab() {
    (crontab -l 2>/dev/null; echo "* * * * * $SCRIPT_PATH >> $CRON_LOG 2>&1") | crontab -
    echo "脚本已添加到 crontab，将每分钟执行一次。"
}

# 主函数
main() {
    if ! read_config; then
        echo "未找到配置文件，开始初始化配置..."
        initial_config
    else
        echo "配置已加载。如需修改配置，请在5秒内按任意键，否则将使用现有配置继续运行。"
        if read -t 5 -n 1; then
            echo "开始修改配置..."
            initial_config
        else
            echo "使用现有配置继续运行。"
        fi
    fi

    if ! crontab -l | grep -q "$SCRIPT_PATH"; then
        add_to_crontab
    fi

    echo "$(date): 开始检查日志文件..." >> "$CRON_LOG"
    check_and_notify
    echo "$(date): 检查完成。" >> "$CRON_LOG"
}

# 执行主函数
main
