# A350-900 全新三维插画 v3

- 工具模式：内置 imagegen，全新生成。没有传入旧飞机图，也没有在旧图上修细节。
- 最终资产：`assets/images/aircraft/a350-900-side-right-v3.png`，真实透明 alpha。
- 保留：近侧视、机头向右、白色无涂装、起落架收起；只替换插画，不改变卡片布局。
- 外形资料：[空客 A350-900 官方资料](https://www.aircraft.airbus.com/en/aircraft/a350/a350-900)，长度、宽度、翼展、高度仅用于生成时的比例约束，不写入用户飞行指标。
- 核对：完整机身/尾翼/翼尖、双发配置、四个主客舱门、暗色驾驶舱、发动机进气与机翼层次。AI 插画不等于工程 CAD，仍需要用户最终目视确认。
- v1 保留；修改旧图的 v2 候选未接入 App。

## 实际使用的完整 Prompt

```text
Use case: stylized-concept
Asset type: a brand-new model-specific 3D-rendered aircraft illustration for a mobile aircraft collection exhibit.
Primary request: generate a completely NEW Airbus A350-900 from scratch, with clean accurate aircraft geometry and a refined three-dimensional premium scale-model appearance. DO NOT edit, trace, reuse, or imitate any of the previously generated aircraft silhouettes. Rebuild this specific model independently.
Subject: exactly one standard passenger Airbus A350-900, pristine pearl-white unpainted presentation, landing gear fully retracted, no livery or logos.
Model-specific geometry: the SHORTER A350-900, not the A350-1000. Respect 66.80m overall length, 5.94m fuselage width, 64.75m wingspan and 17.05m overall height as relative proportions. A long slender wide-body with smooth cylindrical cross-section and a modest belly fairing, not a fat toy tube. A350-specific gently rounded tapered nose, recognizable broad black wraparound cockpit visor/mask rather than separate gray windows on white metal. Four main passenger doors along the visible side, one coherent row of small dark cabin windows. Elegantly swept wings with continuous curved scimitar-like upturned tips, not separate straight vertical 737-style winglets. Correctly proportioned tall swept vertical fin, clean swept horizontal tailplanes and a tapered tail cone. Two large Trent XWB-84-style high-bypass engines correctly mounted under the wings with smooth nacelles and smooth non-chevron exhaust edges; in this near-side view the far engine may be naturally occluded. No extra wings, engines or imaginary structures.
3D quality and details: a professionally modeled high-quality CG scale-model render, visually refined but NOT an aviation photograph and NOT a childish clay toy. Smooth carefully controlled pearl-satin white fuselage with a convincing rounded light falloff, subtle soft gray underside and crisp silhouette. Real modeled wing airfoil thickness, graceful wing-root blending and fairing, discreet flap/aileron/elevator joints and subtle silver leading edges. Engine inlet lip with realistic thickness, deep dark intake, many distinct fan blades and center spinner, believable engine pylon attachment. Restrained door seams, window recesses and cargo hatch outlines. Refined physically plausible material response, broad soft studio key light with a very gentle fill, contact self-shadows where structures meet. Clean small details, no dirt, rivet noise, exaggerated reflections or embossed outlines.
Composition: wide horizontal aircraft exhibit, nose pointing RIGHT, tail LEFT. Near lateral side view, fuselage perfectly level, only modest natural perspective to reveal wing thickness and engine-intake depth; do NOT use a front three-quarter view, overhead view, or dramatic bank. The aircraft must be complete, uncropped, centered, and occupy approximately 88 percent of the wide canvas width, leaving clean margin around nose, tail and every tip.
Background: genuinely transparent alpha outside the complete aircraft silhouette. Precisely clean antialiased edges. No sky, clouds, ground, floor shadow, surrounding glow, haze or white fringe. Shadows only on the aircraft itself.
Text: none. No Airbus / Rolls-Royce / airline logos, no registration, model lettering, labels, UI or watermark. Faithful model illustration, not an engineering-certified CAD drawing.
```
