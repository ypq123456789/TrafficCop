#!/bin/bash
# ============================================================
# 验证：新周期提醒只发一次，且必须发得出去（issue #25）
# ------------------------------------------------------------
# 复现的客户现象：重置日当天收到 485 条一模一样的
#   「🔄 新周期开始：新的流量统计周期已开始，之前的限速（如果有）已自动解除。」
# 0 点到 8 点，每分钟一条。
#
# 三个缺陷叠加：
#   ① trafficcop.sh 的 check_reset_limit 判据是「今天 == 本周期起点」。
#      该条件在重置日【一整天】都成立，而 cron 每分钟跑一次，
#      于是当天写下 1440 条「新的流量周期开始，重置限制」；
#   ② get_traffic_usage 把「本周期内一条 vnstat 记录都查不到」判成取数失败
#      （vnstat 不为 0 字节的小时建条目）。重置日恰好空闲一夜，
#      于是 0-8 点里「流量正常」那行永远写不出来，「新周期」始终是最新一条。
#      8 点机器开始有流量，条目出现，重复推送随之停止 —— 与客户描述完全吻合；
#   ③ 通知脚本的「新周期」分支没有 last_status 判据，无条件发送。
#
# 修复后又暴露出两个问题，本脚本一并覆盖：
#   ④ 光靠日志判断「新周期」根本不可靠：主脚本在同一次运行里会连着写
#      「新周期开始」和「流量正常」，通知脚本每分钟才轮询一次，几乎总是
#      读到后者 → 通知永远发不出去。改为读主脚本落盘的周期标识（事件）。
#   ⑤ 周期窗口的判据不能只看「日号」：2026-02-05、起始日 15 时，2 月 5 日
#      小于 15 会让整个 2 月退回上一季度，窗口不含今天。
#
# 用法: bash test_period_reset.sh
# 依赖: bash / awk / date(GNU)
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/trafficcop.sh"
PASS=0
FAIL=0
ok() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
no() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

if [ ! -f "$SRC" ]; then
    echo "找不到 trafficcop.sh: $SRC"
    exit 1
fi

TMP=$(mktemp -d 2>/dev/null || echo "./_period_reset_tmp")
mkdir -p "$TMP"

# 与主脚本一致的时区处理（周期起点按北京时间算）
if [ "$(TZ='Asia/Shanghai' date '+%z' 2>/dev/null)" = "+0800" ]; then
    export TZ='Asia/Shanghai'
else
    export TZ='CST-8'
fi

# ------------------------------------------------------------
# 按函数名抽取 shell 函数体（与 test_usage_window.sh 同一手法）
# ------------------------------------------------------------
extract_func() {
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        $0 ~ "^" fn "\\(\\) \\{" { on = 1 }
        on {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0 && seen) exit
            seen = 1
        }
    ' "$file"
}

: > "$TMP/funcs.sh"
for fn in bj_date period_length_months period_anchor_month month_shift \
          period_anchor_at period_start_ymd \
          get_period_start_date get_period_end_date check_reset_limit; do
    extract_func "$SRC" "$fn" >> "$TMP/funcs.sh"
    grep -q "^${fn}() {" "$TMP/funcs.sh" || { echo "抽取失败: $fn"; exit 1; }
done

# shellcheck disable=SC1090
source "$TMP/funcs.sh"

# ============================================================
# A. check_reset_limit 必须按周期幂等（而不是按「日期命中」）
# ============================================================
echo ""
echo "===== A. 周期重置幂等 ====="

# tc 用桩替代（本机没有 tc，也不该真去动网卡）
tc() { echo "tc $*" >> "$TC_CALLS"; }

TRAFFIC_PERIOD="monthly"
# 让「今天」正好是周期起点 —— 与客户机器收到重复推送那天的状态一致
PERIOD_START_DAY="$(bj_date +%d)"
TODAY="$(bj_date +%Y-%m-%d)"
CUR_PERIOD="$(get_period_start_date)"
echo "  今天=$TODAY  本周期起点=$CUR_PERIOD"

# A1. 首次运行（没有标记文件）：只初始化，不发「新周期」，也不动 tc
CASE="$TMP/a1"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
check_reset_limit >/dev/null 2>&1
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "0" ] && ok "A1 首次运行不伪造「新周期开始」日志" \
    || no "A1 首次运行就写了 $n_new 条新周期日志"
[ "$n_tc" = "0" ] && ok "A1 首次运行不动 tc（周期中途升级不该删掉现有限速）" \
    || no "A1 首次运行删了 $n_tc 次 tc 规则"
[ "$(cat "$PERIOD_RESET_FILE" 2>/dev/null)" = "$CUR_PERIOD" ] \
    && ok "A1 已落盘本周期起点标记" || no "A1 标记文件内容不对"

