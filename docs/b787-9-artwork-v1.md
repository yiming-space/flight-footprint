# B787-9 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成；没有使用、缩短或修改旧 B787-10 图片。
- 资产：`assets/images/aircraft/b787-9-side-right-v1.png`。
- 文件验证：1954×805 PNG，带 alpha；整批机型聚合、映射、图鉴/详情共 36 项测试通过，静态分析无问题。本轮未新增原生截图。
- 参考：[波音 787 官方尺寸与发动机表](https://www.boeing.com/content/theboeingcompany/us/en/commercial/787.html)、[787 官方设计介绍](https://www.boeing.com/commercial/787/by-design)。
- 生成约束：787-9 的 62.8 m 长度、60.1 m 翼展、17.0 m 高度，区别于 -10 和 -8；后掠翼尖、双发和发动机后缘 chevrons。尺寸仅为生成约束，不加入 App 飞行指标。
- 目视检查：完整单架、机头向右、近侧视、四主客舱门配置（其中一处受机翼遮挡）、单排窗、发动机进气/锯齿边缘及收起起落架。白色无涂装、静态三维质感、带透明 alpha；不是工程 CAD，遮挡部分不声称已逐面核验。
- 独立型号映射，未知标签、混合型号或未制作变体不借用此图，不更改卡片布局或原有统计记录。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: brand-new model-specific three-dimensional aircraft illustration for a mobile aircraft collection exhibit.
Subject: exactly ONE Boeing 787-9 Dreamliner passenger jet, independently generated FROM SCRATCH. Do not modify, shrink or trace the earlier 787-10 illustration. Pristine pearl-white body, no livery, landing gear fully retracted.
Model-specific geometry: specifically the middle-length 787-9, NOT the longer 787-10 and NOT the short 787-8. Relative dimensions approximately 62.8 m length, 60.1 m wingspan and 17.0 m height, with a slender wide-body fuselage roughly 5.8 m wide. Correctly shorter fore/aft fuselage lengths than a 787-10 without making the aircraft stubby. Characteristic 787 smoothly drooping tapered nose, swept cockpit-window glazing without an Airbus A350 black surrounding visor. FOUR main passenger doors on the visible side, a coherent single row of generously sized oval Dreamliner cabin windows. Gracefully swept flexible wings with thin RAKED tips continuing the wing plane, no separate vertical 737/A350 winglets. Exactly two Dreamliner turbofans mounted under the wings, with clear small sawtooth CHEVRONS along the rear nacelle edges, thick metallic inlet lips, recessed dark detailed fan blades and center spinners. Near engine clearly visible; far engine naturally occluded according to the near-side view, no extra engines. Correct swept vertical fin, horizontal tailplanes, tapered tail cone and restrained wing-root/belly fairing. No invented over-wing exits or folding wingtip joints.
Style and finish: refined premium three-dimensional CG scale-model illustration, not an aviation photograph and not a bloated toy. Smooth pearl-satin white body, broad soft studio highlights describing fuselage curvature, gentle gray underside, crisp silhouette and soft contact self-shadows at wing roots, pylons and tail joints. Subtle silver-gray leading edges, real airfoil thickness, discreet flap/aileron/elevator subdivisions, restrained passenger/cargo hatch seams and window recesses. Clean moderate precise detail; no dirt, dense rivet noise, hard chrome, exaggerated reflections or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT and tail LEFT, fuselage perfectly level. Only modest natural perspective to reveal wing thickness and intake depth, not a front three-quarter, overhead or banking view. One complete uncropped airplane, centered at approximately 88 percent of canvas width, clear margins around the nose, tail and all tips.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, haze, glow or external cast shadow. No sky, floor, stand, scenery or other objects.
Text: none. No Boeing/engine/airline logos, registration, model lettering, labels, UI or watermark. Original visually faithful model illustration, not engineering-certified CAD.
```
