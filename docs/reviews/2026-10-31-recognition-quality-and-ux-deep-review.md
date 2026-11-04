# 歌词识别质量与整体架构深度审查

- 日期：2026-10-31
- 审查基线：`main@36104d3`（Merge PR #271，全仓 644 个提交、完整历史已拉取）
- 审查范围：`lib/` 全部 240 个文件 / 70,344 行；`test/` 150 个文件 / 29,501 行 / 855 个用例；25 个 workflow；`docs/` 全部设计文档；并对照上游 ASR runtime（`lumosimmo/qwen3-asr-rs`）的真实 HTTP 契约
- 触发问题：「这一版歌词识别反而不如最初版本」，以及界面过复杂

> **审查限制（必须声明）**：本沙箱没有 Flutter/Dart SDK，**未能运行 `flutter analyze` / `flutter test` / 真机识别**。以下结论全部来自：源码逐行阅读、Git 全历史比对、对上游 runtime 源码的契约核对，以及对融合算法的高保真复刻模拟。凡属推断的地方均标注「推断」。没有任何一条结论依赖「模型跑出来感觉不好」。

---

## 0. 结论先行

### 0.1 三句话

1. **识别质量下降不是玄学，是一条可以逐行读出来的因果链**：全局 3 分钟分片 → 每片跑双引擎 → 融合阶段把另一引擎「没匹配上」的行整行插入 → 分片合并再抹掉全部复核证据 → 编辑器把所有行标成「低置信度」。用户看到的就是「行更多、重复更多、断句更怪、而且重新识别还是老结果」。
2. **真正决定识别精度的两个开关（Whisper 解码参数、人声分离）从头到尾没动过**：Whisper 的调用参数自 2026-10-02 第一版起一字未改（默认贪心解码、无提示词、无 VAD、无分段上限、每片自动识别语言）；PRD 里列为「桌面端必须有」的人声/伴奏分离至今没有实现。30 天里 589 个提交，触及 `whisper_cpp_transcription_service.dart` 的只有 5 次，且全部是进程治理/重构，**没有一次是识别质量**。
3. **「一键准备识别环境」只支持两类电脑**：RTX 5080 与 Intel Mac。其余机器（4060/4070/4090、AMD、Apple Silicon、纯 CPU）在「自动」档位都会落到 `custom`，而 `custom` 被自动安装硬性拒绝——连「Whisper 单模型」也装不了。这是最容易被用户感知为「越做越差」的产品级缺陷。

### 0.2 严重度总表

| 级别 | 编号 | 问题 | 用户可感知后果 |
|---|---|---|---|
| **P0** | R1 | 所有识别都被 3 分钟分片包住（`service_locator.dart:271`），与文档「整首一次送入」直接矛盾 | 接缝处半句/重复；耗时 2–3 倍；复核证据被逐片重置。**已修复**（阈值 20 分钟，歌曲整首一次） |
| **P0** | R2 | 次引擎碎片因「字符比例时间估计」被误判为不匹配而插入（`high_quality_transcription_service.dart:879`） | 实测粒度差 4 倍时 **12 行 → 27 行**（插入 15 行，精确率 44%）；**已修复** |
| **P0** | R3 | 分片合并只保留 `mergeStrategy` 一个 metadata（`resumable_chunked_transcription_service.dart:483`） | 双引擎候选、模型身份、可疑行索引全部丢失；≥3 分钟的歌等于没有双引擎复核。**已修复** |
| **P0** | R4 | 分片检查点指纹不含 ASR 配置（同文件 `:83` / `:495`） | 换模型/换引擎顺序后「重新识别」静默返回旧结果。**已修复** |
| **P0** | R5 | 自动安装只认 RTX 5080 / Intel Mac（`managed_asr_runtime_manager.dart:1314`） | 绝大多数机器「一键准备」直接报错，连 Whisper 单模型也装不了 |
| **P0** | R6 | 最高质量模式在 Qwen 不可用时整体失败，不做降级（`high_quality_transcription_service.dart:64`） | 驱动更新/显存不足 = 一首歌都识别不出来，而 Whisper 本来能跑。**已修复** |
| **P1** | R7 | Whisper 参数从未优化：贪心解码、无 `--prompt`、无 VAD、`-l auto` | 精度上限被锁死；乐器段幻觉；专有名词全错 |
| **P1** | R8 | Qwen 无置信度时统一记 50（`qwen3_...:941`），而阈值是 70 | 每一行都显示「低置信度」，复核队列 = 全部歌词。**已修复** |
| **P1** | R9 | `max_new_tokens: 1024` 固定值（`qwen3_...:593`） | 长歌尾部可能被静默截断。**已修复** |
| **P1** | R10 | 没有质量语料与回归门禁 | 任何「改进」都无法证明有效，也无法证明没有退化 |
| **P1** | R11 | 三套语义重叠的校对入口 + 25 个控件的工具栏 | 用户不知道点哪个；学不会 |
| **P2** | A1 | 上帝屏（编辑器 4,851 行 / 49 import）、无状态管理 | 改动风险高、回归多 |
| **P2** | A2 | `ServiceLocator` 全局单例被 widget 直接调用 | 无法单测、隐式依赖 |
| **P2** | A3 | 播放屏自己 `new AudioPlayer()`，绕过播放抽象 | 双引擎争抢、状态不一致 |
| **P2** | A4 | 25 个 workflow、150 条工作日志 | 维护成本 > 功能产出 |
| **P2** | A5 | PRD 的「人声/伴奏分离」完全未实现 | 混音直接送 ASR，是精度的天花板 |

### 0.3 「为什么不如最初版本」的因果链

```
用户导入一首歌（≥3 分钟，几乎全部）
  │
  ├─[R1] 被 ResumableChunkedTranscriptionService 切成 3 分钟 + 8 秒重叠
  │        └─ 每一片都重新启动完整双引擎（Whisper 上下文重置 / Qwen 内部再切 1200s）
  │
  ├─[R2] 每片做融合：被比例时间估计误判的碎片 → 整行插入（已修）
  │        └─ 片段 vs 整行的 Levenshtein 相似度天然 ≤0.5，永远匹配不上
  │        └─ 只要两个引擎断句粒度不同 + 文本差一个字 → 逐行重复
  │
  ├─[R3] 分片合并：metadata 只剩 {'mergeStrategy': ...}
  │        └─ 双引擎候选、模型身份、可疑行全部消失
  │
  ├─[R4] 用户改配置再点「重新识别」
  │        └─ 指纹不包含配置 → 复用旧分片 JSON → 结果一模一样
  │
  ├─[R8] 编辑器：Qwen 行置信度中性 50 < 阈值 70
  │        └─ 「低置信度 N」= N = 全部行；智能复核 = 全部行
  │
  └─[R5/R6] 换台机器 / Qwen 出问题 → 连一首歌都跑不完
```

一句话：**最初的版本是「一整首歌 → Whisper → 一份干净的草稿」；现在是「切片 → 双引擎 → 并集 → 丢证据 → 全行告警」。**

---

## 1. 审查方法与可复现证据

| 手段 | 说明 |
|---|---|
| 全历史比对 | `git fetch --unshallow` 后按文件追踪（`git log --follow` / `git log -S`），确认「第一版」与「现在」的具体差异 |
| 逐行阅读 | 识别管线（transcription/data）、融合算法、分片合并、编辑器状态、装配层 |
| 上游契约核对 | 通过 GitHub API 拉取 `lumosimmo/qwen3-asr-rs` 的 `qwen3_asr_cli/src/cmd_serve.rs`（3,763 行），核对 `/v1/transcribe` 请求字段与返回结构 |
| 算法复刻 | 把 `_isLikelySameLyricLine` + `_mergeUnmatchedSecondaryLines` 逐分支移植到 Python，用合成语料量化重复行比例（结果见 R2） |
| 文档/代码一致性 | 交叉核对 `docs/high_quality_asr.md`、`docs/local_transcription.md`、`docs/prd.md` 与实现 |

**没有做的事**：没有运行分析和测试（无 SDK）；没有真实音频与人工校对歌词（这恰好是本项目最缺的东西，见 R10）。

---

## 2. 识别质量：根因分析

### R1【P0】全局分片把「整首一次识别」变成了「3 分钟切片」

**证据**

```dart
// lib/core/services/service_locator.dart:271
transcriptionService = ResumableChunkedTranscriptionService(
  delegate: HighQualityTranscriptionService(
    primary: qwenNativeTranscriptionService,
    fallback: WhisperCppTranscriptionService(),
  ),
);

// lib/features/transcription/data/services/resumable_chunked_transcription_service.dart:30
this.chunkDuration = const Duration(minutes: 3),
this.overlap = const Duration(seconds: 8),
```

**它包住了所有模式**：`whisperOnly` 也走同一条路；只要时长 > 3 分钟就切片。流行歌曲 3.5–5 分钟 ⇒ 几乎所有歌都被切成 2 片；带前奏/间奏的长歌可能 3–4 片。

**后果**

1. **接缝半句**：一行歌词跨越 3:00 时，会被两片各识别一半。合并逻辑（同文件 `:458`）只在「文本完全相等且开始时间差 ≤ 8 秒」时去重，半句永远去不掉。
2. **上下文重置**：Whisper 每片从零开始（无初始提示，见 R7），片头常出现「幻听」；Qwen runtime 自身还会在 1200 秒处再切一次，等于两层分片叠加。
3. **耗时翻倍**：每片都跑一遍双引擎，还要额外做 FFmpeg 切片与两次模型预热。
4. **磁盘增长**：每片的 `<id>_work/` 目录（含 `high_quality_shared_input.wav`）从不清理（同文件 `:158` 只删除 `*.wav`）。

**文档自相矛盾**

- `docs/high_quality_asr.md`（原文照抄）：「长音频由 runtime 内部切成 ≤180 秒……**LyricForge 因此整首发送一次，不再叠加第二层分片**。」—— 2026-11-01 核对上游源码后，180 秒这个数字不成立，实际是 `MAX_ASR_INPUT_SECONDS = 1200.0`；该文档已更正。
- `docs/local_transcription.md:158`：「Long audio is processed as 3-minute chunks with an 8-second overlap.」

两句话不可能同时为真。代码实现的是后者，却用在了一个「最高质量」被定义为「整首双引擎对比」的流程上。

**建议**：取消歌曲流程的全局分片（或把阈值提高到 15–20 分钟并显式提示）。断点续跑应该做在**引擎内部**，而不是包在「双引擎 + 融合」外面。

**处理（2026-11-01）**

采用「提高阈值」而不是「彻底删除包装」：`chunkDuration` 默认 3 分钟 → **20 分钟**，`defaultChunkDuration` 成为具名常量。包装器保留的唯一理由是让超长音频（演唱会、有声书）能断点续跑；对任何正常长度的歌，它现在只做一次时长探测就原样转交，**不再创建 `chunk_session` 目录**。

为什么不删：删掉包装器会同时删掉断点续跑，而 R1 的问题不是「有包装器」，是「包装器的阈值低于歌曲长度」。20 分钟对一首歌来说等于「永不触发」，对 40 分钟的现场录音仍然有用。

顺带修掉本节列出的第 4 条后果：每片的 `<id>_work/` 目录（含整片归一化 WAV）在检查点写好之后会被删除，不再无限增长。

**未处理**：`whisperOnly` 与最高质量模式仍然共用同一条包装路径 —— 现在共用的是「整首一次送入」，这是正确行为，无需拆分。

---

### R2【P0】融合阶段的行数膨胀（已实测，结论已按实测更正）

**位置**：`lib/features/transcription/data/services/high_quality_transcription_service.dart:879`（匹配）与 `:1004`（插入）

> **更正说明（2026-11-01）**：本节原稿基于对匹配算法的**手写复刻**，得出「48/48、72/72 全部被插入」以及「重复行率 >30%」。用真实服务跑完 6 组粒度组合后，这两个数字**不成立**，原判断过于悲观。下面是实测结果。原稿的错误在于：漏读了 `_containedFragmentMatchesTimeline` 的比例容差路径，它确实挡住了大部分碎片。

**实测方法**：构造 12 句歌词，主引擎整行 12 秒、次引擎切成 3 秒碎片，直接调用生产服务 `HighQualityTranscriptionService`（不是复刻），再用 Phase 0 工具的指标函数打分。

**实测结果（Whisper 为权威引擎，即 RTX 5080 推荐档位）**

| 主行时长 / 次引擎碎片 | 修复前 | 修复后 |
|---|---|---|
| 12 秒 / 3 秒 | **27 行**（12 主 + **插入 15**），行数比 **2.25**，精确率 **44.4%** | **12 行**，行数比 **1.00**，精确率 **100%** |
| 10 秒 / 3 秒 | 16 行（插入 4），行数比 1.33 | 12 行，1.00 |
| 8 秒 / 4 秒 | 12 行（插入 0） | 12 行 |
| 6 秒 / 6 秒、8 秒 / 8 秒 | 12 行（插入 0） | 12 行 |

