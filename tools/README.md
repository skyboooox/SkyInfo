# 工具

从仓库根目录执行。构建、测试与签名命令见[构建指南](../docs/构建与发布.md)。Docker 复用固定镜像及依赖缓存，只挂载 APP 工程；不要同时运行共用 Gradle 缓存的多个构建容器。

## 资源生成

| 维护源 | 工具与输出 |
| --- | --- |
| 分类、适配结果、图标 manifest | `generate_catalog.py` → Flutter/Android 字段目录 |
| `app/assets/controls.json`、`inferred-controls.json` | `generate_plans.py` → 固定计划 Kotlin 镜像 |
| 原生定义、计划、推荐映射 | `generate_entities.py` → 实体与图标资源 |
| `app/assets/i18n/zh_CN.json` | `generate_language.py` → Dart/Kotlin 默认表及 Android 语言副本 |

```sh
python3 tools/generate_catalog.py
python3 tools/generate_plans.py
python3 tools/generate_entities.py
python3 tools/generate_language.py
./tools/docker.sh dart format lib/l10n/defaults.g.dart
python3 tools/check_project.py
```

只生成受影响资源，完整同步按上表顺序。`resource_keys.py` 维护稳定语言键；字段/实体/图标 ID、单位及用户名称不翻译。固定计划生成只做镜像，不推断参数或访问车辆。

## 检查与辅助脚本

- `check_project.py`：文档链接、语言/目录镜像、图标哈希、设计依赖。默认输出 `app/qa/project-check/`，可用 `--output .local/check` 指定位置。
- `check_public.py`：当前公开源码（含未跟踪文件）中的凭据、私人路径与异常二进制；公开前另用 Gitleaks 扫描历史。
- `test-mqtt.sh`：独立临时 Docker 网络中的 TLS/TCP Mosquitto，覆盖 MQTT5/3.1.1，退出清理。可追加 `--tests app.skyinfo.vehicle.MqttTransportTest`。
- `signing.sh`：缺少配置时初始化本机签名，不覆盖已有密钥。
- `ha_control.py`：生成/部署事件脚本，不执行控制；显式指定 `--target`，部署另提供 `--url`，令牌从环境读取。

网络 ADB 测试仅连接模拟 adbd；依赖与补丁见 [LibADB](../app/android/third_party/libadb/README.md)。

## Figma Desktop Bridge

1. 更新需求及宿主说明，读取固定 Fluorite 规范。
2. 在 Figma 打开[目标文件](../docs/Figma设计.md)，启动已有 Bridge，核对 fileKey、Page 和节点。
3. 保留文字、组件、向量及原型目标，用 `exportAsync` 导出受影响浅深画板。
4. 核对设计后修改 APP，完成行为/视觉回归；节点和操作记录留本机 QA。

Figma 所有读取、修改和导出仅用 Desktop Bridge。断开先恢复，不回退官方 MCP/REST；超时先读取实际节点状态，避免重复修改。临时连接脚本不成为产品依赖。

## Fluorite Design

`docs/design/fluorite-design/` 为固定规范子模块，不进入 APK 或构建上下文；主题别名由 `check_design.py` 校验。初始化：

```sh
git submodule update --init --recursive -- docs/design/fluorite-design
python3 tools/check_design.py
```

仅明确要求时升级：审阅提交、detached checkout、提交 gitlink，再核对主题、Figma 与受影响页面；不用 `--remote`，不直接修改子模块。
