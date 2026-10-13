# LibADB Android 3.1.1

来源：https://github.com/MuntashirAkon/libadb-android/tree/3.1.1 ，提交c849886ebc6d48e7b46d967e78a6bb65c90c3b74。选择Apache-2.0许可；原始文件的版权与SPDX、COPYING、LICENSES保留。Spake2与BouncyCastle继续通过固定版本库引入，不复制示例APP、构建包装器或上游Git。

SkyInfo补丁只有网络恢复边界：TCP connect 3秒、首次ADB/TLS握手8秒、配对读取10秒、OPEN等待8秒；OPEN按真实远端ID循环等待，避免提前OKAY丢失通知。认证、编码、TLS/PAKE和流协议仍使用上游实现。连接建立后的长期SDK事件流不设置空闲读取超时。Android库构建配置适配宿主AGP。

修改此目录必须同步上述补丁说明及本机协议回归；不可删改上游许可或把模拟握手称为实车/Android无线配对验收。
