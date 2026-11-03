# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R11 逐项修复。Phase 0、Phase 1 的前五项、R8（置信度语义）、R9（Qwen 解码预算）、Phase 3.1（校对入口合一）、3.2（工具栏重排）、3.3（复核语义统一）、3.4（撤销栈）、3.5（统一导航）、Phase 4.3（试听统一走服务层）、Phase 4.1 三步（编辑器拆分：试听状态机 + 三个 pane；校对提案逻辑进 domain；编辑会话 → 文档控制器）、Phase 4.2 第一步（装配层迁入 `lib/app/`，编辑器与复核收件箱改为构造注入）已完成；剩 1.6 的 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/e8db9f50-lyric-forge-ktv`（基于 `main` = `5007612`）。
- Phase 4.1 第三步与交接文档已合入 `main`（PR #296/#297，`e39dac6` / `5007612`），push 门禁 run 41577890630 为绿。
- 本轮（Phase 4.2 第一步）改动尚未合并：提交 `refactor: move the assembly layer into lib/app and inject the lyric editor`。
- 已合并：`854a554`（Phase 3.4）、`efde4b5`（Phase 3.5，PR #285）、`c484655` / `376339a`（交接文档，PR #286/#287）、`24306cf`（Phase 4.3 试听通道，PR #288）、`300412d`（PR #289）、`06052a7`（门禁失败自述，PR #290）、`900b935`（PR #291）、`de1f95b`（4.1 第一步，PR #292）、`5310f41`（PR #293）、`95da409`（4.1 第二步，PR #294）、`0583b6f`（4.1 第二步交接文档，PR #295）、`e39dac6`（4.1 第三步，PR #296）。

## 已改文件

