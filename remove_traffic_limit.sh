#!/bin/bash
# 文件名: remove_traffic_limit.sh

# 备份原始文件
cp /root/traffic_monitor_config.txt /root/traffic_monitor_config.txt.bak

# 修改TRAFFIC_LIMIT和LIMIT_SPEED的值
sed -i 's/TRAFFIC_LIMIT=[0-9]*/TRAFFIC_LIMIT=1000000/' /root/traffic_monitor_config.txt
sed -i 's/LIMIT_SPEED=[0-9]*/LIMIT_SPEED=1000000/' /root/traffic_monitor_config.txt

# 显示修改后的内容
echo "修改后的配置文件内容:"
cat /root/traffic_monitor_config.txt

# 下载、设置权限并执行 traffic_monitor.sh
curl -fsSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh -o /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh

echo "限速已解除，traffic_monitor.sh 已更新并重新启动。"
