#!/bin/bash
# ============================================================
# TrafficCop 日志上报模块（方案 C：结构化 JSON 心跳上报）
# ============================================================
#
# 设计原则
# --------
# 1. 【默认关闭】必须用户显式开启（ENABLE_REPORT=yes）。日志含机器名、
#    流量数字等客户数据，默认开启在信任与法律上都站不住。
# 2. 【失败静默】上报失败绝不影响主流程。网络不通、服务端宕机、
#    格式变化——一律不阻塞流量监控本体。
# 3. 【绝不泄露密钥】客户端只持有「上报令牌」（可随时吊销），
#    不持有任何 R2 / S3 的长期凭证。
# 4. 【字段固定】上报字段是固定 schema，服务端可直接查询/聚合，
#    不必解析自由文本日志。
#
# 用法（在主脚本中）
# ------------------
#   source "$WORK_DIR/report_lib.sh"
#   report_event "daily" "$current_usage" "$limit" "$period_start"
#
# 三个上报时机：
#   - report_event "heartbeat"  → 每次流量检查后（默认 1 次/分钟，可降频）
#   - report_event "daily"      → 每日报告时
#   - report_event "error"      → 异常时（cron 丢失、vnstat 无数据等）
#

# ---------- 配置（由主配置读取，或环境变量覆盖） ----------
# ENABLE_REPORT: yes/no  —— 是否开启上报（默认 no）
# REPORT_URL:    上报端点 —— 如 https://trafficcop-logs.<account>.workers.dev/report
# REPORT_TOKEN:  上报令牌 —— 与服务端共享的校验值，可随时吊销
# REPORT_MACHINE_ID: 机器标识（默认取 hostname）
# REPORT_TIMEOUT: curl 超时秒数（默认 10）

REPORT_TIMEOUT="${REPORT_TIMEOUT:-10}"

