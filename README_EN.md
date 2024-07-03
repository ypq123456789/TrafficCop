# TrafficCop - Intelligent Traffic Monitoring and Limiting Script
[English](README_EN.md) | 中文

## Notes

1. This script is based on vnstat traffic statistics. vnstat only starts counting traffic after installation!

2. TC mode cannot prevent DDoS traffic consumption, traffic consumption speed is still relatively fast! PRs to fix this are welcome (if possible).

3. If you encounter GitHub API rate limit issues, try the following solutions:
   - Use the raw content URL to download the script
   - Wait for the API limit to reset (usually 1 hour)
   - Use a personal access token to increase API quota
   - Manually download and run the script

4. The script runs with root privileges by default. For non-root users, ensure sudo privileges and prefix all commands with sudo.

5. If you encounter issues, check the log file (/root/traffic_monitor.log) for more information.

6. Regularly check for script updates to get new features and bug fixes.

7. For specific VPS providers, configuration adjustments may be needed to adapt to their billing models.

8. Speed limits in TC mode may not be precise, actual speeds may vary slightly.

9. Shutdown mode will completely cut off network connections, use with caution.

10. It's recommended to regularly backup the configuration file (traffic_monitor_config.txt).

## FAQ

Q: Why does my traffic statistics seem inaccurate?
A: Ensure vnstat is correctly installed and has been running for some time. Newly installed vnstat needs time to collect accurate data.

Q: How to change the set configuration?
A: Re-run the script, it will prompt you whether to modify the existing configuration.

Q: What if SSH connection becomes slow in TC mode?
A: Try increasing the speed limit value in TC mode.

Q: How to completely uninstall the script?
A: Use the following commands:
```
sudo pkill -f traffic_monitor.sh
sudo rm /root/traffic_monitor.sh /root/traffic_monitor_config.txt /root/traffic_monitor.log
sudo tc qdisc del dev $(ip route | awk '/default/ {print $5}') root
```

## One-click Installation Script

### One-click full package (calls API, latest version, may be rate-limited):
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh && sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```

### One-click full package (download from raw content, version may be outdated):
```
sudo curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh && sudo curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```

### I only want monitoring, no TG push:
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/traffic_monitor.sh && chmod +x /root/traffic_monitor.sh && bash /root/traffic_monitor.sh
```

## Useful Commands
### View logs:
```
sudo tail -f -n 30 /root/traffic_monitor.log
```

### View current configuration:
```
sudo cat traffic_monitor_config.txt
```

### Emergency stop all traffic_monitor processes (for when the script has issues):
```
sudo pkill -f traffic_monitor.sh
```

### One-click remove speed limit
```
sudo curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
```

## Script Logic
- Automatically detects and selects the main network interface for traffic limiting.
- User selects traffic statistics mode (four options).
- User sets traffic calculation cycle (month/quarter/year) and start date.
- User inputs traffic limit and tolerance range.
- User selects limiting mode (TC mode or shutdown mode).
- For TC mode, user can set speed limit value.
- Script checks traffic consumption every minute, executes corresponding action when limit is reached.
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
TrafficCop now integrates Telegram Bot functionality, which can send the following notifications:

- Speed limit warnings
- Speed limit removal notifications
- New cycle start notifications
- Shutdown warnings
- Daily traffic reports

**Supports custom hostnames, one bot can uniformly manage all your VPS!**

To use this feature, provide your Telegram Bot Token and Chat ID during script configuration.

Telegram Bot Token is displayed when you create the bot.

Method to get Chat ID: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates

${BOT_TOKEN} is your Telegram Bot Token

Chat ID can also be obtained through bots, which is simpler, such as [username_to_id_bot](https://t.me/username_to_id_bot)

### Related Commands
One-click push script
```
sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/tg_notifier.sh && chmod +x /root/tg_notifier.sh && bash /root/tg_notifier.sh
```

View TG push scheduled execution log
```
sudo tail -f -n 30 /root/tg_notifier_cron.log
```

View current status
```
sudo tail -f -n 30 /tmp/last_traffic_notification
```

Kill all TG push processes
```
sudo pkill -f tg_notifier.sh && crontab -l | grep -v "tg_notifier.sh" | crontab -
```

Push example as follows:
![image](https://github.com/ypq123456789/TrafficCop/assets/114487221/7674bb25-2771-47e3-a999-8701ef160c7c)

## Preset Configurations
### Alibaba Cloud CDT 200G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g && cat traffic_monitor_config.txt
```

### Alibaba Cloud CDT 20G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g && cat traffic_monitor_config.txt
```

### Alibaba Cloud Lightweight 1T:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-1T && cat traffic_monitor_config.txt
```

### Azure Student 15G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-15g && cat traffic_monitor_config.txt
```

### Azure Student 115G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-115g && cat traffic_monitor_config.txt
```

### GCP 625G High Traffic Ultimate Solution:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-625g && cat traffic_monitor_config.txt
```

### GCP 200G (Free Standard Route 200G Traffic):
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-200g && cat traffic_monitor_config.txt
```

### Alice 1500G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/alice-1500g && cat traffic_monitor_config.txt
```

### Asia Cloud 300G:
```
sudo curl -o /root/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/asia-300g && cat traffic_monitor_config.txt
```

## Star History
Star History Chart

## Telegram Group for Discussion:
https://t.me/+ydvXl1_OBBBiZWM1

## Support the Author
Thank you very much for your interest in this project! Maintaining open-source projects indeed requires a significant investment of time and energy. If you find this project valuable, please consider offering some support, even if it's just the cost of a cup of coffee.

Your generous assistance will motivate me to continue improving this project and make it more practical. It will also allow me to focus more on contributing to the open-source community. If you're willing to provide sponsorship, you can do so through the following channels:

<ul>
  <li>Star this project &nbsp;<a style="vertical-align: text-bottom;" href="https://github.com/ypq123456789/TrafficCop"> <img src="https://img.shields.io/github/stars/ypq123456789/TrafficCop?style=social" alt="Star this project" /> </a></li>
  <li>Follow me on Github &nbsp;<a style="vertical-align: text-bottom;" href="https://github.com/ypq123456789/TrafficCop"> <img src="https://img.shields.io/github/followers/ypq123456789?style=social" alt="Follow me on Github" /> </a></li>
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
