#!/bin/bash

# TrafficCop VPS 更新脚本 - 解决 git 冲突并应用最新修复

echo "=========================================="
echo "TrafficCop VPS 更新脚本"
echo "=========================================="
echo ""

cd /root/TrafficCop || exit 1

echo "📋 当前 Git 状态:"
git status --short
echo ""

echo "🔍 检查本地修改..."
if git diff --quiet && git diff --cached --quiet; then
    echo "✅ 没有本地修改,直接拉取"
    git pull
else
    echo "⚠️  发现本地修改,需要处理"
    echo ""
    
    # 显示修改的内容
    echo "📝 本地修改内容预览:"
    git diff trafficcop.sh | head -20
    echo ""
    
    # 备份当前文件
    BACKUP_FILE="/root/trafficcop.sh.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 备份当前文件到: $BACKUP_FILE"
    cp trafficcop.sh "$BACKUP_FILE"
    echo ""
    
    # 提供三种选项
    echo "请选择处理方式:"
    echo "  1) 保存本地修改并拉取(stash)"
    echo "  2) 放弃本地修改并拉取(hard reset)"
    echo "  3) 手动处理(退出脚本)"
    echo ""
    read -p "请输入选项 [1-3]: " -t 30 choice || choice="1"
    
    case $choice in
        1)
            echo ""
            echo "📦 保存本地修改..."
            git stash push -m "Auto stash before update $(date)"
            echo ""
            echo "⬇️  拉取最新代码..."
            git pull
            echo ""
            echo "🔄 尝试应用本地修改..."
            if git stash pop; then
                echo "✅ 本地修改已合并"
            else
                echo "⚠️  合并冲突!需要手动解决"
                echo "   备份文件: $BACKUP_FILE"
                echo "   运行 'git status' 查看冲突"
            fi
            ;;
        2)
            echo ""
            echo "🗑️  放弃本地修改..."
            git reset --hard HEAD
            echo ""
            echo "⬇️  拉取最新代码..."
            git pull
            echo "✅ 更新完成"
            ;;
        3)
            echo ""
            echo "ℹ️  退出脚本,请手动处理"
            echo "   备份文件: $BACKUP_FILE"
            echo ""
            echo "手动处理命令:"
            echo "  git stash          # 保存修改"
            echo "  git pull           # 拉取更新"
            echo "  git stash pop      # 应用修改"
            exit 0
            ;;
        *)
            echo "❌ 无效选项,退出"
            exit 1
            ;;
    esac
fi

echo ""
echo "=========================================="
echo "📊 更新后状态"
echo "=========================================="
echo ""

# 显示最新的提交
echo "📝 最新提交:"
git log --oneline -3
echo ""

# 显示当前版本
CURRENT_VERSION=$(grep "^VERSION=" trafficcop.sh | cut -d'"' -f2)
echo "🏷️  当前版本: $CURRENT_VERSION"
echo ""

# 测试脚本是否可以正常加载
echo "🧪 测试脚本加载..."
if bash -c 'source /root/TrafficCop/trafficcop.sh 2>&1 | grep -q "当前版本"'; then
    echo "✅ 脚本可以正常加载"
else
    echo "⚠️  脚本加载可能有问题"
fi
echo ""

# 快速测试流量查询
echo "🧪 快速测试流量查询..."
TEST_RESULT=$(timeout 10 bash -c 'source /root/TrafficCop/trafficcop.sh 2>/dev/null && get_traffic_usage' 2>&1)

if echo "$TEST_RESULT" | grep -q "jq: error"; then
    echo "❌ 仍然存在 jq 语法错误!"
    echo "   可能需要手动检查 trafficcop.sh"
elif [ -n "$TEST_RESULT" ] && [[ "$TEST_RESULT" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "✅ 流量查询正常: $TEST_RESULT GB"
    
    # 判断结果是否合理
    if (( $(echo "$TEST_RESULT < 1" | bc -l) )); then
        echo "✅ 流量统计修复成功!(今日重置日应该接近0)"
    else
        echo "⚠️  流量值较大: $TEST_RESULT GB"
        echo "   如果今天是重置日,这个值应该很小"
    fi
else
    echo "⚠️  查询结果异常: $TEST_RESULT"
fi
echo ""

echo "=========================================="
echo "✅ 更新流程完成!"
echo "=========================================="
echo ""
echo "接下来可以:"
echo "  1) 运行验证脚本: bash test_traffic_fix.sh"
echo "  2) 查看流量状态: ./trafficcop.sh --view"
echo "  3) 手动测试查询: bash -c 'source trafficcop.sh && get_traffic_usage'"
echo ""
