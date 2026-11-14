# Handoff

## 目标

修复 #415：加固本地 Qwen3-ASR runtime 的安全边界。

- 问题 A：`qwen3-asr serve` 没有任何认证，本机任意进程都能调用 `/v1/transcribe`、`/v1/align`，让 runtime 读取任意文件路径。
- 问题 B：`_reservePort` 先绑定端口、关闭后再交给 runtime 重新绑定（TOCTOU），而且 `/healthz` 只要返回 200 就被信任，端口可被抢占、身份可被伪造。

#319 保持 OPEN，本轮未涉及。

## Git 现场

- 分支：`arena/12673259-lyric-forge-ktv`，基于 main `458b14c76851e9f463428dfe7e43bfff49bfcb34`。
- PR 标题：`[model-eval] Harden Qwen runtime security boundary`。PR 状态和 head 以 GitHub 为准。
- 临时验证 workflow `.github/workflows/tmp-session-auth-validation.yml` 只用于本分支验证，开 PR 前必须删除，不得进入 main。

## 已改文件

- **Rust runtime 补丁** `tool/patches/qwen3-asr-session-auth.patch`（应用在 upstream `7984967` 加现有三个补丁之上）：
  - 新增 `session_auth.rs`：
    - 从 stdin 第一行读入 64 位 hex 密钥：全零视为非法；报错信息不回显密钥。
    - 只允许字面量 loopback IP；runtime 自己绑定 `--port 0`，Windows 先设置 `SO_EXCLUSIVEADDRUSE`。
    - 绑定后在 stdout 输出 `LYRICFORGE_RUNTIME_READY {protocol, port, proof}`。
    - axum 中间件对每个路由验签（时间窗口 ±120 秒、nonce 防重放、拒绝重复 header），并对每个响应签名（SSE/101 使用 `unsigned-stream` 摘要）。
    - stdin 收到 EOF 时退出。
  - `cmd_serve.rs`：
    - 新增 `--lyricforge-session-stdin`，加载模型前先读密钥。
    - 会话模式下用认证层替换 `CorsLayer::Any`，并由 runtime 自己绑定端口。
  - 测试：单元测试（RFC 4231、与 Dart 共用的向量、篡改/过期/重放、header 解析、loopback 限制）和 7 个 `serve --mock` 集成测试（未认证全部 401、签名可用、旧密钥失效、端口无法被重新绑定、密钥错误时 fail closed、stdin EOF 退出）。
- **workflow** `build-asr-runtime.yml`：
  - Windows CUDA 与 macOS Intel 都会应用补丁并运行 Rust 测试。
  - `RUNTIME_TAG: asr-runtime-v3`，manifest revision 加上 `+session-auth-v1`。
- **Dart**
  - 新增 `qwen_runtime_session.dart`：
    - 协议常量与 HMAC 消息格式。
    - `QwenRuntimeSessionSecret`：`Random.secure()` 生成，`toString` 脱敏，`revoke` 清零。
    - `QwenRuntimePlatformPolicy`：统一接口，各平台说明自己如何独占监听端口。
    - `QwenRuntimeLauncher`：
      - 通过 stdin 传密钥，等待 ready proof，再做一次签名 `/healthz`。
      - 任何失败都撤销密钥并结束子进程。
      - 失败分类：`unsupportedRuntime`、`identityRejected`、`startupTimeout`、`cancelled` 等。
    - `QwenRuntimeSession`：只为自己的 loopback 端点签名，并负责验证响应。
  - `qwen3_asr_native_transcription_service.dart`：
    - 删除端口预留和明文 health 轮询。
    - 复用 session 前重新做签名身份检查；对齐发送前再验证一次。
    - 先签名后连接；响应未通过验证就丢弃，并停止 runtime。
    - cancel/dispose 递增代次，防止晚到的启动结果被当成第二个 session 接管。
  - `forced_alignment_http_client.dart`：
    - 新增可选 authenticator，在建立连接前签名。
    - 在解码响应之前先校验原始字节。
    - 新增 `ForcedAlignmentAuthenticationException`。
  - `managed_asr_runtime_manager.dart`：
    - 准备 Qwen 模型时也走 launcher（预算 2700 秒，支持取消）。
    - 只有身份被证明后才写入 ready marker。
    - 删除 `_reservePort` 和 `_healthReady`。
- **测试**：
  - 新增：`fake_qwen_runtime.dart`（实现与 Rust 相同的 stdin/HMAC 协议）、`qwen_runtime_session_test.dart`、`qwen_runtime_service_lifecycle_test.dart`、`qwen_runtime_security_contract_test.dart`。
  - 扩展：`forced_alignment_http_client_test.dart`（authenticator）。
  - 版本 pin：`asr_runtime_release_workflow_contract_test.dart` 和 `runtime_integrity_install_contract_test.dart` 更新到 v3。
- **文档**：README 的“Local ASR runtime trust boundary”整节重写；`asr_runtime_installation.md`、`local_transcription.md` 更新到 v3。

## 检查结果

- 沙箱里没有 Dart 和 Rust 工具链，也读不到 job 日志，所以用分支上的临时 workflow 做格式化、work log、analyze、测试，并在 Linux 上测试 Rust 补丁，结果以 annotation 形式读取。
- 具体命令、通过/失败数量，以及 Windows/macOS runtime 构建结果都写在 PR 描述里。

## 下一步

- 等 PR 上的 `Build managed ASR runtime` 在 Windows CUDA 和 macOS Intel 上完成补丁测试与打包。合并到 main 后才会发布 `asr-runtime-v3`。在 v3 发布之前，已安装 v2 的用户会被判定为“runtime 过旧”，需要等发布后再修复（fail closed）。
- 在真实的 Windows + RTX 5080 环境里，跑一次完整的“识别 → 对齐 → 空闲关闭”流程（CI 没有 GPU）。

## 已知风险

- 同一用户下的恶意代码可以读取进程内存、附加调试器、注入进程或替换 runtime 二进制，从而拿到密钥。这是 OS 层面的限制，本 PR 不处理，已写入 README 威胁模型。
- loopback HTTP 没有加密；但要窃听同样需要同一机器上的本地权限。
- `SO_EXCLUSIVEADDRUSE` 和 Windows 端口抢占测试只在 CI 的 Windows runner 上验证过（CPU，`serve --mock`），没有在真机 GPU 上验证。

最后更新：2026-11-14 22:30（Asia/Taipei）
