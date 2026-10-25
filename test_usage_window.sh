#!/bin/bash
# ============================================================
# 验证：本周期用量按「vnstat 数据覆盖能力」选择累加粒度（issue #23）
# ------------------------------------------------------------
# 复现的客户现象：每日推送的「当前使用」一天比一天少。
# 根因：原实现固定用小时级数据（vnstat --json h）累加本周期，
#       而 vnstat 默认 HourlyDays=4，小时级只保留 4 天 →「本周期累计」
#       实际只是「最近 4 天」的滚动值，且限速阈值永远触发不了。
#
# 本脚本用合成 fixture 覆盖三种粒度（hour/day/month）、四种统计模式
# （in/out/total/max）、以及「同一周期内累计量不得下降」的兜底逻辑。
#
# 用法: bash test_usage_window.sh
# 依赖: bash / jq / bc / awk / date(GNU)
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
for t in jq bc awk; do
    command -v "$t" >/dev/null 2>&1 || { echo "缺少依赖: $t"; exit 1; }
done

TMP=$(mktemp -d 2>/dev/null || echo "./_usage_window_tmp")
mkdir -p "$TMP"
cd "$TMP" || exit 1

# 字节 → GB：与产品完全同一算法（bc scale=3 截断，不是四舍五入）
exp_gb() { echo "scale=3; $1/1073741824" | bc; }

# ------------------------------------------------------------
# 按函数名抽取 shell 函数体（大括号配对；不会被 heredoc 的 EOF 截断）
# ------------------------------------------------------------
extract_func() {
    awk -v fn="$1" '
        $0 ~ "^" fn "\\(\\) \\{" { on = 1 }
        on {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0 && seen) exit
            seen = 1
        }
    ' "$SRC"
}

: > funcs.sh
for fn in vnstat_db_created vnstat_first_date vnstat_sum_filter get_period_start_date \
          get_period_end_date get_traffic_usage bj_date state_field \
          apply_usage_high_water; do
    extract_func "$fn" >> funcs.sh
    grep -q "^${fn}() {" funcs.sh || { echo "抽取失败: $fn"; exit 1; }
done

# ------------------------------------------------------------
# fixture
#   日级: 每天 rx=1e9 tx=2e9（合计 3e9 字节）
#   小时级: 每天一条 rx=1e10 tx=2e10（10-22 ~ 10-25，模拟 vnstat 4 天窗口）
#   月级: 2026-10 的数值取自真机 159.138.7.126
# ------------------------------------------------------------
gen_day() { # $1=起始日 $2=天数（created 取起始日）
    local d="$1" n="$2" i=0 first=1 y mo da cy cm cd
    read -r cy cm cd <<<"$(date -d "$d" +"%Y %-m %-d" 2>/dev/null)"
    printf '{"interfaces":[{"id":"eth0","created":{"date":{"year":%d,"month":%d,"day":%d}},"traffic":{"day":[' \
        "$cy" "$cm" "$cd"
    while [ "$i" -lt "$n" ]; do
        read -r y mo da <<<"$(date -d "$d +$i day" +"%Y %-m %-d" 2>/dev/null)" || return 1
        [ "$first" = "1" ] || printf ','
        printf '{"date":{"year":%d,"month":%d,"day":%d},"rx":1000000000,"tx":2000000000}' \
            "$y" "$mo" "$da"
        first=0
        i=$((i + 1))
    done
    printf ']}}]}\n'
}

gen_hour() {
    printf '{"interfaces":[{"id":"eth0","created":{"date":{"year":2026,"month":8,"day":24}},"traffic":{"hour":['
    printf '{"date":{"year":2026,"month":10,"day":22},"rx":10000000000,"tx":20000000000},'
    printf '{"date":{"year":2026,"month":10,"day":23},"rx":10000000000,"tx":20000000000},'
    printf '{"date":{"year":2026,"month":10,"day":24},"rx":10000000000,"tx":20000000000},'
    printf '{"date":{"year":2026,"month":10,"day":25},"rx":10000000000,"tx":20000000000}'
    printf ']}}]}\n'
}

