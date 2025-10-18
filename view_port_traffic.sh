#!/bin/bash

# View Port Traffic - 查看端口流量使用情况脚本
# 版本 1.0

WORK_DIR="/root/TrafficCop"
PORTS_CONFIG_FILE="$WORK_DIR/ports_traffic_config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取端口流量使用情况
get_port_traffic_usage() {
    local port=$1
    local interface=$2
    local traffic_mode=$3
    
    local rx_bytes=$(iptables -L INPUT -v -n -x 2>/dev/null | grep "dpt:$port" | awk '{sum+=$2} END {print sum+0}')
    local tx_bytes=$(iptables -L OUTPUT -v -n -x 2>/dev/null | grep "spt:$port" | awk '{sum+=$2} END {print sum+0}')
    
    local usage_bytes
    case $traffic_mode in
        out) usage_bytes=$tx_bytes ;;
        in) usage_bytes=$rx_bytes ;;
        total) usage_bytes=$((rx_bytes + tx_bytes)) ;;
        max) usage_bytes=$(echo "$rx_bytes $tx_bytes" | tr ' ' '\n' | sort -rn | head -n1) ;;
        *) usage_bytes=$((rx_bytes + tx_bytes)) ;;
    esac
    
    if [ -n "$usage_bytes" ] && [ "$usage_bytes" -gt 0 ]; then
        echo "scale=3; $usage_bytes/1024/1024/1024" | bc
    else
        echo "0.000"
    fi
}

# 获取端口配置
get_port_config() {
    local port=$1
    local config=$(cat "$PORTS_CONFIG_FILE" 2>/dev/null || echo '{"ports":[]}')
    echo "$config" | jq -r ".ports[] | select(.port==$port)"
}

# 计算使用百分比
calculate_percentage() {
    local usage=$1
    local limit=$2
    
    if (( $(echo "$limit > 0" | bc -l) )); then
        echo "scale=2; ($usage / $limit) * 100" | bc
    else
        echo "0.00"
    fi
}

# 获取状态颜色
get_status_color() {
    local percentage=$1
    
    if (( $(echo "$percentage >= 90" | bc -l) )); then
        echo "$RED"
    elif (( $(echo "$percentage >= 75" | bc -l) )); then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# 显示进度条
show_progress_bar() {
    local percentage=$1
    local width=30
    local filled=$(echo "scale=0; ($percentage * $width) / 100" | bc)
    
    # 确保filled不为负数且不超过width
    if [ "$filled" -lt 0 ]; then
        filled=0
    elif [ "$filled" -gt "$width" ]; then
        filled=$width
    fi
    
    local color=$(get_status_color "$percentage")
    
    echo -n "${color}["
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    for ((i=filled; i<width; i++)); do echo -n "░"; done
    echo -e "]${NC}"
}

# 显示单个端口信息
show_port_info() {
    local port=$1
    local port_config=$(get_port_config "$port")
    
    if [ -z "$port_config" ]; then
        return
    fi
    
    local description=$(echo "$port_config" | jq -r '.description')
    local traffic_limit=$(echo "$port_config" | jq -r '.traffic_limit')
    local traffic_tolerance=$(echo "$port_config" | jq -r '.traffic_tolerance')
    local traffic_mode=$(echo "$port_config" | jq -r '.traffic_mode')
    local interface=$(echo "$port_config" | jq -r '.main_interface')
    local limit_mode=$(echo "$port_config" | jq -r '.limit_mode')
    local limit_speed=$(echo "$port_config" | jq -r '.limit_speed')
    local period=$(echo "$port_config" | jq -r '.traffic_period')
    local last_reset=$(echo "$port_config" | jq -r '.last_reset')
    
    # 获取当前流量使用
    local current_usage=$(get_port_traffic_usage "$port" "$interface" "$traffic_mode")
    local limit_threshold=$(echo "$traffic_limit - $traffic_tolerance" | bc)
    local percentage=$(calculate_percentage "$current_usage" "$traffic_limit")
    
    # 确定状态
    local status
    local status_color
    if (( $(echo "$current_usage > $limit_threshold" | bc -l) )); then
        status="⚠️ 已限制"
        status_color="$RED"
    elif (( $(echo "$current_usage > ($traffic_limit * 0.8)" | bc -l) )); then
        status="⚡ 接近限制"
        status_color="$YELLOW"
    else
        status="✓ 正常"
        status_color="$GREEN"
    fi
    
    # 翻译模式
    local mode_text
    case $traffic_mode in
        out) mode_text="出站" ;;
        in) mode_text="入站" ;;
        total) mode_text="总计" ;;
        max) mode_text="最大" ;;
    esac
    
    local period_text
    case $period in
        monthly) period_text="月度" ;;
        quarterly) period_text="季度" ;;
        yearly) period_text="年度" ;;
    esac
    
    local limit_mode_text
    if [ "$limit_mode" = "tc" ]; then
        limit_mode_text="限速 ${limit_speed}kbit/s"
    else
        limit_mode_text="阻断"
    fi
    
    # 显示信息
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}端口 $port${NC} - ${PURPLE}$description${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "状态: ${status_color}${status}${NC}"
    echo -e "流量使用: ${YELLOW}${current_usage} GB${NC} / ${GREEN}${traffic_limit} GB${NC} (${percentage}%)"
    show_progress_bar "$percentage"
    echo -e "限制阈值: ${YELLOW}${limit_threshold} GB${NC} (扣除容错 ${traffic_tolerance} GB)"
    echo -e "统计模式: ${mode_text} | 周期: ${period_text} | 上次重置: ${last_reset}"
    echo -e "限制方式: ${limit_mode_text}"
    echo ""
}

