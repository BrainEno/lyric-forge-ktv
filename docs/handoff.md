# Handoff

## 目标
为真实歌曲提供严格配对的旧流程/新流程 A/B 评测工具，防止参考文本、原始音源、模型版本或运行时变化混入结论。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- main 基线：`b2fc94c01de14a797b95778cdacc76d5b7393063`（PR #204 合并提交）
- 分支：`feat/asr-preprocessing-ab-evaluator-20261028`
- PR：[#205 feat: compare ASR preprocessing paths on paired corpus](https://github.com/BrainEno/lyric-forge-ktv/pull/205)
- 当前实现/格式修正提交：`7b770def21d4db396d9090157b147bfa56ac94d2`
- 此次收尾修复工作日志 commit-subject 警告，并把测试库前缀调整为 Dart lint 推荐格式；这些改动会再触发质量门。
- 当前执行环境没有 Dart/Flutter SDK，验证由 GitHub Actions 完成。

## 已改文件
- `tool/asr_preprocessing_ab_eval.dart`
- `test/tool/asr_preprocessing_ab_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/log/entries/2026-10-28-0235-asr-preprocessing-ab-evaluator.md`
- `docs/handoff.md`

## 本轮实现
- 新增旧流程与共享 WAV 流程的 A/B 比较工具，复用现有严格 transcript evaluator 计算的 CER、token error、插入、遗漏和替换指标。
- 需要样本级 `sourceAudioSha256`（预处理前原始文件哈希），`audioSha256` 记录实际传给候选引擎的标准化 WAV 哈希；基准流程可按引擎拆成多个 sample。
- 强制两个语料使用相同 songId/engine 配对、同一人工审核参考文本、同一源音频指纹和时长，以及完全相同的模型 revision 与 runtime version。
- 报告逐歌、逐引擎的错误率/编辑量差值，并检测配对候选的实际 WAV 哈希是否变化；若无变化就明确提示无法把结果归因于预处理字节变化。
- 合成测试只验证评测逻辑，不伪造歌曲结果或宣称识别率改进。

## 检查结果
- 在代码/格式修正 head `7b770def21d4db396d9090157b147bfa56ac94d2` 上，Flutter Quality Gate run [40562395476](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40562395476) 已通过：工作日志预检、Dart 格式、`flutter analyze lib test` 与仓库质量门通过，`flutter test` 报告 758 tests passed。
- 该次检查报告一条 work-log 警告：entry 中 Commit 字段与实际 Git commit subject 不一致。本次修改已将它更正为真实的 `feat: add paired ASR preprocessing evaluator`。
- 新提交会重新触发检查；最终结果需以 PR #205 最新 head 为准。
- 本地未运行 Dart/Flutter 命令。

## 下一步
确认 PR #205 最新 head 的质量门完成且 work-log lint 为 0 warning；若通过，向维护者提供真实中英日歌曲录入 baseline/shared 两套 corpus 的实操流程，不合并 PR。

## 已知风险
- 工具只验证元数据声明和配对关系，不能证明使用者实际提供的参考文本准确或哈希来自模型实际读取的文件。
- 归一化前原始源文件哈希必须从真实源文件计算；候选哈希必须来自识别时实际输入的 WAV。
- 若 baseline 与 shared WAV 哈希完全一致，该轮不能量化输入字节变化带来的效果；如果歌词结果不同，还需排查推理确定性或模型状态。
- 本 PR 新增的是严谨的评测工具，不包含真实音频、参考歌词或任何虚构的实测结果。

最后更新：2026-10-28 02:47（Asia/Taipei）
