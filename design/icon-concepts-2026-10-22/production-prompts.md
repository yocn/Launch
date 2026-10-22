# 已接入的三套应用图标

最终选择：四瓣开合（aperture）、单色九宫格（grid）、蓝紫四格（tiles）。每套有浅、深色透明 PNG。折光 L 未接入。

使用内置 image_gen，transparent_background=true，非 CLI。主图在 Sources/LaunchApp/AppIcons/。安装包使用 grid-light 生成 icns，设置中的选择保存到 UserDefaults。

## 原始图提取

以对应概念展示图为编辑目标，每次仅提取左侧浅色或右侧深色图标，保留完整圆角底板和原始符号、颜色、材质、布局；移除展示背景、另一枚图标和分割线。正方形至少 1024 像素，底板居中占约 80% 宽度，四周透明。无文字、水印，不重新设计。

蓝紫四格提取使用用户最后附带的原稿，保持四个蓝紫玻璃格与右上角的倾斜，不能替换成九宫格或字母 L。

+## aperture 浅色透明图边缘整理

Use case: precise-object-edit / background-extraction. Edit target: supplied single production macOS icon. Fix ONLY the ragged white artifacts and stray disconnected pixels outside and above the rounded square base. Outside silhouette must be perfectly clean smooth antialiased transparent alpha, with NO white fringe, NO stray specks, NO noise halo. Preserve exact interior artwork, tile count, arrangement, original light porcelain base, colors, materials, lighting and proportions. Do not redesign the symbol or base. Keep square 1280 x 1280 canvas, icon base occupying 80 percent width, centered with ten percent transparent margin. One icon, no text, no mockup. Genuine transparent background.

## grid 浅色透明图边缘整理

Use case: precise-object-edit / background-extraction. Edit target: supplied single production macOS icon. Fix ONLY the ragged white artifacts and stray disconnected pixels outside and above the rounded square base. Outside silhouette must be perfectly clean smooth antialiased transparent alpha, with NO white fringe, NO stray specks, NO noise halo. Preserve exact interior artwork, tile count, arrangement, original light porcelain base, colors, materials, lighting and proportions. Do not redesign the symbol or base. Keep square 1280 x 1280 canvas, icon base occupying 80 percent width, centered with ten percent transparent margin. One icon, no text, no mockup. Genuine transparent background.

## tiles 浅色透明图边缘整理

Use case: precise-object-edit / background-extraction. Edit target: supplied single production macOS icon. Fix ONLY the ragged white artifacts and stray disconnected pixels outside and above the rounded square base. Outside silhouette must be perfectly clean smooth antialiased transparent alpha, with NO white fringe, NO stray specks, NO noise halo. Preserve exact interior artwork, tile count, arrangement, original light porcelain base, colors, materials, lighting and proportions. Do not redesign the symbol or base. Keep square 1280 x 1280 canvas, icon base occupying 80 percent width, centered with ten percent transparent margin. One icon, no text, no mockup. Genuine transparent background.