# 显示所有端口信息
show_all_ports() {
    if [ ! -f "$PORTS_CONFIG_FILE" ]; then
        echo -e "${RED}未找到端口配置文件${NC}"
        return
    fi
    
    local port_count=$(cat "$PORTS_CONFIG_FILE" | jq -r '.ports | length')
    
    if [ "$port_count" -eq 0 ]; then
        echo -e "${YELLOW}当前没有配置任何端口${NC}"
        return
    fi
    
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   端口流量监控 - 实时查看工具          ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "更新时间: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "已配置端口: ${GREEN}${port_count}${NC}"
    echo ""
    
    # 获取所有端口并显示
    local ports=$(cat "$PORTS_CONFIG_FILE" | jq -r '.ports[].port')
    
    for port in $ports; do
        show_port_info "$port"
    done
    
    # 显示总计信息
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}总计统计${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local total_usage=0
    local total_limit=0
    
    for port in $ports; do
        local port_config=$(get_port_config "$port")
        local interface=$(echo "$port_config" | jq -r '.main_interface')
        local traffic_mode=$(echo "$port_config" | jq -r '.traffic_mode')
        local traffic_limit=$(echo "$port_config" | jq -r '.traffic_limit')
        
        local current_usage=$(get_port_traffic_usage "$port" "$interface" "$traffic_mode")
        total_usage=$(echo "$total_usage + $current_usage" | bc)
        total_limit=$(echo "$total_limit + $traffic_limit" | bc)
    done
    
    local total_percentage=$(calculate_percentage "$total_usage" "$total_limit")
    
    echo -e "所有端口总使用: ${YELLOW}${total_usage} GB${NC} / ${GREEN}${total_limit} GB${NC} (${total_percentage}%)"
    show_progress_bar "$total_percentage"
    echo ""
}

# 实时监控模式
realtime_monitor() {
    while true; do
        show_all_ports
        echo -e "${YELLOW}[实时监控模式] 按 Ctrl+C 退出${NC}"
        sleep 5
    done
}

# 导出为JSON
export_json() {
    if [ ! -f "$PORTS_CONFIG_FILE" ]; then
        echo -e "${RED}未找到端口配置文件${NC}"
        return
    fi
    
    local ports=$(cat "$PORTS_CONFIG_FILE" | jq -r '.ports[].port')
    local export_file="$WORK_DIR/port_traffic_report_$(date +%Y%m%d_%H%M%S).json"
    
    echo '{' > "$export_file"
    echo '  "timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'",' >> "$export_file"
    echo '  "ports": [' >> "$export_file"
    
    local first=true
    for port in $ports; do
        local port_config=$(get_port_config "$port")
        local interface=$(echo "$port_config" | jq -r '.main_interface')
        local traffic_mode=$(echo "$port_config" | jq -r '.traffic_mode')
        local traffic_limit=$(echo "$port_config" | jq -r '.traffic_limit')
        local description=$(echo "$port_config" | jq -r '.description')
        
        local current_usage=$(get_port_traffic_usage "$port" "$interface" "$traffic_mode")
        local percentage=$(calculate_percentage "$current_usage" "$traffic_limit")
        
        if [ "$first" = false ]; then
            echo '    ,' >> "$export_file"
        fi
        first=false
        
        cat >> "$export_file" << EOF
    {
      "port": $port,
      "description": "$description",
      "current_usage": $current_usage,
      "traffic_limit": $traffic_limit,
      "percentage": $percentage,
      "traffic_mode": "$traffic_mode"
    }
EOF
    done
    
    echo '  ]' >> "$export_file"
    echo '}' >> "$export_file"
    
    echo -e "${GREEN}报告已导出到: ${export_file}${NC}"
}

# 主函数
main() {
    if [ "$1" = "--realtime" ] || [ "$1" = "-r" ]; then
        realtime_monitor
    elif [ "$1" = "--export" ] || [ "$1" = "-e" ]; then
        export_json
    elif [ "$1" = "--json" ] || [ "$1" = "-j" ]; then
        # 输出JSON格式，用于其他脚本调用
        if [ ! -f "$PORTS_CONFIG_FILE" ]; then
            echo '{"ports":[]}'
            return
        fi
        
        local ports=$(cat "$PORTS_CONFIG_FILE" | jq -r '.ports[].port')
        echo '{"ports":['
        
        local first=true
        for port in $ports; do
            local port_config=$(get_port_config "$port")
            local interface=$(echo "$port_config" | jq -r '.main_interface')
            local traffic_mode=$(echo "$port_config" | jq -r '.traffic_mode')
            local traffic_limit=$(echo "$port_config" | jq -r '.traffic_limit')
            local description=$(echo "$port_config" | jq -r '.description')
            
            local current_usage=$(get_port_traffic_usage "$port" "$interface" "$traffic_mode")
            
            if [ "$first" = false ]; then
                echo ','
            fi
            first=false
            
            echo -n "{\"port\":$port,\"description\":\"$description\",\"usage\":$current_usage,\"limit\":$traffic_limit}"
        done
        
        echo ']}'
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  无参数          显示所有端口流量信息"
        echo "  -r, --realtime  实时监控模式（每5秒刷新）"
        echo "  -e, --export    导出为JSON报告"
        echo "  -j, --json      输出JSON格式（用于脚本调用）"
        echo "  -h, --help      显示帮助信息"
        echo ""
        echo "示例:"
        echo "  $0                   # 查看所有端口"
        echo "  $0 --realtime        # 实时监控"
        echo "  $0 --export          # 导出报告"
    else
        show_all_ports
    fi
}

main "$@"
