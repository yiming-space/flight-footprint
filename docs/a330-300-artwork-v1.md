# A330-300 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成，没有旧飞机图片输入。
- 资产：`assets/images/aircraft/a330-300-side-right-v1.png`，2048×768 PNG，带 alpha。
- 参考：[空客 A330-300 官方尺寸](https://www.aircraft.airbus.com/en/aircraft/a330/a330-300)、[空客关于 ceo/neo 翼尖和翼展差异](https://www.airbus.com/en/newsroom/news/2017-02-winglets-a-tip-top-solution-for-more-efficient-aircraft)、[Rolls-Royce Trent 700 官方适用机型](https://www.rolls-royce.com/products-and-services/civil-aerospace/wide-body/trent-700.aspx)。
- 生成约束：经典 A330-300 / ceo 的 63.66 m 长度、5.64 m 机身宽度、60.30 m 翼展、16.79 m 高度；传统较小上翘翼梢、四主客舱门和双发。采用代表性 Trent 700 风格，不声称代表所有航司的发动机选型；不混入 A330neo 的大型弯曲翼梢和 Trent 7000。
- 目视检查：完整单架、机头向右、单排窗、双发、常规翼梢与收起起落架；白色无涂装、精致静态三维质感。alpha 抽样：机体外 (100,40)、(800,250)、(1500,200)、(800,650) 等点均为 0，预览中的灰色 RGB 晕影在这些全透明位置不可见；此检查未修改任何像素。不是工程 CAD，不声称逐面或遮挡部分已核验。
- 仅接入 A330-300 标签，不借用给 -200、neo、P2F；不修改现有航班记录或布局。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: a brand-new model-specific three-dimensional aircraft illustration for a mobile aircraft collection exhibit.
Subject: exactly ONE classic Airbus A330-300 passenger jet, independently generated FROM SCRATCH. No prior aircraft image input, no stretching or modifying an A350 or A330neo image. Pristine pearl-white presentation, no livery, all landing gear retracted.
Model-specific geometry: the original A330-300 / A330ceo, NOT an A330-200, A330-900neo, A350 or four-engine A340. Relative dimensions approximately 63.66 m overall length, 5.64 m fuselage width, 60.30 m wingspan and 16.79 m height. Long slender twin-aisle fuselage with the classic A330 rounded/tapered nose, recognizable angular Airbus cockpit-window panes WITHOUT an A350 black surrounding visor. FOUR main passenger doors along the visible side, one coherent row of small dark cabin windows, no narrowbody over-wing emergency hatches.
Swept classic A330 wings with their SMALLER conventional canted upward winglets, NOT the A330neo's tall curved A350-inspired Sharklets and not raked Boeing tips. Clean realistic wing-root/belly fairing, proper wing airfoil thickness, correct swept horizontal stabilizers and tall single vertical fin with A330-300 proportions. Exactly TWO original-generation A330 under-wing turbofans, representative Trent-700-style long smooth nacelles and appropriately smaller inlet diameter than a new A330neo engine, smooth non-chevron exhaust edges. Detailed metallic inlet lip, deeply recessed dark fan blades/spinner and proper pylons. Near engine clearly visible; far engine naturally occluded in the near-side view. No extra engines, wings or visible wheels.
Style and finish: refined premium CG scale-model illustration, not an aviation photograph and not a chunky toy. Smooth pearl-satin white body with controlled broad soft studio highlights describing cylindrical curvature, gently shaded gray underside, crisp silhouette and soft contact self-shadows at wing roots, pylons and tail joints. Muted silver-gray leading edges, discreet flap/aileron/elevator divisions, subtle passenger/cargo hatch seams and window recesses. Moderate precise detail without dirt, dense rivet noise, chrome glare or excessive blur.
Camera/composition: complete uncropped aircraft in a wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage perfectly level. Modest natural perspective only for wing thickness and engine intake depth, no front three-quarter, overhead or bank. Center aircraft at approximately 88 percent canvas width with clear margins around nose, tail and every tip.
Background: genuine transparent alpha outside the silhouette, clean antialiasing without white fringe, glow, haze or external cast shadow. No sky, floor, stand, scenery or other objects.
Text: none. No Airbus, engine or airline logos, registration, model lettering, labels, UI or watermark. Original visually faithful model illustration, not engineering-certified CAD or an individual airline registration.
```
