#!/bin/bash


# 新增：启用调试模式
set -x

CONFIG_FILE="/root/tg_notifier_config.txt"
LOG_FILE="/root/traffic_monitor.log"
LAST_NOTIFICATION_FILE="/tmp/last_traffic_notification"
SCRIPT_PATH="/root/tg_notifier.sh"
CRON_LOG="/root/tg_notifier_cron.log"

echo "版本号：3.6"  

# 检查是否有同名的 crontab 正在执行:
check_running() {
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查是否有其他实例运行" >> "$CRON_LOG"
    if pidof -x "$(basename "\$0")" -o $$ > /dev/null; then
        # 新增：添加日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 另一个脚本实例正在运行，退出脚本" >> "$CRON_LOG"
        echo "另一个脚本实例正在运行，退出脚本"
        exit 1
    fi
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 没有其他实例运行，继续执行" >> "$CRON_LOG"
}

# 清除旧的通知状态文件
clear_notification_state() {
    if [ -f "$LAST_NOTIFICATION_FILE" ]; then
        rm "$LAST_NOTIFICATION_FILE"
        echo "清除了旧的通知状态文件。"
    fi
}

# 函数：获取非空输入
get_valid_input() {
    local prompt="${1:-"请输入："}"
    local input=""
    while true; do
        read -p "${prompt}" input
        if [[ -n "${input}" ]]; then
            echo "${input}"
            return
        else
            echo "输入不能为空，请重新输入。"
        fi
    done
}


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
DAILY_REPORT="$DAILY_REPORT"
EOF
    echo "配置已保存到 $CONFIG_FILE"
}

# 初始配置
initial_config() {
    local new_token new_chat_id

    echo "请输入Telegram Bot Token: "
    read -r new_token
    while [[ -z "$new_token" ]]; do
        echo "Bot Token 不能为空。请重新输入: "
        read -r new_token
    done

    echo "请输入Telegram Chat ID: "
    read -r new_chat_id
    while [[ -z "$new_chat_id" ]]; do
        echo "Chat ID 不能为空。请重新输入: "
        read -r new_chat_id
    done

    # 更新配置文件
    echo "BOT_TOKEN=$new_token" > "$CONFIG_FILE"
    echo "CHAT_ID=$new_chat_id" >> "$CONFIG_FILE"

    echo "配置已更新。"
    read_config
}



send_telegram_message() {
    local message="${1:-"默认消息"}"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown"
}

test_telegram_notification() {
    local message="🔔 这是一条测试消息。如果您收到这条消息，说明Telegram通知功能正常工作。"
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "disable_notification=true")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ 测试消息已成功发送，请检查您的Telegram。"
    else
        echo "❌ 发送测试消息失败。请检查您的BOT_TOKEN和CHAT_ID设置。"
    fi
}

check_and_notify() {
    local interactive=\$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查流量状态..." >> "$CRON_LOG"
    if [ "$interactive" = "true" ]; then
        echo "开始检查流量状态..."
    fi
    
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 读取最新的日志内容" >> "$CRON_LOG"
    local latest_log=$(tail -n 50 "$LOG_FILE")
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 最新日志内容长度: $(echo "$latest_log" | wc -l) 行" >> "$CRON_LOG"
    
    local status_found=false
    local latest_log=$(tail -n 50 "$LOG_FILE")

    if echo "$latest_log" | grep -q "使用 TC 模式限速"; then
        local message="⚠️ 限速警告：流量已达到限制，已启动 TC 模式限速。"
        if [ ! -f "$LAST_NOTIFICATION_FILE" ] || [ "$(cat "$LAST_NOTIFICATION_FILE")" != "限速" ]; then
            send_telegram_message "$message"
            echo "限速" > "$LAST_NOTIFICATION_FILE"
        fi
        echo "$message"
        status_found=true
    elif echo "$latest_log" | grep -q "系统将在 1 分钟后关机"; then
        local message="🚨 关机警告：流量已达到限制，系统将在 1 分钟后关机！"
        if [ ! -f "$LAST_NOTIFICATION_FILE" ] || [ "$(cat "$LAST_NOTIFICATION_FILE")" != "关机" ]; then
            send_telegram_message "$message"
            echo "关机" > "$LAST_NOTIFICATION_FILE"
        fi
        echo "$message"
        status_found=true
    elif echo "$latest_log" | grep -q "流量正常，清除所有限制"; then
        local message="✅ 流量正常：流量目前处于正常水平，所有限制已清除。"
        if [ -f "$LAST_NOTIFICATION_FILE" ]; then
            send_telegram_message "$message"
            rm "$LAST_NOTIFICATION_FILE"
        fi
        echo "$message"
        status_found=true
    fi
    
    if [ "$status_found" = "false" ]; then
        echo "✅ 流量状态正常：未触发任何限制或警告。"
    fi
    
     echo "$(date '+%Y-%m-%d %H:%M:%S') : 流量检查完成。" >> "$CRON_LOG"
}

# 设置定时任务
setup_cron() {
    if ! crontab -l | grep -q "$SCRIPT_PATH cron"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_PATH cron") | crontab -
        echo "已添加 crontab 项。"
    else
        echo "crontab 项已存在，无需添加。"
    fi
}



daily_report() {
    local current_usage=$(grep "当前流量" "$LOG_FILE" | tail -n 1 | cut -d ' ' -f 4)
    local limit=$(grep "流量限制" "$LOG_FILE" | tail -n 1 | cut -d ' ' -f 4)
    local message="📊 每日流量报告\n当前使用流量：$current_usage\n流量限制：$limit"
    send_telegram_message "$message"
}

# 主任务
main() {
    check_running
    if [ "\$1" = "cron" ]; then
        # cron 模式
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 进入cron模式"
        # 修改：将所有输出重定向到日志文件
        {
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始执行 cron 模式"
            read_config
            check_and_notify false
            echo "$(date '+%Y-%m-%d %H:%M:%S') : cron 模式执行完毕"
        } >> "$CRON_LOG" 2>&1
        exit 0
    else
        # 交互模式
        echo "进入交互模式"
        clear_notification_state
        if ! read_config; then
            echo "配置文件不存在，请进行初始配置。"
            initial_config
        fi

        setup_cron

        echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置。"
        while true; do
            read -n 1 -t 1 input
            if [ -n "$input" ]; then
                echo
                case $input in
                    q|Q) 
                        echo "退出脚本。"
                        exit 0
                        ;;
                    c|C)
                        check_and_notify true
                        ;;
                    r|R)
                        read_config
                        echo "配置已重新加载。"
                        ;;
                    t|T)
                        test_telegram_notification
                        ;;
                    m|M)
                        initial_config
                        ;;
                    *)
                        echo "无效的输入: $input"
                        ;;
                esac
                echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置。"
            fi
        done
    fi
}


# 执行主函数
main "$@"
