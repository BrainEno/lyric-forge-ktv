# Tailscale 远程媒体传输方案

## 结论

LyricForge 不自行实现 Tailscale 同等级的网络层。

跨公网远程播放 / 文件传输采用：

1. 桌面端和手机端安装 Tailscale
2. 两台设备加入同一个 tailnet
3. LyricForge Desktop Media Hub 监听本机 HTTP 端口
4. Media Hub 自动识别 Tailscale IPv4（100.64.0.0/10）
5. 检测到 Tailscale 地址时，优先把它作为远程连接地址
6. 手机端通过该地址访问曲目列表、HTTP Range 音频流和后续下载接口
7. LyricForge 自己仍保留 session token 鉴权

这样 Tailscale 负责跨 NAT、P2P、Relay、WireGuard 加密和设备身份，
LyricForge 只负责播放器业务协议。

---

## 为什么不自行实现 Tailscale

如果从零实现同等级能力，需要长期维护：

- WireGuard / VPN 数据面
- NAT traversal
- UDP hole punching
- STUN 类网络探测
- DERP / relay 基础设施
- 控制平面
- 身份登录和设备授权
- 密钥生成、轮换、撤销
- ACL / grants
- 设备在线状态
- DNS / 稳定设备寻址
- iOS Network Extension
- Android VPNService
- Windows/macOS/Linux 网络适配
- 中继服务器部署、监控和带宽成本

这已经不是播放器功能，而是一套独立网络产品。

---

## 用户体验目标

### 首次配置

1. 用户在桌面端和手机端安装 Tailscale
2. 使用同一账户或允许互访的 tailnet 登录
3. LyricForge 检测到 Tailscale 网络
4. UI 显示：
   - 远程访问：可用
   - Tailscale 地址
   - 本地局域网地址
5. 手机扫描二维码或选择已保存桌面设备

### 日常使用

只要满足：

- 桌面电脑在线
- LyricForge Media Hub 正在运行
- 两端 Tailscale 在线

手机即使使用 5G、其他 Wi-Fi、异地网络，也可以：

- 浏览桌面音乐库
- 流式播放音频
- seek
- 下载到手机
- 获取 KTV 工程
- 获取歌词与封面

---

## 网络优先级

Media Hub 返回多个 endpoint：

1. Tailscale
2. LAN
3. Other

当前默认：

- 有 Tailscale 地址：优先 Tailscale
- 没有 Tailscale：回退 LAN
- 两者都没有：仅本机 loopback

这样不会破坏原有局域网功能。

---

## 端口策略

Media Hub 默认优先使用固定端口：

```
48517
```

原因：

- Tailscale IP 本身稳定
- 固定端口便于保存桌面设备
- 后续可直接支持 MagicDNS，例如：
  `http://my-desktop:48517`

如果 48517 被占用，Media Hub 自动回退到随机可用端口。

---

## 安全策略

### 网络层

远程链路由 Tailscale 提供端到端加密。

### 应用层

LyricForge 继续使用 Media Hub session token。

即便某台 tailnet 设备能够访问目标端口，没有正确 token 仍无法：

- 查看曲目列表
- 拉取音频
- 下载工程

后续可进一步增加：

- trusted device
- 首次配对确认
- 固定设备凭据
- token refresh
- 撤销设备
- 远程访问开关
- 指定“仅 Tailscale / LAN + Tailscale”

---

## 为什么暂时不用 Tailscale Funnel

Funnel 是把服务暴露到公共互联网。

LyricForge 的目标是个人设备之间的私有音乐库访问，
所以默认不应使用 Funnel。

---

## 为什么暂时不用 Tailscale Serve

直接通过 Tailscale IP / MagicDNS + Media Hub 端口已经足够。

后续若希望：

- HTTPS
- 不显示端口
- 更稳定的人类可读 URL

可以再考虑自动配置 Tailscale Serve。

---

## 下一阶段

### A. Desktop Remote Access UI

增加：

- “远程访问”开关
- Tailscale 可用状态
- Tailscale 地址
- LAN 地址
- 固定端口状态
- 二维码
- 启动 / 停止共享
- 防火墙错误提示

### B. Mobile Remote Library

增加：

- 扫码配对
- 保存桌面设备
- 自动重连
- Tailscale / LAN 自动回退
- 远程曲目列表
- 远程音频播放

### C. Background / Always Available

要实现真正的“随时访问”，桌面端需要：

- 开机启动（可选）
- 最小化到托盘
- Media Hub 后台运行
- 远程访问开关持久化
- 电脑睡眠状态提示

注意：电脑关机或深度睡眠时，Tailscale 也无法让 LyricForge 提供音频。

### D. Offline Download

手机端增加：

- 下载队列
- 断点续传
- 校验
- 本地缓存
- 自动使用离线副本
