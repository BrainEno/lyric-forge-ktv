# Handoff

## 目标

为当前播放工程的伴奏更新提供不打断播放的音频层安全能力，作为 #320 的第一阶段；不声称已完成 UI/队列接入。

## Git 现场

- 基线 `2727a802498cc0331e613ba176c30d0cc5713fc9`；分支 `arena/7e83b65f-lyric-forge-ktv`。最终提交和 PR 状态以 Git/GitHub 为准。

## 已改文件

- 工程音源更新能力和纯路径守卫、just_audio 与 Media Hub 包装层、相关测试、日志导航和本 handoff。

## 检查结果

- 本地无 Flutter/Dart；固定 SDK GitHub Actions run 42590251419 通过定向测试和完整门禁，并执行 format、work-log new/write/check；最终 PR 检查以 Actions 为准。
- 本地 `git diff --check`；未运行原生音频设备或手动 UI 检查。

## 下一步

在会话层用项目身份和队列快照保护接入 capability，再连接工程播放器和 UI，并验证播放位置、暂停状态、并发切歌及失败回退。当前 workaround 不变。

## 已知风险

- 此阶段未连接 UI；纯守卫只比较音源路径，不验证工程 ID 或磁盘内容。实际 just_audio 与原生平台尚无端到端验证。当前正在播放的音源发生变化会被拒绝，不会静默切轨。
- 旧伴奏副本清理、分离、人声轨导入和跨进程一致性仍待后续。Media Hub 上传 deadline 测试历史上间歇失败。

最后更新：2026-11-09 17:04（Asia/Taipei）
