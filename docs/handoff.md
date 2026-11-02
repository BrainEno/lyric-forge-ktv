# Handoff

## 目标

「不如以前」的识别质量回退，按 `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` 的 R1–R11 逐项修复。Phase 0、Phase 1 的前五项、R8（置信度语义）、R9（Qwen 解码预算）、Phase 3.1（校对入口合一）、3.2（工具栏重排）、3.3（复核语义统一）、3.4（撤销栈）、3.5（统一导航）已完成；剩 1.6 的 Whisper 参数需真实语料验收，Phase 2 首启动需要真机。

## Git 现场

- Repository: `BrainEno/lyric-forge-ktv`
- 分支：`arena/77e0ffaf-lyric-forge-ktv`，基于 `main@854a554`。
- 该分支包含 Phase 3.5（全局导航：桌面侧栏 / 移动底栏，四个去向 工程/音乐库/校对/设置；新增「校对」收件箱；音乐库去掉自带的第二套导航）；工作区在提交后应为 clean。
- 已合并：`fb99f4f`（Phase 0 工具，PR #274）、`f54f292`（R2 融合重复行，PR #275）、`f2d2f63`（上传用例 flake，PR #276）、`bade954`（整首一次识别 + 分片 metadata + 检查点指纹，PR #277）、`037a431`（Phase 1.5 降级，PR #278）、`dea805b`（R8 置信度语义，PR #279）、`beb52f1`（R9 Qwen 解码预算，PR #280）、`5330a36`（Phase 3.1 校对入口合一 + 「保存并返回」修复，PR #281）、`d189f6f`（Phase 3.2 工具栏重排，PR #282）、`974bcf3`（Phase 3.3 复核语义统一，PR #283）、`854a554`（Phase 3.4 撤销栈，PR #284）。

## 已改文件

