# AVBox 双端迁移实施计划

## 目标

在保留现有 `main`、历史 Release 和旧构建产物的前提下，在 `avbox-final` 上形成两个可独立安装和升级的 Android 应用：

- 手机端：`com.youhuyan.media`
- TV 端：`com.youhuyan.media.tv`

两个应用使用同一套长期固定的发布证书，但使用独立 applicationId。私钥只允许通过 GitHub Actions Secrets 注入，不得写入源码、Gradle 属性文件、构建日志或 APK 资源。

## 已核实的上游事实

- 上游：`XiaochangXu/AVBox`，分支 `main`。
- Android 工程包含 `:app`、`:quickjs`、`:pyramid`、`:libs:backdrop`。
- 当前只有一个 Android application 模块；默认 namespace 和 applicationId 为 `com.github.avbox.osc`。
- 当前主启动 Activity 是 `.ui.MainActivity`，Manifest 使用普通 `LAUNCHER`，没有独立 Leanback launcher 入口。
- 上游手机 UI 规范明确声明项目只面向手机，并说明 TV/遥控器适配代码已删除。因此不能把上游当前 APK 简单换包名后称为 TV 版。
- 上游 Gradle signing 配置读取 `RELEASE_*` 项目属性；CI 必须通过 Secrets 覆盖，不得信任上游仓库中的本地签名属性。

## 实施阶段

### 阶段 A：双端构建骨架

1. 建立明确的 mobile / tv 构建变体或独立 application module。
2. 固定两个 applicationId 和各自的 launcher manifest。
3. 统一版本号来源与 APK 文件命名。
4. Debug 构建先验证依赖、Manifest 合并、资源和包名；不擅自运行 Release 构建。

验收：Actions 能分别生成两个 Debug APK，安装包 applicationId 与目标一致。

### 阶段 B：手机端品牌与回归

1. 保留 AVBox 手机 Compose UI 与播放/数据内核。
2. 替换应用名称、启动图标和对外品牌标识为尤湖沿影视。
3. 检查权限、网络安全配置、文件 Provider authority、深链和升级包名。
4. 运行上游要求的 Debug 编译与单元测试。

验收：手机端能安装、启动、配置资源并完成点播/直播基本流程。

### 阶段 C：TV 独立适配

1. 增加 TV 专用入口与 Leanback launcher 声明。
2. 提供适合 16:9 大屏的首页、分类、详情和播放控制布局。
3. 为所有可交互控件实现清晰的 DPAD 焦点顺序、焦点态和返回行为。
4. 验证遥控器方向键、确认、返回、菜单键；不依赖触摸操作。
5. 处理电视设备能力、无触屏声明、横屏与安全区域。

验收：在 Android TV / Google TV 设备或模拟器上，仅用遥控器完成启动、浏览、搜索、播放、暂停、选集和退出。

### 阶段 D：正式签名与发布

1. 使用新生成且由项目长期保管的发布密钥；手机与 TV 两包使用同一证书。
2. 通过 GitHub Actions Secrets 注入 keystore 与密码；不在仓库提交密钥。
3. 先完成 Debug 验收，再在明确授权后运行 Release 构建。
4. 校验 APK 签名证书指纹、包名、版本号与文件完整性。
5. 上传独立 GitHub Release 资产，并更新下载页面的两个下载入口。

验收：两个 APK 都可下载、安装；相同应用后续更新签名一致；旧版 Release 与源码分支保持不变。

## 当前阻塞项

- GitHub Actions Secrets 写入能力不可用，正式签名密钥尚未安全配置。
- 当前 workflow 仍是初步构建框架，尚未证明上游工程在 CI 中可成功构建。
- TV 专用 UI 与遥控器交互尚未实现。
- 尚无新版 APK、正式 Release 或下载页更新。

## 不可违反的约束

- 不覆盖 `main`、旧 Release 或历史源码分支。
- 不把密钥、密码或 Base64 keystore 放入 Git。
- 不以手机版 APK 改名冒充 TV 版。
- 不在未经明确授权时执行 Release 构建。
- AVBox 为 AGPL-3.0 项目；衍生版本发布时保留许可证与版权声明，并按许可证要求提供对应源码。
