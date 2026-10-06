#!/bin/bash

# 设置新的工作目录
WORK_DIR="/root/TrafficCop"
mkdir -p "$WORK_DIR"

# 导入端口流量辅助函数
if [ -f "$WORK_DIR/port_traffic_helper.sh" ]; then
    source "$WORK_DIR/port_traffic_helper.sh"
fi

# 导入日志读取辅助函数（log_recent_match：轮转后仍能取到「最近一条」记录）
if [ -f "$WORK_DIR/log_helper.sh" ]; then
    source "$WORK_DIR/log_helper.sh"
fi

# 更新文件路径
CONFIG_FILE="$WORK_DIR/pushplus_notifier_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
LAST_NOTIFICATION_FILE="$WORK_DIR/last_pushplus_notification"
SCRIPT_PATH="$WORK_DIR/pushplus_notifier.sh"
CRON_LOG="$WORK_DIR/pushplus_notifier_cron.log"

# 切换到工作目录
cd "$WORK_DIR" || exit 1

# 设置时区为上海（东八区）
# 注意：部分精简系统缺少 /usr/share/zoneinfo，TZ='Asia/Shanghai' 会静默失效退回 UTC。
# 必须显式用 TZ= 探测，确保每日报告时间按北京时间触发。
if [ "$(TZ='Asia/Shanghai' date '+%z' 2>/dev/null)" = "+0800" ]; then
    export TZ='Asia/Shanghai'
else
    export TZ='CST-8'
fi

echo "----------------------------------------------"| tee -a "$CRON_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') : 版本号：1.9"  

