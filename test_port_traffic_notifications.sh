#!/bin/bash

# 测试端口流量通知功能
# 这个脚本用于验证定时推送的端口流量是否正确显示

WORK_DIR="/root/TrafficCop"
cd "$WORK_DIR" || exit 1

echo "=== 端口流量通知测试 ==="
echo "测试时间: $(date)"
echo ""

# 检查必要文件是否存在
echo "1. 检查必要文件..."
if [ ! -f "ports_traffic_config.json" ]; then
    echo "❌ 错误: ports_traffic_config.json 不存在"
    exit 1
fi

if [ ! -f "view_port_traffic.sh" ]; then
    echo "❌ 错误: view_port_traffic.sh 不存在"
    exit 1
fi

if [ ! -f "port_traffic_helper.sh" ]; then
    echo "❌ 错误: port_traffic_helper.sh 不存在"
    exit 1
fi

echo "✅ 所有必要文件都存在"
echo ""

# 测试端口配置
echo "2. 检查端口配置..."
port_count=$(jq -r '.ports | length' "ports_traffic_config.json" 2>/dev/null)
if [ -z "$port_count" ] || [ "$port_count" -eq 0 ]; then
    echo "❌ 错误: 没有配置端口"
    exit 1
fi

echo "✅ 已配置 $port_count 个端口"
echo ""

# 测试 view_port_traffic.sh 的JSON输出
echo "3. 测试 view_port_traffic.sh JSON输出..."
port_data=$(bash "view_port_traffic.sh" --json 2>/dev/null)
if [ -z "$port_data" ]; then
    echo "❌ 错误: view_port_traffic.sh 没有返回数据"
    echo "尝试直接运行:"
    bash "view_port_traffic.sh" --json
    exit 1
fi

echo "✅ view_port_traffic.sh JSON输出正常"
echo "输出数据: $port_data"
echo ""

# 测试 port_traffic_helper.sh 函数
echo "4. 测试 port_traffic_helper.sh 函数..."
source "port_traffic_helper.sh"

if ! command -v get_port_traffic_summary &> /dev/null; then
    echo "❌ 错误: get_port_traffic_summary 函数不可用"
    exit 1
fi

summary=$(get_port_traffic_summary 5)
echo "✅ port_traffic_helper.sh 函数可用"
echo "摘要输出: $summary"
echo ""

# 测试 tg_notifier.sh 的端口流量获取
echo "5. 测试 tg_notifier.sh 端口流量获取..."
if [ -f "tg_notifier.sh" ]; then
    # 临时source tg_notifier.sh 来测试函数
    source "tg_notifier.sh" 2>/dev/null
    
    if command -v get_port_traffic_summary_for_tg &> /dev/null; then
        tg_summary=$(get_port_traffic_summary_for_tg)
        echo "✅ tg_notifier.sh 端口流量获取正常"
        echo "TG格式输出: $tg_summary"
    else
        echo "❌ 错误: get_port_traffic_summary_for_tg 函数不可用"
    fi
else
    echo "⚠️  警告: tg_notifier.sh 不存在"
fi

echo ""
echo "=== 测试完成 ==="