也就是说：**缺陷真实存在，但只在两引擎粒度差 ≥3 倍时才显形**；粒度接近时匹配是好的。

**根因（与直觉不同）**

不是「不匹配就插入」这么粗糙。真正的漏点是 `_containedFragmentMatchesTimeline`：

```dart
final expectedStartMs = (fullDuration * fragmentStart / fullText.length).round();
final expectedEndMs   = (fullDuration * fragmentEnd   / fullText.length).round();
final toleranceMs = (fullDuration * 0.18) > 350 ? ... : 350;
```

它把「碎片在整行中的**字符位置比例**」当成期望时间。但真人唱歌不是匀速念字——拖长音、换气、间奏都会让时间与字符数脱钩；两套 ASR 的时间戳本身还有 ±0.5 秒抖动。于是**真实碎片被比例估计判为「时间对不上」**，走了插入分支。

实测在 12 秒 / 3 秒的组合里，正是第 2、3 个碎片（`dancing through`、`the night`）因 `endDelta` 超出 2.16 秒容差而被插入。

**修复**

新增一条优先判定：**碎片文本已被主行包含，且碎片时间区间落在主行区间内（±400 ms）⇒ 判定为同一句，不插入**。

```dart
if (_spanContains(fullLine, fragmentLine)) return true;
```

文字已经在屏幕上，再插一行只可能是重复；是否精确对齐到「第几个字在第几秒」对用户没有价值。比例容差仍保留，用于处理**时间上突出主行边界**的碎片（那属于真正的边界分歧，保留为待复核行是合理的）。

代价：若某句和声确实在被主行整段覆盖的时间窗内重复了同一批词，这一行会并入主行、失去独立时间戳。这是有意的取舍——**宁可少一行重复，也不要多一行垃圾**；且合并不丢词。

**仍然存在的问题（本 PR 未修，属 R1）**

无论修不修这一处，**权威引擎决定全局断句**：次引擎更细时，若主引擎是 Qwen（`qwenPrimary`），输出就是 Qwen 的 40 行碎片。这不是融合的错，是「谁做主语」的问题 —— 与 R1（全局分片）和 R7（Whisper 参数）一起处理。

**回归防护**

- `test/high_quality_transcription_service_test.dart`：新增两组表驱动测试（4 句 × 12 秒 / 3 秒碎片，两种引擎顺序），断言输出行数等于权威引擎行数、`secondaryOnlyLineCount == 0`；另一组断言**真正的 ad-lib 仍会保留**（防止「一刀切删掉所有次引擎行」这种作弊式修复）。
- 原先断言缺陷行为的测试（`:453`）已改为只保留 `sing a little song` 一行。

### R3【P0】分片合并抹掉全部复核证据

```dart
// resumable_chunked_transcription_service.dart:458
LyricDocument _mergeDocuments(List<LyricDocument> documents) {
  ...
  return LyricDocument(
    language: documents.first.language,
    lines: lines,
    metadata: {'mergeStrategy': 'overlapTextAndTimeDedup'},   // ← 只有这一个键
  );
}
```

`HighQualityTranscriptionService` 辛苦产出的 `fallbackCandidates`、`secondaryOnlyLineIndices`、`qualityMode`、`primaryEngine`、`alignmentEngine`、`suspiciousLineIndexes`，在合并这一步**全部丢弃**（`LyricDocument.copyWith` 的 metadata 是整体替换，不是合并，见 `lib/features/project/domain/models/lyric_document.dart:75`）。

连锁后果：

- `local_project_transcription_workflow.dart:159` 用 `metadata['primaryEngine'] ?? 'generatedBy' ?? 'local-asr'` 记录 `backend` ⇒ ≥3 分钟的歌永远记为 `local-asr`，模型溯源失效（而溯源是 `docs/work_log_index.md` 里反复强调的验收项）。
- 编辑器的「使用另一引擎候选」按钮（`_fallbackCandidateFor`）永远拿不到数据 ⇒ 花了几千行建的 per-line 复核功能，对正常长度的歌**完全无效**。
- `suspiciousLineIndexes` 写入后**全仓无人读取**（`grep` 确认），本身已是死数据。

**建议**：合并时按「文档级 metadata 取首片 + 汇总各类计数/索引」的方式显式重建；`fallbackCandidates` 需要按分片索引偏移重映射（代码里已有类似的 `_remapCandidateIndices`，可直接复用）。

**处理（2026-11-01）**

`_mergeDocuments` 现在同时产出「每个分片的行索引 → 合并后行索引」映射（去重与排序都要穿过），`_mergeMetadata` 据此重建：

- `fallbackCandidates`：逐片拼接，`lineIndex` 按映射重写；同一行只保留一条（编辑器按行查找）。
- `secondaryOnlyLineIndices` / `suspiciousLineIndexes`：重映射后去重排序。
- `fallbackCandidateCount` / `secondaryOnlyLineCount` / `fallbackAppliedCount`：**按合并后的数据重算**，不再原样沿用首片。
- 文档级字段（`primaryEngine`、`alignmentEngine`、`fallbackEngine`、`qualityMode`、`fusionPolicy`）保留首片值。
- `qwenRawJsonPath` / `whisperRawJsonPath` 被显式删除 —— 它们指向某一分片的工作目录，对合并结果来说是假信息。

另外 `_shiftDocument` 现在也会平移候选里的 `startMs` / `endMs`，否则第二片之后的候选时间戳会停留在该片的局部时间（今天没有 UI 读这两个键，但留着就是一颗定时炸弹）。

**注意**：修复后 ≥20 分钟音频才走合并路径，正常歌曲根本不经过这里。这项修复的价值在「超长音频也必须保留复核证据」，而不是「拯救普通歌曲」。

---

### R4【P0】检查点不随配置失效 ⇒「重新识别」静默返回旧结果

```dart
// resumable_chunked_transcription_service.dart:83
final compatible = manifest != null &&
    manifest['version'] == 1 &&
    manifest['sourceFingerprint'] == fingerprint &&   // size:mtime:path
    manifest['chunkMs'] == chunkDuration.inMilliseconds &&
    manifest['overlapMs'] == overlap.inMilliseconds;
```

指纹只含**源文件**的大小/修改时间/路径，不含：模式（whisperOnly ↔ highestQuality）、引擎顺序、模型路径与版本、语言、后端设备。而 `_outputDirectory()` 每次都是同一个 `project/transcription` 目录。

所以：用户改成 Whisper 单模型、或换了更大的 Qwen 模型、或修好了 runtime，再点「重新识别歌词」→ 逐片命中旧 JSON → **输出与上次逐字相同**。这会被用户直接解读为「这软件识别能力不行」。

**建议**：把「影响结果的配置」纳入 session 版本键（或直接删掉冲突的 session 目录）；至少接入模型身份（仓库里已有 `TranscriptionModelIdentity`）。

**处理（2026-11-01）**

manifest 版本 1 → 2，新增 `configFingerprint`：`sha256(mode | engineOrder | qwen 可执行文件/模型/对齐模型/设备/dtype | whisper 可执行文件/模型 | language | 两个复核阈值)`。用哈希而不是明文，避免把绝对路径写进工程目录。任何一项变化都会让检查点整体失效并重建 `chunks/`。

**取舍**：`ffmpegExecutable` 与 `downloadProxy` 不计入 —— 前者影响归一化参数但我们没有版本号可依赖，后者与识别结果无关。宁可少失效一次，也不要在无关设置变动时把用户的进度清空。

**升级影响**：版本号变更会让**所有**旧检查点失效一次。这是有意的：旧检查点没有记录配置，无法判断它是否对应当前设置，继续复用就是在重复 R4 本身的错误。

---

### R5【P0】「一键准备识别环境」只支持两类电脑

```dart
// native_transcription_profile_resolver.dart:165
TranscriptionProfilePreference _automaticProfileFor(hardware) {
  if (hardware.isRtx5080) return rtx5080HighQuality;
  if (hardware.isIntelMac) return intelMacHighQuality;
  return TranscriptionProfilePreference.custom;     // ← 其余全部落到这里
}

// managed_asr_runtime_manager.dart:1314
bool _profileSupportsManagedRuntime(profile) =>
    profile == rtx5080HighQuality || profile == intelMacHighQuality;

// managed_asr_runtime_manager.dart:251（安装入口，无条件先判）
if (!_profileSupportsManagedRuntime(profile.profile)) {
  throw const TranscriptionException(
    '自动安装目前支持 RTX 5080 和 Intel Mac Profile；自定义 Profile 请使用高级设置',
  );
}
```

配套事实：

- `_runtimeAssetName` 只有两个产物：`windows-x64-cuda.zip` 与 `macos-x64.zip`（`:1319`）⇒ **Apple Silicon（arm64）没有任何官方 runtime**。
- 该判断在 `install()` 最前面，**与 mode 无关** ⇒ 即使选「Whisper 单模型 · 更省空间」（whisper.cpp 本身是通用二进制），在普通电脑上也装不了。
- `custom` 档位保留配置默认值 `qwenDevice: 'cuda'` / `qwenDtype: 'bf16'`（`transcription_models.dart:105`），在 Apple Silicon / AMD 机器上必然启动失败；而 `engineOrder` 默认是 `qwenPrimary`（`:101`）⇒ Qwen 失败即整首歌失败。

也就是说：**除 RTX 5080 与 Intel Mac 之外，「推荐路径」是走不通的**；用户只能进「高级设置」手动填 whisper-cli、模型路径、GPU 后端。这与 `docs/local_transcription.md:24`「普通用户不需要理解模型目录层级」的承诺相反。

**建议**

1. 把「Whisper 单模型」定义为**全平台默认可安装**的基线（whisper.cpp 官方预编译 + large-v3 模型），彻底解耦硬件 profile。
2. Qwen 双引擎改为「可选增强」，只在检测到受支持硬件时出现。
3. 未知硬件落到 `whisperOnly + CPU/自动设备`，而不是 `custom + cuda`。
4. 若短期不做 arm64 runtime，就在 UI 明确写「Apple Silicon 暂不支持双引擎」，而不是抛一句内部错误。

---

### R6【P0】最高质量模式没有降级路径

```dart
// high_quality_transcription_service.dart:64
if (!request.config.isHighQualityConfigured) {
  throw const TranscriptionException('最高质量模式需要完整配置 Qwen3-ASR、ForcedAligner 和 Whisper large-v3');
}
```

而两条分支的容错不对称：

- `_transcribeWhisperPrimary`：Qwen 失败 → `catch` → **返回 Whisper 结果**（好）；
- `_runPrimary`（qwenPrimary）：Qwen 失败 → 直接抛（坏）；
- 两条路径里 **Whisper 失败都直接抛**（`fallback` 反而是不可失败的）。

结果：一次驱动更新、一次显存不足、一次模型路径被移动，用户就「一首歌都识别不出来」，而实际上 Whisper 完全可用。

**建议**：模式语义改为能力声明——「双引擎可用则双引擎，否则自动降级为 Whisper 并把降级原因写进结果 metadata 与 UI」。这才是「最高质量」应有的行为。

**处理（2026-11-01）**

把「最高质量」从**前置条件**改成**能力声明**，并在四处同时改，否则任何一处漏掉都会让降级走不到：

| 层 | 之前 | 现在 |
|---|---|---|
| `TranscriptionConfig.isConfigured` | 最高质量必须两引擎齐全 | 只要 Whisper 基线可用（`isWhisperConfigured`）；另加 `runsDualEngine` / `willDegradeToWhisper` 供调用方判断 |
| `AsrRuntimeStatus` | `isReady` = 所有组件就绪 | 新增 `isBaselineReady` = ffmpeg + Whisper runtime + 模型；`missingBaselineComponents` 用于报错文案 |
| 工作流 / 导入预检 / 队列恢复 / 「开始识别」按钮 | 任一组件缺失就拦下 | 只有基线缺失才拦；第二引擎缺失直接放行 |
| `HighQualityTranscriptionService` | 未配置就抛错；Qwen 失败就抛错 | 两条路径都降级为 Whisper 并记录原因 |

**降级分两种，都写进文档 metadata**：

- 配置级：Qwen 没配 → 直接走 Whisper（`degradationReason: qwenNotConfigured`）。
- 运行级：Qwen 抛错 → 用同一份已归一化音频走 Whisper（`qwenUnavailable`，`degradationDetail` 里带原始错误，例如「CUDA 显存不足」）。

**哪些错误不降级**（这是本次唯一的判断分歧点，写明理由）：

- `input`（音频缺失/损坏）—— 两个引擎会以同样方式失败，跑第二遍只是把同样的错误再收集一次，还多花一遍时间。
- `cancelled` —— 用户取消不是「换个引擎再试」的理由。

**Whisper 自己失败时仍然致命**，但错误信息会同时带上降级原因与 Whisper 的原始错误，避免用户只看到「降级也失败了」。

