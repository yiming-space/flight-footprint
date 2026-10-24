# Core family artwork generation — 2026-10-18

Status: generated, inspected, integrated locally and validated; pending user visual acceptance.

Mode: built-in imagegen, new generation from scratch, transparent_background=true, no image references. Each aircraft is independent. Existing exact-model illustrations retain priority.

## 本批接入与复验

- 使用内置 imagegen 从零独立生成四次，无旧图片输入、无付费 API、无购买或重置额度。四张全部生成并检查后统一接入；RGBA 2048×768，总计 4,910,795 字节。
- A330、A321、A320、B737 普通家族文字分别使用四张新代表图。A321 CEO 不再借用 A320 的短机身；A318/A319 仍采用 A320 家族代表，不承诺子型号长度一致。已有 16 款具体型号专属图与其优先级保持不变，特别是 A330-300、A320-200、B737-800 仍用原专属图。CEO/NEO 与 NG/MAX 分开，不改收藏名称、key、次数、里程或航班数据。
- 目视检查：机头向右、水平正侧面、完整轮廓、起落架收起；A330 的宽体与四舱门、A321 的长机身与四舱门、A320 的双翼上出口、737 NG 的融合翼梢与平滑发动机尾缘可辨。A321 翼梢生成结果高于提示词所要求的原式翼尖围栏，按 A321ceo 可选 Sharklet 风格的家族示意接受，不宣称是原式围栏配置或精确 CAD。
- 四角与上中、下中等六个机体外样本 alpha 均为 0；alpha>8 轮廓边界都在画布内。原始透明 PNG 的 RGB 预览存在灰色环境色，但 Flutter 实际深浅背景合成没有灰底或光晕。未裁切、未改形、未手动抠图。
- 七个机型相关测试文件共 64 项通过；本次三个 Dart 文件静态分析无问题。深浅主题的 8 个实际解码帧通过加载，未出现缺图回退。
- 实际合成预览：`.impeccable/review/aircraft-family-core-20261018.png`。这是组件渲染预览，不是四款真机截图验收。
- 模拟器连接检查：`adb devices` 没有设备，旧 Flutter 会话已报告 Lost connection to device；本轮没有声称热加载成功，没有启动或清空设备数据。
- 仅本地开发版本接入；不改已发布 v1.4.0 安装包或更新清单，不发布 GitHub，不操作服务部署。自动续做任务仍保持暂停。

## 资产与来源

| 家族 | 文件 | 原始生成文件 |
| --- | --- | --- |
| A330 | `assets/images/aircraft/a330-family-side-right-v1.png` | `exec-a7177609-37ec-47ae-9e87-ad2fd733d888.png` |
| A321 | `assets/images/aircraft/a321-family-side-right-v1.png` | `exec-9d10c087-ab5e-41d4-83f2-aa9956ccadec.png` |
| A320 | `assets/images/aircraft/a320-family-side-right-v1.png` | `exec-899dc69a-5804-4115-864a-a3a822f960cc.png` |
| B737 | `assets/images/aircraft/b737-family-side-right-v1.png` | `exec-6a4334b0-6dfb-4724-8683-10064230edac.png` |

暂存、原图路径和 SHA256 见外层 `outputs/aircraft-family-core-20261018/manifest.json`。完整实际提示词及制造商参考如下。

## Manufacturer reference sources

- A330-300: https://www.aircraft.airbus.com/en/aircraft/a330/a330-300
- A321ceo: https://www.aircraft.airbus.com/en/aircraft/a320-family/a321ceo
- A320ceo: https://www.aircraft.airbus.com/en/aircraft/a320-family/a320ceo
- Airbus A320 airport-planning manual: https://aircraft.airbus.com/sites/g/files/jlcbta126/files/2023-12/ac_a320_1223.pdf
- Airbus A321 airport-planning manual: https://aircraft.airbus.com/sites/g/files/jlcbta126/files/2025-07/AC_A321_20250715.pdf
- Boeing 737 NG: https://www.boeing.com/Commercial/737ng/737-next-generation-design-highlights
- Boeing 737 NG airport-planning manual: https://www.boeing.com/content/dam/boeing/boeingdotcom/commercial/airports/acaps/737NG_REV_B.pdf

Note: illustrative family representatives, not CAD or exact individual airframe documentation. CEO/neo and NG/MAX separation is retained.

## Complete prompts

## A330

Create a brand-new standalone collectible-aircraft illustration for a mobile aircraft-family collection. One aircraft only. Precise engineering-informed silhouette, refined restrained 3D illustration, not a photograph or toy. Satin unpainted white fuselage and wings, subtle neutral grey underside, dark cockpit glass, small orderly cabin windows, restrained door and panel lines. No airline livery, logos, registration, labels, text, dimensions or watermark.

