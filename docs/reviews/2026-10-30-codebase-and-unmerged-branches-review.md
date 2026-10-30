# 全面代码审查与未合并分支处置报告

- 日期：2026-10-30
- 审查对象：`main` @ `bdb3a59`（Merge PR #250）全部代码 + 远端全部未合并分支
- 方法：全量拉取 278 个远端分支与 229 个 PR 的元数据，逐分支做祖先检测（`merge-base --is-ancestor`）、补丁等价检测（`git cherry`）、假设合并检测（`git merge-tree --write-tree`）、PR 状态/base/head 三方核对，并逐文件核对可疑分支的签名文件是否已在 main 中；对 main 本体做指标统计并精读高风险面（Media Hub 服务端、TLS、持久化、子进程管理、CI 配置）。
- 限制：审查沙箱无 Flutter/Dart SDK，未本地运行 `flutter analyze`/`flutter test`；可执行状态以 GitHub Actions 记录为准——main 在 HEAD 上的 **Flutter Quality Gate 为 success**（run 41069796464，2026-10-30 14:12 UTC）。

---

## 0. 结论先行

### 未合并代码的总账

| 项目 | 数量 | 说明 |
|---|---|---|
| Open PR | **0** | 没有等待审核的 PR，不存在「该不该 merge 某个 PR」的问题 |
| 远端分支（不含 main） | **277** | 真正意义上的「还没 merge 的代码」在这里 |
| 内容已经在 main 里，只是分支没删 | **236**（A 90 + B 18 + C-普通 128） | 直接删分支，零损失 |
| PR 已合但合并后又追加提交（C-追加） | 7 | 逐个核实后均为已落地/无关紧要（见 5.4），删 |
| PR 已关闭未合（D） | 10 个分支 / 11 个 PR | 全部有明确的取代者（见 5.3），关闭决定正确，删分支 |
| 从未提过 PR（E) | 24 | 22 个是被 `-final`/`-sync`/`-clean`/`-v2` 版取代的草稿或垃圾分支，删；**只有 2 条需要认真对待**（见下） |
| **可以直接 merge 的分支** | **0** | 无一例外都与现 main 冲突或已无净内容 |
| **建议「改造后合并」的分支** | **1** | `fix/supervise-high-quality-audio-preparation-20261028`（见 5.5） |
| **需按现架构重做的被弃功能** | **1** | `feat/auto-library-folder-sync`（文件夹自动同步，见 5.6） |
| **值得打捞的小功能想法** | **1** | proofreading 字符级 diff 高亮 widget，因栈式 PR 断链从未到达 main（见 5.6） |
| 最终账：可安全删除 | **275 / 277** | 剩余 1 个改造移植、1 个打 tag 留档后删除 |

### main 本体最重要的发现

1. **【P0·真实功能缺陷】** `http_media_hub_service.dart` 第 1127–1160 行有一段 Dart 类定义文本被误插入 PowerShell 原始字符串内部，导致 **Windows 上 Media Hub 的磁盘空间探针脚本语法损坏，所有传入上传都会被以 507 `storage_check_unavailable` 拒绝**。它能通过编译与测试（腐坏段在字符串里；测试全部注入假探针），由 PR #240 的 squash 提交 `b4faf76` 带入（见 3.1）。
2. **【P1】** 高质量转录的 FFmpeg 预处理仍在用裸 `Process.start` + 无限等待 `exitCode`，与 #211/#212/#214 已建立的子进程监督模式不一致——修复代码已经写好，就在那唯一值得抢救的未合并分支里（见 3.2、5.5）。
3. **【流程】** 277 个僵尸分支的根因是仓库未开启「合并自动删分支」且 merge/squash/rebase 三种合并方式混用，叠加「同一功能反复开 `-final/-sync/-v2…` 分支」的生成式工作习惯（有 5 组共 27 个分支指向完全相同的提交）。

代码本体质量在个人/AI 辅助项目里属中上：安全设计（TLS 指纹固定、上传多维限额、原子 JSON、进程监督）和测试密度（819 个用例、测试代码约 2.8 万行）是扎实的；主要债务集中在 UI 巨型文件、分层规则无机器校验、以及上述流程卫生问题。

---

## 1. 代码库现状快照（main @ bdb3a59）

| 指标 | 数值 |
|---|---|
| 仓库文件总数 | 747 |
| Dart 代码 | `lib` 234 个文件 / 67,841 行；`test` 146 个文件 / 28,070 行；`tool` 3,308 行 |
| 测试用例总数 | 819（`test(` + `testWidgets(`） |
| 最大文件 | `lyric_editor_screen.dart` **4,044 行 / 48 个 import**；`player_screen.dart` 3,098 行 |
| >1000 行的 lib 文件 | **14 个**；>500 行 40 个（占 lib 文件 17%） |
| main 提交 | 626 个，其中 `[skip ci]` 81 个（13%），最近 200 个里 docs/work-log 类 33 个 |
| PR 历史 | 共 229 个：MERGED 218、CLOSED 未合 11、**OPEN 0** |
| GitHub Actions workflow | 24 个，其中 22 个是按文件路径触发的「专项验证」，与主门禁重复跑子集 |
| 版本 | `pubspec.yaml` 仍为 `1.0.0+1`（从未正式发版）；仅有 2 个 ASR runtime 的 tag |
| 平台目录 | android/ios/macos/windows/linux/web 全齐；应用 ID 已由 #243 修掉模板值 |

### 各功能模块规模与测试分布

| feature | lib 行数 | 测试用例 | 备注 |
|---|---|---|---|
| player | 19,409 | 91 | 规模最大、巨型 UI 文件集中地（3,098 / 1,335 / 1,076 / 1,073 行四个 screen） |
| lyrics | 15,256 | 329 | domain 里 proofreading 纯 Dart 管线测试密度最高（277 例），是全库质量最好的区域 |
| transcription | 15,319 | 138 | 子进程/下载/运行时管理，与本机环境强耦合 |
| transfer | 10,483 | 56 | Media Hub 网络攻击面；有专门的安全契约测试，但真实探针（磁盘空间）无覆盖→ 放行了 P0 |
| project | 1,934 | 6 | 薄 |
| home | 1,620（单文件 dashboard） | 2 | #253 刚补了空态/重试测试 |
| import | 1,144 | 2 | 薄 |
| settings | 1,187 | 3 | 薄 |

