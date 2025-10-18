#!/bin/bash

# Port Traffic Limit - 端口流量限制脚本
# 版本 1.0
# 功能：为指定端口设置流量限制

WORK_DIR="/root/TrafficCop"
PORT_CONFIG_FILE="$WORK_DIR/port_traffic_config.txt"
MACHINE_CONFIG_FILE="$WORK_DIR/traffic_monitor_config.txt"
PORT_LOG_FILE="$WORK_DIR/port_traffic_monitor.log"
PORT_SCRIPT_PATH="$WORK_DIR/port_traffic_monitor.sh"
PORT_LOCK_FILE="$WORK_DIR/port_traffic_monitor.lock"

# 设置时区为上海（东八区）
export TZ='Asia/Shanghai'

echo "-----------------------------------------------------" | tee -a "$PORT_LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') Port Traffic Limit 版本：1.0.0" | tee -a "$PORT_LOG_FILE"

# 检查是否已安装必要工具
check_required_tools() {
    local tools=("iptables" "bc" "vnstat")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 缺少必要工具: ${missing_tools[*]}" | tee -a "$PORT_LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 请先运行主流量监控脚本安装依赖" | tee -a "$PORT_LOG_FILE"
        return 1
    fi
    return 0
}

# 读取机器配置
read_machine_config() {
    if [ -f "$MACHINE_CONFIG_FILE" ]; then
        source "$MACHINE_CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# 读取端口配置
read_port_config() {
    if [ -f "$PORT_CONFIG_FILE" ]; then
        source "$PORT_CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# 写入端口配置
write_port_config() {
    cat > "$PORT_CONFIG_FILE" << EOF
PORT=$PORT
PORT_TRAFFIC_LIMIT=$PORT_TRAFFIC_LIMIT
PORT_TRAFFIC_TOLERANCE=$PORT_TRAFFIC_TOLERANCE
PORT_TRAFFIC_MODE=${PORT_TRAFFIC_MODE:-$TRAFFIC_MODE}
PORT_TRAFFIC_PERIOD=${PORT_TRAFFIC_PERIOD:-$TRAFFIC_PERIOD}
PORT_PERIOD_START_DAY=${PORT_PERIOD_START_DAY:-${PERIOD_START_DAY:-1}}
PORT_LIMIT_SPEED=${PORT_LIMIT_SPEED:-${LIMIT_SPEED:-20}}
PORT_MAIN_INTERFACE=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
PORT_LIMIT_MODE=${PORT_LIMIT_MODE:-$LIMIT_MODE}
EOF
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口配置已更新" | tee -a "$PORT_LOG_FILE"
}

# 显示当前端口配置
show_port_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 当前端口配置:" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口号: $PORT" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口流量限制: $PORT_TRAFFIC_LIMIT GB" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 容错范围: $PORT_TRAFFIC_TOLERANCE GB" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计模式: ${PORT_TRAFFIC_MODE:-$TRAFFIC_MODE}" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计周期: ${PORT_TRAFFIC_PERIOD:-$TRAFFIC_PERIOD}" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 周期起始日: ${PORT_PERIOD_START_DAY:-${PERIOD_START_DAY:-1}}" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 限速: ${PORT_LIMIT_SPEED:-${LIMIT_SPEED:-20}} kbit/s" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 网络接口: ${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}" | tee -a "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 限制模式: ${PORT_LIMIT_MODE:-$LIMIT_MODE}" | tee -a "$PORT_LOG_FILE"
}

# 初始化 iptables 规则用于流量统计
init_iptables_rules() {
    local port=$1
    local interface=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
    
    # 检查规则是否已存在
    if ! iptables -L INPUT -v -n | grep -q "dpt:$port"; then
        # 入站流量统计
        iptables -I INPUT -i "$interface" -p tcp --dport "$port" -j ACCEPT
        iptables -I INPUT -i "$interface" -p udp --dport "$port" -j ACCEPT
    fi
    
    if ! iptables -L OUTPUT -v -n | grep -q "spt:$port"; then
        # 出站流量统计
        iptables -I OUTPUT -o "$interface" -p tcp --sport "$port" -j ACCEPT
        iptables -I OUTPUT -o "$interface" -p udp --sport "$port" -j ACCEPT
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') iptables 规则已初始化，端口: $port" | tee -a "$PORT_LOG_FILE"
}

# 获取端口流量使用情况（使用iptables统计）
get_port_traffic_usage() {
    local port=$1
    local interface=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
    local traffic_mode=${PORT_TRAFFIC_MODE:-$TRAFFIC_MODE}
    
    # 获取入站和出站字节数
    local rx_bytes=$(iptables -L INPUT -v -n -x | grep "dpt:$port" | awk '{sum+=$2} END {print sum+0}')
    local tx_bytes=$(iptables -L OUTPUT -v -n -x | grep "spt:$port" | awk '{sum+=$2} END {print sum+0}')
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port - RX: $rx_bytes bytes, TX: $tx_bytes bytes" >> "$PORT_LOG_FILE"
    
    local usage_bytes
    case $traffic_mode in
        out)
            usage_bytes=$tx_bytes
            ;;
        in)
            usage_bytes=$rx_bytes
            ;;
        total)
            usage_bytes=$((rx_bytes + tx_bytes))
            ;;
        max)
            usage_bytes=$(echo "$rx_bytes $tx_bytes" | tr ' ' '\n' | sort -rn | head -n1)
            ;;
        *)
            usage_bytes=$((rx_bytes + tx_bytes))
            ;;
    esac
    
    # 转换为GB
    if [ -n "$usage_bytes" ] && [ "$usage_bytes" -gt 0 ]; then
        local usage_gb=$(echo "scale=3; $usage_bytes/1024/1024/1024" | bc)
        echo $usage_gb
    else
        echo "0.000"
    fi
}

