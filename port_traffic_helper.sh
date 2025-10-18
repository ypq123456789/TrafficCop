#!/bin/bash

# Port Traffic Helper Functions
# 用于通知脚本获取端口流量信息的通用函数

WORK_DIR="/root/TrafficCop"
PORTS_CONFIG_FILE="$WORK_DIR/ports_traffic_config.json"

# 获取端口流量摘要（简短版本，用于警告通知）
get_port_traffic_summary() {
    local max_ports=${1:-5}  # 默认显示最多5个端口
    local summary=""
    
    if [ ! -f "$PORTS_CONFIG_FILE" ] || [ ! -f "$WORK_DIR/view_port_traffic.sh" ]; then
        echo ""
        return
    fi
    
    local port_data=$(bash "$WORK_DIR/view_port_traffic.sh" --json 2>/dev/null)
    
    if [ -z "$port_data" ]; then
        echo ""
        return
    fi
    
    local port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null)
    
    if [ "$port_count" -eq 0 ]; then
        echo ""
        return
    fi
    
    summary="端口流量："
    
    local i=0
    while [ $i -lt $port_count ] && [ $i -lt $max_ports ]; do
        local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
        local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
        local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
        
        if [ -n "$port" ] && [ "$port" != "null" ]; then
            local port_percentage=0
            if (( $(echo "$port_limit > 0" | bc -l 2>/dev/null) )); then
                port_percentage=$(echo "scale=0; ($port_usage / $port_limit) * 100" | bc 2>/dev/null)
            fi
            summary="${summary}\n端口${port}: ${port_usage}/${port_limit}GB (${port_percentage}%)"
        fi
        
        i=$((i + 1))
    done
    
    if [ "$port_count" -gt $max_ports ]; then
        summary="${summary}\n...及其他$((port_count - max_ports))个端口"
    fi
    
    echo "$summary"
}

# 获取端口流量详情（详细版本，用于每日报告）
get_port_traffic_details() {
    local details=""
    
    if [ ! -f "$PORTS_CONFIG_FILE" ] || [ ! -f "$WORK_DIR/view_port_traffic.sh" ]; then
        echo ""
        return
    fi
    
    local port_data=$(bash "$WORK_DIR/view_port_traffic.sh" --json 2>/dev/null)
    
    if [ -z "$port_data" ]; then
        echo ""
        return
    fi
    
    local port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null)
    
    if [ "$port_count" -eq 0 ]; then
        echo ""
        return
    fi
    
    details="🔌 端口流量详情："
    
    local i=0
    while [ $i -lt $port_count ]; do
        local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
        local port_desc=$(echo "$port_data" | jq -r ".ports[$i].description" 2>/dev/null)
        local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
        local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
        
        if [ -n "$port" ] && [ "$port" != "null" ]; then
            local port_percentage=0
            if (( $(echo "$port_limit > 0" | bc -l 2>/dev/null) )); then
                port_percentage=$(echo "scale=1; ($port_usage / $port_limit) * 100" | bc 2>/dev/null)
            fi
            
            # 根据使用率选择状态图标
            local status_icon="✅"
            if (( $(echo "$port_percentage >= 90" | bc -l 2>/dev/null) )); then
                status_icon="🔴"
            elif (( $(echo "$port_percentage >= 75" | bc -l 2>/dev/null) )); then
                status_icon="🟡"
            fi
            
            details="${details}\n${status_icon} 端口 ${port} (${port_desc})：${port_usage}GB / ${port_limit}GB (${port_percentage}%)"
        fi
        
        i=$((i + 1))
    done
    
    echo "$details"
}

# 检查是否有端口流量配置
has_port_config() {
    if [ -f "$PORTS_CONFIG_FILE" ]; then
        local port_count=$(cat "$PORTS_CONFIG_FILE" 2>/dev/null | jq -r '.ports | length' 2>/dev/null)
        [ "$port_count" -gt 0 ]
        return $?
    fi
    return 1
}