这个分布与 open issue #223「测试投入与风险分布错位」的判断一致且至今基本未变：歌词 domain 过度覆盖、播放核心/媒体中心/home 明显偏少。

---

## 2. 做得好的地方（值得保留）

精读高风险面后的正面结论——这些不是模板夸奖，都有具体代码支撑：

- **Media Hub 安全模型是认真的**（`lib/features/transfer/data/services/http_media_hub_service.dart`、`media_hub_tls_identity_store.dart`、`http_media_hub_client_service.dart`）：
  - 只用 `HttpServer.bindSecure`，RSA 2048 自签证书；客户端两处 `badCertificateCallback` 都严格比对 SHA 指纹、**无条件拒绝未固定证书**，没有常见的 `=> true` 漏洞。
  - 只绑定私网/Tailscale CGNAT（100.64/10）/loopback 接口，明确不绑公网网卡。
  - Bearer token 为 122-bit 随机值 + 常量时间比较（#245）；URL 中已移除 token（#252）；无 CORS 通配、OPTIONS 直接 405（#246）。
  - 上传：2 GiB 上限、30 s 空闲/45 min 总超时、全局最多 2 并发且每 token 1 个、写盘前与每 64 MiB 磁盘空间复检、UUID `.part` 临时文件 + 独占 `.reserve` 标记文件原子保留目标名（#240/#248），文件名清洗防路径穿越。
  - UDP 发现用 HMAC-SHA256 + 每请求 nonce + 已见请求缓存防重放，原始 secret 不上网线；本地回放代理只绑 loopback 且剥离查询凭据。
- **JSON 持久化**（`lib/core/persistence/atomic_json_file.dart`）：写入前 schema 校验、flush、`.bak` 轮换、POSIX 原子 rename、Windows 删除-重命名窗口有启动恢复兜底，并暴露故障注入钩子 `onStage`，且有专门测试（`test/core/persistence/atomic_json_file_test.dart`）。
- **子进程治理**：`AsrProcessSupervisor` 已被 whisper/Qwen/分片转录采用（超时、终止、输出处理集中化，#211/#212/#214）；全部 `Process.*` 调用均 `runInShell: false`（含显式或默认），参数均为数组传参；FFmpeg/ASR 运行时下载有 SHA-256 固定与校验（#237，`ffmpeg_runtime_release.dart`）。
- **工程门禁**：Flutter 3.47.7 经 `.fvmrc` 固定、CI 用 `--enforce-lockfile` 且对 `pubspec.lock`/`analysis_options.yaml` 做 `git diff --exit-code`；本地 `scripts/quality_gate.sh` 与 CI 同构；依赖里 file_picker/flutter_soloud 的精确锁版都写明了原因。
- **整洁度基线**：全库 TODO/FIXME 仅 9 处、`print(` 0 处、`// ignore` 仅 2 处；未发现硬编码密钥；Android `usesCleartextTraffic=false`；`lib` 中明文 http 仅出现在系统代理 URL 构造处。
- **审计响应速度**：10-28 审计提出问题后，两天内修复了 CORS、常量时间比较、上传限额、原子保留、pub 锁、平台 ID、README/CONTRIBUTING 等 10+ 个 PR（#240–#253）。执行力不是问题，卫生习惯（关 issue、删分支）才是。

---

## 3. main 本体问题清单（按严重度）

### 3.1 【P0】Windows 磁盘探针脚本字符串腐坏 → Windows 上接收上传全灭

- 位置：`lib/features/transfer/data/services/http_media_hub_service.dart:1124-1163`（`_probeAvailableDiskSpaceBytes`）。
- 现状：PowerShell 原始字符串在 `if ($root -notmatch '^[A-Za-z]:\\` 后被插入 34 行 Dart 文本（`_BoundMediaHubServers` 残片、`MediaHubException`、`_ByteRange`、`_ParsedRange` 四个类的副本），然后在 `) { exit 3 }` 处勉强接回。该文件是**全库唯一**存在重复类名定义的文件（已全量扫描确认孤例）。
- 后果链：Windows 上 `powershell.exe -Command <该脚本>` 必然语法报错 → 探针返回 `null` → `_receiveIncomingAudio` 在首个磁盘检查就抛 `_IncomingUploadStorageCheckUnavailable` → **所有 POST /v1/incoming/audio 以 507 失败**。即「Windows 桌面做接收端」整条功能当前不可用；macOS/Linux 走 `df` 分支不受影响。
- 引入点：PR #240 的 squash 提交 `b4faf76`（`git log -L` 确认）。同题被关闭的 #241 分支里没有这段腐坏。
- 为何没被发现：(1) 腐坏段位于 `r'''...'''` 原始字符串内，分析器与编译器完全无感；(2) `test/features/transfer/http_media_hub_upload_test.dart` 默认注入返回 8 GiB 的假 `diskSpaceProbe`，真实探针在 CI（Linux）上永不执行，Windows 专项 workflow 只测原生构建不测此逻辑。
- 建议修复（一个新分支即可）：删去第 1127–1160 行并将正则补全为 `if ($root -notmatch '^[A-Za-z]:\\$') { exit 3 }`；同时把脚本抽为可测常量并增加内容契约测试（如断言包含 `GetPathRoot`/`AvailableFreeSpace` 且不包含 `class `），理想情况下再在 `windows-latest` 上加一个只调用真实探针的冒烟测试——这正是本该抓住它的测试层。

### 3.2 【P1】高质量转录的 FFmpeg 预处理未接入进程监督（可无限挂起）

- 位置：`lib/features/transcription/data/services/high_quality_transcription_service.dart:247` 附近：裸 `Process.start` 后 `await process.exitCode` 无超时；取消仅靠启动瞬间的标志检查与外部引用 kill；`stderr` 用 `join()` 无上限收集。
- 对照：同目录 whisper/Qwen/分片三条路径已由 #211/#212/#214 接入 `AsrProcessSupervisor`。此前「给子进程设界」系列的最后一环——这个共享音频预处理进程——的修复已经写好但从未提 PR，即 5.5 中的分支。当前 main 里半成品卡死 FFmpeg 会让双引擎转录任务永不结束、队列假死。

### 3.3 【P1】巨型 UI 文件与「上帝 Screen」（= issue #231，仍成立）

