# 剩余八款机型插画 — 2026-10-14 批次

> 历史批次记录：其中 A330-900NEO、B737 MAX 8、A321NEO、B737-800 的 v1 后续被用户指出机翼透视关系问题，现已独立重生成 v2；当前使用版本和完整返修提示词见 [四款机翼返修](aircraft-wing-correction-20261014.md)。本页保留当时的生成/检查记录，不代表用户已认可 v1 的几何。

## 生成与接入方式

用户最新要求“先一次性生成全部再写入”：本批八款先全部暂存、目视核对，再统一接入 App，未逐款热加载。使用 imagegen 技能的 **内置工具模式**，每款从零独立生成，未输入旧飞机图片、未使用 CLI/API 或收费回退。A320-200 和 B737 MAX 9 的首版可见舱门布局未达标，保留在外层暂存目录但不接入；各重新生成一张 v2，未在旧图上修几何。

所有 PNG 真实保留 alpha，读出尺寸并抽样六个机体外部点 alpha 均为 0；这是抽样检查，不是全像素工程分割认证。工具预览的 RGB 灰光或白边不能直接等同于实际 alpha 显示。全部素材人工目视核对完整轮廓与下述主要特征，属于代表配置的艺术插画，不是特定注册号的精确 CAD、出口认证图或发动机工程模型。

暂存及含被拒绝首版提示词的断点清单：`../../outputs/aircraft-remaining-batch-20261014/manifest.json`。App 资产均在 `assets/images/aircraft/`，严格型号映射登记于 `lib/features/stats/aircraft_artwork.dart`。

## 本批清单

- A330-900NEO: `assets/images/aircraft/a330-900neo-side-right-v1.png`，2169×725。目视核对 A330 长机身、四门、neo 风格驾驶舱、曲线 Sharklet 与双发，作为 Trent 7000 代表外观插画。
- B737 MAX 9: `assets/images/aircraft/b737-max-9-side-right-v2.png`，2103×748。v1 缺少中后部出口/堵板轮廓，未接入；v2 从零生成，核对前后舱门、双翼上出口、独立中后部堵板、MAX 分叉翼尖和发动机尾缘锯齿。
- B737 MAX 8: `assets/images/aircraft/b737-max-8-side-right-v1.png`，1983×793。核对标准 MAX 8 前后舱门及双翼上出口、分叉翼尖、双发尾缘锯齿；不作为额外出口的 8-200 配置。
- E190-E2: `assets/images/aircraft/e190-e2-side-right-v1.png`，2048×768。核对紧凑 E2 机身、单侧翼上出口、后掠翼尖、较大双发与区域客机机头；不借用 E190 一代直立翼梢外形。
- A320-200: `assets/images/aircraft/a320-200-side-right-v2.png`，1942×809。v1 中段误绘成两扇分离的全高门，未接入；v2 从零生成，核对前后两扇全高门及居中的两个相邻小型翼上出口，使用 Sharklet/CFM56-5B 的代表 ceo 配置。
- B787-8: `assets/images/aircraft/b787-8-side-right-v1.png`，2048×768。核对短机身 Dreamliner、四门、大椭圆舷窗、后掠翼尖与双发尾缘锯齿。整架轮廓在画面内，左右余量较小，不裁切素材。
- A321NEO: `assets/images/aircraft/a321neo-side-right-v1.png`，2081×756。核对长机身、ACF 代表舱门/翼上出口、Sharklet、PW1100G 风格双发；与 LR 外部尺寸相同，未虚构长度差异，独立生成而非借图。
- B737-800: `assets/images/aircraft/b737-800-side-right-v1.png`，1983×793。核对 737NG 机头、前后舱门及双翼上出口、单一上扬 blended winglet、光滑发动机尾缘，与 MAX 分叉翼尖和锯齿尾缘区分。

## 官方核对依据与实际生成提示词

### A330-900NEO

