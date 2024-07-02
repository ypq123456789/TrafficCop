# TrafficCop - 智能流量监控与限制脚本
[English](README_EN.md) | 中文
## 特别提醒
**流量统计是从你开始安装vnstat开始的**

**流量统计是从你开始安装vnstat开始的**

**流量统计是从你开始安装vnstat开始的**

**如果你在安装本脚本之前没有安装过vnstat，请注意：本脚本基于vnstat的流量统计，而vnstat只会从它安装好之后开始统计流量！**

## 一键安装脚本

### 标准安装（可能有几分钟延迟）：
```
curl -fsSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh -o /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```
### 快速更新版本：
```
curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```
## 实用命令
### 查看日志：
```
tail -f -n 30 /root/traffic_monitor.log
```
### 查看当前配置：
```
cat traffic_monitor_config.txt
```
### 紧急停止所有traffic_monitor进程（用于脚本出现问题时）：
```
pkill -f traffic_monitor.sh
```
### 一键解除限速
```
curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
```

## 脚本逻辑
- 自动检测并选择主要网卡进行流量限制。
- 用户选择流量统计模式（四种选项）。
- 用户设置流量计算周期（月/季/年）和起始日期。
- 用户输入流量限制和容错范围。
- 用户选择限制模式（TC模式或关机模式）。
- 对于TC模式，用户可设置限速值。
- 脚本每分钟检测流量消耗，达到限制时执行相应操作。
- 在新的流量周期开始时自动解除限制。

## 脚本特色
- 四种全面的流量统计模式，适应各种VPS计费方式。
- 自定义流量计算周期和起始日。
- 自定义流量容错范围。
- 交互式配置，可随时修改参数。
- 实时流量统计提示。
- TC模式保证SSH连接可用。
- 关机模式提供更严格的流量控制。
- 自定义限速带宽（TC模式）。

## 预设配置
### 阿里云CDT 200G：
```
curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g
```
### 阿里云CDT 20G：
```
curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g
```

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ypq123456789/TrafficCop&type=Date)](https://star-history.com/#ypq123456789/TrafficCop&Date)

## 支持作者
![mm_reward_qrcode_1719923713616](https://github.com/ypq123456789/TrafficCop/assets/114487221/d402da68-b37d-4538-8505-1afe704507b2)
