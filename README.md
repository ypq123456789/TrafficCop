# TrafficCop - 智能流量监控与限制脚本
[English](README_EN.md) | 中文
## 注意事项

1. 本脚本是基于vnstat的流量统计，vnstat只会在安装后开始统计流量!

2. TC模式无法防止DDoS消耗流量，流量消耗速度仍然较快！欢迎PR修复(如果可以修复的话)。

3. 如果遇到GitHub API速率限制问题,可以尝试以下解决方案:
   - 使用原始内容URL下载脚本
   - 等待API限制重置(通常1小时)
   - 使用个人访问令牌增加API限额
   - 手动下载脚本并运行

4. 脚本默认使用root权限运行。如需非root用户运行，请确保该用户有sudo权限，并将所有命令前加sudo。

5. 如果遇到问题，可以查看日志文件(/root/TrafficCop/traffic_monitor.log)获取更多信息。

6. 定期检查脚本更新以获取新功能和bug修复。

7. 对于特定VPS提供商，可能需要调整配置以适应其计费模式。

8. TC模式下的速度限制可能不是精确的，实际速度可能略有偏差。

9. 关机模式会完全切断网络连接，请谨慎使用。

10. 建议定期备份配置文件(traffic_monitor_config.txt)。

## 常见问题

Q: 为什么我的流量统计似乎不准确?
A: 确保vnstat已正确安装并运行一段时间。新安装的vnstat需要时间来收集准确的数据。

Q: 如何更改已设置的配置?
A: 重新运行脚本，它会提示你是否要修改现有配置。

Q: TC模式下SSH连接变慢怎么办?
A: 尝试增加TC模式下的速度限制值。

Q: 如何完全卸载脚本?
A: 使用以下命令:
```
sudo pkill -f traffic_monitor.sh
sudo rm -rf /root/TrafficCop
sudo tc qdisc del dev $(ip route | grep default | cut -d ' ' -f 5) root
```
## 一键安装脚本

