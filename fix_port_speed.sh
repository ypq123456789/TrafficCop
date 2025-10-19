#!/bin/bash

# 修复端口限速配置 - 将错误的1000000kbit/s改回20kbit/s
# 修复因解除机器限速导致的端口限速异常问题

WORK_DIR="/root/TrafficCop"
PORT_CONFIG_FILE="$WORK_DIR/ports_traffic_config.json"

echo "开始修复端口限速配置..."

if [ ! -f "$PORT_CONFIG_FILE" ]; then
    echo "未找到端口配置文件: $PORT_CONFIG_FILE"
    exit 1
fi

# 备份原配置
cp "$PORT_CONFIG_FILE" "$PORT_CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# 检查是否有异常的限速值
bad_speeds=$(jq -r '.ports[] | select(.limit_speed > 10000) | .limit_speed' "$PORT_CONFIG_FILE" 2>/dev/null)

if [ -n "$bad_speeds" ]; then
    echo "发现异常限速值: $bad_speeds"
    echo "正在修复为20kbit/s..."
    
    # 将所有大于10000的limit_speed改为20
    jq '.ports |= map(if .limit_speed > 10000 then .limit_speed = 20 else . end)' "$PORT_CONFIG_FILE" > "$PORT_CONFIG_FILE.tmp"
    mv "$PORT_CONFIG_FILE.tmp" "$PORT_CONFIG_FILE"
    
    echo "✓ 端口限速配置已修复"
    echo "修复后的配置:"
    jq -r '.ports[] | "端口 \(.port): \(.limit_speed)kbit/s"' "$PORT_CONFIG_FILE"
else
    echo "未发现异常限速值，配置正常"
fi

echo "修复完成！"
