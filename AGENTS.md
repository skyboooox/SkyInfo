# SkyInfo 工作约定

本仓库独立维护 SkyInfo，APP 在 `app/`，工具在 `tools/`。先读[需求说明](docs/需求说明.md)、[开发状态](docs/开发状态.md)及[架构](docs/项目规划.md)。后续用户明确要求覆盖旧方案。

所有 UI/UX 遵循固定 submodule 的 [AGENTS](docs/design/fluorite-design/AGENTS.md)、[DESIGN](docs/design/fluorite-design/DESIGN.md) 与 [REVIEW](docs/design/fluorite-design/REVIEW.md)，宿主差异只在 [DESIGN.md](DESIGN.md) 维护。缺失时运行 `git submodule update --init --recursive`；仅用户明确要求时升级，不直接修改子模块。

UI/UX 按文档 → 设计 → 代码 → 验证执行。Figma 读取、编辑、原型检查和导出仅使用 Desktop Bridge，核对目标文件/Page，保留可编辑节点。连接失败恢复已有 Bridge，不调用官方 MCP/REST、不用截图冒充设计交付。

优先 Docker 构建，复用 Flutter/Android、OkHttp/Paho/SQLite/LibADB。界面、模型、采集、通信和生成资源分层维护，不机械拆分生成计划。语言只编辑 `app/assets/i18n/zh_CN.json`；用工具生成镜像，不手改生成文件。

采集订阅优先，历史统一本地；默认 HA，高级配置 MQTT。信息、悬浮窗、连接、设置四页，车辆/HA 控制通过仪表盘实体，不另设车辆控制菜单。默认标准，保留已保存档位；应用启动恢复采集并检查本机网络 ADB，未授权与不可达分开提示一次，不替用户确认系统 RSA、不自动开启新的上传/悬浮/远控。

开发期不要求向前兼容旧配置/历史，可在明确范围内清理 SkyInfo 本机数据；不改写原始调查、不清理其他设备。动态判断 Android 用户、实际权限、协议与方法兼容性；不按完整固件或固定 UID 阻断，不设置 APP P挡门槛。推测控制沿用固定计划并持续标记待验证，不扩大参数、自动试写或将 accepted/软件读回当成物理效果。

网络 ADB 只连接本机 adbd，无 Shizuku 依赖，独立密钥与配对码不进入导出/日志/Git。实车默认只读，安装/授权/写入须有对应授权。车屏识别和 ADB 点击依用户要求交给 GPT 5.6 Luna low；其他工作不因此自动委托。

公共仓库仅保留源码、当前文档、正式资源与匿名测试。禁止提交签名、令牌、个人服务器/设备数据、实车截图、厂商 APK/JAR、旧检查点或私有 QA。原件保留在维护者本地调查工程，不是普通构建依赖。提交前运行 `python3 tools/check_public.py` 与 `python3 tools/check_project.py`，代码改动按范围做 Docker 回归。

自有代码与原创资源采用 GPL-3.0-only，第三方保留原许可。首次公开、推送或 APK 发布前必须由维护者人工确认已审阅内容；CI 不自动发布、不使用正式签名。发布步骤和 LGPL 依赖材料见[构建与发布](docs/构建与发布.md)及[许可清单](THIRD_PARTY_NOTICES.md)。
