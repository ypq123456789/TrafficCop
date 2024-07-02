#!/bin/bash
CONFIG_FILE="/root/traffic_monitor_config.txt"
LOG_FILE="/root/traffic_monitor.log"
SCRIPT_PATH="/root/traffic_monitor.sh"
LOCK_FILE="/var/run/traffic_monitor.lock"
echo "-----------------------------------------------------"| tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') 当前版本：1.0.34"| tee -a "$LOG_FILE"

# 在脚本开始处添加
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    if kill -0 $pid 2>/dev/null; then
        echo "脚本已在运行，PID: $pid"
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"

# 检查并安装必要的软件包
check_and_install_packages() {
    local packages=("vnstat" "jq" "bc" "tc")
    for package in "${packages[@]}"; do
        if ! command -v $package &> /dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') $package 未安装，正在安装..."| tee -a "$LOG_FILE"
            sudo apt-get update && sudo apt-get install -y $package
            echo "$(date '+%Y-%m-%d %H:%M:%S') $package 安装完成"| tee -a "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') $package 已安装"| tee -a "$LOG_FILE"
        fi
    done
}

# 检查配置和定时任务
check_existing_setup() {
     if [ -s "$CONFIG_FILE" ]; then  
        source "$CONFIG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已存在，如下："| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计模式: $TRAFFIC_MODE"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计周期: $TRAFFIC_PERIOD"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 周期起始日: ${PERIOD_START_DAY:-1}"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量限制: $TRAFFIC_LIMIT GB"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 容错范围: $TRAFFIC_TOLERANCE GB"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 限速: ${LIMIT_SPEED:-20} kbit/s"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 主要网络接口: $MAIN_INTERFACE"| tee -a "$LOG_FILE"
        
        if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 每分钟一次的定时任务已在执行。"| tee -a "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：定时任务未找到，可能需要重新设置。"| tee -a "$LOG_FILE"
        fi
        return 0
    else
        return 1
    fi
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已更新"| tee -a "$LOG_FILE"
}


# 显示当前配置
show_current_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 当前配置:"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计模式: $TRAFFIC_MODE"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计周期: $TRAFFIC_PERIOD"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 周期起始日: ${PERIOD_START_DAY:-1}"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量限制: $TRAFFIC_LIMIT GB"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 容错范围: $TRAFFIC_TOLERANCE GB"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 限速: ${LIMIT_SPEED:-20} kbit/s"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 主要网络接口: $MAIN_INTERFACE"| tee -a "$LOG_FILE"
}

# 检测主要网络接口
get_main_interface() {
    local main_interface=$(ip route | grep default | sed -n 's/^default via [0-9.]* dev \([^ ]*\).*/\1/p' | head -n1)
    if [ -z "$main_interface" ]; then
        main_interface=$(ip link | grep 'state UP' | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p' | head -n1)
    fi
    
    if [ -z "$main_interface" ]; then
        while true; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') 无法自动检测主要网络接口。"| tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 可用的网络接口有："| tee -a "$LOG_FILE"
            ip -o link show | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p'
            read -p "请从上面的列表中选择一个网络接口: " main_interface
            if [ -z "$main_interface" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') 请输入一个有效的接口名称。"| tee -a "$LOG_FILE"
            elif ip link show "$main_interface" > /dev/null 2>&1; then
                break
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') 无效的接口，请重新选择。"| tee -a "$LOG_FILE"
            fi
        done
    else
        read -p "检测到的主要网络接口是: $main_interface, 按Enter使用此接口，或输入新的接口名称: " new_interface
        if [ -n "$new_interface" ]; then
            if ip link show "$new_interface" > /dev/null 2>&1; then
                main_interface=$new_interface
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') 输入的接口无效，将使用检测到的接口: $main_interface"| tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    echo $main_interface| tee -a "$LOG_FILE"
}

# 初始配置函数
echo "开始初始化配置"| tee -a "$LOG_FILE"
initial_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 正在检测主要网络接口..."| tee -a "$LOG_FILE"
    MAIN_INTERFACE=$(get_main_interface)

    echo "$(date '+%Y-%m-%d %H:%M:%S') 请选择流量统计模式："| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 1. 只计算出站流量"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 2. 只计算进站流量"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 3. 出进站流量都计算"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 4. 出站和进站流量只取大"| tee -a "$LOG_FILE"
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
                date -d "${current_year}-${current_month}-${PERIOD_START_DAY} -1 month" +'%Y-%m-%d'
            else
                date -d "${current_year}-${current_month}-${PERIOD_START_DAY}" +%Y-%m-%d 2>/dev/null || date -d "${current_year}-${current_month}-01" +%Y-%m-%d
            fi
            ;;
        quarterly)
            local quarter_month=$(((($(date +%m) - 1) / 3) * 3 + 1))
            if [ $(date +%d) -lt $PERIOD_START_DAY ] || [ $(date +%m) -eq $quarter_month ]; then
                date -d "${current_year}-${quarter_month}-${PERIOD_START_DAY} -3 month" +'%Y-%m-%d'
            else
                date -d "${current_year}-${quarter_month}-${PERIOD_START_DAY}" +'%Y-%m-%d' 2>/dev/null || date -d "${current_year}-${quarter_month}-01" +%Y-%m-%d
            fi
            ;;
        yearly)
            if [ $(date +%d) -lt $PERIOD_START_DAY ] || [ $(date +%m) -eq 01 ]; then
                date -d "${current_year}-01-${PERIOD_START_DAY} -1 year" +'%Y-%m-%d'
            else
                date -d "${current_year}-01-${PERIOD_START_DAY}" +'%Y-%m-%d' 2>/dev/null || date -d "${current_year}-01-01" +%Y-%m-%d
            fi
            ;;
    esac
}

