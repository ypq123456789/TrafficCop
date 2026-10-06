#!/bin/bash
# ============================================================
# 一键创建 R2 桶 + 生命周期规则
# ============================================================
# 前置：已安装 wrangler 并登录（npx wrangler login）
#
# 用法：
#   bash setup-r2.sh
#   bash setup-r2.sh --retention-days 90
#
# ⚠️ 桶名固定为 trafficcop-logs，与 wrangler.toml 里 LOGS 的
#    bucket_name 必须一致，因此**不提供 --bucket 选项**。
#    如需换桶名，请同时改 wrangler.toml，否则 Worker 会绑定到
#    一个不存在（或另一个）的桶上，部署后写入全部失败。
# ============================================================
set -euo pipefail

BUCKET="trafficcop-logs"
RETENTION_DAYS=90

while [ $# -gt 0 ]; do
    case "$1" in
        --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
        --bucket)
            echo "错误：不支持 --bucket。" >&2
            echo "      桶名必须与 wrangler.toml 中 LOGS 的 bucket_name 一致（$BUCKET）。" >&2
            echo "      若要换桶名，请同时修改 wrangler.toml 后再重新部署 Worker。" >&2
            exit 1
            ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

# 与 wrangler.toml 交叉校验：两边桶名不一致时直接失败，避免部署出一个写不进数据的 Worker
WRANGLER_TOML="$(dirname "$0")/wrangler.toml"
if [ -f "$WRANGLER_TOML" ]; then
    toml_bucket=$(grep -E '^\s*bucket_name\s*=' "$WRANGLER_TOML" | tail -n1 | sed 's/.*=\s*//; s/"//g; s/[[:space:]]*$//')
    if [ -n "$toml_bucket" ] && [ "$toml_bucket" != "$BUCKET" ]; then
        echo "错误：桶名不一致。" >&2
        echo "      setup-r2.sh 使用: $BUCKET" >&2
        echo "      wrangler.toml  : $toml_bucket" >&2
        echo "      两者必须相同，否则 Worker 会绑定到错误的桶。" >&2
        exit 1
    fi
fi

echo "=== TrafficCop R2 日志桶初始化 ==="
echo "桶名: $BUCKET"
echo "保留天数: $RETENTION_DAYS"
echo ""

# 1) 建桶（已存在则跳过）
echo "[1/3] 创建 R2 桶..."
if npx wrangler r2 bucket list 2>/dev/null | grep -q "\"$BUCKET\"\| $BUCKET "; then
    echo "  桶 $BUCKET 已存在，跳过"
else
    npx wrangler r2 bucket create "$BUCKET"
    echo "  已创建"
fi

# 2) 生命周期规则：自动清理过期日志
#    这是解决「日志无限增长」的正解（生产机已出现过 150MB 日志）
#
# ⚠️ 规则名与前缀是**位置参数**，不是 --name / --prefix。
#    正确用法：wrangler r2 bucket lifecycle add <bucket> [name] [prefix]
#    用 --name/--prefix 会报未知参数，规则根本加不上，
#    进而导致日志桶没有过期策略、存储无限增长。
echo ""
echo "[2/3] 添加生命周期规则（${RETENTION_DAYS} 天自动过期）..."
RULE_NAME="expire-logs-${RETENTION_DAYS}d"

if npx wrangler r2 bucket lifecycle list "$BUCKET" 2>/dev/null | grep -q "$RULE_NAME"; then
    echo "  规则 $RULE_NAME 已存在，跳过"
else
    # 失败必须让脚本失败（不再用 || echo 无条件吞掉）
    if npx wrangler r2 bucket lifecycle add "$BUCKET" "$RULE_NAME" "logs/" \
        --expire-days "$RETENTION_DAYS" \
        --force; then
        echo "  已添加"
    else
        echo "  错误：生命周期规则添加失败。" >&2
        echo "  日志桶将没有过期策略，存储会无限增长 —— 请修复后再继续。" >&2
        exit 1
    fi
fi

# 3) 校验
echo ""
echo "[3/3] 当前生命周期规则："
npx wrangler r2 bucket lifecycle list "$BUCKET"

echo ""
echo "=== 完成 ==="
echo ""
echo "后续步骤："
echo "  1. 用 wrangler 部署 Worker（在 report-worker/ 目录执行 npx wrangler deploy）"
echo "  2. 设置上报令牌： npx wrangler secret put REPORT_TOKEN"
echo "  3. 把 Worker 的 URL 和令牌填到客户端配置（REPORT_URL / REPORT_TOKEN）"
echo "  4. 在客户端配置里手动把 ENABLE_REPORT 改为 yes（默认关闭）"
