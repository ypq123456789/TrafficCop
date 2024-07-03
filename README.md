# TrafficCop - 智能流量监控与限制脚本
[English](README_EN.md) | 中文
## 特别提醒
**流量统计是从你开始安装vnstat开始的**

**流量统计是从你开始安装vnstat开始的**

**流量统计是从你开始安装vnstat开始的**

**如果你在安装本脚本之前没有安装过vnstat，请注意：本脚本基于vnstat的流量统计，而vnstat只会从它安装好之后开始统计流量！**

**本脚本TC模式无法防止ddos消耗流量，流量消耗速度仍然较快！欢迎PR修复（如果可修复的话）**

## 一键安装脚本

### 一键全家桶：
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh && sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```
### 我只要监控，不要TG推送：
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```
## 实用命令
### 查看日志：
```
sudo tail -f -n 30 /root/traffic_monitor.log
```
### 查看当前配置：
```
sudo cat traffic_monitor_config.txt
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

要使用此功能，请在脚本配置过程中提供你的 Telegram Bot Token 和 Chat ID。

Telegram Bot Token 在你创建机器人时会显示。

Chat ID获取方法：https://api.telegram.org/bot${BOT_TOKEN}/getUpdates 

${BOT_TOKEN}是你的 Telegram Bot Token 

Chat ID还可以通过bot获取，更简单，比如[username_to_id_bot](https://t.me/username_to_id_bot)

### 相关命令
一键推送脚本
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```
查看tg推送定时执行日志
```
sudo tail -f -n 30 /root/tg_notifier_cron.log
```
查看当前状态
```
sudo tail -f -n 30 /tmp/last_traffic_notification
```
杀死所有TG推送进程
```
sudo pkill -f tg_notifier.sh && crontab -l | grep -v "tg_notifier.sh" | crontab -
```

推送示意如下：
![image](https://github.com/ypq123456789/TrafficCop/assets/114487221/7674bb25-2771-47e3-a999-8701ef160c7c)

## 预设配置
### 阿里云CDT 200G：
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g
```
### 阿里云CDT 20G：
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g
```
### 阿里云轻量 1T：
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-1T
```
### azure学生 15G：
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-15g
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
