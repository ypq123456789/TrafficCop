#!/bin/bash

# 设置新的工作目录
WORK_DIR="/root/TrafficCop"
mkdir -p "$WORK_DIR"

# 更新文件路径
CONFIG_FILE="$WORK_DIR/pushplus_notifier_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
LAST_NOTIFICATION_FILE="$WORK_DIR/last_traffic_notification"
SCRIPT_PATH="$WORK_DIR/pushplus_notifier.sh"
CRON_LOG="$WORK_DIR/pushplus_notifier_cron.log"

# 切换到工作目录
cd "$WORK_DIR" || exit 1

# 设置时区为上海（东八区）
export TZ='Asia/Shanghai'

echo "----------------------------------------------"| tee -a "$CRON_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') : 版本号：1.0"  

# 检查是否有同名的 crontab 正在执行:
check_running() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查是否有其他实例运行" >> "$CRON_LOG"
    if pidof -x "$(basename "\$0")" -o $$ > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 另一个脚本实例正在运行，退出脚本" >> "$CRON_LOG"
        echo "另一个脚本实例正在运行，退出脚本"
        exit 1
    fi
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
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo "配置文件不存在或为空，需要进行初始化配置。"
        return 1
    fi

    # 读取配置文件
    source "$CONFIG_FILE"

    # 检查必要的配置项是否都存在
    if [ -z "$PUSHPLUS_TOKEN" ] || [ -z "$MACHINE_NAME" ] || [ -z "$DAILY_REPORT_TIME" ]; then
        echo "配置文件不完整，需要重新进行配置。"
        return 1
    fi

    return 0
}

# 写入配置
write_config() {
    cat > "$CONFIG_FILE" << EOF
PUSHPLUS_TOKEN="$PUSHPLUS_TOKEN"
DAILY_REPORT_TIME="$DAILY_REPORT_TIME"
MACHINE_NAME="$MACHINE_NAME"
EOF
    echo "配置已保存到 $CONFIG_FILE"
}