# 重置端口流量统计
reset_port_traffic_stats() {
    local port=$1
    local interface=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
    
    # 删除并重新创建规则以重置计数器
    iptables -D INPUT -i "$interface" -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D INPUT -i "$interface" -p udp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o "$interface" -p tcp --sport "$port" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o "$interface" -p udp --sport "$port" -j ACCEPT 2>/dev/null
    
    # 重新添加规则
    init_iptables_rules "$port"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 的流量统计已重置" | tee -a "$PORT_LOG_FILE"
}

# 检查并限制端口流量
check_and_limit_port_traffic() {
    local port=$PORT
    local current_usage=$(get_port_traffic_usage "$port")
    local limit_threshold=$(echo "$PORT_TRAFFIC_LIMIT - $PORT_TRAFFIC_TOLERANCE" | bc)
    local limit_mode=${PORT_LIMIT_MODE:-$LIMIT_MODE}
    local limit_speed=${PORT_LIMIT_SPEED:-${LIMIT_SPEED:-20}}
    local interface=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 当前使用流量: $current_usage GB，限制流量: $limit_threshold GB" | tee -a "$PORT_LOG_FILE"
    
    if (( $(echo "$current_usage > $limit_threshold" | bc -l) )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 流量超出限制" | tee -a "$PORT_LOG_FILE"
        
        if [ "$limit_mode" = "tc" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 使用 TC 模式限制端口 $port 速度" | tee -a "$PORT_LOG_FILE"
            
            # 使用 tc + iptables 标记流量并限速
            # 添加 qdisc 根节点（如果不存在）
            if ! tc qdisc show dev "$interface" | grep -q "htb"; then
                tc qdisc add dev "$interface" root handle 1: htb default 30
                tc class add dev "$interface" parent 1: classid 1:1 htb rate 1000mbit
            fi
            
            # 为端口创建类和过滤器
            local class_id="1:$port"
            tc class add dev "$interface" parent 1:1 classid "$class_id" htb rate "${limit_speed}kbit" ceil "${limit_speed}kbit" 2>/dev/null
            tc qdisc add dev "$interface" parent "$class_id" handle "$port": sfq 2>/dev/null
            
            # 标记数据包
            iptables -t mangle -A POSTROUTING -o "$interface" -p tcp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
            iptables -t mangle -A POSTROUTING -o "$interface" -p udp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
            
            # 添加过滤器
            tc filter add dev "$interface" parent 1:0 protocol ip prio 1 handle "$port" fw flowid "$class_id" 2>/dev/null
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 已限速至 ${limit_speed}kbit/s" | tee -a "$PORT_LOG_FILE"
            
        elif [ "$limit_mode" = "shutdown" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 流量超限，将阻断该端口流量" | tee -a "$PORT_LOG_FILE"
            
            # 阻断端口流量
            iptables -I INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
            iptables -I INPUT -p udp --dport "$port" -j DROP 2>/dev/null
            iptables -I OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null
            iptables -I OUTPUT -p udp --sport "$port" -j DROP 2>/dev/null
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 已被阻断" | tee -a "$PORT_LOG_FILE"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 流量正常" | tee -a "$PORT_LOG_FILE"
        
        # 清除可能存在的限制
        if [ "$limit_mode" = "tc" ]; then
            local class_id="1:$port"
            tc filter del dev "$interface" parent 1:0 prio 1 handle "$port" fw 2>/dev/null
            tc qdisc del dev "$interface" parent "$class_id" handle "$port": 2>/dev/null
            tc class del dev "$interface" parent 1:1 classid "$class_id" 2>/dev/null
            
            iptables -t mangle -D POSTROUTING -o "$interface" -p tcp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
            iptables -t mangle -D POSTROUTING -o "$interface" -p udp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
        elif [ "$limit_mode" = "shutdown" ]; then
            # 解除端口阻断
            iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
            iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null
            iptables -D OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null
            iptables -D OUTPUT -p udp --sport "$port" -j DROP 2>/dev/null
        fi
    fi
}

# 获取周期起始日期
get_period_start_date() {
    local period=${PORT_TRAFFIC_PERIOD:-$TRAFFIC_PERIOD}
    local start_day=${PORT_PERIOD_START_DAY:-${PERIOD_START_DAY:-1}}
    local current_date=$(date +%Y-%m-%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    
    case $period in
        monthly)
            if [ $(date +%d) -lt $start_day ]; then
                date -d "${current_year}-${current_month}-${start_day} -1 month" +'%Y-%m-%d'
            else
                date -d "${current_year}-${current_month}-${start_day}" +%Y-%m-%d 2>/dev/null || date -d "${current_year}-${current_month}-01" +%Y-%m-%d
            fi
            ;;
        quarterly)
            local quarter_month=$(((($(date +%m) - 1) / 3) * 3 + 1))
            if [ $(date +%d) -lt $start_day ] || [ $(date +%m) -eq $quarter_month ]; then
                date -d "${current_year}-${quarter_month}-${start_day} -3 month" +'%Y-%m-%d'
            else
                date -d "${current_year}-${quarter_month}-${start_day}" +'%Y-%m-%d' 2>/dev/null || date -d "${current_year}-${quarter_month}-01" +%Y-%m-%d
            fi
            ;;
        yearly)
            if [ $(date +%d) -lt $start_day ] || [ $(date +%m) -eq 01 ]; then
                date -d "${current_year}-01-${start_day} -1 year" +'%Y-%m-%d'
            else
                date -d "${current_year}-01-${start_day}" +'%Y-%m-%d' 2>/dev/null || date -d "${current_year}-01-01" +%Y-%m-%d
            fi
            ;;
    esac
}

# 检查是否需要重置端口流量统计
check_reset_port_limit() {
    local current_date=$(date +%Y-%m-%d)
    local period_start=$(get_period_start_date)
    
    if [[ "$current_date" == "$period_start" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 新的流量周期开始，重置端口 $PORT 的流量统计" | tee -a "$PORT_LOG_FILE"
        reset_port_traffic_stats "$PORT"
    fi
}

# 端口配置向导
port_config_wizard() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 开始端口流量限制配置" | tee -a "$PORT_LOG_FILE"
    
    # 检查机器是否已限制流量
    local machine_limited=false
    if read_machine_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 检测到机器已配置流量限制" | tee -a "$PORT_LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 机器流量限制: $TRAFFIC_LIMIT GB" | tee -a "$PORT_LOG_FILE"
        machine_limited=true
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 机器尚未配置流量限制" | tee -a "$PORT_LOG_FILE"
    fi
    
    # 输入端口号
    while true; do
        read -p "请输入要限制流量的端口号 (1-65535): " PORT
        if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            break
        else
            echo "无效的端口号，请重新输入"
        fi
    done
    
    # 输入端口流量限制
    while true; do
        read -p "请输入端口流量限制 (GB): " PORT_TRAFFIC_LIMIT
        if [[ "$PORT_TRAFFIC_LIMIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # 如果机器已限流，检查端口限流是否超过机器限流
            if [ "$machine_limited" = true ]; then
                if (( $(echo "$PORT_TRAFFIC_LIMIT > $TRAFFIC_LIMIT" | bc -l) )); then
                    echo "端口流量限制不能大于机器流量限制 ($TRAFFIC_LIMIT GB)"
                    echo "请重新输入"
                    continue
                fi
            fi
            break
        else
            echo "无效输入，请输入一个有效的数字"
        fi
    done
    
    # 输入容错范围
    while true; do
        read -p "请输入容错范围 (GB, 默认为 ${TRAFFIC_TOLERANCE:-5}): " PORT_TRAFFIC_TOLERANCE
        if [[ -z "$PORT_TRAFFIC_TOLERANCE" ]]; then
            PORT_TRAFFIC_TOLERANCE=${TRAFFIC_TOLERANCE:-5}
            break
        elif [[ "$PORT_TRAFFIC_TOLERANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo "无效输入，请输入一个有效的数字"
        fi
    done
    
    # 询问是否使用机器配置或自定义配置
    if [ "$machine_limited" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 是否使用机器的其他配置？" | tee -a "$PORT_LOG_FILE"
        echo "1. 使用机器配置（推荐）"
        echo "2. 自定义配置"
        read -p "请选择 (1-2, 默认为1): " config_choice
        
        if [[ "$config_choice" == "2" ]]; then
            # 自定义配置
            custom_port_config
        else
            # 使用机器配置
            PORT_TRAFFIC_MODE=$TRAFFIC_MODE
            PORT_TRAFFIC_PERIOD=$TRAFFIC_PERIOD
            PORT_PERIOD_START_DAY=${PERIOD_START_DAY:-1}
            PORT_LIMIT_SPEED=${LIMIT_SPEED:-20}
            PORT_MAIN_INTERFACE=$MAIN_INTERFACE
            PORT_LIMIT_MODE=$LIMIT_MODE
            echo "$(date '+%Y-%m-%d %H:%M:%S') 已同步机器配置" | tee -a "$PORT_LOG_FILE"
        fi
    else
        # 机器未限流，需要自定义配置，并同步到机器配置
        echo "$(date '+%Y-%m-%d %H:%M:%S') 机器尚未配置，将创建新配置" | tee -a "$PORT_LOG_FILE"
        custom_port_config
        
        # 询问是否同步到机器配置
        read -p "是否将此配置同步到机器流量限制？(y/n, 默认为y): " sync_choice
        if [[ -z "$sync_choice" || "$sync_choice" == "y" || "$sync_choice" == "Y" ]]; then
            sync_to_machine_config
        fi
    fi
    
    # 保存配置
    write_port_config
    
    # 初始化 iptables 规则
    init_iptables_rules "$PORT"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口流量限制配置完成" | tee -a "$PORT_LOG_FILE"
}

# 自定义端口配置
custom_port_config() {
    # 流量统计模式
    while true; do
        echo "请选择流量统计模式："
        echo "1. 只计算出站流量"
        echo "2. 只计算进站流量"
        echo "3. 出进站流量都计算"
        echo "4. 出站和进站流量只取大"
        read -p "请输入选择 (1-4): " mode_choice
        case $mode_choice in
            1) PORT_TRAFFIC_MODE="out"; break ;;
            2) PORT_TRAFFIC_MODE="in"; break ;;
            3) PORT_TRAFFIC_MODE="total"; break ;;
            4) PORT_TRAFFIC_MODE="max"; break ;;
            *) echo "无效输入，请重新选择" ;;
        esac
    done
    
    # 流量统计周期
    read -p "请选择流量统计周期 (m/q/y，默认为m): " period_choice
    case $period_choice in
        q) PORT_TRAFFIC_PERIOD="quarterly" ;;
        y) PORT_TRAFFIC_PERIOD="yearly" ;;
        m|"") PORT_TRAFFIC_PERIOD="monthly" ;;
        *) echo "无效输入，使用默认值：monthly"; PORT_TRAFFIC_PERIOD="monthly" ;;
    esac
    
    # 周期起始日
    read -p "请输入周期起始日 (1-31，默认为1): " PORT_PERIOD_START_DAY
    if [[ -z "$PORT_PERIOD_START_DAY" ]]; then
        PORT_PERIOD_START_DAY=1
    elif ! [[ "$PORT_PERIOD_START_DAY" =~ ^[1-9]$|^[12][0-9]$|^3[01]$ ]]; then
        echo "无效输入，使用默认值：1"
        PORT_PERIOD_START_DAY=1
    fi
    
    # 限制模式
    while true; do
        echo "请选择限制模式："
        echo "1. TC 模式（限速）"
        echo "2. 阻断模式（完全阻断端口流量）"
        read -p "请输入选择 (1-2): " limit_mode_choice
        case $limit_mode_choice in
            1) 
                PORT_LIMIT_MODE="tc"
                read -p "请输入限速 (kbit/s，默认为20): " PORT_LIMIT_SPEED
                PORT_LIMIT_SPEED=${PORT_LIMIT_SPEED:-20}
                if ! [[ "$PORT_LIMIT_SPEED" =~ ^[0-9]+$ ]]; then
                    echo "无效输入，使用默认值：20 kbit/s"
                    PORT_LIMIT_SPEED=20
                fi
                break 
                ;;
            2) 
                PORT_LIMIT_MODE="shutdown"
                PORT_LIMIT_SPEED=""
                break 
                ;;
            *) echo "无效输入，请重新选择" ;;
        esac
    done
    
    # 网络接口
    local main_interface=$(ip route | grep default | sed -n 's/^default via [0-9.]* dev \([^ ]*\).*/\1/p' | head -n1)
    if [ -z "$main_interface" ]; then
        main_interface=$(ip link | grep 'state UP' | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p' | head -n1)
    fi
    
    read -p "网络接口 (默认为 $main_interface): " PORT_MAIN_INTERFACE
    PORT_MAIN_INTERFACE=${PORT_MAIN_INTERFACE:-$main_interface}
}

