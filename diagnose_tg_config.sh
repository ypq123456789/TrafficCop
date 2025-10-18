#!/bin/bash

# TG通知配置诊断脚本

echo "=========================================="
echo "   Telegram通知配置诊断工具"
echo "=========================================="
echo ""

WORK_DIR="/root/TrafficCop"
CONFIG_FILE="$WORK_DIR/tg_notifier_config.txt"

echo "1. 检查配置文件是否存在..."
if [ -f "$CONFIG_FILE" ]; then
    echo "   ✓ 配置文件存在: $CONFIG_FILE"
    echo ""
    
    echo "2. 检查配置文件大小..."
    file_size=$(stat -f%z "$CONFIG_FILE" 2>/dev/null || stat -c%s "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$file_size" ] && [ "$file_size" -gt 0 ]; then
        echo "   ✓ 配置文件大小: ${file_size} 字节"
    else
        echo "   ✗ 配置文件为空！"
        exit 1
    fi
    echo ""
    
    echo "3. 显示配置文件内容..."
    echo "   ----------------------------------------"
    cat "$CONFIG_FILE"
    echo "   ----------------------------------------"
    echo ""
    
    echo "4. 读取并检查配置项..."
    source "$CONFIG_FILE"
    
    echo "   检查 BOT_TOKEN..."
    if [ -z "$BOT_TOKEN" ]; then
        echo "   ✗ BOT_TOKEN 未设置或为空！"
        has_error=1
    else
        echo "   ✓ BOT_TOKEN: ${BOT_TOKEN:0:10}... (已隐藏)"
    fi
    
    echo "   检查 CHAT_ID..."
    if [ -z "$CHAT_ID" ]; then
        echo "   ✗ CHAT_ID 未设置或为空！"
        has_error=1
    else
        echo "   ✓ CHAT_ID: $CHAT_ID"
    fi
    
    echo "   检查 MACHINE_NAME..."
    if [ -z "$MACHINE_NAME" ]; then
        echo "   ✗ MACHINE_NAME 未设置或为空！"
        has_error=1
    else
        echo "   ✓ MACHINE_NAME: $MACHINE_NAME"
    fi
    
    echo "   检查 DAILY_REPORT_TIME..."
    if [ -z "$DAILY_REPORT_TIME" ]; then
        echo "   ✗ DAILY_REPORT_TIME 未设置或为空！"
        has_error=1
    else
        echo "   ✓ DAILY_REPORT_TIME: $DAILY_REPORT_TIME"
    fi
    echo ""
    
    if [ -n "$has_error" ]; then
        echo "=========================================="
        echo "   发现配置问题！"
        echo "=========================================="
        echo ""
        echo "建议操作："
        echo "1. 运行管理工具重新配置"
        echo "   bash /root/TrafficCop/trafficcop-manager.sh"
        echo ""
        echo "2. 选择 2) 安装Telegram通知功能"
        echo ""
        echo "3. 重新输入所有配置信息"
        echo ""
    else
        echo "=========================================="
        echo "   配置检查通过！✓"
        echo "=========================================="
        echo ""
        echo "所有必需的配置项都已正确设置。"
        echo ""
        echo "如果仍然提示配置不存在，可能是："
        echo "1. 脚本没有正确读取配置文件"
        echo "2. 定时任务使用的是旧版本脚本"
        echo ""
        echo "建议操作："
        echo "1. 重新安装最新版本："
        echo "   bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop-manager.sh)"
        echo ""
        echo "2. 重新配置 Telegram 通知"
        echo ""
    fi
    
else
    echo "   ✗ 配置文件不存在: $CONFIG_FILE"
    echo ""
    echo "=========================================="
    echo "   配置文件未找到！"
    echo "=========================================="
    echo ""
    echo "建议操作："
    echo "1. 运行管理工具进行配置"
    echo "   bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop-manager.sh)"
    echo ""
    echo "2. 选择 2) 安装Telegram通知功能"
    echo ""
fi

echo ""
echo "=========================================="
echo "   额外检查"
echo "=========================================="
echo ""

echo "5. 检查定时任务..."
if crontab -l 2>/dev/null | grep -q "tg_notifier.sh"; then
    echo "   ✓ 找到定时任务："
    crontab -l 2>/dev/null | grep "tg_notifier.sh"
else
    echo "   ✗ 未找到定时任务"
fi
echo ""

echo "6. 检查脚本文件..."
if [ -f "/root/TrafficCop/tg_notifier.sh" ]; then
    echo "   ✓ 脚本文件存在"
    echo "   文件大小: $(stat -f%z "/root/TrafficCop/tg_notifier.sh" 2>/dev/null || stat -c%s "/root/TrafficCop/tg_notifier.sh" 2>/dev/null) 字节"
else
    echo "   ✗ 脚本文件不存在"
fi
echo ""

echo "7. 检查日志文件..."
if [ -f "/root/TrafficCop/tg_notifier_cron.log" ]; then
    echo "   ✓ 日志文件存在"
    echo "   最后10行日志："
    echo "   ----------------------------------------"
    tail -n 10 "/root/TrafficCop/tg_notifier_cron.log" | sed 's/^/   /'
    echo "   ----------------------------------------"
else
    echo "   ✗ 日志文件不存在"
fi
echo ""

echo "=========================================="
echo "   诊断完成"
echo "=========================================="
