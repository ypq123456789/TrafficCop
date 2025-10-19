#!/bin/bash

# TrafficCop 机器限速管理脚本 v2.0
# 提供完整的启用/禁用/恢复机器限速功能

WORK_DIR="/root/TrafficCop"
CONFIG_FILE="$WORK_DIR/traffic_monitor_config.txt"
BACKUP_CONFIG_FILE="$CONFIG_FILE.disabled.backup"
SCRIPT_PATH="$WORK_DIR/trafficcop.sh"
CRON_COMMENT="# TrafficCop Monitor"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查网络接口
get_main_interface() {
    ip route | grep default | awk '{print $5}' | head -n1
}

# 清除TC限速规则
clear_tc_rules() {
    local interface=$(get_main_interface)
    if [ -n "$interface" ]; then
        echo "清除网络接口 $interface 的TC限速规则..."
        tc qdisc del dev "$interface" root 2>/dev/null || true
        echo "✓ TC限速规则已清除"
    fi
}

# 停止监控进程
stop_monitor_process() {
    echo "停止TrafficCop监控进程..."
    
    # 杀死相关进程
    pkill -f "trafficcop.sh" 2>/dev/null || true
    pkill -f "traffic_monitor.sh" 2>/dev/null || true
    
    echo "✓ 监控进程已停止"
}

# 移除定时任务
remove_cron_job() {
    echo "移除定时任务..."
    
    # 备份当前crontab
    crontab -l > /tmp/crontab_backup.txt 2>/dev/null || true
    
    # 移除TrafficCop相关的定时任务
    crontab -l 2>/dev/null | grep -v "trafficcop.sh\|traffic_monitor.sh" | crontab - 2>/dev/null || true
    
    echo "✓ 定时任务已移除"
}

# 添加定时任务
add_cron_job() {
    echo "添加定时任务..."
    
    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "trafficcop.sh"; then
        echo "! 定时任务已存在"
        return
    fi
    
    # 添加新的定时任务
    (crontab -l 2>/dev/null; echo "*/5 * * * * cd $WORK_DIR && bash trafficcop.sh --cron $CRON_COMMENT") | crontab -
    
    echo "✓ 定时任务已添加"
}

# 完全禁用机器限速
disable_machine_limit() {
    echo -e "${YELLOW}==================== 禁用机器限速 ====================${NC}"
    echo ""
    
    # 1. 停止监控进程
    stop_monitor_process
    
    # 2. 清除TC限速规则
    clear_tc_rules
    
    # 3. 移除定时任务
    remove_cron_job
    
    # 4. 备份并标记配置文件
    if [ -f "$CONFIG_FILE" ]; then
        echo "备份当前配置..."
        cp "$CONFIG_FILE" "$BACKUP_CONFIG_FILE"
        echo "DISABLED=true" >> "$CONFIG_FILE"
        echo "DISABLED_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_FILE"
        echo "✓ 配置已备份并标记为禁用"
    fi
    
    # 5. 取消可能的关机计划
    shutdown -c 2>/dev/null || true
    echo "✓ 已取消关机计划"
    
    echo ""
    echo -e "${GREEN}✓ 机器限速已完全禁用${NC}"
    echo -e "${CYAN}说明: 原配置已备份，可随时恢复${NC}"
}

# 启用机器限速
enable_machine_limit() {
    echo -e "${YELLOW}==================== 启用机器限速 ====================${NC}"
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 未找到配置文件 $CONFIG_FILE${NC}"
        echo "请先运行 trafficcop.sh 进行初始配置"
        return 1
    fi
    
    # 1. 恢复配置文件（移除DISABLED标记）
    if grep -q "DISABLED=true" "$CONFIG_FILE" 2>/dev/null; then
        echo "恢复配置文件..."
        grep -v "DISABLED\|DISABLED_TIME" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "✓ 配置文件已恢复"
    fi
    
    # 2. 添加定时任务
    add_cron_job
    
    # 3. 立即执行一次监控（测试配置）
    echo "启动TrafficCop监控测试..."
    cd "$WORK_DIR"
    bash "$SCRIPT_PATH" --cron
    
    echo ""
    echo -e "${GREEN}✓ 机器限速已启用${NC}"
    echo -e "${CYAN}监控将通过定时任务每5分钟执行一次${NC}"
    echo -e "${CYAN}刚才已执行一次测试，可在日志中查看结果${NC}"
}