# 获取周期结束日期
get_period_end_date() {
    local current_date=$(date +%Y-%m-%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    
    case $TRAFFIC_PERIOD in
        monthly)
            if [ $(date +%d) -lt $PERIOD_START_DAY ]; then
                date -d "${current_year}-${current_month}-${PERIOD_START_DAY} -1 day" +'%Y-%m-%d'
            else
                date -d "${current_year}-${current_month}-${PERIOD_START_DAY} +1 month -1 day" +'%Y-%m-%d'
            fi
            ;;
        quarterly)
            local quarter_month=$(((($(date +%m) - 1) / 3) * 3 + 1))
            if [ $(date +%d) -lt $PERIOD_START_DAY ] || [ $(date +%m) -eq $quarter_month ]; then
                date -d "${current_year}-${quarter_month}-${PERIOD_START_DAY} +2 month -1 day" +'%Y-%m-%d'
            else
                date -d "${current_year}-${quarter_month}-${PERIOD_START_DAY} +5 month -1 day" +'%Y-%m-%d'
            fi
            ;;
        yearly)
            if [ $(date +%d) -lt $PERIOD_START_DAY ] || [ $(date +%m) -eq 01 ]; then
                date -d "${current_year}-12-31" +'%Y-%m-%d'
            else
                date -d "$((current_year + 1))-12-31" +'%Y-%m-%d'
            fi
            ;;
    esac
}

# 获取流量使用情况
get_traffic_usage() {
    local start_date=$(get_period_start_date)
    local end_date=$(get_period_end_date)  # 新增函数来获取周期结束日期
    
    echo "Debug: Start date: $start_date, End date: $end_date" >&2
    
    local vnstat_output=$(vnstat -i $MAIN_INTERFACE --begin "$start_date" --end "$end_date" --oneline b)
    echo "Debug: vnstat output: $vnstat_output" >&2
    
    case $TRAFFIC_MODE in
        out)
            local usage=$(echo "$vnstat_output" | cut -d';' -f12)
            ;;
        in)
            local usage=$(echo "$vnstat_output" | cut -d';' -f11)
            ;;
        total)
            local usage=$(echo "$vnstat_output" | cut -d';' -f13)
            ;;
        max)
            local rx=$(echo "$vnstat_output" | cut -d';' -f11)
            local tx=$(echo "$vnstat_output" | cut -d';' -f12)
            usage=$(echo "$rx $tx" | tr ' ' '\n' | sort -rn | head -n1)
            ;;
    esac
    
    echo "Debug: Raw usage value: $usage" >&2
    if [ -n "$usage" ]; then
        # 将字节转换为 GiB
        usage=$(echo "scale=3; $usage / 1024 / 1024 / 1024" | bc)
        echo "Debug: Usage in GiB: $usage" >&2
        echo $usage
    else
        echo "Debug: Unable to get usage data" >&2
        echo "0"
    fi
}