gen_month() { # $1..$3 = created 年月日（默认 2025-03-01）
    printf '{"interfaces":[{"id":"eth0","created":{"date":{"year":%d,"month":%d,"day":%d}},"traffic":{"month":[' \
        "${1:-2025}" "${2:-3}" "${3:-1}"
    printf '{"date":{"year":2025,"month":3},"rx":20440929290,"tx":15097694903},'
    printf '{"date":{"year":2026,"month":9},"rx":97436751130,"tx":45650022134},'
    printf '{"date":{"year":2026,"month":10},"rx":87396501773,"tx":32056375723}'
    printf ']}}]}\n'
}

gen_day 2026-08-24 63 > f_day_full.json    # 08-24 ~ 10-25，与真机保留范围一致
gen_day 2026-10-10 16 > f_day_short.json   # 只到 10-10，模拟日级也已滚出
gen_hour > f_hour.json
gen_month 2025 3 1 > f_month.json          # 数据库早就存在
gen_month 2026 10 20 > f_month_newdb.json  # 数据库 10-20 才建（周期中途）
printf '{"interfaces":[{"id":"eth0","traffic":{}}]}\n' > f_empty.json
: > f_none.json   # vnstat 完全无输出
for f in f_day_full.json f_day_short.json f_hour.json f_month.json f_month_newdb.json f_empty.json; do
    jq -e . "$f" >/dev/null 2>&1 || { echo "fixture 非法 JSON: $f"; exit 1; }
done

# ------------------------------------------------------------
# driver：把被测函数跑在受控环境里
# 「今天」冻结为 2026-10-25，让周期边界可预测（只拦截周期计算用到的格式）
# ------------------------------------------------------------
cat > driver.sh <<'DRV'
#!/bin/bash
set -u
cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./funcs.sh

date() {
    case "${1:-}" in
        +%Y) echo "2026" ;;
        +%m) echo "10" ;;
        +%d) echo "25" ;;
        +%z) echo "+0800" ;;
        *)   command date "$@" ;;
    esac
}

MAIN_INTERFACE="eth0"
HOST_TZ_WARNED=1
TRAFFIC_MODE="${TRAFFIC_MODE:-total}"
TRAFFIC_PERIOD="${TRAFFIC_PERIOD:-monthly}"
PERIOD_START_DAY="${PERIOD_START_DAY:-1}"
CONVERSION_BASE="${CONVERSION_BASE:-1024}"
WORK_DIR="."
STATE_FILE="./traffic_state.json"

vnstat() {
    case "$*" in
        *"--json h"*) cat "${F_HOUR:-f_empty.json}" ;;
        *"--json d"*) cat "${F_DAY:-f_empty.json}" ;;
        *"--json m"*) cat "${F_MONTH:-f_empty.json}" ;;
        *)            return 1 ;;
    esac
}
get_byte_divisor() {
    case "$CONVERSION_BASE" in
        1000) echo "1000000000" ;;
        *)    echo "1073741824" ;;
    esac
}

rm -f .traffic_usage_ok
out=$(get_traffic_usage 2>stderr.log)
rc=$?
echo "USAGE=$out"
echo "RC=$rc"
echo "FLAG=$(cat .traffic_usage_ok 2>/dev/null)"
DRV

cat > guard.sh <<'GRD'
#!/bin/bash
set -u
cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./funcs.sh
date() {
    case "${1:-}" in
        +%Y) echo "2026" ;;
        +%m) echo "10" ;;
        +%d) echo "25" ;;
        *)   command date "$@" ;;
    esac
}
TRAFFIC_PERIOD="monthly"
PERIOD_START_DAY=1
CONVERSION_BASE="${CONVERSION_BASE:-1024}"
TRAFFIC_MODE="${TRAFFIC_MODE:-total}"
MAIN_INTERFACE="${MAIN_INTERFACE:-eth0}"
WORK_DIR="."
STATE_FILE="./_st.json"
apply_usage_high_water "$1" 2>/dev/null
GRD

