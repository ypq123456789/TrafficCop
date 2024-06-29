# 脚本功能
监控VPS流量使用，到达限制自动断网，保留SSH端口可用
# 一键脚本
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop.sh)"
# 脚本逻辑
首先，这个脚本会判断当前主要使用的网卡名称是什么，选择主要网卡进行流量限制。

其次，这个脚本会要求用户输入限制流量统计的模式，包括四种，第一种是只计算出站流量，第二种是只计算进站流量，第三种是出进站流量都计算，第四种是出站和进站流量只取大。

然后，这个脚本会要求用户输入流量计算周期（默认为月，允许输入季度、年），以及流量周期计算的起始日期。

然后，这个脚本会要求用户输入要限制的流量大小，然后再输入容错范围，后台计算限制流量为要限制的流量大小减去容错范围，单位均为GB。

最后，这个脚本会每隔1分钟检测当前的流量消耗，如果达到了限制值，那么就会停止除了ssh端口（有可能不是22端口，所以要提前检测）以外的所有流量传输。

并且，这个脚本会在下一个流量周期到达时，自动解禁所有网卡。
# 脚本特色
- ▪️四种模式非常全面，覆盖了几乎市面上所有vps的流量计费模式。
- ▪️允许用户自定义流量计算周期和流量周期计算起始日。
- ▪️允许用户自定义流量容错范围。
- ▪️检查SSH端口而非直接选择22端口。
- ▪️每一个要求用户输入的参数，脚本每次运行都会读取这些参数，并且会询问用户是否需要更改。
- ▪️时刻监控流量运行情况定时输出当前的流量统计结果，并保存到日志文件中，并且在脚本运行的最开始提示用户当前流量统计结果。
- ▪️脚本支持自动更新。
- ▪️使用 tc (Traffic Control) 来限制带宽，而不是完全阻断流量。这样可以确保 SSH 连接始终可用。
- ▪️新增了 LIMITED_RATE 配置项，用于设置限制时的带宽（默认为 20 Kbps）。
- ▪️在脚本开始时，会询问用户确认检测到的 SSH 端口是否正确。

这个版本**更安全**，因为：
- ▪️它不会完全切断网络连接，只是限制带宽。
- ▪️SSH 连接始终可用，即使在限制模式下。
- ▪️可以远程管理和调整限制。
