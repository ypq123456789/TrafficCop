#!/bin/bash

echo "开始测试下载速度..."
echo "测试时间: 30 秒"
echo "下载 URL: http://releases.ubuntu.com/20.04/ubuntu-20.04.3-desktop-amd64.iso"
echo

# 使用 wget 下载文件，限制时间为 30 秒，并将输出保存到临时文件
wget -O /dev/null http://releases.ubuntu.com/20.04/ubuntu-20.04.3-desktop-amd64.iso 2>&1 | tee /tmp/wget_output.txt &
wget_pid=$!

sleep 30
kill $wget_pid

# 使用 sed 提取下载速度
speed=$(sed -n 's/.*(\([0-9.]\+\) [KM]B\/s).*/\1/p' /tmp/wget_output.txt | tail -n 1)
unit=$(sed -n 's/.*(\([0-9.]\+\) \([KM]B\)\/s).*/\2/p' /tmp/wget_output.txt | tail -n 1)

# 转换速度到 Mbps
if [ "$unit" = "KB" ]; then
    speed_mbps=$(echo "scale=2; $speed / 125" | bc)
elif [ "$unit" = "MB" ]; then
    speed_mbps=$(echo "scale=2; $speed * 8" | bc)
else
    echo "无法识别速度单位"
    exit 1
fi

echo "平均下载速度: $speed_mbps Mbps"

# 清理临时文件
rm /tmp/wget_output.txt
