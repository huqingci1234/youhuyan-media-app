# 尤湖沿影视｜独立 Flutter 工程

本分支 `flutter-independent` 专门推进独立 Flutter 客户端，不覆盖 `main` 分支现有的 Android 构建流程，也不修改 `resource-hub` 生产配置。

## 当前可验证里程碑

- Flutter 3.50.0 托管 CI：SDK/Android 环境检查、依赖解析、静态分析、单元测试和 Android Debug APK 构建。
- SQLite 多接口数据模型：多个 JSON 配置可同时保存；HTTPS URL 规范化和重复检测；唯一默认接口。
- 缓存安全：新 JSON 通过结构校验后才允许事务性替换缓存；校验失败只记录错误状态，保留上次成功 JSON 和成功时间。
- 离线数据：配置表保存最近一次成功 JSON；收藏和观看历史使用独立表，不依赖配置记录。
- 远程导入：仅允许 HTTPS，最多跟随 3 次 HTTPS 重定向；20 秒总超时；状态码检查；2 MiB 响应流限制；严格 UTF-8 与 JSON 结构验证。
- 本地导入：通过系统文件选择器导入 JSON，流式读取并执行同样的 2 MiB 限制及 JSON 校验。
- 设置界面：多接口列表、添加、重命名、删除、唯一默认切换、刷新、修改 URL 后重新下载验证，以及上次成功/错误状态。
- 资源目录 V1：从当前默认配置的离线 JSON 缓存读取站点和直播分组；支持按站点名称/标识、直播分组/频道名称本地搜索；远程 API 和播放列表地址仅作为数据保存，不执行远程脚本或自动下载。
- 安全边界：导入内容只作为 JSON 数据保存，不执行 spider、脚本、JAR 或未知二进制插件。

## SQLite 与文件选择器平台策略

- Android、iOS/iPadOS、macOS：使用 sqflite 原生 SQLite。
- Windows（以及 CI/单元测试）：使用 sqflite_common_ffi。
- 本地数据库放在应用私有支持目录。
- file_picker 文档列出 Android、iOS、macOS、Windows 文件选择支持；各目标仍须实际设备/桌面构建验证。

## 当前尚未完成

站点 API 对接、电影/剧集/综艺/动漫列表、详情与播放器、实际直播播放、播放进度恢复、收藏/历史界面、会员服务端和管理员后台仍待开发。Android TV 遥控器/文件选择、Windows/macOS/iOS 真机或桌面测试尚未完成。当前 CI 目标是 Android Debug 预览构建，不是签名发布包。鸿蒙手机仅单独评估 Flutter for OpenHarmony，不阻塞主线；Apple TV/tvOS 不开发。

## 会员规则（已确认，尚未实现）

- 基础版永久免费，基础浏览、搜索、点播/直播、收藏和历史不锁入 VIP。
- VIP：半年 ¥39.9，一年 ¥69.9；每个账号最多 3 台设备。
- 首期由管理员生成兑换码；核销、套餐和设备权限必须以后端验证为准。
- 未接入真实支付前，不显示已支付状态或自动开通会员。

## 安全与版权

仅导入用户拥有或获授权的配置和内容。旧配置中的 spider、JAR、live.txt 或其他脚本字段只可作为不执行的数据保存；不下载或运行未知插件，不抓取或分发未经授权的影视资源。

## 本分支验证

推送 `flutter-independent` 分支会运行 .github/workflows/flutter-independent-ci.yml。成功后上传 14 天有效的 Android Debug APK 构建产物。Debug APK 不能当作正式签名发布包。
