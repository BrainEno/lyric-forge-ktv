# Handoff

## 目标

第三十五轮（第三十三轮 PR #505 已合并为 `ffe3348`，第三十四轮构建了 iOS IPA）：手机端方便地导入音频和视频，视频自动提取声音保存成较小的音频文件（D-056）。

- 首页和音乐库都有“导入音频或视频”：从系统“文件”或相册选择，歌曲复制进 App 的 `Imported Audio` 文件夹并加入音乐库。
- 视频用原生代码提取音轨为 `.m4a`（iOS AVFoundation，Android MediaExtractor + MediaMuxer）。
- 修复用户截图里的 iPhone 显示错误（D-057）：音乐库分区条压在状态栏上、标题上方空一块、底部导航栏上方空一条。

## Git 现场

- 分支：`arena/5f0d36b6-lyric-forge-ktv`，基于 main `ffe3348`。
- 附带 `.github/workflows/ios-ipa.yml`（无签名 IPA 构建）。临时探针 `probe.yml` 合并前删除。

## 已改文件

见工作日志 `2026-12-21-0930`，决定 D-056、D-057。

## 检查结果

- 沙箱里没有 Dart/Flutter/Xcode，格式、analyze 和测试靠 PR 的 Flutter Quality Gate 和临时探针；Swift 靠 iOS IPA 工作流编译。
- 新增测试：文件类型判定、复制/去重/重名、视频提取与失败清理、不支持的文件、取消；原生通道的参数和错误码；结果汇总文案；首页空音乐库导入流程。

## 下一步

- 用户在 iPhone 上试导入音频、相册视频和“文件”里的视频。
- 用户在 iPhone 上确认安全区修复（音乐库顶部、底部导航栏上方）。
- KTV 伴奏、RTX 5080 上的识别测试（用户自测）。

## 已知风险

- Android 只直接复制 AAC 音轨，其他编码的视频会提示暂不支持。
- iOS 从相册选很长的视频时，系统会先转码出临时副本，可能要等一会儿。

最后更新：2026-12-21 09:30（Asia/Taipei）
