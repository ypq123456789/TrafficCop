#!/bin/bash

# 设置 PATH 确保 cron 环境能找到所有命令
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORK_DIR="/root/TrafficCop"
CONFIG_FILE="$WORK_DIR/traffic_monitor_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
SCRIPT_PATH="$WORK_DIR/trafficcop.sh"
LOCK_FILE="$WORK_DIR/traffic_monitor.lock"

# ============================================================
# 日志轮转
# ------------------------------------------------------------
# 背景：脚本由 cron 每分钟执行一次，内部有近百处 `tee -a "$LOG_FILE"`。
# 长期运行后日志会无限增长（生产机已出现过 150MB），带来两个后果：
#   1. 磁盘占用不受控；
#   2. 下游 tg/serverchan/pushplus 通知脚本用 `tac "$LOG_FILE" | grep -m 1`
#      取「最近一条」记录，tac 会把整个文件倒读进内存 —— 文件越大越慢，
#      而且是每分钟都读一次。
#
# 策略：保留式轮转（不是截断丢弃）
#   - 超过 LOG_MAX_BYTES 时，把当前文件改名为 .1，新建空文件继续写；
#   - 依次滚动 .1 -> .2 -> ... 最多保留 LOG_KEEP 份；
#   - 归档文件【仍然参与】下游的 tac 查询（见 log_tac_recent），
#     所以「最近一条」记录不会因为轮转而丢失。
#   - 理论上限占用约 (LOG_KEEP + 1) * LOG_MAX_BYTES。
#
# 触发时机必须足够早：在 --run 的第一次日志写入【之前】。
# 否则「正在以自动化模式运行」这类新记录会被写进刚归档的旧文件里，
# 导致归档文件混入新记录、破坏时序语义。
# ============================================================
LOG_MAX_BYTES=$((10 * 1024 * 1024))   # 单文件上限 10MB
LOG_KEEP=3                            # 保留 3 份归档 -> 约 40MB 封顶
LOG_WINDOW_BYTES=$((2 * 1024 * 1024)) # 读侧扫描窗口 2MB（见 log_recent_match）

# 设置时区为上海（东八区）
# 注意：部分精简系统（如未安装 tzdata 的 Debian 容器）缺少 /usr/share/zoneinfo，
# 此时 TZ='Asia/Shanghai' 会静默失效、退回 UTC，导致周期起点比北京时间晚 8 小时。
# 检测方式必须显式用 TZ= 探测，不能读已导出的 TZ（那样读到的只是回退后的结果）。
if [ "$(TZ='Asia/Shanghai' date '+%z' 2>/dev/null)" = "+0800" ]; then
    export TZ='Asia/Shanghai'
else
    # zoneinfo 缺失，改用 POSIX 字面量偏移（UTC+8），无需时区库
    export TZ='CST-8'
fi

# ============================================================
# 流量换算进制（字节 -> GB）
# ------------------------------------------------------------
# 流量换算进制（字节 -> GB）：1GB 等于 1000^3 还是 1024^3 字节。
#   - 默认 1024：这是**通用标准口径**（KiB/MiB/GiB 体系，也是绝大多数
#     VPS 厂商控制台与 vnstat 自身的口径），适用于绝大多数用户。
#   - 可选 1000：**仅少数按十进制折算的服务商**需要。是否该改，唯一可靠的
#     办法是拿脚本数字和自己的账单/控制台对一次：若脚本一直偏小约 7.4%，
#     说明对方按 1TB = 1000GB 折算，此时改成本项为 1000。
#     ⚠️ 不要凭服务商名字猜 —— 同家不同产品线口径可能不同，
#        官方文档与实际计费也偶有不一致，以实际账单为准。
#
# 改成 1000 的方法（二选一）：
#   ① 改配置文件：编辑 /root/TrafficCop/traffic_monitor_config.txt，
#      把 CONVERSION_BASE=1024 改成 CONVERSION_BASE=1000（若该行不存在，
#      直接新加一行 CONVERSION_BASE=1000），保存即可（无需重启脚本）。
#   ② 重新运行 ./trafficcop.sh，在交互提问处选「2. 1000 进制」。
#
# ⚠️ 只影响「把字节数显示/比较成 GB」这一步，不改变限速判定逻辑本身。
# ⚠️ 端口流量脚本会读取同一份配置，三处口径自动保持一致。
# 非法值或留空一律回退到 1024。
CONVERSION_BASE=${CONVERSION_BASE:-1024}

# ============================================================
# 日志上报（可选，默认关闭）
# ------------------------------------------------------------
# 用于「客户上报 → 我们直接定位原因」。上报内容是结构化 JSON 字段
# （机器名、用量、脚本版本、cron 是否存活等），存储走 Cloudflare R2。
#
# ⚠️ 默认关闭：上报含机器名与流量数字，属客户数据，必须由客户显式开启。
#    开启方式：在配置文件里设置 ENABLE_REPORT=yes 并填好 REPORT_URL / REPORT_TOKEN。
# ============================================================
ENABLE_REPORT=${ENABLE_REPORT:-no}
REPORT_URL=${REPORT_URL:-}
REPORT_TOKEN=${REPORT_TOKEN:-}
REPORT_MACHINE_ID=${REPORT_MACHINE_ID:-}
# 心跳上报降频：默认每 60 次流量检查才上报一次（约 1 小时一次），
# 避免每分钟一条把 R2 写操作打满。
REPORT_HEARTBEAT_EVERY=${REPORT_HEARTBEAT_EVERY:-60}

# 返回「字节 -> GB」的换算除数，供各处 bc 计算复用。
# 用函数而非散落的字面量，避免多处不一致。
# 注意：除 1000 是特例（少数按十进制折算的服务商），其余（含空值、非法值）一律 1024。
get_byte_divisor() {
    case "$CONVERSION_BASE" in
        1000) echo "1000000000" ;;   # 1000^3（少数按十进制折算的服务商）
        *)    echo "1073741824" ;;   # 1024^3（默认 / 通用口径）
    esac
}

echo "-----------------------------------------------------"| tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') 当前版本：1.0.89"| tee -a "$LOG_FILE"

# 供上报模块使用的版本号
SCRIPT_VERSION="1.0.91"

# 载入日志上报模块（可选功能，文件缺失不影响主流程）
if [ -f "$WORK_DIR/report_lib.sh" ]; then
    source "$WORK_DIR/report_lib.sh"
