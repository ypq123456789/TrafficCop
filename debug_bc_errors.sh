#!/bin/bash

# 调试脚本：帮助定位 bc 语法错误
# 使用方法：bash debug_bc_errors.sh

echo "=== BC 错误诊断工具 ==="
echo ""

# 1. 检查所有脚本中的 bc 使用
echo "1. 搜索所有 bc 调用："
echo "----------------------------------------"
find /root/TrafficCop -name "*.sh" -exec grep -Hn "bc" {} \; 2>/dev/null | while read line; do
    if echo "$line" | grep -q "2>/dev/null"; then
        echo "✓ [已修复] $line"
    else
        echo "⚠ [需修复] $line"
    fi
done

echo ""
echo "2. 测试常见 bc 错误场景："
echo "----------------------------------------"

# 测试空变量
echo "测试空变量："
empty_var=""
echo "empty_var='$empty_var'"
echo "echo \"\$empty_var + 5\" | bc"
result=$(echo "$empty_var + 5" | bc 2>&1)
if [[ "$result" == *"syntax error"* ]]; then
    echo "❌ 产生语法错误: $result"
    echo "✓ 修复方法: echo \"\${empty_var:-0} + 5\" | bc"
    result_fixed=$(echo "${empty_var:-0} + 5" | bc 2>/dev/null || echo "0")
    echo "✓ 修复后结果: $result_fixed"
else
    echo "✓ 无错误: $result"
fi

echo ""
# 测试非数字变量
echo "测试非数字变量："
text_var="abc"
echo "text_var='$text_var'"
echo "echo \"\$text_var + 5\" | bc"
result=$(echo "$text_var + 5" | bc 2>&1)
if [[ "$result" == *"syntax error"* ]]; then
    echo "❌ 产生语法错误: $result"
    echo "✓ 修复方法: 添加数字验证或默认值"
else
    echo "✓ 无错误: $result"
fi

echo ""
# 测试除零
echo "测试除零错误："
echo "echo \"5 / 0\" | bc"
result=$(echo "5 / 0" | bc 2>&1)
if [[ "$result" == *"divide by zero"* ]] || [[ "$result" == *"syntax error"* ]]; then
    echo "❌ 产生错误: $result"
    echo "✓ 修复方法: 检查除数不为零"
else
    echo "✓ 无错误: $result"
fi

echo ""
echo "3. 推荐的修复模式："
echo "----------------------------------------"
echo "标准模式：\$(echo \"表达式\" | bc 2>/dev/null || echo \"默认值\")"
echo "比较模式：\$(echo \"条件\" | bc -l 2>/dev/null || echo \"0\")"
echo "安全模式：[ -n \"\$var\" ] && [[ \"\$var\" =~ ^[0-9]+(\.[0-9]+)?\$ ]] && result=\$(echo \"\$var\" | bc)"

echo ""
echo "4. 实时监控 bc 错误："
echo "----------------------------------------"
echo "使用以下命令监控正在运行的脚本的错误输出："
echo "tail -f /root/TrafficCop/port_traffic_monitor.log | grep 'syntax error'"
echo "或者运行脚本时重定向错误："
echo "bash /root/TrafficCop/port_traffic_limit.sh 2>&1 | grep 'syntax error'"
