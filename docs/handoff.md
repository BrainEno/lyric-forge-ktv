# Handoff

## 目标

修复 #415：加固本地 Qwen3-ASR runtime 的安全边界。

- 问题 A：`qwen3-asr serve` 没有任何认证，本机任意进程都能调用 `/v1/transcribe`、`/v1/align`，让 runtime 读取任意文件路径。
- 问题 B：`_reservePort` 先绑定端口、关闭后再交给 runtime 重新绑定（TOCTOU），而且 `/healthz` 只要返回 200 就被信任，端口可被抢占、身份可被伪造。

#319 保持 OPEN，本轮未涉及。

## Git 现场

- 分支：`arena/12673259-lyric-forge-ktv`，基于 main `458b14c76851e9f463428dfe7e43bfff49bfcb34`。
- PR #445，标题 `[model-eval] Harden Qwen runtime security boundary`。PR 状态和最新 head 以 GitHub 为准。
- 分支上用过三个临时 workflow，都已删除，不在 PR diff 里：
  - `tmp-session-auth-validation.yml`：Dart 和 Linux Rust 验证。
  - `tmp-format-fix.yml`：在 pub get 之后执行 dart format。
  - `tmp-windows-session-auth.yml`：Windows 上的 CPU 版 Rust 测试。

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
  - Windows：CUDA 单元测试，加上用 CPU 构建跑的集成测试（独立 target dir），并记录 CUDA 二进制在无 GPU runner 上的启动结果。
  - macOS：session-auth 测试是独立步骤。两个平台失败时都会把日志写进 step summary 和 annotation。
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

- 沙箱里没有 Dart 和 Rust 工具链，也下载不到 job 日志。下面的结果都来自 GitHub Actions：用 annotation 和 step summary 读取。
- Run `43605196763`（head `da18d0b`）：
  - Flutter 全量测试：2058 通过，1 跳过，0 失败。
  - 聚焦的安全/Qwen/ForcedAligner 测试：58 通过。
  - analyze：exit 0，没有 error/warning。
  - work_log check：0 个错误。
  - Linux 上的 Rust 补丁测试：单元 6、`session_auth_integration` 7、`serve_integration` 19，全部通过。
- PR #445 的第一次检查失败在格式检查。原因是临时 workflow 在 `flutter pub get` 之前执行了 `dart format`，用的是最新语言版本的风格，而不是包声明的 `^3.11.4`。已在 pub get 之后重新格式化（`978dbfe`）。
- Windows CUDA 上的 session-auth 测试：
  - 单元测试 6 个全部通过。
  - 集成测试 7 个里失败 6 个。原因是 CUDA 版 `qwen3-asr.exe` 在没有 GPU 的 runner 上根本启动不了：exit `-1073741515`（STATUS_DLL_NOT_FOUND），依赖 `nvcuda.dll`。
  - 用临时 Windows CPU workflow（run `43609022661`）验证：单元 6 + 集成 7，串行和并行都通过，包括 `SO_EXCLUSIVEADDRUSE` 端口抢占测试。
  - 正式 workflow 现在照常跑 CUDA 单元测试；集成测试改用同一份补丁源码的 CPU 构建，放在独立的 `--target-dir`，不会覆盖打包用的 CUDA 二进制。
- macOS Intel 有一次运行（`43611658036`）失败，exit 101，拿不到输出；前两次和之后的运行都通过。已做的处理：
  - session-auth 测试拆成独立步骤，失败时输出日志。
  - runtime 拒绝请求时带上 `Connection: close`。
  - 集成测试改用不复用连接的 HTTP agent，并断言拒绝响应带有该 header。
- PR head `a813d47` 的所有检查都通过：Flutter Quality Gate、Build managed ASR runtime（Windows x64 CUDA、macOS Intel）、ASR runtime release contract、Runtime integrity、ASR install experience、Managed storage location。这个 head 的逐条测试数量从沙箱里读不到。
- 没有做真实 GPU 或端到端模型测试；Windows 只在 GitHub hosted runner 上测过。

## 下一步

- 合并到 main 后才会发布 `asr-runtime-v3`。在 v3 发布之前，已安装 v2 的用户会被判定为 runtime 过旧（fail closed），需要在发布后修复安装。
- 在真实的 Windows + RTX 5080 环境里，跑一次完整的“识别 → 对齐 → 空闲关闭”流程。

## 已知风险

- 同一用户下的恶意代码可以读取进程内存、附加调试器、注入进程或替换 runtime 二进制，从而拿到密钥。这是 OS 层面的限制，本 PR 不处理，已写入 README 威胁模型。
- loopback HTTP 没有加密；但要窃听同样需要同一机器上的本地权限。
- `SO_EXCLUSIVEADDRUSE` 和 Windows 端口抢占测试只在 CI 的 Windows runner 上验证过（CPU，`serve --mock`），没有在真机 GPU 上验证。

最后更新：2026-11-15 00:25（Asia/Taipei）