# 初始配置
initial_config() {
    echo "开始初始化配置..."
    local new_token

    echo "请输入PushPlus Token: "
    read -r new_token
    while [[ -z "$new_token" ]]; do
        echo "PushPlus Token 不能为空。请重新输入: "
        read -r new_token
    done

    echo "请输入机器名称: "
    read -r new_machine_name
    while [[ -z "$new_machine_name" ]]; do
        echo "机器名称不能为空。请重新输入: "
        read -r new_machine_name
    done

    echo "请输入每日报告时间 (时区已经固定为东八区，输入格式为 HH:MM，例如 01:00): "
    read -r new_daily_report_time
    while [[ ! $new_daily_report_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        echo "时间格式不正确。请重新输入 (HH:MM): "
        read -r new_daily_report_time
    done

    # 更新配置文件
    echo "PUSHPLUS_TOKEN=$new_token" > "$CONFIG_FILE"
    echo "MACHINE_NAME=$new_machine_name" >> "$CONFIG_FILE"
    echo "DAILY_REPORT_TIME=$new_daily_report_time" >> "$CONFIG_FILE"

    echo "配置已更新。"
    read_config
}

# 发送 PushPlus 通知
send_pushplus_notification() {
    local title="\$1"
    local content="\$2"
    local url="http://www.pushplus.plus/send"
    local response

    response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{
            \"token\": \"$PUSHPLUS_TOKEN\",
            \"title\": \"$title\",
            \"content\": \"$content\",
            \"template\": \"html\"
        }")

    if echo "$response" | grep -q '"code":200'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : PushPlus 通知发送成功"| tee -a "$CRON_LOG"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : PushPlus 通知发送失败. 响应: $response"| tee -a "$CRON_LOG"
        return 1
    fi
}

# 发送限速警告
send_throttle_warning() {
    local title="⚠️ [${MACHINE_NAME}]限速警告"
    local content="流量已达到限制，已启动 TC 模式限速。"
    send_pushplus_notification "$title" "$content"
}

# 发送限速解除通知
send_throttle_lifted() {
    local title="✅ [${MACHINE_NAME}]限速解除"
    local content="流量已恢复正常，所有限制已清除。"
    send_pushplus_notification "$title" "$content"
}

# 发送新周期开始通知
send_new_cycle_notification() {
    local title="🔄 [${MACHINE_NAME}]新周期开始"
    local content="新的流量统计周期已开始，之前的限速（如果有）已自动解除。"
    send_pushplus_notification "$title" "$content"
}

# 发送关机警告
send_shutdown_warning() {
    local title="🚨 [${MACHINE_NAME}]关机警告"
    local content="流量已达到严重限制，系统将在 1 分钟后关机！"
    send_pushplus_notification "$title" "$content"
}

test_pushplus_notification() {
    local title="🔔 [${MACHINE_NAME}]测试消息"
    local content="这是一条测试消息。如果您收到这条消息，说明PushPlus通知功能正常工作。"
    if send_pushplus_notification "$title" "$content"; then
        echo "✅ [${MACHINE_NAME}]测试消息已成功发送，请检查您的PushPlus。"
    else
        echo "❌ [${MACHINE_NAME}]发送测试消息失败。请检查您的PUSHPLUS_TOKEN设置。"
    fi
}

check_and_notify() { 
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查流量状态..."| tee -a "$CRON_LOG"
    
    local current_status="未知"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local relevant_log=""
    
    # 从后往前读取日志文件，找到第一个包含相关信息的行
    relevant_log=$(tac "$LOG_FILE" | grep -m 1 -E "流量超出限制|使用 TC 模式限速|新的流量周期开始|流量正常，清除所有限制")
    
    # 记录相关的日志内容
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 相关的日志内容: $relevant_log"| tee -a "$CRON_LOG"
    
    # 确定当前状态
    if echo "$relevant_log" | grep -q "流量超出限制，系统将在 1 分钟后关机"; then
        current_status="关机"
    elif echo "$relevant_log" | grep -q "流量超出限制"; then
        current_status="限速"
    elif echo "$relevant_log" | grep -q "新的流量周期开始，重置限制"; then
        current_status="新周期"
    elif echo "$relevant_log" | grep -q "流量正常，清除所有限制"; then
        current_status="正常"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前检测到的状态: $current_status"| tee -a "$CRON_LOG"
    
    local last_status=""
    if [ -f "$LAST_NOTIFICATION_FILE" ]; then
        last_status=$(tail -n 1 "$LAST_NOTIFICATION_FILE" | cut -d' ' -f3-)
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 上次记录的状态: $last_status"| tee -a "$CRON_LOG"
    
    # 根据状态调用相应的通知函数
    if [ "$current_status" = "限速" ] && [ "$last_status" != "限速" ]; then
        send_throttle_warning
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_throttle_warning"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "正常" ] && [ "$last_status" = "限速" ]; then
        send_throttle_lifted
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_throttle_lifted"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "新周期" ]; then
        send_new_cycle_notification
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_new_cycle_notification"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "关机" ]; then
        send_shutdown_warning
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_shutdown_warning"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "未知" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法识别当前状态，不发送通知"| tee -a "$CRON_LOG"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无需发送通知"| tee -a "$CRON_LOG"
    fi
    
    # 追加新状态到状态文件
    echo "$current_time $current_status" >> "$LAST_NOTIFICATION_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 已追加新状态到状态文件"| tee -a "$CRON_LOG"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 流量检查完成。"| tee -a "$CRON_LOG"
}

# 设置定时任务
setup_cron() {
    local correct_entry="* * * * * $SCRIPT_PATH -cron"
    local current_crontab=$(crontab -l 2>/dev/null)
    local pushplus_notifier_entries=$(echo "$current_crontab" | grep "pushplus_notifier.sh")
    local correct_entries_count=$(echo "$pushplus_notifier_entries" | grep -F "$correct_entry" | wc -l)

    if [ "$correct_entries_count" -eq 1 ]; then
        echo "正确的 crontab 项已存在且只有一个，无需修改。"
    else
        # 删除所有包含 pushplus_notifier.sh 的条目
        new_crontab=$(echo "$current_crontab" | grep -v "pushplus_notifier.sh")
        
        # 添加一个正确的条目
        new_crontab="${new_crontab}
$correct_entry"

        # 更新 crontab
        echo "$new_crontab" | crontab -

        echo "已更新 
