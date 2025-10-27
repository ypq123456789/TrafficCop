#!/bin/bash

# Telegram通知脚本 - 时间设置工具
# 用法: bash set_daily_time.sh HH:MM

WORK_DIR="/root/TrafficCop"
CONFIG_FILE="$WORK_DIR/tg_notifier_config.txt"
CRON_LOG="$WORK_DIR/tg_notifier_cron.log"

if [ $# -ne 1 ]; then
    echo "用法: $0 HH:MM"
    echo "示例: $0 09:30"
    exit 1
fi

new_time="$1"

# 验证时间格式
if [[ ! $new_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "错误: 无效的时间格式。请使用 HH:MM 格式 (如: 09:30)"
    exit 1
fi

echo "正在修改每日报告时间为: $new_time"

# 备份配置文件
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# 使用awk修改配置
awk -v new_time="$new_time" '
/^DAILY_REPORT_TIME=/ { print "DAILY_REPORT_TIME=" new_time; next }
{ print }
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "每日报告时间已更新为: $new_time"

# 立即刷新端口流量缓存
echo "正在刷新端口流量缓存..."

if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
    cd "$WORK_DIR"
    
    # 执行端口流量收集并保存到缓存
    cache_file="/tmp/port_traffic_cache_$(date '+%Y-%m-%d_%H:%M:%S')_manual.json"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : [手动设置时间] 开始刷新缓存" >> "$CRON_LOG"
    
    # 获取端口流量数据
    PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH" bash view_port_traffic.sh --json > "$cache_file.tmp" 2>&1
    exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -s "$cache_file.tmp" ]; then
        # 添加元数据
        {
            echo "{"
            echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
            echo "  \"source\": \"manual_time_change\","
            echo "  \"data\": $(cat "$cache_file.tmp")"
            echo "}"
        } > "$cache_file"
        
        rm -f "$cache_file.tmp"
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [手动设置时间] 缓存已刷新: $cache_file" >> "$CRON_LOG"
        echo "✅ 缓存已刷新，定时推送将使用最新数据"
        
        # 显示缓存的数据摘要
        ports_summary=$(cat "$cache_file" | jq -r '.data.ports[] | "\(.port):\(.usage)GB"' 2>/dev/null | tr '\n' ' ')
        if [ -n "$ports_summary" ]; then
            echo "端口流量数据: $ports_summary"
            echo "$(date '+%Y-%m-%d %H:%M:%S') : [手动设置时间] 端口数据摘要: $ports_summary" >> "$CRON_LOG"
        fi
    else
        echo "❌ 缓存刷新失败，但时间已修改"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : [手动设置时间] 缓存刷新失败 (exit code: $exit_code)" >> "$CRON_LOG"
        if [ -f "$cache_file.tmp" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : [手动设置时间] 错误输出: $(cat "$cache_file.tmp")" >> "$CRON_LOG"
            rm -f "$cache_file.tmp"
        fi
    fi
else
    echo "⚠️  未找到 view_port_traffic.sh，时间已修改但未刷新缓存"
fi

echo
echo "修改完成！新的每日报告时间: $new_time"
echo "定时任务将在下次执行时使用新时间。"
