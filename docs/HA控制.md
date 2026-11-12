# HA 车辆发现与控制

车辆传感器归属主设备 `skyinfo_<deviceId>`；控制按空调、各位置座椅、车窗、门锁、灯光、后视镜、车载显示、底盘、驾驶辅助、充电与电源等功能设备分组。各组具有稳定标识，并作为主车机的子设备。传感器保留 JSON 数字/文本类型、有效单位及统计定义；HA REST 的 state 文本不代表数值上报错误。

<a id="ha-entity-plan"></a>
## 设备发现

| 类型 | 条件 |
| --- | --- |
| switch | 可靠双态反馈与开/关参数 |
| select | 可靠离散状态与允许选项；风量 1–7 档；多参数操作的允许参数列表 |
| number | 前排设定温度 17–33°C，整数 |
| button | 单参数动作 |

启用 HA 远控后，通过 WebSocket `mqtt/subscribe` 订阅随机会话 Topic，通过 HA MQTT 服务发布发现与状态。需要 MQTT 集成及令牌订阅权限，不另存 Broker 密码。连接页独立显示远控的连接、订阅、恢复、拒绝与就绪状态。诊断 `ha_entity_subscription` 只在命令 Topic 确实订阅成功时为真；`ha_mqtt_subscription` 分别保留命令与 Birth 订阅的状态、错误码、尝试次数及下次恢复时间。订阅超时为10秒；暂时错误以2、4、8、16、30秒上限退避恢复，保持同一个已认证 WebSocket。认证或权限拒绝停止自动尝试，显式重连或连接配置变更后重新尝试。

[设备级发现](https://www.home-assistant.io/integrations/mqtt/#device-configuration-with-device-discovery)通过 `child_devices` 将173个控制组件合并为一条配置，按 Home Assistant 2026.11.0 的发现契约实现。发现保留；状态非保留，平时按变化发布。发现更新后依次间隔1、3、7秒完成三轮有限状态同步，覆盖HA处理发现和订阅状态Topic的窗口。控制 Topic 每次重连更换，命令 QoS0、非保留，拒绝保留消息及旧会话。

availability 表示远控订阅是否就绪；有状态控件还校验可靠反馈：无效质量、65535、未知状态或双区温度不一致时，有状态控件不可用。动作按钮不伪造当前状态；多参数操作的名称带“操作”，列表只代表请求参数，使用 `optimistic=false`、真实状态Topic及 `None` 状态模板，选择后仍保持unknown。unknown不阻止操作。HA控件可用表示订阅与反馈满足条件；实际车辆执行仍逐次校验桥接、权限及固定计划，结果由回执说明。可靠反馈控件继续只使用真实读回；推测项保留验证标签。HA 注册表禁用状态需单独处理。

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

Birth 主题默认 `homeassistant/status`、在线载荷 `online`，可配置；空主题关闭 Birth 订阅。Birth、HA 启动或手动重连触发发现恢复及有限的真实状态同步，不执行命令、不强制可用。恢复合并并有限重试，静态时不周期全量重发。见[HA Birth 说明](https://www.home-assistant.io/integrations/mqtt/#birth-and-last-will-messages)。

SkyInfo 显示与控制 HA 其他实体的规则见[实体接入](HA实体接入.md)，验证范围见[兼容性](验证与兼容性.md)。

控制实体仅在启用远控后发布发现；发现成功立即按HA目标、设备标识及前缀记录发布状态。关闭远控后，已发布目标发送不可用状态，完整送达后结束本轮离线更新，重启继续未完成部分。升级既有HA配置时执行一次兼容离线更新，保留实体；新安装及新目标在远控关闭时保持未发布。发现、状态及回执的发送与其他上报共享退避，恢复条件见[发送与恢复](架构.md#发送与恢复)。

## 发现升级

沿用 `homeassistant/device/skyinfo_<deviceId>_controls/config`、主设备标识及既有可靠控件的component ID和unique_id，通过同一发现更新把组件移动到对应子设备；HA 2026.11.0支持此契约。单参数动作继续保留原button ID。多参数动作合并为select，风量从number改为档位select，属于实体类型变化；自动化和仪表盘中对这些旧实体的引用须改为对应select及其允许选项。

迁移只在该目标已有本应用控制发现的记录时进行：先在同一发现payload中将被替代组件列为仅含platform的删除项，再发布完整分组配置；成功后按HA目标和设备标识记录完成。失败或进程中断可重复恢复。保留的控件通过原位更新延续注册信息，被替代实体的用户定制不会自动复制。迁移精确作用于本应用原聚合发现中的被替代组件。首次发现和实际迁移均需检查HA发现处理结果；本地模拟不代替安装后的授权验收。
