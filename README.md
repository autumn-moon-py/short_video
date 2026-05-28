# new_short_video

局域网短视频播放项目，包含两个部分：

- Flutter 客户端：自动发现局域网视频服务，纵向切换视频，支持自定义播放控制与拖动进度。
- Dart 文件服务：扫描本地视频目录，返回视频列表，并提供静态文件与 `Range` 请求支持。

## 目录结构

```text
lib/                Flutter 客户端
server/             Dart 文件服务
windows/            Windows Runner
android/            Android Runner
```

## 环境要求

### 客户端

- Windows
- `FVM 2.x`
- Flutter stable
- Dart `3.11.1` 或兼容版本

### 服务端

- Dart SDK
- 默认视频目录：`E:/video/webm`

## 快速启动

### 1. 启动服务端

在项目根目录打开终端后执行：

```powershell
cd server
dart run bin/main.dart
```

如果视频目录不是默认值：

```powershell
cd server
dart run -DFILE_SERVER_ROOT_DIR=D:/your/video/path bin/main.dart
```

启动后默认监听：

```text
http://0.0.0.0:9090
```

服务端接口：

- `GET /health`：健康检查
- `GET /video`：返回视频列表
- `GET /xxx.webm` / `GET /xxx.mp4`：视频静态访问

### 2. 启动客户端

在项目根目录执行：

```powershell
fvm flutter run -d windows
```

如果要做静态检查：

```powershell
fvm flutter analyze
```

## 当前实现说明

### 播放器

- 使用 `media_kit` + `media_kit_video`
- 已禁用插件原生 UI，底部进度条为项目自定义实现
- 当前页会创建视频输出
- Windows 下下一页进入预加载窗口时也会提前创建视频输出，降低切页后黑屏概率
- 每次成功获取视频列表后会先做一次随机乱序

### 预加载与释放策略

- 当前页进入播放时会确保已创建 `VideoController`
- Windows 下下一页进入预加载窗口时也会提前创建 `VideoController`
- 预加载窗口为：`当前页 + 后续 4 个`
- 页面切换时会记录播放位置
- 超出窗口的播放器会释放
- 已增加同步版本号，避免旧的预加载任务误释放新的播放器

### 局域网发现

客户端会自动扫描常见私网段：

- `192.168.x.x`
- `10.x.x.x`
- `172.16.x.x` 到 `172.31.x.x`

发现成功后会缓存服务端 IP，下次优先直接连接。

## 调试说明

### 客户端关键日志

播放器和页面切换相关日志已经补充，控制台里重点看这些前缀：

- `[FeedController]`
- `[ManagedVideoPlayer#索引][标题]`

重点关注的日志内容：

- `loadFeed start` / `loadFeed success`
- `syncWindowAroundCurrent[...]`
- `creating player for index=...`
- `attach video output attempt=...`
- `video output ready attempt=...`
- `video output attach failed attempt=...`
- `stream.buffering=...`
- `stream.error=...`
- `play failed: ...`
- `releasing player at index=...`

### 如何判断问题在哪一层

#### 1. 没有发现服务端

看是否出现：

```text
loadFeed failed: SocketException ...
```

先检查：

- 服务端是否已启动
- 客户端与服务端是否在同一局域网
- 防火墙是否放行 `9090`

#### 2. 发现到服务端，但视频列表为空

检查服务端视频目录是否正确，并确认目录下有：

- `.webm`
- `.mp4`

#### 3. 进度条在走，但画面黑屏

先看这些日志：

- `attach video output attempt=...`
- `video output ready attempt=...`
- `video output attach failed attempt=...`
- `stream.error=...`

如果 `video output ready` 没出现，优先怀疑视频输出初始化失败。

#### 4. 拖动进度后卡顿或跳转异常

当前服务端已支持 `Range` 请求。若仍异常，重点看：

- `onSeekEnd: ...`
- `seek requested: ...`
- `stream.buffering=...`
- `stream.error=...`

## 常用命令

### 客户端

```powershell
fvm flutter run -d windows
fvm flutter analyze
fvm flutter clean
```

### 服务端

```powershell
cd server
dart analyze
dart run test/acceptance_test.dart
dart run bin/main.dart
```

## 已验证项

- 客户端 `fvm flutter analyze` 通过
- 服务端 `dart analyze` 通过
- 服务端验收测试通过
- 服务端已覆盖：
  - `/health`
  - `/video`
  - 静态文件访问
  - `Range` 请求
  - `.webm` / `.mp4` 列表返回

## 备注

- 根目录 `README.md` 以整体联调为主
- `server/README.md` 保留服务端单独说明
- 如果你开新窗口继续排查，优先参考本文件里的“快速启动”和“调试说明”
## Windows proxy note

If `flutter test` fails with `Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`, the local test WebSocket is usually being sent through `HTTP_PROXY` or `HTTPS_PROXY`.

Make sure `NO_PROXY` contains `localhost,127.0.0.1,::1`, or use the wrapper below in this repo:

```powershell
.\tool\flutter.ps1 test
.\tool\flutter.ps1 test test\server_discovery_service_test.dart
.\tool\flutter.ps1 run -d windows --dart-define=VIDEO_SERVER_HOST=127.0.0.1
```