# 检查是否有同名的 crontab 正在执行:
check_running() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查是否有其他实例运行" >> "$CRON_LOG"
    if pidof -x "$(basename "$0")" -o $$ > /dev/null; then
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
    echo "======================================"
    echo "   修改 PushPlus 通知配置"
    echo "======================================"
    echo ""
    echo "提示：按 Enter 保留当前配置，输入新值则更新配置"
    echo ""
    
    local new_token new_machine_name new_daily_report_time

    # PushPlus Token
    if [ -n "$PUSHPLUS_TOKEN" ]; then
        local token_display="${PUSHPLUS_TOKEN:0:10}...${PUSHPLUS_TOKEN: -4}"
        echo "请输入PushPlus Token [当前: $token_display]: "
    else
        echo "请输入PushPlus Token: "
    fi
    read -r new_token
    if [[ -z "$new_token" ]] && [[ -n "$PUSHPLUS_TOKEN" ]]; then
        new_token="$PUSHPLUS_TOKEN"
        echo "  → 保留原配置"
    fi
    while [[ -z "$new_token" ]]; do
        echo "PushPlus Token 不能为空。请重新输入: "
        read -r new_token
    done

    # 机器名称
    if [ -n "$MACHINE_NAME" ]; then
        echo "请输入机器名称 [当前: $MACHINE_NAME]: "
    else
        echo "请输入机器名称: "
    fi
    read -r new_machine_name
    if [[ -z "$new_machine_name" ]] && [[ -n "$MACHINE_NAME" ]]; then
        new_machine_name="$MACHINE_NAME"
        echo "  → 保留原配置"
    fi
    while [[ -z "$new_machine_name" ]]; do
        echo "机器名称不能为空。请重新输入: "
        read -r new_machine_name
    done

    # 每日报告时间
    if [ -n "$DAILY_REPORT_TIME" ]; then
        echo "请输入每日报告时间 [当前: $DAILY_REPORT_TIME，格式 HH:MM]: "
    else
        echo "请输入每日报告时间 (时区已经固定为东八区，输入格式为 HH:MM，例如 01:00): "
    fi
    read -r new_daily_report_time
    if [[ -z "$new_daily_report_time" ]] && [[ -n "$DAILY_REPORT_TIME" ]]; then
        new_daily_report_time="$DAILY_REPORT_TIME"
        echo "  → 保留原配置"
    fi
    while [[ ! $new_daily_report_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        echo "时间格式不正确。请重新输入 (HH:MM): "
        read -r new_daily_report_time
    done

    # 更新配置文件（使用引号防止空格等特殊字符问题）
    PUSHPLUS_TOKEN="$new_token"
    MACHINE_NAME="$new_machine_name"
    DAILY_REPORT_TIME="$new_daily_report_time"
    
    write_config
    
    echo ""
    echo "======================================"
    echo "配置已更新成功！"
    echo "======================================"
    echo ""
    read_config
      
}


# 发送限速警告
send_throttle_warning() {
    local title="⚠️ [${MACHINE_NAME}]限速警告"
    local content="流量已达到限制，已启动 TC 模式限速。"
    
    # 添加端口流量摘要
    if command -v get_port_traffic_summary &> /dev/null; then
        local port_summary=$(get_port_traffic_summary 3)
        if [ -n "$port_summary" ]; then
            content="${content}<br><br>${port_summary}"
        fi
    fi
    
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

# 发送限速解除通知
send_throttle_lifted() {
    local title="✅ [${MACHINE_NAME}]限速解除"
    local content="流量已恢复正常，所有限制已清除。"
    
    # 添加端口流量摘要
    if command -v get_port_traffic_summary &> /dev/null; then
        local port_summary=$(get_port_traffic_summary 3)
        if [ -n "$port_summary" ]; then
            content="${content}<br><br>${port_summary}"
        fi
    fi
    
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

# 发送新周期开始通知
send_new_cycle_notification() {
    local title="🔄 [${MACHINE_NAME}]新周期开始"
    local content="新的流量统计周期已开始，之前的限速（如果有）已自动解除。"
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

# 发送关机警告
send_shutdown_warning() {
    local title="🚨 [${MACHINE_NAME}]关机警告"
    local content="流量已达到严重限制，系统将在 1 分钟后关机！"
    
    # 添加端口流量摘要
    if command -v get_port_traffic_summary &> /dev/null; then
        local port_summary=$(get_port_traffic_summary 3)
        if [ -n "$port_summary" ]; then
            content="${content}<br><br>${port_summary}"
        fi
    fi
    
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

test_pushplus_notification() {
    local title="🔔 [${MACHINE_NAME}]测试消息"
    local content="这是一条测试消息。如果您收到这条消息，说明PushPlus通知功能正常工作。"
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
        echo "✅ [${MACHINE_NAME}]测试消息已成功发送，请检查您的PushPlus。"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : PushPlus 通知发送失败. 响应: $response"| tee -a "$CRON_LOG"
        echo "❌ [${MACHINE_NAME}]发送测试消息失败。请检查您的PUSHPLUS_TOKEN设置。"
        return 1
    fi
}


check_and_notify() { 
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查流量状态..."| tee -a "$CRON_LOG"
    
    local current_status="未知"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local relevant_log=""
    
    # 从后往前读取日志文件，找到第一个包含相关信息的行。
    # 用 log_recent_match 而非裸 tac：日志轮转后目标行可能在归档文件里，
    # 且只在尾部窗口内扫描，避免在 100MB+ 的日志上每分钟全扫一遍。
    relevant_log=$(log_recent_match "流量超出限制|使用 TC 模式限速|新的流量周期开始|流量正常，清除所有限制")
    
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
    local pushplus_entries=$(echo "$current_crontab" | grep "pushplus_notifier.sh")
    local correct_entries_count=$(echo "$pushplus_entries" | grep -F "$correct_entry" | wc -l)

    if [ "$correct_entries_count" -eq 1 ]; then
        echo "正确的 crontab 项已存在且数量正确，无需修改。"
    else
        # 删除所有包含 pushplus_notifier.sh 的条目
        new_crontab=$(echo "$current_crontab" | grep -v "pushplus_notifier.sh")
        
        # 添加正确的条目
        new_crontab="${new_crontab}
$correct_entry"

        # 更新 crontab
        echo "$new_crontab" | crontab -

        echo "已更新 crontab。删除了所有旧的 pushplus_notifier.sh 条目，并添加了新的条目。"
    fi

    # 显示当前的 crontab 内容
    echo "当前的 crontab 内容："
    crontab -l
}

# 每日报告
daily_report() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始生成每日报告"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : DAILY_REPORT_TIME=$DAILY_REPORT_TIME"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : PUSHPLUS_TOKEN=${PUSHPLUS_TOKEN:0:5}..."| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 日志文件路径: $LOG_FILE"| tee -a "$CRON_LOG"

    # 反向读取日志文件，查找第一个同时包含"当前使用流量"和"限制流量"的行。
    # 同样走 log_recent_match，理由见该函数注释（轮转可见性 + 限定扫描窗口）。
    local usage_line=$(log_recent_match "当前使用流量:.*限制流量:")

    if [[ -z "$usage_line" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法在日志中找到同时包含当前使用流量和限制流量的行"| tee -a "$CRON_LOG"
        return 1
    fi

    local current_usage=$(echo "$usage_line" | grep -oP '当前使用流量:\s*\K[0-9.]+ [GBMKgbmk]+')
    local limit=$(echo "$usage_line" | grep -oP '限制流量:\s*\K[0-9.]+ [GBMKgbmk]+')

    if [[ -z "$current_usage" || -z "$limit" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法从行中提取流量信息"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 问题行: $usage_line"| tee -a "$CRON_LOG"
        return 1
    fi

    local title="[${MACHINE_NAME}]每日流量报告"
    local content="📊 每日流量报告<br><br>🖥️ <b>机器总流量</b><br>当前使用：$current_usage<br>流量限制：$limit"
    
    # 检查是否有端口流量配置
    local ports_config_file="$WORK_DIR/ports_traffic_config.json"
    local view_script="$WORK_DIR/view_port_traffic.sh"
    
    if [ -f "$ports_config_file" ]; then
        local port_count=$(jq -r '.ports | length' "$ports_config_file" 2>/dev/null || echo "0")
        
        if [ "$port_count" -gt 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到 $port_count 个端口流量配置，添加端口信息"| tee -a "$CRON_LOG"
            
            # 如果有 view_port_traffic.sh 脚本，使用它
            if [ -f "$view_script" ]; then
                local port_data=$(bash "$view_script" --json 2>/dev/null)
            else
                local port_data=""
            fi
            
            if [ -n "$port_data" ] && echo "$port_data" | jq -e '.ports' >/dev/null 2>&1; then
                local actual_port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null || echo "0")
                
                if [ "$actual_port_count" -gt 0 ]; then
                    content="${content}<br><br>🔌 <b>端口流量详情</b><br>"
                    
                    # 遍历每个端口
                    local i=0
                    while [ $i -lt $actual_port_count ]; do
                        local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                        local port_desc=$(echo "$port_data" | jq -r ".ports[$i].description" 2>/dev/null)
                        local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                        local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                        
                        if [ -n "$port" ] && [ "$port" != "null" ] && [ "$port_usage" != "null" ]; then
                            # 格式化流量显示（保留2位小数）
                            local port_usage_formatted=$(printf "%.2f" "$port_usage" 2>/dev/null || echo "$port_usage")
                            local port_limit_formatted=$(printf "%.2f" "$port_limit" 2>/dev/null || echo "$port_limit")
                            
                            # 计算使用百分比
                            local port_percentage=0
                            if [ -n "$port_limit" ] && [ "$port_limit" != "null" ] && (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                                port_percentage=$(printf "%.2f" $(echo "scale=2; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0"))
                            fi
                            
                            # 根据使用率选择表情
                            local status_icon="✅"
                            if (( $(echo "$port_percentage >= 90" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🔴"
                            elif (( $(echo "$port_percentage >= 75" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🟡"
                            fi
                            
                            content="${content}${status_icon} 端口 ${port} (${port_desc})：${port_usage_formatted}GB / ${port_limit_formatted}GB (${port_percentage}%)<br>"
                        fi
                        
                        i=$((i + 1))
                    done
                    
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 已添加 $actual_port_count 个端口的流量信息"| tee -a "$CRON_LOG"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : JSON数据中没有端口信息"| tee -a "$CRON_LOG"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法获取有效的端口流量JSON数据"| tee -a "$CRON_LOG"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 没有配置端口流量监控"| tee -a "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 端口配置文件不存在"| tee -a "$CRON_LOG"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 准备发送消息: $content"| tee -a "$CRON_LOG"

    local url="http://www.pushplus.plus/send"
    local response

    echo "$(date '+%Y-%m-%d %H:%M:%S') : 尝试发送PushPlus消息"| tee -a "$CRON_LOG"

    response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{
            \"token\": \"$PUSHPLUS_TOKEN\",
            \"title\": \"$title\",
            \"content\": \"$content\"
        }")

    if echo "$response" | grep -q '"code":200'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送成功"| tee -a "$CRON_LOG"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送失败. 响应: $response"| tee -a "$CRON_LOG"
        return 1
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
            check_and_notify
            
            # 检查是否需要发送每日报告
            current_time=$(date +%H:%M)
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前时间: $current_time, 设定的报告时间: $DAILY_REPORT_TIME" >> "$CRON_LOG"
            if [ "$current_time" == "$DAILY_REPORT_TIME" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 时间匹配，准备发送每日报告" >> "$CRON_LOG"
                if daily_report; then
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
             initial_config
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
        daily_report
        ;;
    r|R)
        read_config
        echo "配置已重新加载。"
        ;;
    t|T)
        test_pushplus_notification
        ;;
    m|M)
        initial_config
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
