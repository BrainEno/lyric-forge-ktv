# 诊断、日志与实测数据

本文说明应用怎样记录日志、保存崩溃摘要、统计操作耗时，以及用户怎样导出诊断包；同时给出 KTV 延迟与长歌处理耗时的实测流程（#233、#226）。决策记录见 [D-016](decisions.md)。

## 组成

| 部分 | 位置 | 作用 |
| --- | --- | --- |
| `AppLogger` / `appLog` | `lib/core/diagnostics/app_logger.dart` | 分级（debug/info/warning/error）、带模块标签的日志入口。替代 `print`/`debugPrint`/`developer.log`。 |
| `LogRedactor` | `log_redactor.dart` | 唯一的脱敏点。所有记录在进入任何 sink 之前脱敏，诊断包生成时再脱敏一次。 |
| `MemoryLogSink` | `app_logger.dart` | 最近 500 条，文件不可写时作为诊断包的后备。 |
| `FileLogSink` | `file_log_sink.dart` | JSON Lines 写入 `app.log`，超过 512 KB 轮转为 `app.1.log`（最多约 1 MB）。批量写、串行化，磁盘错误不外抛。 |
| `CrashRecordStore` / `installCrashCapture` | `crash_capture.dart` | 接管 `FlutterError.onError` 与 `PlatformDispatcher.onError`，记录日志并保存最近 10 条崩溃摘要。 |
| `OperationTimings` | `operation_timings.dart` | 本次运行内每种操作最近 20 个样本：耗时、结果、媒体时长、实时倍率、少量结构化属性。 |
| `DiagnosticsReportBuilder` | `diagnostics_report.dart` | 汇总版本/平台、功能分区、耗时、崩溃、最近 400 条日志，输出文本 + JSON。 |
| `AppDiagnostics` | `app_diagnostics.dart` | 以上部分的门面：启动、偏好、摘要、导出、清除。 |
| 设置卡片「诊断与日志」 | `features/settings/presentation/widgets/diagnostics_settings_card.dart` | 导出诊断包、复制诊断信息、清除记录、详细日志开关、崩溃记录开关、耗时列表。 |

文件位于应用支持目录下的 `diagnostics/`（macOS：`~/Library/Application Support/<bundle>/diagnostics/`；Windows：`%APPDATA%\<company>\<app>\diagnostics\`）。「清除记录」只删除这个目录里的日志、崩溃记录和内存中的耗时，不碰歌词、音频和工程。

## 怎样写日志

```dart
import '../../../../core/diagnostics/app_logger.dart';

appLog.info('ktv', 'Recording started');
appLog.warning('transfer', 'Upload failed', error: error, stackTrace: stackTrace);
```

- 标签用小写模块名：`app`、`player`、`project`、`ktv`、`transcription`、`transfer`、`timing`、`crash`、`diagnostics`。
- 只记元数据：数量、时长、状态、失败种类。**不要记歌词文本、音频内容、工程名或歌名。** 脱敏器能抹掉密钥、邮箱和用户目录，但认不出歌词，结构上不写才是第一道防线。
- `debug` 级只在「详细日志」打开时保留；默认最低级别是 `info`。
- 错误对象记为 `类型: 消息`，超过 600 字符截断；栈最多保留 24 帧。

## 脱敏规则

| 内容 | 处理 |
| --- | --- |
| `token`、`access_token`、`password`、`api_key`、`secret`、`authorization`、`cookie`、`pairing_code`、`KTV-QUERY-TOKEN` 等键的值（URL 参数、请求头、`key=value`、JSON） | 保留键，值换成 `<redacted>` |
| `Bearer xxx` / `Basic xxx` | `Bearer <redacted>` |
| `scheme://user:pass@host` | `scheme://<redacted>@host` |
| 邮箱 | `<email>` |
| 当前用户的主目录（`HOME`/`USERPROFILE`），以及任意 `/Users/<名>`、`/home/<名>`、`C:\Users\<名>` | `~` |

脱敏是幂等的；以 `fingerprint=`、`tokenizer=` 这类词尾恰好是密钥名的键不会被误伤。结构化分区（字典）里键名本身是密钥名时，整个值被替换。

## 诊断包内容

导出的 `.txt` 前半是可读文本，后半是 `---- JSON ----` 之后的同内容 JSON（`schemaVersion: 1`）。复制到剪贴板时只包含文本部分。

- **应用与平台**：版本（`appVersion`，由测试保证与 `pubspec.yaml` 一致）、构建模式、操作系统与版本、Dart 版本、CPU 核数、区域设置。不含主机名、用户名或设备序列号。
- **本地识别运行环境**：是否已配置、模式、配置档、语言、引擎顺序、解码档、Qwen 设备与精度、各组件状态和说明、托管根目录（已脱敏）、硬件信息。
- **KTV 麦克风**：输入设备数量、所选设备名称、监听状态、权限、增益、附加监听延迟、引擎自报延迟、错误。
- **资料库规模**：工程数、资料库条目数、根目录数。只有数量。
- **操作耗时（本次运行）**：见下一节。
- **崩溃记录**：时间、来源（flutter/platform）、版本、错误、上下文、前 8 帧。
- **最近日志**：文件日志（包括之前几次运行）最近 400 条；文件不可读时用内存中的记录。

每个分区独立收集：某一分区出错或超时（识别环境 20 秒，其余 5 秒）只在该分区写「收集失败」，不影响整个诊断包。

## 崩溃记录