rm -f stderr.log
run_case() { # $1=标题  其余为 VAR=VAL
    local title="$1"
    shift
    rm -f stderr.log
    env "$@" bash ./driver.sh > out.txt 2>&1
    USAGE=$(grep '^USAGE=' out.txt | head -n1 | cut -d= -f2-)
    RC=$(grep '^RC=' out.txt | head -n1 | cut -d= -f2-)
    GRAN=$(grep -o '累加粒度: [^（]*' stderr.log 2>/dev/null | head -n1 | sed 's/累加粒度: //')
    FLAG=$(grep '^FLAG=' out.txt | head -n1 | cut -d= -f2-)
    echo "  · $title → usage=${USAGE:-?} 粒度=${GRAN:-?} rc=${RC:-?}"
}

echo "=== 1. 小时级覆盖周期起点时仍用小时级（精度优先） ==="
# 周期起点 = 10-25（今天），小时级最早 10-22 已覆盖 → 只累加 10-25 当天 3e10 字节
run_case "period 起点=10-25" F_HOUR=f_hour.json F_DAY=f_day_full.json F_MONTH=f_month.json \
    PERIOD_START_DAY=25 TRAFFIC_MODE=total
[ "$GRAN" = "小时级" ] && ok "选用小时级" || no "应选用小时级，实得: ${GRAN:-空}"
[ "$USAGE" = "$(exp_gb 30000000000)" ] && ok "小时级读数 = $(exp_gb 30000000000) GB" \
    || no "应为 $(exp_gb 30000000000) GB，实得 ${USAGE:-空}"

echo "=== 2. 核心回归：月度周期（起点 1 号）必须用日级，不能退化成「最近 4 天」 ==="
run_case "period 起点=10-01" F_HOUR=f_hour.json F_DAY=f_day_full.json F_MONTH=f_month.json \
    PERIOD_START_DAY=1 TRAFFIC_MODE=total
[ "$GRAN" = "日级" ] && ok "小时级覆盖不足 → 正确退到日级" || no "应退到日级，实得: ${GRAN:-空}"
# 10-01~10-25 共 25 天 × 3e9 = 75e9
[ "$USAGE" = "$(exp_gb 75000000000)" ] && ok "整月累计 = $(exp_gb 75000000000) GB（25 天）" \
    || no "应为 $(exp_gb 75000000000) GB，实得 ${USAGE:-空}"
# 小时级窗口值（4 天 = 1.2e11）绝不应出现
[ "$USAGE" != "$(exp_gb 120000000000)" ] && ok "未误用小时级窗口值（$(exp_gb 120000000000) GB）" \
    || no "仍在用小时级窗口值，bug 未修好"
[ "$FLAG" = "1" ] && ok "取数成功标记 = 1" || no "取数成功标记应为 1，实得 ${FLAG:-空}"

echo "=== 3. 日级也不覆盖时退到月级（季度/年度周期） ==="
run_case "日级只到 10-10" F_HOUR=f_hour.json F_DAY=f_day_short.json F_MONTH=f_month.json \
    PERIOD_START_DAY=1 TRAFFIC_MODE=total
[ "$GRAN" = "月级" ] && ok "日级不足 → 退到月级" || no "应退到月级，实得: ${GRAN:-空}"
MONTH_TOTAL=$((87396501773 + 32056375723))
[ "$USAGE" = "$(exp_gb $MONTH_TOTAL)" ] && ok "月级累计 = $(exp_gb $MONTH_TOTAL) GB（与真机 2026-10 一致）" \
    || no "应为 $(exp_gb $MONTH_TOTAL) GB，实得 ${USAGE:-空}"

echo "=== 3b. 月级数据存在、但数据库建于周期中途 → 必须标不完整 ==="
run_case "库建于 10-20" F_HOUR=f_hour.json F_DAY=f_day_short.json F_MONTH=f_month_newdb.json \
    PERIOD_START_DAY=1 TRAFFIC_MODE=total
echo "$GRAN" | grep -q "^月级" && ok "仍用月级（数据比日级多）" || no "应仍用月级，实得: ${GRAN:-空}"
echo "$GRAN" | grep -q "不完整" && ok "标注为「月级(不完整)」" || no "库建于中途必须标注不完整，实得: ${GRAN:-空}"
grep -q "数据库创建于 20261020" stderr.log 2>/dev/null \
    && ok "日志点明数据库创建日期" || no "缺少数据库创建日期的告警"

