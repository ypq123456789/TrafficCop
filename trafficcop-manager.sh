#!/bin/bash

# TrafficCop 管理器 - 交互式管理工具
# 版本 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 基础目录
WORK_DIR="/root/TrafficCop"
REPO_URL="https://raw.githubusercontent.com/ypq123456789/TrafficCop/main"

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}此脚本必须以root权限运行${NC}"
        exit 1
    fi
}

# 创建工作目录
create_work_dir() {
    mkdir -p "$WORK_DIR"
}

# 下载并安装脚本
install_script() {
    local script_name="$1"
    local output_name="${2:-$script_name}"
    local output_path="$WORK_DIR/$output_name"
    
    echo -e "${YELLOW}正在下载 $script_name...${NC}"
    curl -fsSL "$REPO_URL/$script_name" | tr -d '\r' > "$output_path"
    chmod +x "$output_path"
    
    echo -e "${GREEN}脚本 $output_name 已下载到 $output_path${NC}"
}

# 运行脚本
run_script() {
    local script_path="$1"
    if [ -f "$script_path" ]; then
        echo -e "${YELLOW}正在运行 $script_path...${NC}"
        bash "$script_path"
    else
        echo -e "${RED}脚本 $script_path 不存在${NC}"
    fi
}

# 安装流量监控
install_monitor() {
    echo -e "${CYAN}正在安装流量监控...${NC}"
    install_script "trafficcop.sh" "traffic_monitor.sh"
    run_script "$WORK_DIR/traffic_monitor.sh"
    echo -e "${GREEN}流量监控安装完成！${NC}"
    read -p "按回车键继续..."
}

# 安装Telegram通知
install_tg_notifier() {
    echo -e "${CYAN}正在安装Telegram通知功能...${NC}"
    install_script "tg_notifier.sh"
    run_script "$WORK_DIR/tg_notifier.sh"
    echo -e "${GREEN}Telegram通知功能安装完成！${NC}"
    read -p "按回车键继续..."
}

# 安装PushPlus通知
install_pushplus_notifier() {
    echo -e "${CYAN}正在安装PushPlus通知功能...${NC}"
    install_script "pushplus_notifier.sh"
    run_script "$WORK_DIR/pushplus_notifier.sh"
    echo -e "${GREEN}PushPlus通知功能安装完成！${NC}"
    read -p "按回车键继续..."
}

# 解除流量限制
remove_traffic_limit() {
    echo -e "${CYAN}正在解除流量限制...${NC}"
    install_script "remove_traffic_limit.sh"
    run_script "$WORK_DIR/remove_traffic_limit.sh"
    echo -e "${GREEN}流量限制已解除！${NC}"
    read -p "按回车键继续..."
}

# 查看日志
view_logs() {
    echo -e "${CYAN}查看日志${NC}"
    echo "1) 流量监控日志"
    echo "2) Telegram通知日志"
    echo "3) PushPlus通知日志"
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的日志类型 [0-3]: " log_choice
    
    case $log_choice in
        1)
            if [ -f "$WORK_DIR/traffic_monitor.log" ]; then
                tail -n 30 "$WORK_DIR/traffic_monitor.log"
            else
                echo -e "${RED}流量监控日志不存在${NC}"
            fi
            ;;
        2)
            if [ -f "$WORK_DIR/tg_notifier_cron.log" ]; then
                tail -n 30 "$WORK_DIR/tg_notifier_cron.log"
            else
                echo -e "${RED}Telegram通知日志不存在${NC}"
            fi
            ;;
        3)
            if [ -f "$WORK_DIR/pushplus_notifier_cron.log" ]; then
                tail -n 30 "$WORK_DIR/pushplus_notifier_cron.log"
            else
                echo -e "${RED}PushPlus通知日志不存在${NC}"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 查看当前配置
view_config() {
    echo -e "${CYAN}查看当前配置${NC}"
    echo "1) 流量监控配置"
    echo "2) Telegram通知配置"
    echo "3) PushPlus通知配置"
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的配置类型 [0-3]: " config_choice
    
    case $config_choice in
        1)
            if [ -f "$WORK_DIR/traffic_monitor_config.txt" ]; then
                cat "$WORK_DIR/traffic_monitor_config.txt"
            else
                echo -e "${RED}流量监控配置不存在${NC}"
            fi
            ;;
        2)
            if [ -f "$WORK_DIR/tg_notifier_config.txt" ]; then
                cat "$WORK_DIR/tg_notifier_config.txt"
            else
                echo -e "${RED}Telegram通知配置不存在${NC}"
            fi
            ;;
        3)
            if [ -f "$WORK_DIR/pushplus_notifier_config.txt" ]; then
                cat "$WORK_DIR/pushplus_notifier_config.txt"
            else
                echo -e "${RED}PushPlus通知配置不存在${NC}"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 使用预设配置