- `main()` 在 `AppServices.initialize()` 之后立即调用 `diagnostics.start()`，同步装好处理器，再在后台读取偏好。
- `FlutterError.onError`：记录后交还原处理器（没有时调用 `FlutterError.presentError`），调试模式的红屏与控制台输出照旧。
- `PlatformDispatcher.onError`：记录后若原来有处理器就交给它，否则返回 `true`（已处理）。这些错误原本只会被打印，发布版里未处理的错误还可能结束进程。
- 不使用 `runZonedGuarded`：Flutter 3.3 起推荐 `PlatformDispatcher.onError`，再套一层 zone 会让绑定初始化与 `runApp` 处于不同 zone。
- 设置里关闭「保存崩溃记录」后，错误仍写入日志，但不再保存摘要。崩溃记录从不上传。

## 操作耗时

| 操作 | 测的是什么 | 媒体时长 | 附加属性 |
| --- | --- | --- | --- |
| `transcription.transcribe` | 一次完整识别（含全部引擎与分片），在服务链最外层计时 | 规范化 WAV 的时长（只读文件头） | 模式、语言、解码档、检测语言、行数、主引擎、是否降级及原因、`rssMb`/`peakRssMb`；失败时为失败种类 |
| `ktv.startRecording` | 点击录音到录音开始（含伴奏启动等待） | — | 监听状态、`monitorDelayMs`、`engineLatencyMs` |
| `ktv.stopRecording` | 结束录音、写出音轨与清单 | 录音时长 | 对齐是否可靠、伴奏来源 |
| `ktv.exportMix` | FFmpeg 混音导出 | 录音时长 | 伴奏来源、`rssMb`/`peakRssMb` |

**实时倍率（RTF）= 处理耗时 ÷ 媒体时长**。低于 1 表示比实时快；5 分钟的歌 RTF 0.4 意味着约 2 分钟。设置卡片显示每种操作的次数、中位数、最长、最近一次、中位 RTF 和失败次数。

内存说明：`peakRssMb` 是本进程的峰值常驻内存，包括进程内的 Qwen 原生库和 SoLoud，**不包括** `whisper-cli`、FFmpeg 等子进程。测子进程内存见下文。

## 实测流程（#226）

代码不会自己声称性能或延迟数值。下面的流程产生可以写进文档的数据。每次记录都要写明设备、系统版本、输出设备（有线/USB/蓝牙）、应用版本（诊断包第一节）。

### KTV 端到端延迟（回环法）

目标：测「对着麦克风发声 → 从耳机/扬声器听到」的总延迟，而不是引擎自报值。

1. 准备：一条从耳机输出接回麦克风输入的回环线（或把耳机贴近麦克风、在安静房间里用扬声器），另一台设备或同一台设备上的录音软件（Audacity 等）做双通道录音。
2. 录音软件的左声道接参考信号（直接拾取发声，例如一个靠近声源的第二支麦克风或分线器的一路），右声道接本应用的监听输出。
3. 在应用中打开 KTV 监听，增益与附加延迟设为 0，记下界面显示的「音频引擎约 X ms」。
4. 发出短促脉冲（拍手、敲击，或播放 1 kHz 10 ms 的咔嗒声），重复 10 次以上。
5. 在波形上测量左右声道对应脉冲的起点差，取中位数，即端到端延迟。
6. 依次把附加延迟设为 50、100 ms 重复，确认测量值随设置线性增加（验证测量链路）。
7. 记录：中位数、最小值、最大值、引擎自报值、二者差值。差值就是引擎看不到的部分（转换器、输出设备、蓝牙）。

期望至少覆盖 Windows、macOS、Android 各一台设备；蓝牙耳机单独记一行，通常比有线高 100 ms 以上。

### 录音对齐

1. 选一首有清晰鼓点的伴奏，录一段跟拍敲击的人声。
2. 导出混音后，在 Audacity 中对比伴奏与人声音轨的拍点偏移。
3. 同时记录诊断包里 `ktv.stopRecording` 的「对齐是否可靠」。

### 长歌处理耗时与内存

1. 准备至少三首 ≥ 5 分钟的歌（建议 5、8、12 分钟各一首），记下时长。
2. 每台测试机启动应用后先打开「设置 → 诊断与日志 → 清除记录」，保证样本只来自本轮。
3. 依次识别每首歌（同一模式、同一语言），再各录一段 KTV 并导出混音。
4. 导出诊断包。`transcription.transcribe` 与 `ktv.exportMix` 的样本里有耗时、媒体时长、RTF、`peakRssMb`。
5. Whisper 路径的内存需要单独看子进程：macOS 用 `/usr/bin/time -l` 运行同样参数的 `whisper-cli`，Windows 用任务管理器「详细信息」的峰值工作集或 `Get-Process whisper-cli | Select PeakWorkingSet64`。
6. 冷启动（首次加载模型）与热启动分开记录：第一首歌的耗时包含模型加载。

### 结果写在哪里

把每次测量整理为 `docs/benchmarks/YYYY-MM-DD-<设备>-ktv-latency.md` 或 `...-long-song.md`，附上诊断包里对应的 JSON 片段（已脱敏，可直接提交）。在得到数据之前，文档和界面都只描述测量方法和数据来源，不写推测值。KTV 麦克风面板在延迟数值下方说明它来自音频引擎自报、不含输出设备与蓝牙延迟。

## 隐私

- 日志、崩溃记录与耗时只保存在本机，应用不会上传。
- 诊断包由用户主动导出或复制，内容在导出前可读。
- 诊断包不含歌词、音频或工程内容；密钥、令牌、邮箱和路径中的用户名已替换。
- 用户随时可以清除全部诊断记录。