fi


# 在脚本开始时杀死所有其他 traffic_monitor.sh 进程
kill_other_instances() {
    local current_pid=$$
    local script_name=$(basename "$0")
    for pid in $(pgrep -f "$script_name"); do
        if [ "$pid" != "$current_pid" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 终止其他脚本实例 (PID: $pid)" | tee -a "$LOG_FILE"
            kill $pid
        fi
    done
}





migrate_files() {
    # 创建新的工作目录
    mkdir -p "$WORK_DIR"

    # 迁移配置文件
    if [ -f "/root/traffic_monitor_config.txt" ]; then
        mv "/root/traffic_monitor_config.txt" "$CONFIG_FILE"
    fi

    # 迁移日志文件
    if [ -f "/root/traffic_monitor.log" ]; then
        mv "/root/traffic_monitor.log" "$LOG_FILE"
    fi

    # 删除旧的脚本文件，而不是迁移
    if [ -f "/root/traffic_monitor.sh" ]; then
        rm "/root/traffic_monitor.sh"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 旧的脚本文件已删除" | tee -a "$LOG_FILE"
    fi
    
    # 创建软链接以保持向后兼容（如果crontab中仍在使用旧名称）
    if [ ! -e "$WORK_DIR/traffic_monitor.sh" ] && [ -f "$WORK_DIR/trafficcop.sh" ]; then
        ln -sf "$WORK_DIR/trafficcop.sh" "$WORK_DIR/traffic_monitor.sh"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 已创建 traffic_monitor.sh 软链接" | tee -a "$LOG_FILE"
    fi

    # 迁移软件包安装标志文件
    if [ -f "/root/.traffic_monitor_packages_installed" ]; then
        mv "/root/.traffic_monitor_packages_installed" "$WORK_DIR/.traffic_monitor_packages_installed"
    fi

    # 迁移其他可能存在的相关文件
    for file in /root/traffic_monitor_*.txt /root/traffic_monitor_*.log; do
        if [ -f "$file" ]; then
            mv "$file" "$WORK_DIR/"
        fi
    done

    # 更新 crontab 中的脚本路径
    if crontab -l | grep -q "/root/traffic_monitor.sh"; then
        crontab -l | sed "s|/root/traffic_monitor.sh|$SCRIPT_PATH|g" | crontab -
        echo "$(date '+%Y-%m-%d %H:%M:%S') Crontab 已更新为新的脚本路径" | tee -a "$LOG_FILE"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') 文件已迁移到新的工作目录: $WORK_DIR" | tee -a "$LOG_FILE"
}





check_and_install_packages() {
    local packages=("vnstat" "jq" "bc" "iproute2" "cron")
    local need_install=false

    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') $package 未安装，将进行安装..." | tee -a "$LOG_FILE"
            need_install=true
            break
        fi
    done

    if $need_install; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 正在更新软件包列表..." | tee -a "$LOG_FILE"
        if ! sudo apt-get update; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 更新软件包列表失败，请检查网络连接和系统状态。" | tee -a "$LOG_FILE"
            return 1
        fi

        for package in "${packages[@]}"; do
            if ! dpkg -s "$package" >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') 正在安装 $package..." | tee -a "$LOG_FILE"
                if sudo apt-get install -y "$package"; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') $package 安装成功" | tee -a "$LOG_FILE"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') $package 安装失败，请手动检查并安装。" | tee -a "$LOG_FILE"
                    return 1
                fi
            fi
        done
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 所有必要的软件包已安装" | tee -a "$LOG_FILE"
    fi

    # 验证 tc 命令是否可用
    if ! command -v tc &> /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：'tc' 命令不可用，可能影响限速功能。" | tee -a "$LOG_FILE"
    fi

    # 获取 vnstat 版本
    local vnstat_version=$(vnstat --version 2>&1 | head -n 1)
    echo "$(date '+%Y-%m-%d %H:%M:%S') vnstat 版本: $vnstat_version" | tee -a "$LOG_FILE"

    # 获取主要网络接口
    local main_interface=$(ip route | grep default | sed -e 's/^.*dev \([^ ]*\).*$/\1/' | head -n 1)
    echo "$(date '+%Y-%m-%d %H:%M:%S') 主要网络接口: $main_interface" | tee -a "$LOG_FILE"

    # 获取 vnstat 统计开始时间
    if [ -n "$main_interface" ]; then
        local vnstat_json=$(vnstat -i "$main_interface" --json d)
        local vnstat_start_time=$(echo "$vnstat_json" | jq -r '.interfaces[0].created.date | "\(.year)-\(.month | tostring | if length == 1 then "0" + . else . end)-\(.day | tostring | if length == 1 then "0" + . else . end)"')
        
        if [ -n "$vnstat_start_time" ] && [ "$vnstat_start_time" != "null-null-null" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') vnstat 统计开始日期: $vnstat_start_time，在此之前的流量不会被纳入统计！" | tee -a "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 无法获取 vnstat 统计开始时间" | tee -a "$LOG_FILE"
            echo "vnstat JSON 输出: $vnstat_json" | tee -a "$LOG_FILE"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 无法获取主要网络接口" | tee -a "$LOG_FILE"
    fi
}


# ============================================================
# 日志轮转与读取
# ============================================================

# 轮转日志：超过 LOG_MAX_BYTES 就把当前文件归档并新建。
# 幂等，可安全重复调用。失败绝不影响主流程。
rotate_log_if_needed() {
    [ -f "$LOG_FILE" ] || return 0

    local size
    # 用 stat 取字节数；兼容 GNU 与 BusyBox 两种参数风格
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    [ "$size" -ge "$LOG_MAX_BYTES" ] || return 0

    # 从最老的一份开始滚动，避免覆盖
    local i
    for (( i = LOG_KEEP - 1; i >= 1; i-- )); do
        if [ -f "${LOG_FILE}.${i}" ]; then
            mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))" 2>/dev/null
        fi
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || return 0

    # 新建空文件并继承权限
    : > "$LOG_FILE" 2>/dev/null || true
    chmod --reference="${LOG_FILE}.1" "$LOG_FILE" 2>/dev/null || chmod 600 "$LOG_FILE" 2>/dev/null || true

    # 清掉超出保留份数的尾巴
    local n=$(( LOG_KEEP + 1 ))
    while [ -f "${LOG_FILE}.${n}" ]; do
        rm -f "${LOG_FILE}.${n}" 2>/dev/null || break
        n=$(( n + 1 ))
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') 日志已轮转：${size} 字节 -> ${LOG_FILE}.1（保留 ${LOG_KEEP} 份归档）" >> "$LOG_FILE" 2>/dev/null
    return 0
}

