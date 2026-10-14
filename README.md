<p align="center"><img src="design-assets/app-icon/skyinfo-launcher.png" width="96" alt="SkyInfo"></p>

# SkyInfo

Android 车机上的自定义信息仪表盘。查看原车隐藏或不便查看的信息，用可拖动的悬浮条补充状态栏，并连接 Home Assistant 或 MQTT。

当前版本 **0.8.2**，处于开发验证阶段。主要适配依据来自豹5闪充版 2026 款、Android 14 / CANFD；不代表支持所有比亚迪车型或固件。车辆功能由本机真实接口权限决定，推测控制持续标注待验证。

## 功能

- 可配置数值、状态、列表、设备、控制和历史曲线组件；标准／放大两档布局。
- 顶部悬浮条，自定义图标、字段、单位与位置；闲置自动锁定并点击穿透。
- Home Assistant 实体显示与控制；车辆传感器、控制实体归属同一设备。
- 高级自定义 MQTT，TLS／TCP、逐字段上报和会话命令校验。
- 本地 SQLite 历史，200 MB 容量预算，与 HA 连接状态无关。
- 内置网络 ADB 授权与桥接，无需 Shizuku；系统浅深色主题。

组件布局示例，来自离线自动化测试：

| 浅色 | 深色 |
| --- | --- |
| ![浅色仪表盘](app/test/goldens/light-信息.png) | ![深色仪表盘](app/test/goldens/dark-信息.png) |

## 使用

需要 Android 10 或更新版本，以及目标车机提供的本机网络 ADB / 无线调试接口。首次授权或配对需在系统中确认。安装后配置本机连接，添加仪表盘数据；HA/MQTT、悬浮显示和远程控制分别配置。

公共 APK 尚未发布。源码构建见[构建指南](docs/构建与发布.md)。新版本验证范围见[兼容性与验证](docs/验证与兼容性.md)，不将软件读回当成车辆物理效果验收。

## 开发

```sh
git clone --recurse-submodules https://github.com/skyboooox/SkyInfo.git
cd SkyInfo
python3 tools/check_project.py
./tools/docker.sh flutter analyze
./tools/docker.sh flutter test
./tools/test-mqtt.sh
```

Flutter 负责界面，Kotlin 负责采集、网络 ADB、悬浮窗、历史与通信。UI/UX 使用固定提交的 [Fluorite Design](docs/design/fluorite-design/DESIGN.md)，Figma 维护只使用 Desktop Bridge。

| 目录 | 内容 |
| --- | --- |
| `app/` | Flutter/Android 工程、确定性测试、视觉基线 |
| `tools/` | Docker 构建、资源生成与公开内容检查 |
| `docs/` | 当前需求、架构、协议、兼容性和构建说明 |
| `design-assets/` | 正式图标、矢量品牌源与来源清单 |
| `docs/design/fluorite-design/` | 固定版本的设计规范子模块 |

参见[文档导航](docs/README.md)、[贡献指南](CONTRIBUTING.md)、[隐私说明](docs/隐私与数据.md)和[第三方许可](THIRD_PARTY_NOTICES.md)。SkyInfo 是独立个人项目，与车辆厂商无隶属关系。

自有代码与原创资源采用 [GNU GPL-3.0](LICENSE)（SPDX: GPL-3.0-only）；第三方代码与资源各自遵循原许可。
