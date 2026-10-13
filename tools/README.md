# SkyInfo工具

从仓库根目录执行。生成工具只整理已确认目录/固定计划，不访问车辆、不扩大允许写入参数。

## Docker构建和回归

```sh
./tools/docker.sh flutter analyze
./tools/docker.sh flutter test
./tools/docker.sh bash -lc 'cd android && ./gradlew testDebugUnitTest'
./tools/test-mqtt.sh
./tools/docker.sh flutter build apk --release --target-platform android-arm64
```

`docker.sh`复用Flutter3.44.0/Android/NDK镜像及依赖缓存，仅挂载APP工程。`test-mqtt.sh`临时创建本机TLS Mosquitto，验证MQTT5及3.1.1，会在退出时清理容器与测试证书；不连接用户Broker。构建产物在`app/build/app/outputs/flutter-apk/`。

已有签名材料由`app/android/key.properties`与忽略的signing目录引用。`signing.sh`只在没有签名配置时初始化，不覆盖已用证书；私钥、密码和HA令牌不得提交。

## 生成资源

| 源 | 输出/工具 |
| --- | --- |
| 分类清单、适配结果、design-assets图标manifest | `generate_catalog.py` → Flutter/Android目录 |
| `app/assets/controls.json`（已审阅公开计划） | `generate_plans.py` → 26项 Kotlin 镜像 |
| `app/assets/inferred-controls.json`（固定推测计划） | `generate_plans.py` → 134项 Kotlin 镜像 |
| 原生13项定义、上述计划、图形推荐映射 | `generate_entities.py` → 173项实体、90图标资源 |
| `app/assets/i18n/zh_CN.json` | `generate_language.py` → Dart/Kotlin默认表及原生中文副本 |

按依赖顺序生成，中文文件是可编辑源，自动生成的`defaults.g.dart`、`NativeStrings.kt`及Android镜像资源不得手改。正常只需重新生成变动涉及的源；完整同步顺序：

```sh
python3 tools/generate_catalog.py
python3 tools/generate_plans.py
python3 tools/generate_entities.py
python3 tools/generate_language.py
python3 tools/check_project.py
```

新增名称由`resource_keys.py`提供稳定键，已有键保留；字段ID、动作ID、单位、用户自定义内容不翻译。图标按图形名称/用途分类，字段和实体推荐映射独立。固定计划的公开 JSON 是维护源，生成只同步 Kotlin 镜像，不推断新参数；来源和验证摘要见 docs/验证与兼容性.md。原始证据仍在维护者私有调查工程，不是构建前提。

## HA兼容工具

`ha_control.py`维护已有事件脚本，凭据从环境读取；它不会执行脚本。原生设备控制实体由APP运行时发现，不能用生成脚本数量代替新实体发现验收。

`check_project.py`检查文档链接、镜像资源、语言引用、图标哈希及目录一致性。默认输出到`app/qa/project-check/`；可用`--output app/qa/<本轮目录>`指定报告位置，避免覆盖历史QA；不对车机写入，也不把本机验证升级成物理控制验收。

## Figma Desktop Bridge

Figma只使用Desktop Bridge，覆盖读取、编辑、原型检查及导出。Bridge通过本机Figma中的插件连接访问原生节点；不调用官方Figma MCP、REST设计接口，也不在连接失败时切换到其他通道。

操作顺序：

1. 更新需求及宿主设计说明，读取固定版Fluorite规范。
2. 在本机Figma打开目标文件，启动已有Desktop Bridge插件，确认连接正常。
3. 核对fileKey、Page及节点，与[Figma交付说明](../docs/Figma设计.md#维护方式)一致后执行。
4. 保留可编辑组件、文字、向量及原型目标，导出受影响浅深画板；将节点ID、实际修改与检查结果写入本轮QA。
5. 按检查后的设计修改APP，再做行为/视觉验证。

导出优先在Bridge执行环境调用节点`exportAsync`；不得使用会自动回退REST的截图工具。Bridge断开时恢复已有连接并重新核对目标；操作超时先检查实际节点状态，避免重复创建或重复缩放。无法恢复时记录阻碍，不将旧导出当作新修改结果。临时连接脚本、凭据和本机端口不写入产品配置或作为固定依赖。

## Fluorite Design

`docs/design/fluorite-design/`是规范submodule，不进入APK或Docker构建上下文。通用规则和检查分别在其DESIGN.md/REVIEW.md维护；SkyInfo DESIGN.md只写平台差异。主题别名镜像由`check_design.py`检查，不复制或改写上游Web组件。

从仓库根目录初始化固定版本：

```sh
git submodule update --init --recursive -- docs/design/fluorite-design
```

仅用户明确要求升级时，获取上游、审阅指定提交，然后显式固定版本；不得用`--remote`自动追随。示例命令中的SHA必须替换为已审阅的真实提交：

```sh
git -C docs/design/fluorite-design fetch origin
git -C docs/design/fluorite-design checkout --detach <reviewed-sha>
git add .gitmodules docs/design/fluorite-design
```

升级后核对Fluorite规则、SkyInfo平台差异、主题镜像、Figma及受影响页面；提交子模块指针与宿主说明。本项目不在子模块直接修改规范；上游改动需在独立上游工程处理。只更新文档/依赖约定时检查链接、指针和生成资源；改UI行为时增加Docker行为/视觉验证。

从SkyInfo目录运行：

```sh
python3 tools/check_design.py
python3 tools/check_project.py --output app/qa/<本轮目录>
```

`check_project.py`包含规范检查；缺失初始化、工作树/暂存指针不一致、子模块脏修改或Palette与固定规范不一致会失败。文件清单排除外部submodule内部文件，原始QA与调查证据不作为无用资源清除。

公开配置工具：ha_control.py须显式提供--target，部署另提供--url，不使用测试服务器或设备名称默认值。tools/test-mqtt.sh启动仅本机临时Mosquitto TLS/普通TCP监听并清理临时证书；可传Gradle测试过滤参数，例如--tests app.skyinfo.vehicle.MqttTransportTest。不要将多个Gradle容器同时绑定同一缓存运行，避免跨容器锁等待。

网络ADB使用固定LibADB Android源码模块（仅超时/通知竞态补丁）、Conscrypt、Spake2与BouncyCastle；来源及许可见[依赖说明](../app/android/third_party/libadb/README.md)。网络协议测试只连接本机模拟adbd，不自动连接车机；配对码与密钥不得进入测试日志。