echo "=== 4. 三种粒度都不覆盖周期起点 → 日级 + 明确告警不完整 ==="
run_case "月级也不覆盖" F_HOUR=f_hour.json F_DAY=f_day_short.json F_MONTH=f_empty.json \
    PERIOD_START_DAY=1 TRAFFIC_MODE=total
echo "$GRAN" | grep -q "不完整" && ok "标注为「日级(不完整)」" || no "应标注不完整，实得: ${GRAN:-空}"
grep -q "缺少 .* 以来的完整数据" stderr.log 2>/dev/null \
    && ok "日志明确告警数据不完整" || no "缺少数据不完整告警"
# 10-10~10-25 共 16 天 × 3e9 = 48e9
[ "$USAGE" = "$(exp_gb 48000000000)" ] && ok "只累加有记录的时段 = $(exp_gb 48000000000) GB" \
    || no "应为 $(exp_gb 48000000000) GB，实得 ${USAGE:-空}"

echo "=== 5. vnstat 取不到数据 → 0.000 且返回非 0 ==="
check_nodata() { # $1=说明  $2..=fixture
    local title="$1"
    shift
    rm -f stderr.log
    env "$@" PERIOD_START_DAY=1 bash ./driver.sh > out.txt 2>&1
    USAGE=$(grep '^USAGE=' out.txt | head -n1 | cut -d= -f2-)
    RC=$(grep '^RC=' out.txt | head -n1 | cut -d= -f2-)
    FLAG=$(grep '^FLAG=' out.txt | head -n1 | cut -d= -f2-)
    [ "$USAGE" = "0.000" ] && ok "$title: 回显 0.000" || no "$title: 应回显 0.000，实得 ${USAGE:-空}"
    [ "$RC" != "0" ] && ok "$title: 返回非 0（rc=$RC）" || no "$title: 应返回非 0"
    grep -q "无法获取 vnstat JSON 数据" stderr.log 2>/dev/null \
        && ok "$title: 日志给出取数失败原因" || no "$title: 缺少取数失败日志"
    grep -q "缺少 .* 以来的完整数据" stderr.log 2>/dev/null \
        && no "$title: 无数据时不应再报「数据不完整」（提示矛盾）" \
        || ok "$title: 无数据时不报「不完整」，提示不矛盾"
    [ "$FLAG" = "0" ] && ok "$title: 取数成功标记 = 0（调用方据此跳过限速判断）" \
        || no "$title: 取数成功标记应为 0，实得 ${FLAG:-空}"
}
check_nodata "vnstat 无输出" F_HOUR=f_none.json F_DAY=f_none.json F_MONTH=f_none.json
check_nodata "traffic 对象为空" F_HOUR=f_empty.json F_DAY=f_empty.json F_MONTH=f_empty.json

echo "=== 6. 四种统计模式（in / out / total / max） ==="
case_mode() { # $1=mode $2=期望字节
    run_case "mode=$1" F_HOUR=f_hour.json F_DAY=f_day_full.json F_MONTH=f_month.json \
        PERIOD_START_DAY=1 TRAFFIC_MODE="$1"
    [ "$USAGE" = "$(exp_gb "$2")" ] && ok "mode=$1 → $(exp_gb "$2") GB" \
        || no "mode=$1 应为 $(exp_gb "$2") GB，实得 ${USAGE:-空}"
}
case_mode in 25000000000       # rx 25 天
case_mode out 50000000000      # tx 25 天
case_mode total 75000000000    # rx+tx
case_mode max 50000000000      # max(rx, tx)

