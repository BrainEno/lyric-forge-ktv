# Handoff

## 目标
让真实 ForcedAligner 输出可以直接进入可重复的评估 corpus，避免手动复制秒级时间戳时产生单位错误；不修改歌词或对齐结果。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 主线基线：PR #190 已合并，当前基线 `799057638705b7e4e62e4306e77e78cf64f0872f`。
- 当前分支：`feat/forced-alignment-local-capture-20261026`，目标 PR 指向 `main`。
- 本任务仅扩展离线评估工具与文档/测试；不改产品 UI。
- 本执行环境没有本地 Dart/Flutter SDK，须以最新 PR head 的 GitHub Actions 为验证依据。

## 已改文件
- `tool/forced_alignment_eval.dart`
- `test/tool/forced_alignment_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`
- 本文件与独立工作日志条目

## 本轮实现
- 新增 `capture` 子命令，从显式指定的 loopback `POST /v1/align` 端点获取真实对齐响应。
- 发送音频路径、原始参考歌词文本与语言；读取 `items` 或 `results[0].items`，将秒级起止时间转换为整数毫秒。
- 将实际 spans 与人工校验的参考 spans 包装为现有 schemaVersion 1 corpus；可创建新 corpus 或用 `--append-to` 追加样本。
- 保留空 actual span 输出，输出前重新运行语料 schema、唯一 ID、顺序与音频时长验证；不覆盖已有 output，不发送到非 loopback host。
- 更新中英日实测采集说明。

## 检查结果
- 已新增本机 loopback HTTP 回归测试，覆盖请求字段、秒转毫秒、nested response、远程 host 拒绝与超出音频时长的 span。
- 当前环境没有 Dart/Flutter SDK，未在本地运行 formatter、analyzer 或测试；必须等待此分支最新 GitHub Actions。
- 真实歌曲还没有随仓库提供，未宣称声学精度或中英日实际覆盖率通过。

## 下一步
1. CI 通过后，在重建且含 `POST /v1/align` 的 Windows/RTX 5080 runtime 上采集人工标注的中文、英文、日文样本。
2. 运行 `dart run tool/forced_alignment_eval.dart <corpus.json> --output <report.json>`，检查各语言的文本覆盖率、P95 边界误差和失败样本。
3. 在真实数据被人工审阅前，不设计自动应用词级时间戳的行为。

## 已知风险
- 需要在本机以已知 loopback 端口启动重建后的 native sidecar；当前安装的旧 bundle 可能仍不包含 `POST /v1/align`。
- reference spans 的时间必须由人工对同一份原始音频检查；工具不能判断人工标注是否正确。
- endpoint 未提供校准置信度；本次 capture 也不会合成或推断 confidence。

最后更新：2026-10-26 16:50（Asia/Taipei）