# 「取最近一条匹配行」的统一入口，替代散落各处的 `tac "$LOG_FILE" | grep -m 1`。
#
# 与裸 tac 的区别：
#   1. 按「当前文件 -> .1 -> .2 ...」的顺序查，所以轮转后仍能找到近期记录；
#   2. 每次只在文件尾部的一段窗口内查找（默认 2MB），避免 tac 把整个
#      150MB 文件倒读进内存 —— 「最近一条」几乎总在尾部，扫全量纯属浪费。
#
# ⚠️ 与 log_helper.sh 里的同名函数必须保持一致（三个通知脚本加载的是那份）。
#    两边都改，别只改一处。
#
# 策略要点（这里出过一个真 bug，见 log_helper.sh 的详细注释）：
#   - 当前文件会继续增长、「最近一条」几乎总在尾部 -> 只扫尾部窗口；
#   - 归档文件已冻结、「最近一条」可能在任意位置 -> 必须全量反向扫描。
#   初版对归档也套用窗口，导致位于归档开头的限速记录永远查不到。
#
# 找不到时输出空串并返回 1。
log_recent_match() {
    local pattern="$1"
    local f hit size

    for f in "$LOG_FILE" "${LOG_FILE}.1" "${LOG_FILE}.2" "${LOG_FILE}.3" "${LOG_FILE}.4" "${LOG_FILE}.5"; do
        [ -f "$f" ] || continue

        if [ "$f" = "$LOG_FILE" ]; then
            # 取文件字节数，兼容 GNU 与 BusyBox 两种 stat 参数风格
            size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
            case "$size" in ''|*[!0-9]*) size=0 ;; esac

            if [ "$size" -gt "$LOG_WINDOW_BYTES" ]; then
                # 发生了截断：首行可能是半行，丢掉
                hit=$(tail -c "$LOG_WINDOW_BYTES" "$f" 2>/dev/null | tail -n +2 2>/dev/null | tac 2>/dev/null | grep -m 1 -E "$pattern")
            else
                # 完整文件：一行都不丢
                hit=$(tac "$f" 2>/dev/null | grep -m 1 -E "$pattern")
            fi
        else
            # 已冻结的归档：必须全量反向扫描，不能用窗口
            hit=$(tac "$f" 2>/dev/null | grep -m 1 -E "$pattern")
        fi

        if [ -n "$hit" ]; then
            printf '%s\n' "$hit"
            return 0
        fi
    done
    return 1
}

# 补齐配置文件里可能缺失的字段（老版本升级场景）
# 注意：read_config 和 check_existing_setup 是两条独立的 source 路径，
# 两处都必须调用，漏掉任何一处都会让老用户拿不到默认值。
apply_config_defaults() {
    CONVERSION_BASE=${CONVERSION_BASE:-1024}
    PERIOD_START_DAY=${PERIOD_START_DAY:-1}
    LIMIT_SPEED=${LIMIT_SPEED:-20}
    # 上报相关：默认全部关闭，升级的用户不会被自动开启
    ENABLE_REPORT=${ENABLE_REPORT:-no}
    REPORT_URL=${REPORT_URL:-}
    REPORT_TOKEN=${REPORT_TOKEN:-}
    REPORT_MACHINE_ID=${REPORT_MACHINE_ID:-}
    REPORT_HEARTBEAT_EVERY=${REPORT_HEARTBEAT_EVERY:-60}
}

# 检查配置和定时任务
check_existing_setup() {
     if [ -s "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        # 与 read_config 保持一致：补老配置文件缺失字段的默认值
        apply_config_defaults
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已存在"| tee -a "$LOG_FILE"

        # 情况一：crontab 里没有本脚本的任务
        if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：定时任务未找到，可能需要重新设置。"| tee -a "$LOG_FILE"
            # 这是「客户流量倒退」的根因之一：cron 丢了但没人知道。
            # 开启上报时顺手报一条，便于我们侧主动发现。
            if [ "${ENABLE_REPORT:-no}" = "yes" ] && declare -f report_event >/dev/null 2>&1; then
                report_event "error" "" "" "" "定时任务未找到，cron 可能已丢失" &
            fi
            return 0
        fi

        # 情况二：任务在，但 cron 服务没跑 —— 客户机上真实发生过。
        # 症状同样是「日志不再更新」，但 crontab -l 看起来完全正常，
        # 只检查任务是否存在会漏判。
        if ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：定时任务存在，但 cron 服务未运行（任务不会被执行）。"| tee -a "$LOG_FILE"
            if ensure_cron_service; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') cron 服务已自动拉起。"| tee -a "$LOG_FILE"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：无法启动 cron 服务，请手动检查。"| tee -a "$LOG_FILE"
                if [ "${ENABLE_REPORT:-no}" = "yes" ] && declare -f report_event >/dev/null 2>&1; then
                    report_event "error" "" "" "" "cron 服务未运行且自动启动失败" &
                fi
            fi
            return 0
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') 每分钟一次的定时任务已在执行。"| tee -a "$LOG_FILE"
        return 0
    else
        return 1
    fi
}

# 读取配置
read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        # 老版本配置文件没有新增字段，source 后仍为空，
        # 此处补默认值，保证升级脚本后老用户不需要重新配置。
        apply_config_defaults
        return 0
    else
        return 1
    fi
}

