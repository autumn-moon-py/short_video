# tool/ — 项目辅助工具

针对本项目的 CLI 脚本与 MCP server，供 Trae 会话与本机 pwsh 使用。

## 前提

- PATH 上有 `pwsh`、`flutter`(3.41.6+)、`dart`、`adb`
- **不要用 `fvm`**：本机 fvm 的 stable 解析到 Flutter 3.24.0/Dart 3.5.0，不满足
  `pubspec.yaml` 的 `sdk: ^3.11.1`。脚本全部直接调用 PATH 上的 `flutter`（3.41.6）。

## CLI 脚本

### 拉取 Android 真机 Flutter 日志

```powershell
# 最近 200 行（单设备自动识别）
.\tool\app-logs.ps1

# 最近 30 秒
.\tool\app-logs.ps1 -SinceSeconds 30

# 指定设备 / 更多行 / 落盘
.\tool\app-logs.ps1 -DeviceId <id> -Tail 500 -OutFile log.txt
```

内部流程：`adb devices` 找设备 → `pidof com.autumnmoon.short_video` 取 PID →
`adb logcat --pid=<pid> flutter:I '*:S'`。

### 启动客户端到真机

```powershell
# 自动检测单设备
.\tool\app-run.ps1

# 指定 dart-define（可多个）与设备
.\tool\app-run.ps1 -DeviceId <id> -DartDefine VIDEO_SERVER_HOST=192.168.0.101
```

阻塞直到 `flutter run` 退出，`Ctrl+C` 结束。

### 静态检查

```powershell
.\tool\app-analyze.ps1          # 客户端 + 服务端
.\tool\app-analyze.ps1 -ClientOnly
.\tool\app-analyze.ps1 -ServerOnly
```

### 启停文件服务（9090）

```powershell
.\tool\server-start.ps1 -RootDir E:/video/output -LogFile server.log   # 前台阻塞
.\tool\server-stop.ps1                                                 # 按端口杀进程
```

服务端用的是 `-D` define（与 `server/启动.bat` 一致），非 `--define`。

## MCP server

`tool/mcp/server.dart`：零第三方依赖的 stdio MCP server，暴露 5 个工具：
`app_logs` / `app_run` / `app_analyze` / `server_start` / `server_stop`。

### 手动验证

```powershell
cd tool\mcp
dart analyze
# 冒烟：直接跑 server.dart 会等待 stdin，可用调试器或 MCP client 连接
```

### 接入 Trae（stdio 类型）

项目配置文件里注册一个 MCP server，command 指向：

```
dart run D:\project\flutter\new_short_video\tool\mcp\server.dart
```

工作目录建议设为项目根 `D:\project\flutter\new_short_video`。

## 注意

- 脚本假设 app 包名 `com.autumnmoon.short_video`（见 `android/app`），如需改包名，
  更新各脚本里的 `$Package` / `$pkg`。
- `server-start.ps1` / `app-run.ps1` 是阻塞型脚本，MCP 侧调用前先想好是否会卡住会话。
