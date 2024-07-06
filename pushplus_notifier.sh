#!/bin/bash

# 设置新的工作目录
WORK_DIR="/root/TrafficCop"
mkdir -p "$WORK_DIR"

# 更新文件路径
CONFIG_FILE="$WORK_DIR/pushplus_notifier_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
LAST_NOTIFICATION_FILE="$WORK_DIR/last_pushplus_notification"
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
      echo "已更新 crontab，添加了正确的定时任务。"
    fi

    # 添加每日报告的 cron 任务
    local daily_report_minute=$(echo "$DAILY_REPORT_TIME" | cut -d':' -f2)
    local daily_report_hour=$(echo "$DAILY_REPORT_TIME" | cut -d':' -f1)
    local daily_report_entry="$daily_report_minute $daily_report_hour * * * $SCRIPT_PATH -daily"

    if ! crontab -l | grep -q "$daily_report_entry"; then
        (crontab -l 2>/dev/null; echo "$daily_report_entry") | crontab -
        echo "已添加每日报告的 cron 任务。"
    else
        echo "每日报告的 cron 任务已存在，无需添加。"
    fi
}

# 生成每日报告
generate_daily_report() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始生成每日报告..."| tee -a "$CRON_LOG"
    
    # 获取今天的日期
    local today=$(date '+%Y-%m-%d')
    
    # 从日志文件中提取今天的流量数据
    local traffic_data=$(grep "$today" "$LOG_FILE" | grep "当前流量")
    
    if [ -z "$traffic_data" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 今天没有流量数据。"| tee -a "$CRON_LOG"
        return
    fi
    
    # 提取最新的流量数据
    local latest_data=$(echo "$traffic_data" | tail -n 1)
    local current_traffic=$(echo "$latest_data" | grep -oP '当前流量：\K[0-9.]+[KMGT]?')
    local daily_limit=$(echo "$latest_data" | grep -oP '每日限制：\K[0-9.]+[KMGT]?')
    
    # 计算流量使用百分比
    local usage_percent=$(echo "$latest_data" | grep -oP '使用百分比：\K[0-9.]+')
    
    # 生成报告内容
    local title="📊 [${MACHINE_NAME}]每日流量报告"
    local content="<h2>每日流量报告</h2>
    <p>日期：$today</p>
    <p>当前流量：$current_traffic</p>
    <p>每日限制：$daily_limit</p>
    <p>使用百分比：$usage_percent%</p>"
    
    # 发送报告
    if send_pushplus_notification "$title" "$content"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告已成功发送。"| tee -a "$CRON_LOG"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 发送每日报告失败。"| tee -a "$CRON_LOG"
    fi
}

# 主任务
main() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 进入主任务" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 参数数量: $#" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 所有参数: $@" >> "$CRON_LOG"
    
    check_running
    
    if [[ "$*" == *"-cron"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到-cron参数, 进入cron模式" >> "$CRON_LOG"
        if read_config; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 成功读取配置文件" >> "$CRON_LOG"
            # 继续执行其他操作
            check_and_notify "false"
            
            # 检查是否需要发送每日报告
            current_time=$(TZ='Asia/Shanghai' date +%H:%M)
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前时间: $current_time, 设定的报告时间: $DAILY_REPORT_TIME" >> "$CRON_LOG"
            if [ "$current_time" == "$DAILY_REPORT_TIME" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 时间匹配，准备发送每日报告" >> "$CRON_LOG"
                if generate_daily_report; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送成功" >> "$CRON_LOG"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送失败" >> "$CRON_LOG"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前时间与报告时间不匹配，不发送报告" >> "$CRON_LOG"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 配置文件不存在或不完整，跳过检查" >> "$CRON_LOG"
            exit 1
        fi
    else
        # 交互模式
        echo "进入交互模式"
        if ! read_config; then
            echo "需要进行初始化配置。"
            configure
        fi
        
        setup_cron
        
        # 直接显示当前配置摘要
        echo "当前配置摘要："
        echo "机器名称: $MACHINE_NAME"
        echo "每日报告时间: $DAILY_REPORT_TIME"
        echo "PushPlus Token: ${PUSHPLUS_TOKEN:0:10}..." # 只显示前10个字符
        
        echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'd' 手动发送每日报告，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置，按 'h' 修改每日报告时间。"
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
                    d|D)
                        generate_daily_report
                        ;;
                    r|R)
                        read_config
                        echo "配置已重新加载。"
                        ;;
                    t|T)
                        send_pushplus_notification "🔔 测试通知" "这是一条测试消息，如果您收到此消息，则 PushPlus 通知功能正常。"
                        ;;
                    m|M)
                        configure
                        ;;
                    h|H)
                        echo "请输入新的每日报告时间 (HH:MM): "
                        read -r new_time
                        if [[ $new_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                            sed -i "s/DAILY_REPORT_TIME=.*/DAILY_REPORT_TIME=$new_time/" "$CONFIG_FILE"
                            echo "每日报告时间已更新为 $new_time"
                        else
                            echo "无效的时间格式。未更改。"
                        fi
                        ;;
                    *)
                        echo "无效的输入: $input"
                        ;;
                esac

                echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'd' 手动发送每日报告，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置，按 'h' 修改每日报告时间。"
            fi
        done
    fi
}

# 运行主程序
main "$@"
