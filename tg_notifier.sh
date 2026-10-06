#!/bin/bash

# 设置新的工作目录
WORK_DIR="/root/TrafficCop"
mkdir -p "$WORK_DIR"

# 导入端口流量辅助函数
if [ -f "$WORK_DIR/port_traffic_helper.sh" ]; then
    source "$WORK_DIR/port_traffic_helper.sh"
fi

# 更新文件路径
CONFIG_FILE="$WORK_DIR/tg_notifier_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
LAST_NOTIFICATION_FILE="$WORK_DIR/last_traffic_notification"
SCRIPT_PATH="$WORK_DIR/tg_notifier.sh"
CRON_LOG="$WORK_DIR/tg_notifier_cron.log"

# 文件迁移函数
migrate_files() {
    # 迁移配置文件
    if [ -f "/root/tg_notifier_config.txt" ]; then
        mv "/root/tg_notifier_config.txt" "$CONFIG_FILE"
    fi

    # 迁移日志文件
    if [ -f "/root/traffic_monitor.log" ]; then
        mv "/root/traffic_monitor.log" "$LOG_FILE"
    fi

    # 迁移最后通知文件
    if [ -f "/tmp/last_traffic_notification" ]; then
        mv "/tmp/last_traffic_notification" "$LAST_NOTIFICATION_FILE"
    fi

    # 迁移脚本文件
    if [ -f "/root/tg_notifier.sh" ]; then
        mv "/root/tg_notifier.sh" "$SCRIPT_PATH"
    fi

    # 迁移 cron 日志文件
    if [ -f "/root/tg_notifier_cron.log" ]; then
        mv "/root/tg_notifier_cron.log" "$CRON_LOG"
    fi

    # 更新 crontab 中的脚本路径
    if crontab -l | grep -q "/root/tg_notifier.sh"; then
        crontab -l | sed "s|/root/tg_notifier.sh|$SCRIPT_PATH|g" | crontab -
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') 文件已迁移到新的工作目录: $WORK_DIR" | tee -a "$CRON_LOG"
}

# 在脚本开始时调用迁移函数
migrate_files

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

# 端口流量数据缓存文件
PORT_DATA_CACHE="/tmp/port_traffic_cache.json"

echo "----------------------------------------------"| tee -a "$CRON_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') : 版本号：9.6"  