# 写入配置
write_config() {
    # ⚠️ 安全：REPORT_URL / REPORT_TOKEN / REPORT_MACHINE_ID 来自用户输入或 hostname，
    # 之后会被 `source "$CONFIG_FILE"` 以 root 身份重新解析。
    # 若直接裸写，值里出现空格、`;`、`&`、`$(...)`、反引号就会出错甚至执行任意命令
    # （实测：值中含 $(touch /tmp/x) 时，source 阶段该命令真的被执行）。
    # 用 printf '%q' 做 shell 转义后再落盘，保证「写进去什么、source 回来就是什么」。
    local _q_url _q_token _q_machine
    _q_url=$(printf '%q' "${REPORT_URL:-}")
    _q_token=$(printf '%q' "${REPORT_TOKEN:-}")
    _q_machine=$(printf '%q' "${REPORT_MACHINE_ID:-}")

    cat > "$CONFIG_FILE" << EOF
TRAFFIC_MODE=$TRAFFIC_MODE
TRAFFIC_PERIOD=$TRAFFIC_PERIOD
TRAFFIC_LIMIT=$TRAFFIC_LIMIT
TRAFFIC_TOLERANCE=$TRAFFIC_TOLERANCE
PERIOD_START_DAY=${PERIOD_START_DAY:-1}
LIMIT_SPEED=${LIMIT_SPEED:-20}
MAIN_INTERFACE=$MAIN_INTERFACE
LIMIT_MODE=$LIMIT_MODE
CONVERSION_BASE=${CONVERSION_BASE:-1024}
ENABLE_REPORT=${ENABLE_REPORT:-no}
REPORT_URL=$_q_url
REPORT_TOKEN=$_q_token
REPORT_MACHINE_ID=$_q_machine
REPORT_HEARTBEAT_EVERY=${REPORT_HEARTBEAT_EVERY:-60}
EOF
    chmod 600 "$CONFIG_FILE" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已更新"| tee -a "$LOG_FILE"
}


# 显示当前配置
show_current_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 当前配置:"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计模式: $TRAFFIC_MODE"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量统计周期: $TRAFFIC_PERIOD"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 周期起始日: ${PERIOD_START_DAY:-1}"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量限制: $TRAFFIC_LIMIT GB"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 容错范围: $TRAFFIC_TOLERANCE GB"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 限速: ${LIMIT_SPEED:-20} kbit/s"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 主要网络接口: $MAIN_INTERFACE"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 限制模式: $LIMIT_MODE"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量换算进制: ${CONVERSION_BASE:-1024} (1GB = ${CONVERSION_BASE:-1024}^3 字节)"| tee -a "$LOG_FILE"
    if [ "${ENABLE_REPORT:-no}" = "yes" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 日志上报: 已开启 -> ${REPORT_URL:-未配置}"| tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 日志上报: 已关闭（默认，可在配置文件中开启）"| tee -a "$LOG_FILE"
    fi
}

# 检测主要网络接口
get_main_interface() {
    local main_interface=$(ip route | grep default | sed -n 's/^default via [0-9.]* dev \([^ ]*\).*/\1/p' | head -n1)
    if [ -z "$main_interface" ]; then
        main_interface=$(ip link | grep 'state UP' | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p' | head -n1)
    fi
    
    if [ -z "$main_interface" ]; then
        while true; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') 无法自动检测主要网络接口。"| tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 可用的网络接口有："| tee -a "$LOG_FILE"
            ip -o link show | sed -n 's/^[0-9]*: \([^:]*\):.*/\1/p'
            read -p "请从上面的列表中选择一个网络接口: " main_interface
            if [ -z "$main_interface" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') 请输入一个有效的接口名称。"| tee -a "$LOG_FILE"
            elif ip link show "$main_interface" > /dev/null 2>&1; then
                break
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') 无效的接口，请重新选择。"| tee -a "$LOG_FILE"
            fi
        done
    else
        read -p "检测到的主要网络接口是: $main_interface, 按Enter使用此接口，或输入新的接口名称: " new_interface
        if [ -n "$new_interface" ]; then
            if ip link show "$new_interface" > /dev/null 2>&1; then
                main_interface=$new_interface
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') 输入的接口无效，将使用检测到的接口: $main_interface"| tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    echo $main_interface| tee -a "$LOG_FILE"
}

# 初始配置函数
echo "$(date '+%Y-%m-%d %H:%M:%S') 开始初始化配置"| tee -a "$LOG_FILE"
initial_config() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 正在检测主要网络接口..."| tee -a "$LOG_FILE"
    MAIN_INTERFACE=$(get_main_interface)

    while true; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') 请选择流量统计模式："| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 1. 只计算出站流量"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 2. 只计算进站流量"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 3. 出进站流量都计算"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 4. 出站和进站流量只取大"| tee -a "$LOG_FILE"
        read -p "请输入选择 (1-4): " mode_choice
        case $mode_choice in
            1) TRAFFIC_MODE="out"; break ;;
            2) TRAFFIC_MODE="in"; break ;;
            3) TRAFFIC_MODE="total"; break ;;
            4) TRAFFIC_MODE="max"; break ;;
            *) echo "无效输入，请重新选择。" ;;
        esac
    done

    read -p "请选择流量统计周期 (m/q/y，默认为m): " period_choice
    case $period_choice in
        q) TRAFFIC_PERIOD="quarterly" ;;
        y) TRAFFIC_PERIOD="yearly" ;;
        m|"") TRAFFIC_PERIOD="monthly" ;;
        *) echo "无效输入，使用默认值：monthly"; TRAFFIC_PERIOD="monthly" ;;
    esac

    read -p "请输入周期起始日 (1-31，默认为1): " PERIOD_START_DAY
    if [[ -z "$PERIOD_START_DAY" ]]; then
        PERIOD_START_DAY=1
    elif ! [[ "$PERIOD_START_DAY" =~ ^[1-9]$|^[12][0-9]$|^3[01]$ ]]; then
        echo "无效输入，使用默认值：1"
        PERIOD_START_DAY=1
    fi

    while true; do
        read -p "请输入流量限制 (GB): " TRAFFIC_LIMIT
        if [[ "$TRAFFIC_LIMIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo "无效输入，请输入一个有效的数字。"
        fi
    done

    while true; do
        read -p "请输入容错范围 (GB): " TRAFFIC_TOLERANCE
        if [[ "$TRAFFIC_TOLERANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo "无效输入，请输入一个有效的数字。"
        fi
    done

    # 流量换算进制选择
    # 绝大多数服务商按 1024（通用标准口径），故默认 1024；
    # 1000 只适用于少数按十进制折算的服务商，需用户拿自己账单实测确认。
    while true; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') 请选择流量换算进制（用于把 vnstat 的字节数换算成 GB）："| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S')   1. 1024 进制（1GB = 1,073,741,824 字节）—— 默认，通用标准口径，绝大多数服务商适用"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S')   2. 1000 进制（1GB = 1,000,000,000 字节）—— 仅少数按十进制折算的服务商"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S')   提示：拿不准就选 1。判断方法：脚本数字一直比你的账单小约 7% 时，才改选 2。"| tee -a "$LOG_FILE"
        read -p "请输入选择 (1-2，默认为1): " base_choice
        case $base_choice in
            2) CONVERSION_BASE=1000; break ;;
            1|"") CONVERSION_BASE=1024; break ;;
            *) echo "无效输入，请重新选择。" ;;
        esac
    done

    # 日志上报（可选，默认关闭）
    # 涉及客户数据（机器名、流量数字），必须显式同意才开启。
    echo "$(date '+%Y-%m-%d %H:%M:%S') ------------------------------------------------------"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 是否开启「日志上报」？"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 开启后，脚本会上报结构化诊断信息（机器名、流量数字、脚本版本、"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 定时任务是否存活等），用于出现问题时我们快速定位原因。"| tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 上报内容不含任何业务数据，且随时可关闭。"| tee -a "$LOG_FILE"
    while true; do
        read -p "是否开启日志上报？(y/n，默认为n): " report_choice
        case $report_choice in
            y|Y)
                ENABLE_REPORT="yes"
                read -p "请输入上报地址 (REPORT_URL): " REPORT_URL
                read -p "请输入上报令牌 (REPORT_TOKEN): " REPORT_TOKEN
                REPORT_MACHINE_ID=${REPORT_MACHINE_ID:-$(hostname 2>/dev/null || echo unknown)}
                echo "已开启日志上报，机器标识: $REPORT_MACHINE_ID"
                break ;;
            n|N|"")
                ENABLE_REPORT="no"
                echo "日志上报保持关闭（推荐的安全默认值）"
                break ;;
            *) echo "无效输入，请重新选择。" ;;
        esac
    done

    while true; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') 请选择限制模式："| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 1. TC 模式（更灵活）"| tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 2. 关机模式（更安全）"| tee -a "$LOG_FILE"
        read -p "请输入选择 (1-2): " limit_mode_choice
        case $limit_mode_choice in
            1) 
                LIMIT_MODE="tc"
                read -p "请输入限速 (kbit/s，默认为20): " LIMIT_SPEED
                LIMIT_SPEED=${LIMIT_SPEED:-20}
                if ! [[ "$LIMIT_SPEED" =~ ^[0-9]+$ ]]; then
                    echo "无效输入，使用默认值：20 kbit/s"
                    LIMIT_SPEED=20
                fi
                break 
                ;;
            2) 
                LIMIT_MODE="shutdown"
                LIMIT_SPEED=""  # 关机模式不需要限速
                break 
                ;;
            *) echo "无效输入，请重新选择。" ;;
        esac
    done

    write_config
}

