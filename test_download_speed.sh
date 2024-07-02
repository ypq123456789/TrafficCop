#!/bin/bash

VERSION="0.3"
echo "当前版本：$VERSION"

echo "开始测试下载速度..."
echo "测试时间: 30 秒"
DOWNLOAD_URL="http://speedtest.ftp.otenet.gr/files/test100k.db"
echo "下载 URL: $DOWNLOAD_URL"
echo

# 使用 wget 下载文件，限制时间为 30 秒，并将输出保存到临时文件
wget -O /dev/null $DOWNLOAD_URL 2>&1 | tee /tmp/wget_output.txt &
wget_pid=$!

sleep 30
kill $wget_pid

# 使用 grep 和 cut 提取下载速度
speed=$(grep -oP '\d+(\.\d+)?\s[KMG]B/s' /tmp/wget_output.txt | tail -n 1)

if [ -z "$speed" ]; then
    echo "无法获取下载速度，请检查网络连接。"
    exit 1
fi

value=$(echo $speed | cut -d' ' -f1)
unit=$(echo $speed | cut -d' ' -f2)

# 转换速度到 Mbps
case $unit in
    KB/s)
        speed_mbps=$(echo "scale=2; $value / 125" | bc)
        ;;
    MB/s)
        speed_mbps=$(echo "scale=2; $value * 8" | bc)
        ;;
    GB/s)
        speed_mbps=$(echo "scale=2; $value * 8000" | bc)
        ;;
    *)
        echo "无法识别速度单位: $unit"
        exit 1
        ;;
esac

echo "平均下载速度: $speed_mbps Mbps"

# 清理临时文件
rm /tmp/wget_output.txt
