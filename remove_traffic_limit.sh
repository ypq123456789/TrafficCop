#!/bin/bash

# TrafficCop 解除机器限速脚本 v2.0
# 使用新的管理方式，完全停止监控而不是设置超大值

echo "============================================"
echo "  TrafficCop 机器限速解除脚本 v2.0"
echo "============================================"
echo ""

# 下载并运行新的管理器
echo "正在下载机器限速管理器..."
curl -fsSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/machine_limit_manager.sh -o /tmp/machine_limit_manager.sh

if [ $? -eq 0 ]; then
    chmod +x /tmp/machine_limit_manager.sh
    echo ""
    echo "使用新的管理方式禁用机器限速..."
    bash /tmp/machine_limit_manager.sh --disable
    
    echo ""
    echo "✓ 机器限速已通过新方式完全禁用"
    echo ""
    echo "说明:"
    echo "- 监控进程已停止"
    echo "- TC限速规则已清除" 
    echo "- 定时任务已移除"
    echo "- 原配置已备份，可随时恢复"
    echo ""
    echo "如需恢复监控，请运行:"
    echo "bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/machine_limit_manager.sh)"
    
    # 清理临时文件
    rm -f /tmp/machine_limit_manager.sh
else
    echo "ERROR: 无法下载管理器，使用传统方式..."
    echo ""
    
    # 传统方式作为备用方案
    WORK_DIR="/root/TrafficCop"
    CONFIG_FILE="$WORK_DIR/traffic_monitor_config.txt"
    
    if [ -f "$CONFIG_FILE" ]; then
        # 备份原始文件
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
        
        # 修改配置为超大值 (传统方式)
        sed -i 's/TRAFFIC_LIMIT=[0-9]*/TRAFFIC_LIMIT=1000000/' "$CONFIG_FILE"
        sed -i 's/LIMIT_SPEED=[0-9]*/LIMIT_SPEED=1000000/' "$CONFIG_FILE"
        
        echo "已使用传统方式设置超大限制值"
        echo "配置文件已备份为: $CONFIG_FILE.bak"
    else
        echo "未找到配置文件，无需处理"
    fi
fi

echo ""
echo "操作完成！"
