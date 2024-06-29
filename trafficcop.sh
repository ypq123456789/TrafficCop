#!/bin/bash

CONFIG_FILE="/etc/vps_traffic_limit.conf"
LOG_FILE="/var/log/vps_traffic_limit.log"
SCRIPT_PATH=$(realpath "\$0")

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "$LOG_FILE"
}

# 检查并安装 vnstat
check_and_install_vnstat() {
    if ! command -v vnstat &> /dev/null; then
        log_message "vnstat 未安装，正在安装..."
        sudo apt-get update && sudo apt-get install -y vnstat
        log_message "vnstat 安装完成"
    fi
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

# 函数：获取主要网卡名称
get_main_interface() {
    local detected_interface=$(ip route | grep default | awk '{print \$5}' | head -n1)
    local all_interfaces=($(ip -o link show | awk -F': ' '{print \$2}' | tr -d ' '))

    echo "检测到的默认网卡: $detected_interface"
    echo "系统上的所有网卡:"
    for i in "${!all_interfaces[@]}"; do
        echo "$((i+1)). ${all_interfaces[i]}"
    done

    read -p "请确认是否使用 $detected_interface 作为主要网卡？(y/n) " confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        echo $detected_interface
    else
        read -p "请输入要使用的网卡编号: " choice
        if [[ $choice -ge 1 && $choice -le ${#all_interfaces[@]} ]]; then
            echo ${all_interfaces[$((choice-1))]}
        else
            echo "无效选择，使用默认网卡 $detected_interface"
            echo $detected_interface
        fi
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

# 读取配置
read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        log_message "配置文件不存在，将使用默认值"
    fi
}

# 写入配置
write_config() {
    echo "MAIN_INTERFACE=$MAIN_INTERFACE" > "$CONFIG_FILE"
    echo "SSH_PORT=$SSH_PORT" >> "$CONFIG_FILE"
    echo "DAILY_LIMIT=$DAILY_LIMIT" >> "$CONFIG_FILE"
    echo "MONTHLY_LIMIT=$MONTHLY_LIMIT" >> "$CONFIG_FILE"
    echo "CRON_INTERVAL=$CRON_INTERVAL" >> "$CONFIG_FILE"
    log_message "配置已更新"
}

# 设置 crontab 函数
setup_crontab() {
    read -p "请输入脚本执行的间隔分钟数（1-59）: " interval
    if [[ ! $interval =~ ^[1-9]$|^[1-5][0-9]$ ]]; then
        interval=1
        log_message "无效输入，设置为默认值1分钟"
    fi
    CRON_INTERVAL=$interval
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "*/$interval * * * * $SCRIPT_PATH --run") | crontab -
    log_message "已设置 crontab 每 $interval 分钟执行一次脚本"
}

# 更新配置函数（带超时）
update_config_with_timeout() {
    read -t 3 -p "是否需要更新配置？(y/n) " answer
    if [[ $answer == "y" ]]; then
        log_message "用户选择更新配置"
        read -t 3 -p "每日流量限制 (GB): " DAILY_LIMIT
        read -t 3 -p "每月流量限制 (GB): " MONTHLY_LIMIT
        setup_crontab
        write_config
    else
        log_message "用户未选择更新配置或超时"
    fi
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
        read_config
        check_and_limit_traffic
    else
        check_and_install_vnstat
        check_and_update
        MAIN_INTERFACE=$(get_main_interface)
        SSH_PORT=$(get_ssh_port)
        read_config
        update_config_with_timeout
        log_message "初始设置完成，脚本将通过 crontab 自动运行"
    fi
}

# 执行主函数
main "$@"
