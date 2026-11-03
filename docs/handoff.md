# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R11 逐项修复。Phase 0、Phase 1 的前五项、R8（置信度语义）、R9（Qwen 解码预算）、Phase 3.1（校对入口合一）、3.2（工具栏重排）、3.3（复核语义统一）、3.4（撤销栈）、3.5（统一导航）、Phase 4.3（试听统一走服务层）、Phase 4.1 第一、二步（编辑器拆分：试听状态机 + 三个 pane；校对提案逻辑进 domain）已完成；剩 1.6 的 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/b0768890-lyric-forge-ktv`。
- Phase 4.1 第二步已合入 `main`（PR #294，合并提交 `95da409`），其 push 门禁 run 41568282203 为绿；`main` 之后的工作区应为 clean。
- 已合并：`854a554`（Phase 3.4）、`efde4b5`（Phase 3.5，PR #285）、`c484655` / `376339a`（交接文档，PR #286/#287）、`24306cf`（Phase 4.3 试听通道，PR #288）、`300412d`（PR #289）、`06052a7`（门禁失败自述，PR #290）、`900b935`（PR #291）、`de1f95b`（4.1 第一步，PR #292）、`5310f41`（4.1 交接文档，PR #293）、`95da409`（4.1 第二步，PR #294）。

## 已改文件

