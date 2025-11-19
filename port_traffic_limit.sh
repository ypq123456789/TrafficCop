#!/bin/bash

# Port Traffic Limit - 端口流量限制脚本 v3.0
# 功能：为多个端口设置独立的流量限制（支持JSON配置）
# 最后更新：2025-10-19 03:30

SCRIPT_VERSION="3.0"
LAST_UPDATE="2025-10-19 03:30"

# 设置 PATH 确保 cron 环境能找到所有命令
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORK_DIR="/root/TrafficCop"
PORT_CONFIG_FILE="$WORK_DIR/ports_traffic_config.json"
MACHINE_CONFIG_FILE="$WORK_DIR/traffic_monitor_config.txt"
PORT_LOG_FILE="$WORK_DIR/port_traffic_monitor.log"
PORT_SCRIPT_PATH="$WORK_DIR/port_traffic_limit.sh"

# 设置时区为上海（东八区）
export TZ='Asia/Shanghai'

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 只在交互模式下显示版本信息（cron模式在cron_mode函数中单独记录）
if [ "$1" != "--cron" ]; then
    echo "-----------------------------------------------------"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Port Traffic Limit v${SCRIPT_VERSION} (最后更新: ${LAST_UPDATE})"
fi

# 检查并安装jq
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}jq未安装，正在安装...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y jq
        elif [ -f /etc/redhat-release ]; then
            yum install -y jq
        else
            echo -e "${RED}无法自动安装jq，请手动安装${NC}"
            return 1
        fi
    fi
    return 0
}

# 检查必要工具
check_required_tools() {
    local tools=("iptables" "bc")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}缺少必要工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}请先运行主流量监控脚本安装依赖${NC}"
        return 1
    fi
    
    check_and_install_jq
    return $?
}