# ============================================================
# 周期日期计算（统一使用北京时间 UTC+8）
# ------------------------------------------------------------
# 阿里云 CDT 的免费额度刷新时间为「每自然月 1 日 0 点（北京时间）」，
# 计费阶梯累计长度也是自然月。因此这里所有 date 调用都必须显式带
# TZ='Asia/Shanghai'，不能依赖外部继承的 TZ，否则在 cron 或系统时区
# 为 UTC 的环境下，周期起点会晚 8 小时，导致月初流量统计偏差。
# ============================================================

# 北京时间 date 封装
# 不能写成 TZ='Asia/Shanghai' date ...：在缺少 zoneinfo 的系统上它会退回 UTC。
# 这里直接复用脚本顶部已归一化好的 $TZ（可能是 Asia/Shanghai 或 CST-8）。
bj_date() {
    date "$@"
}

# 获取当前周期的起始日期
get_period_start_date() {
    local current_year=$(bj_date +%Y)
    local current_month=$(bj_date +%m)
    local current_day=$(bj_date +%d)

    case $TRAFFIC_PERIOD in
        monthly)
            if [ "$current_day" -lt $PERIOD_START_DAY ]; then
                bj_date -d "${current_year}-${current_month}-${PERIOD_START_DAY} -1 month" +'%Y-%m-%d'
            else
                bj_date -d "${current_year}-${current_month}-${PERIOD_START_DAY}" +%Y-%m-%d 2>/dev/null || bj_date -d "${current_year}-${current_month}-01" +%Y-%m-%d
            fi
            ;;
        quarterly)
            local quarter_month=$((((10#$current_month - 1) / 3) * 3 + 1))
            if [ "$current_day" -lt $PERIOD_START_DAY ] || [ "$((10#$current_month))" -eq "$quarter_month" ]; then
                bj_date -d "${current_year}-$(printf '%02d' $quarter_month)-${PERIOD_START_DAY} -3 month" +'%Y-%m-%d'
            else
                bj_date -d "${current_year}-$(printf '%02d' $quarter_month)-${PERIOD_START_DAY}" +'%Y-%m-%d' 2>/dev/null || bj_date -d "${current_year}-$(printf '%02d' $quarter_month)-01" +%Y-%m-%d
            fi
            ;;
        yearly)
            if [ "$current_day" -lt $PERIOD_START_DAY ] || [ "$((10#$current_month))" -eq 1 ]; then
                bj_date -d "${current_year}-01-${PERIOD_START_DAY} -1 year" +'%Y-%m-%d'
            else
                bj_date -d "${current_year}-01-${PERIOD_START_DAY}" +'%Y-%m-%d' 2>/dev/null || bj_date -d "${current_year}-01-01" +%Y-%m-%d
            fi
            ;;
    esac
}

# 获取周期结束日期
get_period_end_date() {
    local current_year=$(bj_date +%Y)
    local current_month=$(bj_date +%m)
    local current_day=$(bj_date +%d)

    case $TRAFFIC_PERIOD in
        monthly)
            if [ "$current_day" -lt $PERIOD_START_DAY ]; then
                bj_date -d "${current_year}-${current_month}-${PERIOD_START_DAY} -1 day" +'%Y-%m-%d'
            else
                bj_date -d "${current_year}-${current_month}-${PERIOD_START_DAY} +1 month -1 day" +'%Y-%m-%d'
            fi
            ;;
        quarterly)
            local quarter_month=$((((10#$current_month - 1) / 3) * 3 + 1))
            if [ "$current_day" -lt $PERIOD_START_DAY ] || [ "$((10#$current_month))" -eq "$quarter_month" ]; then
                bj_date -d "${current_year}-$(printf '%02d' $quarter_month)-${PERIOD_START_DAY} +2 month -1 day" +'%Y-%m-%d'
            else
                bj_date -d "${current_year}-$(printf '%02d' $quarter_month)-${PERIOD_START_DAY} +5 month -1 day" +'%Y-%m-%d'
            fi
            ;;
        yearly)
            if [ "$current_day" -lt $PERIOD_START_DAY ] || [ "$((10#$current_month))" -eq 1 ]; then
                bj_date -d "${current_year}-12-31" +'%Y-%m-%d'
            else
                bj_date -d "$((current_year + 1))-12-31" +'%Y-%m-%d'
            fi
            ;;
    esac
}

# 获取流量使用情况
get_traffic_usage() {
    local start_date=$(get_period_start_date)
    local end_date=$(get_period_end_date)

    echo "$(date '+%Y-%m-%d %H:%M:%S') 周期开始日期: $start_date, 周期结束日期: $end_date" >&2

    # 优先使用小时级数据（--json h）按北京时间累加。
    # 原因：vnstat 的「日」是按宿主机时区切分的，若宿主机为 UTC，
    # 其日界比北京时间晚 8 小时，直接累加 day 数据会在月初产生偏差。
    # 小时级数据可以自行判断每个小时属于北京时间的哪一天，从而精确对齐
    # 阿里云 CDT 的北京时间自然月。
    local vnstat_json=$(vnstat -i "$MAIN_INTERFACE" --json h 2>/dev/null)

    # 回退：小时数据不可用时退回日数据（vnstat 2.x 老版本可能不支持 h）
    local use_hourly=true
    if [ -z "$vnstat_json" ] || ! echo "$vnstat_json" | jq -e '.interfaces[0].traffic.hour' >/dev/null 2>&1; then
        use_hourly=false
        vnstat_json=$(vnstat -i "$MAIN_INTERFACE" --json 2>/dev/null)
    fi

    if [ -z "$vnstat_json" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 错误: 无法获取 vnstat JSON 数据" >&2
        echo "0.000"
        return 1
    fi

    # 将日期转换为 YYYYMMDD 整数用于比较（兼容 vnstat 2.x 的 date 对象格式）
    local start_num=$(echo "$start_date" | tr -d '-')
    local end_num=$(echo "$end_date" | tr -d '-')

    # 根据 TRAFFIC_MODE 累加对应的流量
    local usage_bytes
    if [ "$use_hourly" = true ]; then
        # 小时级数据（推荐路径）。
        # 说明：vnstat 记录的日期/小时使用的是【宿主机系统时区】的切分结果，
        # 脚本内的 TZ 只影响 date 命令，无法改变 vnstat 已落库的切分。
        # 因此这里额外校验宿主机偏移：若宿主机不是 UTC+8，会在日志中告警，
        # 提示把系统时区改为 Asia/Shanghai（timedatectl set-timezone Asia/Shanghai）
        # 才能与阿里云 CDT 的北京时间自然月完全对齐。
        if [ "$HOST_TZ_WARNED" != "1" ] && [ "$(date +%z)" != "+0800" ]; then
            HOST_TZ_WARNED=1
            echo "$(date '+%Y-%m-%d %H:%M:%S') 警告: 宿主机时区为 $(date +%z)，非北京时间(+0800)。vnstat 按宿主机时区切分流量，可能与阿里云 CDT 的北京时间周期存在偏差。建议执行: timedatectl set-timezone Asia/Shanghai" >&2
        fi
        case $TRAFFIC_MODE in
            out)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.hour[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .tx] | add // 0')
                ;;
            in)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.hour[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .rx] | add // 0')
                ;;
            total)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.hour[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | (.rx + .tx)] | add // 0')
                ;;
            max)
                local rx_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.hour[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .rx] | add // 0')
                local tx_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.hour[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .tx] | add // 0')
                usage_bytes=$(printf '%s\n%s' "$rx_bytes" "$tx_bytes" | sort -rn | head -n1)
                ;;
        esac
    else
        # 日级数据回退路径（vnstat 老版本）
        case $TRAFFIC_MODE in
            out)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.day[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .tx] | add // 0')
                ;;
            in)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.day[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .rx] | add // 0')
                ;;
            total)
                usage_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.day[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | (.rx + .tx)] | add // 0')
                ;;
            max)
                local rx_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.day[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .rx] | add // 0')
                local tx_bytes=$(echo "$vnstat_json" | jq --argjson start_num "$start_num" --argjson end_num "$end_num" \
                    '[.interfaces[0].traffic.day[] | (.date.year * 10000 + .date.month * 100 + .date.day) as $date_num | select($date_num >= $start_num and $date_num <= $end_num) | .tx] | add // 0')
                usage_bytes=$(printf '%s\n%s' "$rx_bytes" "$tx_bytes" | sort -rn | head -n1)
                ;;
        esac
    fi

    if [ -n "$usage_bytes" ] && [ "$usage_bytes" != "null" ] && [ "$usage_bytes" != "0" ]; then
        # 字节 -> GB。进制由 CONVERSION_BASE 决定（默认 1024，见文件顶部说明）。
        local divisor=$(get_byte_divisor)
        local usage_gb=$(echo "scale=3; $usage_bytes/$divisor" | bc 2>/dev/null || echo "0.000")
        # 确保小数点前至少有一个0
        printf "%.3f\n" "$usage_gb" 2>/dev/null || echo "0.000"
    else
        echo "0.000"
    fi
}