`lyric_editor_screen.dart` 4,044 行/48 import、`player_screen.dart` 3,098 行、`dashboard_screen.dart` 1,620 行为 home 的唯一文件；全库 14 个文件 >1,000 行。`home` 与 `import`、`settings` 甚至没有 domain/data 层（presentation-only），与 AGENTS.md 的三层组织只是「大体遵循」。这些 Screen 同时承载状态、编排与业务判断，是后续任何 UI 改动的主要风险与冲突源（分支 merge-tree 检测中绝大多数冲突也集中在这些文件与 work-log 上）。

### 3.4 【P2】分层规则靠自觉，已被多处突破（= issue #232，仍成立）

- domain 引入 `dart:io`：`player/domain/services/playback_lyrics_project_linker.dart`、`playback_lyrics_project_resolver.dart`。
- presentation 直接 import data 实现 7 处，其中跨 feature 2 处：`lyric_editor_screen.dart` → `transcription/data/services/forced_alignment_proofread_service.dart`；`settings/.../ai_transcription_settings_section.dart` → `transcription/data/.../local_asr_managed_storage_service.dart`。
- `lib/core/services/service_locator.dart`（312 行）位于 core 却 import 全部 feature 的 data 实现——作为组合根可以接受，但它在 core 层造成「core 反向依赖 features」，更合理的位置是 `lib/app/` 之类的装配层。
- 建议：加一个导入方向的契约测试（仓库已有 `test/ci_workflow_contract_test.dart` 这类「用测试守仓库不变量」的先例，照此扩展成本很低）。

### 3.5 【P2】静默吞异常规模化 + 无统一日志（= issue #233，仍成立）

全库 `catch (_)` 159 处。抽样看多数是带注释的 best-effort 清理（如删临时文件、关 sink），本身可辩护；但在**没有统一日志/诊断通道**的前提下，这些静默点会让用户端故障不可观测——P0 那类「探针失败被转成 null」的问题正是因此更难定位。另外 Media Hub 的 500 响应会把 `error.toString()` 回给已认证对端（低风险信息泄露），与「静默」是同一硬币的两面：该记的不记、不该露的露了。

### 3.6 【P2】静态检查强度偏弱

- `analysis_options.yaml` 仍是 `flutter_lints` 默认集，无 `strict-casts/strict-inference/strict-raw-types`；门禁跑 `flutter analyze --no-fatal-infos`，info 级永不阻断。
- 格式检查只覆盖变更文件（issue #230 的债务被制度性保留）；合入像 3.1 那种「能过分析器」的腐坏时，这类门禁给不了额外保护——值得至少对 `lib/**/data/services/` 这类高风险目录补契约测试。

### 3.7 【P2】CI/workflow 蔓延

24 个 workflow 中 22 个是历史 PR 遗留的「专项验证」，多数只是按路径过滤后重复主门禁的子集（如只改 `lib/main.dart` 才触发的 widget-root-validation、`queue-inline-environment-repair-validation`），维护面与漂移风险持续增加；仅 5 个声明了 `permissions:`（其余走仓库默认 token 权限）。#238 名义上「统一」过 workflow，但体量未降。建议砍到 3–4 个：主门禁、原生构建（Win/mac）、ASR runtime 发布、图标重生成。

### 3.8 【P2】流程卫生（观察项，成本真实存在）

- work-log harness：136 条日志 + 工具 + 门禁强制，带来极佳可追溯性，但也让约 1/6 的近期提交是纯日志刷新、多个分支的 tip 提交与代码无关。可以保留，但应意识到它在放大每个 PR 的冲突面（`docs/handoff.md`/`docs/work_log.md` 是所有分支共同的重灾区）。
- `[skip ci]` 占 main 历史 13%（81/626），早期大量功能提交无 CI 背书。
- 10-30 当天 main 曾短暂为红：#251 的合并提交 `6b66a80` 上 Quality Gate 失败（run 41068749896，失败于 quality gate 步），约 7 分钟后被 #250 的合并「盖过去」才转绿。说明 PR 检查绿 ≠ 合并后状态绿，值得为 main 设置必填状态检查 + 要求分支先与 main 同步（或 merge queue）。（注：分支保护详情 API 返回 403 无法核实其当前配置，本条为基于运行记录的推断。）
- 文档漂移（issue #229 部分仍成立）：`docs/architecture_player.md` 仍写着不存在的 shelf/Hive 架构；根目录 `opencode.jsonc` 引用的 `docs/architecture.md`、`docs/dev-standards.md` 均不存在；`scripts/quality_gate.sh` 注释提到不存在的 `packages/desktop_multi_window`。README/CONTRIBUTING 已由 #250/#251 修复。
- `packages/just_audio_media_kit` 是 575 行的 vendored 分叉且被分析器排除，无上游同步记录（issue #236）——至少补一份 FORK.md 记录基线版本与本地改动点（pubspec 里只说明了一处 LRC 行为调整）。

### 与 10-28 审计 issue 的对账（14 个 open）

| Issue | 状态核实（2026-10-30） | 建议 |
|---|---|---|
| #215 README 模板 | #250 已重写 README 并补元数据 | **关闭** |
| #220 pubspec.lock 不可复现 | #244 + #249 已强制 `--enforce-lockfile` 与 SDK 固定 | **关闭** |
| #227 CORS `*` + 非常量时间比较 | #246 已摘除 CORS、#245 已常量时间化 | **关闭** |
| #221 JSON 删除窗口/故障注入 | #209/#242 后 POSIX 窗口已消除、Windows 由恢复兜底、已有故障注入钩子与测试；剩余是「跨平台真实断电类注入」 | 缩小范围后保留或降级 |
| #223 测试错位/#228 依赖大版本/#229 文档漂移/#230 格式债/#231 巨型文件/#232 分层/#233 无日志/#235 状态管理混用/#236 vendored 分叉 | 逐一复核**均仍成立**（程度见 3.3–3.8；状态管理实测：setState 38 文件、StreamController 18、ValueNotifier 2、无第三方状态/DI 框架） | 保留 |
| #226 KTV 延迟/音质无设备数据 | 无法从仓库证伪 | 保留 |

---

## 4. 未合并代码是怎么判定的（方法与总量）

远端现有 278 个分支（含 main），全部 tip 都在 2026-10-02 至 10-30 之间（这个仓库 4 月建仓，大规模开发集中在 10 月这一个爆发月）。判定逻辑：