# A2. 同一周期内反复运行：一条日志都不能多
CASE="$TMP/a2"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
printf '%s\n' "$CUR_PERIOD" > "$PERIOD_RESET_FILE"
for _ in $(seq 1 20); do check_reset_limit >/dev/null 2>&1; done
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "0" ] && ok "A2 同周期内跑 20 次（一天是 1440 次）不写任何新周期日志" \
    || no "A2 同周期内写了 $n_new 条新周期日志"
[ "$n_tc" = "0" ] && ok "A2 同周期内不重复执行 tc del" || no "A2 重复执行了 $n_tc 次 tc del"

# A3. 跨周期（含「重置日机器关机、几天后才开机」）：只动作一次、只写一条
CASE="$TMP/a3"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
printf '2000-01-01\n' > "$PERIOD_RESET_FILE"
for _ in $(seq 1 20); do check_reset_limit >/dev/null 2>&1; done
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "1" ] && ok "A3 周期切换后只写 1 条新周期日志（旧实现是 20 条）" \
    || no "A3 新周期日志条数异常: $n_new"
[ "$n_tc" = "1" ] && ok "A3 周期切换后只清一次限速" || no "A3 tc del 次数异常: $n_tc"

# A4. 标记文件损坏（空内容）时按首次运行处理，不炸也不重复
CASE="$TMP/a4"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"; : > "$PERIOD_RESET_FILE"
check_reset_limit >/dev/null 2>&1
[ "$(cat "$PERIOD_RESET_FILE" 2>/dev/null)" = "$CUR_PERIOD" ] \
    && ok "A4 空标记文件被正常覆盖" || no "A4 空标记文件未被修复"

# ============================================================
# B. 周期窗口：必须正好一个周期，且必须包含今天
# ============================================================
echo ""
echo "===== B. 周期窗口（季 / 年 / 月） ====="

# 用可控的「今天」驱动日期函数（其余调用仍交给真实 date）
FAKE_Y=2026; FAKE_M=01; FAKE_D=05
bj_date() {
    case "$1" in
        +%Y)     echo "$FAKE_Y" ;;
        +%m)     echo "$FAKE_M" ;;
        +%d)     echo "$FAKE_D" ;;
        +%Y%m%d) printf '%s%s%s\n' "$FAKE_Y" "$FAKE_M" "$FAKE_D" ;;
        *)       date "$@" ;;
    esac
}

B_CASES="
quarterly|1|2026|01|05|2026-01-01|2026-03-31
quarterly|1|2026|02|10|2026-01-01|2026-03-31
quarterly|1|2026|03|31|2026-01-01|2026-03-31
quarterly|1|2026|04|01|2026-04-01|2026-06-30
quarterly|15|2026|01|03|2025-10-15|2026-01-14
quarterly|15|2026|01|15|2026-01-15|2026-04-14
quarterly|15|2026|01|20|2026-01-15|2026-04-14
quarterly|15|2026|02|05|2026-01-15|2026-04-14
quarterly|15|2026|02|20|2026-01-15|2026-04-14
quarterly|15|2026|04|14|2026-01-15|2026-04-14
quarterly|15|2026|04|15|2026-04-15|2026-07-14
quarterly|15|2026|05|05|2026-04-15|2026-07-14
yearly|1|2026|01|05|2026-01-01|2026-12-31
yearly|1|2026|06|01|2026-01-01|2026-12-31
yearly|15|2026|01|03|2025-01-15|2026-01-14
yearly|15|2026|01|15|2026-01-15|2027-01-14
yearly|15|2026|06|05|2026-01-15|2027-01-14
monthly|15|2026|11|10|2026-10-15|2026-11-14
monthly|1|2026|11|17|2026-11-01|2026-11-30
monthly|8|2026|11|03|2026-10-08|2026-11-07
quarterly|31|2026|04|15|2026-01-31|2026-04-29
quarterly|31|2026|05|05|2026-04-30|2026-07-30
quarterly|30|2026|04|15|2026-01-30|2026-04-29
monthly|31|2026|02|10|2026-01-31|2026-02-27
monthly|31|2026|03|05|2026-02-28|2026-03-30
monthly|30|2026|02|10|2026-01-30|2026-02-27
"