# 同步配置到机器
sync_to_machine_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 正在同步配置到机器..." | tee -a "$PORT_LOG_FILE"
    
    cat > "$MACHINE_CONFIG_FILE" << EOF
TRAFFIC_MODE=${PORT_TRAFFIC_MODE}
TRAFFIC_PERIOD=${PORT_TRAFFIC_PERIOD}
TRAFFIC_LIMIT=${PORT_TRAFFIC_LIMIT}
TRAFFIC_TOLERANCE=${PORT_TRAFFIC_TOLERANCE}
PERIOD_START_DAY=${PORT_PERIOD_START_DAY}
LIMIT_SPEED=${PORT_LIMIT_SPEED}
MAIN_INTERFACE=${PORT_MAIN_INTERFACE}
LIMIT_MODE=${PORT_LIMIT_MODE}
EOF
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已同步到机器" | tee -a "$PORT_LOG_FILE"
}

# 设置定时任务
setup_port_crontab() {
    # 删除旧的端口监控任务
    crontab -l 2>/dev/null | grep -v "$PORT_SCRIPT_PATH" | crontab -
    
    # 添加新的端口监控任务
    (crontab -l 2>/dev/null; echo "* * * * * $PORT_SCRIPT_PATH --run") | crontab -
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口监控定时任务已设置" | tee -a "$PORT_LOG_FILE"
}

