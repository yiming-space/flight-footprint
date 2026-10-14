# 四款机翼透视关系返修 — 2026-10-14

## 用户反馈与修正边界

用户截图指出 A330-900NEO、B737 MAX 8、A321NEO、B737-800 后方翅膀不对。此前 v1 的远侧主翼突出到前舱上方，近侧翼尖又靠近尾部，产生反向/重复翅膀的视觉错位；上一轮接入测试没有识别这个图像几何缺陷。**代码测试通过并不等于机型结构正确。** 本轮只重做这四款，另外十二款及所有 UI 布局不变。

使用 **imagegen 技能、内置工具模式**，四款各从零独立生成 v2，没有旧图片输入，没有在 v1 上修几何、没有复用另一型号、未用 CLI/API。先暂存全部四款，目视确认主要结构后统一接入，保留 v1 便于回退，续做任务保持暂停。相机约束改为接近正侧视的长焦/正交投影，远侧主翼自然遮挡；明确水平尾翼无翼梢装置，主翼根在中部、向左后掠，近侧主翼翼尖和平尾必须分开。白色无涂装、机头向右、起落架收起、静态三维质感与透明背景保持。

## 新版素材与核对

- A330-900NEO: `assets/images/aircraft/a330-900neo-side-right-v2.png`，2172×724。主翼从机身中部向左后掠，近侧曲线 Sharklet 与尾部水平安定面分离；前段机身上方不再有独立远侧翼尖。远侧主翼遮挡、尾部平尾没有 Sharklet。四门和双发代表外观保留。
- B737 MAX 8: `assets/images/aircraft/b737-max-8-side-right-v2.png`，1983×793。主翼从中部后掠，MAX 上/下分叉翼尖在同一近侧主翼尖，尾部水平安定面为无翼梢装置的常规平尾；前段机身上方的异常远侧翼尖消除。LEAP 尾缘锯齿保留。
- A321NEO: `assets/images/aircraft/a321neo-side-right-v2.png`，2048×768。中部主翼与尾翼分开，Sharklet 附属于近侧主翼尖，远侧主翼不在前舱上方伸出独立鳍片；常规平尾无向上翼梢。保持长窄体、neo 发动机代表外观，未把 LR 图片复用过来。
- B737-800: `assets/images/aircraft/b737-800-side-right-v2.png`，2073×758。737NG 单一上扬 blended winglet 随近侧主翼后掠，不在尾翼上添加翼梢或在前段上方复制远侧翼尖；平尾保持常规无翼梢装置，发动机尾缘为光滑 NG 代表配置。

四张 PNG 都带真实 alpha；机体外六点抽样透明值均为 0，未重编码或手工修改像素。目视核对针对可见翼根、后掠方向、翼梢/尾翼分离和完整轮廓，不是工程认证或精确 CAD；特定航空公司的发动机和出口配置仍可能不同。原始生成路径、实际提示词和断点在 `../../outputs/aircraft-wing-correction-20261014/manifest.json`。

## 官方资料与完整实际提示词

### A330-900NEO

