# 第三方代码与资源

SkyInfo 自有代码许可不覆盖下列资源。原版权、许可正文和来源保持独立；依赖版本见 Gradle 配置与 Flutter 锁文件。

| 内容 | 来源与版本 | 许可 / 仓库内材料 |
| --- | --- | --- |
| Gradle Wrapper | [9.1.0](https://github.com/gradle/gradle) | [Apache-2.0](app/android/gradle/LICENSE-Gradle.txt)，JAR 与 ZIP 校验值核对 |
| LibADB Android | [3.1.1](https://github.com/MuntashirAkon/libadb-android/tree/3.1.1)，c849886ebc6d48e7b46d967e78a6bb65c90c3b74 | 选择 Apache-2.0；部分 BSD-3-Clause/MIT，见 [COPYING](app/android/third_party/libadb/COPYING) 与 [LICENSES](app/android/third_party/libadb/LICENSES/) |
| SPAKE2 Android | [2.2.1](https://github.com/MuntashirAkon/spake2-java/tree/2.2.1) | LGPL-3.0，未修改；[许可与构建来源](app/assets/licenses/NOTICE-network-adb.txt)、[LGPL](app/assets/licenses/spake2-LGPL-3.0.txt)、[GPL](app/assets/licenses/spake2-GPL-3.0.txt) |
| Conscrypt | [2.5.3](https://github.com/google/conscrypt) | Apache-2.0 |
| Bouncy Castle | [1.81](https://www.bouncycastle.org/about/license/) | Bouncy Castle License |
| Okio | [3.6.0](https://github.com/square/okio/tree/parent-3.6.0) | Apache-2.0，OkHttp 传递依赖 |
| OkHttp | [4.12.0](https://github.com/square/okhttp) | Apache-2.0 |
| Eclipse Paho MQTT | [1.2.5](https://github.com/eclipse-paho/paho.mqtt.java) | 选择 EDL-1.0，保留上游版权与许可 |
| AndroidSVG | [1.4](https://github.com/BigBadaboom/androidsvg) | Apache-2.0 |
| Kotlin 标准库 | [2.3.20](https://github.com/JetBrains/kotlin/tree/v2.3.20) | Apache-2.0 |
| Flutter / Dart | [Flutter](https://github.com/flutter/flutter) | BSD-3-Clause；包版本见 [pubspec.lock](app/pubspec.lock) |
| package_info_plus | [Plus Plugins](https://github.com/fluttercommunity/plus_plugins/tree/main/packages/package_info_plus) | BSD-3-Clause |
| url_launcher | [Flutter Packages](https://github.com/flutter/packages/tree/main/packages/url_launcher) | BSD-3-Clause |
| flutter_svg | [官方项目](https://github.com/flutter/packages/tree/main/third_party/packages/flutter_svg) | MIT |
| Tabler Icons | [3.49.0](https://github.com/tabler/tabler-icons)，a4ce1404bc6d24d3c365afe7b258d6bf6f48d62d | [MIT](design-assets/icons/LICENSE-tabler.txt)，来源/几何哈希见 [manifest](design-assets/icons/manifest.json) |
| ChillDINGothic Std | [ChillDIN](https://github.com/Warren2060/ChillDIN-ChillDINGothic) | [SIL OFL 1.1](app/assets/fonts/LICENSE-ChillDIN.txt)，保留原字体及保留名称 |
| IBM Plex Mono | [IBM Plex](https://github.com/IBM/plex) | [SIL OFL 1.1](app/assets/fonts/LICENSE-IBM.txt) |
| Fluorite Design | [固定子模块](https://github.com/skyboooox/fluorite-design)，0b250aab289b5db07263dcd3f81bfcce66eb2963 | 规范引用；固定提交无仓库级 LICENSE，不将其归为 SkyInfo 自有许可、不复制其 Web 代码；字体保留独立许可 |

LibADB 的超时/通知竞态补丁完整源码与说明位于 [third_party/libadb](app/android/third_party/libadb/README.md)。网络 ADB 打包许可位于 APK 的 `assets/flutter_assets/assets/licenses/`；其中同时保留直接原生依赖及 Okio 的上游许可/NOTICE，来源与版本见本表及 Gradle 依赖；完整依赖清单随公开源码提供。

SPAKE2 使用未修改的公开 Android 依赖。重新构建：克隆上述 2.2.1 标签及其子模块，遵循上游 Gradle/CMake 配置；使用本项目公开工程替换该依赖并构建自己的 APK，安装前需卸载证书不同的包。APK Release 随附对应 SPAKE2 Java/C 源码、上游构建配置及重建说明；自有应用源码独立附包。不得只用远程链接替代对应源码材料。

车辆 SDK 由目标车机系统提供，不随 APP 分发。