**UI**：工程信息面板新增「识别降级」一行并显示具体原因；「识别模式」显示为「最高质量（已降级为单引擎）」。两个「第二意见失败」的分支（Qwen 主 + Whisper 失败、Whisper 主 + Qwen 失败）也统一打上 `degraded` 标记，避免同样的情况在两个方向上表现不一致。

**取舍**：降级后的文档 `qualityMode` 仍记为请求的模式，真实情况由 `degraded` + `degradationReason` 表达。反过来（把 `qualityMode` 改成 whisperOnly）会让「用户当初选了什么」这条信息丢失，而工程信息的价值恰恰在于两者都能看到。

---

### R7【P1】Whisper 参数自第一版起从未调整

```dart
// whisper_cpp_transcription_service.dart:196
[ '-m', modelPath, '-f', inputPath, '-l', config.language,
  '-ojf', '-of', outputBase, '-pp' ]
```

对比 2026-10-02 的第一版（commit `2517435`）：**参数完全一致**。30 天内该文件只有 5 次提交，全部是进程治理/音频复用/lint（`c9ebf60`、`b2fc94c`、`df0d494`、`7bf6efd`、`572a7fb`），没有一次是识别质量。

具体缺失（对照 whisper.cpp 能力）：

| 缺失项 | 现状 | 影响 |
|---|---|---|
| `-bs / --beam-size` | 未设置 ⇒ **默认贪心解码** | 直接损失精度，通常是最划算的一项 |
| `--prompt` 初始提示 | 未传（`_buildRecognitionContext` 只给了 Qwen） | 歌名/歌手/专有名词无法引导；PRD 8.3 明确要求 |
| `-et / --entropy-thold` | 默认 2.4 | 乐器段/间奏幻觉无法收敛 |
| `-mc / --max-context` | 默认 -1 | 重复循环难以打断 |
| `-ml / --max-len`, `-sow` | 未设置 | 单段过长，断句由模型随意决定 |
| `-l auto` | **每片**独立自动识别 | 前奏/和声段可能判成错误语种，整片报废 |
| `-t / --threads` | 未设置 | 只用模型默认线程数 |
| VAD（`--vad`） | 未使用 | 纯音乐段也会输出歌词 |

**建议的最小改动**（`_runWhisper`）：

```dart
[
  '-m', config.modelPath, '-f', inputPath,
  '-l', _resolveLanguage(config.language, detected),  // 非 auto 时固定；auto 时先对最长分片探测一次
  '-bs', '5', '-bo', '5',                            // 束搜索
  '-et', '2.8', '-mc', '0',                          // 抑制幻觉与重复
  '-ml', '40', '-sow',                               // 单行长度与按词切分
  if (prompt.isNotEmpty) '--prompt', prompt,          // 歌名/歌手/风格
  '-ojf', '-of', outputBase, '-pp',
]
```

并让 `_buildRecognitionContext` 同时流向 Whisper，而不是只给 Qwen。

---

### R8【P1】置信度语义被「中性 50」污染，复核队列 = 全部歌词

```dart
// qwen3_asr_native_transcription_service.dart:941
var score = explicitConfidence ?? 50;     // 上游 items 只含 text/start/end，没有分数 ⇒ 恒为 50
```

而 UI 与排序都按 70 分阈值工作：

```dart
// lyric_editor_screen.dart:2196
bool _needsReview(int index) =>
    _isLineReviewed(index) ? false
    : document.lines[index].confidence < 70 || ...;

// lyric_editor_screen.dart:2303
final lowConfidenceCount = document.lines.where((l) => l.confidence < 70).length;

// lyric_review_priority_service.dart:77
score.add(23, '识别置信度偏低');     // 50 分 ⇒ 23 分 ⇒ 超过 minimumQueueScore(12)
```

后果：**一份完全正确的转写，工具栏也会显示「低置信度 42 / 待复核 42 / 智能复核 42」**。用户无法从告警里区分「真的是错的」和「引擎没给分数」，告警彻底失去信息量——这比不告警更糟。

**建议**

1. 把「无置信度」与「低置信度」分成两个状态（`confidenceSource: none|model`），UI 显示「未评分」而不是红色告警。
2. 复核排序以**结构证据**为主（双引擎分歧、时间轴异常、重复、异常时长），置信度只在有真实分数时参与。
3. `_needsReview` 改为基于 `LyricReviewPriorityService` 的分数阈值，而不是裸 confidence。

**处理（2026-11-01）**

按「有分数 / 没分数」拆成两种状态，而不是把阈值调松：

- `LyricLine` 新增 `confidenceSource`（`model` / `heuristic` / `unscored`），以及两个判据：`hasConfidenceScore` 与 `isLowConfidence(threshold)`（**没分数就永远不返回 true**）。JSON 往返保留该字段；旧数据缺字段时按 `model` 解析，因此历史工程的行为一字不变。
- 两个引擎都改成如实标注：`scoreAsrLine`（Qwen）在 `explicitConfidence == null` 时返回 `unscored`，分数被规则调整过时返回 `heuristic`；`scoreWhisperSegment` 在没有 token 概率时返回 `unscored`（此前同样伪造 50）。数值仍保留在 `confidence` 里，只用于排序，不再被当作精度。
- 消费侧统一走 `isLowConfidence(...)`：复核队列计数与筛选、`LyricReviewPriorityService` 的置信度阶梯、共识分析器的 `lowPrimaryConfidence`、ASR-first 管线的 `ProofreadReason.lowConfidence`。共识行的 `secondaryConfidence` 在副引擎无分数时记为 `null`，不再对占位值求平均。
- 用户能看到的部分：行徽标显示「未评分」而不是红色的「50」；编辑器手工导入的第二份转写稿也标为 `unscored`（原来写死 60，等于每一行都待复核）。
- 刻意**不改**的：`AsrHallucinationCandidateFilter` 仍然把「无分数 + 无二次证据」的行列为可疑行——那是一份需要人工确认的怀疑清单，不是给用户体验的置信度；`high_quality_transcription_service` 里以 `qwenConfidence >= 55` 决定是否采纳第二引擎候选的门槛也保持原样，因为在没有分数的情况下「不采纳」仍是保守选择。这两处都在本文件里记为后续项，而不是顺手改掉。

**实测口径**：新增 `test/features/transcription/asr_confidence_test.dart` 直接测两个评分函数与 JSON 往返；管线、共识分析器、复核排序各加一例，锁住「同一占位数值，语义不同」：未评分的行不进低置信度理由、不进复核队列，真有分数的 40 分仍然进。占位值仍是 50，所以任何一个漏改的阈值都不会被测试掩盖——它会立刻表现为「未评分行又进了队列」，测试失败。

---

### R9【P1】`max_new_tokens` 固定 1024，长歌可能静默截断

```dart
// qwen3_asr_native_transcription_service.dart:593
'max_new_tokens': 1024,
'max_batch_size': 4,
```

上游默认值是 256（`cmd_serve.rs:530`），这里放大到 1024 是对的；但它与音频时长无关，也没有检查「是否因 token 上限提前结束」。对 5 分钟以上的中文歌或含大量重复副歌的歌，存在尾部被截断且**没有任何提示**的风险。建议按音频时长估算（例如 `max(512, 时长秒数 × 6)`），并在返回文本长度接近上限时写入 metadata 触发复核提示。

**处理（2026-11-01）**

先纠正一个事实，因为它决定了这个缺陷有多严重：`max_new_tokens` 在上游是**每个分片**的预算（`transcribe.rs` 把 `opts.max_new_tokens` 塞进 `ChunkAsrBatch`，`run_asr_on_chunks_batched` 对每个 chunk 用它），而分片上限是 `MAX_ASR_INPUT_SECONDS = 1200.0`，不是本文件 R1 写的 180 秒。也就是说**整首歌（4–5 分钟）就是一个分片**，1024 个 token 要覆盖整首歌词；按每秒 4–5 个汉字估算，一首密集中文歌约 700–900 个 token，再叠上 prompt 与分隔符，1024 处在「刚好够、随时会不够」的边缘。原稿把它当成「每 3 分钟一片」的余量问题，实际上比那更紧。

改法（没有按原建议的 `max(512, 秒数×6)`，理由见下）：

```dart
// lib/features/transcription/domain/models/qwen_decode_budget.dart
max_new_tokens = max(1024, 256 + min(audio_seconds, 1200) * 8)   // 上限 9856
```

- `audio_seconds` 从标准化后的 16 kHz 单声道 PCM WAV 长度读出（32 000 字节/秒，扣掉 44 字节头），不额外调 ffprobe。
- 8 token/秒覆盖约每秒 5 个汉字并留余量；被上限 1200 秒截断，因为 runtime 一次最多只给解码器一片，更长的文件不需要更大的单次预算。
- 下限 1024 = 被替换的那个固定值，保证**没有任何请求的余量比以前更小**。原建议的 512 下限会让短视频/短片段比现状更紧，所以没采纳。
- 没有额外的硬上限：`min(audio_seconds, 1200)` 已经把结果卡在 9856。多加一个永远不会触发的 `clamp(…, 16384)` 只是死代码（第一版就写了，被自己的测试抓出来——`Duration(days: 30)` 返回的是 9856 而不是 16384）。上游 KV cache 是动态增长的，预算调大不会预分配显存，因此「算大一点」是零成本的安全选择。

另外两件事，都不属于「猜一个阈值」：

1. 实际发出的预算写进文档 metadata 的 `maxNewTokens`。以后任何一份识别结果都能回答「当时给了多少余量」，而不是回头读代码猜。
2. 同时写入 `transcriptCoverage`（最后一行结束时间 / 音频总时长，未知时为 null）。**一份在 3:10 就结束、音频有 4:40 的转写，是预算耗尽唯一的外在症状**，而这个比值是可测的。刻意只记录数值、不设阈值、不报警：歌曲本来就常有纯乐器尾奏，把它变成告警就重演了 R8 的错误。

**未做**：仍然没有「模型是否真的撞到 token 上限」的硬信号——`/v1/transcribe` 的响应里没有 `finish_reason` 或 token 计数（只有 OpenAI 兼容端点才有 `finish_reason`），所以这件事只能靠上面两个可测量的间接证据，不能假装知道。若上游未来返回 `completion_tokens`，`transcriptCoverage` 的用途可以立刻升级为「截断判定」。

---

### R10【P0·流程】没有质量语料，所以「改进」无法被证明

- 仓库已有 `tool/asr_transcript_eval.dart`、`tool/asr_preprocessing_ab_eval.dart`、`tool/forced_alignment_eval.dart`，但**没有任何语料目录、没有 CI 门禁、没有基线报告**（本仓 `find` 无 corpus/eval 数据）。
- `docs/high_quality_asr.md:16` 自己写着：「smoke test 不计算 recall/WER/漏行率/时间戳精度」。
- `docs/work_log_index.md`：「real-song recall/WER still requires a manually checked corpus」。
- 855 个用例全部是 fake/mock 行为测试；**没有一条测试能发现 R1–R9 中的任何一条**。

这是「越改越差却感觉不到」的根本原因：项目有极强的**工程纪律**（原子写盘、进程监督、安全契约、分层棘轮），但缺少**产品正确性度量**。纪律全花在了「不出错」上，没有花在「识别得对」上。

**建议（这是所有后续工作的前置条件）**：准备 5–10 首人工校对过的歌（含中文快歌、慢歌、英文、日文、有和声的），把「行召回率 / 字符错误率 / 重复行率 / 时间戳边界误差」做成一条可一键运行的命令 + CI 基线。**先有数字，再谈优化。**

---

### 2.10 其他识别相关问题（较小但真实）

| 编号 | 位置 | 问题 |
|---|---|---|
| R12 | `local_project_transcription_workflow.dart:253` | 输入优先级 `vocalPath → normalizedPath → originalPath` 听起来很讲究，但全仓 `AudioAsset(...)` 没有任何一处写入 `vocalPath` 或 `normalizedPath`（仅 `copyWith`/`fromJson` 透传）⇒ **永远走 `originalPath`**。`docs/local_transcription.md:12`、`docs/high_quality_asr.md:33` 与 `:285` 宣称的「优先人声轨」目前是空操作 |
| R13 | `qwen3_...:850 _groupTokens` | 断行规则是「停顿 ≥650ms / 行长 ≥7s / 文本 ≥54 字 / 句末标点」。对中文歌，650ms 的换气停顿会被当断句、7 秒又过长 ⇒ **断句位置常常不是歌词的句子边界**。这是 Qwen 主引擎时代最直观的「看起来不准」 |
| R14 | `qwen3_...:744 _parseSegmentLevel` 优先 | 若上游将来返回 `segments`，会直接当成歌词行（可能是 30 秒整段），绕过上面所有分组逻辑 |
| R15 | `high_quality_...:1004` | 插入的次要行不做相邻去重（与相邻主行高度相似的也照插） |
| R16 | `resumable_...:158` | 每片 `_work/` 目录（含 5–6MB WAV）不清理，长期累积 |

