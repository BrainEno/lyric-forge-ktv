# 截图目录说明（G. 交付物状态）

**本目录及其子目录（overview/ pages/ interactions/ responsive/800x600 等）为空，这是有意为之的诚实状态。**

原因（完整取证见 `../reports/environment-diagnostic.md`）：

1. 沙箱出口防火墙仅放行 github.com / api.github.com / registry.npmjs.org / pypi.org 等少数主机；
2. Flutter SDK 官方下载源 `storage.googleapis.com` 在 TLS 握手阶段被切断（curl 取证：`SSL_ERROR_SYSCALL`）；
3. 即使从 GitHub 克隆 flutter/flutter，首次运行也必须从同一被断主机下载 Dart SDK（已通过 api.github.com 取回 `bin/internal/update_dart_sdk.sh` 第 133 行取证）；
4. `pub.dev` 被断 → 约 50 个 hosted 依赖无法 `pub get`；
5. 沙箱无 X server / 无浏览器 / apt 源亦不可达 → 无任何截图链路。

按任务书 §2.4 与 §12.1：未获得真实运行截图前，不得以代码模拟、静态渲染或图片生成代替。故本目录保持为空，审计报告的"截图"列一律标注"无（静态）"。

## 补救方案（供后续具备条件的环境执行）

在具备 Flutter 3.47.7（.fvmrc）与显示环境（如 Xvfb）的机器上：

```bash
flutter pub get
flutter run -d linux   # 或 windows/macos
# 按窗口矩阵 800×600 / 1280×800 / 1600×1000 / 1920×1080 调整窗口
# 覆盖页面：/ /library(×5 分区) /quick-play /now-playing /project/:id
#           /project/:id/lyrics /project/:id/player(+全屏KTV) /review /settings /import /media-sharing
```

命名规范：`<page>-<state>-<WxH>.png`，如 `dashboard-default-1280x800.png`。
