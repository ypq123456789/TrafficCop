#!/bin/bash

# 测试下载速度的脚本

# 定义下载文件的 URL（这里使用 Ubuntu 镜像作为示例）
URL="http://releases.ubuntu.com/20.04/ubuntu-20.04.3-desktop-amd64.iso"

# 定义测试时间（秒）
TEST_DURATION=30

# 定义输出文件名
OUTPUT_FILE="/dev/null"

echo "开始测试下载速度..."
echo "测试时间: ${TEST_DURATION} 秒"
echo "下载 URL: ${URL}"
echo

# 使用 wget 下载文件，限制时间，并将输出重定向到 /dev/null
wget --output-document=$OUTPUT_FILE --report-speed=bits -q --show-progress \
     --limit-rate=unlimited --no-clobber --tries=1 \
     --timeout=$TEST_DURATION --progress=bar:force:noscroll \
     $URL 2>&1 | \
    grep -oP '\d+\.\d+\s*[KM]iB/s' | tail -n 1 | \
    awk '{
        speed=\$1;
        unit=\$2;
        if (unit == "KiB/s") speed *= 1024;
        else if (unit == "MiB/s") speed *= 1024 * 1024;
        printf "平均下载速度: %.2f Mbps\n", speed * 8 / (1024 * 1024)
    }'

echo
echo "测试完成"
