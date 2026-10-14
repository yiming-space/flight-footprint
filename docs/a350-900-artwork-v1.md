# A350-900 静态展品插画 v1

- 工具：内置 imagegen；不是 CLI/API 回退，也不是真 3D 模型。
- 最终资产：`assets/images/aircraft/a350-900-side-right-v1.png`。
- 用途：私人机库版机型图鉴的首张对应机型样板；只映射明确的 A350-900，不复用到 A350-1000、其他机型或未知记录。
- 保留：白色无涂装、柔和简化 3D 质感、适量细节、水平侧视、机头向右、起落架收起、透明 alpha。
- 参考：用户确认的通用客机仅作材质/视角风格参考；[空客 A350-900 官方页面](https://www.aircraft.airbus.com/en/aircraft/a350/a350-900)及其官方照片用于外形参考。
- 外形核对使用官方公开的长度 66.80 m、机身宽度 5.94 m 作为比例参考；这些数值不新增到 App 指标中。
- 生成后做过一次驾驶舱面罩修正。插画已目视核对朝向、单架、主要结构、无文字和涂装；它仍是 AI 风格示意，不是工程精模或尺寸测量资料。
- 官网照片没有打包进 App；其他机型图尚待单独制作确认。

## 初始 Prompt

```text
Use case: precise-object-edit
Asset type: model-specific static aircraft artwork for a Flutter aircraft collection exhibit card.
Input images:
- Image 1 is the EDIT TARGET and approved STYLE authority: a rounded, simplified matte-white 3D-looking generic passenger jet in horizontal side profile, nose right. Keep this style, lighting softness and direction; replace its generic narrow-body geometry.
- Image 2 is an Airbus official A350-900 photo, a GEOMETRY reference only. Use the actual A350-900's silhouette and recognizable features. Do not copy its blue livery, wording, logos, photograph, sky, mountain scenery, lighting or three-quarter camera view.
Primary request: Rebuild the aircraft in Image 1 as a clearly recognizable Airbus A350-900, in the SAME clean horizontal side-profile exhibit view, with tail LEFT and nose RIGHT. Exactly one complete aircraft.
Model characteristics: a long wide-body fuselage, approximately 66.8m length and 5.94m fuselage width proportions (not the longer A350-1000); the A350's distinctive smooth rounded nose and dark wraparound cockpit-window mask; smoothly curved upward/outward blended wingtips rather than the generic jet's sharp angular winglets; two large under-wing turbofan engines in smooth rounded nacelles (far engine naturally occluded in true side view); four understated full-size passenger door outlines along the visible side instead of a narrow-body pair of over-wing emergency exits. One tidy row of small dark cabin windows with sensible door gaps. One vertical fin and horizontal tail surfaces. Landing gear fully retracted.
View: horizontal lateral side elevation, little or no yaw and almost no top-down view. The fuselage is perfectly horizontal. The near wing is naturally foreshortened as seen in profile; do not spread a wing toward the camera or turn the nose toward the viewer.
Keep approved art direction: softly rounded simplified 3D collectible model, matte pearl-white painted body and tail, muted light-silver-gray wing and engine details, neutral dark glazing, diffuse studio self-shading, a few restrained panel/control-surface lines and simple broad engine fan hints. Visibly stylized and clean rather than photographic or toy-like. Do not introduce realistic rivets, dirt, metal grain, harsh chrome or a dense technical mesh.
Composition: one full uncropped airplane, centered on a wide transparent canvas, spanning about 84 percent of the canvas width, with clear margin around the nose, tail and wing tips. Genuinely transparent alpha everywhere outside the aircraft silhouette, crisp clean antialiased edges, no external mist, halo, glow, ground or floor shadow.
Text: none. No printed model names, no registration, no Airbus or airline logos, no livery, no UI, no labels, no watermark. This is an original stylized model illustration, not an engineering-certified drawing.
```

## 单次识别特征修正 Prompt

```text
Use case: precise-object-edit
Edit target: the supplied matte-white Airbus A350-900 style illustration.
Change ONLY the cockpit glazing surround at the RIGHT nose: add the A350's distinctive continuous DARK CHARCOAL wraparound cockpit-window mask (the recognizable black visor / raccoon-mask shape) around all the existing cockpit panes. The dark mask must be a clearly visible broad, elegantly curved band, with dark glazing panes inset within it, not merely a thin gray outline or separate windows floating in white metal. The mask tapers smoothly at its rear edge into the white fuselage.
Keep EVERYTHING ELSE unchanged: exact horizontal side-profile view, nose right/tail left, proportions and silhouette, matte-white softened 3D material, curved wingtip, two-engine configuration, visible engine and fan hints, four door outlines, cabin window row, tail shapes, soft lighting, composition, no text/livery, and genuine transparent alpha. Do not add any logos, labels, extra parts, background, glow or floor shadow. Preserve the clean simplified collectible-model style; do not make it photorealistic.
```
