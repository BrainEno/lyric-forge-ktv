# LyricForge KTV — 总体 UI/UX 审计报告（A. 交付物）

审计日期：2026-11-18 · 基线：`main@80b04a3` · 分支：`arena/f1dee18e-lyric-forge-ktv`
**证据等级：静态代码审计（环境无法运行 Flutter，全部结论以文件+行号为据；运行验证、截图、多尺寸实测未完成，见 `environment-diagnostic.md`）**

---

## 1. 项目技术栈清单（§3.1）

| 类别 | 选型 | 版本 | 用途与代码位置 |
|---|---|---|---|
| Flutter / Dart | fvm 固定 | Flutter 3.47.7 / Dart ^3.11.4（.fvmrc、pubspec.yaml） | 全平台（Win/macOS/Linux/Android/iOS） |
| 状态管理 | provider | ^6.1.2 | 依赖注入与可监听选择；实际大量页面用 StatefulWidget+StreamBuilder（dashboard_screen.dart 三层嵌套 StreamBuilder） |
| 路由 | **无三方库**：Navigator 1.0 onGenerateRoute | — | lib/app/app_router.dart + lib/core/navigation/routes.dart |
| UI 组件库 | 纯 Material 3（无三方 UI kit） | — | 全项目 |
| 图标 | Material Icons（uses-material-design）+ cupertino_icons | 1.0.8 | 207 个不同图标、305 处 |
| 字体 | 声明 Inter，**未打包**（问题 S-01） | — | app_theme.dart:195 |
| 主题 | 自研 token：AppColors/AppSpacing + 单一 darkTheme | — | lib/core/theme/ |
| 本地存储 | 自研 JSON 文件持久化（core/persistence/atomic_json_file.dart）+ path_provider | ^2.1.2 | 无 Drift/Hive（架构规则禁止域层依赖） |
| 音频播放 | just_audio + just_audio_media_kit（本地 fork packages/）+ media_kit_libs_* + audio_service + audio_session | 0.10.5 等 | lib/features/player/ |
| 录音/监听 | record 6.2.1 + flutter_soloud 4.1.7（pin） | — | KTV 录音/监听 |
| 音频元数据 | audio_metadata_reader | ^1.8.0 | 内嵌标签/封面 |
| 文本编码 | charset | ^2.0.1 | GBK/Shift-JIS 等歌词导入 |
| 二维码 | qr_flutter + mobile_scanner | 4.1.0 / 7.4.2 | 传输配对 |
| 安全 | basic_utils/crypto/pointycastle | — | 传输指纹固定 HTTPS |
| ASR | 自研服务链（whisper.cpp / Qwen3-ASR / ForcedAligner / FFmpeg） | — | lib/features/transcription/（非 UI 依赖，但驱动设置与导入 UI） |

## 2. UI 架构概览

- **壳**：`ElysiumPlayerApp`（lib/app/app.dart）→ MaterialApp（单 darkTheme）→ 全局 Overlay 内组合 [路由内容 + GlobalTranscriptionQueueBar + GlobalPlayerBar] + 顶层导航（Rail/BottomBar，按 `AppResponsive`）。
- **四大目的地**：工程 / 音乐库 / 校对 / 设置（app_destinations.dart）。
- **页面**：24 个 screen 文件、76 个 widget 文件、57 处 showDialog、11 处 BottomSheet。完整清单见 `../inventory/pages-and-routes.md`。
- **设计系统**：token 化程度高（AppColors×922 用、AppSpacing×1259 用），但**无共享组件层**——复合组件全部页面私有，重复热点见 `../inventory/components.md`。

## 3. 整体设计评价（§8.1）

**当前视觉风格**：Spotify 式深色音乐应用——#121212 底、#1DB954 绿强调、扁平无阴影（全局仅 2 处 BoxShadow）、大圆角卡片、细边框。执行纪律**高于平均水平**：硬编码颜色全项目仅 1 处、间距仅 2 处字面量、响应式有文档与统一断点。

**核心问题（按战略重要性排序）**：

