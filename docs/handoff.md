# Handoff

## 目标

审计路线的第十三轮（第十二轮 PR #484 已合并为 `55b70b3`）。用户这一轮只说“接着开发下一轮”，所以按第十二轮交接里的建议做：设置里显示自动配对、桌面传输中心收尾（T-02），并把落后于代码的审计总表补齐。lib+test 代码量按以往要求不少于 800 行。

1. 设置 → 曲库目录卡片显示“已自动配对 N 首歌”和“在音乐库查看”（没有时写“还没有按文件名自动配对的歌曲”）。数字来自 `LibraryLyricsAutoLinker.autoPairedCount`，和音乐库“自动配对”智能列表是同一批歌。更改曲库目录、立即配对歌词之后，以及从音乐库返回时都会重新计数；计数失败就不显示这一行。跳转用新路由 `/library/auto-paired`，打开歌曲分区并选中“自动配对”。所有音乐库路由改由 `LocalMusicLibraryShell.targetFor` 决定分区和智能列表，路由表少了五个几乎一样的分支。
2. 桌面传输中心（T-02 桌面部分）：711 行的页面拆成页面、卡片（`desktop_transfer_hub_cards.dart`）和文案（`desktop_transfer_hub_text.dart`）。等待卡片用共享的加载行并说明是在读取音乐库还是在启动服务，另一步进行中时“启动并生成二维码”不可点；歌曲列表首次读取时显示加载行而不是“0 首”，为空时用共享空状态并给出“打开音乐库”“刷新电脑音乐库”；“电脑 Library”统一为“电脑音乐库”；地址列表显示“局域网 / Tailscale（可远程连接）/ 其他网络”；小于 1 KB 的文件写成“N B”；在手机上打开时是带“连接电脑”按钮的空状态。接收目录仍按路径写作 `LyricForge/Incoming`（D-030）。
3. 审计总表 `artifacts/ui-audit/reports/issues.md` 末尾加了“处理状态（第 13 轮核对）”，逐条写明状态和能复核的位置；文件开头提示以这一节为准。

## Git 现场

- 分支：`arena/92da7a3f-lyric-forge-ktv`，基于 main `55b70b3`；PR #485。
- 提交：`Show automatic pairings in settings`、`Tidy the desktop transfer hub`、`Remove the format probe and update the handoff`。

## 已改文件

见工作日志 `2026-11-30-0930`、`2026-11-30-1100` 两条记录；没有新的决定记录（设置卡片是 D-034 的延伸）；审计总表加了 T-02 第 13 轮备注和状态一节。

## 检查结果

沙箱里没有 Dart/Flutter，格式、analyze 和测试只在 PR 的 CI 上跑，并用了临时探针工作流（合并前删除）。行长度在本地按字符数检查过；工作日志用 `tool/work_log.dart` 的 Python 移植版跑了 `write` 和 `check`（0 错误）。探针结果：格式无差异；analyze 184 条（与基线持平）；全部测试 3448 个通过、2 个跳过；本轮新增和改动的测试文件共 85 个用例全过。第一次探针发现 `media_hub_security_consent_contract_test.dart` 会读页面源码确认授权弹窗的措辞，所以授权弹窗的文案留在页面里，没有搬进文案类。

## 下一步

- T-02 剩余：`lib/features/lyrics/` 下的 v2 文件名和类名（`lyric_proofread_v2_dialog.dart`、`run_proofread_v2_use_case.dart`、`proofread_v2_review_assembler.dart`、`proofread_v2_document_composer.dart`，以及 `LyricProofreadV2*`、`ProofreadV2*` 约 20 个类型）。牵涉的测试文件较多，适合单独一轮；持久化的 `'whisper-lyrics-v2'` 配置 id 不能改。
- 审计状态一节里标“部分”或“待核”的：C-03（识别设置还有约 590 行）、E-04（编辑器参数尚未对象化）、E-06（`app_theme.dart` 还有一处 `fontSize: 10`）、S-05（圆角字面量未核对）、A-04（语义标注未全量走查）。
- 在真机上确认：设置卡片的计数和跳转、返回后数字更新；桌面传输中心的加载、空状态和地址列表；手机上打开桌面传输页时的“连接电脑”。

## 已知风险

- 都没有在运行中的应用里看过，详见工作日志。
- 第十二轮之前自动配上的歌没有 `lyricAutoLink` 记录，设置里的数字和音乐库一样不包含它们。
- 计数会读一遍音乐库和本地资料；曲库很大时“已自动配对”这一行会比路径晚一点出现。
- 状态一节是按代码和注释核对的，不等于运行验证；标“已处理”的项仍可能在真机上有问题。

最后更新：2026-11-30 11:30（Asia/Taipei）
