# Gradle 构建入口

Wrapper 由 Gradle 9.1.0 的 wrapper task 生成，采用 Apache-2.0；[许可](LICENSE-Gradle.txt)。脚本、JAR 与 properties 一起维护，不能依赖 Flutter 首次 APK 构建隐式生成后才能运行原生测试。

分发 ZIP 的 SHA-256 固定在 properties；JAR 已与 Gradle 官方 9.1.0 wrapper 校验值核对。升级时从正式 Gradle task 生成，再核对 [官方分发](https://services.gradle.org/distributions/) 的 ZIP / wrapper SHA-256，提交四个文件，不替换为厂商 SDK JAR。
