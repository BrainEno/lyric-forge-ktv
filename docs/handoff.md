# Handoff

## 目标

为 #320 在导入已有伴奏后尝试安全同步播放会话。

## Git 现场

- 基线 `8b1a741e135f3595e477bc20fd3fe76c63b5fbad`；分支 `arena/3e0eb0be-lyric-forge-ktv`。最终状态以 Git/GitHub 为准。

## 已改文件

- 工程详情依赖和界面、应用组装、widget 测试、工作日志与导航。

## 检查结果

- 固定 SDK Actions run 42598612125 通过定向测试、完整门禁及工作日志检查；本地无 Flutter/Dart。
- 首次完整门禁 run 42598221905 的 Media Hub 上传 deadline 测试在 TLS 连接时报 Broken pipe。未进行原生设备播放或手动 UI 检查。

## 下一步

- 在真实设备上验证正在播放、暂停、替换正在使用的伴奏、切歌竞争和窗口关闭；核验回退提示后再考虑放宽限制。

## 已知风险

- UI 回归使用 fake；会话能力基于同 isolate 路径快照，不检查文件内容或跨进程写入；持久化为 best-effort。
- 自动分离、人声导入、旧副本清理尚未完成；Media Hub 上传 deadline 测试历史上间歇失败。

最后更新：2026-11-07 18:05（Asia/Taipei）
