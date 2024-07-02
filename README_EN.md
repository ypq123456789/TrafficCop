# TrafficCop - Intelligent Traffic Monitoring and Limiting Script

## Special Reminder
**Traffic statistics start from when you begin installing vnstat**

**Traffic statistics start from when you begin installing vnstat**

**Traffic statistics start from when you begin installing vnstat**

**If you haven't installed vnstat before installing this script, please note: This script is based on vnstat's traffic statistics, and vnstat will only start counting traffic after it's installed!**

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
### One-Click Speed Limit Removal
```
curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
```

## Script Logic
- Automatically detect and select the main network card for traffic limitation.
- User selects traffic statistics mode (four options).
- User sets traffic calculation cycle (month/quarter/year) and start date.
- User inputs traffic limit and tolerance range.
- User chooses limitation mode (TC mode or shutdown mode).
- For TC mode, user can set speed limit value.
- Script checks traffic consumption every minute, executes corresponding operation when limit is reached.
- Automatically removes limitation at the start of a new traffic cycle.

## Script Features
- Four comprehensive traffic statistics modes, adapting to various VPS billing methods.
- Customizable traffic calculation cycle and start date.
- Customizable traffic tolerance range.
- Interactive configuration, parameters can be modified at any time.
- Real-time traffic statistics prompts.
- TC mode ensures SSH connection remains available.
- Shutdown mode provides stricter traffic control.
- Customizable speed limit bandwidth (TC mode).

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

## Support the Author
![mm_reward_qrcode_1719923713616](https://github.com/ypq123456789/TrafficCop/assets/114487221/d402da68-b37d-4538-8505-1afe704507b2)
```