CAMERA IS CRITICAL: a true dead-on ORTHOGRAPHIC SIDE ELEVATION. The longitudinal axis is exactly horizontal. Nose points RIGHT, tail at LEFT. Camera is at fuselage centreline height, looking exactly 90 degrees perpendicular to the fuselage, with zero yaw, zero elevation, zero perspective. NOT a three-quarter view, NOT looking from above, NOT looking into the nose or engine intake. The near engine is seen in its long side profile; the far engine naturally overlaps or is mostly occluded in this exact side projection. Main wings are nearly edge-on rather than fanning diagonally across the fuselage. Anatomically correct low conventional horizontal tailplanes at the extreme aft fuselage, plain horizontal tail tips, ONE vertical fin, no winglets on horizontal stabilizers and no extra fins.

Aircraft in flight, wings level, all landing gear completely retracted and gear doors closed. Keep the complete nose, tail, wings and tips inside the frame with about 6 percent clear margin. Wide landscape canvas, around 2048 by 768, aircraft fills the width. Soft neutral studio-style shading on the aircraft itself, polished but restrained detailing. REAL TRANSPARENT BACKGROUND: alpha zero everywhere outside the aircraft silhouette. No sky, floor, ground plane, cast shadow, glow, halo, backdrop, gradient, or checkerboard. The translucent-looking grey/black preview is not a background to draw.

SUBJECT: Airbus A330 family, represented by an A330-300 CEO passenger airliner with two Rolls-Royce Trent 700 turbofans under the wings (not the A330neo). Preserve its long widebody proportions: 63.66 m length, 5.64 m fuselage width, 16.79 m overall height; swept wing with the original small straight canted winglets, not tall curved A330neo/A350 tips. One single-deck passenger window row, classic Airbus A330 cockpit shape and rounded tapering nose, four evenly separated large closed passenger-door positions along the visible side. Tall smoothly swept conventional vertical tail and low plain horizontal stabilizers. Trent 700 cylindrical nacelles, no chevron exhaust serrations, not enormous neo nacelles. A330 must be visibly much longer and wider-bodied than an A320. Do not invent additional tail wings or attach a main-wing winglet to the tail.

## A321

Create a brand-new standalone collectible-aircraft illustration for a mobile aircraft-family collection. One aircraft only. Precise engineering-informed silhouette, refined restrained 3D illustration, not a photograph or toy. Satin unpainted white fuselage and wings, subtle neutral grey underside, dark cockpit glass, small orderly cabin windows, restrained door and panel lines. No airline livery, logos, registration, labels, text, dimensions or watermark.

CAMERA IS CRITICAL: a true dead-on ORTHOGRAPHIC SIDE ELEVATION. The longitudinal axis is exactly horizontal. Nose points RIGHT, tail at LEFT. Camera is at fuselage centreline height, looking exactly 90 degrees perpendicular to the fuselage, with zero yaw, zero elevation, zero perspective. NOT a three-quarter view, NOT looking from above, NOT looking into the nose or engine intake. The near engine is seen in its long side profile; the far engine naturally overlaps or is mostly occluded in this exact side projection. Main wings are nearly edge-on rather than fanning diagonally across the fuselage. Anatomically correct low conventional horizontal tailplanes at the extreme aft fuselage, plain horizontal tail tips, ONE vertical fin, no winglets on horizontal stabilizers and no extra fins.

Aircraft in flight, wings level, all landing gear completely retracted and gear doors closed. Keep the complete nose, tail, wings and tips inside the frame with about 6 percent clear margin. Wide landscape canvas, around 2048 by 768, aircraft fills the width. Soft neutral studio-style shading on the aircraft itself, polished but restrained detailing. REAL TRANSPARENT BACKGROUND: alpha zero everywhere outside the aircraft silhouette. No sky, floor, ground plane, cast shadow, glow, halo, backdrop, gradient, or checkerboard. The translucent-looking grey/black preview is not a background to draw.

SUBJECT: Airbus A321 family, represented by an A321-200 CEO with CFM56-5B turbofans and original small wingtip fences (not neo, LR or XLR). Preserve the elongated narrowbody proportions: 44.51 m length and 3.95 m fuselage width, overall height 11.76 m; clearly longer passenger cabin than an A320. Classic rounded A320-family nose and six-panel cockpit glazing. FOUR full-height closed door / emergency-door positions on the visible side: front door near the nose, second door before the wing, third door behind the wing, and fourth door near the tail. Do NOT give it A320's two small overwing emergency hatches. One orderly passenger-window row. Two relatively compact CFM56-5B nacelles under the wings, not oversize neo engines and no chevron exhaust. Small original Airbus wingtip fences only at the main wing, plain tailplane tips. Conventional swept vertical fin and low horizontal stabilizers.

## A320

Create a brand-new standalone collectible-aircraft illustration for a mobile aircraft-family collection. One aircraft only. Precise engineering-informed silhouette, refined restrained 3D illustration, not a photograph or toy. Satin unpainted white fuselage and wings, subtle neutral grey underside, dark cockpit glass, small orderly cabin windows, restrained door and panel lines. No airline livery, logos, registration, labels, text, dimensions or watermark.

