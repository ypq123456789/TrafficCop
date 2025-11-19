#!/bin/bash

# TrafficCop jq 语法诊断脚本

echo "=========================================="
echo "jq 语法诊断脚本"
echo "=========================================="
echo ""

# 测试环境
echo "📋 测试环境:"
echo "  jq 版本: $(jq --version)"
echo "  Bash 版本: $BASH_VERSION"
echo ""

# 设置测试参数
START_DATE="2025-11-19"
END_DATE="2025-12-18"
START_TS=$(date -d "$START_DATE" +%s)
END_TS=$(date -d "$END_DATE 23:59:59" +%s)

echo "📅 测试参数:"
echo "  开始日期: $START_DATE (timestamp: $START_TS)"
echo "  结束日期: $END_DATE (timestamp: $END_TS)"
echo ""

# 获取 vnstat JSON
echo "🔍 获取 vnstat JSON 数据..."
VNSTAT_JSON=$(vnstat -i eth0 --json 2>/dev/null)

if [ -z "$VNSTAT_JSON" ]; then
    echo "❌ 无法获取 vnstat JSON 数据"
    exit 1
fi
echo "✅ vnstat JSON 数据获取成功"
echo ""

# 测试1: 最简单的 jq 查询
echo "==================== 测试 1 ===================="
echo "描述: 最简单的 jq 查询(不使用变量)"
echo "命令: echo \"\$VNSTAT_JSON\" | jq '.interfaces[0].traffic.day[0]'"
echo ""
echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.day[0]'
echo ""

# 测试2: 使用 --arg 传递变量
echo "==================== 测试 2 ===================="
echo "描述: 使用 --arg 传递单个变量"
echo "命令: echo \"\$VNSTAT_JSON\" | jq -r --arg start \"\$START_TS\" '\$start'"
echo ""
RESULT2=$(echo "$VNSTAT_JSON" | jq -r --arg start "$START_TS" '$start')
echo "结果: $RESULT2"
echo "预期: $START_TS"
if [ "$RESULT2" = "$START_TS" ]; then
    echo "✅ 变量传递成功"
else
    echo "❌ 变量传递失败"
fi
echo ""

# 测试3: 使用 select 过滤
echo "==================== 测试 3 ===================="
echo "描述: 使用 select 过滤数组"
echo "命令: echo \"\$VNSTAT_JSON\" | jq --arg start \"\$START_TS\" '.interfaces[0].traffic.day[] | select(.timestamp >= (\$start | tonumber))' | head -3"
echo ""
echo "$VNSTAT_JSON" | jq --arg start "$START_TS" '.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber))' | head -3
echo ""

# 测试4: 完整的查询(使用单引号)
echo "==================== 测试 4 ===================="
echo "描述: 完整查询(单引号字符串)"
echo "命令: echo \"\$VNSTAT_JSON\" | jq -r --arg start \"\$START_TS\" --arg end \"\$END_TS\" '[.interfaces[0].traffic.day[] | select(.timestamp >= (\$start | tonumber) and .timestamp <= (\$end | tonumber)) | .rx + .tx] | add // 0'"
echo ""
RESULT4=$(echo "$VNSTAT_JSON" | jq -r --arg start "$START_TS" --arg end "$END_TS" '[.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)) | .rx + .tx] | add // 0')
if [ $? -eq 0 ]; then
    echo "✅ 查询成功: $RESULT4 字节"
    echo "   换算: $(echo "scale=3; $RESULT4/1024/1024/1024" | bc) GB"
else
    echo "❌ 查询失败"
fi
echo ""

# 测试5: 尝试双引号字符串
echo "==================== 测试 5 ===================="
echo "描述: 使用双引号字符串(可能导致变量展开问题)"
echo "命令: echo \"\$VNSTAT_JSON\" | jq -r --arg start \"\$START_TS\" --arg end \"\$END_TS\" \"[.interfaces[0].traffic.day[] | select(.timestamp >= (\\\$start | tonumber) and .timestamp <= (\\\$end | tonumber)) | .rx + .tx] | add // 0\""
echo ""
RESULT5=$(echo "$VNSTAT_JSON" | jq -r --arg start "$START_TS" --arg end "$END_TS" "[.interfaces[0].traffic.day[] | select(.timestamp >= (\$start | tonumber) and .timestamp <= (\$end | tonumber)) | .rx + .tx] | add // 0")
if [ $? -eq 0 ]; then
    echo "✅ 查询成功: $RESULT5 字节"
else
    echo "❌ 查询失败"
fi
echo ""

# 测试6: 模拟脚本中的实际用法
echo "==================== 测试 6 ===================="
echo "描述: 模拟 trafficcop.sh 中的实际代码"
echo ""

get_traffic_test() {
    local start_ts=$START_TS
    local end_ts=$END_TS
    local vnstat_json="$VNSTAT_JSON"
    
    local usage_bytes=$(echo "$vnstat_json" | jq -r --arg start "$start_ts" --arg end "$end_ts" '[.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)) | .rx + .tx] | add // 0')
    
    if [ $? -eq 0 ] && [ -n "$usage_bytes" ] && [ "$usage_bytes" != "null" ]; then
        echo "✅ 函数查询成功: $usage_bytes 字节"
        local usage_gib=$(echo "scale=3; $usage_bytes/1024/1024/1024" | bc)
        echo "   换算: $usage_gib GB"
    else
        echo "❌ 函数查询失败"
        echo "   返回值: '$usage_bytes'"
        echo "   退出码: $?"
    fi
}

get_traffic_test
echo ""

# 测试7: 检查特殊字符
echo "==================== 测试 7 ===================="
echo "描述: 检查 jq 表达式中是否有隐藏字符"
echo ""
JQ_EXPR='[.interfaces[0].traffic.day[] | select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)) | .rx + .tx] | add // 0'
echo "jq 表达式长度: ${#JQ_EXPR}"
echo "jq 表达式(十六进制):"
echo "$JQ_EXPR" | od -A x -t x1z -v | head -10
echo ""

echo "=========================================="
echo "诊断完成"
echo "=========================================="
echo ""
echo "💡 建议:"
echo "  1. 如果测试4成功,说明 jq 语法正确"
echo "  2. 如果测试6失败,可能是脚本中的变量作用域问题"
echo "  3. 将成功的测试命令应用到 trafficcop.sh"
echo ""
