/**
 * TrafficCop 日志上报接收端（Cloudflare Worker）
 * ============================================
 *
 * 职责：
 *   1. 校验上报令牌
 *   2. 解析客户端上报的 JSON
 *   3. 写入 R2（按机器 + 日期分目录，便于按机器回溯）
 *   4. 返回 { ok: true }
 *
 * 部署：
 *   npx wrangler deploy
 *
 * 环境变量 / 密钥（用 wrangler secret put 设置，不要写进代码）：
 *   REPORT_TOKEN   —— 与客户端共享的上报令牌
 *
 * R2 绑定（wrangler.toml）：
 *   [[r2_buckets]]
 *   binding = "LOGS"
 *   bucket_name = "trafficcop-logs"
 */

// 允许的最大请求体（客户端上报通常 <1KB；留足冗余防御滥用）
const MAX_BODY_BYTES = 64 * 1024;

export default {
  async fetch(request, env, ctx) {
    // 只接受 POST
    if (request.method !== "POST") {
      return json({ ok: false, error: "method not allowed" }, 405);
    }

    // 路径校验：只服务 /report
    const url = new URL(request.url);
    if (url.pathname !== "/report") {
      return json({ ok: false, error: "not found" }, 404);
    }

    // 令牌校验（用恒定时间比较，避免时序侧信道）
    const token = request.headers.get("X-Report-Token") || "";
    if (!env.REPORT_TOKEN || !timingSafeEqual(token, env.REPORT_TOKEN)) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    // 读取并限制体积
    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return json({ ok: false, error: "payload too large" }, 413);
    }

    // 解析 JSON
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return json({ ok: false, error: "invalid json" }, 400);
    }

    // 基本字段校验
    const machineId = sanitizeId(data.machine_id || request.headers.get("X-Machine-Id") || "unknown");
    const eventType = sanitizeId(data.event || "unknown");
    const ts = Number(data.epoch) || Math.floor(Date.now() / 1000);
    const date = new Date(ts * 1000);
    const dayKey = date.toISOString().slice(0, 10);

    // 存储路径：logs/<machine>/<date>/<epoch>-<event>.json
    // 按机器分目录 → 排查单台机器时可直接列前缀，效率高
    const key = `logs/${machineId}/${dayKey}/${ts}-${eventType}-${randSuffix()}.json`;

    const record = {
      ...data,
      received_at: new Date().toISOString(),
      client_ip: request.headers.get("CF-Connecting-IP") || "",
      country: request.headers.get("CF-IPCountry") || "",
    };

    try {
      await env.LOGS.put(key, JSON.stringify(record), {
        httpMetadata: { contentType: "application/json" },
        // 便于后续按机器/事件筛选
        customMetadata: {
          machine_id: machineId,
          event: eventType,
          script_version: String(data.script_version || ""),
        },
      });
    } catch (e) {
      return json({ ok: false, error: "storage failed" }, 500);
    }

    return json({ ok: true, key });
  },
};

// ---------- 工具函数 ----------

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// 只保留安全字符，防止路径穿越（../）和非法 key
// 说明：先做字符白名单，再把「连续的点」压成单个点并去首尾点。
// 仅靠白名单是不够的 —— 白名单会把 "../../etc/passwd" 变成
// ".._.._etc_passwd"，虽然 R2 里 ".." 本身不构成穿越（斜杠已被换掉），
// 但 key 里残留 ".." 会让人误判、也可能被下游工具二次解释，故一并清掉。
function sanitizeId(s) {
    let out = String(s)
        .replace(/[^A-Za-z0-9._-]/g, "_")
        .replace(/\.{2,}/g, ".")   // ".." -> "."（消除穿越语义）
        .replace(/^[.]+|[.]+$/g, ""); // 去掉首尾的点与空格
    out = out.slice(0, 64);
    return out || "unknown";
}

function randSuffix() {
  return Math.random().toString(36).slice(2, 8);
}

// 恒定时间字符串比较，避免通过响应时间推测令牌
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