# ---------- 内部：判断是否应当上报 ----------
_report_enabled() {
    [ "${ENABLE_REPORT:-no}" = "yes" ] || return 1
    [ -n "${REPORT_URL:-}" ] || return 1
    [ -n "${REPORT_TOKEN:-}" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    return 0
}

# ---------- 内部：判断字节流是否是合法 UTF-8 ----------
# 用纯 builtin 实现（不 spawn 子进程）——逻辑与 _sanitize_utf8 的校验部分一致。
# 返回 0 = 合法，1 = 非法。
_is_valid_utf8() {
    local s="$1"
    [ -n "$s" ] || return 0

    local -a b=()
    local i n c ch o
    local _old_set=0 _old=""
    [ "${LC_ALL+set}" = set ] && { _old_set=1; _old="$LC_ALL"; }
    export LC_ALL=C
    n=${#s}
    for (( i = 0; i < n; i++ )); do
        ch="${s:i:1}"
        printf -v o '%d' "'$ch" 2>/dev/null || o=0
        b+=("$o")
    done
    if [ "$_old_set" -eq 1 ]; then export LC_ALL="$_old"; else unset LC_ALL; fi

    n=${#b[@]}
    i=0
    local need j ok
    while [ "$i" -lt "$n" ]; do
        c=${b[$i]}
        if [ "$c" -lt 128 ]; then i=$((i + 1)); continue; fi
        if [ "$c" -ge 192 ] && [ "$c" -le 223 ]; then need=2
        elif [ "$c" -ge 224 ] && [ "$c" -le 239 ]; then need=3
        elif [ "$c" -ge 240 ] && [ "$c" -le 247 ]; then need=4
        else return 1; fi
        [ $((i + need)) -le "$n" ] || return 1
        ok=1
        j=1
        while [ "$j" -lt "$need" ]; do
            ch=${b[$((i + j))]}
            if [ "$ch" -lt 128 ] || [ "$ch" -gt 191 ]; then ok=0; break; fi
            j=$((j + 1))
        done
        [ "$ok" -eq 1 ] || return 1
        i=$((i + need))
    done
    return 0
}

# ---------- 内部：非 UTF-8 时的尽力还原（GBK/GB18030 → UTF-8）----------
# 背景：Windows 中文系统的 `hostname` 返回 GBK 字节。若直接净化成 '?',
# 客户在后台看到的机器名就是一串问号，无法定位是哪台机器——
# 这在「排查单台机器」的主场景下等于信息作废。
# 所以先尝试 iconv 还原；iconv 不存在或还原失败，再退回净化。
_try_recover_encoding() {
    local s="$1"
    command -v iconv >/dev/null 2>&1 || return 1
    local out
    # GB18030 是 GBK 的超集，覆盖面更广；失败再试 GBK
    out=$(printf '%s' "$s" | iconv -f GB18030 -t UTF-8 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    out=$(printf '%s' "$s" | iconv -f GBK -t UTF-8 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

# ---------- 内部：剔除非法字节，保证输出是合法 UTF-8 ----------
# ⚠️ 真实场景踩过的坑：Windows 上 `hostname` 对中文机器名返回的是 **GBK 字节**
# （如「杨培强的电脑」→ d1 ee c5 e0 ...），直接塞进 JSON 会产生非法 UTF-8，
# 服务端 JSON.parse / Python / jq 全部解析失败 → 该机器**每一份上报都静默丢失**。
# 而中文机器名恰恰是绝大多数国内客户端的默认情况，属于必现故障。
#
# 处理策略：保留合法 UTF-8 序列；遇到非法字节替换成 '?'，
# 保证「宁可机器名显示成问号，也不能让整条上报丢掉」。
#
# ⚠️ 实现注意（踩过三次才定的方案，勿改）：
#   1. 必须按【字节】遍历，不能用 ${s:i:1} 在默认 locale 下切——那是按字符切，
#      中文被整体取出，字节判断全错。
#   2. 绝不能在循环里 spawn 子进程。曾用 `printf '%s' "$s" | od -An -v -tu1`，
#      本机实测 **730ms/次**（管道 3 个进程），13 个字段就是 9.5 秒，
#      直接把每分钟一次的流量检查拖死。改成 LC_ALL=C + 纯 builtin 算术后
#      降到 **~10ms/次**，且零子进程。
#   3. 单次调用成本几乎全是 bash 本身的开销（本机 Git Bash fork 一个外部进程
#      就要 330ms），算法侧已无优化空间；**真实部署目标 Linux 上是 ~1ms 级**。
_sanitize_utf8() {
    local s="$1"
    [ -n "$s" ] || { printf ''; return; }

    # 快速路径：本来就是合法 UTF-8（绝大多数情况），直接返回，零额外开销。
    if _is_valid_utf8 "$s"; then
        printf '%s' "$s"
        return
    fi

    # 慢路径：非法 UTF-8。先试着按 GBK/GB18030 还原（Windows 中文机器名场景），
    # 还原成功则得到可读中文；失败再逐字节净化成 '?'。
    local recovered
    if recovered=$(_try_recover_encoding "$s") && _is_valid_utf8 "$recovered"; then
        printf '%s' "$recovered"
        return
    fi

    local esc="" i n c need ok j k o
    local -a b=()

    # --- 第一步：按字节取值（LC_ALL=C 下 ${s:i:1} 即单字节）---
    # 必须临时把 LC_ALL 设为 C，否则 ${s:i:1} 按「字符」切，中文被整体取出。
    # 用 local 无法改 locale（locale 是环境变量，bash 只在 export 后生效），
    # 所以这里 export 后再精确还原；已用 .workbuddy/verify_locale_isolation.sh
    # 验证对调用方无污染（trafficcop.sh 主流程依赖 date/sort/grep 的 UTF-8 行为）。
    local _old_lc_all_set=0 _old_lc_all="" _old_lc_set=0 _old_lc=""
    [ "${LC_ALL+set}" = set ] && { _old_lc_all_set=1; _old_lc_all="$LC_ALL"; }
    [ "${LC_CTYPE+set}" = set ] && { _old_lc_set=1; _old_lc="$LC_CTYPE"; }

    export LC_ALL=C
    n=${#s}
    for (( i = 0; i < n; i++ )); do
        c="${s:i:1}"
        printf -v o '%d' "'$c" 2>/dev/null || o=0
        b+=("$o")
    done
    # 精确还原（区分「原值为空」与「原本未设置」）
    if [ "$_old_lc_all_set" -eq 1 ]; then export LC_ALL="$_old_lc_all"; else unset LC_ALL; fi
    if [ "$_old_lc_set" -eq 1 ]; then export LC_CTYPE="$_old_lc"; else unset LC_CTYPE; fi

    # --- 第二步：校验并转义 ---
    n=${#b[@]}
    i=0
    while [ "$i" -lt "$n" ]; do
        c=${b[$i]}
        if [ "$c" -lt 128 ]; then
            # ASCII 一律原样保留（含控制字符）——控制字符的转义是 _json_escape 的职责。
            # ⚠️ 早期版本在这里把 <32 的字节转成 '?'，导致换行/制表符被吞
            # （实测：message="l1\nl2" 变成 "l1?l2"），属信息损失，必须避免。
            esc+="\\$(( c / 64 ))$(( (c % 64) / 8 ))$(( c % 8 ))"
            i=$((i + 1)); continue
        fi
        if [ "$c" -ge 192 ] && [ "$c" -le 223 ]; then need=2
        elif [ "$c" -ge 224 ] && [ "$c" -le 239 ]; then need=3
        elif [ "$c" -ge 240 ] && [ "$c" -le 247 ]; then need=4
        else
            esc+="?"; i=$((i + 1)); continue
        fi
        if [ $((i + need)) -gt "$n" ]; then
            esc+="?"; i=$((i + 1)); continue
        fi
        ok=1
        j=1
        while [ "$j" -lt "$need" ]; do
            local seq=${b[$((i + j))]}
            if [ "$seq" -lt 128 ] || [ "$seq" -gt 191 ]; then ok=0; break; fi
            j=$((j + 1))
        done
        if [ "$ok" -eq 1 ]; then
            k=0
            while [ "$k" -lt "$need" ]; do
                o=${b[$((i + k))]}
                esc+="\\$(( o / 64 ))$(( (o % 64) / 8 ))$(( o % 8 ))"
                k=$((k + 1))
            done
            i=$((i + need))
        else
            esc+="?"; i=$((i + 1))
        fi
    done

    # --- 第三步：单次还原（esc 只含 ASCII 与 \ooo 转义）---
    printf '%b' "$esc"
}

# ---------- 内部：JSON 字符串转义 ----------
# 只处理 JSON 必需的最小转义，避免引入 jq 依赖（部分精简系统没有）
_json_escape() {
    local s
    s=$(_sanitize_utf8 "$1")
    s="${s//\\/\\\\}"      # 反斜杠
    s="${s//\"/\\\"}"      # 双引号
    s="${s//$'\n'/\\n}"    # 换行
    s="${s//$'\r'/\\r}"    # 回车
    s="${s//$'\t'/\\t}"    # 制表符
    printf '%s' "$s"
}

# ---------- 内部：把值安全转成 JSON 数字 ----------
# 非数字（空、null、含字母）一律回退为 0，避免产生非法 JSON
_json_number() {
    local v="$1"
    if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s' "$v"
    else
        printf '0'
    fi
}

# ---------- 内部：探测 cron 是否存活 ----------
# 返回 yes / no / unknown
_detect_cron_alive() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "unknown"; return
    fi
    if crontab -l 2>/dev/null | grep -q "trafficcop.sh\|traffic_monitor.sh"; then
        echo "yes"
    else
        echo "no"
    fi
}

# ---------- 内部：从状态快照读取新鲜度（秒） ----------
# 读不到返回 -1，表示未知
_state_age() {
    local f="${WORK_DIR:-/root/TrafficCop}/traffic_state.json"
    [ -f "$f" ] || { echo "-1"; return; }
    local epoch
    epoch=$(grep -o '"epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$f" 2>/dev/null | grep -o '[0-9]*$')
    [ -n "$epoch" ] || { echo "-1"; return; }
    echo $(( $(date +%s) - epoch ))
}

# ---------- 主函数：上报一个事件 ----------
# 参数：
#   $1 event_type   heartbeat / daily / error / install
#   $2 usage_gb     当前使用流量（可空）
#   $3 limit_gb     限制流量（可空）
#   $4 period_start 周期起始（可空）
#   $5 message      附加说明（可空）
report_event() {
    _report_enabled || return 0

    local event_type="${1:-heartbeat}"
    local usage_gb="${2:-}"
    local limit_gb="${3:-}"
    local period_start="${4:-}"
    local message="${5:-}"

    local machine_id="${REPORT_MACHINE_ID:-$(hostname 2>/dev/null || echo unknown)}"
    local script_version="${SCRIPT_VERSION:-unknown}"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local epoch
    epoch=$(date +%s)

    # 自动附带诊断字段 —— 这些正是「能直接定位原因」的关键
    local cron_alive
    cron_alive=$(_detect_cron_alive)
    local state_age
    state_age=$(_state_age)
    local conversion_base="${CONVERSION_BASE:-1000}"
    local vnstat_start
    vnstat_start=$(cat "${WORK_DIR:-/root/TrafficCop}/.vnstat_start" 2>/dev/null || echo "")

    # 采集构建 JSON（用 printf 拼接，避免 heredoc 变量展开的坑）
    local payload
    payload=$(printf '{"event":"%s","machine_id":"%s","script_version":"%s","timestamp":"%s","epoch":%s,"usage_gb":%s,"limit_gb":%s,"conversion_base":%s,"period_start":"%s","cron_alive":"%s","state_age_sec":%s,"vnstat_start":"%s","message":"%s"}' \
        "$(_json_escape "$event_type")" \
        "$(_json_escape "$machine_id")" \
        "$(_json_escape "$script_version")" \
        "$(_json_escape "$ts")" \
        "$(_json_number "$epoch")" \
        "$(_json_number "$usage_gb")" \
        "$(_json_number "$limit_gb")" \
        "$(_json_number "$conversion_base")" \
        "$(_json_escape "$period_start")" \
        "$(_json_escape "$cron_alive")" \
        "$(_json_number "$state_age")" \
        "$(_json_escape "$vnstat_start")" \
        "$(_json_escape "$message")"
    )

    # 上报。--max-time 保证不拖慢主流程；-s 静默；失败不影响退出码
    local response
    response=$(curl -s --max-time "$REPORT_TIMEOUT" \
        -X POST "$REPORT_URL" \
        -H "Content-Type: application/json" \
        -H "X-Report-Token: $REPORT_TOKEN" \
        -H "X-Machine-Id: $machine_id" \
        -d "$payload" 2>/dev/null)

    # 记一行到本地日志，便于事后核对（不影响主流程）
    local log_f="${WORK_DIR:-/root/TrafficCop}/report.log"
    if echo "$response" | grep -q '"ok":true'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 上报成功 [$event_type] $machine_id" >> "$log_f" 2>/dev/null
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 上报失败 [$event_type] resp=$response" >> "$log_f" 2>/dev/null
    fi

    return 0
}

# ---------- 方案 A 兜底：上传完整日志到 R2 ----------
# 仅在用户显式执行「导出日志」时调用，日常不自动跑。
# 依赖 rclone（客户端需自行安装），或直接用预签名 URL + curl。
#
# 用法：
#   export R2_PRESIGN_URL="https://..."   # 由服务端签发的临时 PUT URL
#   upload_full_log
upload_full_log() {
    [ "${ENABLE_REPORT:-no}" = "yes" ] || return 1

    local log_file="${WORK_DIR:-/root/TrafficCop}/traffic_monitor.log"
    [ -f "$log_file" ] || { echo "日志文件不存在: $log_file"; return 1; }

    local machine_id="${REPORT_MACHINE_ID:-$(hostname 2>/dev/null || echo unknown)}"
    local date_tag
    date_tag=$(date '+%Y%m%d-%H%M%S')

    # 优先用 rclone（支持大文件、断点续传）
    if command -v rclone >/dev/null 2>&1 && [ -n "${R2_REMOTE:-}" ]; then
        echo "使用 rclone 上传到 $R2_REMOTE:$R2_BUCKET/logs/$machine_id/"
        rclone copy "$log_file" "$R2_REMOTE:$R2_BUCKET/logs/$machine_id/" \
            --s3-upload-cutoff 50M \
            --transfers 1 \
            --retries 3 \
            --progress
        return $?
    fi

    # 退而求其次：预签名 URL + curl
    if [ -n "${R2_PRESIGN_URL:-}" ]; then
        echo "使用预签名 URL 上传"
        curl --max-time 300 -X PUT "$R2_PRESIGN_URL" \
            -H "Content-Type: text/plain" \
            --data-binary "@$log_file"
        return $?
    fi

    echo "未配置上传方式：请设置 R2_REMOTE+R2_BUCKET（rclone）或 R2_PRESIGN_URL（预签名）"
    return 1
}
