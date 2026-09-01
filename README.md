# 航迹 · Flight Footprint

一个独立、离线、本地优先的 Flutter 飞行记录应用。1.1 支持 Android，数据无需登录即可记录在设备内；云同步和版本检查都是可选的自建能力。

<img width="4646" height="2000" alt="app001" src="https://github.com/user-attachments/assets/5e748ff7-1738-4226-b1e4-d3fc370261d6" />
<img width="4646" height="2000" alt="app002" src="https://github.com/user-attachments/assets/ead33335-ac84-4cc8-8848-cbd23788f243" />

## 1.1 功能

- 飞行地图 / 旅行足迹离线切换
- 航班快速记录、年份筛选与长按删除
- 总里程、机场、机型、航司、城市与国家统计
- SQLite 本地数据存储
- JSON 备份导出与恢复导入（兼容网页版导出记录）
- 中文 / English 全局切换
- 关于页自动检查 GitHub 最新发布，发现新版本时提示，并提供项目源码入口
- 航空公司与航班号必填，可选通过 ADSBdb / FlightBoard 兼容路线源自动补全
- 可选连接自建 Cloudflare Worker + D1，支持本地覆盖云端与云端恢复到本地
- Android 返回逻辑与沉浸式深色界面

## 本地运行

```bash
flutter pub get
flutter test
flutter run
```

## 数据原则

- SQLite 是设备内唯一真实数据源。
- 地图、机场坐标和行政区数据均随安装包离线提供。
- 机场索引由 [OurAirports 公共机场数据](https://ourairports.com/data/) 生成，保留 IATA、ICAO、正式名、行政城市、机场类型、定期航班标记和别名；生成脚本为 `tool/generate_airport_index.py`。
- 索引保留上一个版本中已移除的 IATA 别名，避免历史记录因数据源更新而失去坐标。
- 1.1 的核心记录功能不要求账号、配对码或网络；更新检查仅在进入关于页或用户主动点击时联网。
- 未连接云端时完全离线可用；连接云端也不会改变 SQLite 本地数据源。

## 可选云端同步

云端同步使用你自己部署的 Cloudflare Worker + D1，飞行记录和旅行足迹由你的 Cloudflare 账号管理。

### 快速搭建

1. 准备 Cloudflare 账号，部署配套的 Worker + D1 模板。
2. 部署时设置 `BOOTSTRAP_SECRET`，建议用密码管理器生成不少于 32 个字符的随机字符串。
3. 部署完成后复制 Worker 地址，稍后填入 App。

### App 使用

1. 打开「我的 → 云端同步」，首次选择「新建云端」，输入 Worker 地址和初始化密钥。
2. App 创建资料库并显示一次恢复码，请立即离线保存。
3. 其他设备选择「恢复已有云端」，输入同一个 Worker 地址和恢复码即可配对。
4. 「本地覆盖云端」上传本机的飞行记录和旅行足迹；「云端恢复到本地」下载云端数据。
5. 当前为手动同步，使用前后按需操作；未配置云端时 App 仍可离线使用。

安全提示：初始化密钥、恢复码和设备令牌只应由自己保存，不要上传到公开仓库或放进截图。云端只保存飞行记录（含航迹点）和旅行足迹，统计数据会在设备本地重新计算。

## 致谢

本项目参考并使用了以下开源项目与公开数据：

- [Flutter](https://flutter.dev/)：应用开发框架。
- [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)：本地图片文字识别能力，遵循 Apache-2.0 许可。
- [ONNX Runtime](https://github.com/microsoft/onnxruntime)：本地模型推理，遵循 MIT 许可。
- [OpenCV](https://opencv.org/)：图像预处理，遵循 Apache-2.0 许可。
- [flag-icons](https://github.com/lipis/flag-icons)：国家和地区旗帜素材，遵循 MIT 许可；许可文本见 `assets/flags/FLAG-ICONS-LICENSE`。
- [Natural Earth](https://www.naturalearthdata.com/)：世界地图数据，公共领域。
- [OurAirports](https://ourairports.com/data/)：机场索引数据，公共领域。

产品交互与视觉方向参考过 Flighty 等飞行记录产品，仅作为设计参考，不包含其代码或素材。