while IFS='|' read -r p day y m d exp_s exp_e; do
    [ -n "$p" ] || continue
    TRAFFIC_PERIOD="$p"; PERIOD_START_DAY="$day"
    FAKE_Y="$y"; FAKE_M="$m"; FAKE_D="$d"
    got_s=$(get_period_start_date)
    got_e=$(get_period_end_date)
    today="$y-$m-$d"
    if [ "$got_s" = "$exp_s" ] && [ "$got_e" = "$exp_e" ]; then
        ok "B $p 起始日=$day 今天=$today → $got_s ~ $got_e"
    else
        no "B $p 起始日=$day 今天=$today → $got_s ~ $got_e（期望 $exp_s ~ $exp_e）"
    fi
    # 不变量①：今天必须落在 [起始日, 结束日] 内
    if [ ! "$today" \< "$got_s" ] && [ ! "$today" \> "$got_e" ]; then
        :
    else
        no "B $p 起始日=$day 今天 $today 不在窗口 $got_s ~ $got_e 内"
    fi
done <<< "$B_CASES"

# 不变量②：窗口长度等于一个周期（月 28~31 / 季 89~92 / 年 365~366）
TRAFFIC_PERIOD=quarterly; PERIOD_START_DAY=1; FAKE_Y=2026; FAKE_M=01; FAKE_D=05
len=$(( ( $(date -d "$(get_period_end_date)" +%s) - $(date -d "$(get_period_start_date)" +%s) ) / 86400 + 1 ))
[ "$len" -ge 89 ] && [ "$len" -le 92 ] && ok "B 季度窗口长度 $len 天（旧代码是 151 天）" \
    || no "B 季度窗口长度异常: $len 天"

TRAFFIC_PERIOD=yearly
len=$(( ( $(date -d "$(get_period_end_date)" +%s) - $(date -d "$(get_period_start_date)" +%s) ) / 86400 + 1 ))
[ "$len" -ge 365 ] && [ "$len" -le 366 ] && ok "B 年度窗口长度 $len 天（旧代码是 730 天）" \
    || no "B 年度窗口长度异常: $len 天"

# ============================================================
# C. 三个通知脚本：新周期按「事件」推送，且失败要能重试
# ============================================================
echo ""
echo "===== C. 新周期通知（事件驱动） ====="

# shellcheck disable=SC1091
. "$ROOT/log_helper.sh"

