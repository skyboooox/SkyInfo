# SkyInfo 工作约定

工程在 `app/`，工具在 `tools/`。先读[需求](docs/需求说明.md)、[架构](docs/项目规划.md)和[验证与兼容性](docs/验证与兼容性.md)。

## 设计与开发

- UI/UX 遵循固定子模块的 [AGENTS](docs/design/fluorite-design/AGENTS.md)、[DESIGN](docs/design/fluorite-design/DESIGN.md) 与 [REVIEW](docs/design/fluorite-design/REVIEW.md)；宿主差异只写 [DESIGN.md](DESIGN.md)。缺失时初始化子模块，仅明确要求时升级，不直接修改上游。
- UI/UX 按文档 → 设计 → 代码 → 验证执行。Figma 仅使用 Desktop Bridge，核对文件/Page，保留可编辑节点；断开先恢复，不调用官方 MCP/REST。
- 优先 Docker 与现有库，界面、模型、采集、通信分层。语言只编辑 `app/assets/i18n/zh_CN.json`，生成文件不手改。
- 文档维护功能、接口、操作和验证边界。同一事实只维护一处，其他文档引用；讨论、请求记录及开发过程不进入产品文档。版本记录只列发行功能与可见变化，验收原件存放在本机忽略目录。

## 数据与实车

- 存储格式兼容策略见构建指南；数据清理仅限 SkyInfo，不改原始调查或其他设备数据。
- 控制保持固定参数与实际权限校验，推测项保留待验证。接口接受、软件读回和物理效果分别判断，不自动试写新功能。
- 实车默认只读；安装、授权和写入须有对应授权。车屏识别及 ADB 点击交给 GPT 5.6 Luna low；其他工作不因此自动委托。
- 网络 ADB 只连接本机，密钥/配对码不进入导出、日志或 Git。

## 检查与发布

运行 `python3 tools/check_public.py`、`python3 tools/check_project.py`；代码改动按范围做 Docker 回归。凭据、实车数据、厂商二进制和私有 QA 不提交；Gradle wrapper 可随源码维护。

自有代码及原创资源为 GPL-3.0-only，第三方保留原许可。首次公开和 APK 发布须人工确认；CI 不发布或使用正式签名。步骤见[构建与发布](docs/构建与发布.md)。