# 初始化JSON配置文件
init_config_file() {
    if [ ! -f "$PORT_CONFIG_FILE" ]; then
        echo '{"ports":[]}' > "$PORT_CONFIG_FILE"
        echo -e "${GREEN}已创建配置文件: $PORT_CONFIG_FILE${NC}"
    fi
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

# 获取端口配置
get_port_config() {
    local port=$1
    if [ -f "$PORT_CONFIG_FILE" ]; then
        jq -r ".ports[] | select(.port == $port)" "$PORT_CONFIG_FILE"
    fi
}

# 检查端口是否已配置
port_exists() {
    local port=$1
    local count=$(jq -r ".ports[] | select(.port == $port) | .port" "$PORT_CONFIG_FILE" 2>/dev/null | wc -l)
    [ "$count" -gt 0 ]
}

# 添加或更新端口配置
add_port_config() {
    local port=$1
    local description=$2
    local traffic_limit=$3
    local traffic_tolerance=$4
    local traffic_mode=$5
    local traffic_period=$6
    local period_start_day=$7
    local limit_speed=$8
    local main_interface=$9
    local limit_mode=${10}
    local created_at=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 删除旧配置（如果存在）
    local temp_file=$(mktemp)
    jq "del(.ports[] | select(.port == $port))" "$PORT_CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$PORT_CONFIG_FILE"
    
    # 添加新配置
    local new_port=$(cat <<EOF
{
  "port": $port,
  "description": "$description",
  "traffic_limit": $traffic_limit,
  "traffic_tolerance": $traffic_tolerance,
  "traffic_mode": "$traffic_mode",
  "traffic_period": "$traffic_period",
  "period_start_day": $period_start_day,
  "limit_speed": $limit_speed,
  "main_interface": "$main_interface",
  "limit_mode": "$limit_mode",
  "created_at": "$created_at",
  "last_reset": "$(date '+%Y-%m-%d')"
}
EOF
)
    
    jq ".ports += [$new_port]" "$PORT_CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$PORT_CONFIG_FILE"
    
    echo -e "${GREEN}端口 $port 配置已保存${NC}"
}

# 删除端口配置
delete_port_config() {
    local port=$1
    local temp_file=$(mktemp)
    jq "del(.ports[] | select(.port == $port))" "$PORT_CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$PORT_CONFIG_FILE"
    echo -e "${GREEN}端口 $port 配置已删除${NC}"
}

# 列出所有端口
list_all_ports() {
    clear
    echo -e "${CYAN}==================== 已配置的端口 ====================${NC}"
    if [ ! -f "$PORT_CONFIG_FILE" ] || [ "$(jq -r '.ports | length' "$PORT_CONFIG_FILE")" -eq 0 ]; then
        echo -e "${YELLOW}暂无配置的端口${NC}"
        return 1
    fi
    
    local index=1
    local total=$(jq -r '.ports | length' "$PORT_CONFIG_FILE")
    
    for ((i=0; i<total; i++)); do
        local port=$(jq -r ".ports[$i].port" "$PORT_CONFIG_FILE")
        local desc=$(jq -r ".ports[$i].description" "$PORT_CONFIG_FILE")
        local limit=$(jq -r ".ports[$i].traffic_limit" "$PORT_CONFIG_FILE")
        local tolerance=$(jq -r ".ports[$i].traffic_tolerance" "$PORT_CONFIG_FILE")
        local mode=$(jq -r ".ports[$i].limit_mode" "$PORT_CONFIG_FILE")
        
        echo -e "  ${GREEN}[$index]${NC} 端口 $port ($desc) - 限制: ${limit}GB, 容错: ${tolerance}GB, 模式: $mode"
        index=$((index + 1))
    done
    
    echo -e "${CYAN}====================================================${NC}"
    return 0
}

# 初始化iptables规则
init_iptables_rules() {
    local port=$1
    local interface=$2
    
    # 检查并添加INPUT规则
    if ! iptables -L INPUT -v -n | grep -q "dpt:$port"; then
        iptables -I INPUT -i "$interface" -p tcp --dport "$port" -j ACCEPT
        iptables -I INPUT -i "$interface" -p udp --dport "$port" -j ACCEPT
    fi
    
    # 检查并添加OUTPUT规则
    if ! iptables -L OUTPUT -v -n | grep -q "spt:$port"; then
        iptables -I OUTPUT -o "$interface" -p tcp --sport "$port" -j ACCEPT
        iptables -I OUTPUT -o "$interface" -p udp --sport "$port" -j ACCEPT
    fi
    
    echo -e "${GREEN}iptables规则已初始化（端口 $port）${NC}"
}

# 获取端口流量使用量
get_port_traffic_usage() {
    local port=$1
    local interface=$2
    
    # 获取入站流量（字节）- 优先检查UFW链，如果不存在则检查标准链
    local in_bytes=$(iptables -L ufw-user-input -v -n -x 2>/dev/null | grep "dpt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
    if [ -z "$in_bytes" ] || [ "$in_bytes" = "0" ]; then
        in_bytes=$(iptables -L INPUT -v -n -x | grep "dpt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
    fi
    
    # 获取出站流量（字节）- 优先检查UFW链，如果不存在则检查标准链
    local out_bytes=$(iptables -L ufw-user-output -v -n -x 2>/dev/null | grep "spt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
    if [ -z "$out_bytes" ] || [ "$out_bytes" = "0" ]; then
        out_bytes=$(iptables -L OUTPUT -v -n -x | grep "spt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
    fi
    
    # 转换为GB（使用printf格式化，确保显示前导零）
    # 使用 bc 时屏蔽 stderr 并在出错时返回 0，保证不会打印 (standard_in) 1: syntax error
    local in_gb=$(printf "%.2f" $(echo "scale=2; $in_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0"))
    local out_gb=$(printf "%.2f" $(echo "scale=2; $out_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0"))
    local total_gb=$(printf "%.2f" $(echo "scale=2; $in_gb + $out_gb" | bc 2>/dev/null || echo "0"))
    
    echo "$in_gb,$out_gb,$total_gb"
}

# 应用TC限速
apply_tc_limit() {
    local port=$1
    local interface=$2
    local speed=$3
    
    # 检查是否已有根qdisc
    if ! tc qdisc show dev "$interface" | grep -q "htb"; then
        tc qdisc add dev "$interface" root handle 1: htb default 30
    fi
    
    # 为端口创建class和filter
    local class_id="1:$port"
    tc class add dev "$interface" parent 1: classid "$class_id" htb rate "${speed}kbit"
    tc filter add dev "$interface" protocol ip parent 1:0 prio 1 u32 match ip sport "$port" 0xffff flowid "$class_id"
    tc filter add dev "$interface" protocol ip parent 1:0 prio 1 u32 match ip dport "$port" 0xffff flowid "$class_id"
    
    echo -e "${GREEN}TC限速已应用（端口 $port: ${speed}kbit/s）${NC}"
}

# 移除TC限速
remove_tc_limit() {
    local port=$1
    local interface=$2
    
    tc filter del dev "$interface" prio 1 2>/dev/null
    tc class del dev "$interface" classid "1:$port" 2>/dev/null
    
    echo -e "${GREEN}TC限速已移除（端口 $port）${NC}"
}

# 阻断端口
block_port() {
    local port=$1
    
    iptables -I INPUT -p tcp --dport "$port" -j DROP
    iptables -I INPUT -p udp --dport "$port" -j DROP
    iptables -I OUTPUT -p tcp --sport "$port" -j DROP
    iptables -I OUTPUT -p udp --sport "$port" -j DROP
    
    echo -e "${RED}端口 $port 已被阻断${NC}"
}

# 解除阻断
unblock_port() {
    local port=$1
    
    iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null
    iptables -D OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null
    iptables -D OUTPUT -p udp --sport "$port" -j DROP 2>/dev/null
    
    echo -e "${GREEN}端口 $port 阻断已解除${NC}"
}

# 检查并限制端口流量
check_and_limit_port_traffic() {
    local port=$1
    
    # 获取端口配置
    local config=$(get_port_config "$port")
    if [ -z "$config" ]; then
        return
    fi
    
    local traffic_limit=$(echo "$config" | jq -r '.traffic_limit')
    local traffic_tolerance=$(echo "$config" | jq -r '.traffic_tolerance')
    local traffic_mode=$(echo "$config" | jq -r '.traffic_mode')
    local limit_mode=$(echo "$config" | jq -r '.limit_mode')
    local limit_speed=$(echo "$config" | jq -r '.limit_speed')
    local interface=$(echo "$config" | jq -r '.main_interface')
    
    # 获取流量使用
    local usage=$(get_port_traffic_usage "$port" "$interface")
    local in_gb=$(echo "$usage" | cut -d',' -f1)
    local out_gb=$(echo "$usage" | cut -d',' -f2)
    local total_gb=$(echo "$usage" | cut -d',' -f3)
    
    # 根据模式选择流量值
    local current_usage
    case "$traffic_mode" in
        "outbound") current_usage=$out_gb ;;
        "inbound") current_usage=$in_gb ;;
        "total") current_usage=$total_gb ;;
        "max") current_usage=$(echo "$in_gb $out_gb" | awk '{print ($1>$2)?$1:$2}') ;;
        *) current_usage=$total_gb ;;
    esac
    
    # 计算触发阈值和使用率
    # 计算触发阈值和使用率，屏蔽 bc stderr 并提供默认值
    local trigger_limit=$(echo "scale=2; $traffic_limit - $traffic_tolerance" | bc 2>/dev/null || echo "0")
    local usage_percentage=0
    if (( $(echo "$traffic_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
        usage_percentage=$(echo "scale=1; ($current_usage / $traffic_limit) * 100" | bc 2>/dev/null || echo "0")
    fi
    
    # 详细记录每个端口的流量信息（入站/出站/总计）
    echo "$(date '+%Y-%m-%d %H:%M:%S') 端口 $port: 入站=${in_gb}GB, 出站=${out_gb}GB, 总计=${total_gb}GB, 当前=${current_usage}GB, 限制=${traffic_limit}GB (${usage_percentage}%)" >> "$PORT_LOG_FILE"
    
    # 检查是否超限
    if (( $(echo "$current_usage >= $trigger_limit" | bc -l 2>/dev/null || echo "0") )); then
        if [ "$limit_mode" = "tc" ]; then
            apply_tc_limit "$port" "$interface" "$limit_speed"
            echo "$(date '+%Y-%m-%d %H:%M:%S') [警告] 端口 $port 已触发TC限速（${current_usage}GB >= ${trigger_limit}GB）" >> "$PORT_LOG_FILE"
        else
            block_port "$port"
            echo "$(date '+%Y-%m-%d %H:%M:%S') [警告] 端口 $port 已被阻断（${current_usage}GB >= ${trigger_limit}GB）" >> "$PORT_LOG_FILE"
        fi
    fi
}

# 端口配置向导
port_config_wizard() {
    clear
    echo -e "${CYAN}==================== 端口配置向导 ====================${NC}"
    echo -e "${YELLOW}提示：所有选项可直接回车使用默认值${NC}"
    echo ""
    
    # 输入端口号
    while true; do
        read -p "请输入端口号 (1-65535): " port
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            break
        else
            echo -e "${RED}无效的端口号，请重新输入${NC}"
        fi
    done
    
    # 检查端口是否已存在
    if port_exists "$port"; then
        echo -e "${YELLOW}端口 $port 已存在配置${NC}"
        read -p "是否要更新配置？[y/N]: " update_choice
        [ -z "$update_choice" ] && update_choice="n"
        if [[ "$update_choice" != "y" && "$update_choice" != "Y" ]]; then
            return
        fi
    fi
    
    # 端口描述
    read -p "端口描述 [回车=Port $port]: " description
    [ -z "$description" ] && description="Port $port"
    
    # 流量限制 - 智能默认
    if read_machine_config && [ -n "$TRAFFIC_LIMIT" ]; then
        default_limit="$TRAFFIC_LIMIT"
    else
        default_limit="100"
    fi
    
    while true; do
        read -p "流量限制(GB) [回车=${default_limit}]: " traffic_limit
        if [ -z "$traffic_limit" ]; then
            traffic_limit="$default_limit"
            break
        elif [[ "$traffic_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo -e "${RED}无效输入${NC}"
        fi
    done
    
    # 容错范围 - 智能默认
    if read_machine_config && [ -n "$TRAFFIC_TOLERANCE" ]; then
        default_tolerance="$TRAFFIC_TOLERANCE"
    else
        default_tolerance="10"
    fi
    
    while true; do
        read -p "容错范围(GB) [回车=${default_tolerance}]: " traffic_tolerance
        if [ -z "$traffic_tolerance" ]; then
            traffic_tolerance="$default_tolerance"
            break
        elif [[ "$traffic_tolerance" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo -e "${RED}无效输入${NC}"
        fi
    done
    
    # 配置方式选择
    echo ""
    echo -e "${CYAN}配置方式：${NC}"
    echo "1) 同步机器总流量配置（推荐，回车默认）"
    echo "2) 自定义配置"
    read -p "选择 [回车=1]: " config_choice
    [ -z "$config_choice" ] && config_choice="1"
    
    if [ "$config_choice" = "1" ]; then
        # 同步机器配置
        if read_machine_config; then
            traffic_mode=${TRAFFIC_MODE:-"total"}
            traffic_period=${TRAFFIC_PERIOD:-"monthly"}
            period_start_day=${PERIOD_START_DAY:-1}
            # 端口限速独立设置，不受机器限速影响
            limit_speed=20
            main_interface=${MAIN_INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n1)}
            limit_mode=${LIMIT_MODE:-"tc"}
            
            echo -e "${GREEN}✓ 已同步机器总流量配置${NC}"
            echo -e "${CYAN}  统计模式: $traffic_mode | 周期: $traffic_period (每月${period_start_day}日起) | 限制模式: $limit_mode${NC}"
            if [ "$limit_mode" = "tc" ]; then
                echo -e "${CYAN}  限速值: ${limit_speed}kbit/s | 网络接口: $main_interface${NC}"
            else
                echo -e "${CYAN}  网络接口: $main_interface${NC}"
            fi
        else
            # 机器配置不存在，使用默认值
            traffic_mode="total"
            traffic_period="monthly"
            period_start_day=1
            limit_speed=20
            main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
            limit_mode="tc"
            
            echo -e "${YELLOW}! 未找到机器配置，使用默认配置${NC}"
            echo -e "${CYAN}  统计模式: total | 周期: monthly (每月1日起) | 限制模式: tc${NC}"
            echo -e "${CYAN}  限速值: 20kbit/s | 网络接口: $main_interface${NC}"
        fi
    else
        # 自定义配置
        echo ""
        echo -e "${CYAN}流量统计模式：${NC}"
        echo "1) total - 入站+出站（默认）"
        echo "2) outbound - 仅出站"
        echo "3) inbound - 仅入站"
        echo "4) max - 取最大值"
        read -p "请选择 [默认: 1]: " mode_choice
        [ -z "$mode_choice" ] && mode_choice="1"
        case $mode_choice in
            1) traffic_mode="total" ;;
            2) traffic_mode="outbound" ;;
            3) traffic_mode="inbound" ;;
            4) traffic_mode="max" ;;
            *) traffic_mode="total" ;;
        esac
        
        echo ""
        echo -e "${CYAN}统计周期：${NC}"
        echo "1) monthly - 每月（默认）"
        echo "2) quarterly - 每季度"
        echo "3) yearly - 每年"
        read -p "请选择 [默认: 1]: " period_choice
        [ -z "$period_choice" ] && period_choice="1"
        case $period_choice in
            1) traffic_period="monthly" ;;
            2) traffic_period="quarterly" ;;
            3) traffic_period="yearly" ;;
            *) traffic_period="monthly" ;;
        esac
        
        read -p "周期起始日 (1-28) [默认: 1]: " period_start_day
        [ -z "$period_start_day" ] && period_start_day=1
        
        echo ""
        echo -e "${CYAN}限制模式：${NC}"
        echo "1) tc - 限速模式（默认）"
        echo "2) shutdown - 阻断模式"
        read -p "请选择 [默认: 1]: " limit_choice
        [ -z "$limit_choice" ] && limit_choice="1"
        if [ "$limit_choice" = "1" ]; then
            limit_mode="tc"
            read -p "限速值 (kbit/s) [默认: 20]: " limit_speed
            [ -z "$limit_speed" ] && limit_speed=20
        else
            limit_mode="shutdown"
            limit_speed=0
        fi
        
        # 获取网络接口
        main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
        echo -e "${GREEN}网络接口: $main_interface${NC}"
    fi
    
    # 保存配置
    echo ""
    echo -e "${CYAN}正在保存配置...${NC}"
    add_port_config "$port" "$description" "$traffic_limit" "$traffic_tolerance" \
        "$traffic_mode" "$traffic_period" "$period_start_day" "$limit_speed" \
        "$main_interface" "$limit_mode"
    
    # 初始化iptables规则
    init_iptables_rules "$port" "$main_interface"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ 端口 $port 配置完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    read -p "按回车键继续..." dummy
}

