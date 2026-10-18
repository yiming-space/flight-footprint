# 地图定位旅行者（2026-10-16）

> 当前状态：已撤回。用户最终选择恢复原定位圆点。小人渲染、呼吸动效、相应独立测试及资源打包项已移除；下方素材和提示词仅作实验记录保留，不再用于 App。地图航线、区域点亮和远景普通标点尺寸不变。

撤回验证：详细地图样式/默认入口/足迹/航线缓存/几何共 39 项测试通过，4 个相关文件静态分析无问题；定位圆点恢复原蓝色、半径 6、白色描边 2.5，无小人计时器或手势监听接入。

用户选择：背小背包的简洁旅行者；轻微呼吸，地图拖动时暂停。首版代码绘制图标被用户否定，改为内置 image_gen 生成的 3D 卡通透明资产，不保留旧小人视觉。

## 资产和生成记录

- 正式资产：`assets/images/map/traveler-location-3d-v1.png`，1024×1536 RGBA，真实 alpha；四角 alpha 均为 0。原文件复制到项目，未进行外部抠图或透明度修改。
- 原始生成：`/Users/yiming/.codex/generated_images/01a07f46-1067-7a62-8b93-93b5b90d94ce/exec-9c2fd082-255f-4402-9b8a-bd5d57b101a8.png`。
- 选用紧凑比例版本：`/Users/yiming/.codex/generated_images/01a07f46-1067-7a62-8b93-93b5b90d94ce/exec-601e20e1-15c9-4b0f-86e2-dcc7858cac09.png`。第二次是仅针对比例的内置工具编辑，不冒充从零生成。
- alpha>8 轮廓 bbox 为 [182,43,848,1517]；仅在 Flutter 绘制源矩形中去掉透明边距，鞋底固定在屏幕投影坐标。解码高度限制为 256，生成源保留原分辨率。

### 初次完整提示词

Use case: stylized-concept. Asset type: a single transparent PNG character sprite for the current-location marker in a travel map mobile app, readable at 34–42 logical pixels tall. Generate from scratch one refined 3D cartoon backpack traveler, full body, standing calmly with BOTH feet planted level, arms relaxed at sides. Gender-neutral young adult proportions, about 3.5 heads tall, charming but not babyish, rounded sculpted shapes and a clean easily recognized silhouette. Three-quarter REAR view turned slightly toward the right so the backpack is clearly visible and just a little cheek/profile is visible. Short dark sculpted hair, light sky-blue travel jacket, a small fresh lime-green backpack with rounded flap and simple straps, dark navy trousers, clean off-white sneakers. Fine satin vinyl / soft clay-like 3D material, tasteful soft ambient occlusion and gentle studio highlights, not a flat icon, not photoreal, not glossy plastic glare. Single centered character, complete head, hands, backpack and shoes all visible, generous clean separation between legs. Orthographic-like view with minimal perspective distortion, camera around waist-to-chest level, no overhead view. Neutral daylight makes the same sprite readable on both charcoal and white maps. TRUE transparent RGBA background, no floor, no scenery, no rectangular background, no checkerboard drawn into image, no platform, no floating, no cast ground shadow, no circular badge, no border or sticker outline. No text, logos or watermark. Compact portrait silhouette occupying about 80 percent of image height; leave small transparent safety margins around entire body. Only ONE figure and ONE pose, not a contact sheet.

### 紧凑比例定向提示词

Edit the supplied traveler into a COMPACT 3D cartoon map-marker figurine. Change ONLY the body proportions: make the entire figure about THREE HEADS TALL, with a substantially larger head, short compact torso and very short legs, like a carefully sculpted premium chibi vinyl travel collectible. Do not keep the long realistic legs from the original. Keep the same blue hoodie, lime-green backpack, short dark hair, navy trousers, off-white shoes, friendly face/profile and three-quarter rear-facing orientation. Maintain the clean refined soft satin 3D rendering, planted standing pose, both shoes aligned at the same ground height, arms relaxed, full head-to-toe silhouette, clear separation of the feet. Single character, centered and almost fills image with a tight 6% safety margin; no multiple views. Genuinely transparent RGBA background, no backdrop glow, no floor, no cast shadow, no plinth, no outlined sticker border, no text, no logo. It must read clearly as a cute traveler at 40 px tall.

## 实现范围

- 首页/全屏详细地图的当前位置；机场、城市标点、航线、地球与离线备用绘制器不改。旧原生定位圆点设为不可见，保留原增量数据源。
- 高度随 zoom 1–7 从 34 到 42 逻辑像素变化并限幅，按原生相机投影更新位置；超出视口不挂载小人。
- 3.6 秒轻微呼吸循环，脚底锚定，不飞起或跳动。原生相机事件和多指 pointer-down/up/cancel 合并暂停，含拖动后镜头惯性，停稳从当前相位继续。
- Reduce Motion、屏幕阅读器导航模式、禁用 TickerMode、后台/非 resumed 状态均停止循环。只重绘图标，不逐帧重建地图或上传 GeoJSON。新增中英“当前位置”语义标签，不新增定位权限或定位请求。
- 依据 Impeccable 的 animate 和 Apple Design 的连续/可中断反馈原则，只替换造型，维持已有数据、镜头与操作语义。

## 验证

- 31 项定向测试通过：生成资产 256 高度解码/透明角像素、缩放限幅与脚底锚点、无效定位、多指/惯性暂停、相位连续恢复、后台、Reduce Motion、TickerMode、双主题中英语义、详细地图/默认入口及香港足迹回归。
- 6 个相关源码/测试文件静态分析无问题；原生 Android Pixel Fold 模拟器热重启成功（1,026 ms），后续纯代码整理热加载成功。截图确认透明 3D 资产已显示，未继续使用线稿，也没有矩形背景。
- 未完成真机/iOS 动效性能测试；没有宣称 FPS 或电量收益。没有修改航班、足迹、定位权限或发布版本。