# 检查并限制流量
check_and_limit_traffic() {
    local current_usage=$(get_traffic_usage)
    local limit_threshold=$(echo "$TRAFFIC_LIMIT - $TRAFFIC_TOLERANCE" | bc)
    
    echo "当前使用流量: $current_usage GB，限制流量: $limit_threshold GB" | tee -a "$LOG_FILE"
    
    if (( $(echo "$current_usage > $limit_threshold" | bc -l) )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量超出限制，开始限速" | tee -a "$LOG_FILE"
        tc qdisc add dev $MAIN_INTERFACE root tbf rate ${LIMIT_SPEED}kbit burst 32kbit latency 400ms
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量正常，清除所有限制" | tee -a "$LOG_FILE"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}


# 检查是否需要重置限制
check_reset_limit() {
    local current_date=$(date +%Y-%m-%d)
    local period_start=$(get_period_start_date)
    
    if [[ "$current_date" == "$period_start" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 新的流量周期开始，重置限制"| tee -a "$LOG_FILE"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}

# 设置crontab
setup_crontab() {
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH") | crontab -
    echo "* * * * * $SCRIPT_PATH --run" | crontab -
    echo "$(date '+%Y-%m-%d %H:%M:%S') Crontab 已设置，每分钟运行一次"| tee -a "$LOG_FILE"
}


# 主函数
main() {
    # 首先检查并安装必要的软件包
    check_and_install_packages

    # 检查配置
    if check_existing_setup; then
        read_config
        while true; do
            # 清空输入缓冲区
            read -n 1 -s -r -p ""
            read -p "是否需要修改配置？(y/n): " modify_config
            case $modify_config in
                [Yy]*)
                    echo "$(date '+%Y-%m-%d %H:%M:%S') 开始修改配置..." | tee -a "$LOG_FILE"
                    initial_config
                    setup_crontab
                    echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已更新，脚本将每分钟自动运行一次" | tee -a "$LOG_FILE"
                    break
                    ;;
                [Nn]*)
                    echo "$(date '+%Y-%m-%d %H:%M:%S') 保持现有配置。" | tee -a "$LOG_FILE"
                    break
                    ;;
                *)
                    echo "$(date '+%Y-%m-%d %H:%M:%S') 无效输入，请输入 y 或 n。" | tee -a "$LOG_FILE"
                    ;;
            esac
        done
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 开始初始化配置..." | tee -a "$LOG_FILE"
        initial_config
        setup_crontab
        echo "$(date '+%Y-%m-%d %H:%M:%S') 初始配置完成，脚本将每分钟自动运行一次" | tee -a "$LOG_FILE"
    fi

    # 显示当前配置
    echo "$(date '+%Y-%m-%d %H:%M:%S') 当前配置：" | tee -a "$LOG_FILE"
    show_current_config

    # 显示当前流量使用情况和限制状态
    if read_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 当前流量使用情况：" | tee -a "$LOG_FILE"
        local current_usage=$(get_traffic_usage)
        echo "Debug: Current usage from get_traffic_usage: $current_usage" | tee -a "$LOG_FILE"
        if [ "$current_usage" != "0" ]; then
            local start_date=$(get_period_start_date)
            echo "当前统计周期: $TRAFFIC_PERIOD (从 $start_date 开始)" | tee -a "$LOG_FILE"
            echo "统计模式: $TRAFFIC_MODE" | tee -a "$LOG_FILE"
            echo "当前使用流量: $current_usage GB" | tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 检查并限制流量：" | tee -a "$LOG_FILE"
            check_and_limit_traffic
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 无法获取流量数据，请检查 vnstat 配置" | tee -a "$LOG_FILE"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件读取失败，请检查配置" | tee -a "$LOG_FILE"
    fi

    if [ "\$1" = "--run" ]; then
        echo "正在以自动化模式运行" | tee -a "$LOG_FILE"
        if read_config; then
            check_reset_limit
            check_and_limit_traffic
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件读取失败，请检查配置" | tee -a "$LOG_FILE"
        fi
    fi
}


# 执行主函数
main "$@"

# 在脚本结束处添加
trap 'rm -f "$LOCK_FILE"' EXIT

echo "-----------------------------------------------------"| tee -a "$LOG_FILE"