# 查看端口配置和流量
view_port_status() {
    clear
    if [ ! -f "$PORT_CONFIG_FILE" ] || [ "$(jq -r '.ports | length' "$PORT_CONFIG_FILE")" -eq 0 ]; then
        echo -e "${YELLOW}当前没有配置任何端口${NC}"
        echo ""
        read -p "按回车键继续..." dummy
        return
    fi
    
    echo -e "${CYAN}==================== 端口配置与流量状态 ====================${NC}"
    echo ""
    
    local index=1
    local total=$(jq -r '.ports | length' "$PORT_CONFIG_FILE")
    
    for ((i=0; i<total; i++)); do
        local port=$(jq -r ".ports[$i].port" "$PORT_CONFIG_FILE")
        local desc=$(jq -r ".ports[$i].description" "$PORT_CONFIG_FILE")
        local limit=$(jq -r ".ports[$i].traffic_limit" "$PORT_CONFIG_FILE")
        local tolerance=$(jq -r ".ports[$i].traffic_tolerance" "$PORT_CONFIG_FILE")
        local mode=$(jq -r ".ports[$i].limit_mode" "$PORT_CONFIG_FILE")
        local speed=$(jq -r ".ports[$i].limit_speed" "$PORT_CONFIG_FILE")
        local interface=$(jq -r ".ports[$i].main_interface" "$PORT_CONFIG_FILE")
        
        echo -e "${GREEN}[$index]${NC} ${GREEN}端口 $port${NC} - $desc"
        echo -e "    流量限制: ${YELLOW}${limit}GB${NC} (容错: ${tolerance}GB)"
        echo -e "    限制模式: $mode$([ "$mode" = "tc" ] && echo " (${speed}kbit/s)")"
        echo -e "    网络接口: $interface"
        
        # 获取当前流量
        local usage=$(get_port_traffic_usage "$port" "$interface")
        local total_gb=$(echo "$usage" | cut -d',' -f3)
        # 计算百分比时屏蔽 bc stderr 并提供默认值
        local percentage=$(echo "scale=1; $total_gb * 100 / $limit" | bc 2>/dev/null || echo "0")
        
        echo -e "    当前使用: ${CYAN}${total_gb}GB${NC} / ${limit}GB (${percentage}%)"
        
        # 状态图标
        if (( $(echo "$percentage >= 90" | bc -l 2>/dev/null || echo "0") )); then
            echo -e "    状态: ${RED}⚠️  接近限制${NC}"
        elif (( $(echo "$percentage >= 70" | bc -l 2>/dev/null || echo "0") )); then
            echo -e "    状态: ${YELLOW}🟡 需要关注${NC}"
        else
            echo -e "    状态: ${GREEN}✅ 正常${NC}"
        fi
        echo ""
        index=$((index + 1))
    done
    
    echo -e "${CYAN}==========================================================${NC}"
    echo ""
    read -p "按回车键继续..." dummy
}

