# A350-1000 全新三维插画 v1

- 工具模式：内置 imagegen，全新生成，未传入或拉伸旧 A350-900 图。
- 最终资产：`assets/images/aircraft/a350-1000-side-right-v1.png`，2079×756 PNG，带 alpha。
- 外形约束：[空客 A350-1000 官方资料](https://www.aircraft.airbus.com/en/aircraft/a350/a350-1000)。以 73.78 m 长度 / 5.94 m 机身宽度 / 64.75 m 翼展与 Trent XWB-97 配置作为生成约束；与 -900 采用独立资产，不合并统计记录。
- 保持：白色无涂装、近侧视、机头向右、起落架收起、精致静态三维质感和透明背景。AI 插画并非工程 CAD，主要轮廓和识别特征目视检查，不能视为逐面工程精度验证。
- 本轮仅增加这一款，定时任务的 10% 额度保护不变。

## 实际完整 Prompt

```text
Use case: stylized-concept
Asset type: brand-new model-specific three-dimensional aircraft illustration for a mobile aircraft collection exhibit.
Subject: exactly ONE Airbus A350-1000 passenger jet, independently generated FROM SCRATCH. Do not edit, trace, resize or stretch any previous A350-900 artwork. Pristine pearl-white unpainted presentation, gear fully retracted.
Model geometry: specifically the longer A350-1000. Respect relative dimensions of 73.78 m overall length, 5.94 m fuselage width and 64.75 m wingspan, with noticeably longer fuselage sections ahead of and behind the wing than the shorter A350-900. Long slender wide-body proportions, a smooth cylindrical body, modest realistic belly fairing, A350's smoothly rounded tapered nose and recognizable continuous broad BLACK wraparound cockpit visor around the dark window panes. Four full-size main passenger doors on the visible side and one coherent row of small dark cabin windows. Swept wings with elegant continuously curved scimitar-like upturned tips, not separate straight vertical 737 winglets. Exactly TWO appropriately large Trent XWB-97-style under-wing turbofans, smooth nacelle exhaust edges without 787 chevrons. Correct wing root and engine-pylon geometry, dark deep intake with distinct fan blades and center spinner. Far engine naturally occluded according to the near-side viewpoint. Correct single swept vertical fin, horizontal stabilizers and tapered tail cone. No extra structures, no visible landing wheels.
Style and finish: refined premium CG scale-model illustration, visually three-dimensional and precise but NOT an aviation photograph, NOT a chunky toy. Pearl-satin white body with controlled broad soft studio highlights describing the rounded cross-section, gentle gray underside, crisp silhouettes, and soft contact self-shadowing at the wing roots, pylons, nacelles and tail joints. Thin muted silver-gray leading edges, actual airfoil thickness, discreet flap/aileron/elevator divisions, subtle passenger and cargo hatch seams, recessed windows and modeled fan details. Clean restrained detail; no dirt, dense rivet noise, hard chrome, excessive reflections or blur.
Camera and composition: complete uncropped aircraft, wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level. Only modest natural perspective revealing wing thickness and engine-intake depth, never a front three-quarter, overhead or banking view. Aircraft centered at approximately 88 percent canvas width, with clear margins around the nose, tail and every tip.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, haze, glow, external cast shadow, floor, stand, sky or other objects.
Text: none. No Airbus, Rolls-Royce or airline logos, registration, model lettering, labels, UI or watermark. Original visually faithful model illustration, not engineering-certified CAD.
```