# ============================================================
# 状态快照：供下游（tg_notifier / serverchan / pushplus）读取
# ============================================================
# 背景：原先每日报告用 `tac 日志 | grep -m 1` 抓「当前使用流量…限制流量」，
# 该行没有时间戳校验。一旦 cron 中断（客户机上真实发生过），日志停止更新，
# 报告就会读到几天前的旧值，表现为「流量倒退」。
# 现在改为写一份带时间戳的 JSON 快照，下游按新鲜度判断是否可信。
STATE_FILE="$WORK_DIR/traffic_state.json"

write_state_snapshot() {
    local usage="$1"
    local limit="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local epoch
    epoch=$(date +%s)
    local period_start
    period_start=$(get_period_start_date 2>/dev/null || echo "")

    # 用 cat 重定向整体覆盖写入，避免半行损坏
    cat > "$STATE_FILE" <<EOF
{
  "timestamp": "$ts",
  "epoch": $epoch,
  "usage_gb": ${usage:-0},
  "limit_gb": ${limit:-0},
  "conversion_base": ${CONVERSION_BASE:-1024},
  "period_start": "$period_start",
  "script_version": "${SCRIPT_VERSION:-1.0.91}",
  "hostname": "$(hostname 2>/dev/null || echo unknown)"
}
EOF
    chmod 644 "$STATE_FILE" 2>/dev/null
}

