#!/bin/bash

# ============================================================
# crontab 安全读写（共享函数库）
# ------------------------------------------------------------
# 由 trafficcop.sh / machine_limit_manager.sh / port_traffic_limit.sh /
# trafficcop-manager.sh / tg_notifier.sh / pushplus_notifier.sh /
# serverchan_notifier.sh 共同 source。
#
# ------------------------------------------------------------
# 为什么需要这个库：旧写法会静默清空客户的整个 crontab
# ------------------------------------------------------------
# 旧写法是「先删后加」两步：
#     crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
#     (crontab -l 2>/dev/null; echo "新任务") | crontab -
#
# 三个致命问题（均在客户机上实测复现）：
#
#   1. **两步之间失败就永久丢失**。磁盘满、crontab 锁、脚本被中断 ——
#      任何一种都会让 cron 停在「已删除且没加回」的中间态，
#      而这个状态没有任何备份可以恢复。
#
#   2. **第 2 步失败会清空整个 crontab**。`crontab -` 从 stdin 读，
#      上游失败时收到的是**空输入**，真 cron 会把 crontab 写成 0 字节 ——
#      客户自己的其他定时任务（备份、清理等）一起消失。
#
#   3. **第 1 步本身就不安全**。实测 `(crontab -l | grep -v X) | crontab -`
#      执行后 crontab 直接变空：管道右侧与左侧存在竞态，
#      且 `grep -v` 里的 `.` 是正则通配而不是字面量。
#
# 本库的三个函数把「读-改-写」收敛成一次原子操作，
# 并强制要求「写完回读校验」，杜绝静默失败。
#
# ------------------------------------------------------------
# 依赖：调用方需要提供
#   $WORK_DIR    —— 可写目录，用于临时文件与备份
#   $LOG_FILE    —— 可选的日志文件，传入则记录变更（可为 /dev/null）
#   $SCRIPT_TAG  —— 用于识别「本项目自己的任务行」，避免误删他人任务
# ============================================================

# 内部：把一条消息同时写到日志和标准输出（没有 LOG_FILE 时静默跳过）
_cron_log() {
    [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ] && \
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
    return 0
}

# 内部：读当前 crontab。空 crontab 时 `crontab -l` 退出码是 1，属于正常。
_cron_read() {
    crontab -l 2>/dev/null || true
}

# ------------------------------------------------------------
# cron_task_present <模式>
#   任务行是否存在。返回 0=存在，1=不存在。
# ------------------------------------------------------------
cron_task_present() {
    _cron_read | grep -qE -- "$1"
}

