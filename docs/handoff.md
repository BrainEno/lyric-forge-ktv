# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R11 逐项修复。Phase 0、Phase 1 的前五项、R8（置信度语义）、R9（Qwen 解码预算）、Phase 3.1（校对入口合一）、3.2（工具栏重排）、3.3（复核语义统一）、3.4（撤销栈）、3.5（统一导航）、Phase 4.3（试听统一走服务层）已完成；剩 1.6 的 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/29adf058-lyric-forge-ktv`（Arena 会话分支；每次新任务都在这条分支上从 `origin/main` 起步）。
- 本分支包含 Phase 4.3（`AudioPreviewService` + 双向互斥装饰器；KTV 录音结果 sheet 抽出并注入服务；presentation 不再 import `just_audio`；分层棘轮新增一条禁令）。合并后本文件相对 `main` 应无差异，工作区应为 clean。
- 已合并：`854a554`（Phase 3.4 撤销栈，PR #284）、`efde4b5`（Phase 3.5 统一导航，PR #285）、`c484655`（偶发失败记录，PR #286）、`376339a`（Phase 3.5 交接文档，PR #287）、`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）、`bade954`（整首一次识别 + 分片 metadata + 检查点指纹，PR #277）、`037a431`（Phase 1.5 降级，PR #278）、`dea805b`（R8 置信度语义，PR #279）、`beb52f1`（R9 Qwen 解码预算，PR #280）、`5330a36`（Phase 3.1 校对入口合一 + 「保存并返回」修复，PR #281）、`d189f6f`（Phase 3.2 工具栏重排，PR #282）、`974bcf3`（Phase 3.3 复核语义统一，PR #283）。

## 已改文件

