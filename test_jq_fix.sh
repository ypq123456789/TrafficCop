#!/bin/bash

# 快速验证 jq 修复是否生效

echo "=========================================="
echo "TrafficCop jq 修复验证"
echo "=========================================="
echo ""

# 测试参数
START_TS=$(date -d "2025-11-19" +%s)
END_TS=$(date -d "2025-12-18 23:59:59" +%s)

echo "📅 测试日期: 2025-11-19 (重置日)"
echo "   开始时间戳: $START_TS"
echo "   结束时间戳: $END_TS"
echo ""

# 获取 vnstat JSON
VNSTAT_JSON=$(vnstat -i eth0 --json 2>/dev/null)

if [ -z "$VNSTAT_JSON" ]; then
    echo "❌ 无法获取 vnstat 数据"
    exit 1
fi

echo "🔍 测试修复后的 jq 命令..."
echo ""

# 使用修复后的方法
jq_filter='[.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)) | .rx + .tx] | add // 0'
RESULT=$(printf '%s' "$VNSTAT_JSON" | jq -r --arg start "$START_TS" --arg end "$END_TS" "$jq_filter")

if [ $? -eq 0 ] && [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
    echo "✅ jq 查询成功!"
    echo ""
    echo "📊 流量统计结果:"
    echo "   原始值: $RESULT 字节"
    
    # 转换为各种单位
    MB=$(echo "scale=2; $RESULT/1024/1024" | bc)
    GB=$(echo "scale=3; $RESULT/1024/1024/1024" | bc)
    
    echo "   MB: $MB MB"
    echo "   GB: $GB GB"
    echo ""
    
    # 判断是否合理
    if (( $(echo "$GB < 1" | bc -l) )); then
        echo "✅ 流量值合理!(重置日应该接近0)"
        echo "   预期: ~0.1 GB"
        echo "   实际: $GB GB"
    else
        echo "⚠️  流量值较大: $GB GB"
        echo "   如果今天是重置日,这个值应该很小"
    fi
else
    echo "❌ jq 查询失败"
    echo "   返回值: '$RESULT'"
    echo "   退出码: $?"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ 修复验证完成!"
echo "=========================================="
echo ""
echo "现在可以运行完整脚本:"
echo "  /root/TrafficCop/trafficcop.sh --view"
echo ""
