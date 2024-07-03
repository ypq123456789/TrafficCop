#!/bin/bash


# 新增：启用调试模式
# set -x

CONFIG_FILE="/root/tg_notifier_config.txt"
LOG_FILE="/root/traffic_monitor.log"
LAST_NOTIFICATION_FILE="/tmp/last_traffic_notification"
SCRIPT_PATH="/root/tg_notifier.sh"
CRON_LOG="/root/tg_notifier_cron.log"
echo "----------------------------------------------"| tee -a "$CRON_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') : 版本号：5.4"  

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 尝试发送 Telegram 消息: $message" >> "$CRON_LOG"
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown")
    echo "$(date '+%Y-%m-%d %H:%M:%S') : Telegram API 响应: $response" >> "$CRON_LOG"
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 消息发送成功" >> "$CRON_LOG"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 消息发送失败" >> "$CRON_LOG"
        return 1
    fi
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

# 检查和通知
check_and_notify() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查流量状态..." >> "$CRON_LOG"
    
    local latest_log=$(tail -n 200 "$LOG_FILE")
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 最新日志内容长度: $(echo "$latest_log" | wc -l) 行" >> "$CRON_LOG"
    
    local current_status=""
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 确定当前状态
    if echo "$latest_log" | grep -q "使用 TC 模式限速"; then
        current_status="限速"
    elif echo "$latest_log" | grep -q "系统将在 1 分钟后关机"; then
        current_status="关机"
    elif echo "$latest_log" | grep -q "流量正常，清除所有限制"; then
        current_status="正常"
    elif echo "$latest_log" | grep -q "新的流量周期"; then
        current_status="新周期"
    else
        current_status="未知"
    fi
    
    local last_status=""
    if [ -f "$LAST_NOTIFICATION_FILE" ]; then
        last_status=$(tail -n 1 "$LAST_NOTIFICATION_FILE" | cut -d' ' -f3-)
    fi
    
    if [ ! -f "$LAST_NOTIFICATION_FILE" ] || [ "$current_status" != "$last_status" ]; then
        echo "$current_time $current_status" >> "$LAST_NOTIFICATION_FILE"

        local message=""
        if [ "$current_status" = "限速" ] && ([ -z "$last_status" ] || [ "$last_status" = "正常" ]); then
            message="⚠️ 限速警告：流量已达到限制，已启动 TC 模式限速。"
        elif [ "$current_status" = "正常" ] && [ "$last_status" = "限速" ]; then
            message="✅ 限速解除：流量已恢复正常，所有限制已清除。"
        elif [ "$current_status" = "新周期" ]; then
            message="🔄 新周期开始：新的流量统计周期已开始，之前的限速（如果有）已自动解除。"
        elif [ "$current_status" = "关机" ]; then
            message="🚨 关机警告：流量已达到严重限制，系统将在 1 分钟后关机！"
        elif [ "$current_status" = "未知" ]; then
            message="❓ 未知状态：无法确定当前流量状态。"
        fi
        
   if [ -n "$message" ]; then
    if send_telegram_message "$message"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 通知发送成功: $message" >> "$CRON_LOG"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 发送通知失败: $message" >> "$CRON_LOG"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 状态从 '$last_status' 变为 '$current_status'，无需发送通知" >> "$CRON_LOG"
fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 状态未变化，保持为 '$current_status'" >> "$CRON_LOG"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 流量检查完成。" >> "$CRON_LOG"
}

# 设置定时任务
setup_cron() {
    local correct_entry="* * * * * $SCRIPT_PATH -cron"
    local current_crontab=$(crontab -l 2>/dev/null)
    local tg_notifier_entries=$(echo "$current_crontab" | grep "tg_notifier.sh")
    local correct_entries_count=$(echo "$tg_notifier_entries" | grep -F "$correct_entry" | wc -l)

    if [ "$correct_entries_count" -eq 1 ]; then
        echo "正确的 crontab 项已存在且只有一个，无需修改。"
    else
        # 删除所有包含 tg_notifier.sh 的条目
        new_crontab=$(echo "$current_crontab" | grep -v "tg_notifier.sh")
        
        # 添加一个正确的条目
        new_crontab="${new_crontab}
$correct_entry"

        # 更新 crontab
        echo "$new_crontab" | crontab -

        echo "已更新 crontab。删除了所有旧的 tg_notifier.sh 条目，并添加了一个每分钟执行的条目。"
    fi

    # 显示当前的 crontab 内容
    echo "当前的 crontab 内容："
    crontab -l
}




# 每日报告
daily_report() {
    local current_usage=$(grep "当前流量" "$LOG_FILE" | tail -n 1 | cut -d ' ' -f 4)
    local limit=$(grep "流量限制" "$LOG_FILE" | tail -n 1 | cut -d ' ' -f 4)
    local message="📊 每日流量报告\n当前使用流量：$current_usage\n流量限制：$limit"
    send_telegram_message "$message"
}

# 主任务
main() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 进入主任务" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 参数数量: $#" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 所有参数: $@" >> "$CRON_LOG"
    
    check_running
    
    if [[ "$*" == *"-cron"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到-cron参数, 进入cron模式" >> "$CRON_LOG"
        # cron 模式代码
       if read_config; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 成功读取配置文件" >> "$CRON_LOG"
    check_and_notify "false"
    
    # 检查是否需要发送每日报告
    current_time=$(date +%H:%M)
    if [ "$current_time" == "00:00" ]; then
        if daily_report; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送成功" >> "$CRON_LOG"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送失败" >> "$CRON_LOG"
        fi
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 配置文件不存在或无法读取，跳过检查" >> "$CRON_LOG"
fi

    else
        # 交互模式
        echo "进入交互模式"
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
                        check_and_notify "true"
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
echo "----------------------------------------------"| tee -a "$CRON_LOG"
