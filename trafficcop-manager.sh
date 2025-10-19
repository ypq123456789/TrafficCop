#!/bin/bash

# TrafficCop 管理器 - 交互式管理工具
# 版本 2.3
# 最后更新：2025-10-19 18:30

SCRIPT_VERSION="2.3"
LAST_UPDATE="2025-10-19 18:30"

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
    cd "$WORK_DIR"
}

# 下载脚本
install_script() {
    local script_name="$1"
    echo -e "${YELLOW}正在下载 $script_name...${NC}"
    curl -fsSL "$REPO_URL/$script_name" -o "$WORK_DIR/$script_name"
    chmod +x "$WORK_DIR/$script_name"
}

# 运行脚本
run_script() {
    local script_path="$1"
    bash "$script_path"
}

# 安装流量监控
install_monitor() {
    echo -e "${CYAN}正在安装流量监控功能...${NC}"
    install_script "trafficcop.sh"
    run_script "$WORK_DIR/trafficcop.sh"
    echo -e "${GREEN}流量监控功能安装完成！${NC}"
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
    
    # 检查pushplus_notifier.sh是否在仓库中，如果不在，使用本地的
    if curl -s --head "$REPO_URL/pushplus_notifier.sh" | grep "HTTP/2 200\|HTTP/1.1 200" > /dev/null; then
        install_script "pushplus_notifier.sh"
    else
        echo -e "${YELLOW}从仓库下载失败，使用本地文件...${NC}"
        # 复制当前目录下的pushplus_notifier.sh到工作目录
        if [ -f "pushplus_notifier.sh" ]; then
            cp "pushplus_notifier.sh" "$WORK_DIR/pushplus_notifier.sh"
            chmod +x "$WORK_DIR/pushplus_notifier.sh"
        else
            echo -e "${RED}本地pushplus_notifier.sh文件不存在！${NC}"
            read -p "按回车键继续..."
            return
        fi
    fi
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

# 管理端口配置
manage_port_config() {
    echo -e "${CYAN}端口配置管理${NC}"
    
    if [ ! -f "$WORK_DIR/port_traffic_limit.sh" ]; then
        echo -e "${RED}端口流量限制脚本不存在，请先安装${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    run_script "$WORK_DIR/port_traffic_limit.sh"
}

# 查看端口流量状态
view_port_traffic() {
    echo -e "${CYAN}正在查看端口流量状态...${NC}"
    
    # 确保脚本存在
    if [ ! -f "$WORK_DIR/view_port_traffic.sh" ]; then
        echo -e "${YELLOW}端口流量查看脚本不存在，正在下载...${NC}"
        install_script "view_port_traffic.sh"
    fi
    
    if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
        run_script "$WORK_DIR/view_port_traffic.sh"
    else
        echo -e "${RED}无法下载端口流量查看脚本${NC}"
        read -p "按回车键继续..."
    fi
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

# 查看日志
view_logs() {
    echo -e "${CYAN}查看日志${NC}"
    echo "1) 流量监控日志"
    echo "2) Telegram通知日志"
    echo "3) PushPlus通知日志"
    echo "4) Server酱通知日志"
    echo "5) 端口流量监控日志"
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的日志 [0-5]: " log_choice
    
    case $log_choice in
        1)
            if [ -f "$WORK_DIR/traffic_monitor.log" ]; then
                tail -50 "$WORK_DIR/traffic_monitor.log"
            else
                echo -e "${RED}流量监控日志不存在${NC}"
            fi
            ;;
        2)
            if [ -f "$WORK_DIR/tg_notifier.log" ]; then
                tail -20 "$WORK_DIR/tg_notifier.log"
            else
                echo -e "${RED}Telegram通知日志不存在${NC}"
            fi
            ;;
        3)
            if [ -f "$WORK_DIR/pushplus_notifier.log" ]; then
                tail -20 "$WORK_DIR/pushplus_notifier.log"
            else
                echo -e "${RED}PushPlus通知日志不存在${NC}"
            fi
            ;;
        4)
            if [ -f "$WORK_DIR/serverchan_notifier.log" ]; then
                tail -20 "$WORK_DIR/serverchan_notifier.log"
            else
                echo -e "${RED}Server酱通知日志不存在${NC}"
            fi
            ;;
        5)
            if [ -f "$WORK_DIR/port_traffic_monitor.log" ]; then
                tail -20 "$WORK_DIR/port_traffic_monitor.log"
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
    echo "0) 返回主菜单"
    
    read -p "请选择要查看的配置类型 [0-4]: " config_choice
    
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
    echo ""
    echo "可用的预设配置:"
    echo "1) ali-20g  - 阿里云轻量 20G配置"
    echo "2) ali-200g - 阿里云轻量 200G配置"
    echo "3) ali-1T   - 阿里云轻量 1T配置"
    echo "4) asia-300g - 亚洲地区 300G配置"
    echo "5) az-15g   - Azure 15G配置"
    echo "6) az-115g  - Azure 115G配置"
    echo "7) gcp-200g - Google Cloud 200G配置"
    echo "8) gcp-625g - Google Cloud 625G配置"
    echo "9) alice-1500g - Alice 1500G配置"
    echo "0) 返回主菜单"
    echo ""
    
    read -p "请选择预设配置 [0-9]: " preset_choice
    
    local config_file=""
    case $preset_choice in
        1) config_file="ali-20g" ;;
        2) config_file="ali-200g" ;;
        3) config_file="ali-1T" ;;
        4) config_file="asia-300g" ;;
        5) config_file="az-15g" ;;
        6) config_file="az-115g" ;;
        7) config_file="gcp-200g" ;;
        8) config_file="gcp-625g" ;;
        9) config_file="alice-1500g" ;;
        0) return ;;
        *) 
            echo -e "${RED}无效的选择${NC}"
            read -p "按回车键继续..."
            return
            ;;
    esac
    
    echo -e "${YELLOW}正在下载并应用预设配置 $config_file...${NC}"
    
    # 下载预设配置文件
    if curl -fsSL "$REPO_URL/$config_file" -o "$WORK_DIR/traffic_monitor_config.txt"; then
        echo -e "${GREEN}预设配置已应用！${NC}"
        echo -e "${CYAN}配置内容：${NC}"
        cat "$WORK_DIR/traffic_monitor_config.txt"
        
        # 提示用户是否立即启动监控
        echo ""
        read -p "是否立即启动流量监控？[y/N]: " start_monitor
        if [[ $start_monitor =~ ^[Yy]$ ]]; then
            install_script "trafficcop.sh"
            run_script "$WORK_DIR/trafficcop.sh"
        fi
    else
        echo -e "${RED}下载预设配置失败${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 停止所有服务