# 检查是否有同名的 crontab 正在执行:
check_running() {
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查是否有其他实例运行" >> "$CRON_LOG"
    if pidof -x "$(basename "$0")" -o $$ > /dev/null; then
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

# 保存端口流量数据到缓存（带历史记录和详细调试）
save_port_traffic_data() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 开始执行 save_port_traffic_data"| tee -a "$CRON_LOG"
    
    if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 找到 view_port_traffic.sh 文件"| tee -a "$CRON_LOG"
        
        # 详细记录执行环境
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] WORK_DIR=$WORK_DIR"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] PWD=$(pwd)"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 执行命令: cd $WORK_DIR && PATH='/usr/sbin:/usr/bin:/sbin:/bin:$PATH' bash view_port_traffic.sh --json"| tee -a "$CRON_LOG"
        
        local port_data
        port_data=$(cd "$WORK_DIR" && PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH" bash view_port_traffic.sh --json 2>/dev/null)
        local exit_code=$?
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] view_port_traffic.sh 退出码: $exit_code"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 原始输出长度: ${#port_data} 字符"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 原始输出前200字符: $(echo "$port_data" | head -c 200)"| tee -a "$CRON_LOG"
        
        local timestamp=$(date '+%Y-%m-%d_%H:%M:%S')
        local caller_info=""
        
        # 识别调用来源
        if [[ "${BASH_SOURCE[1]}" == *"tg_notifier.sh"* ]]; then
            local line_num=$(caller 0 | cut -d' ' -f1)
            caller_info="_line${line_num}"
        fi
        
        if [ -n "$port_data" ]; then
            # 创建带时间戳的历史缓存文件
            local history_cache="/tmp/port_traffic_cache_${timestamp}${caller_info}.json"
            local tmpfile="${history_cache}.tmp.$$"
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 尝试解析JSON并添加元数据"| tee -a "$CRON_LOG"
            
            # 先写到临时文件并附加元数据，再验证JSON结构
            echo "$port_data" | jq ". + {\"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\", \"data_source\": \"manual\", \"caller\": \"${caller_info}\", \"exit_code\": $exit_code}" > "$tmpfile" 2>/dev/null || true
            
            if [ -s "$tmpfile" ] && jq -e '.ports' "$tmpfile" >/dev/null 2>&1; then
                mv -f "$tmpfile" "$history_cache"
                chmod 644 "$history_cache" 2>/dev/null || true
                
                # 创建/更新最新缓存的符号链接
                ln -sf "$history_cache" "$PORT_DATA_CACHE" 2>/dev/null || cp "$history_cache" "$PORT_DATA_CACHE"
                
                # 记录详细日志，包括数据预览
                local usage_summary=$(echo "$port_data" | jq -r '.ports[] | "\(.port):\(.usage)GB"' 2>/dev/null | tr '\n' ' ' || echo "无法解析端口数据")
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 端口流量数据已保存到缓存 $history_cache"| tee -a "$CRON_LOG"
                echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 缓存数据摘要: $usage_summary"| tee -a "$CRON_LOG"
                
                # 清理超过24小时的历史缓存文件
                find /tmp -name "port_traffic_cache_*" -type f -mtime +1 -delete 2>/dev/null || true
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 生成缓存失败，临时文件无效或JSON解析失败"| tee -a "$CRON_LOG"
                echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 临时文件大小: $(wc -c "$tmpfile" 2>/dev/null || echo "文件不存在")"| tee -a "$CRON_LOG"
                echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 原始数据: $port_data"| tee -a "$CRON_LOG"
                rm -f "$tmpfile" 2>/dev/null || true
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : view_port_traffic.sh返回空数据"| tee -a "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : view_port_traffic.sh 文件不存在: $WORK_DIR/view_port_traffic.sh"| tee -a "$CRON_LOG"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] save_port_traffic_data 执行完成"| tee -a "$CRON_LOG"
}

# 从缓存加载端口流量数据
load_port_traffic_data() {
    if [ -f "$PORT_DATA_CACHE" ]; then
        local cache_age=$(( $(date +%s) - $(stat -c %Y "$PORT_DATA_CACHE" 2>/dev/null || echo 0) ))
        local cache_age_minutes=$(( cache_age / 60 ))
        
        if [ $cache_age_minutes -le 60 ]; then
            # 先校验缓存文件是否为有效JSON并包含ports字段
            if [ ! -s "$PORT_DATA_CACHE" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 缓存文件存在但为空，删除并返回"| tee -a "$CRON_LOG"
                rm -f "$PORT_DATA_CACHE" 2>/dev/null || true
                return
            fi
            if ! jq -e '.ports' "$PORT_DATA_CACHE" >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 缓存文件不是有效JSON或缺少ports字段，删除并返回"| tee -a "$CRON_LOG"
                rm -f "$PORT_DATA_CACHE" 2>/dev/null || true
                return
            fi
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 读取端口流量缓存，文件年龄: ${cache_age_minutes}分钟"| tee -a "$CRON_LOG" >&2
            cat "$PORT_DATA_CACHE" 2>/dev/null
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 端口流量缓存已过期(${cache_age_minutes}分钟)，删除缓存文件"| tee -a "$CRON_LOG"
            rm -f "$PORT_DATA_CACHE"
        fi
    fi
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
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] || [ -z "$MACHINE_NAME" ] || [ -z "$DAILY_REPORT_TIME" ]; then
        echo "配置文件不完整，需要重新进行配置。"
        return 1
    fi

    return 0
}

# 写入配置
write_config() {
    cat > "$CONFIG_FILE" << EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DAILY_REPORT_TIME="$DAILY_REPORT_TIME"
MACHINE_NAME="$MACHINE_NAME"
EOF
    echo "配置已保存到 $CONFIG_FILE"
}