### 一键全家桶（调用api，版本最新，可能会403）：
```
sudo apt update && mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
### 一键全家桶（从原始内容下载，版本可能落后）：
```
sudo apt update && mkdir -p /root/TrafficCop && curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
### 我只要监控，不要TG推送：
```
sudo apt update &&  mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh
```
## 实用命令
### 查看日志：
```
sudo tail -f -n 30 /root/TrafficCop/traffic_monitor.log
```
### 查看当前配置：
```
sudo cat /root/TrafficCop/traffic_monitor_config.txt
```
### 紧急停止所有traffic_monitor进程（用于脚本出现问题时）：
```
sudo pkill -f traffic_monitor.sh
```
### 一键解除限速
```
sudo curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
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

## Telegram Bot 集成
TrafficCop 现在集成了 Telegram Bot 功能，可以发送以下通知：

- 限速警告
- 限速解除通知
- 新周期开始通知
- 关机警告
- 每日流量报告

**支持自定义主机名，一个机器人就可以统一管理你的所有小鸡！**

**支持自定义每日流量报告的时间，你想每个小鸡什么时候通知就什么时候，当然你也可以设置都是一样的时间，一下子冒出来一堆，享受坐拥数🐔的快感**

要使用此功能，请在脚本配置过程中提供你的 Telegram Bot Token 和 Chat ID。

Telegram Bot Token 在你创建机器人时会显示。

Chat ID获取方法：https://api.telegram.org/bot${BOT_TOKEN}/getUpdates 

${BOT_TOKEN}是你的 Telegram Bot Token 

Chat ID还可以通过bot获取，更简单，比如[username_to_id_bot](https://t.me/username_to_id_bot)

### 相关命令
一键推送脚本（调用api，版本最新，可能会403）：
```
sudo apt update && mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
一键推送脚本（从原始内容下载，版本可能落后）：
```
sudo apt update && mkdir -p /root/TrafficCop && curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
查看tg推送定时执行日志
```
sudo tail -f -n 30 /root/TrafficCop/tg_notifier_cron.log
```
查看当前状态
```
sudo tail -f -n 30 /root/TrafficCop/last_traffic_notification
```
杀死所有TG推送进程
```
sudo pkill -f tg_notifier.sh && crontab -l | grep -v "tg_notifier.sh" | crontab -
```

推送示意如下：
![image](https://github.com/ypq123456789/TrafficCop/assets/114487221/7674bb25-2771-47e3-a999-8701ef160c7c)

## pushplus 集成
TrafficCop 现在集成了pushplus推送功能。

可发送的通知类型同上、支持自定义主机名、支持自定义每日流量报告的时间。

要使用此功能，请在脚本配置过程中提供你的pushplus token。

### 相关命令
一键推送脚本（调用api，版本最新，可能会403）：
```
sudo bash -c "mkdir -p /root/TrafficCop && curl -sSfL -H 'Accept: application/vnd.github.v3.raw' -o /root/TrafficCop/pushplus_notifier.sh https://api.github.com/repos/ypq123456789/TrafficCop/contents/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && /root/TrafficCop/pushplus_notifier.sh"
```
一键推送脚本（从原始内容下载，版本可能落后）：
```
sudo mkdir -p /root/TrafficCop && curl -sSfL -o /root/TrafficCop/pushplus_notifier.sh https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && /root/TrafficCop/pushplus_notifier.sh
```
查看pushplus推送定时执行日志
```
sudo tail -f -n 30 /root/TrafficCop/pushplus_notifier_cron.log
```
查看当前状态
```
sudo tail -f -n 30 /root/TrafficCop/last_pushplus_notification
```
杀死所有pushplus推送进程
```
sudo pkill -f pushplus_notifier.sh && crontab -l | grep -v "pushplus_notifier.sh" | crontab -
```

## 预设配置
### 阿里云CDT 200G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### 阿里云CDT 20G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### 阿里云轻量 1T：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-1T && cat /root/TrafficCop/traffic_monitor_config.txt
```
### azure学生 15G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-15g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### azure学生 115G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-115g && cat /root/TrafficCop/traffic_monitor_config.txt
```

### GCP 625G[大流量极致解法](https://www.nodeseek.com/post-115166-1)：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-625g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### GCP 200G(白嫖标准路由200g流量就跑)：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-200g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### alice 1500G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/alice-1500g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### 亚洲云 300G：
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/asia-300g && cat /root/TrafficCop/traffic_monitor_config.txt
```
## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ypq123456789/TrafficCop&type=Date)](https://star-history.com/#ypq123456789/TrafficCop&Date)

## 交流TG群：
https://t.me/+ydvXl1_OBBBiZWM1

## 支持作者
<span><small>非常感谢您对本项目的兴趣！维护开源项目确实需要大量时间和精力投入。若您认为这个项目为您带来了价值，希望您能考虑给予一些支持，哪怕只是一杯咖啡的费用。
您的慷慨相助将激励我继续完善这个项目，使其更加实用。它还能让我更专心地参与开源社区的工作。如果您愿意提供赞助，可通过下列渠道：</small></span>
<ul>
    <li>给该项目点赞 &nbsp;<a style="vertical-align: text-bottom;" href="https://github.com/ypq123456789/TrafficCop">
      <img src="https://img.shields.io/github/stars/ypq123456789/TrafficCop?style=social" alt="给该项目点赞" />
    </a></li>
    <li>关注我的 Github &nbsp;<a style="vertical-align: text-bottom;"  href="https://github.com/ypq123456789/TrafficCop">
      <img src="https://img.shields.io/github/followers/ypq123456789?style=social" alt="关注我的 Github" />
    </a></li>
</ul>
<table>
    <thead><tr>
        <th>微信</th>
        <th>支付宝</th>
    </tr></thead>
    <tbody><tr>
        <td><img style="max-width: 50px" src="https://github.com/ypq123456789/TrafficCop/assets/114487221/fb265eef-e624-4429-b14a-afdf5b2ca9c4" alt="微信" /></td>
        <td><img style="max-width: 50px" src="https://github.com/ypq123456789/TrafficCop/assets/114487221/884b58bd-d76f-4e8f-99f4-cac4b9e97168" alt="支付宝" /></td>
    </tr></tbody>
</table>
