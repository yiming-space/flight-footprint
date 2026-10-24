# v1.5.0 · 主题、探索记忆与航班时间

发布日期：2026-10-24。Android 版本 `1.5.0+18`，包名 `com.hjmingg.flight_footprint`。本次更新 Android；macOS 下载继续使用 v1.1.5。

## 更新内容

- 调整深浅主题的颜色层级，并将磨砂玻璃表面用于导航和相关卡片；机型收藏页使用更新后的页面背景和卡面颜色。
- 探索页顶部将最远足迹、新抵达城市、最常飞航线和首次记录机型整理为四张横向循环卡片。卡片保持统一尺寸，支持滑动切换；有对应记录时可打开相关航班。
- 首页和横向全屏地图显示航线方向箭头，便于辨认航线方向。没有实际航迹的航线仍为地图示意线。
- 航班录入和展示按机场时区处理当地时间，统计年份按出发机场当地日期归类。采用时区数据库规则处理夏令时；当地时间不存在或对应两个时刻时会明确提示，不会静默选择偏移。
- 机场时区数据随 App 提供，离线可用；无有效机场时区的旧记录在年度统计中沿用设备本地年份兼容逻辑。历史保存的绝对时间不会被批量改写。
- 正式包继续关闭实验性实时机型查询和 ADSB.lol 路线回退，保留常规航班补全与手动填写。

## 验证

- 514 项 Flutter 测试通过，`flutter analyze --no-pub` 通过。
- APK 大小为 134,383,420 字节，versionName 为 `1.5.0`、versionCode 为 `18`；包含 `arm64-v8a`、`armeabi-v7a`、`x86_64`，未标记 `application-debuggable`。
- `apksigner` 校验通过；签名证书 SHA-256 为 `c13d824fd91c8413afad2d7d2c313914362731fb5d8eb3b1709d7d405d0b5065`，与 v1.4.0 APK 一致。APK 文件 SHA-256 为 `56df0b2bc8b32535ee632a5eaafecf6e5e8d7c60ad70634bd4f24c090568391a`。
- APK 包含 16 张具体机型专属插画、12 张家族代表图和 1 张旧通用参考图，共 29 张机型图像素材。
- 当前模拟器运行的是调试签名版本；本次没有覆盖安装 release APK，也没有清除模拟器数据，因此未完成该设备上的正式版升级验收。
- Android release 构建沿用正式版参数：

```sh
flutter build apk --release --no-pub \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_LIVE_AIRCRAFT=false \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_ADSB_LOL_ROUTESET=false \
  --dart-define=FLIGHT_FOOTPRINT_FEEDBACK_URL=https://flight-footprint-feedback.hjmingg-gushen.workers.dev/v1/feedback
```

## GitHub 发布

- 正式发布页：[Flight Footprint v1.5.0](https://github.com/yiming-space/flight-footprint/releases/tag/v1.5.0)，非草稿、非预发布，并设为最新版。
- 源码标签 `v1.5.0` 对应提交 `bb5032068585e64a55b98ca7841dd2c39b4861c6`。
- `app-release.apk` 与 `SHA256SUMS.txt` 已上传。GitHub 返回的 APK 大小及 SHA-256 与本地一致，公开下载地址返回 HTTP 200。
- 安装包公开可用后更新主分支 `update.json`，包含版本、build、下载链接、字节数及校验值，保留既有客户端检查协议。
