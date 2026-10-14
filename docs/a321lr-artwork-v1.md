# A321LR 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成，没有旧飞机图片输入。
- 资产：`assets/images/aircraft/a321lr-side-right-v1.png`。
- 参考：[空客 A321neo/A321LR 产品资料与尺寸](https://www.aircraft.airbus.com/en/aircraft/a320-family/a321neo)、[A321LR 首飞与 ACF/LEAP-1A 说明](https://www.airbus.com/en/newsroom/news/2018-01-airbus-globetrotting-a321lr-performs-its-maiden-flight)、[A321neo ACF 门/出口结构说明](https://www.airbus.com/en/newsroom/press-releases/2018-01-airbus-rolls-out-first-a321neo-acf)。
- 生成约束：44.51 m 长度、3.95 m 机身宽度、35.80 m 翼展、11.76 m 高度，A321neo 家族 Sharklets 与 LEAP-1A 风格双发。LR 并非加长的 A321neo，不把内部附加油箱画成外部凸起。
- 目视检查：完整单架、机头向右、窄体比例、单排窗、翼上出口、双发/翼梢与收起起落架。选择代表性 ACF 外观；门/出口启用和发动机选型存在运营配置差异，不代表每条航班的具体实机配置。白色无涂装、三维静态风格、透明 alpha，不是工程 CAD。
- 只接入 A321LR 标签，不借用给 A321NEO/XLR，不修改航班记录或卡片布局。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: a brand-new model-specific three-dimensional aircraft illustration for a mobile aircraft collection.
Subject: exactly ONE Airbus A321LR passenger jet, independently generated FROM SCRATCH, with no prior aircraft image as input. Pearl-white unpainted presentation, no livery, all landing gear retracted.
Model-specific geometry: the long-range A321neo ACF variant, NOT an A320, widebody A330, A321XLR or a fictional further-stretched A321. Use relative dimensions of 44.51 m overall length, 3.95 m fuselage width, 35.80 m wingspan and 11.76 m height. An elegant long slender single-aisle fuselage, standard A320-family rounded nose and distinct angular dark cockpit-window panes WITHOUT an A350 black surrounding visor. One coherent row of small cabin windows. Show a sensible Airbus Cabin Flex door/exit layout: front and aft entrance doors, the ACF rear-section door as configured, and paired emergency exits above the wing, rather than the old full-size door ahead of the wing. Do not depict internal extra fuel tanks as external lumps. The LR is not longer than a standard A321neo.
Swept narrowbody wings with gracefully blended tall Airbus Sharklets, proper compact wing-root fairing and swept tailplanes. Exactly TWO appropriately sized CFM LEAP-1A-style turbofans under the wings, larger rounded nacelles than an old A321ceo, smooth non-chevron exhaust edges, metallic inlet lips and deep dark fan blades/spinner. Near engine clearly visible, far engine naturally occluded for a near-side view. Correct tall swept vertical fin and tapered tail cone; no extra wings, engines, antennas or visible wheels.
Style and finish: refined premium CG scale-model illustration, not an aviation photograph and not a chunky toy. Smooth pearl-satin white surfaces with broad soft studio highlights describing the cylindrical body, gentle gray underside, crisp contours and soft contact self-shadows at wing roots, pylons and tail joints. Actual wing thickness, subtle silver-gray leading edges, discreet flap/aileron/elevator seams and passenger/cargo door outlines. Restrained precise detail; no dirt, dense rivet noise, chrome glare or excessive blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage perfectly level, modest natural perspective only to reveal wing thickness and intake depth. Never front three-quarter, overhead or banked. Complete uncropped airplane, centered at about 88 percent canvas width, clear margins around all ends and tips.
Background: genuine transparent alpha, clean antialiasing without white fringe, glow, haze or external cast shadow. No sky, floor, stand, scenery or objects.
Text: none. No Airbus/engine/airline logos, registration, model lettering, UI, labels or watermark. Original visually faithful model illustration, not engineering-certified CAD or a specific airline registration.
```
