#!/bin/bash

# TrafficCop 管理器 - 交互式管理工具
# 版本 1.2
# 最后更新：2025-10-19 00:20

SCRIPT_VERSION="1.2"
LAST_UPDATE="2025-10-19 00:20"

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

# 安装Server酱通知
install_serverchan_notifier() {
    echo -e "${CYAN}正在安装Server酱通知功能...${NC}"
    # 检查serverchan_notifier.sh是否在仓库中，如果不在，使用本地的
    if curl -s --head "$REPO_URL/serverchan_notifier.sh" | grep "HTTP/2 200\|HTTP/1.1 200" > /dev/null; then
        install_script "serverchan_notifier.sh"
    else
        echo -e "${YELLOW}从仓库下载失败，使用本地文件...${NC}"
        # 复制当前目录下的serverchan_notifier.sh到工作目录
        if [ -f "serverchan_notifier.sh" ]; then
            cp "serverchan_notifier.sh" "$WORK_DIR/serverchan_notifier.sh"
            chmod +x "$WORK_DIR/serverchan_notifier.sh"
        else
            echo -e "${RED}本地serverchan_notifier.sh文件不存在！${NC}"
            read -p "按回车键继续..."
            return
        fi
    fi
    run_script "$WORK_DIR/serverchan_notifier.sh"
    echo -e "${GREEN}Server酱通知功能安装完成！${NC}"
    read -p "按回车键继续..."
}

# 安装端口流量限制
install_port_traffic_limit() {
    echo -e "${CYAN}正在安装端口流量限制功能...${NC}"
    
    # 安装主配置脚本
    install_script "port_traffic_limit.sh"
    
    # 安装端口流量查看脚本
    echo -e "${YELLOW}正在下载端口流量查看脚本...${NC}"
    install_script "view_port_traffic.sh"
    
    # 安装辅助函数库
    echo -e "${YELLOW}正在下载辅助函数库...${NC}"
    install_script "port_traffic_helper.sh"
    
    # 运行配置向导
    run_script "$WORK_DIR/port_traffic_limit.sh"
    
    echo -e "${GREEN}端口流量限制功能安装完成！${NC}"
    echo -e "${CYAN}提示：使用选项5可管理端口配置，支持序号快速选择${NC}"
    read -p "按回车键继续..."
}

# 解除端口流量限制
remove_port_traffic_limit() {
    echo -e "${CYAN}正在解除端口流量限制...${NC}"
    if [ -f "$WORK_DIR/port_traffic_limit.sh" ]; then
        bash "$WORK_DIR/port_traffic_limit.sh" --remove
        echo -e "${GREEN}端口流量限制已解除！${NC}"
        echo -e "${YELLOW}注意：配置文件和查看脚本仍保留，可继续使用选项12/13管理${NC}"
    else
        echo -e "${RED}端口流量限制脚本不存在${NC}"
    fi
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
    echo "4) Server酱通知日志"
    echo "5) 端口流量监控日志"
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的日志类型 [0-5]: " log_choice
    
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
        4)
            if [ -f "$WORK_DIR/serverchan_notifier_cron.log" ]; then
                tail -n 30 "$WORK_DIR/serverchan_notifier_cron.log"
            else
                echo -e "${RED}Server酱通知日志不存在${NC}"
            fi
            ;;
        5)
            if [ -f "$WORK_DIR/port_traffic_monitor.log" ]; then
                tail -n 30 "$WORK_DIR/port_traffic_monitor.log"
            else
                echo -e "${RED}端口流量监控日志不存在${NC}"
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
    echo "4) Server酱通知配置"
    echo "5) 端口流量监控配置"
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的配置类型 [0-5]: " config_choice
    
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
        4)
            if [ -f "$WORK_DIR/serverchan_notifier_config.txt" ]; then
                cat "$WORK_DIR/serverchan_notifier_config.txt"
            else
                echo -e "${RED}Server酱通知配置不存在${NC}"
            fi
            ;;
        5)
            if [ -f "$WORK_DIR/port_traffic_config.txt" ]; then
                cat "$WORK_DIR/port_traffic_config.txt"
            else
                echo -e "${RED}端口流量监控配置不存在${NC}"
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
    pkill -f serverchan_notifier.sh 2>/dev/null || true
    pkill -f port_traffic_monitor.sh 2>/dev/null || true
    
    # 清理crontab
    crontab -l | grep -v "traffic_monitor.sh" | grep -v "tg_notifier.sh" | grep -v "pushplus_notifier.sh" | grep -v "serverchan_notifier.sh" | grep -v "port_traffic_monitor.sh" | crontab -
    
    echo -e "${GREEN}所有TrafficCop服务已停止${NC}"
    read -p "按回车键继续..."
}

# 查看端口流量
view_port_traffic() {
    clear
    if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
        bash "$WORK_DIR/view_port_traffic.sh"
    else
        echo -e "${RED}端口流量查看脚本不存在！${NC}"
        echo -e "${YELLOW}请先安装端口流量限制功能${NC}"
    fi
    echo ""
    read -p "按回车键继续..."
}

# 安装/管理端口配置
manage_port_config() {
    clear
    if [ -f "$WORK_DIR/port_traffic_limit.sh" ]; then
        # 已安装，直接进入管理界面
        bash "$WORK_DIR/port_traffic_limit.sh"
    else
        # 未安装，先安装
        echo -e "${YELLOW}检测到端口流量限制功能未安装${NC}"
        echo ""
        read -p "是否现在安装？[Y/n]: " install_confirm
        [ -z "$install_confirm" ] && install_confirm="y"
        
        if [[ "$install_confirm" = "y" || "$install_confirm" = "Y" ]]; then
            install_port_traffic_limit
        else
            echo ""
            read -p "按回车键继续..."
        fi
    fi
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${PURPLE}====================================${NC}"
    echo -e "${PURPLE}   TrafficCop 管理工具 v${SCRIPT_VERSION}     ${NC}"
    echo -e "${PURPLE}====================================${NC}"
    echo -e "${CYAN}最后更新: ${LAST_UPDATE}${NC}"
    echo ""
    echo -e "${YELLOW}1) 安装流量监控${NC}"
    echo -e "${YELLOW}2) 安装Telegram通知功能${NC}"
    echo -e "${YELLOW}3) 安装PushPlus通知功能${NC}"
    echo -e "${YELLOW}4) 安装Server酱通知功能${NC}"
    echo -e "${YELLOW}5) 安装/管理端口流量限制${NC}"
    echo -e "${YELLOW}6) 解除流量限制${NC}"
    echo -e "${YELLOW}7) 查看日志${NC}"
    echo -e "${YELLOW}8) 查看当前配置${NC}"
    echo -e "${YELLOW}9) 使用预设配置${NC}"
    echo -e "${YELLOW}10) 停止所有服务${NC}"
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
        read -p "请选择操作 [0-10]: " choice
        
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
                install_serverchan_notifier
                ;;
            5)
                manage_port_config
                ;;
            6)
                remove_traffic_limit
                ;;
            7)
                view_logs
                ;;
            8)
                view_config
                ;;
            9)
                use_preset_config
                ;;
            10)
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
