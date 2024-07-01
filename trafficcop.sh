#!/bin/bash
echo "当前版本：1.0.4"

# 配置文件路径
CONFIG_FILE="/root/traffic_monitor_config.txt"
LOG_FILE="/root/traffic_monitor.log"
SCRIPT_PATH="/root/traffic_monitor.sh"


# 检查配置和定时任务
check_existing_setup() {
     if [ -s "$CONFIG_FILE" ]; then  
        source "$CONFIG_FILE"
        echo "配置已存在："
        echo "流量统计模式: $TRAFFIC_MODE"
        echo "流量统计周期: $TRAFFIC_PERIOD"
        echo "周期起始日: ${PERIOD_START_DAY:-1}"
        echo "流量限制: $TRAFFIC_LIMIT GB"
        echo "容错范围: $TRAFFIC_TOLERANCE GB"
        echo "限速: ${LIMIT_SPEED:-20} kbit/s"
        echo "主要网络接口: $MAIN_INTERFACE"
        
        if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
            echo "每分钟一次的定时任务已在执行。"
        else
            echo "警告：定时任务未找到，可能需要重新设置。"
        fi
        return 0
    else
        return 1
    fi
}

# 检查并安装必要的软件包
check_and_install_packages() {
    local packages=("vnstat" "jq" "bc" "tc")
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
TRAFFIC_MODE=$TRAFFIC_MODE
TRAFFIC_PERIOD=$TRAFFIC_PERIOD
TRAFFIC_LIMIT=$TRAFFIC_LIMIT
TRAFFIC_TOLERANCE=$TRAFFIC_TOLERANCE
PERIOD_START_DAY=${PERIOD_START_DAY:-1}
LIMIT_SPEED=${LIMIT_SPEED:-20}
MAIN_INTERFACE=$MAIN_INTERFACE
EOF
    log_message "配置已更新"
}


# 显示当前配置
show_current_config() {
    echo "当前配置:"
    echo "流量统计模式: $TRAFFIC_MODE"
    echo "流量统计周期: $TRAFFIC_PERIOD"
    echo "周期起始日: ${PERIOD_START_DAY:-1}"
    echo "流量限制: $TRAFFIC_LIMIT GB"
    echo "容错范围: $TRAFFIC_TOLERANCE GB"
    echo "限速: ${LIMIT_SPEED:-20} kbit/s"
    echo "主要网络接口: $MAIN_INTERFACE"
}

get_main_interface() {
    local main_interface=$(ip route | grep default | sed -n 's/^default via [0-9.]* dev \([^ ]*\).*/\1/p' | head -n1)
    if [ -z "$main_interface" ]; then
        main_interface=$(ip link | grep 'state UP' | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p' | head -n1)
    fi
    
    if [ -z "$main_interface" ]; then
        while true; do
            echo "无法自动检测主要网络接口。"
            echo "可用的网络接口有："
            ip -o link show | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p'
            read -p "请从上面的列表中选择一个网络接口: " main_interface
            if [ -z "$main_interface" ]; then
                echo "请输入一个有效的接口名称。"
            elif ip link show "$main_interface" > /dev/null 2>&1; then
                break
            else
                echo "无效的接口，请重新选择。"
            fi
        done
    else
        read -p "检测到的主要网络接口是: $main_interface, 按Enter使用此接口，或输入新的接口名称: " new_interface
        if [ -n "$new_interface" ]; then
            if ip link show "$new_interface" > /dev/null 2>&1; then
                main_interface=$new_interface
            else
                echo "输入的接口无效，将使用检测到的接口: $main_interface"
            fi
        fi
    fi
    
    echo $main_interface
}


# 初始配置函数
initial_config() {
    echo "正在检测主要网络接口..."
    MAIN_INTERFACE=$(get_main_interface)

    echo "请选择流量统计模式："
    echo "1. 只计算出站流量"
    echo "2. 只计算进站流量"
    echo "3. 出进站流量都计算"
    echo "4. 出站和进站流量只取大"
    read -p "请输入选择 (1-4): " mode_choice
    case $mode_choice in
        1) TRAFFIC_MODE="out" ;;
        2) TRAFFIC_MODE="in" ;;
        3) TRAFFIC_MODE="total" ;;
        4) TRAFFIC_MODE="max" ;;
        *) TRAFFIC_MODE="total" ;;
    esac

    read -p "请选择流量统计周期 (m/q/y，默认为m): " period_choice
    case $period_choice in
        q) TRAFFIC_PERIOD="quarterly" ;;
        y) TRAFFIC_PERIOD="yearly" ;;
        *) TRAFFIC_PERIOD="monthly" ;;
    esac

    read -p "请输入周期起始日 (1-31，默认为1): " PERIOD_START_DAY
    PERIOD_START_DAY=${PERIOD_START_DAY:-1}

    read -p "请输入流量限制 (GB): " TRAFFIC_LIMIT
    read -p "请输入容错范围 (GB): " TRAFFIC_TOLERANCE

    read -p "请输入限速 (kbit/s，默认为20): " LIMIT_SPEED
    LIMIT_SPEED=${LIMIT_SPEED:-20}

    write_config
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
            echo $(date -d "${current_year}-${quarter_month}-${PERIOD_START_DAY}" +'%Y-%m-%d')
            ;;
        yearly)
            echo "${current_year}-01-${PERIOD_START_DAY}"
            ;;
    esac
}