- [制造商官方资料](https://www.aircraft.airbus.com/en/aircraft/a330/a330-900)

```text
Use case: stylized-concept
Asset type: one model-specific aircraft illustration for a mobile collection.
Generate a completely NEW aircraft FROM SCRATCH, not an edit of any previous picture and not reused from another model.
Style: refined three-dimensional CG scale-model illustration, pearl satin WHITE unpainted fuselage and tail. Soft restrained studio light gives rounded volume, gentle gray belly and self-shadows, subtle metal leading edges, visible recessed fan blades, understated door and flap seams. No livery, text, logos, registration, watermark, grime or extreme chrome.
Camera: TRUE near-orthographic SIDE ELEVATION, nose RIGHT tail LEFT, fuselage exactly horizontal. Camera perpendicular to longitudinal axis: ZERO front/rear three-quarter yaw; only 2 degrees above the fuselage centerline for slight wing surface depth, long-lens orthographic look. Do not use a dramatic front three-quarter angle. Main far wing and far engine mostly OCCLUDED. Keep complete uncropped silhouette within 90% canvas width, with generous clear margins on all sides. Gear fully retracted.
Background: genuine fully transparent alpha outside the aircraft. No floor, stand, haze, glow, exterior shadow, white fringes or scenery.

Model-specific geometry: Airbus A330-900neo, NOT classic A330-300 or shorter A330-800. Proportions: 63.69 m length, 5.64 m fuselage width, 64.00 m wingspan, 16.79 m height. Long twin-aisle body with FOUR main passenger doors and one window row. A330 nose and angular cockpit glazing, representative dark surrounding cockpit mask of A330neo. New swept wings with LARGE gracefully CURVED A350-inspired Sharklets, not the classic A330's small canted winglets. Exactly TWO large Rolls-Royce Trent 7000-style turbofans, rounded nacelles, smooth non-chevron exhaust edges, proper new pylons. Near engine clear, far engine naturally occluded. Correct A330 swept fin/tailplanes and restrained belly fairing.
CRITICAL anatomy and projection: There is exactly ONE vertical tail fin at the aft end, with a conventional pair of swept HORIZONTAL tail stabilizers at the tail. Horizontal stabilizers have plain tapered tips, NEVER upright winglets, split tips or sharklets. Main wings are attached ONLY at the MID-body wing box below the cabin windows. Both main wings sweep BACK towards the LEFT tail, never forward. The near wing's root is around the middle of the fuselage and its tapered tip is farther LEFT but clearly separate from and in front of the tail assembly. The far main wing is geometrically consistent with the near wing and is occluded behind the body/near wing in this true side projection; do NOT place a detached far-wing fin above the forward fuselage. No fins sprouting from the nose, front cabin or tailplane. No duplicated fins or reversed wing, no long wingtip extending past the tail. Show the wing root and correct rearward sweep coherently.
```

### B737 MAX 8

- [制造商官方资料](https://www.boeing.com/commercial/737max)

```text
Use case: stylized-concept
Asset type: one model-specific aircraft illustration for a mobile collection.
Generate a completely NEW aircraft FROM SCRATCH, not an edit of any previous picture and not reused from another model.
Style: refined three-dimensional CG scale-model illustration, pearl satin WHITE unpainted fuselage and tail. Soft restrained studio light gives rounded volume, gentle gray belly and self-shadows, subtle metal leading edges, visible recessed fan blades, understated door and flap seams. No livery, text, logos, registration, watermark, grime or extreme chrome.
Camera: TRUE near-orthographic SIDE ELEVATION, nose RIGHT tail LEFT, fuselage exactly horizontal. Camera perpendicular to longitudinal axis: ZERO front/rear three-quarter yaw; only 2 degrees above the fuselage centerline for slight wing surface depth, long-lens orthographic look. Do not use a dramatic front three-quarter angle. Main far wing and far engine mostly OCCLUDED. Keep complete uncropped silhouette within 90% canvas width, with generous clear margins on all sides. Gear fully retracted.
Background: genuine fully transparent alpha outside the aircraft. No floor, stand, haze, glow, exterior shadow, white fringes or scenery.

Model-specific geometry: Boeing 737 MAX 8, specifically standard MAX 8 NOT MAX 9, MAX 10, 737-800NG or high-density 8-200. Proportions: 39.5 m length, 35.9 m wingspan, 12.3 m height, shorter body sections than MAX 9. Slender single-aisle 737 fuselage, pointed Boeing nose, angular cockpit panes without Airbus visor, one cabin-window row, front/aft entry doors and paired over-wing emergency exits. No extra mid-aft 8-200/MAX9 exit or plug outline. Swept wings with distinctive MAX Advanced Technology SPLIT upper/lower wingtip elements, not Airbus Sharklets. Exactly TWO CFM LEAP-1B-style engines forward/up mounted, rounded intake lips and subtle rear nacelle CHEVRONS, not flat-bottom old CFM56 nacelles. Correct 737 fin/dorsal root and tailplanes. Near engine clear, far naturally occluded.
CRITICAL anatomy and projection: There is exactly ONE vertical tail fin at the aft end, with a conventional pair of swept HORIZONTAL tail stabilizers at the tail. Horizontal stabilizers have plain tapered tips, NEVER upright winglets, split tips or sharklets. Main wings are attached ONLY at the MID-body wing box below the cabin windows. Both main wings sweep BACK towards the LEFT tail, never forward. The near wing's root is around the middle of the fuselage and its tapered tip is farther LEFT but clearly separate from and in front of the tail assembly. The far main wing is geometrically consistent with the near wing and is occluded behind the body/near wing in this true side projection; do NOT place a detached far-wing fin above the forward fuselage. No fins sprouting from the nose, front cabin or tailplane. No duplicated fins or reversed wing, no long wingtip extending past the tail. Show the wing root and correct rearward sweep coherently.
```

### A321NEO

- [制造商官方资料](https://www.aircraft.airbus.com/en/aircraft/a320-family/a321neo)
- [制造商官方资料](https://www.airbus.com/en/newsroom/press-releases/2018-01-airbus-rolls-out-first-a321neo-acf)

```text
Use case: stylized-concept
Asset type: one model-specific aircraft illustration for a mobile collection.
Generate a completely NEW aircraft FROM SCRATCH, not an edit of any previous picture and not reused from another model.
Style: refined three-dimensional CG scale-model illustration, pearl satin WHITE unpainted fuselage and tail. Soft restrained studio light gives rounded volume, gentle gray belly and self-shadows, subtle metal leading edges, visible recessed fan blades, understated door and flap seams. No livery, text, logos, registration, watermark, grime or extreme chrome.
Camera: TRUE near-orthographic SIDE ELEVATION, nose RIGHT tail LEFT, fuselage exactly horizontal. Camera perpendicular to longitudinal axis: ZERO front/rear three-quarter yaw; only 2 degrees above the fuselage centerline for slight wing surface depth, long-lens orthographic look. Do not use a dramatic front three-quarter angle. Main far wing and far engine mostly OCCLUDED. Keep complete uncropped silhouette within 90% canvas width, with generous clear margins on all sides. Gear fully retracted.
Background: genuine fully transparent alpha outside the aircraft. No floor, stand, haze, glow, exterior shadow, white fringes or scenery.

Model-specific geometry: Airbus A321neo passenger jet, representative Airbus Cabin Flex configuration, independently generated NOT an edit/reuse of A321LR. Proportions: 44.51 m length, 3.95 m body width, 35.80 m wingspan, 11.76 m height. Standard A321neo fuselage length, same external family dimensions as LR; do NOT invent an externally shorter LR distinction or draw fuel tanks outside. Long single-aisle fuselage, rounded Airbus nose/angular cockpit panes without A350 visor, single window row, sensible ACF front/aft doors and paired over-wing exits; rear-section door according to representative configuration. Tall blended Airbus Sharklets. Exactly TWO representative Pratt & Whitney PW1100G-style geared turbofans, large round nacelles with smooth non-chevron exhaust edges, detailed inlet/fan. Correct fin and swept tailplanes. Near engine clear, far naturally occluded. Not A321ceo or XLR.
CRITICAL anatomy and projection: There is exactly ONE vertical tail fin at the aft end, with a conventional pair of swept HORIZONTAL tail stabilizers at the tail. Horizontal stabilizers have plain tapered tips, NEVER upright winglets, split tips or sharklets. Main wings are attached ONLY at the MID-body wing box below the cabin windows. Both main wings sweep BACK towards the LEFT tail, never forward. The near wing's root is around the middle of the fuselage and its tapered tip is farther LEFT but clearly separate from and in front of the tail assembly. The far main wing is geometrically consistent with the near wing and is occluded behind the body/near wing in this true side projection; do NOT place a detached far-wing fin above the forward fuselage. No fins sprouting from the nose, front cabin or tailplane. No duplicated fins or reversed wing, no long wingtip extending past the tail. Show the wing root and correct rearward sweep coherently.
```

### B737-800

- [制造商官方资料](https://www.boeing.com/commercial/737ng)

```text
Use case: stylized-concept
Asset type: one model-specific aircraft illustration for a mobile collection.
Generate a completely NEW aircraft FROM SCRATCH, not an edit of any previous picture and not reused from another model.
Style: refined three-dimensional CG scale-model illustration, pearl satin WHITE unpainted fuselage and tail. Soft restrained studio light gives rounded volume, gentle gray belly and self-shadows, subtle metal leading edges, visible recessed fan blades, understated door and flap seams. No livery, text, logos, registration, watermark, grime or extreme chrome.
Camera: TRUE near-orthographic SIDE ELEVATION, nose RIGHT tail LEFT, fuselage exactly horizontal. Camera perpendicular to longitudinal axis: ZERO front/rear three-quarter yaw; only 2 degrees above the fuselage centerline for slight wing surface depth, long-lens orthographic look. Do not use a dramatic front three-quarter angle. Main far wing and far engine mostly OCCLUDED. Keep complete uncropped silhouette within 90% canvas width, with generous clear margins on all sides. Gear fully retracted.
Background: genuine fully transparent alpha outside the aircraft. No floor, stand, haze, glow, exterior shadow, white fringes or scenery.

Model-specific geometry: Boeing 737-800 Next Generation, NOT MAX 8 or 737-900. Proportions: 39.5 m length, 35.8 m wingspan with winglets, about 12.5 m height. Standard slender 737 single-aisle body, pointed Boeing nose/angular cockpit panes, one window row, front/aft doors and paired over-wing emergency exits. Representative classic BLENDED UPWARD winglets, not MAX Advanced Technology split upper/lower tips. Exactly TWO CFM56-7B-style engines with distinctive somewhat FLATTENED LOWER inlet/nacelle shape and smooth NON-CHEVRON rear edges, not rounder larger MAX LEAP-1B engines. Correct 737 vertical fin with dorsal root and horizontal stabilizers. Near engine clear, far naturally occluded. Gear retracted, no visible wheels. No obsolete eyebrow windows are required.
CRITICAL anatomy and projection: There is exactly ONE vertical tail fin at the aft end, with a conventional pair of swept HORIZONTAL tail stabilizers at the tail. Horizontal stabilizers have plain tapered tips, NEVER upright winglets, split tips or sharklets. Main wings are attached ONLY at the MID-body wing box below the cabin windows. Both main wings sweep BACK towards the LEFT tail, never forward. The near wing's root is around the middle of the fuselage and its tapered tip is farther LEFT but clearly separate from and in front of the tail assembly. The far main wing is geometrically consistent with the near wing and is occluded behind the body/near wing in this true side projection; do NOT place a detached far-wing fin above the forward fuselage. No fins sprouting from the nose, front cabin or tailplane. No duplicated fins or reversed wing, no long wingtip extending past the tail. Show the wing root and correct rearward sweep coherently.
```

## 验证结果

41 项定向测试通过，2 个修改的 Dart 文件静态分析无问题；模拟器一次热重启成功（919 ms）。原生截图已核对 A330neo、A321neo 的当前卡片显示和透明边缘；两款 737 有生成 PNG 目视与 widget 资产加载验证，未用这两张截图冒充四款原生验收。用户表示自行核验后停止模拟器操作，四款状态为“已接入、待用户核验”。详见[制作进度](aircraft-artwork-progress.md)；保留旧批次记录作为历史，不用旧版测试证明新版几何准确。