- `lib/core/navigation/app_destinations.dart` — 新增：四个去向的标签/图标/路由，以及「路由 → 去向」映射（`/project/:id/lyrics` 归校对，设备互传归无）。
- `lib/core/navigation/app_navigation_shell.dart` — 新增：宽屏 `NavigationRail`、窄屏 `NavigationBar`，按部件导出以便围绕既有的播放条/队列条组合。
- `lib/features/lyrics/presentation/screens/review_inbox_screen.dart` — 新增：「校对」收件箱，按待复核行数排序，显示 待复核/低置信度/未评分，点进歌词编辑器。
- `lib/core/navigation/app_router.dart` — 新增 `/review`。
- `lib/main.dart` — 新增 `navigatorKey` 与 `_goToDestination`（工程走 popUntil 根，其余压栈）；在 `builder` 里围绕播放条安装导航；沉浸与不属于四个去向的路由不显示导航。
- `lib/features/player/presentation/screens/local_music_library_shell.dart` — 删除自带 rail/bottom bar 与「设置」入口，5 个分区改为内容顶部的分行；新增可注入 `sections` 以便测试。
- `test/core/navigation/app_destinations_test.dart`、`test/core/navigation/app_navigation_shell_test.dart`、`test/features/lyrics/presentation/screens/review_inbox_screen_test.dart`、`test/features/player/presentation/screens/local_music_library_shell_test.dart` — 新增，共 22 例。
- `test/features/settings/transcription_settings_contract_test.dart` — 源码契约测试从「音乐库侧栏有设置项」改为「设置是全局去向之一，且音乐库不再自带导航」。
- `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md` — §4.1 处理记录、计划表 3.5 标为完成。
- `docs/log/entries/2026-11-03-0043-app-navigation.md` — 本任务工作日志条目。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md` — 生成同步。
- `docs/handoff.md` — 本文件。

## 检查结果

- 本地无 Flutter/Dart SDK，用临时 CI workflow 在固定工具链（Flutter 3.47.7 / Dart 3.13.5）上验证，随后删除该 workflow（最终 diff 不含任何 CI 文件）：
  - `dart format`（PR 相对 main 的全部改动文件）=> 0 changed。
  - `flutter analyze --no-pub --no-fatal-infos lib test` => exit 0。
  - 6 个受影响测试文件 => 全通过；`bash scripts/quality_gate.sh --skip-pub-get`（全量，含工作日志契约）=> 通过。
- `app_destinations_test.dart` 锁路由映射的对称性（每个去向的 route 反查等于自己）与两个易错点：歌词编辑器归「校对」、设备互传不归任何去向。
- `app_navigation_shell_test.dart` 在 1400/390 两种宽度下断言侧栏与底栏、点击派发、高亮跟随路由、隐藏与「无去向则不显示」。
- `review_inbox_screen_test.dart` 覆盖空状态、过滤无歌词工程、按待复核排序（一个月前的工程排在最前）、跳转 `/project/abc/lyrics`、未评分显示、加载失败重试。
- `local_music_library_shell_test.dart` 断言 5 个分区仍在、切换真的换内容、`initialIndex` 生效、且不再渲染自带 rail/bottom bar。
- 逐行复刻 `tool/work_log.dart` 语义的本地脚本：生成文件一致 + 条目均被引用 + 无断链。
- PR 的 Flutter Quality Gate 在合并前等待通过。

## 已知风险

- **还没有真实歌曲的基线数字。** 工具就绪，但需要用户提供 5–10 首人工校对歌词（见 `docs/asr_quality_baseline.md` 第 8 节）。报告里旧的「>30%」预测已被实测推翻，不再引用。
- 融合修复（R2）的取舍：若和声真的在主行覆盖的时间窗内重复同一批词，该行会并入主行并失去独立时间戳（不丢词）。这是有意的。
- 降级（R6）的取舍：`input` 类错误与取消不降级；降级后 `qualityMode` 仍记为请求的模式，真实情况看 `degraded` / `degradationReason`。降级后的草稿质量**等同 Whisper 单模型**，UI 已明确标注，不要把它当成双引擎结果去做质量对比。
- 工具栏（Phase 3.2）的取舍：**不可用项置灰而不是隐藏**（「在播放位置插入」会写明「先试听本工程」），**筛选与偏移改成菜单但保留计数与当前值**，只读指标降级为文本。没有任何功能被删除；「下一处问题」按钮在原代码中不存在，因此没有新增。
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
- **两次未定位的偶发失败**，都不是已修复：
  - run 41295405781（14 次完整门禁中的 1 次）在 `test/tool/forced_alignment_eval_test.dart` 的 provenance 输出附近失败；该文件单独跑 25 次不复现。
  - run 41485065687（PR #285 合并后的 `main` push 门禁）在 `scripts/quality_gate.sh --skip-pub-get` 步骤退出 1，**同一棵树**在 3 分钟前的 PR 门禁通过、随后的临时工作流连跑两遍全量门禁也全绿，因此判定为偶发而非回归。两个 run 都抓不到失败用例名：本环境无法下载 Actions 日志，该 workflow 又不上传测试报告，annotation 里只有 `Process completed with exit code 1`。
  - 复现方法：把临时工作流加回分支（`scripts/quality_gate.sh --skip-pub-get` 跑两遍，把 `[E]` 行与断言上下文发成 annotation），确认后立刻删除。
  - `main` 的门禁**无法重跑**：`gh run rerun` 报 `cannot be rerun; its workflow file may be broken`，`gh workflow run` 返回 403（token 无 dispatch 权限）。要让 `main` 重新变绿，只能开一个改写文档的 PR 再合并一次。
- `main` 基线：`efde4b5`（PR #285 合并）之后的 push 门禁 run 41485065687 变红且原因未定位（见上）；本条改动就是为重新触发该门禁而开的文档 PR，合并后再看 run 结果决定是否需要第三次触发。

## 下一步

1. Phase 3 已完成（3.1–3.5）。下一步优先级建议：Phase 2（首启动门槛）里唯一能在 CI 里推进的是 2.3「首启动向导压成 2 步」，但仍需真机确认实际点击路径；2.1/2.2 依赖真实硬件。
2. 若继续做纯 CI 可验收项：Phase 4.3「行试听统一走 `AudioPlayerService`」属架构收敛且可写测试；4.1（拆分 `LyricEditorScreen`）收益大但改动面也大，建议单独开一轮。
3. Phase 1.6 剩下的 Whisper 解码参数与 `--prompt`（R7）需要用 `--baseline --fail-on-regression` 验收，等真实语料。
4. 需要用户提供 5–10 首人工校对语料后，用 `--baseline --fail-on-regression` 出真实基线并填进报告的 Phase 0 验收行。
5. Phase 2.1 首启动可安装性（R5）：只能在真机验收，需用户配合。
6. 偶发失败：`test/features/transfer/http_media_hub_upload_test.dart` 的 `total upload deadline applies while chunks continue arriving` 有**两种**表现——`SecureSocket.connect` 阶段 `Broken pipe`，以及这次的 `Expected: contains 'upload_total_timeout'` 只收到裸 408。同一个用例，同一类竞态。此前记录的 `forced_alignment_eval_test.dart` 位置有误。

最后更新：2026-11-03 00:43（Asia/Taipei）