CAMERA IS CRITICAL: a true dead-on ORTHOGRAPHIC SIDE ELEVATION. The longitudinal axis is exactly horizontal. Nose points RIGHT, tail at LEFT. Camera is at fuselage centreline height, looking exactly 90 degrees perpendicular to the fuselage, with zero yaw, zero elevation, zero perspective. NOT a three-quarter view, NOT looking from above, NOT looking into the nose or engine intake. The near engine is seen in its long side profile; the far engine naturally overlaps or is mostly occluded in this exact side projection. Main wings are nearly edge-on rather than fanning diagonally across the fuselage. Anatomically correct low conventional horizontal tailplanes at the extreme aft fuselage, plain horizontal tail tips, ONE vertical fin, no winglets on horizontal stabilizers and no extra fins.

Aircraft in flight, wings level, all landing gear completely retracted and gear doors closed. Keep the complete nose, tail, wings and tips inside the frame with about 6 percent clear margin. Wide landscape canvas, around 2048 by 768, aircraft fills the width. Soft neutral studio-style shading on the aircraft itself, polished but restrained detailing. REAL TRANSPARENT BACKGROUND: alpha zero everywhere outside the aircraft silhouette. No sky, floor, ground plane, cast shadow, glow, halo, backdrop, gradient, or checkerboard. The translucent-looking grey/black preview is not a background to draw.

SUBJECT: Airbus A320 family, represented by an A320-200 CEO with CFM56-5B turbofans and original small wingtip fences (not neo). Correct compact narrowbody proportions: 37.57 m overall length, 3.95 m fuselage width and 11.76 m overall height. The cabin is noticeably shorter than an A321. Rounded Airbus A320-family nose and six-panel cockpit glazing. Two large closed passenger doors on the visible side, one near each end, plus TWO small overwing emergency-exit hatches close together at the middle of the cabin. One regular passenger-window row. Two compact CFM56-5B turbofan nacelles under the wings, smooth exhaust edges, no chevrons, not large LEAP or geared-turbofan neo nacelles. Original short upper-and-lower wingtip fences only at main-wing tips, not tall Sharklets. Correct low horizontal tailplanes with plain tips and one swept vertical tail.

## B737

Create a brand-new standalone collectible-aircraft illustration for a mobile aircraft-family collection. One aircraft only. Precise engineering-informed silhouette, refined restrained 3D illustration, not a photograph or toy. Satin unpainted white fuselage and wings, subtle neutral grey underside, dark cockpit glass, small orderly cabin windows, restrained door and panel lines. No airline livery, logos, registration, labels, text, dimensions or watermark.

CAMERA IS CRITICAL: a true dead-on ORTHOGRAPHIC SIDE ELEVATION. The longitudinal axis is exactly horizontal. Nose points RIGHT, tail at LEFT. Camera is at fuselage centreline height, looking exactly 90 degrees perpendicular to the fuselage, with zero yaw, zero elevation, zero perspective. NOT a three-quarter view, NOT looking from above, NOT looking into the nose or engine intake. The near engine is seen in its long side profile; the far engine naturally overlaps or is mostly occluded in this exact side projection. Main wings are nearly edge-on rather than fanning diagonally across the fuselage. Anatomically correct low conventional horizontal tailplanes at the extreme aft fuselage, plain horizontal tail tips, ONE vertical fin, no winglets on horizontal stabilizers and no extra fins.

Aircraft in flight, wings level, all landing gear completely retracted and gear doors closed. Keep the complete nose, tail, wings and tips inside the frame with about 6 percent clear margin. Wide landscape canvas, around 2048 by 768, aircraft fills the width. Soft neutral studio-style shading on the aircraft itself, polished but restrained detailing. REAL TRANSPARENT BACKGROUND: alpha zero everywhere outside the aircraft silhouette. No sky, floor, ground plane, cast shadow, glow, halo, backdrop, gradient, or checkerboard. The translucent-looking grey/black preview is not a background to draw.

SUBJECT: Boeing 737 NG family, represented by a Boeing 737-800 passenger jet with CFM56-7B turbofans and single upward curved blended winglets. NOT 737 MAX, NOT 737 Classic. Preserve 39.5 m length, 35.8 m wingspan including winglets and 12.5 m overall height. Narrow slender fuselage, distinct pointed Boeing 737 nose, angular six-pane cockpit windows and classic swept vertical tail with its dorsal fin fillet. Two large closed passenger doors on the visible side near the front and rear, plus TWO small overwing exit hatches close together. One passenger-window row. Two CFM56-7B engines with the characteristic flattened nacelle underside and modest size, smooth nacelle exhaust rims: NO serrated MAX chevrons, NO oversize LEAP engines. Main-wing tips have one smoothly curved upward blended winglet, not MAX's two-pronged split-scimitar tip, and horizontal tailplane tips are plain. The exact side projection must not look like an oblique frontal aircraft.
