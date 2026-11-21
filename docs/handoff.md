# Handoff

## 目标

审计路线的第二十九轮（第二十八轮 PR #500 已合并为 `915fa83`），用户三个请求合在一个 PR：

1. 左侧导航文字显示有问题：“音乐库”的“音”粗黑而“乐库”细灰。原因是应用没有指定字体，每个汉字单独走系统回退。修复（D-050）：`AppTypography` 在系统回退之前先列简体中文界面字体（Windows 首选 Microsoft YaHei UI），主题和组件样式都使用它。
2. 准备“最高质量双引擎”时报“识别引擎安装包缺少运行时清单”。Windows 探针确认发布包完整，问题在用户机器上的单次 `Expand-Archive`。修复（D-051）：`ZipBundleExtractor` 按安装包中央目录逐项核对解压结果，依次尝试 `tar.exe`、.NET `ZipFile`、`Expand-Archive`，先查磁盘空间，失败时写明每次尝试；已校验的安装包重试时直接复用。
3. 下载中途失败要从断点续传（D-051）：`ResumableFileDownload` 就地 `Range` 重试；HF→ModelScope 切换时把断点移过去；下一次从断点更长的镜像继续；已校验的识别引擎 / FFmpeg 安装包不再重复下载。

## Git 现场

- 分支：`arena/05e56260-lyric-forge-ktv`，基于 main `915fa83`，PR #501。
- PR 合并方式：squash，标题 `Draw each Chinese label in one typeface; resume downloads and recover the runtime install`。临时探针 `probe.yml`、`probe-win.yml` 合并前删除。

## 已改文件

见工作日志 `2026-12-16-0930`（字体）、`2026-12-16-1030`（下载与安装），决定 D-050、D-051。

## 检查结果

- Windows 探针（windows-latest）：`asr-runtime-v3` Windows 包 1223455711 字节，SHA-256 与发布信息一致；14 个条目，`runtime-manifest.json` 在最后；PowerShell 5.1 `Expand-Archive` 与 `tar.exe` 都完整解出。
- 沙箱里没有 Dart/Flutter，格式、analyze 和测试都靠 PR 的 Flutter Quality Gate 和临时探针。
- 新增测试：中央目录解析（含 ZIP64、反斜杠、越界路径）、解压回退与诊断、磁盘空间不足、真实 `unzip` 解压；下载就地续传、无进展失败上限、取消、HTTP 错误不重试；模型下载就地续传、HF→ModelScope 断点转移、从更长的镜像断点开始；安装器接线的源码约束。

## 下一步

- 在用户的 Windows 机器上重试“最高质量双引擎”：应提示复用已校验的安装包（不再下载 1.2 GB）；若仍失败，把错误详情（每种解压方式的退出码、stderr、缺失文件）发回来。
- 在机器上确认左侧导航等处汉字粗细一致；验证 D-049 的识别进度卡与 `VocalSeparator` 迁移。
- 在 RTX 5080 上实际跑几首歌，检验 D-044–D-047 的人声检查与自动补句（行召回 ≥ 0.95、CER ≤ 0.10）。

## 已知风险

- 用户机器上 `Expand-Archive` 丢最后一个条目的确切原因未确认（推测是磁盘空间或杀毒软件）；新诊断会指出来。
- HF 与 ModelScope 断点只在双方公布相同 SHA-256 时互通；上游文件在两次尝试之间更新时，最终校验会删除断点并重新下载该文件。
- 安装成功后 `downloads/asr-runtime.zip`（1.2 GB）仍保留，与之前相同。
- 极少数没有微软雅黑的 Windows 仍会退回系统字体选择。

最后更新：2026-12-16 10:30（Asia/Taipei）