---

## 3. 架构审查

### 3.1 规模画像

| 指标 | 数值 |
|---|---|
| `lib/` | 240 文件 / 70,344 行 |
| `test/` | 150 文件 / 29,501 行 / 855 用例 |
| 屏幕（`*_screen.dart`） | 23 个 / 约 23,000 行 |
| >1000 行的 lib 文件 | 16 个（最大：`lyric_editor_screen.dart` 4,851 行 / 49 import） |
| 顶层对话框/抽屉类 | 32 个；`showDialog` 37 处；`showModalBottomSheet` 10 处 |
| workflow | 25 个 |
| 工作日志条目 | 150 条（`git log` 644 提交，近 30 天 589 提交） |
| `catch (_)` | 165 处 |
| 版本号 | `1.0.0+1`（从未正式发版） |

### 3.2 做得好的地方（这些不该推倒重来）

- **分层是真的收干净了**：`test/architecture_layer_imports_contract_test.dart` 的两张基线表**已经清空**，domain 不依赖 Flutter/IO，presentation 不 import data。这在本仓是一个明确的进步。
- **持久化**：`AtomicJsonFile`（校验 + 备份 + 恢复 + 故障注入钩子 + 版本号），并有跨平台 CI。
- **子进程治理**：`AsrProcessSupervisor` 统一超时/终止/输出上限；FFmpeg、whisper、Qwen 全部走它。
- **安全**：Media Hub 的 TLS 指纹固定、常量时间 token、上传限额与原子保留，做得很认真。
- **可追溯性**：150 条工作日志 + 决策记录 + 交接文档，工程记忆远好于同类个人项目。

**但请注意**：以上全部是「不出错」维度的投入。产品维度（识别得对、看得懂、点得动）几乎没有对应投入。这正是「代码质量中上，但用户信心下降」的结构性原因。

### 3.3 组合根与全局单例

```dart
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  ...
  late final TranscriptionService transcriptionService;
  ...
}
```

- 320 行的单例装配器放在 `lib/core/`，却 import 了 80+ 个 feature 的 `data/` 实现 ⇒ **core 反向依赖 features**，与 `AGENTS.md` 的分层规则相冲突（只是这条规则没被棘轮覆盖）。
- 每个 widget 都通过 `ServiceLocatorGlobal.I.xxx` 直接取服务（`initState` 里），导致：不可注入、无法并行测试、隐式全局状态。`DashboardScreen` 已经为此开了「可选注入构造参数」的后门，是补丁而非解法。

**建议**：把装配移到 `lib/app/composition_root.dart`，用构造注入（或 Provider/Riverpod）下发；widget 只依赖抽象。

### 3.4 上帝屏 + 无状态管理

- `lyric_editor_screen.dart`：4,851 行、49 个 import、29 个类、100+ 个方法、单文件 `setState`。它同时承担：加载、试听控制、时间戳编辑、内联编辑、筛选、搜索、复核打分缓存、三套校对流程编排、导出、保存、未保存拦截。
- `player_screen.dart` 3,091 行 / 32 个类；`dashboard_screen.dart` 1,620 行 / 21 个类。
- 全仓 `setState` 出现在 39 个文件；没有 Riverpod/Bloc/Provider 等状态方案；`StreamController` + `ValueNotifier` 各管一段。

这是「不敢改、改了就坏」的直接来源，也是分支冲突的重灾区（上一次审查已指出）。

### 3.5 三套语义重叠的校对流程

| 入口 | 依赖 | 行为 |
|---|---|---|
| 参考歌词纠正 | 需要外部参考歌词 | 时间轴对齐 + 批量套用 |
| 逐行智能纠错 | 需要参考歌词 + 可选 timing evidence | 只换文本、保留时间 |
| 智能校对 V2 | 可用参考歌词 + 第二份 ASR 稿 | 生成 change set，逐行审阅后应用 |

外加「查看逐行对比」「撤销最近更改」「恢复对齐前版本」共 6 个按钮。`docs/lyric_proofreading_ux_review.md` 自己把这条列为 D3「选择困难」。

**处理（2026-11-01）**

六个入口合成**一个**「校对」菜单（`LyricProofreadMenuButton`），流程本身一行没改：

| 菜单项 | 变化前 |
|---|---|
| 智能校对 V2 · 不需要参考歌词 | 「智能校对 V2」按钮 |
| 参考歌词纠正 · 有参考歌词，可一并修正时间轴 | 「参考歌词纠正」按钮 |
| 逐行智能纠错（保留时间戳）· 只改文字 | 「逐行智能纠错」按钮 |
| 查看逐行对比 | 「查看逐行对比」按钮 |
| 撤销最近更改 | 「撤销最近更改」按钮 |
| 恢复对齐前版本 | 「恢复对齐前版本」按钮 |

之所以是菜单而不是「智能合并成一个流程」：这三条路径的**输入证据不同**（无参考 / 有参考 / 有参考 + 独立校时证据），合并算法属于改写领域层，而当前没有真实语料能证明改写后更好（见 R10）。用户真正的痛点是「不知道点哪个」，菜单里并排的两行说明直接回答这个问题；剩余的组合逻辑等有语料再谈。

顺带的行为约束：每个菜单项按可用性出现（`onPressed == null` 时整项不渲染），所以空工程仍然只看到「不可用」而不会被误导。窄屏布局原本在 AppBar 放了 5 个图标按钮、工具栏又放一个 V2 按钮；现在 AppBar 一个图标菜单，工具栏在窄屏不再重复显示。

**验收**：编辑器首屏校对入口 6 → 1（工具栏）／5 → 1（窄屏 AppBar）。

领域层为这些功能写了 **2,965 行**（`domain/proofreading/`）+ 1,200 行 review widget，测试用例占全仓 39%（337/855）。它们**只在用户已经有参考歌词时才有用**——而参考歌词正是普通用户没有的东西。投入与价值严重错位。

### 3.6 双播放栈 + UI 内自建 AudioPlayer

- 播放：`just_audio` + `just_audio_media_kit`（Windows/Linux）+ `audio_service`；录音：`record`；监听：`flutter_soloud`。三套原生音频栈，各有平台差异（这本身有合理理由）。
- 但 `player_screen.dart:5` 在 **presentation 层** 直接 `import 'package:just_audio/just_audio.dart'` 并 `new AudioPlayer()`（`:1965`）做试听，完全绕过 `AudioPlayerService`：两套播放器可以同时出声、状态不同步、无法统一暂停，也违反 `AGENTS.md`「one app-scoped playback/session model」。

**处理（2026-11-03）**

先把对象弄清楚了：那个 `AudioPlayer` **不是行试听**。歌词编辑器的行试听（`_startAuditionWindow` / 校对对话框逐行逐词）一直走 `PlaybackSessionService` + `AudioPlayerService`，还带自己的窗口循环。越层的是 **KTV 录音成品的 A/B 试听**（`_KtvTakeResultSheetState`），而且后果比原文写的更直接：

- `stopRecording()`（`local_ktv_recording_service.dart:220`）**不停主播放**；录完立刻弹出结果 sheet。
- 点「播放原始人声」时，**正在播放的歌和被录的人声同时出声**，两条进度条各说各话。
- 全屏 KTV 已 `enterImmersive()`，`main.dart` 里 `if (!immersive)` 让全局播放条不渲染——用户连「暂停那首歌」的入口都看不到。

修法不是把录音塞进 `AudioPlayerService`。那个播放器永远代表「当前队列项」：把录音载进去，播放条、歌词编辑器、队列会继续描述一首已经没在响的歌，全 App 的 `seek` 都会跳到录音里——用一个新的一致性谎言换掉旧的不一致。

- 新增 app 级**试听通道** `AudioPreviewService`（domain 接口 + `just_audio` 实现 + 注册进 `ServiceLocator`），只播单个松散文件：`loadFile / play / pause / stop / seek / stateStream`。
- `ExclusiveAudioPreviewService` 负责互斥，**双向**：试听开始先暂停歌曲；歌曲开始播放则暂停试听。放在服务层而不是 widget 里，因为 sheet 可能中途消失（关闭、返回），不变量不能依赖 widget 活着。
- sheet 从 `player_screen.dart`（3,091 行）抽出为 `widgets/ktv_take_result_sheet.dart`，服务走构造注入——私有 widget 里自建播放器是它至今没有测试的根本原因。
- presentation 不再 import `just_audio`（全仓只剩 data 层一处），并加了一条分层棘轮：presentation 不许 import `just_audio` / `just_audio_media_kit` / `audio_service` / `flutter_soloud` / `record`。

**行为变化（有意的）**：试听录音会暂停歌曲；关掉 sheet 后歌曲保持暂停，不会自己接着放。

**验收**：`audio_preview_exclusivity_test.dart` 断言调用顺序为 `song.pause` 然后 `preview.play`，以及反向（歌曲开播 → 试听暂停）；`ktv_take_result_sheet_test.dart` 用假服务覆盖加载、切换、播放/暂停、文件缺失、导出后切换、关闭即停共 6 例；分层棘轮新增一条 presentation 音频实现禁令。

### 3.7 文档 / 代码漂移

- R1 的分片矛盾（两篇文档 + 代码三方不一致）。
- `docs/prd.md` 7.1「桌面端必须有：人声/伴奏分离」**完全未实现**：`AudioAsset.vocalPath` / `instrumentalPath` 全仓无写入方，只有 UI 文案和 `ProcessingStage.vocalsSeparated` 枚举。
- `docs/prd.md` 8.3「语言提示、初始提示、专有词典」：只有语言提示（且 Whisper 用 auto），初始提示与词典没有。
- 文档里大量「已实现/已验证」的措辞，与实际能力边界不一致，会持续误导后续开发（包括 AI 助手）。

### 3.8 CI / 测试与风险错配

- 25 个 workflow，其中 22 个是按路径触发的专项验证，重复跑主门禁的子集。
- 855 个用例的分布：`features/lyrics` 337（39%）、`features/transcription` 144（17%）、`features/player` 93（11%）、`features/transfer` 60（7%）。
- 融合确实有测试（`test/high_quality_transcription_service_test.dart` 785 行、`test/resumable_chunked_transcription_service_test.dart` 339 行），**但它们断言的是错误契约**：把「主行内部的一个词变成独立歌词行」写成期望值（见 R2）。这类测试越多，越会把缺陷固化成「设计」。
- 缺少的是**性质测试**：同一句歌词无论两个引擎怎么断句，输出行数都不应增加；分片不会改变整曲结果；配置变化必须使缓存失效。这三条都不需要模型，成本极低。
- 没有 golden 输出对比、没有算法性质测试（例如「同一句不同粒度不得产生重复行」）。

### 3.9 存储与性能

- 各仓库整体 JSON 读写（`docs/engineering_risks_roadmap.md` 已列为待测风险，至今没有基准数据）。上千首歌后可能变慢，但**目前没有证据说明已经到了瓶颈**——按文档建议，先测再迁。

---

## 4. UI / UX 审查（用户视角）

### 4.1 两个世界，没有统一导航

- **音乐世界**：Dashboard → LocalMusicLibraryShell（5 个 tab：曲库/歌手/专辑/收藏/播放列表）→ QuickPlay（1,073 行）→ NowPlaying（635 行）→ 全局播放条。
- **KTV 制作世界**：Dashboard「导入并识别」→ 就绪门禁 → ImportAudioScreen → 队列 → ProjectDetail（1,271 行）→ LyricEditor（4,851 行）→ Player（3,091 行）→ ImmersiveKTV。
- **设备互联世界**：MediaHub 共 8 个屏幕（桌面 hub v1/v2、移动 hub、扫码、远程库、下载管理…）。

三者之间没有 `NavigationRail` / 底部导航，只能靠 Dashboard 上的按钮和返回栈。用户第一次打开时无法建立「我在哪、下一步做什么」的心智模型。

**处理（2026-11-03）**

装了**一份**全局导航，四个去向：工程 / 音乐库 / 校对 / 设置。

- 它挂在 `MaterialApp.builder` 里、包住整个 Navigator，而不是塞进某个屏幕。原因是这个问题按屏修不了：任何一个屏幕都不知道用户是从哪个方向来的，而逐个屏幕教一遍既重复又会立刻走样。
- 宽屏是左侧 `NavigationRail`（≥1200 时展开显示文字），窄屏是底部 `NavigationBar`。**同一个 `NavigationRail` 内部放两个导航**是最初容易踩的坑（见下）。
- 「工程」就是根路由，选中它等于一路 `popUntil` 回根；其余三个 `pushNamedAndRemoveUntil` 压在根之上，因此返回键回到上一个地方而不是退出应用。
- 高亮按路由判定：`/project/:id/lyrics` 高亮**校对**（用户正在校对），`/project/:id` 与 `:id/player` 高亮**工程**。设备互传、`/now-playing`、沉浸 KTV 这些不属于四个去向的路由**不显示导航**——一个什么都没选中的侧栏只会问用户「你在哪」。
- 新增「校对」就是这件事缺的那块：它列出所有带歌词的工程，按**待复核行数**排序（而不是按更新时间），每行直接显示 `待复核 N / 低置信度 M / 未评分 K`，点进去就是该工程的歌词编辑器。在此之前，进入编辑器只能靠记住 Dashboard 上哪个工程有歌词、点进去、再找按钮。

