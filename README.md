# 尤湖沿影视｜独立 Flutter 工程

本分支 flutter-independent 专门推进独立 Flutter 客户端，不覆盖 main 分支现有的 Android 构建流程，也不修改 resource-hub 生产配置。

## 当前可验证里程碑

- Flutter 3.50.0 托管 CI：SDK/Android 环境检查、依赖解析、静态分析、单元测试和 Android Debug APK 构建。
- SQLite 多接口数据模型：多个 JSON 配置可同时保存；HTTPS URL 规范化和重复检测；唯一默认接口。
- 缓存安全：新 JSON 通过结构校验后才允许事务性替换缓存；校验失败只记录错误状态，保留上次成功 JSON 和成功时间。
- 离线数据：配置表保存最近一次成功 JSON；收藏和观看历史使用独立表，不依赖配置记录。
- 安全边界：仅把导入内容作为 JSON 数据保存，不执行 spider、脚本、JAR 或未知二进制插件。

## SQLite 平台选择

- Android、iOS/iPadOS、macOS：使用 sqflite 原生 SQLite。
- Windows（以及 CI/单元测试）：使用 sqflite_common_ffi。
- 数据库放在应用私有支持目录，不写入 resource-hub。

## 当前尚未完成

配置 repository 已建立，但尚未接入完整设置 UI；本地文件选择器、远程 HTTPS 下载器（含响应流大小限制/超时）、站点和直播列表、搜索、播放器、收藏/历史界面、会员服务端及管理员后台仍待开发。当前 CI 目标是 Android Debug 预览构建，不是签名发布包，也没有真机兼容性结论。

## 会员规则（已确认，尚未实现）

- 基础版永久免费，基础浏览、搜索、点播/直播、收藏和历史不锁入 VIP。
- VIP：半年 ¥39.9，一年 ¥69.9；每个账号最多 3 台设备。
- 首期由管理员生成兑换码；核销、套餐和设备权限必须以后端验证为准。
- 未接入真实支付前，不显示已支付状态或自动开通会员。

## 安全与版权

仅导入用户拥有或获授权的配置和内容。旧配置中的 spider、JAR、live.txt 或其他脚本字段只可作为不执行的数据保存；不下载或运行未知插件，不抓取或分发未经授权的影视资源。

## 本分支验证

推送 flutter-independent 分支会运行 .github/workflows/flutter-independent-ci.yml。成功后上传 14 天有效的 Android Debug APK 构建产物。Debug APK 不能当作正式签名发布包。
