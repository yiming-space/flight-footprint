# B777-300ER 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成，没有旧飞机图片输入。
- 资产：`assets/images/aircraft/b777-300er-side-right-v1.png`。
- 核对依据：[波音官方资料](https://www.boeing.com/commercial/777/design-highlights)，相对尺寸用于插画约束，不加入 App 飞行指标。
- 保持：精致静态三维质感、白色无涂装、近侧视、机头向右、起落架收起、真实透明 alpha。
- 核对：完整轮廓、门窗、机头/尾翼、双发、翼尖与发动机类型的主要特征。AI 插画不是工程 CAD，最终仍需目视确认。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: brand-new model-specific 3D aircraft exhibit illustration for a mobile aircraft collection.
Subject: exactly ONE Boeing 777-300ER passenger jet, generated independently FROM SCRATCH. Do not modify, trace, or reuse a previously generated aircraft shape. Pristine pearl-white paint, no airline livery, gear fully retracted.
Model accuracy: the stretched 777-300ER, not a short 777-200, a 777X, an A350 or a 787. Relative dimensions: length 73.9 m, wingspan 64.8 m, height 18.5 m; a long cylindrical wide-body with appropriate roughly 6.2 m body width, five full-size passenger doors on the visible side and a consistent single cabin-window row. Boeing 777 nose with distinct angular cockpit-window panes WITHOUT an A350 black visor; tapered blade-like tail cone and tall swept fin. Swept wings with horizontally RAKED extended tips, no upward vertical winglets and no folding wingtip joints. Two very large GE90-115B-style turbofans, rounded inlet lip with deep dark detailed fan and spinner, smooth nacelle exhaust edges WITHOUT 787-style chevrons. Proper engine pylons, near engine clearly visible, far engine naturally occluded according to the near-side camera. Correct swept horizontal tailplanes and restrained wing-root/belly fairing.
Style: a refined premium CG scale-model illustration, NOT a real aviation photograph, not a chunky toy. Smooth pearl-satin white body with broad soft highlights describing its rounded 3D cross-section, gentle gray underside, crisp fine edges, physically plausible self-shadows where the wing root, pylon, tail and nacelle meet. Thin silver-gray leading edges, subtle passenger/cargo door outlines, clean flap/aileron joints and moderately detailed dark fan blades. No dirt, noisy rivets, embossed seams, dramatic chrome or excessive blur.
Camera/composition: a complete uncropped airplane in a wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage perfectly level. Only slight natural perspective to reveal wing thickness and intake depth, not a front three-quarter or overhead view. Center the aircraft at roughly 88 percent of canvas width with clean space around every tip and both ends.
Background: genuine transparent alpha outside the aircraft, clean antialiasing without white fringe, haze or glow. No sky, floor, stand, scenery or external cast shadow.
Text: NONE. No Boeing or GE logo, no airline logo, registration, model name, UI, watermark or labels. Visually faithful model illustration, not certified engineering CAD.
```