stop_all_services() {
    echo -e "${CYAN}正在停止所有TrafficCop服务...${NC}"
    
    # 停止流量监控进程
    pkill -f "trafficcop.sh" 2>/dev/null
    pkill -f "traffic_monitor.sh" 2>/dev/null
    echo "✓ 流量监控进程已停止"
    
    # 移除cron任务
    crontab -l 2>/dev/null | grep -v "trafficcop.sh\|traffic_monitor.sh" | crontab - 2>/dev/null
    echo "✓ 定时任务已清理"
    
    # 清除TC规则
    local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -n "$interface" ]; then
        tc qdisc del dev "$interface" root 2>/dev/null
        echo "✓ TC限速规则已清除"
    fi
    
    # 取消关机计划
    shutdown -c 2>/dev/null
    echo "✓ 关机计划已取消"
    
    echo -e "${GREEN}所有服务已停止！${NC}"
    read -p "按回车键继续..."
}

# 更新所有脚本
update_all_scripts() {
    echo -e "${CYAN}正在更新所有脚本到最新版本...${NC}"
    
    local scripts=("trafficcop.sh" "tg_notifier.sh" "pushplus_notifier.sh" "serverchan_notifier.sh" 
                  "port_traffic_limit.sh" "view_port_traffic.sh" "port_traffic_helper.sh" 
                  "remove_traffic_limit.sh" "machine_limit_manager.sh")
    
    for script in "${scripts[@]}"; do
        if curl -fsSL "$REPO_URL/$script" -o "$WORK_DIR/$script.new" 2>/dev/null; then
            mv "$WORK_DIR/$script.new" "$WORK_DIR/$script"
            chmod +x "$WORK_DIR/$script"
            echo -e "${GREEN}✓ $script 已更新${NC}"
        else
            echo -e "${YELLOW}! $script 更新失败或不存在${NC}"
        fi
    done
    
    echo -e "${GREEN}脚本更新完成！${NC}"
    read -p "按回车键继续..."
}

# 解除流量限制
remove_traffic_limit() {
    echo -e "${CYAN}正在解除流量限制...${NC}"
    install_script "remove_traffic_limit.sh"
    run_script "$WORK_DIR/remove_traffic_limit.sh"
    echo -e "${GREEN}流量限制解除完成！${NC}"
    read -p "按回车键继续..."
}

# 机器限速管理
manage_machine_limit() {
    echo -e "${CYAN}正在启动机器限速管理器...${NC}"
    
    # 下载并运行机器限速管理器
    echo -e "${YELLOW}正在下载机器限速管理器...${NC}"
    install_script "machine_limit_manager.sh"
    
    if [ -f "$WORK_DIR/machine_limit_manager.sh" ]; then
        run_script "$WORK_DIR/machine_limit_manager.sh"
    else
        echo -e "${RED}无法下载机器限速管理器${NC}"
        echo -e "${YELLOW}尝试使用旧方式解除限速...${NC}"
        remove_traffic_limit
    fi
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         TrafficCop 管理工具 v${SCRIPT_VERSION}        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo -e "${PURPLE}====================================${NC}"
    echo -e "${CYAN}最后更新: ${LAST_UPDATE}${NC}"
    echo ""
    echo -e "${YELLOW}1) 安装/管理流量监控${NC}"
    echo -e "${YELLOW}2) 安装/管理Telegram通知${NC}"
    echo -e "${YELLOW}3) 安装/管理PushPlus通知${NC}"
    echo -e "${YELLOW}4) 安装/管理Server酱通知${NC}"
    echo -e "${YELLOW}5) 安装/管理端口流量限制${NC}"
    echo -e "${CYAN}6) 查看端口流量状态${NC}"
    echo -e "${GREEN}7) 机器限速管理 (启用/禁用)${NC}"
    echo -e "${YELLOW}8) 解除流量限制 (旧方式)${NC}"
    echo -e "${YELLOW}9) 查看日志${NC}"
    echo -e "${YELLOW}10) 查看当前配置${NC}"
    echo -e "${YELLOW}11) 使用预设配置${NC}"
    echo -e "${YELLOW}12) 停止所有服务${NC}"
    echo -e "${GREEN}13) 更新所有脚本到最新版本${NC}"
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
        read -p "请选择操作 [0-13]: " choice
        
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
                view_port_traffic
                ;;
            7)
                manage_machine_limit
                ;;
            8)
                remove_traffic_limit
                ;;
            9)
                view_logs
                ;;
            10)
                view_config
                ;;
            11)
                use_preset_config
                ;;
            12)
                stop_all_services
                ;;
            13)
                update_all_scripts
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
main "$@"