| 类 | 判定标准 | 数量 | 结论 |
|---|---|---|---|
| A 已合·祖先型 | 分支 tip 是 main 的祖先（merge-commit 式合并后未删分支） | 90 | 删 |
| B 已合·补丁等价型 | 非祖先，但 `git cherry` 显示每个提交的 patch 都已在 main（squash/rebase 合并后未删分支） | 18 | 删 |
| C PR 已合并 | GitHub 记录 PR=MERGED；tip 与 PR head 一致者 128 个直接判已合；合并后又追加提交者 7 个单独核实（5.4） | 135 | 删（7 个经核实同理） |
| D PR 已关未合 | GitHub 记录 PR=CLOSED 且未 merged；每个都有同题取代 PR 已合入（5.3） | 10 个分支（11 个 PR，#77 的分支另经 #75 合入，归 A） | 删，关闭决定正确 |
| E 从未提 PR | 无任何 PR 记录且存在 main 没有的补丁 | 24 | 逐条裁决见 5.2 |

对全部 C/D/E 类另做了 `git merge-tree` 假设合并：只有 9 个分支能无冲突合并（其中 7 个的「新增内容」只是一个应删的记号文件），其余全部冲突——这量化证明了「可直接 merge 的未合并分支 = 0」。

补充形态证据（这些分支垃圾是工作方式的副产品，不是 277 份独立工作）：
- 5 组、27 个分支指向**完全相同**的提交：`feat/ktv-lyric-stage-*` 9 个别名、`feat/relink-missing-local-media-final2..8` 7 个、`feat/mobile-remote-library-catalog-downloads(-v2..v6)` 6 个、`tmp-ignore-this` ×3、`temp-never-use` 与已合分支同点。
- 仓库设置 `delete_branch_on_merge=false`，且 merge/squash/rebase 三种合并方式全部开启并实际在混用（main 上有 49 个 merge-commit 式 PR、114 个 squash 式主题，其余为 rebase/自定义）——僵尸分支是制度必然结果。

---

## 5. 逐项裁决与具体原因

### 5.1 可以直接 merge 的：无

277 个分支里没有任何一个能干净并入当前 main 且带来净价值。唯一「无冲突且带真实代码」的 `feat/ktv-lyric-stage-real4` 会新增已被弃用的 `ktv_lyric_stage.dart`（main 里是其后继者 `fullscreen_ktv_lyric_stage.dart`，见 5.3 #78），合并即引入重复实现。

### 5.2 E 类（从未提 PR 的 24 个）逐条裁决

| 分支 | 裁决 | 具体原因（证据） |
|---|---|---|
| `fix/supervise-high-quality-audio-preparation-20261028` | **改造后合并**（唯一） | 内容与 main 现状逐行核对确认是真缺口（见 5.5） |
| `feat/auto-library-folder-sync` | 不合并；打 tag 留档后删 | main 中无任何 watched-root 概念，功能确实未落地；但落后 main 359 个提交且合并冲突，PRD/路线图亦无此需求。想做需按现架构重写（见 5.6） |
| `feat/high-quality-asr-mode` | close（删） | 初版草稿；功能经同题 `-final` 分支以 PR #11 合入 |
| `feat/high-quality-asr-mode-sync` | close（删） | tip 与 `-final` 仅差约 3 分钟，merge-tree 净变更与 `-final` 完全相同（+1,276 行/12 文件），是重复快照 |
| `feat/asr-hardware-profiles` | close（删） | 经 `-final` 以 PR #13 合入 |
| `feat/global-playback-shell-20261003` | close（删） | 经 `-sync` 版以 PR #14 合入（祖先型） |
| `feat/managed-asr-runtime` | close（删） | 经 `-final` 以 PR #16 合入 |
| `feat/artist-album-library-20261004` | close（删） | 其数据层设计（`local_media_catalog*`）未被采用，但「按艺人/专辑浏览」功能已由 `ui/local-artist-album-browser`（PR #31）以另一实现落地，`local_artist_album_browser_screen.dart` 在 main |
| `feat/persistent-playback-session-20261004` | close（删） | 叠在 #49/#50/#51 已弃栈上（含 11 个从未入 main 的旧设计文件）；播放会话持久化已由 PR #65 以 `file_playback_session_store.dart` 等不同设计落地 |
| `feat/mobile-remote-catalog-downloads-final` | close（删） | 与已合的 `-ready`（PR #60）同晚相隔约 2 分钟的 1 提交重复快照 |
| `feat/relink-missing-local-media-final2`、`feat/relink-missing-local-media-final3`、`feat/relink-missing-local-media-final4`、`feat/relink-missing-local-media-final5`、`feat/relink-missing-local-media-final6`、`feat/relink-missing-local-media-final7`、`feat/relink-missing-local-media-final8`（7 个） | close（删） | 7 个分支同指一个提交，唯一「新增内容」是垃圾文件 `__scratch_marker_should_delete`；relink 功能已由 PR #71/#72 合入 |
| `feat/fullscreen-ktv-interactions` | close（删） | 早期迭代；同批内容经 `feat/ktv-interaction-surface`（PR #75）/`feat/ktv-immersive-route-v2`（PR #79）落地，main 有 `fullscreen_ktv_lyric_stage.dart` |
| `feat/ktv-immersive-route` | close（删） | 被 `-v2`（PR #79）取代 |
| `fix/surface-weak-lyric-matches-20261022` | close（删）；想法可打捞 | 核心修复经 `-core` 版 PR #136 合入；其字符级 diff widget 的遭遇见 5.6 |
| `feat/lyric-proofreading-t5-retiming-plan-20261022` | close（删） | 仅 1 个测试提交（152 行），已被 `t5-retiming-v2`（PR #146）的演进版覆盖，目标测试文件在 main 中存在 |
| `ci/flutter-quality-gate-20261023` | close（删） | 同日被 `ci/universal-flutter-quality-gate`（PR #147）、其后 #238 的统一门禁取代，主门禁正在 main 上运行 |
| `test/proofread-pipeline-shared-invariants-20261024` | close（删） | 与已合的 `test/proofread-shared-invariants`（PR #164）同日相隔约 5 分钟的重复实现；等价 helper `shared_proofread_pipeline_invariants.dart` 已在 main |
| `feat/proofread-v2-ui-20261024` | close（删） | 非干净草稿，被同日 `-clean` 版（PR #165）取代合入 |

### 5.3 D 类（PR 已关未合）逐条裁决：关闭决定全部正确，删分支即可

