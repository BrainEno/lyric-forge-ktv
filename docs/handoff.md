# Handoff

## 目标

为 #320 增加会话级工程音轨安全更新能力，保留播放与队列状态；提交中文 PR，不自动合并。

## Git 现场

- 基线 `031cb4829b799eeee5056ff1b49d582b33ad6850`；分支 `arena/71ce4390-lyric-forge-ktv`。最终提交和 PR 状态以 Git/GitHub 为准。

## 已改文件

- 播放会话接口、默认实现和两层装饰器、会话回归测试、日志导航和本 handoff。

## 检查结果

- 本地无 Flutter/Dart；固定 SDK GitHub Actions run 42593597602 通过定向与完整质量门禁，并执行 format、work-log new/write/check。首次完整门禁 run 42593178811 在 Media Hub 上传 deadline 测试失败，现有日志缺少具体异常。最终 PR 检查以 Actions 为准。
- 本地 `git diff --check`；未做原生音频设备或手动 UI 检查。

## 下一步

设计界面调用并覆盖新伴奏、当前音源被替换、切歌竞争、更新失败的提示与回退；在接入并验证后才能移除当前 workaround。

## 已知风险

- 本轮能力尚无 UI 调用方；检查基于同一 isolate 会话和音频路径，不检测文件内容或跨进程变更；队列持久化沿用 best-effort。测试为 fake 后端，未验证真实 just_audio 或原生设备。
- 当前播放音源本身变化仍被拒绝；自动分离、人声轨导入、旧副本清理及跨进程一致性仍待后续。Media Hub 上传 deadline 测试历史上间歇失败。

最后更新：2026-11-09 17:30（Asia/Taipei）