# ------------------------------------------------------------
# cron_replace_tasks <移除匹配的正则> [追加的行...]
#   把「含指定模式的所有行」替换成给定的新行；模式匹配的旧行全部删除。
#   一次原子写入，带备份、回滚和回读校验。
#
#   用法：
#     cron_replace_tasks "trafficcop\.sh" "* * * * * /root/TrafficCop/trafficcop.sh --run"
#     cron_replace_tasks "tg_notifier\.sh"      # 只删不加
#
#   特性：
#     - 全程内存组装，只调用一次 crontab <file>，不用 crontab - 读 stdin；
#     - 写前备份，失败或校验不过自动回滚；
#     - 写完回读校验，确认真生效才返回 0；
#     - 保留所有与模式不匹配的行（客户的其他任务）。
#
#   返回：0 成功；1 失败（已尽力回滚）
# ------------------------------------------------------------
cron_replace_tasks() {
    local remove_pattern="$1"; shift
    local add_lines=("$@")

    local wd="${WORK_DIR:-/tmp}"
    local tmp_file="$wd/.crontab.tmp.$$"
    local backup_file="$wd/.crontab.bak.$$"
    local log_file="${LOG_FILE:-/dev/null}"
    local backup_log="$wd/.crontab.prev.$$"
    local current

    [ -d "$wd" ] || mkdir -p "$wd" 2>/dev/null

    # 读当前 crontab。空 crontab 时 `crontab -l` 退出码是 1，属正常。
    local current
    current=$(_cron_read)

    # 备份原始内容（回滚依据，也留一份给人看）
    # ⚠️ 必须先确认备份写成功才能继续。磁盘满 / 只读挂载 / 权限异常时
    #    备份会静默失败（2>/dev/null 吞掉了错误），此时若还往下走，
    #    一旦后面 `crontab -r` 删空客户 crontab 就**没有任何东西可回滚**。
    #    （CodeRabbit 指出，已按此加固）
    if ! printf '%s\n' "$current" > "$backup_log" 2>/dev/null; then
        _cron_log "cron: 备份写入失败（磁盘满或目录不可写），已放弃修改"
        rm -f "$backup_log" 2>/dev/null
        return 1
    fi

    # ---- 内存里组装新内容，完全不碰 crontab ----
    # 用 grep -F 风格的字面匹配时手动转义；此处统一交给调用方给正则，
    # 但额外去掉空行，避免累积出一堆空行。
    new_content=$(printf '%s\n' "$current" \
        | grep -vE -- "$remove_pattern" \
        | grep -v '^[[:space:]]*$')

    # 在**内存里**拼好完整内容，再一次性落盘。
    # 早前一版用 `{ ...; } > "$tmp_file"` 直接重定向：磁盘满时重定向失败，
    # 产生一个空文件，而空文件又会被后面的 `[ ! -s ]` 当成「有意的删空」，
    # 从而执行 crontab -r 把客户任务全删掉。现在先拼字符串、写成功再判断。
    local final_content="$new_content"
    local line
    for line in "${add_lines[@]}"; do
        [ -n "$line" ] || continue
        if [ -n "$final_content" ]; then
            final_content="$final_content
$line"
        else
            final_content="$line"
        fi
    done

    # 落盘。两种情形都要确认写成功：
    #   - 有内容 -> 写文件
    #   - 无内容 -> 只需创建空文件（后续走「有意的删空」分支）
    if [ -n "$final_content" ]; then
        if ! printf '%s\n' "$final_content" > "$tmp_file" 2>/dev/null; then
            _cron_log "cron: 临时文件写入失败（磁盘满或目录不可写），已放弃修改"
            rm -f "$tmp_file" "$backup_log" 2>/dev/null
            return 1
        fi
    elif ! : > "$tmp_file" 2>/dev/null; then
        _cron_log "cron: 临时文件创建失败（磁盘满或目录不可写），已放弃修改"
        rm -f "$tmp_file" "$backup_log" 2>/dev/null
        return 1
    fi

    if [ ! -s "$tmp_file" ]; then
        # ⚠️ 这里要区分两种「空」，二者性质完全不同（CodeRabbit 指出，已实测确认）：
        #
        #   (a) **有意的删除**：原内容里确实有匹配行，且调用方没要求补任何行。
        #       例如 stop_all_services 在「crontab 只有 TrafficCop 任务」的机器上
        #       删除自己 —— 这时过滤后为空是**正确结果**，必须放行。
        #       早前一版把它当成危险情况一律拒绝，导致 stop_all_services /
        #       remove_cron_job / 禁用定时任务在这些机器上永远失败。
        #
        #   (b) **意外的清空**：读取失败拿到空内容，或原内容里压根没有匹配行，
        #       却写了个空 —— 这才是旧写法 `| crontab -` 造成客户任务消失的真凶。
        #       这种情况必须拒绝。
        #
        # 判据：原内容非空 **且** 确实匹配得上要删的模式 -> (a)，允许删空。
        if [ "${#add_lines[@]}" -eq 0 ]; then
            rm -f "$tmp_file" 2>/dev/null
            if [ -n "$current" ] && printf '%s\n' "$current" | grep -qE -- "$remove_pattern"; then
                # 有意删空：用 crontab -r（真 cron 的删除命令），并回读确认
                if crontab -r 2>/dev/null && [ -z "$(_cron_read)" ]; then
                    _cron_log "cron: 已删除本项目全部任务（crontab 无其他任务）"
                    rm -f "$backup_log" 2>/dev/null
                    return 0
                fi
                # 删空失败：回滚，绝不留下半成品
                _cron_log "cron: 删除全部任务失败，正在回滚"
                [ -s "$backup_log" ] && crontab "$backup_log" 2>/dev/null
                rm -f "$backup_log" 2>/dev/null
                return 1
            fi
            # (b) 没有匹配行却得到空内容 —— 说明读取异常，拒绝写入
            _cron_log "cron: 新内容为空且无匹配行，已放弃写入（避免误清空）"
            rm -f "$backup_log" 2>/dev/null
            return 1
        fi
    fi

    # ---- 原子写入：整个 crontab 只写这一次 ----
    if ! crontab "$tmp_file" 2>/dev/null; then
        _cron_log "cron: 写入 crontab 失败，尝试回滚"
        if [ -s "$backup_file" ]; then
            crontab "$backup_file" 2>/dev/null
        elif [ -s "$backup_log" ]; then
            crontab "$backup_log" 2>/dev/null
        fi
        rm -f "$tmp_file" "$backup_file" "$backup_log" 2>/dev/null
        return 1
    fi

    # ---- 回读校验：写进去不等于生效 ----
    #
    # ⚠️ 这里**不能**校验「remove_pattern 已彻底消失」：
    #    替换任务的语义是「删掉旧行、补上新行」，而新任务行本身就
    #    指向同一个脚本（如 trafficcop.sh），必然再次匹配该模式。
    #    那样校验会永远失败并触发无谓回滚。
    #
    # 正确的判据是：
    #   1) crontab 读出来非空（没被写空）；
    #   2) 每一条要求新增的行都确实在（用 grep -F 字面匹配，避免正则误判）。
    local ok=1
    local after
    after=$(_cron_read)

    if [ -z "$after" ]; then
        ok=0
        _cron_log "cron: 校验失败——crontab 被写成空"
    fi

    local line
    for line in "${add_lines[@]}"; do
        [ -n "$line" ] || continue
        if ! printf '%s\n' "$after" | grep -qF -- "$line"; then
            ok=0
            _cron_log "cron: 校验失败——新增任务未生效"
            break
        fi
    done

    # 补一个「旧任务没有残留重复项」的检查：
    # 同一模式不应该出现多行（去重后应与新增的行数一致）。
    if [ -n "$remove_pattern" ] && [ "${#add_lines[@]}" -gt 0 ]; then
        local matched
        matched=$(printf '%s\n' "$after" | grep -cE -- "$remove_pattern")
        if [ "$matched" -gt "${#add_lines[@]}" ]; then
            ok=0
            _cron_log "cron: 校验失败——仍有 $matched 行匹配，期望不超过 ${#add_lines[@]}"
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        _cron_log "cron: crontab 已更新"
        rm -f "$tmp_file" "$backup_file" "$backup_log" 2>/dev/null
        return 0
    fi

    # ---- 校验不过：回滚 ----
    _cron_log "cron: 校验未通过，正在回滚"
    if [ -s "$backup_log" ]; then
        crontab "$backup_log" 2>/dev/null
    fi
    rm -f "$tmp_file" "$backup_file" "$backup_log" 2>/dev/null
    return 1
}