- `lib/app/app_services.dart` — 新增：原 `lib/core/services/service_locator.dart`（345 行）整体迁入并改名 `AppServices`，访问点 `AppServices.instance`；服务构建顺序逐行不变。旧文件与 `ServiceLocatorGlobal` extension 删除。
- `lib/app/app.dart` — 新增：`ElysiumPlayerApp` 从 `lib/main.dart` 移出（可选 `services`，缺省取单例），`_navigatorKey` 私有化。
- `lib/app/app_router.dart` — 新增：`const AppRouter(services)` + 实例 `onGenerateRoute`（取代 `core/navigation/app_router.dart` 的静态方法）；`/review` 与 `/project/:id/lyrics` 显式传依赖。
- `lib/app/lyric_editor_assembly.dart` — 新增：`assembleLyricEditorDependencies` + `buildForcedAlignmentRunner`（把原先内联在 `_openProofreadV2` 里的设置读取 / profile 解析 / runtime 就绪检查 / 原生 aligner 调用搬出屏幕，两句中文错误文案逐字保留）。
- `lib/core/navigation/routes.dart` — 新增：`Routes` 常量与三个 path helper。刻意留在 `lib/core`（`app_destinations.dart` 与各屏要在 `lib/app` 之下引用它）。
- `lib/features/lyrics/presentation/lyric_editor_dependencies.dart` — 新增：`LyricEditorDependencies`（6 字段，runner 非空）。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart` — 2,064 → 2,042 行：`initState` 的 5 处单例查询与 40 行内联 runner 换成 `widget.dependencies`。
- `lib/features/lyrics/presentation/screens/review_inbox_screen.dart` — `projectRepository` 由可选变必填，删除单例回退。
- `lib/main.dart` — 176 → 46 行：只剩 bootstrap 与首帧后的系统媒体会话挂接。
- 38 个 feature 文件 — `ServiceLocatorGlobal.I` → `AppServices.instance`，import 指向 `lib/app/app_services.dart`。
- `test/architecture/app_assembly_contract_test.dart` — 新增棘轮（`core→app` = 0；features 只许见 `app_services.dart`；单例调用点 ≤72 / ≤34 文件；编辑器与收件箱零 `AppServices`；路由表负责装配编辑器依赖；`main.dart` 不 import `presentation/`、不含 `MaterialApp(`）。
- 测试与 workflow — 4 个读取源码路径的契约测试、2 个导航测试、`widget_test.dart` 改指向新路径；6 个 workflow 的 `paths`/`analyze` 从 `lib/core/services/service_locator.dart` / 旧 router 改为 `lib/app/app_services.dart` / `lib/app`。
- `docs/architecture_player.md`、`docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md`（§4.2 第一步记录 + Phase 4 表更新）、`docs/log/entries/2026-11-03-1320-app-assembly-layer.md`、`docs/work_log*.md`、本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.13.5）上验证，**首次运行即全绿**（run 41582433217）：`dart format`（相对 main 的改动文件）无 diff、`dart tool/work_log.dart check` 通过、`flutter analyze --no-pub --no-fatal-infos lib test` clean、`bash scripts/quality_gate.sh --skip-pub-get` 全量通过（含改动过的 widget / 契约测试与新增棘轮）。验证后该 workflow 从分支删除。
- 静态自检（无 SDK 时可用）：全仓库相对 import 全部解析到存在的文件（0 处断链）；测试里 68 个 `lib/...` 源码路径全部存在；`transcription_settings_contract_test` / `asr_managed_storage_contract_test` / `asr_storage_preflight_contract_test` / `transcription_ready_import_contract_test` 断言的字符串在新文件里逐条命中。
- 棘轮首跑即命中冻结值（72 处 / 34 文件），无基线例外。
- 逐行复刻 `tool/work_log.dart write` 语义的本地脚本：生成的三份文件与提交内容一致。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 工具栏（Phase 3.2）的取舍：**不可用项置灰而不是隐藏**（「在播放位置插入」会写明「先试听本工程」），**筛选与偏移改成菜单但保留计数与当前值**，只读指标降级为文本。没有任何功能被删除；「下一处问题」按钮在原代码中不存在，因此没有新增。
- **两次 `main` 门禁失败仍未定位**（run 41485065687、41498901477）：同一棵树在 PR 门禁与分支上的全量门禁都是绿的，最可能是 `main` 推送时 22 个专项 workflow 并发、跑满同一台 runner 导致的时序类用例抖动，但这是推断而不是结论。从下一轮起失败会自己报出用例名；在那之前不要把它们写成「已修复」。
- 装配层（4.2 第一步）的取舍：**`Routes` 留在 `lib/core`，路由表进 `lib/app`**。屏幕要 push 名字，而 `lib/core` 不能反向依赖装配层；把常量留在下层、把表放上层，依赖方向才单向。另一个取舍：**强制对齐 runner 非空且无默认值**——「runtime 是否就绪」只有设置存储与 runtime 检查能回答，给 null 默认等于把静默降级塞回 widget；不可用时抛原有的两句中文文案，由既有错误路径展示。**唯一的行为变化**是复核收件箱的 repository 由可选变必填（路由总会传）与编辑器不再自带 runner 断言。剩余的 `AppServices.instance` 调用是有意的过渡态，不要为了「一次性清理」把 34 个文件塞进同一个改动。
- 编辑会话（4.1 第三步）的取舍：**试听耦合是反转的，不是搬移的。** 控制器不认识试听，只回答「这次编辑是否让试听失效」；「这一行是不是正在播的那行」仍由屏幕判断（沿用原来的 lineId/索引语义）。因此改文字不会打断试听，改时间才会——与重构前逐字一致。另一个**有意的行为变化**：`setLineReviewed` 先比对当前复核状态，因为复核服务即使状态不变也会返回带新时间戳的新文档，旧的 `identical()` 判断抓不到，重复标记同一行会凭空多出一步撤销。刻意留在屏幕的是复核队列、筛选、跟随播放与聚焦请求——它们是从文档派生的视图状态。
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

1. 下一步：4.2 继续按屏替换。装配层与编辑器已完成，剩余 34 个文件仍用 `AppServices.instance`，优先序：`player_screen.dart`（7 处）、`playback_lyrics_availability_sync.dart`（5 处）、`local_song_lyrics_import_action.dart`（5 处）、`project_detail_screen.dart`（4 处）、`transcription_ready_import_screen.dart`（4 处）。每迁一屏就把棘轮上限调低到新值（只能降不能升）。
2. 再之后：4.4 引入最小状态管理时，`LyricEditorDocumentController` 与 `LineAuditionController` 已经是可以直接接管的 ChangeNotifier 形态（前者是纯 Dart 对象，改动成本很低）。
3. 需要硬件或真实语料的部分不变：Phase 2 首启动、1.6 的 Whisper 参数、R5 可安装性。
4. Phase 1.6 剩下的 Whisper 解码参数与 `--prompt`（R7）需要用 `--baseline --fail-on-regression` 验收，等真实语料。
5. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
6. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
7. 偶发失败：`test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving` 有**两种**表现——`SecureSocket.connect` 阶段 `Broken pipe`，以及这次的 `Expected: contains 'upload_total_timeout'` 只收到裸 408。同一个用例，同一类竞态。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-03 13:26（Asia/Taipei）
