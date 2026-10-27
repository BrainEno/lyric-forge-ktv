# Handoff

## 目标
在 PR #204 已合并、最高质量模式已改为双引擎共用 WAV 的基础上，为真实歌曲提供严格配对的旧流程/新流程 A/B 评测工具，防止参考文本、原始音源、模型版本或运行时变化混入结论。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- main 基线：`b2fc94c01de14a797b95778cdacc76d5b7393063`（PR #204 合并提交）
- 本轮分支：`feat/asr-preprocessing-ab-evaluator-20261028`
- 新增工具：`tool/asr_preprocessing_ab_eval.dart`
- 新增测试：`test/tool/asr_preprocessing_ab_eval_test.dart`
- 当前执行环境没有 Dart/Flutter SDK；待 GitHub Actions 负责格式、分析与测试验证。

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
- 合成测试只验证评测逻辑，不伪造歌曲结果或宣称音质/识别率改进。

## 检查结果
- 本地未运行 `dart format`、`flutter analyze`、`flutter test`；本环境无 Dart/Flutter SDK。
- GitHub Actions 尚待最新提交检查，不能提前宣称通过。

## 下一步
验证新 A/B 工具的类型/格式、五个配对与混淆条件回归测试、完整 Flutter 质量门。通过后提供在 Windows 上生成 baseline/shared corpus 并对真实中英日样本评测的命令流程。

## 已知风险
- 本 PR 新增的是严谨的比较工具，不包含真实音频、参考歌词或任何虚构的测量结果。
- 工具只验证元数据声明和配对关系，不能证明使用者实际提供的参考文本确实准确或哈希来自正确文件。
- 归一化前原始源文件哈希必须由执行者从真实源文件计算；候选哈希必须来自识别时实际输入的 WAV。
- 若 baseline 与 shared WAV 哈希完全一致，该轮可以说明输入相同，但无法量化“输入字节发生变化”带来的效果；若文本结果不同还需要检查推理确定性/模型状态。

最后更新：2026-10-28 02:35（Asia/Taipei）
