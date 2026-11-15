# Handoff

## 目标

实现 #450：识别结果简繁混排时，比较路径不再把字形差异当成识别错误；用户可以选择输出字形，新草稿按设置统一一次，编辑器里也能预览后统一。简→繁是近似转换，界面和文档都要标明。PR 关闭 #450，合并前先征求用户确认。

## Git 现场

- 分支：`arena/8ada1083-lyric-forge-ktv`，基于 main `c6a693952f7b3a8a5f554e0251cf9a8cf6bc1488`。
- 验证用的临时 workflow `.github/workflows/tmp-450.yml` 和它提交的 `tool/.tmp_ci_*.txt` 在开 PR 前删除，不进入 PR diff。
- `chinese_script_data.g.dart` 由 `tool/generate_chinese_script_tables.dart --opencc <OpenCC 检出> --revision fae2a0a911c30764e669a7d8b0591cd8e852934a` 生成；`test/tool/generate_chinese_script_tables_test.dart` 在设置 `OPENCC_DIR` 时校验生成结果与提交的文件逐字节一致。

## 已改文件

- **字表与转换（lyrics domain，纯 Dart）**
  - `text/chinese_script_data.g.dart`：OpenCC 字符表、完整词组表（与逐字转换结果相同的词条存为 `key|`）、台湾/香港异体表、简体独有与繁体独有字集。
  - `text/chinese_script_tables.dart`：首次使用时解析；`comparisonFold` 把繁体、地区异体和简体折叠到同一代表字（幂等，简体字不会经地区表反向折叠，所以「什么」与「什麼」相同）。
  - `text/chinese_script_converter.dart`：最长词组匹配转换、`convertLine`（繁体行只做地区字形调整）、`foldForComparison`、字形判定。
  - `models/chinese_script_preference.dart`、`services/chinese_script_unification_service.dart`：自动/显式目标、跳过日韩行与手改行、可重放的 `chineseScriptUnification` 记录。
- **比较路径**：`lyric_tokenizer.dart`（默认折叠）、`lyric_alignment_service.dart`（相似度折叠，「一致」比较原写法）、`lyric_review_priority_service.dart`、`asr_text_comparison.dart`（经 tokenizer）。
- **识别**：`transcription_models.dart`（设置项与 `chineseScriptOutputTarget`）、`whisper_decoding_policy.dart`（繁体提示模板，进入指纹）、Whisper 与分片服务传参、`local_project_transcription_workflow.dart`（落盘前统一并写 `transcription.chineseScript`）、`project_proofread_evidence_loader.dart`（重放记录后仍匹配主引擎）。
- **界面**：设置对话框「中文字形」下拉框；编辑器「校对 → 统一简繁字形」对话框（预览、默认跳过手改行、可撤销、不自动保存）。
- **工具与许可**：`tool/asr_quality_report.dart`（字形折叠 CER、书写 CER、字形不一致行数）；`third_party/opencc/` 与 `lib/main.dart` 的许可证注册；`pubspec.yaml` 资源。
- **文档**：`decisions.md`（D-015）、本文件、工作日志条目 `2026-11-15-1500`。

## 检查结果

全部来自 GitHub Actions 临时 workflow；沙箱里没有 Dart/Flutter 工具链。各次运行见工作日志条目。

## 下一步

- 用真实混排的识别结果观察自动模式的命中率，再决定默认值是否保持「自动」。
- 如需更准的简→繁，可以考虑按上下文提示一简对多繁的字，而不是只依赖词组表。

## 已知风险

- 简→繁是近似转换：一简对多繁的字（发/發/髮、干/乾/幹）由 OpenCC 词组表决定，词组之外按默认候选。已知「我一出门就想你」会变成「我一齣門就想你」。界面在设置项与对话框里都提示逐行核对。
- 字表更新必须改 `chineseScriptDataRevision`；旧记录无法再证明文本未被手改，相关 V2 证据会降为只读审计（有意为之）。
- 原有 CER 现在是字形折叠后的值；旧报告与新报告比较时，字形差异造成的 CER 下降不是识别改进，书写 CER 才包含它。

最后更新：2026-11-15 15:00（Asia/Taipei）