for notifier in tg_notifier.sh pushplus_notifier.sh serverchan_notifier.sh; do
    NSRC="$ROOT/$notifier"
    label="${notifier%%_notifier.sh}"

    if [ ! -f "$NSRC" ]; then
        echo "  [SKIP] $notifier 不存在"
        continue
    fi

    CASE="$TMP/c_$label"; mkdir -p "$CASE"
    extract_func "$NSRC" check_and_notify > "$CASE/notify.sh"
    grep -q "^check_and_notify() {" "$CASE/notify.sh" \
        || { no "$label 抽取 check_and_notify 失败"; continue; }
    # shellcheck disable=SC1090
    . "$CASE/notify.sh"

    WORK_DIR="$CASE"
    LOG_FILE="$CASE/traffic_monitor.log"
    CRON_LOG="$CASE/cron.log"
    LAST_NOTIFICATION_FILE="$CASE/last_traffic_notification"
    COUNT="$CASE/ok.count"
    FAILCOUNT="$CASE/fail.count"
    SEND_RC="$CASE/send.rc"

    # 桩：只计数，不真的发推送；SEND_RC 控制「发送成功/失败」
    send_new_cycle_notification() {
        if [ "$(cat "$SEND_RC" 2>/dev/null)" = "1" ]; then
            echo "new_cycle" >> "$FAILCOUNT"; return 1
        fi
        echo "new_cycle" >> "$COUNT"; return 0
    }
    send_throttle_warning()  { echo "throttle"  >> "$COUNT"; return 0; }
    send_throttle_lifted()   { echo "lifted"    >> "$COUNT"; return 0; }
    send_shutdown_warning()  { echo "shutdown"  >> "$COUNT"; return 0; }

    : > "$COUNT"; : > "$FAILCOUNT"; : > "$CRON_LOG"
    echo 0 > "$SEND_RC"

    # 真实的日志顺序：主脚本同一次运行里先写「新周期开始」，紧接着写「流量正常」
    {
        echo "2026-11-15 00:00:00 新的流量周期开始，重置限制"
        echo "2026-11-15 00:00:01 流量正常，清除所有限制"
    } > "$LOG_FILE"
    printf '2026-11-15\n' > "$CASE/.last_period_reset"

    # C1. 升级后第一次跑：静默登记当前周期，不补推历史周期
    for _ in $(seq 1 3); do check_and_notify >/dev/null 2>&1; done
    n=$(grep -c . "$COUNT" 2>/dev/null || true)
    [ "$n" = "0" ] && ok "$label C1 首次运行不补推历史周期" || no "$label C1 首次运行多推了 $n 条"

    # C2. 周期切换（日志里紧接着就有「正常」）：必须仍能推，且只推一次
    printf '2026-12-15\n' > "$CASE/.last_period_reset"
    echo "2026-12-15 00:00:00 新的流量周期开始，重置限制" >> "$LOG_FILE"
    echo "2026-12-15 00:00:01 流量正常，清除所有限制" >> "$LOG_FILE"
    for _ in $(seq 1 10); do check_and_notify >/dev/null 2>&1; done
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && ok "$label C2 新周期后紧跟「流量正常」也能推，且 10 轮只推 1 条" \
        || no "$label C2 新周期推送数 $n（期望 1）"

    # C3. 发送失败：不记标记，下一轮必须重试成功
    printf '2026-01-15\n' > "$CASE/.last_period_reset"
    echo 1 > "$SEND_RC"
    check_and_notify >/dev/null 2>&1
    m=$(grep -c "new_cycle" "$FAILCOUNT" 2>/dev/null || true)
    [ "$m" = "1" ] && ok "$label C3 发送失败时记录失败（未记为已通知）" \
        || no "$label C3 发送失败未走失败分支: $m"
    echo 0 > "$SEND_RC"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    [ "$n" = "2" ] && ok "$label C3 失败后下一轮自动重试并成功" \
        || no "$label C3 失败后未重试（成功数 $n，期望 2）"

    # C4. 两个周期之间没有任何「正常」日志（vnstat 整周期失败）也要能推
    printf '2026-02-15\n' > "$CASE/.last_period_reset"
    echo "2026-02-15 00:00:00 新的流量周期开始，重置限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    [ "$n" = "3" ] && ok "$label C4 中间没有「正常」日志时下个周期照常推送" \
        || no "$label C4 跨周期推送丢失（$n，期望 3）"

    # C5. 刚推过「新周期」时不要再重复推「限速解除」
    : > "$COUNT"
    printf '2026-02-15 10:00:00 限速\n' > "$LAST_NOTIFICATION_FILE"
    printf '2026-03-15\n' > "$CASE/.last_period_reset"
    echo "2026-03-15 00:00:00 新的流量周期开始，重置限制" >> "$LOG_FILE"
    echo "2026-03-15 00:00:01 流量正常，清除所有限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    m=$(grep -c "lifted"    "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && [ "$m" = "0" ] && ok "$label C5 新周期只推一条，不重复推解除限速" \
        || no "$label C5 新周期=$n 解限=$m（期望 1 / 0）"

    # C6. 限速 / 解限分支本身不受影响
    : > "$COUNT"
    printf '2026-03-16 10:00:00 正常\n' > "$LAST_NOTIFICATION_FILE"
    echo "2026-03-16 11:00:00 流量超出限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    echo "2026-03-16 12:00:00 流量正常，清除所有限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "throttle" "$COUNT" 2>/dev/null || true)
    m=$(grep -c "lifted"   "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && [ "$m" = "1" ] && ok "$label C6 限速/解限推送逻辑未受影响" \
        || no "$label C6 限速=$n 解限=$m（期望各 1）"
done


# C7. 两个渠道共用同一个 WORK_DIR、各自一份标记 → 谁都不该被对方「吃掉」
CASE="$TMP/c7"; mkdir -p "$CASE"
WORK_DIR="$CASE"
printf '2026-04-15\n' > "$CASE/.last_period_reset"
NEW_CYCLE_MARK_FILE="$CASE/.mark_a"; new_cycle_notify_pending >/dev/null 2>&1
NEW_CYCLE_MARK_FILE="$CASE/.mark_b"; new_cycle_notify_pending >/dev/null 2>&1
printf '2026-07-15\n' > "$CASE/.last_period_reset"
NEW_CYCLE_MARK_FILE="$CASE/.mark_a"; pa=$(new_cycle_notify_pending)
NEW_CYCLE_MARK_FILE="$CASE/.mark_b"; pb=$(new_cycle_notify_pending)
if [ "$pa" = "2026-07-15" ] && [ "$pb" = "2026-07-15" ]; then
    ok "C7 各渠道独立标记文件，互不影响"
else
    no "C7 渠道标记互相干扰（a=$pa b=$pb）"
fi

# ============================================================
# D. 语法检查
# ============================================================
echo ""
echo "===== D. 语法检查 ====="
for s in trafficcop.sh tg_notifier.sh serverchan_notifier.sh pushplus_notifier.sh log_helper.sh; do
    if [ -f "$ROOT/$s" ]; then
        bash -n "$ROOT/$s" 2>/dev/null && ok "$s 语法通过" || no "$s 语法错误"
    else
        echo "  [SKIP] $s 不在当前目录"
    fi
done

echo ""
echo "==================== 结果 ===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