**顺带修掉的重复导航**：`LocalMusicLibraryShell` 自己有一套 `NavigationRail`（6 项，其中一项是设置）和一套 `NavigationBar`。全局导航一上，桌面会**侧栏套侧栏**、移动会**底部导航叠底部导航**，而且「设置」出现两次。现在音乐库的 5 个分区（歌曲/艺人/专辑/收藏/歌单）变成内容区顶部的一条分行，垂直/水平边缘交给全局导航。5 个分区一个没少，跨设备传输入口也保留（宽屏在分区条右侧，窄屏仍是悬浮按钮）。

**验收**：任意页面 1 次点击回到四个去向中的任意一个（`app_navigation_shell_test.dart` 在 390/1400 两种宽度下断言点击回调；`app_destinations_test.dart` 断言路由映射与「每个去向的 route 反查等于自己」）。

**没做**：设备互传那 8 个屏幕没有并入导航（它们是流程，不是目的地）；各页面内部的返回栈仍是各自的，没有做多 Navigator 的嵌套栈——那会让 Android 返回键语义变复杂，收益不足以抵。

### 4.2 首启动门槛过高

一个普通用户想「导入一首歌拿到歌词」需要理解并操作：

1. 质量模式（最高质量 / Whisper 单模型）
2. 硬件 Profile（RTX 5080 / Intel Mac / 自定义）
3. 组件清单（FFmpeg、Whisper runtime、large-v3 模型 3.1GB、Qwen runtime、Qwen 模型、ForcedAligner）
4. 磁盘空间预检
5. 已有模型扫描 / 粘贴路径 / 浏览目录（三选一）
6. 存储位置迁移
7. 下载代理

其中任何一步失败（尤其 R5 的硬件门槛）都会把用户推回「高级设置」——一个需要填可执行文件路径和模型目录的表单。这是**给开发者用的界面，不是给唱歌的人用的界面**。

### 4.3 编辑器工具栏：一屏 25 个控件

`_EditorToolbar`（`lyric_editor_screen.dart:2588`）在同一区域提供：

- 4 个指标：行数、语言、待复核、低置信度
- 4 个筛选 chip：智能复核 / 全部 / 待复核 / 低置信度
- 播放、在播放位置插入
- ~~4 个校对入口 + 查看对比 + 撤销对齐 + 恢复对齐前版本~~ → 1 个「校对」菜单（2026-11-01 已合并，见 3.5）
- 循环试听、跟随播放、完整播放器
- 全局偏移：−100ms / 值 / +100ms / 归零
- 进度条

在紧凑宽度下这一整排变成**横向滚动却没有滚动提示**（`adaptiveControls`），右侧按钮等于不存在。用户的原话「对于用户来说有点复杂」是完全准确的，而且这不是审美问题，是可发现性故障。

**处理（2026-11-02）**

`_EditorToolbar` 从 `lyric_editor_screen.dart` 抽成 `widgets/lyric_editor_toolbar.dart`（编辑器主文件少了约 340 行），并按「一行里要反复按的东西留下、其余归位」重排：

| 原控件 | 现在在哪 |
|---|---|
| 4 个只读指标 | 合并成一行状态文本：`12 行 · ZH · 待复核 3 · 低置信度 2`（仍然带强调色） |
| 4 个筛选 chip | 1 个筛选菜单，每个选项**保留自己的计数与一句说明** |
| −100ms / 值 / +100ms / 归零 | 1 个「偏移 +200ms」菜单，按钮上直接显示当前值 |
| 在播放位置插入 | 「更多」菜单（原来同时出现在工具栏和窄屏底栏） |
| 导出 LRC | 「更多」菜单（原来在 AppBar 独占一个图标） |
| 完整播放器 | 「更多」菜单 |
| 播放 / 跟随播放 / 校对 / 添加歌词行 / 保存 | 原地保留 |
| 撤销 / 重做（2026-11-03 追加） | 「更多」菜单；菜单项不计入首屏控件数 |

两个结构性变化，比单纯减少数量更重要：

1. **不再有横向滚动**。`adaptiveControls` 的 `SingleChildScrollView` 分支被删掉，控件区在任何宽度都是 `Wrap`：宽度不够就换行，不会把东西藏到屏幕外。这同时修掉 §4.5 表格里的「横向滚动无指示器」。
2. **不可用项不再隐藏**。「在播放位置插入」在没试听过本工程时保持可见但置灰，并写明「先试听本工程」——原来它在窄屏是直接消失，用户无从知道它存在过。

**验收**：首屏可点控件（AppBar + 控件区 + 底栏，不计列表行内按钮）从约 25 降到 **7**（干净文档）／**8**（有未保存修改时，多一个保存按钮）。`test/features/lyrics/presentation/widgets/lyric_editor_toolbar_test.dart` 直接数控件。

**没做**：报告里提到的「下一处问题」跳转按钮不存在于当前代码中，属于新功能而非重排，因此没有凭空加。

### 4.4 告警噪声（见 R8）

`低置信度 N`、`待复核 N`、`智能复核 N` 三个数字在 Qwen 主引擎下**总是等于总行数**。用户学到的是「这些红点可以忽略」——一旦形成这种习惯，真正错的那些行也会被忽略。

**处理（2026-11-02）**：把三套口径收成一套。

根因不是阈值，而是**同一个问题有三个实现**：

| 数字 | 原来的来源 | 问题 |
|---|---|---|
| 低置信度 N | `document.lines.where((l) => l.isLowConfidence(70))` | 数的是全文档，**包含已复核行** |
| 待复核 N | 编辑器里手写的 `_needsReview(index)` 谓词 | 又是另一套条件（`confidence < 100 && 有 fallbackCandidate`） |
| 智能复核 N | `LyricReviewPriorityService.rank()` 的长度 | 第三个集合，排除已复核行 |

三者互不包含、各自被一个筛选器驱动，因此「三个数字不相等」和「三个数字都等于总行数」都可能出现——后者正好是最坏的可信度状态。

现在只有一个对象 `LyricReviewQueue`（`lib/features/lyrics/domain/models/lyric_review_queue.dart`）：它调用既有的排序服务得到**一个队列**，所有计数与筛选都从它派生。

- **待复核 N** = 队列长度（未复核 + 达到证据阈值），列表按分数从高到低。
- **低置信度 M** = 队列中「有真实分数且低于 70」的子集，**按构造保证 M ≤ N**。它不再是独立人口。
- **智能复核** 这个第四次重复的入口被删除：筛选器从 4 个变成 3 个（全部 / 待复核 / 低置信度）。
- **未评分 N** 取代了误导性的红色 0：状态行现在写 `12 行 · ZH · 待复核 3 · 未评分 42`，并带 tooltip 说明「引擎没有返回分数，因此不计入低置信度」。没有分数时，「低置信度」菜单项**保留但置灰**，第二行写「本稿的识别引擎没有返回分数，无从判断」——这条沿用 3.2 的规则：不可用的东西要说明原因，而不是消失。
- 行徽标同步：列表里只显示队列状态（已复核 / 优先 N），原始分数与「未评分」回到检查器里，避免同一行在两个地方被两套标准判定。

**验收**：`待复核 N ≥ 低置信度 M` 恒成立（`lowConfidenceIndices ⊆ indices`，单测断言）；一份没有结构问题的稿件，不论引擎有没有给分数，`待复核` 都是 0；未评分稿件不再出现「低置信度 0」这种看起来像「检查过了、没问题」的假阴性。原来三个数字里有两个是重复计数，现在只剩一个。

### 4.5 具体小 bug（可直接修）

| 位置 | 问题 |
|---|---|
| `lyric_editor_screen.dart:2349` | 未保存弹窗里的「保存并返回」执行的是 `pop(false)` + `onSave()`，**保存后不会返回**，用户要再按一次返回。**已修复**（2026-11-01：对话框抽成 `confirmUnsavedLyricEdits`，返回 `stay/discard/save` 三态；`save` 现在先保存再 `pop`） |
| `lyric_editor_screen.dart:2588+` | 紧凑模式下工具栏横向滚动无指示器。**已修复**（2026-11-02：控件区改为 `Wrap`，不再横向滚动） |
| `player_screen.dart:1965` | 行试听自建 `AudioPlayer`，与全局播放器可能同时出声 |
| `lyric_editor_screen.dart:109` | 默认 filter 是 `all`，但复核相关按钮在首屏最显眼处，暗示用户应该先做复核 |
| `resumable_...:158` | 分片工作目录不清理（见 R16） |

### 4.6 编辑不可撤销（计划表 3.4）

编辑器的 `撤销最近更改` 只覆盖**参考对齐**这一种操作，而且只保留一次快照、下一次编辑就作废。除此之外——改错一个字、误删一行、偏移拨反、应用了一份不该应用的校对提案——**没有回头路**，只能靠「不保存并返回」把整份文档丢掉。对一份需要逐行校对的歌词来说，这是最容易造成实际损失的一类缺陷：改错五行，要么全部重来，要么手工逐行改回。

**处理（2026-11-03）**：加入通用的编辑历史。

- `LyricEditHistory`（`lib/features/lyrics/domain/models/lyric_edit_history.dart`）是**两个栈**：撤销栈最多 50 步，重做栈在新编辑发生时作废（和任何编辑器一致）。
- 每次用户可见的修改在**修改之前**记录当前文档，共 11 处：改行文本/时间、删行、加行、在播放位置插入、全局偏移、标记复核、应用参考对齐、应用逐行纠错、应用校对提案、撤销对齐、恢复对齐前版本。
- **同一行 2 秒内的连续修改合并为一步**（`mergeKey: line:N`），否则一次重打会把 50 步额度吃光；偏移按钮同理（`mergeKey: offset`）。
- 快捷键 `Ctrl/Cmd+Z` 撤销、`Ctrl/Cmd+Shift+Z` 与 `Ctrl+Y` 重做；文本输入框内仍走它自己的撤销（更靠近焦点）。
- 「更多」菜单里两个入口**始终可见**：没有历史时置灰并写「没有可撤销的修改」/「没有可重做的修改」；有历史时直接写出这一步会撤掉什么（如「修改第 3 行（Ctrl/Cmd+Z）」），用户不必先按一下才知道。
- 加载新工程会清空历史——跨歌曲撤销会恢复另一首歌的歌词，比不能撤销更糟。
- 撤销后 `_hasChanges` 置为 true（撤销本身也是未保存状态），并同步刷新复核队列。

**验收**：误改 5 行可一路撤回到原始文档（`lyric_edit_history_test.dart` 用 5 次不同行的修改 + 5 次撤销断言文本完全回到初始值）；历史上限 50 步、更早的丢弃；重做分支被新编辑作废；快捷键有独立的 widget 测试（`lyric_edit_shortcuts_test.dart` 真实发送 Ctrl+Z / Cmd+Z / Ctrl+Shift+Z / Ctrl+Y）。

**没做**：没有做「撤销到上次保存」的一次性回退，也没有把历史持久化到磁盘。前者会和「未保存修改」拦截弹窗重叠，后者会让「撤销」把文档带回到磁盘上已经不存在的状态。

---

## 5. 值得保留的部分

写这份报告的目的不是否定整个项目。以下部分达到或超过同类项目水平，**后续重构请不要碰**：

1. `AtomicJsonFile` 持久化协议与跨平台测试。
2. `AsrProcessSupervisor` 的统一超时/终止/输出上限。
3. Media Hub 的安全模型（TLS 固定、常量时间比较、上传限额、原子保留）。
4. 分层棘轮（基线已清零，机制正确，继续收紧）。
5. 管理工作日志 / 决策记录 / 交接文档的纪律。
6. `AsrAudioNormalization` 统一音频规格（16kHz/mono/s16le）。
7. Flutter SDK 固定、`--enforce-lockfile`、质量门禁与 CI 同构。

---

## 6. 后续计划

原则：**先能测量，再修管线，再简化界面，最后重构架构。** 在质量基线建立之前，任何「优化识别」的改动都是盲改。

### Phase 0：建立质量基线（1–2 天，前置条件）

| 项 | 内容 |
|---|---|
| 交付 | 5–10 首人工校对歌曲（LRC + 说明：语种/快慢/有无和声）放在 gitignore 的 `corpus/`；`tool/asr_quality_report.dart` 一条命令输出：行召回率、CER、**重复行率**、时间戳边界 MAE、每引擎与融合后对比 |
| 验收 | 对当前 main 跑出一份基线报告；重复行率数字写进报告（我预测会 >30%） |
| 规模 | ~1 个 PR，主要是工具与文档；不改运行时行为 |

