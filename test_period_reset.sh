#!/bin/bash
# ============================================================
# 验证：新周期提醒只发一次（issue #25）
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
#   ③ 三个通知脚本的「新周期」分支没有 last_status 判据，无条件发送。
#
# 本脚本覆盖 ①③ 的回归。② 属取数逻辑，需要 vnstat 环境，见 test_usage_window.sh。
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

# ============================================================
# A. check_reset_limit 必须按周期幂等（而不是按「日期命中」）
# ============================================================
echo ""
echo "===== A. 周期重置幂等 ====="

: > "$TMP/funcs.sh"
for fn in bj_date get_period_start_date check_reset_limit; do
    extract_func "$SRC" "$fn" >> "$TMP/funcs.sh"
    grep -q "^${fn}() {" "$TMP/funcs.sh" || { echo "抽取失败: $fn"; exit 1; }
done

# shellcheck disable=SC1090
source "$TMP/funcs.sh"

# tc 用桩替代（本机没有 tc，也不该真去动网卡）
TC_CALLS="$TMP/tc.calls"
tc() { echo "tc $*" >> "$TC_CALLS"; }

TRAFFIC_PERIOD="monthly"
# 让「今天」正好是周期起点 —— 与客户机器收到重复推送那天的状态一致
PERIOD_START_DAY="$(bj_date +%d)"
TODAY="$(bj_date +%Y-%m-%d)"
CUR_PERIOD="$(get_period_start_date)"
echo "  今天=$TODAY  本周期起点=$CUR_PERIOD"

# A1. 首次运行（没有标记文件）：只初始化，不发「新周期」
CASE="$TMP/a1"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
check_reset_limit >/dev/null 2>&1
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "0" ] && ok "A1 首次运行不伪造「新周期开始」日志" \
    || no "A1 首次运行就写了 $n_new 条新周期日志"
[ "$n_tc" = "1" ] && ok "A1 首次运行仍会清一次限速（残留 tc 规则）" \
    || no "A1 首次运行 tc del 次数异常: $n_tc"
[ "$(cat "$PERIOD_RESET_FILE" 2>/dev/null)" = "$CUR_PERIOD" ] \
    && ok "A1 已落盘本周期起点标记" || no "A1 标记文件内容不对"

# A2. 同一周期内反复运行：一条日志都不能多
CASE="$TMP/a2"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
printf '%s\n' "$CUR_PERIOD" > "$PERIOD_RESET_FILE"
for _ in $(seq 1 180); do check_reset_limit >/dev/null 2>&1; done
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "0" ] && ok "A2 同周期内跑 180 次（一天是 1440 次）不写任何新周期日志" \
    || no "A2 同周期内写了 $n_new 条新周期日志"
[ "$n_tc" = "0" ] && ok "A2 同周期内不重复执行 tc del" || no "A2 重复执行了 $n_tc 次 tc del"

# A3. 跨周期（含「重置日机器关机、几天后才开机」）：只动作一次、只写一条
CASE="$TMP/a3"; mkdir -p "$CASE"
WORK_DIR="$CASE"; LOG_FILE="$CASE/traffic_monitor.log"; MAIN_INTERFACE="eth0"
PERIOD_RESET_FILE="$CASE/.last_period_reset"; TC_CALLS="$CASE/tc.calls"
: > "$LOG_FILE"; : > "$TC_CALLS"
printf '2000-01-01\n' > "$PERIOD_RESET_FILE"
for _ in $(seq 1 180); do check_reset_limit >/dev/null 2>&1; done
n_new=$(grep -c "新的流量周期开始" "$LOG_FILE" 2>/dev/null || true)
n_tc=$(grep -c "qdisc del" "$TC_CALLS" 2>/dev/null || true)
[ "$n_new" = "1" ] && ok "A3 周期切换后只写 1 条新周期日志（旧实现是 180 条）" \
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
# B. 三个通知脚本：「新周期」状态变化才推送
# ============================================================
echo ""
echo "===== B. 通知去重（tg / pushplus / serverchan） ====="

