# Figma 与设计资源

UI/UX 统一遵循固定子模块的 [Fluorite Design](design/fluorite-design/DESIGN.md) 和 [REVIEW](design/fluorite-design/REVIEW.md)，车机差异仅在 [宿主 DESIGN](../DESIGN.md) 维护。

## Desktop Bridge

Figma 读取、编辑、原型检查、截图和资源导出只使用 Desktop Bridge，通过本机原生 Plugin API 操作。Bridge 断开时恢复已有插件，不使用官方 MCP/REST 或把 APP 截图冒充设计交付。设计不是源码构建依赖。

先核对目标文件与 Page，保留文字、矢量、组件实例及原型连接。UI/UX 按文档 → 设计 → 代码 → 验证执行；导出受影响浅深画板，操作节点与检查记录写本机 QA，不公开个人诊断。

## SkyInfo 画板

当前设计文件 [ToGPT / SkyInfo](https://www.figma.com/design/T7jZP95JDLgkNKUI5NeEqy/ToGPT?node-id=140-896)，唯一 SkyInfo Page 为 `140:896`（成品）。一个项目一个 Page。

四页和编辑器覆盖信息、悬浮条、连接与设置；数据优先的创建流程、实体控制详情、删除/清空确认和共享控件维护在同一套设计。主页大小采用实际车机逻辑视口，默认标准；启动引导复用确认对话框。

| 资源 | 节点 |
| --- | --- |
| 启动器品牌矢量组 | 254:34454 |
| 传统全彩图标 / 自适应前景 / 单色 | 254:34455 / 254:34459 / 254:34463 |
| 浅色授权 / 不可达引导 | 254:34467 / 254:34490 |
| 深色授权 / 不可达引导 | 254:34513 / 254:34536 |

正式图标、矢量源及哈希在 [design-assets](../design-assets/app-icon/README.md)。设计预览数值是快照或示意，不能称实时采样/已执行命令；APP 可见预览使用实际缓存，缺失显示空值。