use_preset_config() {
    echo -e "${CYAN}使用预设配置${NC}"
    echo "1) 阿里云CDT 200G"
    echo "2) 阿里云CDT 20G"
    echo "3) 阿里云轻量 1T"
    echo "4) azure学生 15G"
    echo "5) azure学生 115G"
    echo "6) GCP 625G（大流量极致解法）"
    echo "7) GCP 200G（白嫖标准路由200g流量）"
    echo "8) alice 1500G"
    echo "9) 亚洲云 300G"
    echo "0) 返回主菜单"
    
    read -p "请选择预设配置 [0-9]: " preset_choice
    
    case $preset_choice in
        1)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/ali-200g"
            echo -e "${GREEN}已应用阿里云CDT 200G配置${NC}"
            ;;
        2)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/ali-20g"
            echo -e "${GREEN}已应用阿里云CDT 20G配置${NC}"
            ;;
        3)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/ali-1T"
            echo -e "${GREEN}已应用阿里云轻量 1T配置${NC}"
            ;;
        4)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/az-15g"
            echo -e "${GREEN}已应用azure学生 15G配置${NC}"
            ;;
        5)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/az-115g"
            echo -e "${GREEN}已应用azure学生 115G配置${NC}"
            ;;
        6)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/GCP-625g"
            echo -e "${GREEN}已应用GCP 625G配置${NC}"
            ;;
        7)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/GCP-200g"
            echo -e "${GREEN}已应用GCP 200G配置${NC}"
            ;;
        8)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/alice-1500g"
            echo -e "${GREEN}已应用alice 1500G配置${NC}"
            ;;
        9)
            curl -o "$WORK_DIR/traffic_monitor_config.txt" "$REPO_URL/asia-300g"
            echo -e "${GREEN}已应用亚洲云 300G配置${NC}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
    
    if [ -f "$WORK_DIR/traffic_monitor_config.txt" ]; then
        cat "$WORK_DIR/traffic_monitor_config.txt"
    fi
    
    read -p "按回车键继续..."
}

# 停止所有服务
stop_all_services() {
    echo -e "${CYAN}正在停止所有TrafficCop服务...${NC}"
    pkill -f traffic_monitor.sh 2>/dev/null || true
    pkill -f tg_notifier.sh 2>/dev/null || true
    pkill -f pushplus_notifier.sh 2>/dev/null || true
    
    # 清理crontab
    crontab -l | grep -v "traffic_monitor.sh" | grep -v "tg_notifier.sh" | grep -v "pushplus_notifier.sh" | crontab -
    
    echo -e "${GREEN}所有TrafficCop服务已停止${NC}"
    read -p "按回车键继续..."
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${PURPLE}====================================${NC}"
    echo -e "${PURPLE}     TrafficCop 管理工具 v1.0      ${NC}"
    echo -e "${PURPLE}====================================${NC}"
    echo -e "${YELLOW}1) 安装流量监控${NC}"
    echo -e "${YELLOW}2) 安装Telegram通知功能${NC}"
    echo -e "${YELLOW}3) 安装PushPlus通知功能${NC}"
    echo -e "${YELLOW}4) 解除流量限制${NC}"
    echo -e "${YELLOW}5) 查看日志${NC}"
    echo -e "${YELLOW}6) 查看当前配置${NC}"
    echo -e "${YELLOW}7) 使用预设配置${NC}"
    echo -e "${YELLOW}8) 停止所有服务${NC}"
    echo -e "${YELLOW}0) 退出${NC}"
    echo -e "${PURPLE}====================================${NC}"
    echo ""
}

# 主函数
main() {
    check_root
    create_work_dir
    
    while true; do
        show_main_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                install_monitor
                ;;
            2)
                install_tg_notifier
                ;;
            3)
                install_pushplus_notifier
                ;;
            4)
                remove_traffic_limit
                ;;
            5)
                view_logs
                ;;
            6)
                view_config
                ;;
            7)
                use_preset_config
                ;;
            8)
                stop_all_services
                ;;
            0)
                echo -e "${GREEN}感谢使用TrafficCop管理工具！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main
