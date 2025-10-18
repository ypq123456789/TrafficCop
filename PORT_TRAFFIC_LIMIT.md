# 端口流量限制功能 - 开发总结

## 概述

为TrafficCop项目成功添加了端口流量限制功能，允许用户为指定端口设置独立的流量限制。

## 新增文件

### 1. port_traffic_limit.sh
主要的端口流量限制脚本，包含以下核心功能：

#### 主要功能
- **端口流量统计**：使用iptables规则精确统计指定端口的入站和出站流量
- **流量限制**：支持两种模式
  - TC模式：使用tc (Traffic Control) 对端口流量进行限速
  - 阻断模式：超过流量限制时完全阻断端口
- **配置管理**：
  - 读取和写入端口配置
  - 与机器配置的智能同步
  - 配置验证（确保端口流量限制不超过机器总限制）
- **自动化监控**：通过crontab定时任务每分钟检查一次
- **周期管理**：支持月度、季度、年度流量周期

#### 技术实现
1. **iptables规则**：
   - 为入站和出站流量创建统计规则
   - 使用mangle表标记数据包
   - 精确跟踪特定端口的流量使用

2. **TC (Traffic Control)**：
   - 使用HTB (Hierarchical Token Bucket)实现分层流量控制
   - 为不同端口分配独立的带宽限制
   - 通过packet marking实现精确的流量分类

3. **流量计算**：
   - 支持四种统计模式：出站、入站、总计、最大值
   - 实时读取iptables计数器
   - 字节到GB的精确转换

#### 关键函数
- `init_iptables_rules()`: 初始化iptables规则用于流量统计
- `get_port_traffic_usage()`: 获取端口流量使用情况
- `check_and_limit_port_traffic()`: 检查并限制端口流量
- `port_config_wizard()`: 交互式配置向导
- `sync_to_machine_config()`: 同步配置到机器级别

## 修改的文件

### 2. trafficcop-manager.sh
在管理器脚本中添加了端口流量限制相关选项：

#### 新增功能
- 选项5：安装端口流量限制
- 选项7：解除端口流量限制
- 日志查看选项中添加端口流量监控日志
- 配置查看选项中添加端口流量配置

#### 修改内容
- `install_port_traffic_limit()`: 安装端口流量限制功能
- `remove_port_traffic_limit()`: 解除端口流量限制
- `view_logs()`: 添加端口流量监控日志查看
- `view_config()`: 添加端口流量配置查看
- `stop_all_services()`: 添加停止端口流量监控服务
- `show_main_menu()`: 更新菜单选项
- `main()`: 更新主函数处理新选项

### 3. README.md
添加了详细的端口流量限制功能说明：

#### 新增章节
- **端口流量限制功能（新增）**
  - 功能特点
  - 使用逻辑（两种场景）
  - 安装和配置方法
  - 配置选项说明
  - 相关命令
  - 使用示例
  - 技术原理
  - 注意事项

#### 更新内容
- 管理器脚本功能列表更新
- 添加了完整的使用文档和示例

### 4. README_EN.md
添加了英文版的端口流量限制功能说明，内容与中文版对应。

## 功能实现逻辑

### 场景一：机器未限制流量
```
用户设置端口流量限制
  ↓
创建端口配置
  ↓
询问是否同步到机器配置
  ↓
如果同步：端口配置 → 机器配置
```

### 场景二：机器已限制流量
```
用户设置端口流量限制
  ↓
验证：端口限制 ≤ 机器限制
  ↓
选择配置方式：
  - 使用机器配置（推荐）
  - 自定义配置
  ↓
保存端口配置
```

## 技术栈

1. **iptables**: 流量统计和过滤
2. **tc (Traffic Control)**: 流量控制和限速
3. **HTB (Hierarchical Token Bucket)**: 分层令牌桶算法
4. **bash**: 脚本语言
5. **crontab**: 定时任务调度

## 配置文件

### port_traffic_config.txt
```bash
PORT=端口号
PORT_TRAFFIC_LIMIT=流量限制(GB)
PORT_TRAFFIC_TOLERANCE=容错范围(GB)
PORT_TRAFFIC_MODE=流量统计模式
PORT_TRAFFIC_PERIOD=统计周期
PORT_PERIOD_START_DAY=周期起始日
PORT_LIMIT_SPEED=限速值(kbit/s)
PORT_MAIN_INTERFACE=网络接口
PORT_LIMIT_MODE=限制模式
```

## 日志文件

- `port_traffic_monitor.log`: 端口流量监控日志
- 记录流量使用、限制触发、配置变更等信息

## 使用示例

### 示例1：为Web服务器（端口80）设置200GB限制
```bash
# 运行脚本
sudo /root/TrafficCop/port_traffic_limit.sh

# 输入配置
端口号: 80
流量限制: 200 GB
容错范围: 10 GB
配置方式: 使用机器配置

# 结果
当端口80流量达到190GB时，自动触发限制
```

### 示例2：为SSH服务（端口22）设置50GB限制并自定义配置
```bash
# 运行脚本
sudo /root/TrafficCop/port_traffic_limit.sh

# 输入配置
端口号: 22
流量限制: 50 GB
容错范围: 5 GB
配置方式: 自定义配置
统计模式: 出站流量
统计周期: 月度
限制模式: TC模式
限速值: 50 kbit/s
```

## 命令速查表

| 操作 | 命令 |
|------|------|
| 安装端口流量限制 | `bash <(curl -sL https://raw.githubusercontent.com/ypq123456789/TrafficCop/main/trafficcop-manager.sh)` |
| 查看端口流量日志 | `sudo tail -f -n 30 /root/TrafficCop/port_traffic_monitor.log` |
| 查看端口配置 | `sudo cat /root/TrafficCop/port_traffic_config.txt` |
| 手动运行检查 | `sudo /root/TrafficCop/port_traffic_monitor.sh --run` |
| 解除端口限制 | `sudo /root/TrafficCop/port_traffic_limit.sh --remove` |
| 停止端口监控 | `sudo pkill -f port_traffic_monitor.sh` |

## 注意事项

1. ✅ 端口流量限制基于iptables，确保系统已安装
2. ✅ 流量统计从设置时开始，不包含历史流量
3. ✅ 建议先运行主流量监控脚本安装依赖
4. ⚠️ TC模式可能对端口性能有轻微影响
5. ⚠️ 阻断模式会完全禁止端口通信，谨慎使用
6. 📝 目前仅支持单端口配置（多端口支持开发中）

## 未来改进方向

1. **多端口支持**: 允许同时配置多个端口
2. **端口组管理**: 将多个端口作为一组进行管理
3. **流量分析**: 添加流量使用趋势分析和预测
4. **通知集成**: 集成Telegram/PushPlus通知端口流量状态
5. **Web界面**: 开发Web管理界面
6. **API接口**: 提供RESTful API用于远程管理

## 测试建议

1. 在测试环境中验证功能
2. 测试场景：
   - 机器未限流 + 新端口配置
   - 机器已限流 + 端口配置验证
   - TC模式限速效果
   - 阻断模式功能
   - 周期重置功能
3. 监控日志确认功能正常运行
4. 验证iptables规则正确性

## 贡献者

本功能由 GitHub Copilot 协助开发完成。

## 版本信息

- **版本**: 1.0.0
- **发布日期**: 2025-10-18
- **兼容性**: TrafficCop v1.0.84+

## 许可证

遵循项目主许可证。