echo "=== 7. 累计量兜底：同一周期内不取下降值 ==="
CUR_PERIOD="2026-10-01"
mk_state() { # $1=usage $2=base $3=period $4=mode $5=iface
    cat > _st.json <<EOF
{"usage_gb":$1,"conversion_base":$2,"period_start":"$3","traffic_mode":"$4","main_interface":"$5"}
EOF
}
guard_case() { # $1=prev $2=new $3=期望 $4=说明 [$5=base] [$6=period] [$7=mode] [$8=iface]
    mk_state "$1" "${5:-1024}" "${6:-$CUR_PERIOD}" "${7:-total}" "${8:-eth0}"
    local got
    got=$(bash ./guard.sh "$2")
    rm -f _st.json
    [ "$got" = "$3" ] && ok "$4 → $3" || no "$4 应为 $3，实得 ${got:-空}"
}
guard_case 30.000 20.000 30.000 "读数下降 → 沿用旧值"
guard_case 30.000 35.000 35.000 "读数上升 → 采用新值"
guard_case 30.000 5.000 5.000 "骤降过半（疑似库重建）→ 采用新值"
guard_case 15.000 14.995 15.000 "舍入级微降 → 视为未下降"
guard_case 30.000 0.000 30.000 "读到 0（疑似取数失败）→ 沿用旧值"
guard_case 30.000 20.000 20.000 "计费周期变化 → 采用新值" 1024 "1999-01-01"
guard_case 30.000 20.000 20.000 "换算进制变化 → 采用新值" 1000
guard_case 30.000 20.000 20.000 "统计模式变化（total→out）→ 采用新值" 1024 "$CUR_PERIOD" "out"
guard_case 30.000 20.000 20.000 "监控网卡变化 → 采用新值" 1024 "$CUR_PERIOD" "total" "eth1"
rm -f _st.json
got=$(bash ./guard.sh 20.000)
[ "$got" = "20.000" ] && ok "无快照 → 采用新值" || no "无快照应为 20.000，实得 ${got:-空}"

echo "=== 8. 静态检查 ==="
grep -q 'vnstat_first_date' "$SRC" && ok "已按数据覆盖情况选粒度" || no "未找到 vnstat_first_date"
grep -q 'use_hourly' "$SRC" && no "仍存在无条件优先小时级的旧逻辑" || ok "旧的小时级硬编码逻辑已移除"
grep -q 'apply_usage_high_water' "$SRC" && ok "已实现累计量兜底" || no "未实现累计量兜底"
grep -q '"traffic_mode"' "$SRC" && ok "快照记录了统计模式（口径变化时不再沿用）" || no "快照未记录 traffic_mode"
grep -q '"main_interface"' "$SRC" && ok "快照记录了监控网卡" || no "快照未记录 main_interface"
grep -q 'vnstat_db_created' "$SRC" && ok "已用建库日期兜底月级完整性" || no "缺少 vnstat_db_created"
grep -q 'USAGE_FLAG_FILE' "$SRC" && ok "取数失败有标记文件" || no "缺少取数标记"
grep -q 'current_usage=$(apply_usage_high_water' "$SRC" && ok "check_and_limit_traffic 已调用兜底" \
    || no "check_and_limit_traffic 未调用兜底"
grep -q '^SCRIPT_VERSION="1.0.93"' "$SRC" && ok "版本号 1.0.93" || no "版本号未更新"
grep -q 'SCRIPT_VERSION:-1.0.92' "$SRC" && no "快照里的版本回退值仍是 1.0.92" || ok "快照版本回退值已同步"

line="2026-10-25 20:00:00 当前使用流量: 69.849 GB，限制流量: 1004 GB"
u=$(echo "$line" | grep -oP '当前使用流量:\s*\K[0-9.]+ [GBMKgbmk]+' 2>/dev/null)
l=$(echo "$line" | grep -oP '限制流量:\s*\K[0-9.]+ [GBMKgbmk]+' 2>/dev/null)
[ "$u" = "69.849 GB" ] && [ "$l" = "1004 GB" ] && ok "日志行仍可被通知脚本解析" \
    || no "日志行解析失败: u=$u l=$l"

for s in trafficcop.sh tg_notifier.sh serverchan_notifier.sh pushplus_notifier.sh; do
    if [ -f "$ROOT/$s" ]; then
        bash -n "$ROOT/$s" 2>/dev/null && ok "$s 语法通过" || no "$s 语法错误"
    else
        echo "  [SKIP] $s 不在当前目录，跳过语法检查"
    fi
done

echo ""
echo "==================== 结果 ===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