# 恢复之前的配置
restore_machine_limit() {
    echo -e "${YELLOW}==================== 恢复机器限速 ====================${NC}"
    echo ""
    
    if [ ! -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "${RED}错误: 未找到备份配置文件${NC}"
        echo "无法恢复，请手动重新配置"
        return 1
    fi
    
    # 恢复配置文件
    echo "恢复备份配置..."
    cp "$BACKUP_CONFIG_FILE" "$CONFIG_FILE"
    echo "✓ 配置已恢复"
    
    # 启用监控
    enable_machine_limit
}

# 查看当前状态
show_status() {
    echo -e "${CYAN}==================== 当前状态 ====================${NC}"
    echo ""
    
    # 检查配置文件
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q "DISABLED=true" "$CONFIG_FILE" 2>/dev/null; then
            local disabled_time=$(grep "DISABLED_TIME=" "$CONFIG_FILE" | cut -d'=' -f2)
            echo -e "配置状态: ${RED}已禁用${NC} (禁用时间: $disabled_time)"
        else
            echo -e "配置状态: ${GREEN}已启用${NC}"
        fi
    else
        echo -e "配置状态: ${YELLOW}未配置${NC}"
    fi
    
    # 检查进程状态（检查最近的执行记录而不是实时进程）
    local last_run=$(grep "当前版本" "$WORK_DIR/traffic_monitor.log" 2>/dev/null | tail -1 | awk '{print $1, $2}')
    if [ -n "$last_run" ]; then
        local last_run_timestamp=$(date -d "$last_run" +%s 2>/dev/null || echo "0")
        local current_timestamp=$(date +%s)
        local time_diff=$((current_timestamp - last_run_timestamp))
        
        if [ $time_diff -lt 600 ]; then  # 10分钟内有执行记录
            echo -e "监控进程: ${GREEN}运行中${NC} (最后执行: $last_run)"
        else
            echo -e "监控进程: ${YELLOW}空闲中${NC} (最后执行: $last_run)"
        fi
    else
        echo -e "监控进程: ${RED}未运行${NC}"
    fi
    
    # 检查定时任务
    if crontab -l 2>/dev/null | grep -q "trafficcop.sh"; then
        echo -e "定时任务: ${GREEN}已设置${NC}"
    else
        echo -e "定时任务: ${RED}未设置${NC}"
    fi
    
    # 检查TC规则
    local interface=$(get_main_interface)
    if [ -n "$interface" ] && tc qdisc show dev "$interface" | grep -q "tbf"; then
        echo -e "TC限速: ${YELLOW}已激活${NC}"
    else
        echo -e "TC限速: ${GREEN}未激活${NC}"
    fi
    
    # 检查备份
    if [ -f "$BACKUP_CONFIG_FILE" ]; then
        echo -e "配置备份: ${GREEN}存在${NC}"
    else
        echo -e "配置备份: ${YELLOW}不存在${NC}"
    fi
}

# 详细状态检查
show_detailed_status() {
    echo -e "${CYAN}==================== 详细状态 ====================${NC}"
    echo ""
    
    # 基本状态
    show_status
    echo ""
    
    # 检查配置文件内容
    echo -e "${CYAN}配置文件内容:${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo -e "${RED}配置文件不存在${NC}"
    fi
    echo ""
    
    # 检查定时任务详情
    echo -e "${CYAN}定时任务详情:${NC}"
    crontab -l 2>/dev/null | grep -v "^#" | grep "trafficcop\|traffic_monitor" || echo "无相关定时任务"
    echo ""
    
    # 检查最近的日志
    echo -e "${CYAN}最近的监控日志 (最后10行):${NC}"
    if [ -f "$WORK_DIR/traffic_monitor.log" ]; then
        tail -10 "$WORK_DIR/traffic_monitor.log"
    else
        echo "日志文件不存在"
    fi
    echo ""
    
    # 检查当前流量使用
    echo -e "${CYAN}当前流量统计:${NC}"
    if command -v vnstat >/dev/null 2>&1; then
        vnstat -i $(get_main_interface) --oneline 2>/dev/null | head -1 || echo "无法获取流量统计"
    else
        echo "vnstat 未安装"
    fi
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        TrafficCop 机器限速管理         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    show_status
    echo ""
    echo "选择操作:"
    echo "1) 禁用机器限速 (完全停止监控)"
    echo "2) 启用机器限速 (恢复监控)"
    echo "3) 恢复之前配置 (从备份恢复)"
    echo "4) 查看详细状态"
    echo "5) 清除TC限速规则 (仅清除当前限速)"
    echo "0) 退出"
    echo ""
}

# 主程序
main() {
    # 创建工作目录
    mkdir -p "$WORK_DIR"
    
    if [ "$1" = "--disable" ]; then
        disable_machine_limit
        exit 0
    elif [ "$1" = "--enable" ]; then
        enable_machine_limit
        exit 0
    elif [ "$1" = "--status" ]; then
        show_status
        exit 0
    fi
    
    while true; do
        show_menu
        read -p "请选择 [0-5]: " choice
        
        case $choice in
            1)
                echo ""
                read -p "确认禁用机器限速？这将停止所有监控 [y/N]: " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    disable_machine_limit
                    read -p "按回车键继续..."
                fi
                ;;
            2)
                echo ""
                enable_machine_limit
                read -p "按回车键继续..."
                ;;
            3)
                echo ""
                restore_machine_limit
                read -p "按回车键继续..."
                ;;
            4)
                echo ""
                show_detailed_status
                read -p "按回车键继续..."
                ;;
            5)
                echo ""
                clear_tc_rules
                read -p "按回车键继续..."
                ;;
            0)
                echo "退出"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
