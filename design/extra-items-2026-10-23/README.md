# 非应用条目类型角标预览

2026-10-23：用户确认当前角标大小合适。网址与快捷指令优先，角标统一放在左下角。需求仍在讨论，未实现功能。

![浅深色与小尺寸效果](type-badges-preview.png)

使用内置 image_gen，非 CLI；transparent_background=false。此图为交互视觉讨论稿，不是生产图标资源。实际视觉以用户确认的输出为准，不把生成提示词里的预期比例当作精确测量值。示例主图标、名称均为虚构。

## 原始提示词

```text
Use case: ui-mockup.
Asset type: one polished, realistic macOS launcher icon-badge preview board, not a new app-logo concept.
Primary request: compare WEBSITE and SHORTCUT launcher items, each with a SMALL TYPE BADGE ATTACHED TO THE BOTTOM-LEFT CORNER of its main icon, in coordinated LIGHT and DARK modes.
Composition: a clean landscape board, equal left light panel and right dark panel. Restrained blurred pale gray-blue desktop backdrop on left, graphite-blue desktop backdrop on right, no distracting wallpaper. Headers exactly "浅色" on left and "深色" on right in understated native Chinese sans-serif. Both panels contain the same two enlarged item icons in a spacious horizontal row, front-facing, with ample room and no surrounding card borders. Website first: native rounded-square white/blue main icon with a simple blue document mark, representing a saved website favicon, label "项目文档". Shortcut second: native rounded-square purple/lavender main icon with a simple white crescent moon, representing a custom shortcut icon, label "专注模式".
CRITICAL BADGES: Each main icon has precisely ONE small circular badge at BOTTOM LEFT, never at bottom right. Badge diameter approximately 24 percent of main icon width. Badge overlaps the icon silhouette, mostly inside but slightly outside at the lower-left corner, like a macOS Finder alias badge in placement. Website badge: crisp simple dark blue globe glyph with meridian and equator lines inside a neutral circular surface. Shortcut badge: crisp two stacked slightly offset cyan/purple diamond layers, a recognizable Shortcuts-type mark, inside an equally sized neutral circular surface. This type badge is NOT a notification dot, not a number, not an arrow, not a play button. Circular surface near-white in light mode and charcoal in dark mode, subtle thin border and tiny contact shadow so it separates from any main icon. Same badge location, size and glyph geometry across light/dark modes.
Below the large icon row, include a very quiet secondary row of the SAME TWO badged icons rendered much smaller (roughly one third of the large row's icon size) to judge normal launcher-scale readability; a small section caption exactly "小尺寸效果". Keep badges visible and crisp at this smaller scale. Do not add other types, app icons, search bars, controls, buttons, legends, arrows, explanations, spec dimensions, extra labels, or watermarks. Native tasteful macOS materials, restrained depth, no inflatable heavy 3D, no giant badges. Prioritize actual interface legibility and correct BOTTOM-LEFT placement. The output is a single comparison image, not executable UI.
```