> 如果暂时没有人工校对歌词，退而求其次：先用 2 首歌 + 手工通读一遍的 LRC。**关键是「同一批歌、同一套指标、每次可复现」。**

**当前状态（2026-11-01）**：工具已就绪 —— `tool/asr_quality_report.dart` + `docs/asr_quality_baseline.md`，含行召回、精确率、CER、重复行率、行数比、时间戳 MAE/中位数/p95，以及 `--baseline --fail-on-regression` 回归门禁；`corpus/` 已加入 `.gitignore`。**真实歌曲的基线数字仍未产生**，需要 5–10 首人工校对歌词（本文件列出的 >30% 重复行率仍是算法复刻得出的预测，不是实测值）。基线跑出来后，请把数字填到本节表格的「验收」行。

### Phase 1：修复识别管线（P0，3–5 个 PR）

| # | 改动 | 验收 |
|---|---|---|
| 1.1 | 取消歌曲流程的全局 3 分钟分片（阈值 ≥15 分钟才启用，或直接移到 whisper 适配器内部） | 同一首歌只有一个 `chunk_session`；接缝重复行 = 0；metadata 完整 |
| 1.2 | 重写 `_isLikelySameLyricLine`：子串窗口相似度 + 「被主行时间包住则不插入」+ 插入上限 | 新增表驱动测试：3 种粒度组合下重复行率 < 2% |
| 1.3 | 分片合并保留/重建 metadata（含 fallbackCandidates 索引重映射） | ≥3 分钟的歌在编辑器里能看到「另一引擎候选」 |
| 1.4 | 检查点版本键纳入配置（模式/模型/语言/设备） | 改配置后重新识别，输出确实变化 |
| 1.5 | 最高质量自动降级；Whisper 失败才致命 | 断开 Qwen 后仍能得到 Whisper 草稿 + 降级提示 |
| 1.6 | Whisper 参数（R7）+ 上下文提示词 | 基线报告对比：CER / 行召回不劣化，且专有名词命中提升 |

**Phase 1 完成后，正常长度的歌应该回到「一整首、一次 Whisper、干净草稿」的状态**——这就是「最初的版本」的体验，但参数更好。

### Phase 2：让首启动能走通（P0，2 个 PR）

| # | 改动 | 验收 |
|---|---|---|
| 2.1 | 定义「基线可安装」= Whisper 单模型，全平台可用（Windows/macOS x64 + arm64）；自动安装不再依赖硬件 profile | 在一台非 RTX5080 的 Windows 与一台 Apple Silicon Mac 上，从零到「识别出第一首歌」不需要进高级设置 |
| 2.2 | Qwen 双引擎改为「可选增强」，未知硬件默认 `whisperOnly` + 安全设备参数 | 未知硬件不再出现 `cuda/bf16` 默认值 |
| 2.3 | 首启动向导压成 2 步（选方案 → 一键准备），组件细节折叠 | 用户路径 ≤3 次点击进入导入 |

### Phase 3：界面简化（1–2 周）

| # | 改动 | 验收 |
|---|---|---|
| 3.1 | 三套校对合并为一个「校对」入口 + 一个对话框（内部按有无参考歌词切换策略） | 编辑器首屏校对按钮 6 → 1 |
| 3.2 | 工具栏重排：主操作（播放/保存/下一处问题）+ 「更多」菜单；紧凑模式改为明确的溢出菜单而不是横向滚动 | 首屏可点控件 ≤8。**已完成 2026-11-02**：无「下一处问题」按钮可保留（原先就不存在），实际 7/8 个 |
| 3.3 | 复核语义重做：单一「建议复核 N 行（按优先级）」+ 无置信度显示为「未评分」 | 正确转写时告警数为 0。**已完成 2026-11-02**：`待复核 N` 为唯一计数，低置信度成为其子集，未评分单独显示 |
| 3.4 | 撤销栈（≥50 步，Ctrl+Z）+ 修复「保存并返回」 | 误改 5 行可整体回退。**已完成 2026-11-03**：「保存并返回」在 3.1 修完；撤销栈 50 步、Ctrl/Cmd+Z 与 Ctrl/Cmd+Shift+Z、Ctrl+Y |
| 3.5 | 加统一导航（桌面 NavigationRail / 移动底部导航）：音乐库 / 工程 / 校对 / 设置 | 任意页面 1 次点击回到主线。**已完成 2026-11-03**：全局侧栏/底栏 + 新增「校对」收件箱；音乐库不再自带第二套导航 |

### 4.1 现状补充（2026-11-03，三步）

`LyricEditorScreen` 原为 4,591 行、**零 widget 测试**，因为所有状态都在一个 2,067 行的 `State` 里，任何行为都只能靠驱动整个编辑器来验证。第一步做了两件互不依赖的事：

1. **把行试听的状态机搬出去。** `LineAuditionController`（`presentation/controllers/`）接管"当前在试听哪一行、是否循环、到达窗口结尾该暂停还是回到起点、动作未完成时忽略重复的边界事件、队列换到别的工程就丢弃高亮"。这些规则此前只能用整个编辑器去碰，现在有 13 个用例直接覆盖，包括调用顺序（先 seek 起播位置再 play）、同窗口的暂停/继续/重播、循环回跳、重复边界事件被吞掉、以及边界动作抛错时上报而不是静默吞掉。
2. **把三个 pane 拆成文件。** `lyric_list_pane.dart`（列表 + 行内编辑 + 时间戳对话框 + 复核行）、`lyric_inspector_pane.dart`（检查器 + 时间轴编辑 + 候选卡）、`lyric_editor_atoms.dart`（徽章、微调按钮、时间格式化）。参数一个没改，行为逐字保留；`_LyricListPane` 等私有类因此变成可测试的公开部件，并新增 5 个 widget 测试（渲染、点击选中、两种空状态、搜索过滤）。

顺带消掉一个重复常量：编辑器里的 `_reviewConfidenceThreshold = 70` 与 `LyricReviewQueue` 里的默认值原本是两份，现在统一为 `kLyricReviewConfidenceThreshold`。

屏幕从 4,591 → 2,597 行。剩下的两块是校对编排（`_openProofreadV2` 一族约 600 行）与文档编辑/撤销/保存流程。

**第二步（同日）把校对编排里的纯逻辑搬进 domain。** `_openProofreadV2` 原先在一个函数里做了四件事：解析第二份转写稿、跑管线、把管线结果翻译成审核行、再把用户的勾选拼回文档。后两件事与 UI 无关，却只能靠整个编辑器验证，因此拆成三个文件：

- `proofread_review_proposal.dart`：审核行/被删行/用户选择的类型（原先住在对话框 widget 文件里，导致 domain 无法引用——分层棘轮禁止 domain 依赖 presentation）。
- `proofread_v2_review_assembler.dart`：把两种策略的管线输出翻译成审核行、被删行与说明文案，并生成头部摘要。参考优先与被删行使用「参考索引」空间、ASR 优先使用「草稿索引」空间，所以是两条独立入口而不是一个带分支的函数。
- `proofread_v2_document_composer.dart`：把勾选结果拼回文档——locked 行无条件应用、未勾选行保留原文、被删行只在显式恢复时按时间戳插回、时间溯源跟着存活的行 id 走、参考优先改过时间才把 globalOffset 归零。

同时修掉一个真实的判定缺陷：`ForcedAligner` 是否可用原先在屏幕里内联判断「qwenRuntime 与 qwenAligner 都 ready」，而 `AsrRuntimeStatus.isBaselineReady` 的语义是「缺项当作该 profile 不需要」。这两套语义混在一起很危险——一个从未被 inspect 报出的组件会被当成可用。现在 `AsrRuntimeStatus.hasReadyComponents(Set)` 显式要求「必须报出且 ready」，供可选能力使用；baseline 语义保持不变。

屏幕 2,597 → 2,298 行（`_openProofreadV2` 从 358 行降到约 180 行，且只剩对话框与提交流程）。新增 36 个用例：assembler 16、composer 14（`isDifferent` 覆盖文本/时间/置信度/偏移/增删行）、语言映射 4，另加 runtime 判定 2 条。

**第三步（同日）把编辑会话本身搬出去。** 屏幕里剩下的六个字段——当前文档、脏标记、选中行、手工编辑标记、批量更改快照、撤销历史——由二十多处 `setState` 各自改一部分，规则写在"谁先跑到谁算"的位置：

- `LyricEditorDocumentController`（`presentation/controllers/`）接管这六个字段，并用 `LyricEditResult` 回答调用方唯一还需要知道的 UI 问题：这次编辑要不要丢掉正在试听的高亮。
- 试听耦合被**反转**而不是搬移：控制器不认识试听，屏幕用 `_isAuditionTarget`（沿用原有语义：按请求的 lineId 定位，没有 id 才退回索引）回答"这一行是不是正在播的那行"，只有**改时间**才让试听失效——改文字不会。
- 规则从隐式变成可测：只有改文字才算手工编辑（微调时间戳不算）；删行会一并删掉它的手工标记；删除后的选中行跟随接替它的那一行；同一行连续输入合并成一步撤销、不同行不合并；撤销绝不恢复已不存在的选中行；插入/删除会丢掉按下标索引的 `fallbackCandidates`；加载工程清空历史并恢复持久化的保护标记；保存时把本次会话的手工标记写回 metadata；对齐/提案这类批量更改可以整体撤销，而之后任何普通编辑都会让它失效。
- 顺带修掉一个真实的空转：`setLineReviewed` 原先只靠 `identical()` 判断"没变化"，但复核服务即使状态不变也会返回带新时间戳的文档，于是重复标记同一行会凭空多出一步撤销。现在先比对当前复核状态。
- 屏幕 2,298 → 2,064 行，新增 43 个用例。刻意留在屏幕的是复核队列、筛选、跟随播放与聚焦请求——它们是从文档派生的视图状态，不属于文档。

**仍未拆**：强制对齐 runner 的装配（需要 `ServiceLocator`），留到 4.2。

### 4.2 现状补充（2026-11-03，第一步）

第一步只搬**装配层**，不逐屏改注入：`lib/core/services/service_locator.dart`（345 行）改名为 `AppServices` 并整体移到 `lib/app/app_services.dart`，装配的东西本身一行没变。原因很直接——这一层的价值在「进程启动时把真实服务图建一次」，而它偏偏住在 `lib/core/`，也就是所有 feature 都允许依赖的那一层；于是每个屏幕都能顺手 `ServiceLocatorGlobal.I.xxx`，屏幕也就永远无法在没有整个服务图的情况下被构造（这是编辑器此前零 widget 测试的根因）。

同一次搬迁里改掉三处「装配藏在别处」：

- **路由表**：`core/navigation/app_router.dart` 的静态 `AppRouter.onGenerateRoute` → `lib/app/app_router.dart` 的 `AppRouter(services)` 实例方法。装配需要什么就从构造函数拿，`/quick-play` 那个唯一的实时状态查询也不再是隐式的。
- **App widget**：`ElysiumPlayerApp` 从 `lib/main.dart` 移到 `lib/app/app.dart`（可选 `services`，缺省取 `AppServices.instance`），`main.dart` 只剩 bootstrap + 首帧后挂接系统媒体会话；`_navigatorKey` 一并私有化。
- **路由名**：`Routes` 留在 `lib/core/navigation/routes.dart`。屏幕要 push 名字，而 `lib/core` 不能反向依赖 `lib/app`——把常量留在下层、把表放进装配层，方向才是单向的。

**强制对齐 runner 出屏幕**。4.1 之后编辑器里剩下的唯一装配耦合是 `_openProofreadV2` 里内联的 40 行闭包：读设置、解析 profile、inspect runtime、确认 `qwenRuntime`+`qwenAligner` 都 ready、再调原生 aligner，失败时抛两句中文文案。它现在被 `lib/app/lyric_editor_assembly.dart` 的 `buildForcedAlignmentRunner` 生产，编辑器只拿到 `LyricEditorDependencies`（6 个字段：project repository、播放会话、音频播放器、歌词导入/导出、runner）。文案逐字保留，所以用户可见行为不变；区别是这段逻辑终于能在装配层被读、被替换、被测试，而不再需要「打开编辑器并选择对齐」才能执行。

**棘轮**：`test/architecture/app_assembly_contract_test.dart` 冻结三件事——`lib/core` 永不 import `lib/app`；features 只允许从 `lib/app/` 拿 `app_services.dart`（拿 `app.dart`/`app_router.dart`/assembler 即失败，那等于屏幕自己造同层部件）；`AppServices.instance` 的调用点只能减少（第一步把 80 处 / 37 文件降到 **72 处 / 34 文件**，编辑器与复核收件箱清零）。另加两条声明式断言：路由表必须显式给编辑器装配依赖，`main.dart` 不得 import 任何 `presentation/`。

