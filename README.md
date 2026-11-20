# 尤湖沿影视（Youhuyan Media）

跨平台影视应用项目，当前优先构建 Android 预览版。

## 当前阶段
- Flutter Android app foundation
- TVBox JSON configuration import (metadata only; no remote scripts or binaries are executed)
- GitHub Actions Android debug APK build
- No bundled media, streams, or third-party playback sources

## Build
GitHub Actions runs on pushes to main and can be triggered manually. The first build is a debug preview APK, not a production-signed release.

## Project principles
- Only use media sources and playlists that the user owns or is authorized to access.
- Treat imported configuration as untrusted data.
- Never execute remote spider scripts, JARs, or downloaded binaries.
- Respect third-party licenses and attribution requirements.

## Membership plan (planned; not implemented)
- Basic: free
- VIP: 6 months CNY 39.9; 12 months CNY 69.9
- Up to 3 devices per VIP account
- Initial redemption is administrator-issued codes; no automatic payment integration yet.

## License
Application-specific code in this repository will be licensed separately once third-party dependencies and any reused components have been reviewed. Do not assume the entire app inherits the license of a referenced project.