1. **品牌断裂（P1）**：应用图标是红/黑/米白、块状 "F"、均衡器渐隐条、做旧印刷质感；UI 是 Spotify 绿+灰。二者零交集。窗口标题与首页大字仍叫 "Elysium Player"。这不是美化问题，是"用户记不住这个产品"的根因。
2. **核心场景差异化不足（P2）**：KTV 舞台仅行级高亮，已有逐字 timing 数据却未见逐字扫光渲染——KTV 产品的"灵魂画面"目前是通用歌词列表样式。
3. **组件重复（P2）**：12 套封面、15 套徽标、17 套空状态、4 套播放控制。无共享组件层是视觉漂移的结构性根源。
4. **密度热点（P2）**：校对菜单 20 项单菜单、ASR 设置 1008 行单组件——功能强但组织依赖用户耐心。
5. **对比度硬伤（P1/P2）**：白字/绿底 2.3:1；三级灰 3.5:1 承担大量说明文字。

**值得保留**：token 体系与执行纪律；响应式断点体系；歌词编辑器的已重构交互（内联编辑、时间直输、菜单收敛）；工程详情的"下一步"引导面板；完善的空/错态文案意识。

## 4. 问题严重程度分布

| 级别 | 数量 | 代表 |
|---|---|---|
| P0 | 0 | —（静态审计无法判定运行时阻断问题） |
| P1 | 4 | 品牌断裂、旧名残留、主按钮对比度、字体失效 |
| P2 | 19 | 组件重复、菜单过载、入口冗余、设置缺区等 |
| P3 | 20 | 文案、小字号、留白、工程债 |

明细见 `issues.md`（支持按级别/页面筛选）。

## 5. 建议的设计原则（§8.2）

1. **"Forge Red" 单点强调**：从图标提取红色作为品牌强调色，**只**用于：主 CTA、KTV 正在唱行、品牌位。保留深色底但把 Spotify 绿降级或替换——绿=成功语义（ready/完成），红=品牌/行动。图标的均衡器渐隐条可作为加载态/进度态的品牌纹样（而非放大 logo）。
2. **效率优先于装饰**：桌面专业工具，动画维持 ≤200ms 功能性过渡，不引入渐变堆叠与玻璃拟态。
3. **歌词即主角**：歌词展示字号、对比度、行距为最高优先级；编辑态文本永不低于 14px/4.5:1。
4. **一个组件一个出处**：封面/徽标/空态/播放控制先入共享层再谈视觉升级。
5. **中文优先排版**：明确 CJK 字体回退链，行高对中文适配（≥1.5）。
6. **长时舒适**：保持深色，文本三级灰提亮至 AA。

## 6. 优化优先级（§8.3）与实施路线（§8.4）

**阶段 1（必须优先，低风险高收益）**
- 全局正名 LyricForge KTV（B-02）；窗口标题、页头、设置、空态。
- 打包 Inter + CJK fallback 或删声明（S-01）。
- 修复两个对比度硬伤（A-01 accent 压暗；A-03 三级灰提亮）。
- 删死代码 RemoteMediaLibraryScreen（T-01）。

**阶段 2（核心组件重构，为品牌化铺路）**
- 新建 `lib/core/widgets/`：`AppArtwork`、`AppBadge`、`AppEmptyState`、`TransportBar`（C-04/05/06/07）。
- 校对菜单分组化 + 去"V2"（C-02、E-02）；ASR 设置拆卡（C-03）。

**阶段 3（品牌与核心场景）**
- 主题引入 Forge Red 强调色 + 导航品牌位换应用图标纹样（B-01）。
- KTV 舞台逐字扫光渲染（K-01，数据链路已有）。
- Dashboard 入口收敛（C-01）、设置分区化（SE-01）。

**阶段 4（细节统一）**
- 全部 P3：圆角/字号 token 化、alpha 阶梯、Semantics 补全、播放器快捷键（A-02）。

**暂不值得动**：路由自研方案、JSON 持久化、传输域架构、provider 选型——均工作良好且非 UI 问题。

## 7. 交付物索引
- 环境诊断：`environment-diagnostic.md`
- 页面报告：`pages/`（dashboard / library / player / lyric-editor / project-detail / settings / import / review-inbox-and-transfer）
- 清单：`../inventory/`（components / theme-and-styles / pages-and-routes）
- 问题总表：`issues.md`（43 项）
- 截图：`../screenshots/README.md`（**空，原因与补救方案见内**）
- Google Drive 归档状态：`google-drive-status.md`