- `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart` — 新增：审核行/被删行/用户选择的类型，从对话框 widget 迁入 domain（domain 不允许依赖 presentation）。
- `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart` — 新增：把两种策略的管线输出翻译成审核行、被删行、说明文案与头部摘要；参考优先与被删行用参考索引空间，ASR 优先用草稿索引空间，故为两条入口。
- `lib/features/lyrics/domain/proofreading/proofread_v2_document_composer.dart` — 新增：把勾选结果拼回文档（locked 无条件应用、未勾选保留原文、被删行按时间戳插回、时间溯源跟随存活 id、参考优先改时间才归零偏移）；`isDifferent` 取代屏幕里的 `_sameProofreadLines`。
- `lib/features/lyrics/domain/proofreading/forced_alignment_language.dart` — 新增：工程语言 → ForcedAligner 语言名，未支持的语言抛错而不是回退。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart` — 2,597 → 2,298 行；`_openProofreadV2` 只剩对话框与提交流程，删除 `_composeProofreadV2Document` / `_sameProofreadLines` / `_forcedAlignmentLanguage` / 三个标签函数。
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart` — 审核类型移出，改为 import domain。
- `lib/features/transcription/domain/services/asr_runtime_manager.dart` — 新增 `hasReadyComponents(Set)`：可选能力必须「报出且 ready」，与 baseline 的「缺项视为不需要」语义区分开。
- `test/features/lyrics/domain/proofreading/proofread_v2_review_assembler_test.dart` — 新增 16 例。
- `test/features/lyrics/domain/proofreading/proofread_v2_document_composer_test.dart` — 新增 14 例。
- `test/features/lyrics/domain/proofreading/forced_alignment_language_test.dart` — 新增 4 例。
- `test/asr_runtime_status_test.dart` — 新增 2 例。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — §4.1 第二步记录、计划表 4.1 更新。
- `docs/log/entries/2026-11-03-1040-proofread-proposal-domain.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.13.5）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - 探测脚本本身红过两次：第一次是 `git merge-base HEAD origin/main` 在浅克隆上退出 128（改成 `fetch-depth: 0`）；第二次是 `hasReadyComponents` 把「组件未列出」当成 ready（`Set.every` 空集为真），用例抓到这个真实缺陷后才改成现在的实现。
  - `dart format`（相对 main 的改动文件）=> 0 changed（过程中被探测工作流自动格式化过一次并已 rebase 吸收）。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。
  - 目标测试：assembler 16 + composer 14 + 语言映射 4 + 对话框 + runtime 判定 2 + 分层棘轮 => 全通过。
  - `bash scripts/quality_gate.sh --skip-pub-get`（全量，含工作日志契约）=> 通过（run 41567177240 绿）。
- assembler 覆盖：参考顺序而非草稿顺序、插值行无草稿来源且保持琥珀色、受保护行变 locked、提案文档丢弃 globalOffset、被删行仍可见、覆盖率说明只在自动策略出现、参考警告按条数说明；ASR 优先的一一对应、低分行、受保护行、强制对齐有无词级证据两种标签、四种说明文案与警告透传；摘要计数与覆盖率可选项；标签枚举全覆盖。
- composer 覆盖：接受即替换、未接受保留草稿、locked 无条件应用、无来源新行按审核顺序插入、被删行仅显式恢复且按时间戳插回、参考优先改时间才归零偏移（文本改动与 ASR 优先不动偏移）、时间溯源只跟随存活 id、缺 id 自动补齐；`isDifferent` 识别文本/时间/置信度/偏移/增删行。
- PR #294 的 Flutter Quality Gate 通过后合并；合并后 `main` 的 push 门禁 run 41568282203 通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 工具栏（Phase 3.2）的取舍：**不可用项置灰而不是隐藏**（「在播放位置插入」会写明「先试听本工程」），**筛选与偏移改成菜单但保留计数与当前值**，只读指标降级为文本。没有任何功能被删除；「下一处问题」按钮在原代码中不存在，因此没有新增。
- **两次 `main` 门禁失败仍未定位**（run 41485065687、41498901477）：同一棵树在 PR 门禁与分支上的全量门禁都是绿的，最可能是 `main` 推送时 22 个专项 workflow 并发、跑满同一台 runner 导致的时序类用例抖动，但这是推断而不是结论。从下一轮起失败会自己报出用例名；在那之前不要把它们写成「已修复」。
- 校对提案（4.1 第二步）的取舍：**审核行的中文标签跟着类型进 domain**。它们是复核载荷的一部分（对话框只负责渲染），代价是 domain 里出现用户可见文案；换来的是「管线输出 → 审核行」这段翻译可以被测试，而不必启动整个编辑器。另一个有意的行为收窄：ASR 优先在 `draft.lines[index]` 越界时不再抛 `RangeError`（原实现会让整次校对以「无法生成或应用校对提案」失败），而是把 `originalLine` 记为 null——管线本身保证一一对应，这里只是防御。
- 强制对齐就绪判定的修正：`hasReadyComponents` 要求「组件被报出且 ready」，而 `isBaselineReady` 保留「缺项视为该 profile 不需要」的既有语义（有测试依赖它）。两者混用会把从未 inspect 到的组件当成可用，所以不要用 baseline 的写法改写可选能力检查。
- 编辑器拆分（4.1 第一步）的取舍：**只搬不改**——pane 的参数列表原样保留，所以这一步没有改变任何渲染或交互；真正有逻辑变化的是试听状态机换成了控制器（行为逐条对应原实现，仅新增「释放后不再通知」这一保护）。**仍未拆的两块**是校对编排（`_openProofreadV2` 一族约 600 行）与文档编辑/撤销/保存流程，它们与对话框、`ServiceLocator`、proofread 管线耦合更深，下一步单独做 `LyricEditorController` 时应先拆校对编排。
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

1. 下一步：4.1 第三步——文档编辑/撤销/保存的 `LyricEditorController`。屏幕里剩下的是 `_recordEdit`/`_undo`/`_redo`、行增删改、时间轴编辑、全局偏移与保存流程（约 900 行），它们与 `LyricEditHistory`、`_AlignmentUndoSnapshot`、播放位置强耦合；先抽「编辑操作 → 新文档 + 历史快照」这一层，UI 只负责触发与展示。若继续往下，再考虑把强制对齐 runner 的装配（现在内联在 `_openProofreadV2`，需要 `ServiceLocator`）移到可注入的工厂。
2. 再之后：4.2 把装配层移到 `lib/app/`，逐步用构造注入替掉 `ServiceLocatorGlobal.I`（4.1/4.3 已经示范「注入服务 + 私有 widget 变公开可测」）。
3. 需要硬件或真实语料的部分不变：Phase 2 首启动、1.6 的 Whisper 参数、R5 可安装性。
4. Phase 1.6 剩下的 Whisper 解码参数与 `--prompt`（R7）需要用 `--baseline --fail-on-regression` 验收，等真实语料。
5. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
6. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
7. 偶发失败：`test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving` 有**两种**表现——`SecureSocket.connect` 阶段 `Broken pipe`，以及这次的 `Expected: contains 'upload_total_timeout'` 只收到裸 408。同一个用例，同一类竞态。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-03 10:58（Asia/Taipei）
