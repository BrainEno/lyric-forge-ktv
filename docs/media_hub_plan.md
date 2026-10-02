# Media Hub 开发计划：桌面音乐库 ↔ 手机播放器

## 目标

把 LyricForge 从“单机 KTV 制作工具”扩展为 local-first 的跨端播放器：

- 桌面端负责持有完整本地音频库与 KTV 工程
- 手机端在同一局域网内发现或配对桌面端
- 手机端可以浏览桌面端曲目
- 手机端可以直接流式播放，不要求先完整下载
- 用户可选择下载到手机离线播放
- KTV 工程传输复用同一套连接、鉴权和传输协议
- 不依赖云存储，不上传用户音频

Spotify 只作为信息层级、深色媒体界面、播放器交互节奏的参考，不复制品牌资产或产品文案。

---

## 产品形态

### Desktop Media Hub

桌面端新增“音乐共享”能力。

核心职责：

1. 选择共享来源
   - LyricForge 工程中的原声 / 伴奏 / 人声
   - 用户手动选择的本地音频
   - 后续支持指定音乐文件夹
2. 启动局域网 HTTP 服务
3. 生成一次会话 token
4. 暴露曲目列表和受保护的音频流地址
5. 支持 HTTP Range，满足 seek、断点和边下边播
6. 后续增加二维码和 mDNS / Bonjour 发现

### Mobile Player

手机端新增独立的“音乐”入口。

建议导航：

- 首页
- 桌面音乐库
- 下载
- 最近播放
- 设置

播放器采用 Spotify-inspired 结构：

- 大封面
- 曲名 / 艺术家
- 进度条
- 上一首 / 播放暂停 / 下一首
- 播放队列
- 歌词入口
- 下载状态
- 当前音源（原声 / 伴奏 / 人声）

移动端不复制 Spotify 品牌、Logo、专有图标或文案。

---

## Media Hub Protocol v1

### 配对信息

二维码或手动连接最终都转换为：

```
lyricforge://media-hub/connect
  ?v=1
  &host=192.168.1.20
  &port=49152
  &token=<one-time-session-token>
```

第一版 token 只在本次共享会话有效。

### API

#### 健康检查

```
GET /v1/health
Authorization: Bearer <token>
```

#### 曲目列表

```
GET /v1/tracks
Authorization: Bearer <token>
```

返回内容不暴露桌面本地文件路径。

#### 音频流 / 下载

```
GET /v1/tracks/{trackId}/audio
Authorization: Bearer <token>
Range: bytes=...
```

要求：

- 支持 200
- 支持 206 Partial Content
- 支持 open-ended range
- 支持 suffix range
- 非法 range 返回 416
- HEAD 返回正确 Content-Length / Content-Range
- 根据音频格式返回正确 MIME type

---

## 安全边界

MVP：

- 默认只绑定本机局域网可达的 HTTP server
- 每次启动共享重新生成 token
- API 不返回本机绝对路径
- 手机端需要 token 才能查看列表或读取音频
- UI 必须明确显示“正在共享”
- 用户可随时停止共享

后续：

- 受信任设备列表
- 设备名 + 首次确认
- token 轮换
- 可选固定 PIN
- 局域网 HTTPS / Noise 等更强通道视需求评估

---

## 开发切片

### Slice A — Media Hub Foundation

当前目标：

- MediaHub 领域模型
- MediaHubService 接口
- HttpMediaHubService
- token 鉴权
- 曲目列表
- 音频流
- HTTP Range
- LAN IP 解析
- ServiceLocator 注册

这一阶段不改 UI，避免和播放器页面同时大改。

### Slice B — Desktop Sharing UI

新增桌面端“音乐共享”页面 / Dialog：

- 选择多个音频文件
- 从现有 KTV 工程加入共享列表
- 开始 / 停止共享
- 展示 IP、端口、二维码
- 显示连接设备和当前传输状态
- Windows / macOS 防火墙失败给出明确提示

验收：

- 两台同局域网设备可通过浏览器访问 health 和 tracks
- 任意一首音频可以 Range 请求
- 停止共享后端口立即关闭

### Slice C — Mobile Media Hub Client

新增：

- MediaHubClientService
- 扫二维码
- 手动输入 IP:Port
- 拉取曲目列表
- 连接状态与重试
- 将远程 stream URL 接入 AudioPlayerService

验收：

- iOS / Android 可读取桌面曲目列表
- 点击歌曲后无需完整下载即可播放
- seek 可用
- 网络断开后显示明确错误，不假装继续播放

### Slice D — Spotify-inspired Mobile Player

重点：

- 响应式首页
- mini player
- Now Playing 全屏页
- 播放队列
- 最近播放
- 歌词页
- 原声 / 伴奏 / 人声切换
- 深色媒体视觉体系

验收：

- 单手操作友好
- 小屏不溢出
- 横竖屏布局明确
- 播放控件和网络状态不互相遮挡

### Slice E — Offline Download & Cache

新增：

- 下载到手机
- 下载进度
- 本地缓存索引
- 校验文件完整性
- 删除下载
- 自动回退：桌面在线时优先远程，离线时使用已下载文件

### Slice F — KTV Project Transfer

复用 Media Hub session：

- manifest
- lyrics.json
- original / instrumental / vocals
- 封面与元数据

不再维护另一套“一次性工程传输服务器”。

---

## 当前技术决策

1. Media Hub 与 ProjectRepository 解耦。
   当前 ProjectRepository 仍是内存实现，不能让跨端播放被工程持久化进度阻塞。

2. 第一版使用 dart:io HttpServer。
   需求只是局域网 JSON + 文件流 + Range，不需要先引入 shelf。

3. 流式播放和离线下载使用同一音频 endpoint。
   这样手机端播放器、下载器和 KTV 工程传输可以共享鉴权与错误模型。

4. 先显式配对，后自动发现。
   二维码 / 手动连接比 mDNS 更容易验证；Bonjour / mDNS 放到连接链路稳定之后。

5. 所有远程音频最终都必须进入现有 AudioPlayerService 抽象。
   UI 不直接操作 HTTP client 或本地文件路径。
