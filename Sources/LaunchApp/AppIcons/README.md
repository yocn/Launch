# Launch 应用图标

六张透明底主图：aperture（四瓣开合）/ grid（单色九宫格）/ tiles（蓝紫四格），每套 light / dark。
依据用户选定的三个方案由内置 image_gen 分别提取并独立生成，设计稿及提示词在 design/icon-concepts-2026-10-22。

SwiftPM 将本目录打进 Launch_LaunchApp.bundle。安装脚本从 grid-light.png 生成默认 AppIcon.icns；运行时仅使用公开的 applicationIconImage 接口切换，不改写签名资源或添加 FinderInfo。

用户最终确认的是四瓣、黑白九宫格、蓝紫 2×2 玻璃格（右上角倾斜）。折光 L 仅为早期候选，不接入设置。
