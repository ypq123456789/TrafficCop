#!/bin/bash
# ============================================================
# 一键创建 R2 桶 + 生命周期规则
# ============================================================
# 前置：已安装 wrangler 并登录（npx wrangler login）
#
# 用法：
#   bash setup-r2.sh
#   bash setup-r2.sh --retention-days 90
# ============================================================
set -euo pipefail

BUCKET="${BUCKET:-trafficcop-logs}"
RETENTION_DAYS=90

while [ $# -gt 0 ]; do
    case "$1" in
        --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
        --bucket)         BUCKET="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

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
echo ""
echo "[2/3] 添加生命周期规则（${RETENTION_DAYS} 天自动过期）..."
npx wrangler r2 bucket lifecycle add "$BUCKET" \
    --name "expire-logs-${RETENTION_DAYS}d" \
    --prefix "logs/" \
    --expire-days "$RETENTION_DAYS" \
    --force || echo "  （规则可能已存在）"

# 3) 校验
echo ""
echo "[3/3] 当前生命周期规则："
npx wrangler r2 bucket lifecycle list "$BUCKET" || true

echo ""
echo "=== 完成 ==="
echo ""
echo "后续步骤："
echo "  1. 用 wrangler 部署 Worker（在 report-worker/ 目录执行 npx wrangler deploy）"
echo "  2. 设置上报令牌： npx wrangler secret put REPORT_TOKEN"
echo "  3. 把 Worker 的 URL 和令牌填到客户端配置（REPORT_URL / REPORT_TOKEN）"
echo "  4. 在客户端配置里手动把 ENABLE_REPORT 改为 yes（默认关闭）"
