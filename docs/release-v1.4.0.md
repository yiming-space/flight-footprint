# v1.4.0 · 探索与详细地图更新

发布日期：2026-10-18。Android 版本 `1.4.0+17`，包名 `com.hjmingg.flight_footprint`。

## 更新重点

- 首页自动静默检查更新，有新版本才提示；「我的」保留手动入口，离线不影响记录。
- 详细地图支持足迹板块点亮，优化香港区域、首次加载、角落署名、定位紫色圆点及深浅主题。往返航线采用左右分开的示意弧线，无箭头，线宽与标点随缩放适配；真实轨迹不变形。
- 探索详情新增最远足迹纪念卡、常住城市设置及解锁大洲；展示国家旗帜、到访日期与估算距离。
- 城市和国家／地区统计同时纳入已完成航班与保存足迹；待出行航班在可靠到达时间或推算飞行结束后再自动归档。
- 已解锁机型新增8张主流家族正侧面代表图，保留16张专属插画，优化透视堆叠、详情配色及统计入口翻牌。
- 修复低次数航司胶囊的可读长度，完善航班补全的并发、缓存、失败反馈与手填保护。

## 安装与边界

- 提供通用 Android APK，支持 arm64-v8a、armeabi-v7a、x86_64。与此前正式版使用相同签名，可覆盖安装；建议先导出备份，不要先卸载旧 App。
- 详细底图需要联网，失败时保留本地备用与重试；核心记录仍为本地优先。示意弧线不是实际飞行轨迹，家族插画不是所有子型号的精确外观。
- 实验性实时机型查询及 ADSB.lol 路线回退在正式包中继续显式关闭，保留常规补全与手动填写。
- 本次仅更新 Android；macOS 安装包仍为 v1.1.5。只讨论过的年度回顾、自动恢复点和额外解锁动画未包含在本版。

## 构建验证

- 全项目441项 Flutter 测试通过，`flutter analyze --no-pub` 无问题；反馈 Worker 的12项 Node 测试通过，本次未部署 Worker。
- 使用与正式包相同的两个实验功能关闭参数，机型补全、更新服务与首页启动更新81项定向测试再次通过；该集合与全量测试有重叠，不相加为总数。
- APK：127,066,502字节，versionName `1.4.0`、versionCode `17`；包内未标记 debuggable。实际包含16张专属图、8张家族图及1张旧通用参考图，不包含签名配置、私钥或用户数据库。
- APK SHA-256：`cef6e6b37d10c67c4b43c2cb7b5918c00a680965046c071305511903cd8b98dd`。
- apksigner 校验通过，签名证书 SHA-256 与此前正式版一致：`c13d824fd91c8413afad2d7d2c313914362731fb5d8eb3b1709d7d405d0b5065`。
- 既有模拟器运行的是调试签名包，本轮不卸载、不覆盖安装正式包、不清除用户数据；不以签名一致冒充真机升级验证。

```sh
flutter build apk --release --no-pub \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_LIVE_AIRCRAFT=false \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_ADSB_LOL_ROUTESET=false \
  --dart-define=FLIGHT_FOOTPRINT_FEEDBACK_URL=https://flight-footprint-feedback.hjmingg-gushen.workers.dev/v1/feedback
```

## GitHub 发布

- 正式发布页：[Flight Footprint v1.4.0](https://github.com/yiming-space/flight-footprint/releases/tag/v1.4.0)，非草稿、非预发布，标记为最新版。
- 源码标签 `v1.4.0` 对应提交 `19e106c0c3795195795628c3146c61008332e7f3`。安装包与 SHA256SUMS.txt 均已上传；GitHub 返回的 APK 大小、SHA-256 与本地一致。
- 安装包公开可用后再更新主分支的 update.json，包含版本、build、下载链接、字节数及校验值；保留旧版客户端的检查协议。
