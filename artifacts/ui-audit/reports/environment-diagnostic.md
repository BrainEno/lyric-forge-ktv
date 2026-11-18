# 环境诊断报告（强制前置条件，任务书 §2）

审计日期：2026-11-18 · 执行环境：Arena Sandbox · 分支：`arena/f1dee18e-lyric-forge-ktv`（基线 `80b04a3`）

> **结论：本沙箱不具备获得可用 Flutter SDK 的条件，任务书 §2.4 强制停止条件对“运行期审计”触发。**
> 依据任务书 §10 约束 9（"不要因为无法截图就放弃静态代码审计，但必须明确区分两类证据"），
> 本次审计的**静态代码审查部分继续执行并单独标注证据类型**；运行、截图、多尺寸实测、Google Drive 截图归档标记为**未完成**并说明具体失败环节。

## 2.1 执行环境实测

| 项目 | 实测值 |
|---|---|
| 操作系统 | Debian GNU/Linux 12 (bookworm)，内核 6.1.158+ |
| CPU 架构 | x86_64（Intel Xeon @ 2.60GHz，2 核） |
| 当前用户 | `user` (uid=1001)，在 sudo 组 |
| 磁盘空间 | 21G 总量，**20G 可用**（充足） |
| 内存 | **3.8Gi 总计 / 3.6Gi 可用**，无 Swap |
| 图形界面 | **无**。`DISPLAY`/`WAYLAND_DISPLAY` 均为空；`/tmp/.X11-unix/` 为空目录 |
| 虚拟显示服务 | **未安装**：无 Xvfb、xvfb-run、weston、sway、x11vnc |
| 浏览器 | **未安装**：无 chromium / chrome / firefox |
| 截图工具 | ImageMagick `import`/`convert` 存在，但无 X server 可供截屏 |
| Flutter / Dart | **均未安装**（PATH、`/opt`、`/usr/local`、`$HOME`、全盘 6 层 find、dpkg、snap 均无结果） |

## 2.2 网络连接实测（2026-11-18 12:21 UTC）

沙箱出口防火墙采用 SNI 白名单。DNS 全部解析正常（8.8.8.8），但被禁主机在 **TLS 握手阶段**被切断：

| URL | DNS | TCP/TLS | 结果 |
|---|---|---|---|
| `https://docs.flutter.dev` | ✅ 正常 | ❌ `SSL_ERROR_SYSCALL`（TLS 握手被切断） | **失败：TLS 阶段** |
| `https://storage.googleapis.com` | ✅ 正常 | ❌ `SSL_ERROR_SYSCALL` | **失败：TLS 阶段** |
| `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` | ✅ 正常 | ❌ 同上，无响应体 | **失败：TLS 阶段（官方 Release Metadata 不可达）** |
| `https://pub.dev` | ✅ 正常 | ❌ `SSL_ERROR_SYSCALL` | **失败：TLS 阶段** |
| `https://github.com` | ✅ 正常 | ✅ HTTP/2 200 | 可用 |
| `https://api.github.com` | ✅ 正常 | ✅ 可用（已用它取回 Flutter 源码取证） | 可用 |
| `http://deb.debian.org`（apt 源） | — | ❌ 无响应 | 失败（无法安装 Xvfb 等 GUI 依赖） |

失败类型判定：**不是 DNS 失败、不是 403/451、不是超时**，而是出口防火墙对非白名单主机的 TLS 阻断。

## 2.3 Flutter SDK 获取能力判定（含取证）

1. **官方 SDK 下载源不可达**：Flutter SDK 归档与 Release Metadata 均托管于 `storage.googleapis.com`（见上表，TLS 阻断）。
2. **GitHub 克隆路径亦不可行（已取证，非推测）**：通过 `api.github.com` 取回 Flutter 官方仓库 `bin/internal/update_dart_sdk.sh`，第 133 行实证：
   ```sh
   DART_SDK_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}${ENGINE_REALM:+/$ENGINE_REALM}"
   ```
   即：即使从 GitHub 克隆 flutter/flutter，首次运行任何 `flutter` 命令都必须从 `storage.googleapis.com` 下载 Dart SDK 与引擎产物 → 同样被阻断。
3. **镜像方案被任务书禁止**：`FLUTTER_STORAGE_BASE_URL` 镜像（如 storage.flutter-io.cn）属于任务书 §2.4 禁止的"未经授权的代理/不明下载镜像"，且镜像域名同样不在沙箱白名单内。
4. **依赖不可获取**：`pubspec.lock` 证实本项目约 50 个依赖为 `source: hosted`（pub.dev），`pub.dev` 被阻断 → `flutter pub get` 必然失败。
5. **GUI 依赖不可安装**：无 X server/浏览器，且 `deb.debian.org` 不可达，无法安装 Xvfb → 即使 SDK 存在也无法截图（任务书 §2.4 要求必须明确报告此限制，不得伪装成完整审计环境）。

**最终判定：无法构建、无法运行、无法截图。三项能力缺失链路完整取证如上。**

## 2.4 对审计范围的影响（诚实声明）

| 审计活动 | 状态 | 证据类型 |
|---|---|---|
| 技术栈 / 页面路由 / 组件 / 主题样式盘点（§3） | ✅ 可完成 | **静态代码证据**（文件+行号） |
| 逐页面运行与截图（§4） | ❌ 不可完成 | 无 Flutter SDK、无 GUI |
| 多窗口尺寸实测（§4.2） | ❌ 不可完成 | 同上；以 `lib/core/layout/app_responsive.dart` 与布局代码静态推断代替，**明确标注为静态推断** |
| 逐页面审查（§5） | ⚠️ 部分完成 | 静态代码审查；视觉实测项标注"未能运行验证" |
| Google Drive 截图归档（§12） | ❌ 前置条件不满足（§12.1 第 1–5 条全部不成立） | 不上传任何非真实截图，详见 `09-google-drive-status.md` |

本报告满足任务书 §2.4"输出环境诊断报告，列明失败的 URL、具体错误、失败阶段和当前限制"的要求。
