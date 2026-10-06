#!/bin/bash
# ============================================================
# TrafficCop 定时任务诊断与修复
# ------------------------------------------------------------
# 用途：客户机 cron 丢失 / 不生效时，在机器上跑一次本脚本即可诊断并修复。
#
# 背景：客户机上出现过「日志里两次出现『定时任务未找到』」+「流量数字停在旧值」。
# 根因排查后确认脚本自身有两个缺陷会让 cron 静默丢失（已在 1.0.91 修复）：
#   1. setup_crontab() 是「先删后加」两步，中间失败会留下「删了没加回」的中间态；
#      第 2 步失败时 `crontab -` 收到空输入会**清空整个 crontab**，
#      连客户自己的其他定时任务一起丢。
#   2. 只检查「crontab 里有没有那行任务」，无法发现
#      「任务在、但 cron 服务没跑」—— 症状一样是日志不更新。
#
# 用法：
#   bash fix_crontab.sh            # 诊断 + 自动修复
#   bash fix_crontab.sh --check    # 只诊断，不做任何修改
# ============================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORK_DIR="/root/TrafficCop"
SCRIPT_PATH="$WORK_DIR/trafficcop.sh"
LOG_FILE="$WORK_DIR/traffic_monitor.log"

CHECK_ONLY=no
[ "$1" = "--check" ] && CHECK_ONLY=yes

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'

say()  { echo "$*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*"; }

say "=============================================="
say " TrafficCop 定时任务诊断"
say "=============================================="
say ""

PROBLEMS=0
FIXED=0

# ------------------------------------------------------------
# 检查 1：脚本本身是否在
# ------------------------------------------------------------
say "--- 1. 脚本文件 ---"
if [ -f "$SCRIPT_PATH" ]; then
    ok "主脚本存在: $SCRIPT_PATH"
    if [ -x "$SCRIPT_PATH" ]; then
        ok "主脚本可执行"
    else
        warn "主脚本没有执行权限"
        if [ "$CHECK_ONLY" = no ]; then
            chmod +x "$SCRIPT_PATH" && ok "已补上执行权限" || err "补权限失败"
        fi
    fi
    # 版本号（用于判断是否需要更新到含修复的版本）
    ver=$(grep -oE '^SCRIPT_VERSION="[^"]+"' "$SCRIPT_PATH" 2>/dev/null | head -1 | sed 's/.*="//; s/"//')
    say "     版本: ${ver:-未知}"
    case "$ver" in
        1.0.91|1.0.92|1.0.9[3-9]|1.[1-9].*)
            ok "版本已包含 cron 修复"
            ;;
        *)
            warn "版本可能不含 cron 修复（需 1.0.91+），建议更新主脚本"
            ;;
    esac
else
    err "主脚本不存在: $SCRIPT_PATH"
    say "     请先重新安装 TrafficCop 主脚本"
    PROBLEMS=$((PROBLEMS+1))
fi
say ""

# ------------------------------------------------------------
# 检查 2：crontab 里有没有任务
# ------------------------------------------------------------
say "--- 2. crontab 任务 ---"
CRON_CONTENT=$(crontab -l 2>/dev/null)
if echo "$CRON_CONTENT" | grep -q "$SCRIPT_PATH --run"; then
    ok "定时任务已存在于 crontab"
    say "     $(echo "$CRON_CONTENT" | grep "$SCRIPT_PATH --run")"