# 修改端口配置
modify_port_config() {
    list_all_ports
    
    if [ ! -f "$PORT_CONFIG_FILE" ] || [ "$(jq -r '.ports | length' "$PORT_CONFIG_FILE")" -eq 0 ]; then
        echo ""
        read -p "按回车键继续..." dummy
        return
    fi
    
    echo ""
    echo -e "${YELLOW}提示：可输入序号或端口号${NC}"
    read -p "请选择 (序号/端口号): " mod_input
    
    local mod_port=""
    
    # 判断是否为纯数字
    if [[ "$mod_input" =~ ^[0-9]+$ ]]; then
        # 获取端口总数
        local total_ports=$(jq -r '.ports | length' "$PORT_CONFIG_FILE")
        
        # 如果输入的数字小于等于端口总数，尝试作为序号
        if [ "$mod_input" -le "$total_ports" ]; then
            # 按序号获取端口号
            mod_port=$(jq -r ".ports[$((mod_input - 1))].port" "$PORT_CONFIG_FILE")
            echo -e "${CYAN}序号 $mod_input 对应端口: $mod_port${NC}"
            echo ""
        else
            # 否则作为端口号处理
            mod_port="$mod_input"
        fi
    else
        echo -e "${RED}无效输入${NC}"
        echo ""
        read -p "按回车键继续..." dummy
        return
    fi
    
    if port_exists "$mod_port"; then
        # 设置要修改的端口，然后调用配置向导
        port_config_wizard_with_port "$mod_port"
    else
        echo -e "${RED}端口 $mod_port 不存在${NC}"
        echo ""
        read -p "按回车键继续..." dummy
    fi
}