| PR / 分支 | 裁决 | 具体原因（证据） |
|---|---|---|
| #49 `feat/system-media-session-20261004`、#50 `feat/mobile-background-playback-20261004`、#52 `feat/mobile-background-media-controls-20261005` | 删 | 同题三连提案，最终由 `feat/mobile-background-playback-20261005`（PR #53）合入；main 有 `mobile_system_media_session.dart`、`system_media_audio_handler.dart`、pubspec 有 audio_service。（#50 的分支还成了 #51 的栈基，见 5.4 注） |
| #78 `feat/ktv-lyric-stage-real4` | 删 | main 已有后继实现 `fullscreen_ktv_lyric_stage.dart`（提交 `97be220` 引入）+ 对应测试；合入 real4 只会多一份平行实现 |
| #92 `feat/ktv-take-history` | 删 | 约 1 小时后被 `feat/ktv-take-history-index`（PR #93）取代合入；main 有 `ktv_take_history_store.dart` |
| #167 `fix/qwen-asr-download-recovery-20261024` | 删 | 被 `-ci` 版（PR #168）取代；其标志性代码（ranged GET 下载探针）在 main 的 `asr_download_connection_checker.dart` 中 |
| #174 `fix/asr-failure-progress-diagnostics-20261025` | 删 | 被 `-rebased` 版（PR #178）取代；`asr_install_error_card.dart`（可复制诊断卡）在 main |
| #175 `fix/qwen-attention-contiguous-candle-20261025` | 删 | 被 PR #176 取代；补丁以更名后的 `tool/patches/qwen3-asr-eager-attention-contiguous.patch` 在 main |
| #241 `fix/media-hub-upload-resource-limits-20261029` | 删（不必复活） | 创建约 4 分钟即关闭，改走 #240 并已合入，后续 #248 又叠加了原子保留。注脚：被选中的 #240 反而带入了 3.1 的字符串腐坏，而 #241 的版本没有——正确处理是就地修 P0，而不是复活本分支 |
| #247 `security/atomic-upload-reservations-20261029` | 删 | base 错叠在 #240 的分支上（栈式 PR），7 分钟后以基于 main 的 `-main` 版 PR #248 重提并合入（祖先型） |

### 5.4 C 类需要单独说明的 7 个（PR 合并后又被追加提交）+ 栈式 PR 审计

| 分支 | 追加部分是什么 | 裁决与原因 |
|---|---|---|
| `feat/forced-alignment-quality-evaluator-20261026`（#190） | PR head=`9d826df`（功能本体，已合）；之后只多了 1 个纯格式化提交 `c8efe5e` | 删。格式化价值≈0，随后该文件历次改动都会顺带格式化 |
| `feat/lyric-proofreading-t2-token-alignment-20261022`（#133） | tip 是叠进来的栈式 PR #134（T2b anchor chaining）的 squash 提交 | 删。T2b 另经 `-main` 移植分支以 PR #139 进入 main，`reference_token_aligner.dart` 中可查 |
| `feat/lyric-proofreading-t5-asr-consensus-20261022`（#141） | tip 是栈式 PR #142（repetition cleanup） | 删。该功能经 `fix/port-t5-repetition-to-main` 以 PR #144 进入 main，`asr_repetition_analyzer.dart` 在库 |
| `fix/surface-weak-lyric-matches-core-20261022`（#136） | tip 是栈式 PR #137（字符级 diff widget） | 删分支；但这是**唯一真正丢了的功能碎片**，见 5.6 |
| `fix/validate-asr-retiming-evidence-20261023`（#161） | 分支被复用承载了 #162 的修复提交 + 一串 work-log 提交 | 删。#162 本体已合入 |
| `fix/incomplete-token-alignment-coverage-20261023`（#162） | 合并后追加的全是 work-log 文档刷新（8+ 个 docs 提交） | 删。无代码价值 |
| `feat/persistent-batch-transcription-20261004`（#19） | 合并后追加 2 个「project detail UI 微调」提交（均 `[skip ci]`，10-04） | 删。项目详情页此后已被 PR #20 及响应式系列整体重写，这批微调无移植意义 |

**栈式 PR（base 不是 main）专项审计**——全仓共 9 个，这是最容易「假合并、真丢失」的形态，逐一追了签名文件的最终归宿：

| 栈式 PR | 合入的 base 分支 | 内容最终是否到达 main |
|---|---|---|
| #51 `feat/unified-remote-streaming-session` | #50 的分支（已关闭未合） | 其 4 个专有文件（`unified_remote_media_library_screen.dart` 等）**不在 main**；但远程库/播放的功能已由其后的 #59/#60/#65/#66 一线以不同设计完整取代。判定：早期设计被弃，分支可删 |
| #132 reference-sanitizer | t1-tokenizer 分支 | 是，`reference_text_sanitizer.dart` 在 main |
| #134 T2b anchor-chain | t2-token-alignment 分支 | 是，经 #139 移植 |
| #137 字符级 ASR diff | surface-weak-core 分支（其 PR #136 已先合入 main） | **否**——`alternative_candidate_diff.dart` 从未出现在 main 的任何历史中（见 5.6） |
| #142 T5 repetition | t5-asr-consensus 分支 | 是，经 #144 移植 |
| #247（已关） | #240 的分支 | 是，改以 #248 基于 main 合入 |

### 5.5 唯一建议「改造后合并」的分支

**`fix/supervise-high-quality-audio-preparation-20261028`**（E 类，2026-10-28，落后 main 59 个提交）

为什么值得救：
- 它是 #211/#212/#214「子进程生命周期设界」系列的收尾一环：把 `high_quality_transcription_service` 中生成双引擎共享 16 kHz 音频的 FFmpeg 预处理接入 `AsrProcessSupervisor`（超时/终止/统一错误归类），并把 `resumable_chunked_transcription_service` 里的重复监督代码收敛为共享实现（分支 diff +397/−561，含 `high_quality_transcription_service_test` 的实质补充）。
- 已和现 main 逐点核对：main 的同一位置仍是裸 `Process.start` + 无超时等待（见 3.2），功能缺口真实存在，而非已被别的 PR 覆盖。

