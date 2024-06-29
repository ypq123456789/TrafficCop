#!/bin/bash

# 配置文件路径
CONFIG_FILE="/root/traffic_monitor_config.txt"
LOG_FILE="/root/traffic_monitor.log"
SCRIPT_PATH=$(realpath "\$0")

# 检查并安装必要的软件包
check_and_install_packages() {
    local packages=("vnstat" "jq" "bc")
    for package in "${packages[@]}"; do
        if ! command -v $package &> /dev/null; then
            echo "$package 未安装，正在安装..."
            sudo apt-get update && sudo apt-get install -y $package
            echo "$package 安装完成"
        else
            echo "$package 已安装"
        fi
    done
}

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "$LOG_FILE"
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
TRAFFIC_PERIOD=$TRAFFIC_PERIOD
TRAFFIC_LIMIT=$TRAFFIC_LIMIT
PERIOD_START_DAY=$PERIOD_START_DAY
LIMIT_SPEED=$LIMIT_SPEED
MAIN_INTERFACE=$MAIN_INTERFACE
CHECK_INTERVAL=$CHECK_INTERVAL
EOF
    log_message "配置已更新"
}

# 配置处理函数
handle_config() {
    if read_config; then
        echo "当前配置："
        echo "流量统计周期: $TRAFFIC_PERIOD"
        echo "流量限制: $TRAFFIC_LIMIT GB"
        echo "周期起始日: $PERIOD_START_DAY"
        echo "限速: $LIMIT_SPEED kbit/s"
        echo "主网卡: $MAIN_INTERFACE"
        echo "检查间隔: $CHECK_INTERVAL 分钟"
        
        read -t 10 -p "是否需要修改配置？(y/n, 10秒后默认为n): " modify_config
        if [[ $modify_config == "y" ]]; then
            update_config
        fi
    else
        echo "未找到配置文件，开始初始配置"
        initial_config
    fi
}

# 更新配置函数
update_config() {
    read -p "流量统计周期 (monthly/quarterly/yearly, 当前: $TRAFFIC_PERIOD): " new_period
    TRAFFIC_PERIOD=${new_period:-$TRAFFIC_PERIOD}

    read -p "流量限制 (GB, 当前: $TRAFFIC_LIMIT): " new_limit
    TRAFFIC_LIMIT=${new_limit:-$TRAFFIC_LIMIT}

    read -p "周期起始日 (1-31, 当前: $PERIOD_START_DAY): " new_start_day
    PERIOD_START_DAY=${new_start_day:-$PERIOD_START_DAY}

    read -p "限速 (kbit/s, 当前: $LIMIT_SPEED): " new_speed
    LIMIT_SPEED=${new_speed:-$LIMIT_SPEED}

    MAIN_INTERFACE=$(get_main_interface)

    read -p "检查间隔 (分钟, 当前: $CHECK_INTERVAL): " new_interval
    CHECK_INTERVAL=${new_interval:-$CHECK_INTERVAL}

    write_config
}

# 获取主要网络接口
get_main_interface() {
    local main_interface=$(ip route | grep default | awk '{print \$5}' | head -n1)
    if [ -z "$main_interface" ]; then
        main_interface=$(ip link show | grep 'state UP' | awk -F': ' '{print \$2}' | head -n1)
    fi
    
    if [ -z "$main_interface" ]; then
        echo "无法自动检测主要网络接口。"
        read -p "请手动输入主要网络接口名称: " main_interface
    else
        echo "检测到的主要网络接口是: $main_interface"
        read -p "是否使用此接口？(y/n) " confirm
        if [[ $confirm != "y" ]]; then
            read -p "请输入正确的网络接口名称: " new_interface
            main_interface=$new_interface
        fi
    fi
    
    echo $main_interface
}

# 初始配置函数
initial_config() {
    read -p "请选择流量统计周期 (monthly/quarterly/yearly): " TRAFFIC_PERIOD
    read -p "请输入流量限制 (GB): " TRAFFIC_LIMIT
    read -p "请输入周期起始日 (1-31): " PERIOD_START_DAY
    read -p "请输入限速 (kbit/s): " LIMIT_SPEED
    MAIN_INTERFACE=$(get_main_interface)
    read -p "请输入检查间隔 (分钟，默认为5): " CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-5}

    write_config
}

# 设置crontab
setup_crontab() {
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH") | crontab -
    echo "*/$CHECK_INTERVAL * * * * $SCRIPT_PATH --run" | crontab -
    log_message "Crontab 已设置，每 $CHECK_INTERVAL 分钟运行一次"
}

# 获取当前周期的起始日期
get_period_start_date() {
    local current_date=$(date +%Y-%m-%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    
    case $TRAFFIC_PERIOD in
        monthly)
            if [ $(date +%d) -lt $PERIOD_START_DAY ]; then
                echo $(date -d "${current_year}-${current_month}-01 -1 month" +'%Y-%m-%d')
            else
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
    local total_usage=$(vnstat --json | jq ".interfaces[0].traffic.total.bytes")
    echo "$((total_usage / (1024*1024*1024)))"
}

# 检查并限制流量
check_and_limit_traffic() {
    local usage=$(get_traffic_usage)
    log_message "当前使用流量: $usage GB"

    if (( $(echo "$usage > $TRAFFIC_LIMIT" | bc -l) )); then
        log_message "超过流量限制，正在限制带宽..."
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
        tc qdisc add dev $MAIN_INTERFACE root tbf rate ${LIMIT_SPEED}kbit burst 32kbit latency 400ms
    else
        log_message "流量正常，清除所有限制"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}

# 主函数
main() {
    check_and_install_packages
    
    if [[ "\$1" == "--run" ]]; then
        if read_config; then
            check_and_limit_traffic
        else
            log_message "配置文件为空或不存在，请先运行脚本进行配置"
        fi
    else
        handle_config
        setup_crontab
        log_message "设置完成，脚本将每 $CHECK_INTERVAL 分钟自动运行一次"
    fi
}

# 执行主函数
main "$@"
