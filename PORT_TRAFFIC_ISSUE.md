# 端口流量统计问题说明

## 问题描述
在UFW防火墙环境下，端口流量统计只能统计到入站流量，出站流量显示为0。

## 根本原因
1. **UFW默认策略**：UFW默认允许所有出站流量（outgoing: allow），这意味着出站数据包不会经过ufw-user-output链的统计规则
2. **历史流量无法追溯**：iptables只能统计规则添加后的流量，无法统计历史流量
3. **规则缺失**：之前的脚本没有正确添加UFW出站统计规则

## 影响
- 在修复前，端口流量统计严重偏低（只统计入站，漏掉出站）
- 历史流量数据无法恢复

## 解决方案

### 已实施修复（v3.1）
1. ✅ 修改 `init_iptables_rules()` 函数，自动检测UFW环境
2. ✅ 在UFW环境下，自动添加出站统计规则到 `ufw-user-output` 链
3. ✅ 修改 `get_port_traffic_usage()` 函数，优先从UFW链读取流量数据

### 用户操作建议
1. **重启流量统计**：从现在开始，流量统计将包含入站+出站
2. **重置流量计数**（可选）：如果需要重新开始统计，可以重置iptables计数器：
   ```bash
   # 重置所有计数器
   iptables -Z
   ```
3. **使用vnstat作为参考**：vnstat统计的是网络接口总流量，可以作为验证参考

## 验证方法
```bash
# 查看端口的入站和出站规则
iptables -L ufw-user-input -v -n -x | grep "dpt:YOUR_PORT"
iptables -L ufw-user-output -v -n -x | grep "spt:YOUR_PORT"

# 查看端口流量
bash /root/TrafficCop/view_port_traffic.sh
```

## 技术细节
- UFW入站规则：`ufw-user-input` 链
- UFW出站规则：`ufw-user-output` 链（需手动添加统计规则）
- 流量统计从规则添加时刻开始，不包含历史数据