为什么不能直接 merge、改造清单（建议基于当前 main 新开分支**移植语义**，而不是 rebase 老分支硬怼）：
1. 分支基点在 #214 合入之前，其 diff 会**删除** #214 的 work-log 条目 `docs/log/entries/2026-10-28-1945-supervise-resumable-chunk-processes.md` ——这违反仓库「日志条目不可变」硬规则，移植时必须剔除一切 docs/log 的删除。
2. #214 合入后 `resumable_chunked_transcription_service` 自身已有监督逻辑，分支里对该文件的「收敛重构」需要与现状人工对账，避免回退 #214 的行为与测试（分支删了约 288 行该服务的测试，要逐例确认是真重复还是覆盖丢失）。
3. 分支含两个主题完全相同的重复提交（`b6ed668`、`b4de511`，疑似 cherry-pick 残留），且主题误写 `(#215)`——#215 是 README 审计 **issue** 而非本 PR，提交时须修正。
4. 按 AGENTS.md 补 work-log 条目并跑全量 `scripts/quality_gate.sh` 后，以新 PR 形式合入；旧分支在移植完成后删除。

### 5.6 不建议合并、但值得单独记录的两项「未落地」

1. **文件夹自动同步**（`feat/auto-library-folder-sync`，8 提交/+459 行，10-08）：watched-root 持久化、启动/恢复时节流重扫、文件夹管理弹窗一整套，main 中无任何等价物。但它基于 10-08 的媒体库结构、与现 `local_library_explorer_screen`/`audio_library_import_service` 的形态已脱节，且 PRD 与工程风险路线图中都没有这个需求。建议：确认弃需则直接删；若仍想做，打 `archive/auto-library-folder-sync-20261008` tag 留作参考实现后删分支，并另开 issue 按现架构重新设计——不要试图 rebase 这个分支。
2. **Proofreading 候选歌词字符级 diff 高亮**（`alternative_candidate_diff.dart` + 测试，约 293 行，散落在 E 类 `fix/surface-weak-lyric-matches`、C 类 `fix/surface-weak-lyric-matches-core`、`feat/show-asr-lyric-diffs` 三个分支上）：栈式 PR #137 把它合进了一条已经合入 main 的分支，导致它从未真正到达 main；现 `lyric_proofread_v2_dialog.dart` 中也没有字符级 diff 渲染（已查证无 diff/RichText 相关实现）。价值判断：对「看清 ASR 候选差在哪」是真实 UX 提升，但必须移植进 v2 对话框的现行结构。优先级低，可开 `good-first-port` 类 issue 记录后把三条分支一并删除。

### 5.7 其余 C-普通（128）、A（90）、B（18）类

无逐条说明的必要：每一类的判定依据都是机器可验的（祖先关系 / patch 等价 / GitHub MERGED 且 tip=PR head），完整名单见附录 A。删除它们不丢失任何代码——GitHub 上 PR 页面与提交对象仍可追溯（squash 合并的原始提交可由 PR 页找回）。

---

## 6. 建议执行清单（按顺序）

1. **修 P0**（3.1）：新分支修复 PowerShell 探针字符串 + 给脚本内容加契约测试（可选：windows-latest 探针冒烟）。
2. **移植监督修复**（5.5）：按清单 4 步走，合入后删源分支。
3. **仓库设置**：开启 *Automatically delete head branches*；合并方式收敛为一种（推荐只留 squash，与现行多数实践一致）；给 main 设置必填状态检查（Flutter Quality Gate）并要求 up-to-date，避免再现「红 main 窗口」。禁止再开栈式 PR（base 必须是 main），当时的 9 个栈式 PR 直接造成 1 次真丢失（#137）。
4. **批量删分支**：先给 `feat/auto-library-folder-sync` 打 archive tag（可选），然后按附录 A + 5.2/5.3/5.4 名单分批 `git push origin --delete <branch>…`。删完后远端应只剩 main 与在研分支。
5. **关掉已修复的 open issue**：#215、#220、#227 直接关闭并注明修复 PR；#221 缩小范围。
6. **立项跟踪**（可选）：为 5.6 两项各开一个 issue，把「删分支」和「丢想法」解耦。
7. 中期：拆 `lyric_editor_screen`/`player_screen` 两个上帝文件（哪怕只做按职责抽文件、不动逻辑也显著降冲突）；补分层导入契约测试；workflow 从 24 砍到 ~4 个并统一声明 `permissions`。

---

## 附录 A：可直接删除的分支全名单（内容已进入 main）

> 删除依据见第 4 节。A 类 = 已是 main 的祖先提交；B 类 = 每个提交的 patch 都已等价存在于 main（squash/rebase 合并的典型形态）；C-普通类 = GitHub 记录 PR 已 MERGED 且合并后分支 tip 未再变动。

### A 类（90 个，祖先已合入）