# 移除端口流量限制
remove_port_limit() {
    if read_port_config; then
        local port=$PORT
        local interface=${PORT_MAIN_INTERFACE:-$MAIN_INTERFACE}
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') 正在移除端口 $port 的流量限制..." | tee -a "$PORT_LOG_FILE"
        
        # 清除 tc 限制
        local class_id="1:$port"
        tc filter del dev "$interface" parent 1:0 prio 1 handle "$port" fw 2>/dev/null
        tc qdisc del dev "$interface" parent "$class_id" handle "$port": 2>/dev/null
        tc class del dev "$interface" parent 1:1 classid "$class_id" 2>/dev/null
        
        # 清除 iptables mangle 规则
        iptables -t mangle -D POSTROUTING -o "$interface" -p tcp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
        iptables -t mangle -D POSTROUTING -o "$interface" -p udp --sport "$port" -j MARK --set-mark "$port" 2>/dev/null
        
        # 清除阻断规则
        iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null
        iptables -D OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null
        iptables -D OUTPUT -p udp --sport "$port" -j DROP 2>/dev/null
        
        # 清除流量统计规则
        iptables -D INPUT -i "$interface" -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -D INPUT -i "$interface" -p udp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -o "$interface" -p tcp --sport "$port" -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -o "$interface" -p udp --sport "$port" -j ACCEPT 2>/dev/null
        
        # 删除定时任务
        crontab -l 2>/dev/null | grep -v "$PORT_SCRIPT_PATH" | crontab -
        
        # 删除配置文件
        rm -f "$PORT_CONFIG_FILE"
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port 的流量限制已移除" | tee -a "$PORT_LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 未找到端口配置" | tee -a "$PORT_LOG_FILE"
    fi
}