# 带端口号的配置向导（用于修改）
port_config_wizard_with_port() {
    local preset_port=$1
    # 直接调用原配置向导，它会检测到端口已存在并提示更新
    clear
    echo -e "${CYAN}==================== 修改端口配置 ====================${NC}"
    echo -e "${YELLOW}提示：所有选项可直接回车保持原值${NC}"
    echo ""
    
    local old_port="$preset_port"
    
    # 获取现有配置
    local config=$(get_port_config "$old_port")
    local old_desc=$(echo "$config" | jq -r '.description')
    local old_limit=$(echo "$config" | jq -r '.traffic_limit')
    local old_tolerance=$(echo "$config" | jq -r '.traffic_tolerance')
    local old_mode=$(echo "$config" | jq -r '.limit_mode')
    local old_interface=$(echo "$config" | jq -r '.main_interface')
    
    echo -e "${CYAN}当前配置：${NC}"
    echo "  端口: $old_port"
    echo "  描述: $old_desc"
    echo "  限制: ${old_limit}GB (容错: ${old_tolerance}GB)"
    echo "  模式: $old_mode"
    echo "  接口: $old_interface"
    echo ""
    
    # 端口号（允许修改）
    while true; do
        read -p "端口号 [回车=$old_port]: " port
        if [ -z "$port" ]; then
            port="$old_port"
            break
        elif [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            # 检查新端口号是否与其他端口冲突（排除当前端口）
            if [ "$port" != "$old_port" ] && port_exists "$port"; then
                echo -e "${RED}端口 $port 已存在配置！${NC}"
            else
                break
            fi
        else
            echo -e "${RED}无效的端口号（1-65535）${NC}"
        fi
    done
    
    # 端口描述
    read -p "端口描述 [回车=$old_desc]: " description
    [ -z "$description" ] && description="$old_desc"
    
    # 流量限制
    while true; do
        read -p "流量限制(GB) [回车=$old_limit]: " traffic_limit
        if [ -z "$traffic_limit" ]; then
            traffic_limit="$old_limit"
            break
        elif [[ "$traffic_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo -e "${RED}无效输入${NC}"
        fi
    done
    
    # 容错范围
    while true; do
        read -p "容错范围(GB) [回车=$old_tolerance]: " traffic_tolerance
        if [ -z "$traffic_tolerance" ]; then
            traffic_tolerance="$old_tolerance"
            break
        elif [[ "$traffic_tolerance" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo -e "${RED}无效输入${NC}"
        fi
    done
    
    # 同步其他配置
    if read_machine_config; then
        traffic_mode=${TRAFFIC_MODE:-"total"}
        traffic_period=${TRAFFIC_PERIOD:-"monthly"}
        period_start_day=${PERIOD_START_DAY:-1}
        # 端口限速独立设置，不受机器限速影响
        limit_speed=20
        main_interface=${MAIN_INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n1)}
        limit_mode=${LIMIT_MODE:-"tc"}
    else
        traffic_mode="total"
        traffic_period="monthly"
        period_start_day=1
        limit_speed=20
        main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
        limit_mode="tc"
    fi
    
    # 保存配置
    echo ""
    echo -e "${CYAN}正在更新配置...${NC}"
    
    # 如果端口号改变了，需要先删除旧端口配置和限速
    if [ "$port" != "$old_port" ]; then
        echo -e "${YELLOW}端口号已改变 ($old_port -> $port)，正在迁移配置...${NC}"
        
        # 删除旧端口的iptables规则和tc限速
        unblock_port "$old_port"
        remove_tc_limit "$old_port" "$old_interface"
        
        # 删除旧端口配置
        delete_port_config "$old_port"
        
        echo -e "${GREEN}✓ 已清理旧端口 $old_port 的配置和限速${NC}"
    fi
    
    # 添加新配置（如果端口未变，会自动覆盖）
    add_port_config "$port" "$description" "$traffic_limit" "$traffic_tolerance" \
        "$traffic_mode" "$traffic_period" "$period_start_day" "$limit_speed" \
        "$main_interface" "$limit_mode"
    
    echo ""
    if [ "$port" != "$old_port" ]; then
        echo -e "${GREEN}✓ 端口配置已从 $old_port 迁移到 $port！${NC}"
    else
        echo -e "${GREEN}✓ 端口 $port 配置已更新！${NC}"
    fi
    echo ""
    read -p "按回车键继续..." dummy
}

# 解除端口限速
remove_port_limit() {
    list_all_ports
    
    if [ ! -f "$PORT_CONFIG_FILE" ] || [ "$(jq -r '.ports | length' "$PORT_CONFIG_FILE")" -eq 0 ]; then
        echo ""
        read -p "按回车键继续..." dummy
        return
    fi
    
    echo ""
    echo -e "${YELLOW}提示：可输入序号、端口号或'all'${NC}"
    read -p "请选择 (序号/端口号/all): " del_input
    
    local del_port=""
    
    # 判断是否为all
    if [ "$del_input" = "all" ]; then
        read -p "确认解除所有端口限速？[y/N]: " confirm
        [ -z "$confirm" ] && confirm="n"
        if [[ "$confirm" = "y" || "$confirm" = "Y" ]]; then
            remove_all_limits
            echo -e "${GREEN}已解除所有端口限速${NC}"
        else
            echo -e "${YELLOW}已取消操作${NC}"
        fi
        echo ""
        read -p "按回车键继续..." dummy
        return
    # 判断是否为纯数字（可能是序号或端口号）
    elif [[ "$del_input" =~ ^[0-9]+$ ]]; then
        # 获取端口总数
        local total_ports=$(jq -r '.ports | length' "$PORT_CONFIG_FILE")
        
        # 如果输入的数字小于等于端口总数，尝试作为序号
        if [ "$del_input" -le "$total_ports" ]; then
            # 按序号获取端口号
            del_port=$(jq -r ".ports[$((del_input - 1))].port" "$PORT_CONFIG_FILE")
            echo -e "${CYAN}序号 $del_input 对应端口: $del_port${NC}"
        else
            # 否则作为端口号处理
            del_port="$del_input"
        fi
        
        # 检查端口是否存在并解除限速
        if port_exists "$del_port"; then
            local config=$(get_port_config "$del_port")
            local interface=$(echo "$config" | jq -r '.main_interface')
            
            delete_port_config "$del_port"
            unblock_port "$del_port"
            remove_tc_limit "$del_port" "$interface"
            echo -e "${GREEN}端口 $del_port 限速已解除${NC}"
        else
            echo -e "${RED}端口 $del_port 不存在${NC}"
        fi
    else
        echo -e "${RED}无效输入${NC}"
    fi
    
    echo ""
    read -p "按回车键继续..." dummy
}

# 查看定时任务
view_crontab_status() {
    clear
    echo -e "${CYAN}==================== 定时任务状态 ====================${NC}"
    echo ""
    
    local wrapper_script="$WORK_DIR/port_traffic_cron_wrapper.sh"
    local current_cron=$(crontab -l 2>/dev/null)
    
    # 检查是否存在包装脚本定时任务或旧的直接调用定时任务
    if echo "$current_cron" | grep -Fq "$wrapper_script"; then
        echo -e "${GREEN}✓ 定时任务已启用（使用 GitHub 最新版本）${NC}"
        echo ""
        echo "当前定时任务："
        echo "$current_cron" | grep "$wrapper_script"
        echo ""
        echo -e "${CYAN}说明：每分钟从 GitHub 获取最新版本并自动检查所有端口流量${NC}"
        echo -e "${CYAN}包装脚本：$wrapper_script${NC}"
        echo ""
        read -p "是否要禁用定时任务？[y/N]: " disable
        [ -z "$disable" ] && disable="n"
        if [[ "$disable" = "y" || "$disable" = "Y" ]]; then
            crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
            rm -f "$wrapper_script"
            echo -e "${GREEN}定时任务已禁用${NC}"
        fi
    elif echo "$current_cron" | grep -Fq "$PORT_SCRIPT_PATH"; then
        echo -e "${YELLOW}⚠ 定时任务已启用（使用本地版本 - 建议升级）${NC}"
        echo ""
        echo "当前定时任务："
        echo "$current_cron" | grep "$PORT_SCRIPT_PATH"
        echo ""
        echo -e "${CYAN}说明：每分钟检查所有端口流量（使用本地文件）${NC}"
        echo -e "${YELLOW}建议：升级到从 GitHub 获取最新版本的方式${NC}"
        echo ""
        read -p "是否要升级到 GitHub 最新版本模式？[Y/n]: " upgrade
        [ -z "$upgrade" ] && upgrade="y"
        if [[ "$upgrade" = "y" || "$upgrade" = "Y" ]]; then
            # 移除旧的定时任务
            crontab -l 2>/dev/null | grep -v "$PORT_SCRIPT_PATH" | crontab -
            echo -e "${GREEN}已移除旧的定时任务${NC}"
            # 设置新的定时任务
            setup_crontab
        else
            read -p "是否要禁用定时任务？[y/N]: " disable
            [ -z "$disable" ] && disable="n"
            if [[ "$disable" = "y" || "$disable" = "Y" ]]; then
                crontab -l 2>/dev/null | grep -v "$PORT_SCRIPT_PATH" | crontab -
                echo -e "${GREEN}定时任务已禁用${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}✗ 定时任务未启用${NC}"
        echo ""
        read -p "是否要启用定时任务？[Y/n]: " enable
        [ -z "$enable" ] && enable="y"
        if [[ "$enable" = "y" || "$enable" = "Y" ]]; then
            setup_crontab
        fi
    fi
    
    echo ""
    read -p "按回车键继续..." dummy
}

# 更新脚本
update_script() {
    clear
    echo -e "${CYAN}==================== 更新脚本 ====================${NC}"
    echo ""
    echo -e "${YELLOW}准备从 GitHub 下载最新版本...${NC}"
    echo ""
    
    # GitHub 原始文件链接
    local GITHUB_RAW="https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/port_traffic_limit.sh"
    local TEMP_FILE="/tmp/port_traffic_limit_new.sh"
    
    # 显示当前版本
    echo -e "${CYAN}当前版本: ${NC}v${SCRIPT_VERSION} (${LAST_UPDATE})"
    echo ""
    
    # 下载新版本
    echo -e "${YELLOW}正在下载...${NC}"
    if wget -q --timeout=10 --tries=3 -O "$TEMP_FILE" "$GITHUB_RAW"; then
        # 检查下载的文件是否有效
        if [ -s "$TEMP_FILE" ] && head -1 "$TEMP_FILE" | grep -q "^#!/bin/bash"; then
            # 提取新版本号
            local new_version=$(grep '^SCRIPT_VERSION=' "$TEMP_FILE" | head -1 | cut -d'"' -f2)
            local new_update=$(grep '^LAST_UPDATE=' "$TEMP_FILE" | head -1 | cut -d'"' -f2)
            
            echo -e "${GREEN}✓ 下载成功${NC}"
            echo ""
            echo -e "${CYAN}最新版本: ${NC}v${new_version} (${new_update})"
            echo ""
            
            # 比较版本
            if [ "$new_version" = "$SCRIPT_VERSION" ]; then
                echo -e "${YELLOW}当前已是最新版本${NC}"
                rm -f "$TEMP_FILE"
            else
                echo -e "${GREEN}发现新版本！${NC}"
                echo ""
                read -p "是否要更新到最新版本？[Y/n]: " confirm
                [ -z "$confirm" ] && confirm="y"
                
                if [[ "$confirm" = "y" || "$confirm" = "Y" ]]; then
                    # 备份当前版本
                    local BACKUP_FILE="${PORT_SCRIPT_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
                    cp "$PORT_SCRIPT_PATH" "$BACKUP_FILE"
                    echo -e "${GREEN}✓ 已备份当前版本到: $BACKUP_FILE${NC}"
                    
                    # 替换脚本
                    mv "$TEMP_FILE" "$PORT_SCRIPT_PATH"
                    chmod +x "$PORT_SCRIPT_PATH"
                    
                    echo -e "${GREEN}✓ 更新成功！${NC}"
                    echo ""
                    echo -e "${CYAN}提示：脚本将在3秒后重启以应用更新...${NC}"
                    sleep 3
                    
                    # 重启脚本
                    exec "$PORT_SCRIPT_PATH"
                else
                    echo -e "${YELLOW}取消更新${NC}"
                    rm -f "$TEMP_FILE"
                fi
            fi
        else
            echo -e "${RED}✗ 下载的文件无效${NC}"
            rm -f "$TEMP_FILE"
        fi
    else
        echo -e "${RED}✗ 下载失败${NC}"
        echo -e "${YELLOW}请检查网络连接或稍后重试${NC}"
        rm -f "$TEMP_FILE"
    fi
    
    echo ""
    read -p "按回车键继续..." dummy
}

# 交互式主菜单
interactive_menu() {
    while true; do
        clear
        echo -e "${CYAN}========== 端口流量限制管理 v${SCRIPT_VERSION} ==========${NC}"
        echo -e "${YELLOW}最后更新: ${LAST_UPDATE}${NC}"
        echo ""
        echo "1) 添加端口配置"
        echo "2) 修改端口配置"
        echo "3) 解除端口限速"
        echo "4) 查看端口配置及流量使用情况"
        echo "5) 查看定时任务配置"
        echo "6) 更新脚本到最新版本"
        echo "0) 退出"
        echo -e "${CYAN}===========================================${NC}"
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                port_config_wizard
                ;;
            2)
                modify_port_config
                ;;
            3)
                remove_port_limit
                ;;
            4)
                view_port_status
                ;;
            5)
                view_crontab_status
                ;;
            6)
                update_script
                ;;
            0)
                echo -e "${GREEN}退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 设置定时任务
