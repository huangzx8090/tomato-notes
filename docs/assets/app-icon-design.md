# 番茄小记图标

采用初稿 C：柔和立体的陶土番茄、鼠尾草绿双叶与奶油白指针，配暖白底。

- 设计原图：`apps/macos/Packaging/AppIcon.png`，由内置 image_gen 生成；保留完整正方形底图，避免自动抠图留下杂点。
- 应用图标：`apps/macos/Scripts/make-icon.swift` 读取原图，高质量缩放后统一应用圆角和 7% 透明边距，生成 16–1024 px 的标准 iconset；现有打包流程将其转换为 `AppIcon.icns`。
- README 预览：`docs/assets/app-icon.png`，使用同一流程的 512 px 输出。
- 菜单栏状态符号沿用原有实现，以便清楚区分运行、暂停与休息。

更新预览与应用图标：

```bash
swift apps/macos/Scripts/make-icon.swift build/AppIcon.iconset
cp build/AppIcon.iconset/icon_256x256@2x.png docs/assets/app-icon.png
apps/macos/Scripts/build-app.sh release --universal
```

## 最终生图提示词

输入参考为本次图标探索图中的左下 C。使用内置 image_gen，`transparent_background: false`；圆角和透明边距由构建脚本统一处理。

```text
Use case: precise-object-edit.
Asset type: opaque square SOURCE ARTWORK for a native macOS app icon. Native packaging will apply the rounded-square mask later.
Input reference: the four-concept comparison board. The selected design is ONLY THE BOTTOM LEFT icon C.

Create ONE isolated high-resolution SQUARE source illustration that faithfully matches C: a plump softly rounded matte terracotta tomato sculpture, two sage-green clay leaves meeting at the top, and short thick rounded raised ivory clock hands at approximately 12:20 on the tomato front. Soft warm diffuse light from upper-left, gentle natural contact shadow under the tomato, matte ceramic/clay material, quiet tactile refinement. Keep C's exact simple proportions, warm calm charm, and soft 3D style. No face, no words, no ticks. Do not use A, B or D.

IMPORTANT SOURCE-ART FORMAT:
- The ENTIRE square image, corner to corner and edge to edge, is an OPAQUE warm ivory backdrop (#F6F1E8), softly shaded only immediately under the tomato.
- NO rounded square base or tile. NO tile border, raised edge, bevel, plinth or frame. NO exterior gray backdrop. NO transparency or alpha cutout. This is a full-bleed source painting, NOT a mockup of a rounded app icon.
- The tomato together with the leaves occupies roughly 76% of the square width and 80% of square height. Generous clean ivory space all around. The tip of the leaves is at roughly 10% image height and bottom of tomato at 89% height. Keep the tomato-and-leaves optically centered as one unified symbol. No extreme closeup.
- Tomato is roughly spherical but subtly squashed with rounded shoulders, warm muted red-orange, not shiny plastic and not a glossy photograph of food. Leaves have very understated sculptural veins, not botanical detail.
- The ivory clock-hand mark is clear and simple, with one vertical hand pointing upward and a shorter hand pointing down-right, both thick and smoothly joined, softly raised like a small ceramic inlay. Soft contact shadows, no harsh specular highlights.
- The composition and geometry must remain very simple and legible at reduced app-icon sizes.

Single square full-bleed artwork only. No A/B/C/D label, no typography, no other icon, no comparison board, no devices, no mockup.
```