# 读取状态快照的新鲜度（秒）。读不到或解析失败则回显极大值，视为不可信。
# 用法: state_age_seconds [文件路径]
state_age_seconds() {
    local f="${1:-${STATE_FILE:-$WORK_DIR/traffic_state.json}}"
    [ -f "$f" ] || { echo "999999999"; return; }
    local epoch
    epoch=$(grep -o '"epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$f" 2>/dev/null | grep -o '[0-9]*$')
    [ -n "$epoch" ] || { echo "999999999"; return; }
    local now
    now=$(date +%s)
    echo $((now - epoch))
}


# 修改 check_and_limit_traffic 函数
check_and_limit_traffic() {
    local current_usage=$(get_traffic_usage)
    local limit_threshold=$(echo "$TRAFFIC_LIMIT - $TRAFFIC_TOLERANCE" | bc 2>/dev/null || echo "0")
    
    # --run（cron）模式不会走 show_current_config，此处显式记录当前进制，
    # 便于事后排查「脚本数字与账单对不上」这类问题。
    echo "$(date '+%Y-%m-%d %H:%M:%S') 流量换算进制: ${CONVERSION_BASE:-1024} (1GB = ${CONVERSION_BASE:-1024}^3 字节)" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 当前使用流量: $current_usage GB，限制流量: $limit_threshold GB" | tee -a "$LOG_FILE"

    # 写入机器可读的状态快照（带时间戳）。
    # 下游（tg_notifier 每日报告等）必须读这个文件，而不是去 guess 日志里的最后一行——
    # 日志行没有时间戳校验，cron 一旦中断就会读到几天前的陈旧值，导致「流量倒退」假象。
    write_state_snapshot "$current_usage" "$limit_threshold"

    # 心跳上报（可选，默认关闭）。降频：每 REPORT_HEARTBEAT_EVERY 次检查上报一次。
    # 用计数器文件而非内存变量，因为脚本是「一次运行一次检查」的模型。
    if [ "${ENABLE_REPORT:-no}" = "yes" ] && declare -f report_event >/dev/null 2>&1; then
        local hb_file="$WORK_DIR/.report_hb_count"
        local hb_count=0
        [ -f "$hb_file" ] && hb_count=$(cat "$hb_file" 2>/dev/null || echo 0)
        [[ "$hb_count" =~ ^[0-9]+$ ]] || hb_count=0
        hb_count=$((hb_count + 1))
        if [ "$hb_count" -ge "${REPORT_HEARTBEAT_EVERY:-60}" ]; then
            hb_count=0
            report_event "heartbeat" "$current_usage" "$limit_threshold" "$(get_period_start_date 2>/dev/null)" "" &
        fi
        echo "$hb_count" > "$hb_file" 2>/dev/null
    fi
    
    if (( $(echo "$current_usage > $limit_threshold" | bc -l 2>/dev/null || echo "0") )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量超出限制" | tee -a "$LOG_FILE"
        if [ "$LIMIT_MODE" = "tc" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 使用 TC 模式限速" | tee -a "$LOG_FILE"
            tc qdisc add dev $MAIN_INTERFACE root tbf rate ${LIMIT_SPEED}kbit burst 32kbit latency 400ms
        elif [ "$LIMIT_MODE" = "shutdown" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') 流量超出限制，系统将在 1 分钟后关机" | tee -a "$LOG_FILE"
            shutdown -h +1 "流量超出限制，系统将在 1 分钟后关机"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 流量正常，清除所有限制" | tee -a "$LOG_FILE"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}


# 检查是否需要重置限制
check_reset_limit() {
    # 使用北京时间判断是否进入新周期（与 CDT 免费额度刷新时间对齐）
    local current_date=$(bj_date +%Y-%m-%d)
    local period_start=$(get_period_start_date)
    
    if [[ "$current_date" == "$period_start" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 新的流量周期开始，重置限制"| tee -a "$LOG_FILE"
        tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
    fi
}

# 设置/修复 crontab 任务。
#
# ⚠️ 这里曾经是一个真实的丢任务事故点（客户机实测 cron 消失）。
#    原写法是「先删后加」两步：
#        crontab -l | grep -v "$SCRIPT_PATH" | crontab -
#        (crontab -l; echo "...") | crontab -
#    两步之间任何环节失败（磁盘满、crontab 锁、脚本被中断），
#    cron 就已经进入「被删除且没加回」的状态。
#    更糟的是第 2 步失败时 `crontab -` 收到空输入会**把整个 crontab 清空**，
#    连客户自己的其他定时任务一起丢失。
#
# 现在的做法：
#   1. 全程在内存里组装，只调用一次 `crontab -`（原子）；
#   2. 先备份原 crontab 到文件，失败可回滚；
#   3. 写完立即回读校验，确认任务真的在，才算成功；
#   4. 附带自愈：cron 服务没装/没启动时尝试拉起。
setup_crontab() {
    local cron_line="* * * * * $SCRIPT_PATH --run"
    local backup_file="$WORK_DIR/crontab.backup.$$"
    # ⚠️ tmp_file 必须在这里赋值。写成 `local tmp_file new_content`（只声明不赋值）
    #    会让后面的 `> "$tmp_file"` 重定向到空文件名，报
    #    "No such file or directory"，随后 `crontab ""` 写空 —— 整个 crontab 被清空。
    #    这正是本次要修的那类事故，只是换了个入口。
    local tmp_file="$WORK_DIR/crontab.tmp.$$"
    local new_content

    # crontab 为空时 `crontab -l` 退出码是 1，不能当成错误处理
    local current
    current=$(crontab -l 2>/dev/null)

    # ---- 组装新内容（纯内存，不碰 crontab）----
    # 去掉：TrafficCop 自己的旧任务行 + 本脚本可能追加过的空行
    new_content=$(printf '%s\n' "$current" \
        | grep -v -e "$SCRIPT_PATH" -e 'traffic_monitor\.sh' \
        | grep -v '^[[:space:]]*$')

    {
        [ -n "$new_content" ] && printf '%s\n' "$new_content"
        printf '%s\n' "$cron_line"
    } > "$tmp_file"

    # ---- 备份原 crontab（供失败回滚）----
    printf '%s\n' "$current" > "$backup_file" 2>/dev/null

    # ---- 原子写入：整个 crontab 只写这一次 ----
    if ! crontab "$tmp_file" 2>/dev/null; then
        # 写入失败：立刻回滚，绝不留下「被删掉」的中间态
        if [ -s "$backup_file" ]; then
            crontab "$backup_file" 2>/dev/null && \
                echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：写入 crontab 失败，已回滚原设置。"| tee -a "$LOG_FILE"
        fi
        rm -f "$tmp_file" "$backup_file" 2>/dev/null
        return 1
    fi

    # ---- 回读校验：写进去不等于生效，必须确认 ----
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Crontab 已设置，每分钟运行一次"| tee -a "$LOG_FILE"
        rm -f "$tmp_file" "$backup_file" 2>/dev/null
        return 0
    fi

    # 校验不过：回滚
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：crontab 写入后校验未通过，正在回滚。"| tee -a "$LOG_FILE"
    [ -s "$backup_file" ] && crontab "$backup_file" 2>/dev/null
    rm -f "$tmp_file" "$backup_file" 2>/dev/null
    return 1
}

# 自愈：cron 服务装了但没运行 / 压根没装时，任务写了也不会执行。
# 这是「crontab 里有任务但日志不更新」这类现象的常见原因。
ensure_cron_service() {
    # 已经能读到自己的任务且 cron 在跑 -> 什么都不用做
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
        # 任务在，但还要确认 cron 守护进程是否活着
        if pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1; then
            return 0
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：crontab 中有本脚本任务，但 cron 服务未运行，正在尝试启动。"| tee -a "$LOG_FILE"
    fi

    local started=no
    # Debian/Ubuntu 系
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start cron 2>/dev/null && started=yes
        systemctl is-active cron >/dev/null 2>&1 && started=yes
    fi
    # CentOS/RHEL 系
    [ "$started" = no ] && { service crond start 2>/dev/null && started=yes; }
    # 精简系统可能只有 cron 命令
    [ "$started" = no ] && { cron 2>/dev/null; pgrep -x cron >/dev/null 2>&1 && started=yes; }

    if [ "$started" = yes ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') cron 服务已启动。"| tee -a "$LOG_FILE"
        return 0
    fi
    return 1
}


# 主函数
main() {


   # 调用函数来杀死其他实例
   kill_other_instances
  
  # 在脚本开始时调用迁移函数
   migrate_files

  # 切换到工作目录
   cd "$WORK_DIR" || exit 1

# 创建锁文件（如果不存在）
touch "${LOCK_FILE}"

# 尝试获取文件锁
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') 另一个脚本实例正在运行，退出。" | tee -a "$LOG_FILE"
    exit 1
fi

    # 检查是否以 --run 模式运行
    if [ "$1" = "--run" ]; then
        # ⚠️ 轮转必须在本分支的【第一次日志写入之前】执行。
        # 否则「正在以自动化模式运行」那行会先写进即将被归档的旧文件，
        # 导致归档里混入新记录、破坏下游 tac 查询的时序语义。
        rotate_log_if_needed

        echo "$(date '+%Y-%m-%d %H:%M:%S') 正在以自动化模式运行" | tee -a "$LOG_FILE"
        if read_config; then
            check_reset_limit
            check_and_limit_traffic
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件读取失败，请检查配置" | tee -a "$LOG_FILE"
        fi
        return
    fi

 # 非 --run 模式下的操作
  # 首先检查并安装必要的软件包
    check_and_install_packages
    if check_existing_setup; then
        read_config
        show_current_config

        echo "$(date '+%Y-%m-%d %H:%M:%S') 是否需要修改配置？(y/n): 5秒内按任意键修改配置，否则保持现有配置" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 开始等待用户输入..." | tee -a "$LOG_FILE"
        
        start_time=$(date +%s.%N)
     if read -t 5 -n 1 modify_config; then
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    echo ""  # 换行
    echo "$(date '+%Y-%m-%d %H:%M:%S') 收到用户输入: '${modify_config}' (ASCII: $(printf '%d' "'$modify_config" 2>/dev/null || echo "N/A"))" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 等待时间: $duration 秒" | tee -a "$LOG_FILE"
    if [[ $duration < 0.1 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 警告：输入时间过短，可能是自动输入" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') 忽略此输入，保持现有配置。" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 开始修改配置..." | tee -a "$LOG_FILE"
        initial_config
        setup_crontab
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置已更新，脚本将每分钟自动运行一次" | tee -a "$LOG_FILE"
    fi
else
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    echo ""  # 换行
    echo "$(date '+%Y-%m-%d %H:%M:%S') 等待超时，无用户输入" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 等待时间: $duration 秒" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 保持现有配置。" | tee -a "$LOG_FILE"
fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 开始初始化配置..." | tee -a "$LOG_FILE"
        initial_config
        setup_crontab
        echo "$(date '+%Y-%m-%d %H:%M:%S') 初始配置完成，脚本将每分钟自动运行一次" | tee -a "$LOG_FILE"
    fi

    # 显示当前流量使用情况和限制状态
    if read_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 当前流量使用情况：" | tee -a "$LOG_FILE"
        local current_usage=$(get_traffic_usage)
        #echo "Debug: Current usage from get_traffic_usage: $current_usage" | tee -a "$LOG_FILE"
        if [ "$current_usage" != "0" ]; then
            local start_date=$(get_period_start_date)
            echo "$(date '+%Y-%m-%d %H:%M:%S') 当前统计周期: $TRAFFIC_PERIOD (从 $start_date 开始)" | tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 统计模式: $TRAFFIC_MODE" | tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 当前使用流量: $current_usage GB" | tee -a "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') 检查并限制流量：" | tee -a "$LOG_FILE"
            check_and_limit_traffic
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 无法获取流量数据，请检查 vnstat 配置" | tee -a "$LOG_FILE"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 配置文件读取失败，请检查配置" | tee -a "$LOG_FILE"
    fi
    
# 确保脚本退出时释放锁
trap 'flock -u 9; rm -f ${LOCK_FILE}' EXIT
}



# 执行主函数
main "$@"



echo "-----------------------------------------------------"| tee -a "$LOG_FILE"
