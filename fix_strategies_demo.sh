#!/bin/bash

# 修复策略演示脚本
# 展示不同的 bc 错误修复方法及其优缺点

echo "=== BC 错误修复策略对比 ==="
echo ""

# 策略1：静默错误 + 默认值（我们使用的方法）
echo "策略1：静默错误 + 默认值"
echo "----------------------------------------"
echo "优点：简单直接，不会中断脚本执行"
echo "缺点：可能隐藏真正的问题"
echo ""
echo "示例代码："
echo 'result=$(echo "$var + 5" | bc 2>/dev/null || echo "0")'
echo ""

# 策略2：预验证 + 条件执行
echo "策略2：预验证 + 条件执行"
echo "----------------------------------------"
echo "优点：更安全，能发现数据问题"
echo "缺点：代码更复杂"
echo ""
echo "示例代码："
cat << 'EOF'
if [[ "$var" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$var" ]; then
    result=$(echo "$var + 5" | bc)
else
    result=0
    echo "警告：变量 $var 不是有效数字，使用默认值 0"
fi
EOF
echo ""

# 策略3：使用 awk 替代 bc
echo "策略3：使用 awk 替代 bc"
echo "----------------------------------------"
echo "优点：awk 对错误输入更宽容，性能更好"
echo "缺点：语法稍有不同，精度可能略低"
echo ""
echo "示例代码："
echo 'result=$(awk "BEGIN {print ($var + 5)}" 2>/dev/null || echo "0")'
echo ""

# 策略4：使用 bash 算术运算（适用于整数）
echo "策略4：使用 bash 算术运算"
echo "----------------------------------------"
echo "优点：原生支持，无外部依赖，速度快"
echo "缺点：只支持整数运算"
echo ""
echo "示例代码："
echo 'result=$((${var:-0} + 5))'
echo ""

# 实际测试各种策略
echo "=== 实际测试各策略表现 ==="
echo ""

test_values=("" "abc" "10.5" "0" "-5")

for test_val in "${test_values[@]}"; do
    echo "测试值: '$test_val'"
    echo "----------------------------------------"
    
    # 策略1：静默错误
    result1=$(echo "${test_val:-0} + 5" | bc 2>/dev/null || echo "0")
    echo "策略1结果: $result1"
    
    # 策略2：预验证
    if [[ "$test_val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        result2=$(echo "$test_val + 5" | bc)
    else
        result2=0
    fi
    echo "策略2结果: $result2"
    
    # 策略3：awk
    result3=$(awk "BEGIN {print (${test_val:-0} + 5)}" 2>/dev/null || echo "0")
    echo "策略3结果: $result3"
    
    # 策略4：bash算术（转换为整数）
    int_val=$(echo "$test_val" | grep -o '^-\?[0-9]\+' || echo "0")
    result4=$((${int_val:-0} + 5))
    echo "策略4结果: $result4"
    
    echo ""
done

echo "=== 推荐使用场景 ==="
echo ""
echo "• 简单计算 + 不想被错误中断：使用策略1（我们的方法）"
echo "• 数据验证很重要：使用策略2"
echo "• 需要更好的性能：使用策略3 (awk)"
echo "• 只做整数运算：使用策略4 (bash算术)"
echo ""
echo "对于 TrafficCop 项目，策略1最合适，因为："
echo "1. 流量统计允许少量误差"
echo "2. 不希望计算错误导致监控中断"
echo "3. 代码简洁易维护"
