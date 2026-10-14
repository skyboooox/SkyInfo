# 自定义MQTT控制

自定义MQTT明确提供TLS及普通TCP两种连接，默认TLS；普通TCP首次保存提示未加密，确认后相同连接不重复提示，修改端口不会自动改变传输方式。TLS校验证书和主机名。

自定义MQTT位于“连接”的高级配置，默认连接为Home Assistant。MQTT远程控制默认关闭，启用后使用与[HA控制](HA控制.md)相同的173项车辆控制目录和4项APP操作，其中134项推测控制直接使用固定计划且始终保留待验证标记；车辆写入由当前用户的内置网络ADB桥接执行，实时检查接口兼容性、参数、权限和反馈。不提供任意FID、Shell命令或原始Binder写入入口。

## 主题与命令

设APP配置主题前缀为`skyinfo/example`：

| 主题 | 方向 | 内容 |
| --- | --- | --- |
| `skyinfo/example/meta` | APP发布 | 字段与控制定义、`command_target`、`command_session`、`control_enabled` |
| `skyinfo/example/heartbeat` | APP发布 | 当前连接的命令会话及采集状态 |
| `skyinfo/example/command` | APP订阅 | 一次性控制请求，发送端使用QoS1且retained=false |
| `skyinfo/example/command_result` | APP发布 | QoS1、非retained的命令执行回执，结果在`result`对象 |

Broker账号需允许发布自身主题及订阅自身`command`主题。每次实际建立MQTT连接生成新的随机`command_session`，发送端必须读取本次meta/heartbeat，不能缓存上次连接的会话。`command_target`对应APP的实体前缀，默认由本次安装的独立设备标识派生。

以下是协议示例，时间必须由发送端更新为当前UTC，不是可直接执行的命令：

```json
{
  "schema_version": 1,
  "target": "skyinfo_demo",
  "command_id": "unique_command_id",
  "command_session": "从当前meta或heartbeat读取",
  "issued_at": "2030-01-01T00:00:00Z",
  "expires_at": "2030-01-01T00:00:20Z",
  "action": "app_refresh",
  "value": 1
}
```

`command_id`为1—128位字母、数字、下划线或连字符，最近256个已接受ID持久化去重。`value`必须为整数，操作与范围见HA控制白名单或当前meta。载荷最大16KiB；无效JSON、错误目标、旧会话、重复ID、过期或越界请求不执行，拒绝原因进入诊断。

命令有效期最多30秒；设备时钟判断要求发出时间距当前时间不超过正负30秒且尚未超过expires_at。MQTT没有HA握手的HTTP Date校准，发送端与车机应保持时钟同步；偏差过大时拒绝，不自动改写设备时钟。HA使用服务器时间口径。

MQTT5订阅开启retain-as-published，拒绝带保留标志的控制。MQTT3.1.1拒绝新订阅时Broker重放的保留消息；协议会清除实时转发消息的保留标志，无法从接收端辨认发布者当时是否使用retained，因此发送端必须设置false。新连接会话与去重校验同时防止旧命令补放。[Paho订阅定义](https://github.com/eclipse-paho/paho.mqtt.java/blob/v1.2.5/org.eclipse.paho.mqttv5.client/src/main/java/org/eclipse/paho/mqttv5/common/MqttSubscription.java)、[MQTT3.1.1规范](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html)。

## 运行与回执

仅启用远程控制、不选择上传字段或关闭上报时，仍维护MQTT连接与30秒心跳。普通断线按1—60秒退避重连，网络可用时发起恢复；重连发布新meta并重新读取、发布一次当前已选状态。认证、配置、证书失败停止定时重试，配置或网络变化后重新判断。TLS和主机名检查不会降级。

命令通过校验后至多执行一次，车辆命令不重试。回执与命令执行分开：发送失败只重试回执，内存队列最多16条、保留120秒，间隔1—30秒；切换服务器/目标或主动停止会丢弃待发回执。进程终止后不补执行命令，回执队列也不跨进程保存。回执ID用于接收端去重，`confirmed`只表示配置保存或接口接受且目标读回，不能代替物理效果验收。诊断显示最后命令、发送错误和待发回执数量。

`meta.controls` 的 `options` 是允许的离散整数，`validation` 为 verified/inferred；上下界不代表中间值均允许。验证范围见[兼容性](验证与兼容性.md)。
