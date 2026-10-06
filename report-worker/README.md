# TrafficCop 日志上报接收端

客户端（`trafficcop.sh` + `report_lib.sh`）的日志上报接收服务，部署在
Cloudflare Workers 上，数据落到 Cloudflare R2。

## 为什么需要它

客户报「流量不对」时，此前只能靠客户截图或让客户手工传日志，来回几轮才能
定位。有了上报，可直接看到**机器名、用量、脚本版本、cron 是否存活、
状态快照新鲜度**，多数问题在第一次沟通时就能给出结论。

## 架构

```
客户端 trafficcop.sh
  └─ report_lib.sh  (方案 C：结构化 JSON 心跳上报，默认关闭)
       │  POST /report   X-Report-Token: <令牌>
       ▼
Cloudflare Worker  (worker.js)
  └─ 校验令牌 → 解析 JSON → 写 R2
       ▼
R2 桶 trafficcop-logs
  └─ logs/<machine_id>/<YYYY-MM-DD>/<epoch>-<event>-<rand>.json
```

方案 A（`upload_full_log`）作为兜底：需要完整日志时，客户端用 rclone 或
预签名 URL 把 `traffic_monitor.log` 整份传上来。日常不跑。

## 隐私与默认关闭

- **默认关闭**。上报内容含机器名、流量数字等客户数据，必须由客户显式
  开启（`ENABLE_REPORT=yes`），我们不能替客户决定。
- 客户端**只持有上报令牌**（可随时吊销），不持有任何 R2/S3 长期凭证。
- 令牌经 `X-Report-Token` 请求头传递，不进 URL、不进 body，避免被日志记录。
- 服务端用恒定时间比较校验令牌（`timingSafeEqual`），防时序侧信道。

## 部署

需要 Cloudflare 账号（Access Key / Account ID）。

```bash
# 1. 建桶 + 配置生命周期（自动清理 90 天前的日志）
bash setup-r2.sh

# 2. 部署 Worker
npx wrangler deploy

# 3. 设置上报令牌（不要写进代码或 wrangler.toml）
npx wrangler secret put REPORT_TOKEN
```

部署后拿到形如
`https://trafficcop-logs.<account>.workers.dev/report` 的地址，
填到客户端的 `REPORT_URL`，令牌填 `REPORT_TOKEN`。

## 客户端开启方式

在客户端的配置文件里加：

```ini
ENABLE_REPORT=yes
REPORT_URL=https://trafficcop-logs.<account>.workers.dev/report
REPORT_TOKEN=<与 worker 端一致的令牌>
# 可选：心跳降频，默认每 60 次流量检查上报一次（约 1 小时）
REPORT_HEARTBEAT_EVERY=60
```

也可以跑 `./trafficcop.sh --config` 交互式开启。

## 接口

`POST /report`，请求头 `X-Report-Token`，body 为固定 schema 的 JSON：

| 字段 | 说明 |
|---|---|
| `event` | `heartbeat` / `daily` / `error` / `install` |
| `machine_id` | 机器标识（默认取 hostname） |
| `script_version` | 客户端脚本版本 |
| `timestamp` / `epoch` | 上报时间 |
| `usage_gb` / `limit_gb` | 本周期用量与限额（GB） |
| `conversion_base` | 字节→GB 换算进制（1000/1024） |
| `period_start` | 计费周期起始日 |
| `cron_alive` | 定时任务是否存活（`yes`/`no`/`unknown`） |
| `state_age_sec` | 状态快照的年龄（秒），用于判断数据是否新鲜 |
| `vnstat_start` | vnstat 统计起点 |
| `message` | 附加说明 |

响应：`{"ok":true,"key":"<R2 key>"}`；失败时返回 4xx/5xx 与 `{"ok":false,"error":"..."}`。

## 中文机器名的坑（已修）

Windows 中文系统的 `hostname` 返回的是 **GBK 字节**（例如「杨培强的电脑」→
`d1 ee c5 e0 ...`）。这些字节不是合法 UTF-8，直接拼进 JSON 会导致
`JSON.parse` 失败 —— 该机器的**每一份上报都会静默丢失**。

由于中文机器名是国内客户端的默认情况，这是必现故障。客户端 `report_lib.sh`
的处理是：先判断是否合法 UTF-8（是则原样返回，零开销）；不合法则尝试用
`iconv` 按 GBK/GB18030 还原成可读中文；再不行才逐字节降级为 `?`，
**保证整条上报永远不会因为编码问题被丢掉**。

## 测试

本地测试不需要 Cloudflare 账号：

```bash
bash .workbuddy/run_all_report_tests.sh
```

覆盖 7 组、共 99 条断言：上报场景、UTF-8 合法性、locale 隔离、Worker 接收端、
端到端串联、主脚本集成、编码还原。
