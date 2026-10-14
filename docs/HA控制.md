# HA 车辆发现与控制

车辆传感器与控制实体统一归属 `skyinfo_<deviceId>`。传感器保留 JSON 数字/文本类型、有效单位及统计定义；HA REST 的 state 文本不代表数值上报错误。

<a id="ha-entity-plan"></a>
## 设备发现

| 类型 | 条件 |
| --- | --- |
| switch | 可靠双态反馈与开/关参数 |
| select | 可靠离散状态与允许选项 |
| number | 前排设定温度 17–33°C、风量 1–7，整数 |
| button | 单参数动作、无可靠反馈或推测动作；每个允许参数一个按钮 |

启用 HA 远控后，通过 WebSocket `mqtt/subscribe` 订阅随机会话 Topic，通过 HA MQTT 服务发布发现与状态。需要 MQTT 集成及令牌订阅权限，不另存 Broker 密码；订阅失败在诊断 `ha_entity_subscription` 查看。

[设备级发现](https://www.home-assistant.io/integrations/mqtt/#device-discovery-payload)合并 516 个控制组件为一条配置。发现保留，状态非保留且只按变化发布。控制 Topic 每次重连更换，命令 QoS0、非保留，拒绝保留消息及旧会话。

availability 取实际桥接和反馈：无效质量、65535、未知状态或双区温度不一致时，有状态控件不可用。动作按钮不伪造当前状态；推测项保留验证标签，无额外推测开关。HA 注册表禁用状态需单独处理。

## 执行与回执

本地、HA 与 MQTT 共用固定车辆执行器，按实际用户/权限、SDK 方法、协议、允许参数及基线校验，不按完整固件或固定 UID 阻断，不设 APP P挡门槛。控制目录 173 项，参数见[元数据](../app/assets/entities.json)及[计划](../app/assets/controls.json)。动作码不是开度，单参数温度动作不是任意范围，点动保留停止任务。

| 回执 | 含义 |
| --- | --- |
| confirmed | 配置保存或可靠目标读回，不证明物理效果 |
| accepted_unconfirmed / partial_unconfirmed / timeout_unconfirmed | 已发送，结果未确认 |
| rejected / unsupported_state / unsupported_environment | 拒绝、基线无效或环境不匹配 |
| stop_unconfirmed / error / bridge_unavailable | 停止未确认、错误或桥接不可用 |

最后回执不是全部实体的当前状态。车辆动作不自动重试；停止或切换目标清空待发回执。主动停止尽力发布离线，强杀或网络故障无法保证即时送达；重连同步真实状态。

## 事件脚本

`tools/ha_control.py` 提供车辆、4 项 APP 操作及通用入口共 178 个脚本，通过设备同名标签筛选。脚本与原生设备实体可共存，不自动删除用户配置。

事件校验 target、整数 value、固定动作、command_id 及过去 30 秒至未来 2 秒时效。时间使用 HA 握手 HTTP Date 加单调时钟，最近 256 个命令持久去重。

## 恢复

Birth 主题默认 `homeassistant/status`、在线载荷 `online`，可配置；空主题关闭 Birth 订阅。Birth、HA 启动或手动重连只重发真实控制状态，不执行命令、不强制可用。恢复合并并有限重试，静态时不周期全量重发。见[HA Birth 说明](https://www.home-assistant.io/integrations/mqtt/#birth-and-last-will-messages)。

SkyInfo 显示与控制 HA 其他实体的规则见[实体接入](HA实体接入.md)，验证范围见[兼容性](验证与兼容性.md)。