# 主函数
main() {
    # 创建工作目录
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || exit 1
    
    # 检查必要工具
    if ! check_required_tools; then
        exit 1
    fi
    
    # 如果是自动运行模式
    if [ "$1" = "--run" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 正在以自动化模式运行端口监控" | tee -a "$PORT_LOG_FILE"
        
        # 尝试获取文件锁
        exec 9>"${PORT_LOCK_FILE}"
        if ! flock -n 9; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 另一个端口监控实例正在运行，退出" | tee -a "$PORT_LOG_FILE"
            exit 1
        fi
        
        if read_port_config && read_machine_config; then
            check_reset_port_limit
            check_and_limit_port_traffic
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件读取失败" | tee -a "$PORT_LOG_FILE"
        fi
        
        # 释放锁
        flock -u 9
        return
    fi
    
    # 如果是移除模式
    if [ "$1" = "--remove" ]; then
        remove_port_limit
        return
    fi
    
    # 交互式配置模式
    echo "$(date '+%Y-%m-%d %H:%M:%S') ===== Port Traffic Limit 端口流量限制 =====" | tee -a "$PORT_LOG_FILE"
    
    # 检查是否已有配置
    if read_port_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 检测到已有端口配置" | tee -a "$PORT_LOG_FILE"
        show_port_config
        
        read -p "是否要修改配置？(y/n): " modify_choice
        if [[ "$modify_choice" == "y" || "$modify_choice" == "Y" ]]; then
            port_config_wizard
        fi
    else
        # 新配置
        port_config_wizard
    fi
    
    # 复制脚本到工作目录（用于定时任务）
    if [ "$(realpath "$0")" != "$PORT_SCRIPT_PATH" ]; then
        cp "$0" "$PORT_SCRIPT_PATH"
        chmod +x "$PORT_SCRIPT_PATH"
    fi
    
    # 设置定时任务
    setup_port_crontab
    
    # 显示当前流量使用情况
    if read_port_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ========== 当前端口流量使用情况 ==========" | tee -a "$PORT_LOG_FILE"
        local current_usage=$(get_port_traffic_usage "$PORT")
        echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $PORT 当前使用流量: $current_usage GB" | tee -a "$PORT_LOG_FILE"
        check_and_limit_port_traffic
    fi
    
    echo "-----------------------------------------------------" | tee -a "$PORT_LOG_FILE"
}

# 执行主函数
main "$@"
