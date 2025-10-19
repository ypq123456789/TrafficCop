#!/bin/bash

# 调试端口流量统计脚本
# 帮助诊断为什么端口11710显示0.000GB

echo "=== 端口流量统计调试工具 ==="
echo ""

port=11710
echo "调试端口: $port"
echo ""

echo "1. 检查 iptables INPUT 规则："
echo "原始输出："
iptables -L INPUT -v -n -x 2>/dev/null | grep "dpt:$port"
echo ""

echo "提取字节数（第2字段）："
iptables -L INPUT -v -n -x 2>/dev/null | grep "dpt:$port" | awk '{print "字段1:", $1, "字段2:", $2, "字段3:", $3}'
echo ""

echo "累加计算："
rx_bytes=$(iptables -L INPUT -v -n -x 2>/dev/null | grep "dpt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
echo "rx_bytes = $rx_bytes"
echo ""

echo "2. 检查 iptables OUTPUT 规则："
echo "原始输出："
iptables -L OUTPUT -v -n -x 2>/dev/null | grep "spt:$port"
echo ""

echo "提取字节数（第2字段）："
iptables -L OUTPUT -v -n -x 2>/dev/null | grep "spt:$port" | awk '{print "字段1:", $1, "字段2:", $2, "字段3:", $3}'
echo ""

echo "累加计算："
tx_bytes=$(iptables -L OUTPUT -v -n -x 2>/dev/null | grep "spt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')
echo "tx_bytes = $tx_bytes"
echo ""

echo "3. 总流量计算："
echo "使用 bc 计算："
total_bytes=$(echo "$rx_bytes + $tx_bytes" | bc 2>/dev/null || echo "0")
echo "total_bytes = $total_bytes"
echo ""

echo "转换为 GB："
if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ]; then
    gb_value=$(echo "scale=6; $total_bytes/1024/1024/1024" | bc 2>/dev/null || echo "0")
    formatted_gb=$(printf "%.3f" $(echo "$gb_value" | awk '{printf "%.6f", $1}'))
    echo "gb_value = $gb_value"
    echo "formatted_gb = $formatted_gb"
else
    echo "total_bytes 为空或为0，显示 0.000"
fi

echo ""
echo "4. 预期结果："
echo "入站: 366,946,134 字节 ≈ 0.342 GB"
echo "出站: 4,409,662,648 字节 ≈ 4.11 GB"
echo "总计: 4,776,608,782 字节 ≈ 4.45 GB"
