# TrafficCop - Smart Traffic Monitoring and Limiting Script
English | [中文](README.md)

[VTEXS](https://console.vtexs.com/?affid=1554) sponsored this project.

## Important Notes

1. This script relies on vnstat for traffic statistics. vnstat will only start tracking traffic after installation!

2. TC mode cannot prevent DDoS traffic consumption, and traffic can still be consumed quickly! PRs to fix this issue are welcome (if possible).

3. If you encounter GitHub API rate limiting issues, try these solutions:
   - Use raw content URLs to download scripts
   - Wait for the API limit to reset (usually 1 hour)
   - Use a personal access token to increase API quota
   - Download scripts manually and run them

4. The script runs with root privileges by default. For non-root users, ensure they have sudo privileges and prefix all commands with sudo.

5. If you encounter issues, check the log file (/root/TrafficCop/traffic_monitor.log) for more information.

6. Regularly check for script updates to get new features and bug fixes.

7. For specific VPS providers, configuration adjustments may be needed to adapt to their billing models.

8. Speed limits in TC mode may not be precise; actual speeds may vary slightly.

9. Shutdown mode completely cuts off network connections - use with caution.

10. It's recommended to regularly backup the configuration file (traffic_monitor_config.txt).

## Frequently Asked Questions

Q: Why do my traffic statistics seem inaccurate?
A: Ensure vnstat is properly installed and has been running for some time. Newly installed vnstat needs time to collect accurate data.

Q: How do I change existing configurations?
A: Run the script again, and it will prompt you to modify existing configurations.

Q: What if SSH connections become slow in TC mode?
A: Try increasing the speed limit value in TC mode.

Q: How do I completely uninstall the script?
A: Use the following commands:
```
sudo pkill -f traffic_monitor.sh
sudo rm -rf /root/TrafficCop
sudo tc qdisc del dev $(ip route | grep default | cut -d ' ' -f 5) root
```

## One-Click Installation Scripts
### One-Click Interactive Installation Script
```
bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop-manager.sh)
```
#### Features

1. Install Traffic Monitoring - Download and install basic traffic monitoring functionality
2. Install Telegram Notifications - Add Telegram push notifications
3. Install PushPlus Notifications - Add PushPlus push notifications
4. Install ServerChan Notifications - Add ServerChan push notifications
5. Install Port Traffic Limit - Set independent traffic limits for specific ports (NEW)
6. Remove Traffic Limits - Instantly remove current traffic restrictions
7. Remove Port Traffic Limits - Remove traffic limits for specific ports
8. View Logs - View log files for various services
9. View Current Configuration - View configuration files for various services
10. Use Preset Configurations - Apply optimized preset configurations for different service providers
11. Stop All Services - Stop all TrafficCop-related services

#### Advantages
1. One-stop management - Users only need to remember one command to manage all TrafficCop functions
2. Interactive experience - Select via numerical menu, no need to memorize complex commands
3. Visual interface - Enhanced user experience with colored output
4. Flexible operation - Return to main menu after completing an operation to continue with other options
5. User-friendly - Each operation has confirmation prompts to avoid mistakes
   
![image](https://github.com/user-attachments/assets/bc12c7e6-bba3-498d-a0bc-6ed8ce561e84)

### One-Click Complete Suite with Telegram Push (API call, latest version, may return 403):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
### One-Click Complete Suite with Telegram Push (Raw content download, may be outdated):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
### One-Click Complete Suite with PushPlus Push (API call, latest version, may return 403):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/pushplus_notifier.sh" | tr -d '\r' > /root/TrafficCop/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && bash /root/TrafficCop/pushplus_notifier.sh
```
### One-Click Complete Suite with PushPlus Push (Raw content download, may be outdated):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh && sudo curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/pushplus_notifier.sh" | tr -d '\r' > /root/TrafficCop/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && bash /root/TrafficCop/pushplus_notifier.sh
```
### Monitoring Only, No Notifications:
```
sudo apt update &&  mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/trafficcop.sh" | tr -d '\r' > /root/TrafficCop/traffic_monitor.sh && chmod +x /root/TrafficCop/traffic_monitor.sh && bash /root/TrafficCop/traffic_monitor.sh
```
## Useful Commands
### View Logs:
```
sudo tail -f -n 30 /root/TrafficCop/traffic_monitor.log
```
### View Current Configuration:
```
sudo cat /root/TrafficCop/traffic_monitor_config.txt
```
### Emergency Stop All traffic_monitor Processes (for when script issues occur):
```
sudo pkill -f traffic_monitor.sh
```
### One-Click Remove Speed Limit
```
sudo curl -sSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/remove_traffic_limit.sh | sudo bash
```

## Script Logic
- Automatically detects and selects the main network interface for traffic limiting.
- Users select traffic statistics mode (four options).
- Users set traffic calculation cycle (month/quarter/year) and start date.
- Users input traffic limit and error tolerance range.
- Users select limiting mode (TC mode or shutdown mode).
- For TC mode, users can set speed limit values.
- Script checks traffic consumption every minute and executes appropriate actions when limits are reached.
- Automatically removes restrictions when a new traffic cycle begins.

## Script Features
- Four comprehensive traffic statistics modes, adaptable to various VPS billing methods.
- Custom traffic calculation cycles and start dates.
- Custom traffic error tolerance range.
- Interactive configuration, parameters can be modified at any time.
- Real-time traffic statistics prompts.
- TC mode ensures SSH connections remain available.
- Shutdown mode provides stricter traffic control.
- Custom bandwidth throttling (TC mode).

## Telegram Bot Integration
TrafficCop now integrates Telegram Bot functionality, which can send the following notifications:

- Speed limit warnings
- Speed limit removal notifications
- New cycle start notifications
- Shutdown warnings
- Daily traffic reports

**Supports custom hostnames - one bot can manage all your VPS instances!**

**Supports custom daily traffic report times - you can set when each VPS notifies you, or set them all to the same time to enjoy the feeling of owning multiple VPS instances at once!**

To use this feature, provide your Telegram Bot Token and Chat ID during script configuration.

Telegram Bot Token is displayed when you create a bot.

Chat ID can be obtained via: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates 

${BOT_TOKEN} is your Telegram Bot Token

Chat ID can also be obtained more easily through bots like [username_to_id_bot](https://t.me/username_to_id_bot)

### Related Commands
One-Click Push Script (API call, latest version, may return 403):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -H "Accept: application/vnd.github.v3.raw" -fsSL "https://api.github.com/repos/ypq123456789/TrafficCop/contents/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
One-Click Push Script (Raw content download, may be outdated):
```
sudo apt update && mkdir -p /root/TrafficCop && curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/tg_notifier.sh" | tr -d '\r' > /root/TrafficCop/tg_notifier.sh && chmod +x /root/TrafficCop/tg_notifier.sh && bash /root/TrafficCop/tg_notifier.sh
```
View TG Push Scheduled Execution Log
```
sudo tail -f -n 30 /root/TrafficCop/tg_notifier_cron.log
```
View Current Status
```
sudo tail -f -n 30 /root/TrafficCop/last_traffic_notification
```
Kill All TG Push Processes
```
sudo pkill -f tg_notifier.sh && crontab -l | grep -v "tg_notifier.sh" | crontab -
```

Push notification example:
![image](https://github.com/ypq123456789/TrafficCop/assets/114487221/7674bb25-2771-47e3-a999-8701ef160c7c)

## PushPlus Integration
TrafficCop now integrates PushPlus notification functionality.

Notification types are the same as above, with support for custom hostnames and custom daily traffic report times.

To use this feature, provide your PushPlus token during script configuration.

### Related Commands
One-Click Push Script (API call, latest version, may return 403):
```
sudo bash -c "mkdir -p /root/TrafficCop && curl -sSfL -H 'Accept: application/vnd.github.v3.raw' -o /root/TrafficCop/pushplus_notifier.sh https://api.github.com/repos/ypq123456789/TrafficCop/contents/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && /root/TrafficCop/pushplus_notifier.sh"
```
One-Click Push Script (Raw content download, may be outdated):
```
sudo mkdir -p /root/TrafficCop && curl -sSfL -o /root/TrafficCop/pushplus_notifier.sh https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/pushplus_notifier.sh && chmod +x /root/TrafficCop/pushplus_notifier.sh && /root/TrafficCop/pushplus_notifier.sh
```
View PushPlus Push Scheduled Execution Log
```
sudo tail -f -n 30 /root/TrafficCop/pushplus_notifier_cron.log
```
View Current Status
```
sudo tail -f -n 30 /root/TrafficCop/last_pushplus_notification
```
Kill All PushPlus Push Processes
```
sudo pkill -f pushplus_notifier.sh && crontab -l | grep -v "pushplus_notifier.sh" | crontab -
```

Push notification example:
![Screenshot_20240707_022328_com tencent mm](https://github.com/ypq123456789/TrafficCop/assets/114487221/c32c1ba1-1082-4f01-a26c-25608e9e3c29)

## Port Traffic Limit Feature (NEW)

TrafficCop now supports setting independent traffic limits for specific ports! This feature is ideal for scenarios requiring fine-grained traffic management for specific services (such as web servers, proxy services, etc.).

### Features

1. **Independent Port Traffic Statistics** - Use iptables to accurately track inbound and outbound traffic for specific ports
2. **Smart Configuration Sync** - Automatically sync machine configuration, also supports custom configuration
3. **Flexible Limit Strategies** - Supports two limit modes:
   - TC Mode: Throttle port traffic speed
   - Block Mode: Completely block port traffic when limit exceeded
4. **Configuration Validation** - Ensures port traffic limit does not exceed total machine traffic limit
5. **Automated Management** - Supports scheduled tasks for automatic monitoring and limiting

### Usage Logic

#### Scenario 1: Machine Has No Traffic Limit
When the machine has no configured traffic limit, setting a traffic limit for a specific port will:
1. Create port traffic configuration
2. Ask whether to sync configuration to machine traffic limit
3. If sync is selected, port configuration will automatically apply at machine level

#### Scenario 2: Machine Already Has Traffic Limit
When the machine already has a configured traffic limit, setting a traffic limit for a specific port will:
1. Check that port traffic limit is less than or equal to machine traffic limit
2. Default to inheriting other machine configurations (statistics mode, period, limit mode, etc.)
3. Allow custom configuration for special needs

### Installation and Configuration

#### Method 1: Via Manager Script (Recommended)
```bash
bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop-manager.sh)
```
Select "5) Install Port Traffic Limit"

#### Method 2: Run Script Directly
```bash
sudo mkdir -p /root/TrafficCop && \
curl -fsSL "https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/port_traffic_limit.sh" | tr -d '\r' > /root/TrafficCop/port_traffic_limit.sh && \
chmod +x /root/TrafficCop/port_traffic_limit.sh && \
bash /root/TrafficCop/port_traffic_limit.sh
```

### Configuration Options

During configuration, you need to provide:

1. **Port Number** - The port to limit traffic for (1-65535)
2. **Traffic Limit** - Maximum traffic allowed for the port (GB)
3. **Tolerance Range** - Buffer before triggering limit (GB)
4. **Configuration Method** - Choose to use machine configuration or custom configuration

If choosing custom configuration, you also need to set:
- Traffic statistics mode (outbound/inbound/total/max)
- Statistics period (monthly/quarterly/yearly)
- Period start day
- Limit mode (TC throttle/block)
- Throttle value (TC mode only)

### Related Commands

#### View Port Traffic Monitor Log
```bash
sudo tail -f -n 30 /root/TrafficCop/port_traffic_monitor.log
```

#### View Port Traffic Configuration
```bash
sudo cat /root/TrafficCop/port_traffic_config.txt
```

#### Manually Run Port Traffic Check
```bash
sudo /root/TrafficCop/port_traffic_monitor.sh --run
```

#### Remove Port Traffic Limit
```bash
sudo /root/TrafficCop/port_traffic_limit.sh --remove
```

#### Stop Port Traffic Monitoring
```bash
sudo pkill -f port_traffic_monitor.sh && \
crontab -l | grep -v "port_traffic_monitor.sh" | crontab -
```

### Usage Example

Suppose your machine has a 1TB total traffic limit, and you want to set a separate 200GB traffic limit for port 80 (web service):

1. Run the port traffic limit script
2. Enter port number: 80
3. Enter traffic limit: 200
4. Enter tolerance range: 10 (limiting starts when usage reaches 190GB)
5. Choose to use machine configuration (recommended) or custom configuration
6. Script will automatically set up a scheduled task to check port traffic every minute

When port 80 traffic reaches 190GB:
- **TC Mode**: Port speed will be limited to the set value (e.g., 20kbit/s)
- **Block Mode**: Port will be completely blocked, unable to receive or send data

### Technical Principles

Port traffic limit feature is implemented using:

1. **iptables** - Create rules to track traffic for specific ports
2. **tc (Traffic Control)** - Implement port-level traffic control and throttling
3. **HTB (Hierarchical Token Bucket)** - Hierarchical traffic control, allocating different bandwidth to different ports
4. **Packet Marking** - Use mangle table to mark packets for precise traffic classification

### Important Notes

1. Port traffic limit depends on iptables, ensure it's installed on your system
2. Port traffic statistics start from setup time, do not include historical traffic
3. It's recommended to run the main traffic monitor script first to ensure dependencies are installed
4. TC mode may have slight impact on port performance
5. Block mode completely prohibits port communication, use with caution
6. Currently only supports single port configuration, run script multiple times for multiple ports (multi-port support in development)

## Preset Configurations
### Alibaba Cloud CDT 200GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-200g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Alibaba Cloud CDT 20GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-20g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Alibaba Cloud Lightweight 1TB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/ali-1T && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Azure Student 15GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-15g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Azure Student 115GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/az-115g && cat /root/TrafficCop/traffic_monitor_config.txt
```

### GCP 625GB [High Traffic Ultimate Solution](https://www.nodeseek.com/post-115166-1):
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-625g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### GCP 200GB (Standard route with 200GB free traffic):
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/GCP-200g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Alice 1500GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/alice-1500g && cat /root/TrafficCop/traffic_monitor_config.txt
```
### Asia Cloud 300GB:
```
sudo curl -o /root/TrafficCop/traffic_monitor_config.txt https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/asia-300g && cat /root/TrafficCop/traffic_monitor_config.txt
```
## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ypq123456789/TrafficCop&type=Date)](https://star-history.com/#ypq123456789/TrafficCop&Date)

## Telegram Group:
https://t.me/+ydvXl1_OBBBiZWM1

## Support the Author
<span><small>Thank you very much for your interest in this project! Maintaining open-source projects requires a significant investment of time and energy. If you find this project valuable, please consider offering some support, even if it's just the cost of a cup of coffee.
Your generous assistance will motivate me to continue improving this project and make it more practical. It will also allow me to focus more on open-source community work. If you'd like to provide sponsorship, you can do so through the following channels:</small></span>
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
