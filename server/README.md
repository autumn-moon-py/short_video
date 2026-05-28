# file_server

一个轻量的 Dart 文件服务，提供两类能力：

- `GET /video`：返回根目录下 `.webm` 文件列表及可访问 URL
- 静态文件访问：直接通过路径访问根目录下的资源文件

默认根目录为 `E:/video/webm`。

## 运行

直接运行，使用默认根目录：

```powershell
dart run bin/main.dart
```

通过 Dart define 指定根目录：

```powershell
dart run -DFILE_SERVER_ROOT_DIR=E:/video/output bin/main.dart
```

启动后默认监听 `0.0.0.0:9090`。

## 接口

健康检查：

```text
GET /
GET /health
```

返回视频列表：

```text
GET /video
```

返回格式：

```json
[
  ["A(1)", "http://127.0.0.1:9090/A/A(1).webm"]
]
```

静态文件访问示例：

```text
GET /A/A(1).webm
```

## 测试

运行验收测试：

```powershell
dart run test/acceptance_test.dart
```
