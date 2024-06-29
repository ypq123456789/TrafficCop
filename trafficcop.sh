#!/bin/bash

CONFIG_FILE="/etc/vps_traffic_limit.conf"
LOG_FILE="/var/log/vps_traffic_limit.log"
SCRIPT_URL="https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh"
TEMP_SCRIPT="/tmp/trafficcop_new.sh"

# 日志函数
log_message() {
    local message="\$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> $LOG_FILE
}

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   log_message "此脚本必须以root权限运行"
   exit 1
fi

# 检查并安装vnstat
check_and_install_vnstat() {
    if ! command -v vnstat &> /dev/null; then
        log_message "未检测到vnstat。正在尝试安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y vnstat
        elif command -v yum &> /dev/null; then
            yum install -y vnstat
        else
            log_message "无法自动安装vnstat。请手动安装后再运行此脚本。"
            exit 1
        fi
        
        if command -v vnstat &> /dev/null; then
            log_message "vnstat安装成功。"
            systemctl start vnstat
            systemctl enable vnstat
        else
            log_message "vnstat安装失败。请手动安装后再运行此脚本。"
            exit 1
        fi
    else
        log_message "检测到vnstat已安装。"
    fi
}

# 在脚本开始时检查并安装vnstat
check_and_install_vnstat

# 检查并更新脚本函数
check_and_update() {
    log_message "正在检查更新..."
    if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT"; then
        if [[ -s "$TEMP_SCRIPT" ]]; then
            CURRENT_HASH=$(sha256sum "\$0" | cut -d' ' -f1)
            NEW_HASH=$(sha256sum "$TEMP_SCRIPT" | cut -d' ' -f1)
            
            if [[ "$NEW_HASH" != "$CURRENT_HASH" ]]; then
                log_message "发现新版本。"
                read -p "是否要更新？(y/n): " choice
                case "$choice" in 
                    y|Y )
                        mv "$TEMP_SCRIPT" "\$0"
                        chmod +x "\$0"
                        log_message "更新成功。请重新运行脚本。"
                        exit 0
                        ;;
                    * ) 
                        log_message "更新已跳过。"
                        rm -f "$TEMP_SCRIPT"
                        ;;
                esac
            else
                log_message "您正在使用最新版本。"
                rm -f "$TEMP_SCRIPT"
            fi
        else
            log_message "错误：下载的文件为空。"
            rm -f "$TEMP_SCRIPT"
        fi
    else
        log_message "错误：下载更新失败。"
    fi
}

# 函数：获取主要网卡名称
get_main_interface() {
    ip route | grep default | awk '{print \$5}' | head -n1
}

# 函数：获取SSH端口
get_ssh_port() {
    grep "Port " /etc/ssh/sshd_config | awk '{print \$2}'
}

# 函数：读取配置文件
read_config() {
    if [[ -f $CONFIG_FILE ]]; then
        source $CONFIG_FILE
    else
        # 默认值
        TRAFFIC_MODE=3
        CYCLE="月"
        START_DATE="01"
        LIMIT_GB=1000
        TOLERANCE_GB=50
    fi
}

# 函数：保存配置文件
save_config() {
    cat > $CONFIG_FILE <<EOF
TRAFFIC_MODE=$TRAFFIC_MODE
CYCLE=$CYCLE
START_DATE=$START_DATE
LIMIT_GB=$LIMIT_GB
TOLERANCE_GB=$TOLERANCE_GB
EOF
}

# 函数：更新配置
update_config() {
    read -p "当前流量统计模式为 $TRAFFIC_MODE，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        log_message "用户选择修改流量统计模式"
        echo "选择流量统计模式："
        echo "1. 只计算出站流量"
        echo "2. 只计算进站流量"
        echo "3. 出进站流量都计算"
        echo "4. 出站和进站流量只取大"
        read -p "请输入选择（1-4）: " TRAFFIC_MODE
        log_message "用户选择了流量统计模式: $TRAFFIC_MODE"
    fi

    read -p "当前流量计算周期为 $CYCLE，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入流量计算周期（月/季/年）: " CYCLE
        log_message "用户修改了流量计算周期为: $CYCLE"
    fi

    read -p "当前流量周期起始日期为 $START_DATE，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入流量周期起始日期（格式：DD，例如01）: " START_DATE
        log_message "用户修改了流量周期起始日期为: $START_DATE"
    fi

    read -p "当前限制流量大小为 $LIMIT_GB GB，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入要限制的流量大小（GB）: " LIMIT_GB
        log_message "用户修改了限制流量大小为: $LIMIT_GB GB"
    fi

    read -p "当前容错范围为 $TOLERANCE_GB GB，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入容错范围（GB）: " TOLERANCE_GB
        log_message "用户修改了容错范围为: $TOLERANCE_GB GB"
    fi

    save_config
    log_message "配置已更新并保存"
}

# 函数：获取当前流量统计
get_current_traffic() {
    local rx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 10)
    local tx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 11)
    log_message "当前进站流量: $(( rx_bytes / 1024 / 1024 )) MB"
    log_message "当前出站流量: $(( tx_bytes / 1024 / 1024 )) MB"
    log_message "总流量: $(( (rx_bytes + tx_bytes) / 1024 / 1024 )) MB"
}

# 设置iptables规则函数
setup_iptables() {
    # 清除现有规则
    iptables -F
    iptables -X

    # 设置默认策略
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # 允许已建立的连接和相关数据包
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 允许本地回环接口
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # 允许SSH连接
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    iptables -A OUTPUT -p tcp --sport $SSH_PORT -j ACCEPT

    # 允许DNS查询
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

    log_message "已应用iptables规则，限制了网络访问"
}

# 检查流量并应用限制
check_and_limit_traffic() {
    local rx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 10)
    local tx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 11)
    local total_traffic=0

    case $TRAFFIC_MODE in
        1) total_traffic=$(( tx_bytes / 1024 / 1024 / 1024 )) ;;
        2) total_traffic=$(( rx_bytes / 1024 / 1024 / 1024 )) ;;
        3) total_traffic=$(( (rx_bytes + tx_bytes) / 1024 / 1024 / 1024 )) ;;
        4) total_traffic=$(( rx_bytes > tx_bytes ? rx_bytes : tx_bytes ))
           total_traffic=$(( total_traffic / 1024 / 1024 / 1024 )) ;;
    esac

    log_message "当前使用流量: $total_traffic GB"

    if (( total_traffic >= ACTUAL_LIMIT )); then
        log_message "流量超出限制，应用iptables规则"
        setup_iptables
    else
        log_message "流量在限制范围内，清除iptables规则"
        iptables -F
        iptables -X
    fi
}

# 检查更新
check_and_update

# 主程序开始
MAIN_INTERFACE=$(get_main_interface)
SSH_PORT=$(get_ssh_port)

read_config
log_message "当前配置:"
log_message "$(cat $CONFIG_FILE)"

get_current_traffic

read -p "是否需要更新配置？(y/n) " answer
if [[ $answer == "y" ]]; then
    update_config
fi

# 计算实际限制流量
ACTUAL_LIMIT=$((LIMIT_GB - TOLERANCE_GB))
log_message "实际限制流量: $ACTUAL_LIMIT GB"

# 主循环
log_message "开始主循环，每60秒检查一次流量"
while true; do
    check_and_limit_traffic
    sleep 60
done