行为上唯一的变化是复核收件箱的构造参数从可选变必填（路由总会传），以及编辑器不再自带 runner 默认值——两者都是「少一条隐式回退」。屏幕 2,064 → 2,042 行。剩余的 34 个文件仍用 `AppServices.instance`，是有意的过渡态，后续按屏替换（下一批候选：播放器屏 7 处、`playback_lyrics_availability_sync` 5 处、`local_song_lyrics_import_action` 5 处）。

### 4.2 第二步（2026-11-03，播放面）

编辑器之后轮到播放。`player_screen.dart` 里其实混着两件事：一个从全局单例取七个服务的屏幕，和一个**已经没人能到达**的全屏 KTV 视图。后者删掉，七个里四个直接消失。

**删掉的死代码**：`_FullScreenKtvView` / `_FullScreenKtvViewState` / `_KtvAudioControlsSheet` / `_CompactSourceMenu` / `_FullscreenLyric` / `_FullscreenNoLyrics`，约 1,000 行。它们引用数都是 0——`ImmersiveKtvScreen` 早已接手全屏 KTV，旧视图再没被构造过。屏幕 2,630 → 1,533 行。

**顺带暴露的真问题**：`test/features/player/ktv_take_operation_lock_test.dart` 里有一条断言「播放器历史操作有导出/录制保护」，它读 `player_screen.dart` 源码找 `_takeMutationLocked()` —— 而那个函数只在死视图里。也就是说这条契约一直在给不可达代码保温：**KTV 录音 / 成品导出 / 录音历史的 UI 目前没有任何入口**，`KtvRecordingService`、`KtvMicrophoneService`、`KtvTakeHistoryStore` 都被构造、都有测试，却没有屏幕使用它们。这不是本步引入的（视图在更早的重写里失去入口），但本步把它变得可见。恢复那套界面是产品决定，不是重构，所以本步只删断言、记录缺口，不擅自重建。

**活下来的注入**：

- `PlaybackLyricsResolver`（domain）把 `resolveAndSyncPlaybackLyrics` 的四个协作者（工程仓库、媒体元数据仓库、播放会话、路径规范化器）绑成一个对象。三个播放面都要这同一组，此前各自持有四个可空字段 + 单例回退，那正是回退长出来的地方。
- `PlayerScreenDependencies`（仓库、播放器、会话 + 全屏 KTV 需要的元数据仓库与规范化器）、`NowPlayingDependencies`（会话、播放器、resolver）在 `lib/features/player/presentation/`；`lib/app/playback_assembly.dart` 负责从 `AppServices` 装配。
- `ImmersiveKtvScreen` 的五个服务由可选变必填，删掉逐字段的 locator 回退——它现在是唯一的全屏 KTV 面。
- `AppServices.isInitialized`：`ElysiumPlayerApp` 可以在 bootstrap 之前渲染壳（widget 测试就是这么用的），此时不挂歌词同步组件，而不是去读一个未初始化的 `late final`。

**棘轮**：`AppServices.instance` 调用点 72 → **54**（34 → 29 个文件）；新增断言——播放面五个文件零 `AppServices`、路由表必须调用对应 assembler、`player_screen.dart` 不得再声明 `_FullScreenKtvView`、`immersive_ktv_screen.dart` 是全屏 KTV 的唯一实现。

### 4.2 第三步（2026-11-03，KTV 录音回到全屏 KTV）

第二步把「KTV 录音/导出/历史没有入口」这件事摆到了台面上。这一步把它补回去，位置按产品决定：**沉浸式 KTV**（`ImmersiveKtvScreen`），不另建第二套全屏面。

**九个协作者一个包**。全屏 KTV 需要的不是五个服务，而是九个：工程仓库、媒体元数据仓库、播放器、播放会话、路径规范化器，加上麦克风、录音、演唱历史、试听。`ImmersiveKtvDependencies` 把它们绑成一个对象，由 `lib/app/playback_assembly.dart` 的 `assembleImmersiveKtvDependencies` 装配；`ImmersiveKtvScreen` 只收一个 `required this.dependencies`，播放器屏与 Now Playing 各自持一份这个包。顺带把 `PlayerScreenDependencies` 里只为全屏 KTV 存在的 `metadataRepository` / `pathCanonicalizer` 两个字段收进包里（5 字段 → 4），少一个「这个字段到底谁在用」的问题。

**界面的三段迁移**（都来自被删的 `_FullScreenKtvView`，行为逐条对应）：

- `KtvRecordingToolbar`：录音/停止、录音时长、演唱历史、麦克风四个入口。导出中禁用录音，录音或导出中禁用历史。
- `KtvMicrophoneSheet`：原 `_KtvAudioControlsSheet` 原样搬家（设备切换/刷新、实时监听、麦克风/歌曲/监听延迟三个滑块，以及录音期间锁设备与歌曲音量）。
- `KtvTakeHistorySheet`：列表、收藏、重命名、删除、点开成品；中断录音的恢复提示从「打开前的 SnackBar」改成表内横幅——扫描现在发生在列表那里，提示也就该在那里。

**变更锁是这一步真正的交付物**。`_takeMutationLocked` 的语义（`isRecording || isExporting` 期间不许删除/重命名/收藏）与两句话术逐字恢复，并且照旧在重命名对话框、删除确认框 **await 之后**再判一次——导出可能正好在这期间开始。与旧实现的两点差别：锁放在 `KtvTakeHistorySheet` 而不是屏幕上（这样测试可以直接把录音服务置为 `isExporting` 观察拒绝，而不必扫源码找函数名），以及录音/导出期间屏幕顶部常显一个指示胶囊（控制层会淡出，否则录制中的 take 既看不见也停不下来）。

**没有改变的东西**：录音开始/停止、导出与试听仍然全部走 `KtvRecordingService` 与 `AudioPreviewService`，录音不进入播放队列，4.3 的 `exclusive_preview` 语义未被触碰。**棘轮不动**：54 处 / 29 文件——这四个 KTV 服务在第二步已随死代码离开 `lib/features`，本步没有新的单例可迁，也就不能声称减了。

### 4.2 第四步（2026-11-03，本地音乐库）

播放面与 KTV 之后剩下最大的一块：本地音乐库。五个分区（歌曲 / 艺人 / 专辑 / 收藏 / 歌单）、快速播放、两个播放条、队列面板，以及它们打开的四个对话框/动作，全都在 `initState` 或函数体里直接取单例。这一步之后**播放器特性内 0 处**（除文档注释），全仓 **54 处 / 29 文件 → 32 处 / 19 文件**。

**一个包，不是四个**。`LocalLibraryDependencies` 绑定九个协作者（库仓库、收藏歌单仓库、元数据仓库、播放历史仓库、重新定位服务、音频导入服务、会话、播放器）+ `LyricsImportDependencies`（解析器 + 歌词导入器）。与播放面不同（每屏用的子集不同，所以拆成两个对象），音乐库五分区是**同一个屏幕的五个身体**，拆开只会得到四个几乎一样的类。

**三处兜底消失**：

- `showCreateLocalPlaylistDialog` / `showRenameLocalPlaylistDialog` / `showAddToLocalPlaylistDialog` 的 `repository ?? AppServices.instance...` —— 可选参数变成必填参数。调用点早就都传了仓库，兜底只是「忘传时静默退回全局」。
- `LocalFavoriteButton` 自己取仓库 → 必填 `repository`；`didUpdateWidget` 里仓库变了会重订阅。
- `PlaybackQueuePanel` 的「保存队列为歌单」→ 必填 `collectionRepository`，代价是 `NowPlayingDependencies` 多一个字段（这个按钮真的需要它，比让面板回落单例诚实）。

**两个行为变化**：① 两个播放条在 bootstrap 之前不渲染（它们原来在 `initState` 读 `late final`，未初始化会抛异常；生产总是先 `initialize()`，app 壳早已用同样理由跳过歌词同步组件）；② `LocalMusicLibraryShell` 从「无参 + `static const` 五个默认页」变成「要 `dependencies` 或显式 `sections`」，且页面只在依赖变化时重建一次——分区装在 `IndexedStack` 里，每帧重建会丢滚动位置并重新加载库。

**棘轮**：54 → **32** 处（29 → 19 文件）；新增断言——12 个库文件零 `AppServices.instance`、路由表必须调 `assembleLocalLibraryDependencies` 并走 `_libraryShell(`、装配层真的绑定九个服务并复用同一个 `buildPlaybackLyricsResolver`、`lib/app/app.dart` 必须把同一个包交给两个播放条。

### 4.2 第五步（2026-11-03，项目 / 导入 / 远程媒体）

下一批高频页面：项目详情、批量导入就绪、批量导入、远程媒体库。`ProjectDetailDependencies`、`TranscriptionImportDependencies`、`RemoteMediaLibraryDependencies` 在 `lib/app/screen_assembly.dart` 组装；路由显式传项目详情和导入依赖，导入就绪页将同一对象转交批量导入页。

**导入恢复路径没有换语义**：桌面 readiness preflight、设置页返回后刷新、ASR 环境准备后仅恢复环境故障队列、手机直接进入导入面都保留原行为。`TranscriptionQueuePanel` 的 queue / settings store / runtime manager 改为必填，去掉了它自身的 locator fallback。`AsrRuntimeSetupDialog` 内部仍从 singleton 取安装服务，作为后续独立迁移项；本轮不重做安装 UI。

远程媒体屏当前没有生产调用 / 路由点；只让其构造依赖显式，不新造入口。**没有触及歌词识别算法、歌词结果、播放器音频行为或布局**，因此不涉及识别质量回归或真实歌验证。棘轮 **32/19 → 16/14**，新增路由/依赖契约；PR #305 head `9f88da4` 的七个 CI check 全绿（质量门禁 run 41609783247）。

### 4.2 第六步（2026-11-03，Dashboard 与旧桌面分享屏）

`DashboardScreen` 原来把五个可选 collaborator 拆开传入；只要漏一个，就整个回退到 `AppServices.instance`。此外高级模型设置动作又直接从 singleton 取 `TranscriptionSettingsStore`。现在以必填的 `DashboardDependencies`（工程仓库、播放历史仓库、播放会话、播放器、转写队列、设置存储）作为一个整体，由 `lib/app/home_assembly.dart` 组装并由首页 / fallback 路由传入；已有空状态和失败重试测试改用同一份显式依赖包。

**旧桌面分享屏审查为死代码，选择删除而非注入**：`DesktopMediaSharingScreen` 有 559 行，全仓没有构造/引用；`/mediaSharing` 始终由 `DesktopMediaTransferHubV2Screen` 承载，V2 有媒体共享范围确认、HTTPS pinning 等安全契约测试。删除旧屏不会改变路由或运行时行为，也避免维护两套相似入口。新增契约确认旧文件不存在、路由仍指向 V2。

**范围边界**：没有改 ASR 算法、歌词、音频行为、Dashboard 布局或交互；识别质量不受影响，也没有真实歌曲验收声明。`TranscriptionConfigDialog` 仍是被多个 UI 调用的 singleton consumer，留给后续独立迁移。单例棘轮 **16/14 → 12/12**；PR #307 三个 check 全绿，合入 `f5bbbba` 后 `main` push 门禁 run 41615872789 通过。

### 4.2 第七步（2026-11-03，transfer surfaces）

审查确认 `CrossDeviceMediaLibraryScreen` 与旧 `DesktopMediaTransferHubScreen` 没有生产构造点，应删除而非继续注入；实际使用面为桌面 V2、手机传输首页、远程媒体 shell 与歌曲 / 艺人 / 专辑 / 下载子页。新增三类必填依赖包，并在 `lib/app/transfer_assembly.dart` 集中装配，由路由传给活动页面、shell 再把同一依赖包传给对应子屏。

**保持行为不变**：桌面 V2 仍在启动共享前展示安全确认；手机连接后仍恢复持久传输队列；远程播放仍使用原播放会话，下载仍经现有队列入本地媒体库。本轮没有改 UI、服务行为、ASR 或歌词识别。架构契约确认所有活动 transfer screens 不再直接访问 `AppServices`，旧屏文件已移除。单例棘轮 **12/12 → 5/5** 已由质量门禁验证；PR #309 已合并为 `85fa82d`；质量门禁 run 41621483112、readiness 41621483098、widget-root 41621483096 全绿。本地没有 Flutter / Dart SDK，因此格式、分析和测试结果均来自 CI。合并后 main run 41621880411 在既有 upload-deadline 时序测试失败，未改网络服务或其断言。

### 4.2 第八步（2026-11-03，ASR 设置 / runtime / 队列）