# ------------------------------------------------------------
# cron_remove_tasks <移除匹配的正则>
#   便捷封装：只删不加。语义等价于 cron_replace_tasks <正则>
#   （底层在「删完不加」时若新内容为空会拒绝写入，
#     这里的场景是 crontab 里除本项目任务外还有别的东西，通常非空）
# ------------------------------------------------------------
cron_remove_tasks() {
    cron_replace_tasks "$1"
}

# ------------------------------------------------------------
# cron_service_alive
#   cron 守护进程是否在运行。返回 0=在跑，1=没跑或检测不到
# ------------------------------------------------------------
cron_service_alive() {
    pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1
}

# ------------------------------------------------------------
# cron_ensure_service
#   cron 没跑时尝试拉起（Debian 系 / RHEL 系 / 精简系统三种方式）。
#   返回 0=已确保在跑，1=尝试过但失败
# ------------------------------------------------------------
cron_ensure_service() {
    cron_service_alive && return 0

    if command -v systemctl >/dev/null 2>&1; then
        systemctl start cron 2>/dev/null
        systemctl is-active cron >/dev/null 2>&1 && return 0
    fi
    service crond start 2>/dev/null
    cron_service_alive && return 0
    cron 2>/dev/null            # 有些精简系统只能直接跑守护进程
    cron_service_alive && return 0
    return 1
}
