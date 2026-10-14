# v1.3.0 Android 发布验证

日期：2026-10-15。应用版本 `1.3.0+16`，包名 `com.hjmingg.flight_footprint`。

## 构建与验证

- 最终源码：342 项 Flutter 测试通过，`flutter analyze --no-pub` 无问题。
- 反馈 Worker：12 项 Node 测试通过；只读 `/health` 返回正常，本轮没有部署 Worker 或创建真实反馈 Issue。
- APK：117,291,076 字节，包含 arm64-v8a、armeabi-v7a、x86_64，versionName 1.3.0、versionCode 16；非 debuggable。
- APK SHA-256：`078bc7fdaff5f999bf74684a6c08443a3adb6b684ad4760e3a4dad80d5c64f9b`。
- apksigner 校验通过。正式签名证书 SHA-256 与 GitHub v1.2.0 APK 相同：`c13d824fd91c8413afad2d7d2c313914362731fb5d8eb3b1709d7d405d0b5065`。
- 包内保留 16 款具体机型及 1 个通用参考素材。不打包签名私钥、本地配置、航班数据库或开发截图。
- 此次仅发布 Android；macOS 下载仍为 v1.1.5。既有模拟器验证属于开发构建，本轮未覆盖安装正式 APK，不以签名一致冒充真实设备升级测试。

```sh
flutter build apk --release --no-pub \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_LIVE_AIRCRAFT=false \
  --dart-define=FLIGHT_FOOTPRINT_ENABLE_ADSB_LOL_ROUTESET=false \
  --dart-define=FLIGHT_FOOTPRINT_FEEDBACK_URL=https://flight-footprint-feedback.hjmingg-gushen.workers.dev/v1/feedback
```

实验性实时执飞机型及 ADSB.lol 路线回退在正式模式默认关闭，本包也显式传入 false。ADSBdb／adsb.im 常规补全与手动填写保留；接口使用条件确认后才能考虑开放实验能力。航司 Logo 使用已记录的动态公共端点，不打包 Logo 数据库，品牌权利与来源限制见 [数据来源说明](airline-logo-source.md)。
