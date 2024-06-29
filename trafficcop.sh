#!/bin/bash

# 配置文件路径
CONFIG_FILE="/root/traffic_monitor_config.txt"
LOG_FILE="/root/traffic_monitor.log"
SCRIPT_PATH=$(realpath "\$0")

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "$LOG_FILE"
}

# 检查并更新脚本
check_and_update() {
    # 实现脚本自动更新的逻辑
    log_message "检查脚本更新..."
    if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT"; then
        if [[ -s "$TEMP_SCRIPT" ]]; then
            CURRENT_HASH=$(sha256sum "\$0" | cut -d' ' -f1)
            NEW_HASH=$(sha256sum "$TEMP_SCRIPT" | cut -d' ' -f1)
            
            if [[ "$NEW_HASH" != "$CURRENT_HASH" ]]; then
                log_message "发现新版本。"
                read -p "是否要更新？(y/n): " choice
                case "$choice" in 
                    y|Y )
                        mv "$TEMP_SCRIPT" "\$0"
                        chmod +x "\$0"
                        log_message "更新成功。请重新运行脚本。"
                        exit 0
                        ;;
                    * ) 
                        log_message "更新已跳过。"
                        rm -f "$TEMP_SCRIPT"
                        ;;
                esac
            else
                log_message "您正在使用最新版本。"
                rm -f "$TEMP_SCRIPT"
            fi
        else
            log_message "错误：下载的文件为空。"
            rm -f "$TEMP_SCRIPT"
        fi
    else
        log_message "错误：下载更新失败。"
    fi
}
#!/bin/bash

# 检查并安装 vnstat
check_and_install_vnstat() {
    if ! command -v vnstat &> /dev/null; then
        log_message "vnstat 未安装，正在安装..."
        sudo apt-get update && sudo apt-get install -y vnstat
        log_message "vnstat 安装完成"
    fi
}

# 函数：获取 SSH 端口
get_ssh_port() {
    local ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print \$2}')
    if [ -z "$ssh_port" ]; then
        ssh_port=22
    fi
    echo $ssh_port
}

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "$LOG_FILE"
}

# 读取配置
read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        initial_config
    fi
}

# 写入配置
write_config() {
    echo "TRAFFIC_PERIOD=$TRAFFIC_PERIOD" > "$CONFIG_FILE"
    echo "TRAFFIC_LIMIT=$TRAFFIC_LIMIT" >> "$CONFIG_FILE"
    echo "PERIOD_START_DAY=$PERIOD_START_DAY" >> "$CONFIG_FILE"
    log_message "配置已更新"
}

# 设置crontab
setup_crontab() {
    (crontab -l 2>/dev/null | grep -v "/root/traffic_monitor.sh") | crontab -
    echo "0 0 * * * /root/traffic_monitor.sh" | crontab -
    log_message "Crontab 已设置"
}

# 初始配置函数
initial_config() {
    log_message "开始初始配置"
    
    while true; do
        read -p "请选择流量统计周期 (1: 月, 2: 季度, 3: 年): " period_choice
        case $period_choice in
            1) TRAFFIC_PERIOD="monthly"; break;;
            2) TRAFFIC_PERIOD="quarterly"; break;;
            3) TRAFFIC_PERIOD="yearly"; break;;
            *) echo "无效选择，请重新输入";;
        esac
    done
    
    read -p "请输入 ${TRAFFIC_PERIOD} 流量限制 (GB): " TRAFFIC_LIMIT
    
    read -p "请输入流量统计周期的起始日 (1-31): " PERIOD_START_DAY
    if [[ ! $PERIOD_START_DAY =~ ^[1-9]$|^[1-2][0-9]$|^3[0-1]$ ]]; then
        PERIOD_START_DAY=1
        echo "无效输入，设置为默认值1"
    fi
    
    setup_crontab
    write_config
}