# 获取流量使用情况
get_traffic_usage() {
    local start_date=$(get_period_start_date)
    local end_date=$(date +%Y-%m-%d)
    local json_data=$(vnstat --json -i $MAIN_INTERFACE)
    
    case $TRAFFIC_MODE in
        out)
            local usage=$(echo $json_data | jq ".interfaces[0].traffic.months[-1].tx")
            ;;
        in)
            local usage=$(echo $json_data | jq ".interfaces[0].traffic.months[-1].rx")
            ;;
        total)
            local usage=$(echo $json_data | jq ".interfaces[0].traffic.months[-1].tx + .interfaces[0].traffic.months[-1].rx")
            ;;
        max)
            local tx=$(echo $json_data | jq ".interfaces[0].traffic.months[-1].tx")
            local rx=$(echo $json_data | jq ".interfaces[0].traffic.months[-1].rx")
            local usage=$(echo "if ($tx > $rx) $tx else $rx" | bc)
            ;;
    esac
    
    echo "$((usage / (1024*1024*1024)))"
}

# 检查并限制流量
check_and_limit_traffic() {
    local usage=$(get_traffic_usage)
    local limit=$((TRAFFIC_LIMIT - TRAFFIC_TOLERANCE))
    log_message "当前使用流量: $usage GB，限制流量: $limit GB"

    if (( $(echo "$usage > $limit" | bc -l) )); then
        log_message "超过流量限制，正在限制带宽..."
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
        tc qdisc add dev $MAIN_INTERFACE root tbf rate ${LIMIT_SPEED}kbit burst 32kbit latency 400ms
    else
        log_message "流量正常，清除所有限制"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}

# 检查是否需要重置限制
check_reset_limit() {
    local current_date=$(date +%Y-%m-%d)
    local period_start=$(get_period_start_date)
    
    if [[ "$current_date" == "$period_start" ]]; then
        log_message "新的流量周期开始，重置限制"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}

# 设置crontab
setup_crontab() {
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH") | crontab -
    echo "* * * * * $SCRIPT_PATH --run" | crontab -
    log_message "Crontab 已设置，每分钟运行一次"
}


# 主函数
main() {
 if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then  
    if check_existing_setup; then
        read -p "是否需要修改配置？(y/n): " modify_config
        if [[ $modify_config == "y" ]]; then
            initial_config
            setup_crontab
            log_message "设置已更新，脚本将每分钟自动运行一次"
        else
            echo "保持现有配置。"
        fi
    else
        echo "未找到现有配置，开始初始设置..."
        check_and_install_packages
        initial_config
        setup_crontab
        log_message "设置完成，脚本将每分钟自动运行一次"
    fi

    if [[ "\$1" == "--run" ]]; then
        if read_config; then
            check_reset_limit
            check_and_limit_traffic
        else
            log_message "配置文件为空或不存在，请先运行脚本进行配置"
        fi
    fi
}


# 执行主函数
main "$@"