- `lib/features/player/domain/models/audio_preview_state.dart` — 新增：试听状态（`isLoaded` / `isPlaying` / `position` / `duration`），刻意比 `PlaybackState` 小，不含队列与音源概念。
- `lib/features/player/domain/services/audio_preview_service.dart` — 新增：试听通道接口（`loadFile / play / pause / stop / seek / stateStream`）。
- `lib/features/player/data/services/just_audio_audio_preview_service.dart` — 新增：`just_audio` 实现，复用桌面解码后端；`play()` 不等待播放结束（`just_audio` 的 future 是播完才完成）。
- `lib/features/player/data/services/exclusive_audio_preview_service.dart` — 新增：双向互斥装饰器（试听前暂停歌曲；歌曲开播则暂停试听）。
- `lib/core/services/service_locator.dart` — 注册 `audioPreviewService`。
- `lib/features/player/presentation/widgets/ktv_take_result_sheet.dart` — 新增：从 `player_screen.dart` 抽出的 KTV 录音结果 sheet，服务走构造注入，文件存在性检查可注入（`previewFileExists`）。
- `lib/features/player/presentation/widgets/playback_error_banner.dart`、`.../ktv_control_label.dart`、`lib/features/player/presentation/recording_time_format.dart` — 新增：播放页与 sheet 共用的错误条、滑杆标签、时间格式化。
- `lib/features/player/presentation/screens/player_screen.dart` — 删除自建 `AudioPlayer` 与三个私有组件（3,091 → 2,633 行），改调 `KtvTakeResultSheet`。
- `test/features/player/audio_preview_exclusivity_test.dart` — 新增，6 例，锁调用顺序与两个方向。
- `test/features/player/presentation/widgets/ktv_take_result_sheet_test.dart` — 新增，6 例，假试听服务 + 假录音服务。
- `test/architecture_layer_imports_contract_test.dart` — 新增一条规则：presentation 不许 import `just_audio` / `just_audio_media_kit` / `audio_service` / `flutter_soloud` / `record`。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — §3.6 处理记录（并纠正原文「行试听」的误标）、计划表 4.3 标为完成。
- `docs/log/entries/2026-11-03-0206-audition-service.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.13.5）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（PR 相对 main 的全部改动文件）=> 0 changed（首轮由流程里的格式化步骤自动提交了一次）。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。**首轮曾红**：sheet 只 import 了 `audio_preview_service.dart`（接口文件不 re-export 状态类），`AudioPreviewState` 被当成未知类型；补 import 后通过。
  - 4 个目标测试文件 => 全通过；`bash scripts/quality_gate.sh --skip-pub-get`（全量，含工作日志契约）=> 通过。
- `audio_preview_exclusivity_test.dart` 断言：歌曲在播时 `play()` 的记录顺序为 `song.pause` → `preview.play`；歌曲已暂停时不重复 pause；歌曲开播时试听被 pause；歌曲的暂停事件不打断试听；试听本就没响时不做多余动作；释放后不再响应。
- `ktv_take_result_sheet_test.dart` 覆盖：默认加载人声 stem、有混音时默认加载混音并可切回、播放/暂停跟随服务状态、文件缺失给出原因且不调用服务、导出后自动切到混音、关闭即停。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + 条目均被引用 + 无断链。
- PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 工具栏（Phase 3.2）的取舍：**不可用项置灰而不是隐藏**（「在播放位置插入」会写明「先试听本工程」），**筛选与偏移改成菜单但保留计数与当前值**，只读指标降级为文本。没有任何功能被删除；「下一处问题」按钮在原代码中不存在，因此没有新增。
- 试听（Phase 4.3）的取舍：**试听不进入队列，也不会冒充「当前播放项」**。理由是把录音载入 app 级播放器会让播放条/歌词页/队列继续描述一首已经没在响的歌，全 App 的 `seek` 会跳到录音里。代价是：试听期间歌曲被暂停，关掉 sheet 后**保持暂停**（不会自动接着放）——这是有意的行为变化，不是回归。互斥放在服务层而非 widget，因为 sheet 可能中途消失。
- **试听文件存在性检查可注入**（`previewFileExists`）：`testWidgets` 跑在 fake-async 区里，真实文件 I/O 的 future 永远不会完成，不注入就没法测这个 sheet。
- 导航（Phase 3.5）的取舍：**导航挂在 `MaterialApp.builder` 外层**（因此需要 `navigatorKey`），因为按屏安装无法解决「不知道用户从哪来」；**设备互传不设为去向**（是流程不是目的地），这些页面与沉浸 KTV 一律不显示导航；**音乐库放弃自带导航**，5 个分区改为内容顶部分行——否则桌面侧栏套侧栏、移动底栏叠底栏，且「设置」出现两次。刻意没做：每个去向独立的嵌套 Navigator（会让 Android 返回键语义变复杂）。
- 撤销栈（Phase 3.4）的取舍：**记录的是「修改前」的文档，且只在用户可见的修改处记录**（含标记复核这类 metadata 修改）；同一行 2 秒内合并为一步，否则重打一行就吃掉全部 50 步额度；**加载工程时清空历史**——跨歌曲撤销比不能撤销更糟。刻意没做：「撤销到上次保存」（和未保存拦截弹窗重叠）与历史持久化（会把文档带回磁盘上已不存在的状态）。
- 复核语义（Phase 3.3）的取舍：**`待复核` 是唯一人口，`低置信度` 是它的子集，`未评分` 是信息而不是告警**。没有分数时「低置信度」菜单项保留但置灰并说明原因，而不是删掉——删掉会让用户以为功能不存在，显示「0」又会读成「检查过了、没问题」。行徽标只反映队列状态，原始分数回到检查器，避免同一行在两处被两套标准判定。
- 校对入口（Phase 3.1）的取舍：**只改了入口，没合并算法**。三条路径的输入证据不同（无参考 / 有参考 / 有参考 + 独立校时证据），合并算法属于领域层重写，当前没有语料能证明改写更好（R10）。用户的痛点是「不知道点哪个」，菜单里的两行说明解决的就是这个。
- 解码预算（R9）的取舍：`max_new_tokens` 在上游是**每分片**预算，分片上限 1200 秒（不是旧文档写的 180 秒）。公式 `max(1024, 256 + min(时长,1200)×8)` 最坏 9856。仍然**拿不到**「模型是否真的撞到上限」的硬信号：`/v1/transcribe` 不返回 `finish_reason` 或 token 数，只有 OpenAI 兼容端点才有；因此只记录 `maxNewTokens` 与 `transcriptCoverage` 两个可观测量，不据此报警。
- 置信度（R8）的取舍：`LyricLine.confidence` 仍是非空 `int`（117 处读取），用「占位值 + 来源标记」表达「没分数」，而不是改成可空。刻意没改的两处写在审查文档 R8 小节：可疑幻觉清单仍把「无分数 + 无二次证据」列为候选；融合里 `qwenConfidence >= 55` 的采纳门槛保持不变。
- 已知噪声残留：`secondary == null`（只跑单引擎）时 ASR-first 管线仍把每一行标 `amber`，这是既有且有测试的依据的策略，属于 Phase 3.3 的后续项，不要误以为是 R8 没修干净。
- 触摸 `project_detail_screen.dart` 会顺带格式化该文件里约 195 行历史格式债（仓库门禁只格式化「本次改动的文件」）。这是格式化器的输出，不是重写；下一个改这个文件的人不会再付一次成本。
- 权威引擎仍决定全局断句：`qwenPrimary` 时输出就是 Qwen 的细分结果，属 R7 范围（Whisper 参数与 `--prompt` 尚未优化）。
- 20 分钟阈值是**策略选择而非实测结论**：没有真实语料证明 20 分钟比 3 分钟在长音频上更好，只是对歌曲而言两者等价于「整首一次」。若将来出现超长现场录音的质量投诉，先看接缝，而不是直接把阈值调回去。
- 检查点版本升到 2 会让所有旧检查点失效一次（有意的：旧检查点没有配置指纹）。
- 真机行为（Windows/macOS 上的 FFmpeg 进程树、GPU 显存、设备端播放）仍未在本环境验证。
- **偶发失败，两次都不是已修复**：
  - run 41295405781（14 次完整门禁中的 1 次）：抓到的日志尾部指向 `forced_alignment_eval_test.dart` 的 provenance 输出附近，但那个位置是**误导**；同类竞态的真实来源是 `test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving`（两种表现：`SecureSocket.connect` 的 `Broken pipe`，以及只收到裸 408 而缺少 `upload_total_timeout`），见「下一步」第 6 条。
  - run 41485065687（PR #285 合并后的 `main` push 门禁）：`scripts/quality_gate.sh --skip-pub-get` 退出 1，**同一棵树**在 3 分钟前的 PR 门禁通过、随后临时工作流连跑两遍全量门禁也全绿（run 41485674778），故判定偶发而非回归。这个 run 连失败用例名都没拿到：本环境无法下载 Actions 日志，该 workflow 又不上传测试报告，annotation 里只有 `Process completed with exit code 1`。
  - 复现方法：把临时工作流加回分支（跑两遍 `scripts/quality_gate.sh --skip-pub-get`，把 `[E]` 行与断言上下文发成 annotation），确认后立刻删除，不要留在合并 diff 里。
  - `main` 的门禁**无法重跑**：`gh run rerun` 报 `cannot be rerun; its workflow file may be broken`，`gh workflow run` 返回 403（token 无 dispatch 权限）；要重新触发只能开一个纯文档 PR 并合并。
- `main` 基线：Phase 3.5 由 PR #285 合入（合并提交 `efde4b5`）。紧随其后的 push 门禁 run 41485065687 变红且原因未定位（见上）；确认方法是在同一棵树上连跑两遍全量门禁（临时工作流 run 41485674778，两遍全绿），随后用文档 PR #286 重新触发，run 41487053012 为绿。若本文件之后 `main` 再次变红，同样先用这个方法排除真实回归，再谈修复。

## 下一步

1. Phase 3（3.1–3.5）与 Phase 4.3 已完成。下一步优先级建议：4.1 把 `LyricEditorScreen`（4,591 行）按 4.3 同样的手法拆分——先抽一个能被假服务驱动的 widget，再拆 controller；4.2 把装配层移到 `lib/app/`，逐步用构造注入替掉 `ServiceLocatorGlobal.I`（4.3 已经示范了「注入服务 + 私有 widget 变公开可测」的路径）。
2. 需要硬件或真实语料的部分不变：4.2 之外的 Phase 2 首启动、1.6 的 Whisper 参数、R5 可安装性。
3. Phase 1.6 剩下的 Whisper 解码参数与 `--prompt`（R7）需要用 `--baseline --fail-on-regression` 验收，等真实语料。
4. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
5. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
6. 偶发失败：`test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving` 有**两种**表现——`SecureSocket.connect` 阶段 `Broken pipe`，以及这次的 `Expected: contains 'upload_total_timeout'` 只收到裸 408。同一个用例，同一类竞态。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-03 02:10（Asia/Taipei）
