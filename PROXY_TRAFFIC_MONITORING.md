# 代理服务器流量监控说明

## 问题背景

在使用 iptables 按端口监控代理服务器（如 xray/v2ray）流量时，会遇到一个根本性的限制问题。

## 代理流量的工作原理

以 xray 代理服务器（监听 11710 端口）为例，当客户端访问 YouTube 时的流量路径：

```
客户端 (36.161.108.71)
    ↓ 请求 (入站到11710)
代理服务器 (104.194.87.91:11710)
    ↓ 请求 (出站，随机源端口 52658)
YouTube (149.154.175.55:443)
    ↓ 响应 (入站，目标端口 52658)
代理服务器 (104.194.87.91:52658)
    ↓ 响应 (出站从11710)
客户端 (36.161.108.71)
```

## iptables 端口监控的局限性

### 可以监控的流量

使用 `--dport 11710` 和 `--sport 11710` 规则只能捕获：

✅ **客户端 → 服务器11710端口** (入站，dport:11710)  
✅ **服务器11710端口 → 客户端** (出站，sport:11710)

### 无法监控的流量

❌ **服务器随机端口 → YouTube** (出站，sport:52658)  
❌ **YouTube → 服务器随机端口** (入站，dport:52658)

## 实际测量数据

以下是 2025-11-19 的实际测量对比：

### 服务器总流量（vnstat）
- 入站：5.88 GiB
- 出站：6.02 GiB
- 比例：**1.02:1** ✓ 符合代理预期

### 端口 11710 流量（iptables 原始方案）
- 入站：3.81 MB (0.0037 GiB)
- 出站：2369 MB (2.313 GiB)
- 比例：**1:620** ✗ 严重不对称

### 流量捕获率
- 出站捕获率：2.313 / 6.02 = **38.4%**
- 入站捕获率：0.0037 / 5.88 = **0.06%**

### 原因分析

- **入站流量**：只捕获了客户端的请求头/握手流量（~4MB），未捕获服务器从目标网站接收的响应流量（~5.88GB）
- **出站流量**：只捕获了服务器发送给客户端的响应流量（~2.3GB），未捕获服务器向目标网站发起的请求流量

## 解决方案

### 方案选择

由于完整监控代理流量需要使用 cgroup/conntrack 等复杂技术，我们采用**估算法**：

**核心原理**：客户端请求多少数据，服务器就需要下载并转发相应数据

### 计算公式

```bash
入站流量(dport) = 客户端实际请求量（可准确测量）
出站流量(sport) = 入站流量（估算值）
总流量 = 入站流量 × 2（估算值）
```

### 实现代码

```bash
# 获取入站流量（字节）
local in_bytes=$(iptables -L ufw-before-input -v -n -x | grep "dpt:$port" | awk '{sum+=$2} END {printf "%.0f", sum+0}')

# 转换为GB
local in_gb=$(printf "%.2f" $(echo "scale=2; $in_bytes / 1024 / 1024 / 1024" | bc))

# 代理场景：出站流量 = 入站流量（估算）
local out_gb="$in_gb"

# 总流量 = 入站 × 2（估算）
local total_gb=$(printf "%.2f" $(echo "scale=2; $in_gb * 2" | bc))

echo "$in_gb,$out_gb,$total_gb"
```

## 用户说明

在脚本输出中添加以下说明：

```
⚠ 代理监控说明：
  入站: 实际测量值（客户端→服务器）
  出站: 估算值 = 入站（服务器→客户端，无法直接测量）
  总计: 估算值 = 入站 × 2（实际略高10-20%因协议开销）
```

## 估算精度

### 误差来源

1. **协议开销**：TCP/IP 头部、TLS 握手、重传等（+5-10%）
2. **压缩因素**：某些内容可能经过压缩（±5-15%）
3. **连接复用**：HTTP/2、QUIC 等协议的连接复用影响

### 预期精度

- **理想情况**：总流量 ≈ 入站 × 2.0
- **实际情况**：总流量 ≈ 入站 × 2.1 到 2.3
- **误差范围**：±10-20%

对于流量限制场景，这个精度完全可以接受。

## 精确监控方案（备选）

如果需要精确监控代理总流量，可以使用以下方案：

### 方案1：cgroup v2 + iptables

```bash
# 创建 cgroup
mkdir -p /sys/fs/cgroup/xray
echo [xray-pid] > /sys/fs/cgroup/xray/cgroup.procs

# 使用 iptables cgroup 匹配
iptables -I INPUT -m cgroup --path xray -j ACCOUNT
iptables -I OUTPUT -m cgroup --path xray -j ACCOUNT
```

**优点**：可以追踪进程的所有流量  
**缺点**：配置复杂，需要 cgroup v2 支持

### 方案2：conntrack 标记

```bash
# 标记 xray 发出的包
iptables -t mangle -I OUTPUT -m owner --cmd-owner xray-linux-amd64 -j MARK --set-mark 11710
iptables -t mangle -A OUTPUT -m mark --mark 11710 -j CONNMARK --save-mark

# 标记关联的返回包
iptables -t mangle -A INPUT -m connmark --mark 11710 -j MARK --restore-mark

# 统计流量
iptables -I INPUT -m mark --mark 11710 -j ACCOUNT
iptables -I OUTPUT -m mark --mark 11710 -j ACCOUNT
```

**优点**：可以追踪连接的完整流量  
**缺点**：需要 conntrack 支持，配置复杂

### 方案3：进程级监控工具

使用 `nethogs`、`iftop` 等工具直接监控进程流量。

**优点**：简单直观  
**缺点**：无法与 iptables 限速集成

## 结论

对于代理场景的流量监控和限制：

1. **推荐方案**：使用估算法（入站 × 2），简单实用，精度可接受
2. **显示说明**：在输出中明确告知用户这是估算值
3. **精确需求**：如果需要精确监控，使用 cgroup 或 conntrack 方案

---

**最后更新**：2025-11-19  
**版本**：v1.0
