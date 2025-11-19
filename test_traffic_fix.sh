#!/bin/bash

# TrafficCop 流量统计修复验证脚本
# 用于测试 vnstat JSON API 查询是否正常工作

echo "=========================================="
echo "TrafficCop 流量统计修复验证"
echo "=========================================="
echo ""

# 获取当前日期和时间戳
CURRENT_DATE=$(date +%Y-%m-%d)
START_DATE="2025-11-19"
END_DATE="2025-12-18"

START_TS=$(date -d "$START_DATE" +%s)
END_TS=$(date -d "$END_DATE 23:59:59" +%s)

echo "📅 测试参数:"
echo "  当前日期: $CURRENT_DATE"
echo "  周期开始: $START_DATE (timestamp: $START_TS)"
echo "  周期结束: $END_DATE (timestamp: $END_TS)"
echo ""

# 测试1: 验证 jq 语法是否正确
echo "🔍 测试1: 验证 jq 命令语法"
echo "----------------------------------------"
JQ_TEST=$(vnstat -i eth0 --json 2>/dev/null | jq -r --arg start "$START_TS" --arg end "$END_TS" \
    '[.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)) | .rx + .tx] | add // 0')

if [ $? -eq 0 ] && [ -n "$JQ_TEST" ]; then
    echo "✅ jq 命令执行成功"
    echo "   返回值: $JQ_TEST 字节"
    TRAFFIC_GB=$(echo "scale=3; $JQ_TEST/1024/1024/1024" | bc)
    echo "   换算: $TRAFFIC_GB GB"
else
    echo "❌ jq 命令执行失败"
    exit 1
fi
echo ""

# 测试2: 查看今天的原始流量数据
echo "🔍 测试2: 查看今天($CURRENT_DATE)的原始流量数据"
echo "----------------------------------------"
TODAY_DATA=$(vnstat -i eth0 --json 2>/dev/null | jq -r --arg date "$CURRENT_DATE" \
    '.interfaces[0].traffic.day[] | select(.date.year == 2025 and .date.month == 11 and .date.day == 19)')

if [ -n "$TODAY_DATA" ]; then
    echo "$TODAY_DATA" | jq '.'
    
    TODAY_RX=$(echo "$TODAY_DATA" | jq -r '.rx')
    TODAY_TX=$(echo "$TODAY_DATA" | jq -r '.tx')
    TODAY_TOTAL=$((TODAY_RX + TODAY_TX))
    
    echo ""
    echo "📊 今日流量详情:"
    echo "   接收(RX): $(echo "scale=2; $TODAY_RX/1024/1024" | bc) MB"
    echo "   发送(TX): $(echo "scale=2; $TODAY_TX/1024/1024" | bc) MB"
    echo "   总计: $(echo "scale=2; $TODAY_TOTAL/1024/1024" | bc) MB"
else
    echo "⚠️  未找到今天的流量数据"
fi
echo ""

# 测试3: 使用脚本的实际函数测试
echo "🔍 测试3: 调用 TrafficCop 脚本函数"
echo "----------------------------------------"
cd /root/TrafficCop 2>/dev/null || cd "$(dirname "$0")"

# 静默加载脚本
SCRIPT_USAGE=$(bash -c 'source trafficcop.sh 2>/dev/null && get_traffic_usage')

if [ -n "$SCRIPT_USAGE" ] && [ "$SCRIPT_USAGE" != "0.000" ]; then
    echo "✅ 脚本函数执行成功"
    echo "   返回值: $SCRIPT_USAGE GB"
else
    echo "❌ 脚本函数返回异常: $SCRIPT_USAGE"
fi
echo ""

# 测试4: 对比新旧方法的差异
echo "🔍 测试4: 对比旧方法(vnstat --oneline)与新方法"
echo "----------------------------------------"
OLD_METHOD=$(vnstat -i eth0 --begin "$START_DATE" --end "$END_DATE" --oneline b 2>/dev/null | cut -d';' -f11)
OLD_METHOD_GB=$(echo "scale=3; $OLD_METHOD/1024/1024/1024" | bc 2>/dev/null || echo "0")

echo "📌 旧方法(--oneline):"
echo "   原始值: $OLD_METHOD 字节"
echo "   换算: $OLD_METHOD_GB GB"
echo ""
echo "📌 新方法(JSON API):"
echo "   原始值: $JQ_TEST 字节"
echo "   换算: $TRAFFIC_GB GB"
echo ""

# 计算差异
DIFF=$(echo "scale=3; $OLD_METHOD_GB - $TRAFFIC_GB" | bc)
echo "📊 差异: $DIFF GB"

if (( $(echo "$DIFF > 10" | bc -l) )); then
    echo "✅ 新方法修复成功!差异显著,旧方法确实有问题"
elif (( $(echo "$DIFF < 0.1" | bc -l) )); then
    echo "⚠️  差异很小,可能还需要进一步检查"
else
    echo "ℹ️  差异在预期范围内"
fi
echo ""

# 最终总结
echo "=========================================="
echo "📋 测试总结"
echo "=========================================="
echo ""
echo "如果看到以下结果,说明修复成功:"
echo "  ✓ jq 命令无语法错误"
echo "  ✓ 今日流量约为 110 MB (0.107 GB)"
echo "  ✓ 脚本函数返回 ~0.1 GB"
echo "  ✓ 旧方法返回 ~100 GB(错误)"
echo "  ✓ 新旧方法差异 > 10 GB"
echo ""
echo "现在可以运行以下命令更新VPS上的脚本:"
echo "  cd /root/TrafficCop && git pull"
echo ""