# 更新配置函数（带超时）
update_config_with_timeout() {
    read -p "是否需要更新配置？(y/n) " answer
    if [[ $answer == "y" ]]; then
        log_message "用户选择更新配置"
        
        read -t 10 -p "流量统计周期 (1: 月, 2: 季度, 3: 年, 当前: $TRAFFIC_PERIOD) (10秒后超时): " -e period_choice
        case $period_choice in
            1) TRAFFIC_PERIOD="monthly";;
            2) TRAFFIC_PERIOD="quarterly";;
            3) TRAFFIC_PERIOD="yearly";;
            "") 
                if [ "$TRAFFIC_PERIOD" == "" ]; then
                    TRAFFIC_PERIOD="monthly"
                    log_message "超时或未输入，默认设置为月度周期"
                fi
                ;;
            *) 
                TRAFFIC_PERIOD="monthly"
                log_message "无效输入，默认设置为月度周期"
                ;;
        esac
        
        read -t 10 -p "${TRAFFIC_PERIOD} 流量限制 (GB) (10秒后超时): " -e -i "$TRAFFIC_LIMIT" new_limit
        TRAFFIC_LIMIT=${new_limit:-$TRAFFIC_LIMIT}
        
        read -t 10 -p "流量统计周期的起始日 (1-31, 当前: $PERIOD_START_DAY) (10秒后超时): " -e -i "$PERIOD_START_DAY" new_start_day
        if [[ $new_start_day =~ ^[1-9]$|^[1-2][0-9]$|^3[0-1]$ ]]; then
            PERIOD_START_DAY=$new_start_day
        elif [ -z "$new_start_day" ]; then
            PERIOD_START_DAY=1
            log_message "超时或未输入，起始日默认设置为1号"
        else
            PERIOD_START_DAY=1
            log_message "无效的起始日输入，默认设置为1号"
        fi
        
        setup_crontab
        write_config
    else
        log_message "用户未选择更新配置"
    fi
}

# 获取当前周期的起始日期
get_period_start_date() {
    local current_date=$(date +%Y-%m-%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    
    case $TRAFFIC_PERIOD in
        monthly)
            if [ $(date +%d) -lt $PERIOD_START_DAY ]; then
                # 如果当前日期小于起始日，则取上个月的起始日
                echo $(date -d "${current_year}-${current_month}-01 -1 month" +'%Y-%m-%d')
            else
                # 确保日期有效，如果无效则使用当月最后一天
                echo $(date -d "${current_year}-${current_month}-${PERIOD_START_DAY}" +%Y-%m-%d 2>/dev/null || date -d "${current_year}-${current_month}-01 +1 month -1 day" +%Y-%m-%d)
            fi
            ;;
        quarterly)
            local quarter_month=$(((($(date +%m) - 1) / 3) * 3 + 1))
            echo $(date -d "${current_year}-${quarter_month}-01" +'%Y-%m-%d')
            ;;
        yearly)
            echo "${current_year}-01-01"
            ;;
    esac
}

# 获取流量使用情况
get_traffic_usage() {
    local start_date=$(get_period_start_date)
    local end_date=$(date +%Y-%m-%d)
    local rx_bytes=$(awk -v start="$start_date" -v end="$end_date" '\$1 >= start && \$1 <= end {sum += \$2} END {print sum}' /root/vnstat_data.txt)
    local tx_bytes=$(awk -v start="$start_date" -v end="$end_date" '\$1 >= start && \$1 <= end {sum += \$3} END {print sum}' /root/vnstat_data.txt)
    echo "$(( (rx_bytes + tx_bytes) / (1024*1024*1024) ))"
}

# 检查并限制流量
check_and_limit_traffic() {
    local daily_usage=$(vnstat -i "$MAIN_INTERFACE" --oneline | cut -d';' -f11)
    local monthly_usage=$(vnstat -i "$MAIN_INTERFACE" -m | tail -n2 | head -n1 | awk '{print \$3 \$4}')

    daily_usage=${daily_usage%MiB}
    monthly_usage=${monthly_usage%MiB}

    daily_usage_gb=$(echo "scale=2; $daily_usage / 1024" | bc)
    monthly_usage_gb=$(echo "scale=2; $monthly_usage / 1024" | bc)

    log_message "当日使用: $daily_usage_gb GB, 当月使用: $monthly_usage_gb GB"

    if (( $(echo "$daily_usage_gb > $DAILY_LIMIT" | bc -l) )); then
        log_message "超过每日限制，正在限制流量..."
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        iptables -A OUTPUT -p tcp --sport "$SSH_PORT" -j ACCEPT
        iptables -A INPUT -j DROP
        iptables -A OUTPUT -j DROP
    elif (( $(echo "$monthly_usage_gb > $MONTHLY_LIMIT" | bc -l) )); then
        log_message "超过每月限制，正在限制流量..."
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        iptables -A OUTPUT -p tcp --sport "$SSH_PORT" -j ACCEPT
        iptables -A INPUT -j DROP
        iptables -A OUTPUT -j DROP
    else
        iptables -F
        log_message "流量正常，清除所有限制"
    fi
}

# 主函数
main() {
    if [[ "\$1" == "--run" ]]; then
        if read_config; then
            check_and_limit_traffic
        else
            log_message "配置文件为空或不存在，请先运行脚本进行配置"
        fi
    else
        check_and_install_vnstat
        check_and_update
        MAIN_INTERFACE=$(get_main_interface)
        SSH_PORT=$(get_ssh_port)
        if ! read_config; then
            initial_config
        else
            update_config_with_timeout
        fi
        log_message "设置完成，脚本将通过 crontab 自动运行"
    fi
}

# 执行主函数
main "$@"
