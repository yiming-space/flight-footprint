# A380-800 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成；没有旧飞机图片输入。
- 资产：`assets/images/aircraft/a380-800-side-right-v1.png`。
- 文件验证：1983×793 PNG，带 alpha；单款接入后 18 项映射/图鉴测试通过，整批六款接入后 36 项测试通过，静态分析无问题。本轮未新增原生截图。
- 参考：[空客 A380 官方介绍](https://www.airbus.com/en/products-services/commercial-aircraft/passenger-aircraft/a380)、[官方尺寸与发动机资料 PDF](https://www.airbus.com/sites/g/files/jlcbta136/files/2025-01/airbus-a380-facts-and-figures-february-2022.pdf)、[常规翼尖围栏与 A380plus 提案的区别](https://www.airbus.com/en/newsroom/news/2017-06-focus-on-efficiency-and-cabin-comfort-enhancements-for-airbus-a380-and-a320)。
- 约束：全长双层客舱、四发配置、常规小型翼尖围栏，白色无涂装、近侧视、机头向右、起落架收起、真实透明背景。相对尺寸只用于生成，不写入 App 飞行指标。
- 目视检查：单架且完整、两排客舱窗、两台近侧发动机独立可见，远侧按视角遮挡；无文字和涂装。只核对可见轮廓，不能把遮挡部分或生成结果视为工程 CAD 精度验证。
- 未调整 UI 布局或已有四款资产；单独型号映射，不借用其他机型插画。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: a brand-new model-specific three-dimensional aircraft illustration for a mobile aircraft collection exhibit.
Subject: exactly ONE Airbus A380-800 passenger airliner, generated independently FROM SCRATCH. Do not modify, trace or reuse an existing aircraft image. Pristine pearl-white presentation without livery, all landing gear fully retracted.
Model-specific geometry: a genuine A380-800, with TWO FULL-LENGTH passenger decks and two coherent parallel rows of small dark cabin windows along the deep oval fuselage, NOT a 747-style short upper-deck hump. Proportions approximately 72.7 m long, 79.8 m wingspan, 24.1 m overall height, about 7.1 m fuselage width. Characteristically broad rounded A380 nose with cockpit panes positioned between the passenger deck levels; standard dark individual cockpit glazing, no A350 black visor. Correctly arranged discreet passenger door outlines on the main and upper decks. Broad swept wings, thick well-blended wing roots, SMALL classic wingtip fences extending above and below the tip, NOT giant A350 curved winglets or proposed A380plus devices. Exactly FOUR under-wing turbofan engines, two per wing: the two near engines clearly separated at correct inboard and outboard positions, far-side engines naturally occluded according to the near-side camera. Rounded Trent-900-style nacelles with thick metallic inlet rims, recessed dark detailed fan blades and center spinners; smooth exhaust edges, no Dreamliner chevrons. Properly tall swept single vertical fin, horizontal tailplanes and tapered aft fuselage. No extra engines or wings, no exposed landing wheels.
Style and finish: refined premium CG scale-model illustration, not an aviation photograph and not a chunky toy. Smooth pearl-satin white paint, soft broad studio highlights describing the fuselage volume, a gentle silver-gray underside, crisp contours and soft contact self-shadows at wing roots, pylons and tail joints. Moderate precise modeling of wing airfoil thickness, flap/aileron joints, leading edges and subtle passenger/cargo hatch seams. Restrained realistic material response; no dirt, noisy rivets, hard chrome or excessive blur.
Camera/composition: complete uncropped aircraft in a wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage perfectly level. Only modest natural perspective to reveal wing thickness and intake depth, not a front three-quarter view, overhead view or bank. Center the airplane at about 88 percent of canvas width with clear margin around the nose, tail and every wingtip.
Background: genuine transparent alpha outside the aircraft silhouette, clean antialiased edges without white fringe, glow, haze or external cast shadow. No sky, scenery, floor, stand or other objects.
Text: none. No Airbus, engine or airline logos, registration, model lettering, UI, labels or watermark. Original visually faithful model illustration, not engineering-certified CAD.
```
