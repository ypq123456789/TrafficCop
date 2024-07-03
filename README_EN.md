# TrafficCop - Intelligent Traffic Monitoring and Limiting Script
[English](README_EN.md) | [中文](README.md)

## Special Reminder
**Traffic statistics start from when you begin installing vnstat**

**Traffic statistics start from when you begin installing vnstat**

**Traffic statistics start from when you begin installing vnstat**

**If you haven't installed vnstat before installing this script, please note: This script is based on vnstat's traffic statistics, and vnstat will only start counting traffic after it's installed!**

**The TC mode of this script cannot prevent DDoS from consuming traffic, and traffic consumption speed is still relatively fast! PRs to fix this (if possible) are welcome.**

## One-Click Installation Script

### Standard Installation (may have a few minutes delay):
```
curl -fsSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh -o /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```
### Quick Update Version:
```
curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```
## Useful Commands
### View Logs:
```
tail -f -n 30 /root/traffic_monitor.log
```
### View Current Configuration:
```
cat traffic_monitor_config.txt
```
### Emergency Stop All traffic_monitor Processes (for when the script encounters issues):
```
pkill -f traffic_monitor.sh
```
### One-Click Remove Traffic Limit
```
curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
```

## Script Logic
- Automatically detects and selects the main network interface for traffic limiting.
- User selects traffic statistics mode (four options).
- User sets traffic calculation cycle (month/quarter/year) and start date.
- User inputs traffic limit and tolerance range.
- User chooses limiting mode (TC mode or shutdown mode).
- For TC mode, user can set speed limit value.
- Script checks traffic consumption every minute, executes corresponding operation when limit is reached.
- Automatically removes limit at the start of a new traffic cycle.

## Script Features
- Four comprehensive traffic statistics modes, adapting to various VPS billing methods.
- Customizable traffic calculation cycle and start date.
- Customizable traffic tolerance range.
- Interactive configuration, parameters can be modified at any time.
- Real-time traffic statistics prompts.
- TC mode ensures SSH connection remains usable.
- Shutdown mode provides stricter traffic control.
- Customizable speed limit bandwidth (TC mode).

## Telegram Bot Integration
TrafficCop now integrates Telegram Bot functionality, capable of sending the following notifications:

- Speed limit warning
- Speed limit removal notification
- New cycle start notification
- Shutdown warning
- Daily traffic report

**Supports custom hostname, one bot can manage all your VPS uniformly!**

To use this feature, please provide your Telegram Bot Token and Chat ID during script configuration.

Telegram Bot Token will be displayed when you create the bot.

Method to get Chat ID: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates 

${BOT_TOKEN} is your Telegram Bot Token 

Chat ID can also be obtained through bots, which is simpler, such as [username_to_id_bot](https://t.me/username_to_id_bot)

### Related Commands
One-click push script
```
curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```
View tg push scheduled execution log
```
tail -f -n 30 /root/tg_notifier_cron.log
```
View current status
```
tail -f -n 30 /tmp/last_traffic_notification
```
Kill all TG push processes
```
pkill -f tg_notifier.sh && crontab -l | grep -v "tg_notifier.sh" | crontab -
```

Push example as follows:
![image](https://github.com/ypq123456789/TrafficCop/assets/114487221/7674bb25-2771-47e3-a999-8701ef160c7c)

## Preset Configurations
### Alibaba Cloud CDT 200G:
```
curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g
```
### Alibaba Cloud CDT 20G:
```
curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g
```

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ypq123456789/TrafficCop&type=Date)](https://star-history.com/#ypq123456789/TrafficCop&Date)

## TG Group for Communication:
https://t.me/+ydvXl1_OBBBiZWM1

## Support the Author
<span><small>Thank you very much for your interest in this project! Maintaining open-source projects indeed requires a lot of time and energy investment. If you feel this project has brought you value, I hope you can consider giving some support, even if it's just the cost of a cup of coffee.
Your generous assistance will motivate me to continue improving this project, making it more practical. It will also allow me to focus more on work in the open-source community. If you're willing to provide sponsorship, you can do so through the following channels:</small></span>
<ul>
    <li>Star this project &nbsp;<a style="vertical-align: text-bottom;" href="https://github.com/ypq123456789/TrafficCop">
      <img src="https://img.shields.io/github/stars/ypq123456789/TrafficCop?style=social" alt="Star this project" />
    </a></li>
    <li>Follow my Github &nbsp;<a style="vertical-align: text-bottom;"  href="https://github.com/ypq123456789/TrafficCop">
      <img src="https://img.shields.io/github/followers/ypq123456789?style=social" alt="Follow my Github" />
    </a></li>
</ul>
<table>
    <thead><tr>
        <th>WeChat</th>
        <th>Alipay</th>
    </tr></thead>
    <tbody><tr>
        <td><img style="max-width: 50px" src="https://github.com/ypq123456789/TrafficCop/assets/114487221/fb265eef-e624-4429-b14a-afdf5b2ca9c4" alt="WeChat" /></td>
        <td><img style="max-width: 50px" src="https://github.com/ypq123456789/TrafficCop/assets/114487221/884b58bd-d76f-4e8f-99f4-cac4b9e97168" alt="Alipay" /></td>
    </tr></tbody>
</table>