- [制造商官方资料](https://www.aircraft.airbus.com/en/aircraft/a330/a330-900)

选用几何约束：Airbus A330-900neo, NOT classic A330-300 or shorter A330-800. Proportions: 63.69 m length, 5.64 m fuselage width, 64.00 m wingspan, 16.79 m height. Long twin-aisle body with FOUR main passenger doors and one window row. A330 nose and angular cockpit glazing, representative dark surrounding cockpit mask of A330neo. New swept wings with LARGE gracefully CURVED A350-inspired Sharklets, not the classic A330's small canted winglets. Exactly TWO large Rolls-Royce Trent 7000-style turbofans, rounded nacelles, smooth non-chevron exhaust edges, proper new pylons. Near engine clear, far engine naturally occluded. Correct A330 swept fin/tailplanes and restrained belly fairing.

实际生成提示词（a330-900neo-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Airbus A330-900neo, NOT classic A330-300 or shorter A330-800. Proportions: 63.69 m length, 5.64 m fuselage width, 64.00 m wingspan, 16.79 m height. Long twin-aisle body with FOUR main passenger doors and one window row. A330 nose and angular cockpit glazing, representative dark surrounding cockpit mask of A330neo. New swept wings with LARGE gracefully CURVED A350-inspired Sharklets, not the classic A330's small canted winglets. Exactly TWO large Rolls-Royce Trent 7000-style turbofans, rounded nacelles, smooth non-chevron exhaust edges, proper new pylons. Near engine clear, far engine naturally occluded. Correct A330 swept fin/tailplanes and restrained belly fairing.
```

### B737 MAX 9

- [制造商官方资料](https://www.boeing.com/commercial/737max)
- [制造商官方资料](https://www.boeing.com/737-9-updates)

选用几何约束：Boeing 737 MAX 9, NOT shorter MAX 8, longer MAX 10 or 737-900NG. Proportions: 42.1 m length, 35.9 m wingspan, 12.3 m height; slender single-aisle 737 body. Classic pointed Boeing nose, angular cockpit panes without Airbus visor, a single cabin-window row, forward/aft entry doors, paired over-wing exits and a discreet closed mid-aft exit/plug outline appropriate to a standard MAX 9 configuration. Swept wings with the distinctive Boeing MAX Advanced Technology SPLIT tips, upper and lower elements, not simple vertical Sharklets. Exactly TWO CFM LEAP-1B-style turbofans, properly forward/up mounted, rounder inlet than old CFM56-7B, subtle CHEVRONS along rear nacelle edges. Near engine clear, far naturally occluded. Swept 737 fin with dorsal root, correct horizontal tailplanes. Do not make it stubby or add MAX-10 landing gear.

实际生成提示词（b737-max-9-side-right-v2.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Boeing 737 MAX 9, NOT shorter MAX 8, longer MAX 10 or 737-900NG. Proportions: 42.1 m length, 35.9 m wingspan, 12.3 m height; slender single-aisle 737 body. Classic pointed Boeing nose, angular cockpit panes without Airbus visor, a single cabin-window row, forward/aft entry doors, paired over-wing exits and a discreet closed mid-aft exit/plug outline appropriate to a standard MAX 9 configuration. Swept wings with the distinctive Boeing MAX Advanced Technology SPLIT tips, upper and lower elements, not simple vertical Sharklets. Exactly TWO CFM LEAP-1B-style turbofans, properly forward/up mounted, rounder inlet than old CFM56-7B, subtle CHEVRONS along rear nacelle edges. Near engine clear, far naturally occluded. Swept 737 fin with dorsal root, correct horizontal tailplanes. Do not make it stubby or add MAX-10 landing gear.
DOOR LAYOUT CRITICAL, visible side from RIGHT nose to LEFT tail: ONE full-height front entry door near the nose, TWO small adjacent over-wing exit hatches together above wing, ONE separate clearly visible medium-sized rectangular MID-AFT plugged exit outline BETWEEN wing and tail entry door, then ONE full-height rear entry door near tail. The mid-aft exit outline is essential and must not be omitted. A longer MAX 9 fuselage, not MAX 8. MAX split winglet with upward and downward elements and LEAP-1B rear chevrons.
Near-lateral side profile; entire silhouette with margins. Independently generate a brand new aircraft, do not edit or reference any previous image.
```

### B737 MAX 8

- [制造商官方资料](https://www.boeing.com/commercial/737max)

选用几何约束：Boeing 737 MAX 8, specifically standard MAX 8 NOT MAX 9, MAX 10, 737-800NG or high-density 8-200. Proportions: 39.5 m length, 35.9 m wingspan, 12.3 m height, shorter body sections than MAX 9. Slender single-aisle 737 fuselage, pointed Boeing nose, angular cockpit panes without Airbus visor, one cabin-window row, front/aft entry doors and paired over-wing emergency exits. No extra mid-aft 8-200/MAX9 exit or plug outline. Swept wings with distinctive MAX Advanced Technology SPLIT upper/lower wingtip elements, not Airbus Sharklets. Exactly TWO CFM LEAP-1B-style engines forward/up mounted, rounded intake lips and subtle rear nacelle CHEVRONS, not flat-bottom old CFM56 nacelles. Correct 737 fin/dorsal root and tailplanes. Near engine clear, far naturally occluded.

实际生成提示词（b737-max-8-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Boeing 737 MAX 8, specifically standard MAX 8 NOT MAX 9, MAX 10, 737-800NG or high-density 8-200. Proportions: 39.5 m length, 35.9 m wingspan, 12.3 m height, shorter body sections than MAX 9. Slender single-aisle 737 fuselage, pointed Boeing nose, angular cockpit panes without Airbus visor, one cabin-window row, front/aft entry doors and paired over-wing emergency exits. No extra mid-aft 8-200/MAX9 exit or plug outline. Swept wings with distinctive MAX Advanced Technology SPLIT upper/lower wingtip elements, not Airbus Sharklets. Exactly TWO CFM LEAP-1B-style engines forward/up mounted, rounded intake lips and subtle rear nacelle CHEVRONS, not flat-bottom old CFM56 nacelles. Correct 737 fin/dorsal root and tailplanes. Near engine clear, far naturally occluded.
```

### E190-E2

- [制造商官方资料](https://www.embraer.com/e-jets-e2/e190e2/en/)
- [制造商官方资料](https://www.embraer.com/media/vmsjxvk5/e-jets-e2_apm_e-jetse2.pdf)

选用几何约束：Embraer E190-E2 regional passenger jet, NOT first-generation E190, larger E195-E2, A220 or an Airbus/Boeing narrowbody. Proportions: 36.24 m length, 33.72 m span, 10.95 m height; slender small regional fuselage and distinctive tapered E-Jet nose/cockpit glazing, one window row. Front/aft passenger doors and appropriate over-wing exits. New high-aspect-ratio swept wings with SWEPT-BACK TIPS continuing the wing, not old E190 tall upright winglets. Exactly TWO comparatively large Pratt & Whitney PW1900G-style geared turbofans under the wings, rounded nacelles and smooth non-chevron rear edges. Proper pylons and wing-root fairing, correct E2 tall swept fin and tailplanes. Near engine clear, far naturally occluded. Preserve compact regional-airliner proportions rather than making a long widebody.

实际生成提示词（e190-e2-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Embraer E190-E2 regional passenger jet, NOT first-generation E190, larger E195-E2, A220 or an Airbus/Boeing narrowbody. Proportions: 36.24 m length, 33.72 m span, 10.95 m height; slender small regional fuselage and distinctive tapered E-Jet nose/cockpit glazing, one window row. Front/aft passenger doors and appropriate over-wing exits. New high-aspect-ratio swept wings with SWEPT-BACK TIPS continuing the wing, not old E190 tall upright winglets. Exactly TWO comparatively large Pratt & Whitney PW1900G-style geared turbofans under the wings, rounded nacelles and smooth non-chevron rear edges. Proper pylons and wing-root fairing, correct E2 tall swept fin and tailplanes. Near engine clear, far naturally occluded. Preserve compact regional-airliner proportions rather than making a long widebody.
```

### A320-200

- [制造商官方资料](https://www.aircraft.airbus.com/en/aircraft/a320-family/a320ceo)
- [制造商官方资料](https://www.airbus.com/sites/g/files/jlcbta136/files/2023-05/Airbus-techdata-AC-A320_0523.pdf)

选用几何约束：Airbus A320-200 / A320ceo, a representative late-production SHARKLET-equipped ceo configuration, NOT A320neo or longer A321. Proportions: 37.57 m length, 3.95 m body width, 35.80 m span with Sharklets, 11.76 m height. Shorter compact single-aisle Airbus fuselage, rounded A320 nose, angular dark cockpit panes without black A350 visor. Front/aft main passenger doors and two over-wing emergency exits along visible side; one cabin-window row. Swept wings and tall blended Sharklets. Exactly TWO representative CFM56-5B-style old-generation engines, SMALLER/SLIMMER nacelles than an A320neo LEAP/PW GTF, smooth rear edges without Dreamliner chevrons. Correct Airbus fin and horizontal stabilizers. Near engine clear, far naturally occluded. Wingtip/engine configuration is representative, not every airline's configuration.

实际生成提示词（a320-200-side-right-v2.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Airbus A320-200 / A320ceo, a representative late-production SHARKLET-equipped ceo configuration, NOT A320neo or longer A321. Proportions: 37.57 m length, 3.95 m body width, 35.80 m span with Sharklets, 11.76 m height. Shorter compact single-aisle Airbus fuselage, rounded A320 nose, angular dark cockpit panes without black A350 visor. Front/aft main passenger doors and two over-wing emergency exits along visible side; one cabin-window row. Swept wings and tall blended Sharklets. Exactly TWO representative CFM56-5B-style old-generation engines, SMALLER/SLIMMER nacelles than an A320neo LEAP/PW GTF, smooth rear edges without Dreamliner chevrons. Correct Airbus fin and horizontal stabilizers. Near engine clear, far naturally occluded. Wingtip/engine configuration is representative, not every airline's configuration.
DOOR LAYOUT CRITICAL, visible side from RIGHT nose to LEFT tail: ONE full-height front entry door near the nose, then cabin windows, TWO small adjacent OVER-WING exits centered TOGETHER above the wing, then cabin windows, then ONE full-height rear entry door near the tail. Exactly TWO full-size doors total on this side, plus TWO small adjacent over-wing exit hatches. Do not draw four full-height doors, A321 mid-fuselage doors, or widely separated large middle doors.
Near-lateral side profile; entire silhouette with margins. Independently generate a brand new aircraft, do not edit or reference any previous image.
```

### B787-8

- [制造商官方资料](https://www.boeing.com/content/theboeingcompany/us/en/commercial/787.html)
- [制造商官方资料](https://www.boeing.com/commercial/787/by-design)

选用几何约束：Boeing 787-8 Dreamliner, the SHORTEST variant, NOT 787-9 or stretched 787-10. Proportions: 56.7 m length, 60.1 m wingspan, 16.9 m height. Shorter fore/aft fuselage sections while keeping a graceful widebody shape. Smoothly drooping tapered Dreamliner nose/cockpit glazing, FOUR main passenger doors, one row of generous oval cabin windows. Swept flexible wings with thin RAKED tips continuing in the wing plane, no separate vertical winglets. Exactly TWO Dreamliner under-wing turbofans with clearly modeled small rear nacelle CHEVRONS, recessed intake fan/spinner and silver rim. Correct fin, swept tailplanes and tapered tail cone. Near engine clear, far naturally occluded. No Airbus visor, extra exits or folding tips.

实际生成提示词（b787-8-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Boeing 787-8 Dreamliner, the SHORTEST variant, NOT 787-9 or stretched 787-10. Proportions: 56.7 m length, 60.1 m wingspan, 16.9 m height. Shorter fore/aft fuselage sections while keeping a graceful widebody shape. Smoothly drooping tapered Dreamliner nose/cockpit glazing, FOUR main passenger doors, one row of generous oval cabin windows. Swept flexible wings with thin RAKED tips continuing in the wing plane, no separate vertical winglets. Exactly TWO Dreamliner under-wing turbofans with clearly modeled small rear nacelle CHEVRONS, recessed intake fan/spinner and silver rim. Correct fin, swept tailplanes and tapered tail cone. Near engine clear, far naturally occluded. No Airbus visor, extra exits or folding tips.
```

### A321NEO

- [制造商官方资料](https://www.aircraft.airbus.com/en/aircraft/a320-family/a321neo)
- [制造商官方资料](https://www.airbus.com/en/newsroom/press-releases/2018-01-airbus-rolls-out-first-a321neo-acf)

选用几何约束：Airbus A321neo passenger jet, representative Airbus Cabin Flex configuration, independently generated NOT an edit/reuse of A321LR. Proportions: 44.51 m length, 3.95 m body width, 35.80 m wingspan, 11.76 m height. Standard A321neo fuselage length, same external family dimensions as LR; do NOT invent an externally shorter LR distinction or draw fuel tanks outside. Long single-aisle fuselage, rounded Airbus nose/angular cockpit panes without A350 visor, single window row, sensible ACF front/aft doors and paired over-wing exits; rear-section door according to representative configuration. Tall blended Airbus Sharklets. Exactly TWO representative Pratt & Whitney PW1100G-style geared turbofans, large round nacelles with smooth non-chevron exhaust edges, detailed inlet/fan. Correct fin and swept tailplanes. Near engine clear, far naturally occluded. Not A321ceo or XLR.

实际生成提示词（a321neo-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Airbus A321neo passenger jet, representative Airbus Cabin Flex configuration, independently generated NOT an edit/reuse of A321LR. Proportions: 44.51 m length, 3.95 m body width, 35.80 m wingspan, 11.76 m height. Standard A321neo fuselage length, same external family dimensions as LR; do NOT invent an externally shorter LR distinction or draw fuel tanks outside. Long single-aisle fuselage, rounded Airbus nose/angular cockpit panes without A350 visor, single window row, sensible ACF front/aft doors and paired over-wing exits; rear-section door according to representative configuration. Tall blended Airbus Sharklets. Exactly TWO representative Pratt & Whitney PW1100G-style geared turbofans, large round nacelles with smooth non-chevron exhaust edges, detailed inlet/fan. Correct fin and swept tailplanes. Near engine clear, far naturally occluded. Not A321ceo or XLR.
```

### B737-800

- [制造商官方资料](https://www.boeing.com/commercial/737ng)

选用几何约束：Boeing 737-800 Next Generation, NOT MAX 8 or 737-900. Proportions: 39.5 m length, 35.8 m wingspan with winglets, about 12.5 m height. Standard slender 737 single-aisle body, pointed Boeing nose/angular cockpit panes, one window row, front/aft doors and paired over-wing emergency exits. Representative classic BLENDED UPWARD winglets, not MAX Advanced Technology split upper/lower tips. Exactly TWO CFM56-7B-style engines with distinctive somewhat FLATTENED LOWER inlet/nacelle shape and smooth NON-CHEVRON rear edges, not rounder larger MAX LEAP-1B engines. Correct 737 vertical fin with dorsal root and horizontal stabilizers. Near engine clear, far naturally occluded. Gear retracted, no visible wheels. No obsolete eyebrow windows are required.

实际生成提示词（b737-800-side-right-v1.png）：

```text
Use case: stylized-concept
Asset type: model-specific static three-dimensional aircraft illustration for a mobile aircraft collection.
Generate exactly ONE complete aircraft independently FROM SCRATCH. No previous aircraft picture as input, no tracing, stretching, relabeling or shape borrowing.
Style: refined premium CG scale-model illustration, not a real aviation photograph or a bloated toy. Pearl-satin white unpainted body and tail, no airline livery. Broad soft studio highlights describe rounded fuselage volume; gentle gray underside, crisp contours, soft contact self-shadows at wing roots/pylons/tail. Detailed dark recessed fan blades/spinner, subtle metal inlet rims and leading edges, discreet flap/control-surface divisions and door seams. Moderate precise detail; no grime, dense rivet noise, chrome glare or blur.
Camera/composition: wide horizontal near-lateral side view, nose RIGHT, tail LEFT, fuselage level, only slight natural perspective to show intake depth and wing thickness. Not front three-quarter, top-down or banked. Complete uncropped nose/tail/wingtips, centered at about 88 percent of canvas width with clear margins. All landing gear fully retracted.
Background: genuinely transparent alpha outside the silhouette, clean antialiased edges, no white fringe, glow, haze, floor, stand, scenery or external cast shadow.
Text: none. No manufacturer/engine/airline logos, registration, model lettering, labels, UI or watermark. Original model illustration, not engineering-certified CAD or a specific airline registration.
Model geometry (priority): Boeing 737-800 Next Generation, NOT MAX 8 or 737-900. Proportions: 39.5 m length, 35.8 m wingspan with winglets, about 12.5 m height. Standard slender 737 single-aisle body, pointed Boeing nose/angular cockpit panes, one window row, front/aft doors and paired over-wing emergency exits. Representative classic BLENDED UPWARD winglets, not MAX Advanced Technology split upper/lower tips. Exactly TWO CFM56-7B-style engines with distinctive somewhat FLATTENED LOWER inlet/nacelle shape and smooth NON-CHEVRON rear edges, not rounder larger MAX LEAP-1B engines. Correct 737 vertical fin with dorsal root and horizontal stabilizers. Near engine clear, far naturally occluded. Gear retracted, no visible wheels. No obsolete eyebrow windows are required.
```

## 验证

统一映射、pubspec 与全部型号的 widget 资产加载测试已更新；本批运行结果在 [机型插画制作进度](aircraft-artwork-progress.md) 记录。不以历史原生截图冒充本批所有机型已在真机目视验证。
