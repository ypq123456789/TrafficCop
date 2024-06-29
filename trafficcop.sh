#!/bin/bash

CONFIG_FILE="/etc/vps_traffic_limit.conf"
LOG_FILE="/var/log/vps_traffic_limit.log"

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

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
        echo "选择流量统计模式："
        echo "1. 只计算出站流量"
        echo "2. 只计算进站流量"
        echo "3. 出进站流量都计算"
        echo "4. 出站和进站流量只取大"
        read -p "请输入选择（1-4）: " TRAFFIC_MODE
    fi

    read -p "当前流量计算周期为 $CYCLE，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入流量计算周期（月/季/年）: " CYCLE
    fi

    read -p "当前流量周期起始日期为 $START_DATE，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入流量周期起始日期（格式：DD，例如01）: " START_DATE
    fi

    read -p "当前限制流量大小为 $LIMIT_GB GB，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入要限制的流量大小（GB）: " LIMIT_GB
    fi

    read -p "当前容错范围为 $TOLERANCE_GB GB，是否修改？(y/n) " answer
    if [[ $answer == "y" ]]; then
        read -p "输入容错范围（GB）: " TOLERANCE_GB
    fi

    save_config
}

# 函数：获取当前流量统计
get_current_traffic() {
    local rx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 10)
    local tx_bytes=$(vnstat -i $MAIN_INTERFACE --oneline | cut -d';' -f 11)
    echo "当前进站流量: $(( rx_bytes / 1024 / 1024 )) MB"
    echo "当前出站流量: $(( tx_bytes / 1024 / 1024 )) MB"
    echo "总流量: $(( (rx_bytes + tx_bytes) / 1024 / 1024 )) MB"
}

# 函数：记录日志
log_traffic() {
    local message="\$1"
    echo "$(date): $message" >> $LOG_FILE
}

# 主程序开始
MAIN_INTERFACE=$(get_main_interface)
SSH_PORT=$(get_ssh_port)

read_config
echo "当前配置:"
cat $CONFIG_FILE
echo ""

get_current_traffic
echo ""

read -p "是否需要更新配置？(y/n) " answer
if [[ $answer == "y" ]]; then
    update_config
fi

# 计算实际限制流量
ACTUAL_LIMIT=$((LIMIT_GB - TOLERANCE_GB))

# 设置iptables规则函数
setup_iptables() {
    # ... (保持原有的iptables设置逻辑)
}

# 检查流量并应用限制
check_and_limit_traffic() {
    # ... (保持原有的检查逻辑)

    # 添加日志记录
    log_traffic "当前使用流量: $total_traffic GB"

    if (( total_traffic >= ACTUAL_LIMIT )); then
        log_traffic "流量超出限制，应用iptables规则"
        setup_iptables
    else
        log_traffic "流量在限制范围内，清除iptables规则"
        iptables -F
        iptables -X
    fi
}

# 主循环
while true; do
    check_and_limit_traffic
    sleep 60
done