# 初始配置
initial_config() {
    echo "======================================"
    echo "   修改 Telegram 通知配置"
    echo "======================================"
    echo ""
    echo "提示：按 Enter 保留当前配置，输入新值则更新配置"
    echo ""
    
    local new_token new_chat_id new_machine_name new_daily_report_time

    # Bot Token
    if [ -n "$BOT_TOKEN" ]; then
        # 隐藏部分Token显示
        local token_display="${BOT_TOKEN:0:10}...${BOT_TOKEN: -4}"
        echo "请输入Telegram Bot Token [当前: $token_display]: "
    else
        echo "请输入Telegram Bot Token: "
    fi
    read -r new_token
    # 如果输入为空且有原配置，保留原配置
    if [[ -z "$new_token" ]] && [[ -n "$BOT_TOKEN" ]]; then
        new_token="$BOT_TOKEN"
        echo "  → 保留原配置"
    fi
    # 如果还是空（首次配置），要求必须输入
    while [[ -z "$new_token" ]]; do
        echo "Bot Token 不能为空。请重新输入: "
        read -r new_token
    done

    # Chat ID
    if [ -n "$CHAT_ID" ]; then
        echo "请输入Telegram Chat ID [当前: $CHAT_ID]: "
    else
        echo "请输入Telegram Chat ID: "
    fi
    read -r new_chat_id
    if [[ -z "$new_chat_id" ]] && [[ -n "$CHAT_ID" ]]; then
        new_chat_id="$CHAT_ID"
        echo "  → 保留原配置"
    fi
    while [[ -z "$new_chat_id" ]]; do
        echo "Chat ID 不能为空。请重新输入: "
        read -r new_chat_id
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
    BOT_TOKEN="$new_token"
    CHAT_ID="$new_chat_id"
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
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="⚠️ [${MACHINE_NAME}]限速警告：流量已达到限制，已启动 TC 模式限速。${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 获取端口流量摘要（专为Telegram格式化）
get_port_traffic_summary_for_tg() {
    # 如果有 port_traffic_helper.sh 中的函数，优先使用
    if command -v get_port_traffic_summary &> /dev/null; then
        local summary=$(get_port_traffic_summary 5)
        if [ -n "$summary" ]; then
            # 转换换行符为URL编码格式
            echo "$summary" | sed 's/\n/%0A/g'
            return
        fi
    fi
    
    # 兼容性实现（如果port_traffic_helper.sh不可用）
    local ports_config_file="$WORK_DIR/ports_traffic_config.json"
    local summary=""
    
    if [ ! -f "$ports_config_file" ]; then
        return
    fi
    
    # 检查是否有端口配置
    local port_count=$(jq -r '.ports | length' "$ports_config_file" 2>/dev/null)
    if [ -z "$port_count" ] || [ "$port_count" -eq 0 ]; then
        return
    fi
    
    summary="%0A%0A🔌 端口流量详情："
    
    # 使用与view_port_traffic.sh相同的方法获取流量
    if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
        local port_data=$(bash "$WORK_DIR/view_port_traffic.sh" --json 2>/dev/null)
        if [ -n "$port_data" ]; then
            local max_display=5
            local displayed=0
            
            for ((i=0; i<port_count && displayed<max_display; i++)); do
                local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                
                if [ -n "$port" ] && [ "$port" != "null" ]; then
                    local port_percentage=0
                    if (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                        port_percentage=$(echo "scale=0; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0")
                    fi
                    summary="${summary}%0A✓ 端口 ${port}: ${port_usage}GB / ${port_limit}GB (${port_percentage}%)"
                    displayed=$((displayed + 1))
                fi
            done
            
            if [ "$port_count" -gt "$max_display" ]; then
                summary="${summary}%0A...及其他 $((port_count - max_display)) 个端口"
            fi
        fi
    fi
    
    echo "$summary"
}

# 发送限速解除通知
send_throttle_lifted() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="✅ [${MACHINE_NAME}]限速解除：流量已恢复正常，所有限制已清除。${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 发送新周期开始通知
send_new_cycle_notification() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local message="🔄 [${MACHINE_NAME}]新周期开始：新的流量统计周期已开始，之前的限速（如果有）已自动解除。"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 发送关机警告
send_shutdown_warning() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="🚨 [${MACHINE_NAME}]关机警告：流量已达到严重限制，系统将在 1 分钟后关机！${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}




test_telegram_notification() {
    local message="🔔 [${MACHINE_NAME}]这是一条测试消息。如果您收到这条消息，说明Telegram通知功能正常工作。"
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "disable_notification=true")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ [${MACHINE_NAME}]测试消息已成功发送，请检查您的Telegram。"
    else
        echo "❌ [${MACHINE_NAME}]发送测试消息失败。请检查您的BOT_TOKEN和CHAT_ID设置。"
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

# 更新cron任务中的时间（当修改每日报告时间时调用）
update_cron_time() {
    local new_time="$1"
    echo "正在更新cron任务时间为: $new_time"
    
    # 重新读取配置以获取最新时间
    read_config
    
    # 重新设置cron任务
    setup_cron
    
    echo "cron任务时间已更新"
}

# 每日报告
daily_report() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始生成每日报告"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : DAILY_REPORT_TIME=$DAILY_REPORT_TIME"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : BOT_TOKEN=${BOT_TOKEN:0:5}... CHAT_ID=$CHAT_ID"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 日志文件路径: $LOG_FILE"| tee -a "$CRON_LOG"

    # ---------------------------------------------------------------
    # 取数：优先读带时间戳的状态快照，其次回退到日志（并做新鲜度校验）
    #
    # 历史缺陷：原先直接 `tac 日志 | grep -m 1` 抓最后一条含「当前使用流量…限制流量」
    # 的行。该行没有时间戳校验，cron 中断后日志停止更新，报告便读到几天前的陈旧值，
    # 客户会看到「流量倒退」的假象（真实客户机上已发生）。
    # 现在优先读 trafficcop.sh 写出的 traffic_state.json，并按新鲜度判断可信度。
    # ---------------------------------------------------------------
    local usage_line=""
    local current_usage=""
    local limit=""
    local data_source="日志"
    local is_stale="false"
    local stale_hint=""

    # 状态快照路径（与 trafficcop.sh 的 WORK_DIR 一致）
    local state_file="$WORK_DIR/traffic_state.json"
    # 允许通过环境变量调整新鲜度阈值（秒），默认 3 小时
    local stale_threshold="${STATE_STALE_THRESHOLD:-10800}"

    if [ -f "$state_file" ]; then
        local st_epoch st_now st_age
        st_epoch=$(grep -o '"epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$state_file" 2>/dev/null | grep -o '[0-9]*$')
        if [ -n "$st_epoch" ]; then
            st_now=$(date +%s)
            st_age=$((st_now - st_epoch))
            local st_usage st_limit
            st_usage=$(grep -o '"usage_gb"[[:space:]]*:[[:space:]]*[0-9.]*' "$state_file" 2>/dev/null | grep -o '[0-9.]*$')
            st_limit=$(grep -o '"limit_gb"[[:space:]]*:[[:space:]]*[0-9.]*' "$state_file" 2>/dev/null | grep -o '[0-9.]*$')

            if [ -n "$st_usage" ] && [ -n "$st_limit" ]; then
                if [ "$st_age" -le "$stale_threshold" ]; then
                    current_usage="${st_usage} GB"
                    limit="${st_limit} GB"
                    data_source="状态快照"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 使用状态快照，数据年龄 ${st_age}s（阈值 ${stale_threshold}s）"| tee -a "$CRON_LOG"
                else
                    # 快照存在但已过期 → 说明主脚本长时间没跑，cron 很可能已失效
                    is_stale="true"
                    local age_hours=$((st_age / 3600))
                    local age_days=$((st_age / 86400))
                    stale_hint="数据已 ${age_days} 天 ${age_hours} 小时未更新"
                    current_usage="${st_usage} GB"
                    limit="${st_limit} GB"
                    data_source="状态快照(过期)"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 警告：状态快照已过期 ${st_age}s，主脚本可能未在运行"| tee -a "$CRON_LOG"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 状态快照存在但字段不完整，回退到日志解析"| tee -a "$CRON_LOG"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 状态快照无法解析 epoch，回退到日志解析"| tee -a "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 未找到状态快照（老版本安装），回退到日志解析"| tee -a "$CRON_LOG"
    fi

    # 回退路径：从日志解析（老安装兼容）。同时校验该行的时间戳新鲜度。
    if [ -z "$current_usage" ] || [ -z "$limit" ]; then
        # 反向读取日志文件，查找第一个同时包含"当前使用流量"和"限制流量"的行
        usage_line=$(tac "$LOG_FILE" 2>/dev/null | grep -m 1 -E "当前使用流量:.*限制流量:")

        if [[ -z "$usage_line" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法在日志中找到同时包含当前使用流量和限制流量的行"| tee -a "$CRON_LOG"
            return 1
        fi

        current_usage=$(echo "$usage_line" | grep -oP '当前使用流量:\s*\K[0-9.]+ [GBMKgbmk]+')
        limit=$(echo "$usage_line" | grep -oP '限制流量:\s*\K[0-9.]+ [GBMKgbmk]+')

        if [[ -z "$current_usage" || -z "$limit" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法从行中提取流量信息"| tee -a "$CRON_LOG"
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 问题行: $usage_line"| tee -a "$CRON_LOG"
            return 1
        fi

        # 校验日志行自带的时间戳新鲜度（行首形如 2026-10-06 10:30:00）
        local line_ts line_epoch
        line_ts=$(echo "$usage_line" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')
        if [ -n "$line_ts" ]; then
            line_epoch=$(date -d "$line_ts" +%s 2>/dev/null || echo "")
            if [ -n "$line_epoch" ]; then
                local log_age=$(($(date +%s) - line_epoch))
                if [ "$log_age" -gt "$stale_threshold" ]; then
                    is_stale="true"
                    stale_hint="日志数据已 $((log_age / 86400)) 天 $(((log_age % 86400) / 3600)) 小时未更新"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 警告：日志数据已过期 ${log_age}s"| tee -a "$CRON_LOG"
                fi
            fi
        else
            # 无时间戳的老格式日志行，无法判断新鲜度，保守标记
            is_stale="unknown"
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 日志行无时间戳，无法校验新鲜度"| tee -a "$CRON_LOG"
        fi
        data_source="日志"
    fi

    # 构建基础消息
    local message="📊 [${MACHINE_NAME}]每日流量报告%0A%0A"
    if [ "$is_stale" = "true" ]; then
        message="${message}⚠️ 注意：${stale_hint}%0A请检查定时任务是否正常运行%0A%0A"
    elif [ "$is_stale" = "unknown" ]; then
        message="${message}⚠️ 注意：无法校验数据新鲜度%0A%0A"
    fi
    message="${message}🖥️ 本周期流量（数据来源：${data_source}）：%0A当前使用：$current_usage%0A流量限制：$limit"
    
    # 检查是否有端口流量配置
    local ports_config_file="$WORK_DIR/ports_traffic_config.json"
    local view_script="$WORK_DIR/view_port_traffic.sh"
    
    if [ -f "$ports_config_file" ]; then
        local port_count=$(jq -r '.ports | length' "$ports_config_file" 2>/dev/null || echo "0")
        
        if [ "$port_count" -gt 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到 $port_count 个端口流量配置，添加端口信息"| tee -a "$CRON_LOG"
            
            # 尝试从缓存加载准确的端口数据
            local port_data=$(load_port_traffic_data)
            
            # 调试：显示获取到的端口数据（只显示前100个字符避免日志过长）
            echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 获取到的端口数据长度: ${#port_data}字符"| tee -a "$CRON_LOG"
            if [ -n "$port_data" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 数据预览: $(echo "$port_data" | head -c 100)..."| tee -a "$CRON_LOG"
            fi
            
            if [ -n "$port_data" ] && echo "$port_data" | jq -e '.ports' >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 使用缓存的端口流量数据"| tee -a "$CRON_LOG"
                local actual_port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null || echo "0")
                
                if [ "$actual_port_count" -gt 0 ]; then
                    message="${message}%0A%0A🔌 端口流量详情："
                    
                    # 遍历每个端口
                    local i=0
                    while [ $i -lt $actual_port_count ]; do
                        local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                        local port_desc=$(echo "$port_data" | jq -r ".ports[$i].description" 2>/dev/null)
                        local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                        local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                        
                        # 调试：显示每个端口的原始数据
                        echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 端口[$i] port=$port, desc=$port_desc, usage=$port_usage, limit=$port_limit"| tee -a "$CRON_LOG"
                        
                        if [ -n "$port" ] && [ "$port" != "null" ] && [ "$port_usage" != "null" ]; then
                            # 格式化流量显示（保留2位小数）
                            local port_usage_formatted=$(printf "%.2f" "$port_usage" 2>/dev/null || echo "$port_usage")
                            local port_limit_formatted=$(printf "%.2f" "$port_limit" 2>/dev/null || echo "$port_limit")
                            
                            # 根据使用率选择表情
                            local port_percentage=0
                            if [ -n "$port_limit" ] && [ "$port_limit" != "null" ] && (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                                port_percentage=$(printf "%.2f" $(echo "scale=2; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0"))
                            fi
                            
                            local status_icon="✅"
                            if (( $(echo "$port_percentage >= 90" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🔴"
                            elif (( $(echo "$port_percentage >= 75" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🟡"
                            fi
                            
                            message="${message}%0A${status_icon} 端口 ${port} (${port_desc})：${port_usage_formatted}GB / ${port_limit_formatted}GB"
                        fi
                        
                        i=$((i + 1))
                    done
                    
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 已添加 $actual_port_count 个端口的流量信息"| tee -a "$CRON_LOG"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : JSON数据中没有端口信息"| tee -a "$CRON_LOG"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法获取缓存的端口流量数据，尝试实时获取"| tee -a "$CRON_LOG"
                
                # 备用方案：尝试实时获取数据
                if [ -f "$view_script" ]; then
                    local fallback_data=$(bash "$view_script" --json 2>/dev/null)
                    if [ -n "$fallback_data" ] && echo "$fallback_data" | jq -e '.ports' >/dev/null 2>&1; then
                        port_data="$fallback_data"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') : 使用实时端口流量数据作为备用"| tee -a "$CRON_LOG"
                        # 重新处理端口数据
                        local actual_port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null || echo "0")
                        if [ "$actual_port_count" -gt 0 ]; then
                            message="${message}%0A%0A🔌 端口流量详情："
                            local i=0
                            while [ $i -lt $actual_port_count ]; do
                                local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                                local port_desc=$(echo "$port_data" | jq -r ".ports[$i].description" 2>/dev/null)
                                local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                                local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                                
                                if [ -n "$port" ] && [ "$port" != "null" ] && [ "$port_usage" != "null" ]; then
                                    local port_usage_formatted=$(printf "%.2f" "$port_usage" 2>/dev/null || echo "$port_usage")
                                    local port_limit_formatted=$(printf "%.2f" "$port_limit" 2>/dev/null || echo "$port_limit")
                                    
                                    local port_percentage=0
                                    if [ -n "$port_limit" ] && [ "$port_limit" != "null" ] && (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                                        port_percentage=$(printf "%.2f" $(echo "scale=2; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0"))
                                    fi
                                    
                                    local status_icon="✅"
                                    if (( $(echo "$port_percentage >= 90" | bc -l 2>/dev/null || echo "0") )); then
                                        status_icon="🔴"
                                    elif (( $(echo "$port_percentage >= 75" | bc -l 2>/dev/null || echo "0") )); then
                                        status_icon="🟡"
                                    fi
                                    
                                    message="${message}%0A${status_icon} 端口 ${port} (${port_desc})：${port_usage_formatted}GB / ${port_limit_formatted}GB"
                                fi
                                i=$((i + 1))
                            done
                            echo "$(date '+%Y-%m-%d %H:%M:%S') : 已添加 $actual_port_count 个端口的流量信息（备用数据）"| tee -a "$CRON_LOG"
                        fi
                    else
                        echo "$(date '+%Y-%m-%d %H:%M:%S') : 实时数据获取也失败，跳过端口流量显示"| tee -a "$CRON_LOG"
                    fi
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : view_port_traffic.sh脚本不存在，跳过端口流量显示"| tee -a "$CRON_LOG"
                fi
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 没有配置端口流量监控"| tee -a "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 端口配置文件不存在"| tee -a "$CRON_LOG"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 准备发送消息"| tee -a "$CRON_LOG"
    
    # 调试：显示即将发送的消息内容
    echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] 发送到TG的消息内容:"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : [调试] $message"| tee -a "$CRON_LOG"

    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local response

    echo "$(date '+%Y-%m-%d %H:%M:%S') : 尝试发送Telegram消息"| tee -a "$CRON_LOG"

    response=$(curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message")

    if echo "$response" | grep -q '"ok":true'; then
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
        check_and_notify "false"
        
    # 检查是否需要发送每日报告
    # 先刷新缓存，保证定时发送时有最新的端口数据（在cron环境下主动生成缓存）
    save_port_traffic_data 2>/dev/null || true
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
        # 菜单模式 (替换原来的交互模式)
        if ! read_config; then
            echo "需要进行初始化配置。"
            initial_config
        fi
        
        setup_cron
        
        # 显示菜单
        while true; do
            clear
            echo "======================================"
            echo "      Telegram 通知脚本管理菜单"
            echo "======================================"
            echo "当前配置摘要："
            echo "机器名称: $MACHINE_NAME"
            echo "每日报告时间: $DAILY_REPORT_TIME"
            echo "Bot Token: ${BOT_TOKEN:0:10}..." # 只显示前10个字符
            echo "Chat ID: $CHAT_ID"
            echo "======================================"
            echo "1. 检查流量并推送"
            echo "2. 手动发送每日报告"
            echo "3. 发送测试消息"
            echo "4. 重新加载配置"
            echo "5. 修改配置"
            echo "6. 修改每日报告时间"
            echo "7. 查看缓存调试信息"
            echo "0. 退出"
            echo "======================================"
            echo -n "请选择操作 [0-7]: "
            
            read choice
            echo
            
            case $choice in
                0)
                    echo "退出脚本。"
                    exit 0
                    ;;
                1)
                    echo "正在检查流量并推送..."
                    # 检查流量时保存当前准确的端口数据
                    save_port_traffic_data
                    check_and_notify
                    ;;
                2)
                    echo "正在发送每日报告..."
                    # 手动发送每日报告前保存当前准确的端口数据
                    save_port_traffic_data
                    daily_report
                    ;;
                3)
                    echo "正在发送测试消息..."
                    test_telegram_notification
                    ;;
                4)
                    echo "正在重新加载配置..."
                    read_config
                    echo "配置已重新加载。"
                    ;;
                5)
                    echo "进入配置修改模式..."
                    initial_config
                    ;;
                6)
                    echo "修改每日报告时间"
                    echo -n "请输入新的每日报告时间 (HH:MM): "
                    read -r new_time
                    if [[ $new_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                        # 直接使用命令行工具修改配置，避免交互环境问题
                        cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
                        awk -v new_time="$new_time" '
                        /^DAILY_REPORT_TIME=/ { print "DAILY_REPORT_TIME=" new_time; next }
                        { print }
                        ' "$CONFIG_FILE.backup" > "$CONFIG_FILE"
                        
                        echo "每日报告时间已更新为 $new_time"
                        # 更新 cron 任务
                        update_cron_time "$new_time"
                        # 修改时间后立即刷新缓存
                        echo "正在刷新端口流量缓存..."
                        save_port_traffic_data
                        echo "缓存已刷新，定时推送将使用最新数据。"
                    else
                        echo "无效的时间格式。请使用 HH:MM 格式 (如: 09:30)"
                    fi
                    ;;
                7)
                    echo "查看最近的缓存调试信息..."
                    echo "最近5个缓存文件："
                    ls -lt /tmp/port_traffic_cache_*.json 2>/dev/null | head -5
                    echo
                    echo "最新缓存内容："
                    latest_cache=$(ls -t /tmp/port_traffic_cache_*.json 2>/dev/null | head -1)
                    if [ -n "$latest_cache" ]; then
                        echo "文件: $latest_cache"
                        cat "$latest_cache" | jq '.' 2>/dev/null || cat "$latest_cache"
                    else
                        echo "未找到缓存文件"
                    fi
                    ;;
                *)
                    echo "无效的选择，请输入 0-7"
                    ;;
            esac
            
            if [ "$choice" != "0" ]; then
                echo
                echo "按 Enter 键继续..."
                read
            fi
        done
    fi
}


# 执行主函数
main "$@"
echo "----------------------------------------------"| tee -a "$CRON_LOG"