代码审查确认剩余五个 singleton consumer 应收必填依赖，而不是放宽调用点或给 widget 增加 optional fallback：配置 dialog 收 profile resolver、下载连通性检查器与 proxy store；runtime setup / 设置区复用同一个 setup dependencies 包（runtime manager、storage preflight、managed storage service、settings store 及其配置 dialog dependencies）；真实音频 smoke-test 卡片直接收 smoke service；全局队列条由 app 壳传入同一队列服务。Dashboard、项目详情、导入 readiness 与队列修复均由 `lib/app/` 装配/传递。

**保持既有语义**：设置存储实例、runtime repair/preflight/install、模型恢复、配置保存、下载代理与队列 protective-pause/recovery 流程均未改变；没有改识别算法、歌词、UI 布局或交互。队列仍只在 runtime/settings 修复后走原 recovery service 恢复。新增注入契约，并将架构测试收紧为 features 不导入 `lib/app/`；singleton 棘轮 **5/5 → 0/0**。PR #311 最终 head `b6c61c0` 的 Flutter Quality Gate run 41629406817 与所有 10 个专项 check 全绿；PR 已合并为 `cc307c6`，合并后 `main` 质量门禁 run 41630265190 通过。真实歌曲准确率不属于本次验证，也没有硬件测试要求。

### Phase 4：架构收敛（持续，2–3 周）

| # | 改动 |
|---|---|
| 4.1 | `LyricEditorScreen` 拆分为 `LyricEditorController`（状态/用例）+ 列表 pane + inspector pane + toolbar | 第一步（2026-11-03）：4,591 → 2,597 行；行试听状态机 → `LineAuditionController`（13 例），列表/检查器/原子部件独立成文件（5 例 widget 测试）。第二步（同日）：校对编排的纯逻辑 → `ProofreadV2ReviewAssembler` + `ProofreadV2DocumentComposer` + 审核行类型进 domain，屏幕 2,597 → 2,298 行（36 例）。第三步（同日）：编辑会话 → `LyricEditorDocumentController`（文档/脏标记/选中行/手工标记/批量快照/撤销历史），屏幕 2,298 → 2,064 行（43 例）。**三步合计 4,591 → 2,064 行**。强制对齐 runner 已在 4.2 第一步完成 |
| 4.2 | 装配层移到 `lib/app/`，逐步用构造注入替换 `ServiceLocatorGlobal.I` | 第一步（2026-11-03）：`ServiceLocator` → `AppServices` 迁入 `lib/app/`，路由表 / App widget / 编辑器依赖装配同批迁入。第二步（同日）：播放面改为构造注入（`PlaybackLyricsResolver` + 两个依赖对象 + `lib/app/playback_assembly.dart`），删除 1,000 行不可达的旧全屏 KTV 视图，单例调用点 72 → 54（34 → 29 文件）。**发现**：KTV 录音/导出/历史 UI 已无入口。第三步（同日）：`ImmersiveKtvDependencies`（9 个协作者）+ `lib/app/playback_assembly.dart` 装配，录音工具条 / 麦克风 sheet / 演唱历史 sheet 回到 `ImmersiveKtvScreen`，恢复 `isRecording || isExporting` 变更锁；棘轮维持 54 处 / 29 文件。第四步（同日，本地音乐库）：`LocalLibraryDependencies`（9 个协作者）+ `lib/app/local_library_assembly.dart`，五个分区 / 快速播放 / 两个播放条 / 队列面板 / 四个对话框全部构造注入，棘轮 54 → 32 处（29 → 19 文件）。第五步（同日）：项目详情、批量导入 readiness / surface、远程媒体库及队列环境修复改为依赖注入，`lib/app/screen_assembly.dart` 装配三类依赖，棘轮 32 → 16 处（19 → 14 文件）；识别与 UI 行为不变。第六步（同日）：Dashboard 收敛到必填 `DashboardDependencies`，删除 559 行无调用点的 `DesktopMediaSharingScreen`，路由仍使用 V2；棘轮 16 → 12（14 → 12 文件）。第七步（同日，transfer）：桌面 V2 / 手机传输首页 / 远程库 shell 与子页改为三类必填依赖注入，删除无调用点的 `CrossDeviceMediaLibraryScreen` 与旧 `DesktopMediaTransferHubScreen`；行为契约保持不变，棘轮 12 → 5 处（12 → 5 文件）；PR #309 三个必需 CI check 全绿。第八步（同日，ASR 设置 / runtime / 队列）：最后五个 consumer 改为必填构造注入，app 层集中装配，队列修复语义不变；棘轮 5 → 0（5 → 0 文件），PR #311 全部 CI check 通过；4.2 完成。 | 第一步（2026-11-03）：`ServiceLocator` → `AppServices` 迁入 `lib/app/`，路由表 / App widget / 编辑器依赖装配同批迁入，`Routes` 留在 `lib/core/navigation/`；`LyricEditorScreen` 改收 `LyricEditorDependencies`（含从屏幕里拆出的强制对齐 runner），复核收件箱改收 repository；棘轮测试冻结 `core→app` = 0、features 只许见 `app_services.dart`、单例调用点 80→72（37→34 文件）。剩余：其余屏幕按屏注入 |
| 4.3 | 试听统一走服务层，删除 UI 内自建 `AudioPlayer` | **已完成 2026-11-03**：越层的是 KTV 录音成品试听（行试听本来就走 `AudioPlayerService`）。新增 `AudioPreviewService` + 双向互斥装饰器，sheet 抽出并注入服务，presentation 不再 import `just_audio`，分层棘轮新增一条禁令 |
| 4.4 | 引入最小状态管理（Riverpod/Provider 任一），先只改造编辑器与播放条 | **首轮完成（2026-11-03）**：编辑器文档 controller 加入可观察状态，局部 `ChangeNotifierProvider/Selector` 只选文档/dirty/选中/undo 等字段；项目加载从 FutureBuilder build 移到 Future 完成回调。播放服务仍是唯一事实源；桌面播放条将已有 session 快照传给队列/模式控件，避免子控件重复订阅，移动条和 audio 状态继续使用现有 streams。短时 UI 状态留在 widget；识别管线不变。CI 覆盖 controller 通知、提供 session 快照的 queue panel 与全量质量门禁。
| 4.5 | 合并/退役专项 workflow，保留主门禁 + 原生构建 + runtime 发布 + 图标 | **进行中（第五切片）**：已逐项移除重复的 ASR client、transcription execution-failure、transcription readiness、transcription settings 和 root widget 聚焦 analyze/test workflows；这些检查均由 Flutter Quality Gate 的全仓 analyze 与全量测试覆盖，并由 CI 合同测试锁定。原生平台、KTV recovery、runtime 发布等专项验证暂不动，仍须逐项核对。

### Phase 5：补齐产品能力（按 PRD）

| # | 内容 | 说明 |
|---|---|---|
| 5.1 | **人声/伴奏分离**（PRD 7.1「必须有」） | 先把 ASR 输入从混音换成 vocal stem，这大概率是识别准确率最大的一次跃升；同时 KTV 伴奏模式才有真实意义 |
| 5.2 | 导出闭环：LRC / SRT / ASS + 工程清单 + 与伴奏混音 | 目前只有 LRC |
| 5.3 | 发版：语义化版本、打包产物、升级迁移 | `1.0.0+1` 从未发布 |

### 6.5 优先顺序建议（如果只能做三件事）

1. **R2 融合重复行**（用户感知最直接，改动局限在一个函数 + 一组测试）。
2. **R1/R3 去掉全局分片并保留 metadata**（一次性恢复「最初的版本」的形态）。
3. **R7 Whisper 参数 + 提示词**（把识别上限真正抬高）。

### 6.6 在修复落地之前：用现有版本拿到较干净的草稿

这一节是给「今天就要用」的操作建议（基于当前代码，不需要改代码）：

1. **模式选「Whisper 单模型 · 更省空间」**。在当前实现里，双引擎融合是重复行的主要来源；单模型结果是「一份干净的草稿」，形态最接近最初的版本。
2. **语言手动指定 `zh` / `en` / `ja`**，不要留 `auto`（每片独立自动识别，前奏容易误判）。
3. **不要反复点「重新识别歌词」**：分片检查点不会因配置变化失效（R4），你看到的结果可能还是上一次的。
4. **复核筛选先用「全部」**，不要用「智能复核」——Qwen 行置信度恒为 50，会把全部行都塞进队列（R8）。
5. 如果一首歌识别后行数明显多于人工 LRC，**不要手工删**：先把该工程目录下的 `transcription/chunk_session/` 删掉再识别一次，可以排除旧检查点的影响。

---

## 7. 今天就能做的 5 个小改动（低风险、可独立验证）

### 7.1 关闭全局分片（1 行）

```dart
// lib/core/services/service_locator.dart
transcriptionService = HighQualityTranscriptionService(
  primary: qwenNativeTranscriptionService,
  fallback: WhisperCppTranscriptionService(),
);
// 需要断点续跑时再显式包一层，阈值改为 >= 15 分钟
```

### 7.2 融合插入加「被主行包住就不插」守卫（~15 行）

```dart
for (var index = 0; index < secondaryLines.length; index++) {
  if (matchedSecondaryIndices.contains(index)) continue;
  final line = secondaryLines[index];
  // 新增：落在任一主行时间区间内部的行，视为同一歌词的另一种断句
  final enclosed = primaryLines.any(
    (p) => p.startTime <= line.startTime && line.endTime <= p.endTime,
  );
  if (enclosed) continue;
  ...
}
```

### 7.3 Whisper 参数（见 R7 片段）

### 7.4 检查点指纹加入配置

```dart
final fingerprint = [
  await _fingerprint(request.inputAudioPath),
  request.config.mode.name,
  request.config.engineOrder.name,
  request.config.modelPath,
  request.config.qwenModelPath,
  request.config.language,
].join('|');
```

### 7.5 「无置信度」不再算「低置信度」

```dart
// 新增 metadata: confidenceSource
final hasScore = explicitConfidence != null;   // Qwen items 没有分数
// UI: hasScore ? '低置信度 N' : '未评分 → 建议按时间轴/分歧复核'
```

每个改动都应在 Phase 0 的基线报告上跑一次对比，确认「重复行率下降、行召回不下降」。

---

## 8. 验证清单

因为本沙箱无 Flutter SDK，下面的清单需要在你本机执行：

```bash
flutter analyze --no-pub --no-fatal-infos lib test
flutter test
dart tool/work_log.dart check
scripts/quality_gate.sh
```

针对本次修复的重点人工验证：

- [ ] 选一首 4 分钟中文歌：识别结果行数 ≈ 人工 LRC 行数（不应明显多于）
- [ ] 检查时间轴 2:55–3:05 区间（分片接缝）没有重复/半句
- [ ] 编辑器「低置信度」数字与真实错误行数量大致相关（而不是等于总行数）
- [ ] 修改配置后重新识别，结果确实变化
- [ ] 拔掉/破坏 Qwen runtime，最高质量模式仍能产出 Whisper 草稿并显示降级原因
- [ ] 一台非 RTX5080 的 Windows 与一台 Apple Silicon Mac：从零开始 3 步内完成准备

---

## 附录 A：关键证据索引

| 主题 | 位置 |
|---|---|
| 全局分片装配 | `lib/core/services/service_locator.dart:271` |
| 分片参数 / 合并 | `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart:30-31, 83, 158, 458-484, 495` |
| 融合匹配 / 插入 | `lib/features/transcription/data/services/high_quality_transcription_service.dart:64, 879, 1004, 1028` |
| Whisper 调用 | `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart:196-215` |
| Qwen 请求 / 断行 / 置信度 | `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart:592-594, 744, 850-905, 941` |
| 硬件 profile | `lib/features/transcription/data/services/native_transcription_profile_resolver.dart:132, 165-175` |
| 自动安装门槛 | `lib/features/transcription/data/services/managed_asr_runtime_manager.dart:251-256, 1314-1326` |
| 配置默认值 | `lib/features/transcription/domain/models/transcription_models.dart:101, 105-106` |
| 编辑器评分/告警 | `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart:2196, 2303, 2349, 2588+` |
| 复核打分 | `lib/features/lyrics/domain/services/lyric_review_priority_service.dart:33, 77` |
| 把缺陷写成期望的测试 | `test/high_quality_transcription_service_test.dart:453-529` |
| 项目 metadata 写入 | `lib/features/transcription/data/services/local_project_transcription_workflow.dart:159, 253-266` |
| 文档矛盾 | `docs/high_quality_asr.md:130-133` vs `docs/local_transcription.md:158-161` |
| PRD 缺口（分离/提示词） | `docs/prd.md` 7.1 / 8.3 |

---

**结论**：这个代码库的工程质量是可信的，问题不在「代码写坏了」，而在**方向**——精力集中在安全、持久化、校对流程这些「不出错」的地方，而决定产品价值的识别管线，从第一版到今天只做了叠加，没有做过一次有度量支撑的优化。把 R1/R2/R3/R7 四件事做掉，识别体验就能回到甚至超过「最初的版本」；把 Phase 3 做掉，界面复杂的问题也就解决了。