- `build/enforce-pinned-flutter-sdk-locally-20261029`
- `chore/worklog-index-local-context-20261019`
- `docs/align-architecture-and-agent-instructions-20261029`
- `docs/contribution-and-github-templates-20261029`
- `docs/readme-contributing-and-project-metadata-20261029`
- `feat/asr-end-to-end-smoke`
- `feat/asr-runtime-partial-release`
- `feat/asr-runtime-setup-wizard`
- `feat/cross-device-batch-download-20261004`
- `feat/cross-device-batch-upload-20261004`
- `feat/desktop-transcription-settings`
- `feat/embedded-audio-metadata-20261004`
- `feat/global-playback-shell-sync-20261003`
- `feat/guided-smart-review-confirmation-20261021`
- `feat/ktv-foundation-stack`
- `feat/ktv-immersive-route-v2`
- `feat/ktv-interaction-surface`
- `feat/ktv-lyric-stage`
- `feat/ktv-lyric-stage-code`
- `feat/ktv-lyric-stage-final`
- `feat/ktv-lyric-stage-final2`
- `feat/ktv-lyric-stage-impl`
- `feat/ktv-lyric-stage-real`
- `feat/ktv-lyric-stage-real2`
- `feat/ktv-lyric-stage-real3`
- `feat/ktv-lyric-stage-v2`
- `feat/ktv-lyric-stage-work`
- `feat/library-smart-views-search-20261004`
- `feat/local-media-library-20261004`
- `feat/local-media-metadata-lyrics-import-20261004`
- `feat/local-playlists-favorites-20261004`
- `feat/lyric-proofreading-t1-tokenizer-20261022`
- `feat/managed-asr-runtime-final`
- `feat/managed-qwen-model-download-20261004`
- `feat/media-hub-stable-identity-discovery`
- `feat/mobile-artwork-swipe-navigation-20261005`
- `feat/mobile-background-playback-20261005`
- `feat/mobile-remote-library-catalog-downloads`
- `feat/mobile-remote-library-catalog-downloads-v2`
- `feat/mobile-remote-library-catalog-downloads-v3`
- `feat/mobile-remote-library-catalog-downloads-v4`
- `feat/mobile-remote-library-catalog-downloads-v5`
- `feat/mobile-remote-library-catalog-downloads-v6`
- `feat/now-playing-linked-lyrics`
- `feat/persistent-media-transfer-queue-20261004`
- `feat/persistent-play-history-20261004`
- `feat/playback-modes-20261004`
- `feat/playback-queue-management-20261004`
- `feat/player-screen-immersive-ktv-entry`
- `feat/relink-missing-local-media`
- `feat/relink-missing-local-media-final`
- `feat/relink-missing-local-media-review`
- `feat/relink-missing-local-media-ui`
- `feat/resumable-chunked-transcription-20261004`
- `feat/runtime-integrity-validation`
- `feat/save-playback-queue-to-playlist`
- `feat/smart-lyric-review-queue-20261021`
- `feat/smart-review-inline-audition-20261021`
- `feat/transcription-readiness-gate`
- `fix/atomic-json-platform-replacement-20261029`
- `fix/enforce-reproducible-pub-lock-20261029`
- `fix/macos-elysium-player-icon`
- `fix/mobile-root-widget-test-isolation`
- `fix/platform-app-identifiers-20261029`
- `fix/player-overlay-batch-import-20261003`
- `fix/project-detail-refresh-after-lyrics`
- `fix/reference-alignment-auto-repair-diff-20261021`
- `fix/widget-test-ios-cli-20261005`
- `fix/windows-asr-runtime-first-release`
- `fix/windows-mp3-media-kit-backend`
- `fix/windows-rc2176-icon`
- `refactor/responsive-dashboard-20261004`
- `refactor/responsive-layout-system-20261004`
- `refactor/responsive-library-catalog-20261004`
- `refactor/responsive-now-playing-20261004`
- `security/atomic-upload-reservations-main-20261029`
- `security/constant-time-media-hub-tokens-20261029`
- `security/media-hub-cors-origin-policy-20261029`
- `security/remove-mediahub-token-from-artwork-urls-20261029`
- `temp-never-use`
- `test/dashboard-empty-and-retry-states-20261029`
- `tmp-ignore-this`
- `tmp-ignore-this-2`
- `tmp-ignore-this-3`
- `ui/home-media-center-20261004`
- `ui/local-artist-album-browser-20261004`
- `ui/local-player-workspace-20261004`
- `ui/lyrics-review-workspace-20261004`
- `ui/player-ktv-workspace-20261004`
- `ui/project-detail-workspace-20261004`

### B 类（18 个，patch 等价已合入）

- `ci/scope-asr-runtime-build-triggers-20261025`
- `cleanup/remove-legacy-library-screens-20261004`
- `docs/fix-persistence-worklog-squash-subject-20261028`
- `feat/qwen-source-preflight-20261024`
- `fix/ios-dev-flutter-device-gate-20261005`
- `fix/lyric-proofreading-adlib-validation-20261023`
- `fix/qwen-source-metadata-mismatch-20261024`
- `fix/source-aware-desktop-player-bar`
- `fix/windows-cmake-elysium-target-cache`
- `refactor/responsive-local-collections-20261004`
- `refactor/responsive-lyric-editor-20261004`
- `refactor/responsive-lyric-import-dialog-20261004`
- `refactor/responsive-media-metadata-dialog-20261004`
- `refactor/responsive-project-detail-20261004`
- `refactor/responsive-project-player-ktv-20261004`
- `refactor/responsive-residual-main-flows-20261004`
- `test/proofread-v2-t9-regression-20261025`
- `test/qwen-download-behavior-20261024`

### C-普通类（128 个，PR 已合并且 tip 未变）