setup_crontab() {
    # 定时任务直接执行本地文件
    local cron_entry="* * * * * bash $PORT_SCRIPT_PATH --cron"
    local current_cron=$(crontab -l 2>/dev/null)
    
    # 检查是否已存在定时任务
    if echo "$current_cron" | grep -Fq "$PORT_SCRIPT_PATH --cron"; then
        echo -e "${YELLOW}定时任务已存在${NC}"
        echo -e "${CYAN}定时任务: $cron_entry${NC}"
    else
        # 先移除旧的包装脚本定时任务（如果存在）
        local wrapper_script="$WORK_DIR/port_traffic_cron_wrapper.sh"
        if echo "$current_cron" | grep -Fq "$wrapper_script"; then
            crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
            echo -e "${YELLOW}已移除旧的包装脚本定时任务${NC}"
        fi
        
        # 添加新的定时任务
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo -e "${GREEN}定时任务已添加（每分钟检查端口流量）${NC}"
        echo -e "${CYAN}定时任务: $cron_entry${NC}"
        echo -e "${YELLOW}提示: 请通过主菜单选项5更新脚本到最新版本${NC}"
    fi
}

# 移除所有端口限制
remove_all_limits() {
    echo -e "${YELLOW}正在移除所有端口限制...${NC}"
    
    if [ -f "$PORT_CONFIG_FILE" ]; then
        jq -r '.ports[].port' "$PORT_CONFIG_FILE" | while read port; do
            unblock_port "$port"
            
            local config=$(get_port_config "$port")
            local interface=$(echo "$config" | jq -r '.main_interface')
            remove_tc_limit "$port" "$interface"
        done
    fi
    
    # 移除定时任务（包括新旧两种方式）
    local wrapper_script="$WORK_DIR/port_traffic_cron_wrapper.sh"
    
    # 移除包装脚本的定时任务（旧版本）
    if crontab -l 2>/dev/null | grep -q "$wrapper_script"; then
        crontab -l 2>/dev/null | grep -v "$wrapper_script" | crontab -
        echo -e "${GREEN}已移除旧的包装脚本定时任务${NC}"
    fi
    
    # 移除旧的直接调用定时任务
    if crontab -l 2>/dev/null | grep -q "$PORT_SCRIPT_PATH"; then
        crontab -l 2>/dev/null | grep -v "$PORT_SCRIPT_PATH" | crontab -
        echo -e "${GREEN}已移除旧的定时任务${NC}"
    fi
    
    # 删除包装脚本文件
    if [ -f "$wrapper_script" ]; then
        rm -f "$wrapper_script"
        echo -e "${GREEN}已删除包装脚本${NC}"
    fi
    
    echo -e "${GREEN}所有端口限制已移除${NC}"
}

