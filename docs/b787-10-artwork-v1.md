# B787-10 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成，没有旧飞机图片输入。
- 资产：`assets/images/aircraft/b787-10-side-right-v1.png`。
- 核对依据：[波音官方资料](https://www.boeing.com/content/theboeingcompany/us/en/commercial/787.html)，相对尺寸用于插画约束，不加入 App 飞行指标。
- 保持：精致静态三维质感、白色无涂装、近侧视、机头向右、起落架收起、真实透明 alpha。
- 核对：完整轮廓、门窗、机头/尾翼、双发、翼尖与发动机类型的主要特征。AI 插画不是工程 CAD，最终仍需目视确认。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: brand-new model-specific 3D aircraft exhibit illustration for a mobile aircraft collection.
Subject: exactly ONE Boeing 787-10 Dreamliner passenger jet, generated independently FROM SCRATCH. Do not modify or trace a previous aircraft illustration. Pristine pearl-white body, no livery, all landing gear retracted.
Model accuracy: specifically the LONGEST 787-10, not the shorter 787-9 or 787-8. Respect the approximately 68.3 m length, 60.1 m wingspan and 17.0 m overall height as relative proportions. A long slender composite wide-body with the 787's smoothly drooping tapered nose, characteristic swept cockpit-window glazing, FOUR full-size main passenger doors along the visible side, and a coherent single row of noticeably generous oval Dreamliner cabin windows. Gracefully swept flexible wings with thin RAKED tips continuing in the wing plane: no separate vertical A350/737-style winglets. Two Dreamliner turbofans under the wings with clearly modeled small sawtooth CHEVRONS along the rear nacelle edges, deep recessed dark intake fans and metallic inlet rims. Near engine clearly visible, far engine naturally occluded according to the side camera; no extra engines. Correctly tapered tail cone, swept vertical fin and horizontal tailplanes; fine wing-root/belly fairing. No 777 folding tips, no Airbus black cockpit visor, no invented over-wing exits.
Style: refined premium three-dimensional CG scale-model illustration, neither an aviation photograph nor a bloated clay toy. Pearl-satin white surface with soft broad studio highlights that describe fuselage curvature, gently shaded gray belly, crisp fine contours and soft contact self-shadowing around engine pylons, wing roots and tail joints. Muted silver-gray wing leading edges, discreet passenger/cargo hatch seams, subtle flap/aileron subdivisions, realistically recessed engine fan blades and spinner. Moderate precise detail without dirt, dense rivets, harsh chrome or exaggerated reflections.
Camera/composition: wide horizontal near-lateral side view with the NOSE RIGHT and TAIL LEFT, fuselage level. Slight natural perspective only for wing thickness and intake depth, NOT a front three-quarter or top view. Complete uncropped aircraft, centered, about 88 percent of canvas width, generous clear margins at all ends and tips.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges with no white halo, glow, haze, external shadow, floor, stand, sky or scenery.
Text: none. No Boeing/Rolls-Royce/GE/airline logo, no registration, labels, model name, UI or watermark. Faithful model illustration, not certified engineering CAD.
```