else
    warn "定时任务未找到（这正是客户机上的现象）"
    PROBLEMS=$((PROBLEMS+1))
    if [ "$CHECK_ONLY" = no ]; then
        # ---- 原子修复：一次写入，全程备份 ----
        BACKUP="$WORK_DIR/crontab.backup.manual.$$"
        TMPF="$WORK_DIR/crontab.tmp.$$"
        printf '%s\n' "$CRON_CONTENT" > "$BACKUP" 2>/dev/null

        # 组装：保留原有任务 + 追加本脚本任务
        NEW=$(printf '%s\n' "$CRON_CONTENT" | grep -v -e "$SCRIPT_PATH" -e 'traffic_monitor\.sh' | grep -v '^[[:space:]]*$')
        {
            [ -n "$NEW" ] && printf '%s\n' "$NEW"
            echo "* * * * * $SCRIPT_PATH --run"
        } > "$TMPF"

        if crontab "$TMPF" 2>/dev/null; then
            # 回读校验
            if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --run"; then
                ok "定时任务已修复（每分钟一次）"
                FIXED=$((FIXED+1))
            else
                err "写入后校验未通过，正在回滚"
                [ -s "$BACKUP" ] && crontab "$BACKUP" 2>/dev/null
            fi
        else
            err "写入 crontab 失败"
            if [ -s "$BACKUP" ]; then
                crontab "$BACKUP" 2>/dev/null && ok "已回滚到原 crontab"
            fi
        fi
        rm -f "$TMPF" "$BACKUP" 2>/dev/null
    fi
fi
say ""

# ------------------------------------------------------------
# 检查 3：cron 服务是否在跑
# ------------------------------------------------------------
say "--- 3. cron 服务状态 ---"
if pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1; then
    ok "cron 服务正在运行"
else
    warn "cron 服务未运行（任务存在也不会执行）"
    PROBLEMS=$((PROBLEMS+1))
    if [ "$CHECK_ONLY" = no ]; then
        started=no
        command -v systemctl >/dev/null 2>&1 && { systemctl start cron 2>/dev/null; }
        if pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1; then
            started=yes
        else
            service crond start 2>/dev/null
            pgrep -x crond >/dev/null 2>&1 && started=yes
        fi
        if [ "$started" = yes ]; then
            ok "cron 服务已启动"
            FIXED=$((FIXED+1))
        else
            err "自动启动失败，请手动执行：systemctl start cron（或 service crond start）"
        fi
    fi
fi
say ""

# ------------------------------------------------------------
# 检查 4：crontab 是否为空（曾被误清空的痕迹）
# ------------------------------------------------------------
say "--- 4. 其他定时任务 ---"
OTHER=$(printf '%s\n' "$CRON_CONTENT" | grep -v -e "$SCRIPT_PATH" -e 'traffic_monitor\.sh' | grep -v '^[[:space:]]*$' | grep -v '^#')
if [ -n "$OTHER" ]; then
    ok "还存在其他定时任务："
    printf '%s\n' "$OTHER" | while read -r l; do say "       $l"; done
else
    warn "crontab 里没有其他任务。"
    say "     如果这台机器原本有其他定时任务（备份、清理等），"
    say "     说明曾被旧版脚本的「先删后加」逻辑误清空 ——"
    say "     那种情况下只能手工补回，本脚本无法自动恢复。"
fi
say ""

# ------------------------------------------------------------
# 检查 5：日志最近更新时间（判断是否真的在跑）
# ------------------------------------------------------------
say "--- 5. 日志活跃度 ---"
if [ -f "$LOG_FILE" ]; then
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || stat -f %m "$LOG_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$(( NOW - LOG_MTIME ))
    say "     日志最后更新: $(date -d "@$LOG_MTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$LOG_MTIME")"
    say "     距今: $(( AGE / 60 )) 分钟"
    if [ "$AGE" -gt 600 ]; then
        warn "日志已 $(( AGE / 60 )) 分钟没有更新，脚本实际没在运行"
        PROBLEMS=$((PROBLEMS+1))
    else
        ok "日志在正常更新"
    fi
else
    warn "日志文件不存在: $LOG_FILE"
fi
say ""

# ------------------------------------------------------------
# 汇总
# ------------------------------------------------------------
say "=============================================="
if [ "$PROBLEMS" -eq 0 ]; then
    say -e "${GREEN}诊断结果：一切正常，无需处理${NC}"
else
    say -e "${YELLOW}发现 $PROBLEMS 个问题${NC}"
    [ "$CHECK_ONLY" = yes ] && say "（当前是 --check 模式，未做任何修改）"
    [ "$FIXED" -gt 0 ] && say -e "${GREEN}已自动修复 $FIXED 项${NC}"
fi
say "=============================================="

[ "$PROBLEMS" -gt 0 ] && [ "$FIXED" -eq 0 ] && exit 1
exit 0