# Cron模式 - 自动检查所有端口
cron_mode() {
    # 记录执行开始（无论配置文件是否存在）
    echo "-----------------------------------------------------" >> "$PORT_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Port Traffic Limit v${SCRIPT_VERSION} (最后更新: ${LAST_UPDATE})" >> "$PORT_LOG_FILE"
    
    if [ ! -f "$PORT_CONFIG_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件不存在，跳过检查" >> "$PORT_LOG_FILE"
        exit 0
    fi
    
    # 获取所有端口（使用数组避免管道子shell问题）
    local ports_array=()
    while IFS= read -r port; do
        ports_array+=("$port")
    done < <(jq -r '.ports[].port' "$PORT_CONFIG_FILE" 2>/dev/null)
    
    # 检查是否有端口配置
    if [ ${#ports_array[@]} -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 没有配置端口，跳过检查" >> "$PORT_LOG_FILE"
        exit 0
    fi
    
    # 记录开始检查
    echo "$(date '+%Y-%m-%d %H:%M:%S') 开始检查 ${#ports_array[@]} 个端口的流量..." >> "$PORT_LOG_FILE"
    
    # 循环检查每个端口
    for port in "${ports_array[@]}"; do
        if [ -n "$port" ]; then
            check_and_limit_port_traffic "$port"
        fi
    done
    
    # 记录检查完成
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量检查完成" >> "$PORT_LOG_FILE"
}

# 主函数
main() {
    # 检查必要工具
    if ! check_required_tools; then
        exit 1
    fi
    
    # 初始化配置文件
    init_config_file
    
    # 解析参数
    if [ "$1" = "--remove" ]; then
        if [ -n "$2" ]; then
            # 移除特定端口
            if port_exists "$2"; then
                delete_port_config "$2"
                unblock_port "$2"
                echo -e "${GREEN}端口 $2 配置已移除${NC}"
            else
                echo -e "${RED}端口 $2 不存在${NC}"
            fi
        else
            # 移除所有端口
            remove_all_limits
        fi
        exit 0
    elif [ "$1" = "--cron" ]; then
        # Cron自动检查模式
        cron_mode
        exit 0
    else
        # 交互式配置模式
        interactive_menu
    fi
}

# 执行主函数
main "$@"
