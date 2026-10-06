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

    // 读取并限制体积。
    // ⚠️ 不能先 request.text() 再判长度：那会把整个请求体读进内存之后才检查，
    //    而 Cloudflare 允许的请求体可达数百 MB、Worker 内存上限 128MB，
    //    持有令牌的请求可以借此把 Worker 打爆内存。
    //    这里改为流式按字节累计，一超限立刻停读并返回 413。
    //    另外 raw.length 是 UTF-16 码元数，不是字节数，多字节字符会少算。
    const body = await readBodyLimited(request, MAX_BODY_BYTES);
    if (body === null) {
      return json({ ok: false, error: "payload too large" }, 413);
    }
    const raw = new TextDecoder("utf-8", { fatal: false }).decode(body);

    // 解析 JSON
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return json({ ok: false, error: "invalid json" }, 400);
    }

    // 顶层必须是普通对象：null / 数组 / 数字 / 字符串都要拒绝。
    // 否则 null 会在读 data.machine_id 时抛异常返回 500（与文档承诺的 400 不符），
    // 而数组会绕过字段校验、把一条没有 event 的脏记录写进 R2 并返回成功。
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
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

/**
 * 流式读取请求体，超过 limit 字节立即放弃。
 * 返回 Uint8Array；超限返回 null。
 *
 * 这样做的意义：在读到第 limit+1 个字节时就能返回，不必把整个请求体
 * 载入内存。否则持有令牌者发一个 200MB 的体就能耗尽 Worker 的 128MB 内存。
 */
async function readBodyLimited(request, limit) {
  if (!request.body) return new Uint8Array(0);

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        // 主动取消读取，及时释放连接与缓冲
        try { await reader.cancel(); } catch { /* 忽略取消异常 */ }
        return null;
      }
      chunks.push(value);
    }
  } finally {
    try { reader.releaseLock(); } catch { /* 已关闭时忽略 */ }
  }

  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.byteLength;
  }
  return out;
}

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
//
// ⚠️ 不能先比较长度再提前 return：那会在响应时间上泄露令牌长度，
//    攻击者能控制候选令牌并反复测量，逐步把长度和内容试出来。
//    正确做法是先把两端都映射成**固定长度**的摘要，再逐字节比较，
//    这样比较耗时可执行次数与输入长度无关。
//    这里用同步的 FNV-1a 摘要（不引入 await 到调用链，也不依赖 WebCrypto 的异步接口），
//    把任意长度输入压成固定 8 字符，再做恒定时间比较。
function timingSafeEqual(a, b) {
  const da = fixedLengthDigest(a);
  const db = fixedLengthDigest(b);
  let diff = 0;
  for (let i = 0; i < da.length; i++) {
    diff |= da.charCodeAt(i) ^ db.charCodeAt(i);
  }
  return diff === 0;
}

// 把任意字符串压成固定 8 字符摘要（FNV-1a 32 位，双轮不同种子降低碰撞）
// 固定长度是关键：后续比较的迭代次数因此与输入长度无关。
function fixedLengthDigest(s) {
  const str = String(s);
  const h1 = fnv1a(str, 0x811c9dc5);
  const h2 = fnv1a(str, 0x01000193);
  return h1.toString(16).padStart(8, "0") + h2.toString(16).padStart(8, "0");
}

function fnv1a(str, seed) {
  let h = seed >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    // FNV prime 16777619，用移位加法避免 32 位乘法溢出
    h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
  }
  return h >>> 0;
}