# shellcheck disable=SC1091
. "$ROOT/log_helper.sh"

for notifier in tg_notifier.sh pushplus_notifier.sh serverchan_notifier.sh; do
    NSRC="$ROOT/$notifier"
    label="${notifier%%_notifier.sh}"

    if [ ! -f "$NSRC" ]; then
        echo "  [SKIP] $notifier 不存在"
        continue
    fi

    CASE="$TMP/b_$label"; mkdir -p "$CASE"
    extract_func "$NSRC" check_and_notify > "$CASE/notify.sh"
    grep -q "^check_and_notify() {" "$CASE/notify.sh" \
        || { no "$label 抽取 check_and_notify 失败"; continue; }
    # shellcheck disable=SC1090
    . "$CASE/notify.sh"

    WORK_DIR="$CASE"
    LOG_FILE="$CASE/traffic_monitor.log"
    CRON_LOG="$CASE/cron.log"
    LAST_NOTIFICATION_FILE="$CASE/last_traffic_notification"
    COUNT="$CASE/sent.count"

    # 桩：只计数，不真的发推送
    send_new_cycle_notification()  { echo "new_cycle"    >> "$COUNT"; }
    send_throttle_warning()        { echo "throttle"     >> "$COUNT"; }
    send_throttle_lifted()         { echo "lifted"       >> "$COUNT"; }
    send_shutdown_warning()        { echo "shutdown"     >> "$COUNT"; }

    # ---- B1. 日志里堆满「新周期开始」（客户现场的样子），只许推一次 ----
    : > "$COUNT"; : > "$CRON_LOG"
    {
        i=0
        while [ $i -lt 60 ]; do
            printf '2026-11-15 00:%02d:00 新的流量周期开始，重置限制\n' $i
            i=$((i + 1))
        done
    } > "$LOG_FILE"

    for _ in $(seq 1 60); do check_and_notify >/dev/null 2>&1; done
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && ok "$label 日志堆了 60 条「新周期」也只推 1 条（旧实现推 60 条）" \
        || no "$label 新周期推送了 $n 条"

    # ---- B2. 之后日志变成「流量正常」：不许再推任何东西 ----
    echo "2026-11-15 08:00:00 流量正常，清除所有限制" >> "$LOG_FILE"
    for _ in $(seq 1 5); do check_and_notify >/dev/null 2>&1; done
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    n_all=$(grep -c . "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && ok "$label 状态转为「正常」后不再推新周期" \
        || no "$label 转为正常后新周期推了 $n 条"
    [ "$n_all" = "1" ] && ok "$label 全程没有多余推送" || no "$label 总共推了 $n_all 条"

    # ---- B3. 下个周期再来一次：必须能正常推（去重不能把功能去没了） ----
    echo "2026-12-15 00:00:00 新的流量周期开始，重置限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "new_cycle" "$COUNT" 2>/dev/null || true)
    [ "$n" = "2" ] && ok "$label 下一个周期仍会正常推送一次" \
        || no "$label 新周期推送未恢复: $n"

    # ---- B4. 限速/解限分支不受影响 ----
    : > "$COUNT"
    echo "2026-12-16 10:00:00 流量超出限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    echo "2026-12-16 11:00:00 流量正常，清除所有限制" >> "$LOG_FILE"
    check_and_notify >/dev/null 2>&1
    n=$(grep -c "throttle" "$COUNT" 2>/dev/null || true)
    m=$(grep -c "lifted" "$COUNT" 2>/dev/null || true)
    [ "$n" = "1" ] && [ "$m" = "1" ] && ok "$label 限速/解限推送逻辑未受影响" \
        || no "$label 限速=$n 解限=$m（期望各 1）"
done

# ============================================================
# C. 语法检查
# ============================================================
echo ""
echo "===== C. 语法检查 ====="
for s in trafficcop.sh tg_notifier.sh serverchan_notifier.sh pushplus_notifier.sh; do
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
