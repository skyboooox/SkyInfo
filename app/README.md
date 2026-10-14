# SkyInfo 工程

Flutter 主界面 + Kotlin 原生运行层，包名 `app.skyinfo.vehicle`；版本和发行渠道见[构建指南](../docs/构建与发布.md#版本与升级)。

从仓库根目录执行 [构建与发布](../docs/构建与发布.md) 的命令。`lib/` 分为 UI、domain、data 和 l10n；Android 原生职责见[架构](../docs/项目规划.md)。正式目录、计划与语言镜像随源码维护；生成工具在 `../tools/`。

`test/` 和 Android `src/test/` 保留匿名夹具、模拟服务及视觉基线。`qa/` 为本机生成报告目录，默认忽略；签名、运行配置与构建产物均不提交。