- `ci/unify-flutter-workflows-20261028`（PR #238）
- `ci/universal-flutter-quality-gate-20261023`（PR #147）
- `docs/engineering-risks-roadmap-20261028`（PR #206）
- `docs/lyric-proofreading-v2-contracts-20261022`（PR #130）
- `docs/record-universal-ci-gate-20261023`（PR #149,148）
- `docs/second-review-commercial-readiness-20261028`（PR #207）
- `feat/asr-eval-provenance-20261027`（PR #199）
- `feat/asr-eval-strict-provenance-20261027`（PR #200）
- `feat/asr-first-proofread-pipeline-20261023`（PR #154）
- `feat/asr-first-secondary-transcript-input-20261025`（PR #179）
- `feat/asr-hardware-profiles-final`（PR #13）
- `feat/asr-install-experience`（PR #112）
- `feat/asr-managed-storage-location`（PR #117）
- `feat/asr-preprocessing-ab-evaluator-20261028`（PR #205）
- `feat/asr-quality-metrics-and-recall-20261027`（PR #197）
- `feat/asr-runtime-health`（PR #114）
- `feat/asr-storage-preflight`（PR #113）
- `feat/asr-transcript-evaluator-20261027`（PR #198）
- `feat/desktop-media-sharing-ui`（PR #5）
- `feat/desktop-player-ui-refresh-20261002`（PR #12）
- `feat/editor-reference-proofread-review-20261023`（PR #158）
- `feat/forced-align-proofread-service-20261025`（PR #185）
- `feat/forced-align-recovery-diagnostics-20261026`（PR #189）
- `feat/forced-align-token-audition-20261026`（PR #186）
- `feat/forced-aligner-http-adapter-contract-20261025`（PR #180）
- `feat/forced-alignment-local-capture-20261026`（PR #191）
- `feat/forced-alignment-proofread-evidence-20261025`（PR #182）
- `feat/high-quality-asr-mode-final`（PR #11）
- `feat/ktv-auto-recover-interrupted-takes`（PR #96）
- `feat/ktv-entry-backing-mode`（PR #86）
- `feat/ktv-history-resolved-storage-ui`（PR #97）
- `feat/ktv-input-device-persistence`（PR #91）
- `feat/ktv-input-device-picker-ui`（PR #90）
- `feat/ktv-input-device-selection`（PR #89）
- `feat/ktv-microphone-monitoring`（PR #87）
- `feat/ktv-recording-export`（PR #88）
- `feat/ktv-take-history-index`（PR #93）
- `feat/ktv-take-library-metadata`（PR #99）
- `feat/ktv-take-playback-controls`（PR #100）
- `feat/local-whisper-transcription`（PR #8）
- `feat/lyric-proofreading-t1-reference-sanitizer-20261022`（PR #132）
- `feat/lyric-proofreading-t2-anchor-chain-20261022`（PR #134）
- `feat/lyric-proofreading-t2b-anchor-chain-main-20261022`（PR #139）
- `feat/lyric-proofreading-t3-strategy-selector-20261022`（PR #135）
- `feat/lyric-proofreading-t4-reference-first-20261022`（PR #140）
- `feat/lyric-proofreading-t5-hallucination-20261022`（PR #143）
- `feat/lyric-proofreading-t5-reference-suggestions-20261022`（PR #145）
- `feat/lyric-proofreading-t5-repetition-20261022`（PR #142）
- `feat/lyric-proofreading-t5-retiming-v2-20261022`（PR #146）
- `feat/lyric-proofreading-t6-result-contract-20261023`（PR #150）
- `feat/lyric-proofreading-t7-result-invariants-20261023`（PR #151）
- `feat/lyric-row-audition-time-markers-20261022`（PR #138）
- `feat/lyric-timeline-edit-export`（PR #82）
- `feat/media-hub-artwork-persistent-downloads`（PR #61）
- `feat/media-hub-client`（PR #3）
- `feat/media-hub-foundation`（PR #1）
- `feat/mobile-remote-catalog-downloads-ready`（PR #60）
- `feat/mobile-remote-library-mini-player`（PR #59）
- `feat/mobile-remote-library-ui`（PR #6）
- `feat/persist-playback-session`（PR #65）
- `feat/player-auto-scroll-lyrics`（PR #83）
- `feat/proofread-secondary-asr-timing-evidence-20261023`（PR #159）
- `feat/proofread-v2-ui-clean-20261024`（PR #165）
- `feat/queue-inline-environment-repair`（PR #118）
- `feat/qwen-forced-align-http-endpoint-20261025`（PR #183）
- `feat/qwen-model-integrity`（PR #111）
- `feat/qwen-modelscope-download-fallback-20261024`（PR #169）
- `feat/rebind-restored-remote-playback`（PR #66）
- `feat/reference-review-apply-undo-20261023`（PR #156）
- `feat/reference-review-retiming-bundle-20261023`（PR #155）
- `feat/remote-artwork-now-playing-system-media`（PR #62）
- `feat/remote-audio-playback`（PR #4）
- `feat/remote-pairing-download-lyrics`（PR #7）
- `feat/shared-normalized-asr-input-20261027`（PR #204）
- `feat/show-asr-lyric-diffs-20261022`（PR #137）
- `feat/strict-forced-alignment-provenance-20261027`（PR #201）
- `feat/tailscale-remote-media`（PR #2）
- `feat/transcription-execution-failure-kinds`（PR #116）
- `feat/transcription-queue-protective-pause`（PR #115）
- `feat/unified-remote-streaming-session-20261004`（PR #51）
- `fix/asr-failure-progress-diagnostics-rebased-20261025`（PR #178）
- `fix/asr-fusion-recall-confidence-20261026`（PR #195）
- `fix/asr-model-provenance-20261027`（PR #202）
- `fix/asr-preflight-required-models-20261024`（PR #172）
- `fix/asr-whisper-baseline-fallback`（PR #81）
- `fix/elysium-player-branding-icons`（PR #57）
- `fix/flutter-soloud-meta-conflict`（PR #101）
- `fix/forced-alignment-http-deadlines-20261028`（PR #213）
- `fix/hide-player-bar-on-now-playing`（PR #64）
- `fix/ios-audio-service-build`（PR #10）
- `fix/json-persistence-recovery-20261028`（PR #209）
- `fix/ktv-recording-storage-contract`（PR #98）
- `fix/ktv-take-delete-path-safety`（PR #94）
- `fix/ktv-take-operation-locks`（PR #119）
- `fix/ktv-wav-interrupted-recovery`（PR #95）
- `fix/latest-player-test-regressions-20261008`（PR #74）
- `fix/lrc-export-effective-timestamps`（PR #85）
- `fix/macos-asr-storage-resume`（PR #122）
- `fix/macos-audio-picker-20261002`（PR #9）
- `fix/macos-network-client-entitlement`（PR #121）
- `fix/macos-release-network-server-entitlement-20261028`（PR #208）
- `fix/macos-soloud-no-cmake`（PR #120）
- `fix/media-kit-audio-osc-property-log-20261026`（PR #193）
- `fix/mobile-player-stability-and-downloads`（PR #58）
- `fix/mpv-disk-cache-warning-20261026`（PR #194）
- `fix/multiscript-align-normalization-20261026`（PR #188）
- `fix/pin-verify-ffmpeg-20261028`（PR #237）
- `fix/player-refresh-lyrics-after-edit`（PR #84）
- `fix/port-t5-repetition-to-main-20261022`（PR #144）
- `fix/proofread-preserve-unrelated-timeline-issues-20261023`（PR #157）
- `fix/qwen-align-route-patch-20261025`（PR #184）
- `fix/qwen-asr-download-recovery-ci-20261024`（PR #168）
- `fix/qwen-cuda-eager-attention-contiguous-20261025`（PR #176）
- `fix/qwen-model-download-auto-resume`（PR #123）
- `fix/qwen-process-lifetimes-20261028`（PR #212）
- `fix/reject-invalid-asr-confidence-20261023`（PR #160）
- `fix/route-observer-build-notification-20261026`（PR #192）
- `fix/shared-asr-audio-normalization-20261027`（PR #203）
- `fix/supervise-resumable-chunk-processes-20261028`（PR #214）
- `fix/unknown-forced-align-confidence-20261026`（PR #187）
- `fix/v2-lyric-audition-feedback-20261026`（PR #196）
- `fix/whisper-cli-process-timeouts-20261028`（PR #211）
- `fix/windows-plugin-warning-noise`（PR #102）
- `security/explicit-media-hub-consent-20261029`（PR #239）
- `security/media-hub-upload-guardrails-20261029`（PR #240）
- `test/proofread-shared-invariants-20261024`（PR #164）
- `test/proofreading-reference-invariants-20261023`（PR #153）
- `test/structural-reference-alignment-cases-20261024`（PR #163）
