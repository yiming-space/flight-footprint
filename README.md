# 航迹 · Flight Footprint

一个独立、离线、本地优先的 Flutter 飞行记录应用。1.0 先支持 Android，数据无需登录即可记录在设备内；云同步和版本检查都是可选的自建能力。

## 1.0 功能

- 飞行地图 / 旅行足迹离线切换
- 航班快速记录、年份筛选与长按删除
- 总里程、机场、机型、航司、城市与国家统计
- SQLite 本地数据存储
- JSON 备份导出与恢复导入（兼容网页版导出记录）
- 中文 / English 全局切换
- 关于页手动检查 GitHub 最新发布，并提供项目源码入口
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
- 1.0 的核心记录功能不要求账号、配对码或网络；更新检查仅在用户主动点击时联网。
- 未连接云端时完全离线可用；连接云端也不会改变 SQLite 本地数据源。

## 可选云端同步

项目内的 [`cloudflare-self-host`](../flight-footprint/cloudflare-self-host) 是配套 Worker + D1 模板。它不依赖 ChatGPT 登录，也不要求应用上架：用户可以部署自己的 Worker，在 App 的「我的 → 云端同步」中输入 Worker 地址与凭据。

1. 首次使用选择「新建云端」，填写 Worker 地址和部署时设置的 `BOOTSTRAP_SECRET`。
2. App 会创建资料库、配对当前设备，并显示一次恢复码；请离线保存恢复码。
3. 其他设备选择「恢复已有云端」，输入同一个 Worker 地址和恢复码即可配对。
4. 「本地覆盖云端」只上传本机的飞行记录和旅行足迹；「云端恢复到本地」会先完整校验云端快照，再替换本机这两类记录。两种操作都用 `revision` compare-and-swap 防止误覆盖。

设备令牌和恢复码使用 Android 安全存储，不提交到源码或备份截图。当前版本是手动同步；云端快照只保存飞行记录（含轨迹点）和旅行足迹，统计数据在设备本地重新计算。删除记录暂未使用墓碑标记，因此删除同步策略会在后续版本单独设计。航班资料补全是独立的可插拔、尽力而为数据源，不影响本地记录与云端同步；当前优先查询 ADSBdb，并兼容 FlightBoard 使用的 adsb.im / adsb.lol 路线接口。
