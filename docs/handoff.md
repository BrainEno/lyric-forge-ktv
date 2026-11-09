# Handoff

## 目标

修复 ASR 校对将不可比较的空归一化文本误判为一致的问题。

## Git 现场

- 基线 `7e9232ac8baaf259464057ad41b4fa4f24a5ba9b`，分支 `arena/1806f5be-lyric-forge-ktv`。验证时快照：

```
8cd785b Format ASR review changes for verification
b3af8b0 Improve temporary validation diagnostics
191602c Verify incomparable ASR review evidence
7e9232a Merge pull request #392
```

最终 PR 中不保留临时验证 workflow；以当前 Git 状态为准。

## 已改文件

- ASR 共识、校对 pipeline、复核原因及中文提示、定向测试、审查报告和工作日志导航。

## 检查结果

- 固定 SDK Actions run 42623215036 通过格式化、三组定向测试和 `flutter analyze --no-pub --no-fatal-infos lib test tool`。初次验证分析命令未使用质量门禁的非致命 info 参数，失败后按门禁参数重跑通过。
- 本地无 Flutter/Dart；没有真实歌曲评测或手动 UI 检查。最终 PR 完整检查以 GitHub 状态为准。

## 下一步

- 准备授权、人工核对的真实歌曲语料，建立分语种的识别与时间误差基准；评估相邻行拼接误报后再调整策略。

## 已知风险

- 归一化规则沿用现有校对服务，并不覆盖所有可能的 Unicode 符号；超预算仍保守复核。双引擎一致不证明歌词正确。
- 原生设备、真实歌曲识别和用户界面尚未手动验证；工程跨进程写入及其他无条件写入风险仍未解决。

最后更新：2026-11-07（Asia/Taipei）
