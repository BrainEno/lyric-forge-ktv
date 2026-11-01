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

领域层为这些功能写了 **2,965 行**（`domain/proofreading/`）+ 1,200 行 review widget，测试用例占全仓 39%（337/855）。它们**只在用户已经有参考歌词时才有用**——而参考歌词正是普通用户没有的东西。投入与价值严重错位。

### 3.6 双播放栈 + UI 内自建 AudioPlayer

- 播放：`just_audio` + `just_audio_media_kit`（Windows/Linux）+ `audio_service`；录音：`record`；监听：`flutter_soloud`。三套原生音频栈，各有平台差异（这本身有合理理由）。
- 但 `player_screen.dart:5` 在 **presentation 层** 直接 `import 'package:just_audio/just_audio.dart'` 并 `new AudioPlayer()`（`:1965`）做行试听，完全绕过 `AudioPlayerService`：两套播放器可以同时出声、状态不同步、无法统一暂停，也违反 `AGENTS.md`「one app-scoped playback/session model」。

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
- 4 个校对入口 + 查看对比 + 撤销对齐 + 恢复对齐前版本
- 循环试听、跟随播放、完整播放器
- 全局偏移：−100ms / 值 / +100ms / 归零
- 进度条

在紧凑宽度下这一整排变成**横向滚动却没有滚动提示**（`adaptiveControls`），右侧按钮等于不存在。用户的原话「对于用户来说有点复杂」是完全准确的，而且这不是审美问题，是可发现性故障。

### 4.4 告警噪声（见 R8）

`低置信度 N`、`待复核 N`、`智能复核 N` 三个数字在 Qwen 主引擎下**总是等于总行数**。用户学到的是「这些红点可以忽略」——一旦形成这种习惯，真正错的那些行也会被忽略。

### 4.5 具体小 bug（可直接修）

| 位置 | 问题 |
|---|---|
| `lyric_editor_screen.dart:2349` | 未保存弹窗里的「保存并返回」执行的是 `pop(false)` + `onSave()`，**保存后不会返回**，用户要再按一次返回 |
| `lyric_editor_screen.dart:2588+` | 紧凑模式下工具栏横向滚动无指示器 |
| `player_screen.dart:1965` | 行试听自建 `AudioPlayer`，与全局播放器可能同时出声 |
| `lyric_editor_screen.dart:109` | 默认 filter 是 `all`，但复核相关按钮在首屏最显眼处，暗示用户应该先做复核 |
| `resumable_...:158` | 分片工作目录不清理（见 R16） |

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
| 3.2 | 工具栏重排：主操作（播放/保存/下一处问题）+ 「更多」菜单；紧凑模式改为明确的溢出菜单而不是横向滚动 | 首屏可点控件 ≤8 |
| 3.3 | 复核语义重做：单一「建议复核 N 行（按优先级）」+ 无置信度显示为「未评分」 | 正确转写时告警数为 0 |
| 3.4 | 撤销栈（≥50 步，Ctrl+Z）+ 修复「保存并返回」 | 误改 5 行可整体回退 |
| 3.5 | 加统一导航（桌面 NavigationRail / 移动底部导航）：音乐库 / 工程 / 校对 / 设置 | 任意页面 1 次点击回到主线 |

### Phase 4：架构收敛（持续，2–3 周）

| # | 改动 |
|---|---|
| 4.1 | `LyricEditorScreen` 拆分为 `LyricEditorController`（状态/用例）+ 列表 pane + inspector pane + toolbar |
| 4.2 | 装配层移到 `lib/app/`，逐步用构造注入替换 `ServiceLocatorGlobal.I` |
| 4.3 | 行试听统一走 `AudioPlayerService`，删除 UI 内自建 `AudioPlayer` |
| 4.4 | 引入最小状态管理（Riverpod/Provider 任一），先只改造编辑器与播放条 |
| 4.5 | 合并/退役 22 个专项 workflow，保留主门禁 + 原生构建 + runtime 发布 + 图标 |

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
