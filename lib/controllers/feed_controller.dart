import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';
import '../repositories/video_repository.dart';
import '../utils/app_logger.dart';

enum FeedScreenState { loading, ready, empty, error }

class FeedController extends GetxController {
  FeedController(this._repository);

  static const int preloadRadius = 4;
  static const int resumeRadius = 1;
  static const int loopTriggerRemaining = 10;
  static const Duration minTransitionDuration = Duration(milliseconds: 180);

  final VideoRepository _repository;
  final PageController pageController = PageController();

  final Rx<FeedScreenState> screenState = FeedScreenState.loading.obs;
  final RxList<VideoItem> videos = <VideoItem>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool showChrome = false.obs;
  final RxBool isLandscapeMode = false.obs;
  final RxString errorMessage = ''.obs;
  final RxString serverHost = ''.obs;
  final RxnDouble draggingPositionMs = RxnDouble();
  final RxBool isPageTransitioning = false.obs;
  final RxBool hasCachedServer = false.obs;

  final Map<int, ManagedVideoPlayer> _players = <int, ManagedVideoPlayer>{};
  final Map<int, Duration> _resumePositions = <int, Duration>{};
  final Map<int, Uint8List> _coverCache = <int, Uint8List>{};
  final List<int> _preloadQueue = <int>[];
  List<VideoItem> _loopSeed = <VideoItem>[];
  bool _drainingPreloads = false;
  Timer? _chromeTimer;
  bool _bootstrapping = false;
  int _windowSyncVersion = 0;
  bool _playbackSyncRunning = false;
  bool _playbackSyncQueued = false;
  bool _appendingLoopBatch = false;
  DateTime? _transitionStartedAt;
  Directory? _coverCacheDir;
  Future<void>? _coverCacheInitTask;

  void _log(String message) {
    AppLogger.debug('FeedCtrl', message);
  }

  @override
  void onInit() {
    super.onInit();
    _coverCacheInitTask = _ensureCoverCacheDir();
    unawaited(loadFeed());
  }

  ManagedVideoPlayer? playerAt(int index) => _players[index];
  Uint8List? coverFrameAt(int index) => _coverCache[index];

  bool get isDebugAddressVisible => kDebugMode && serverHost.value.isNotEmpty;

  Future<void> loadFeed({bool forceRescan = false}) async {
    if (_bootstrapping) {
      _log('loadFeed ignored: bootstrapping in progress');
      return;
    }

    _bootstrapping = true;
    _windowSyncVersion++;
    _log('loadFeed start, forceRescan=$forceRescan');
    screenState.value = FeedScreenState.loading;
    hasCachedServer.value = !forceRescan && await _repository.hasCachedServer();
    errorMessage.value = '';
    showChrome.value = false;
    draggingPositionMs.value = null;
    _chromeTimer?.cancel();
    await _disposeAllPlayers();
    _resumePositions.clear();

    try {
      if (forceRescan) {
        await _repository.clearCachedServer();
      }

      final payload = await _repository.fetchVideos();
      _loopSeed = payload.videos.toList(growable: false);
      final shuffledVideos = payload.videos.toList()..shuffle();
      videos.assignAll(shuffledVideos);
      _coverCache.clear();
      serverHost.value = payload.serverHost;
      _log(
        'loadFeed success, videos=${videos.length}, server=${payload.serverHost}',
      );

      if (videos.isEmpty) {
        screenState.value = FeedScreenState.empty;
        _log('loadFeed finished with empty result');
        return;
      }

      currentIndex.value = 0;
      screenState.value = FeedScreenState.ready;
      isPageTransitioning.value = true;
      _transitionStartedAt = DateTime.now();

      await _ensureCurrentPlayerReady();
      unawaited(_syncWindowAroundCurrent());
    } catch (error) {
      _log('loadFeed failed: $error');
      errorMessage.value = _toReadableMessage(error);
      screenState.value = FeedScreenState.error;
    } finally {
      isPageTransitioning.value = false;
      _bootstrapping = false;
      _log('loadFeed end, state=${screenState.value}');
    }
  }

  Future<void> onPageChanged(int index) async {
    if (index == currentIndex.value || index < 0 || index >= videos.length) {
      _log(
        'onPageChanged ignored: index=$index current=${currentIndex.value} total=${videos.length}',
      );
      return;
    }

    final previous = currentIndex.value;
    _log('onPageChanged: $previous -> $index');
    isPageTransitioning.value = true;
    _transitionStartedAt = DateTime.now();
    _rememberPosition(previous);
    currentIndex.value = index;
    _maybeAppendRandomLoop();
    draggingPositionMs.value = null;
    hideChrome();
    update(['video_$previous', 'video_$index', 'current_controls']);

    try {
      await _ensureCurrentPlayerReady();
      unawaited(_syncWindowAroundCurrent());
    } finally {
      await _ensureMinTransitionDuration();
      isPageTransitioning.value = false;
      update(['video_$index', 'current_controls']);
    }
  }

  void toggleChrome() {
    if (showChrome.value) {
      hideChrome();
      return;
    }
    showChromeTemporarily();
  }

  void showChromeTemporarily() {
    showChrome.value = true;
    _restartChromeTimer();
  }

  void hideChrome() {
    _chromeTimer?.cancel();
    showChrome.value = false;
  }

  Future<void> togglePlayPause() async {
    final player = _players[currentIndex.value];
    if (player == null) {
      _log('togglePlayPause ignored: no player at index=${currentIndex.value}');
      return;
    }

    if (player.playing.value) {
      _log('togglePlayPause -> pause, index=${currentIndex.value}');
      await player.pause();
      return;
    }

    _log('togglePlayPause -> play, index=${currentIndex.value}');
    await player.play();
  }

  Future<void> toggleOrientationMode() async {
    isLandscapeMode.toggle();
    final landscape = isLandscapeMode.value;

    if (GetPlatform.isAndroid) {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [DeviceOrientation.portraitUp],
      );
    }

    showChromeTemporarily();
  }

  void onSeekStart(double value) {
    draggingPositionMs.value = value;
    _chromeTimer?.cancel();
  }

  void onSeekUpdate(double value) {
    draggingPositionMs.value = value;
  }

  Future<void> onSeekEnd(double value) async {
    final player = _players[currentIndex.value];
    if (player == null) {
      _log('onSeekEnd ignored: no player at index=${currentIndex.value}');
      draggingPositionMs.value = null;
      return;
    }

    final total = player.duration.value.inMilliseconds.toDouble();
    final clamped = value.clamp(0, total <= 0 ? 0 : total);
    _log(
      'onSeekEnd: index=${currentIndex.value}, targetMs=${clamped.round()}, totalMs=${total.round()}',
    );
    await player.seek(Duration(milliseconds: clamped.round()));
    draggingPositionMs.value = null;
    showChromeTemporarily();
  }

  Future<void> retryDiscovery() async {
    await loadFeed(forceRescan: true);
  }

  Future<String?> exportLogs() async {
    try {
      final path = await AppLogger.exportToFile();
      _log('logs exported to: $path');
      return path;
    } catch (e) {
      _log('log export failed: $e');
      return null;
    }
  }

  Future<void> goToNextVideo() async {
    _maybeAppendRandomLoop();
    if (currentIndex.value >= videos.length - 1) {
      return;
    }

    await pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> goToPreviousVideo() async {
    if (currentIndex.value <= 0) {
      return;
    }

    await pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= videos.length || index == currentIndex.value) {
      return;
    }

    pageController.jumpToPage(index);
  }

  Future<void> _ensureCurrentPlayerReady() async {
    final index = currentIndex.value;
    _log('ensureCurrentPlayerReady: index=$index');
    await _ensurePlayer(index);
    final player = _players[index];
    await player?.ensureVideoController();
    unawaited(player?.ensureCoverFrame());
    update(['video_$index', 'current_controls']);
    await _syncPlaybackStates();
  }

  Future<void> _syncWindowAroundCurrent() async {
    final syncVersion = ++_windowSyncVersion;
    final current = currentIndex.value;
    final desired = <int>{};

    desired.add(current);
    for (var offset = 1; offset <= preloadRadius; offset++) {
      final next = current + offset;
      if (next >= 0 && next < videos.length) {
        desired.add(next);
      }
    }

    final ordered = desired.toList()
      ..sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
    _log(
      'syncWindowAroundCurrent[$syncVersion]: current=$current desired=$ordered',
    );
    for (final index in ordered) {
      // 预加载只创建并入队，不阻塞窗口同步；preload 由单 worker 串行 drain
      await _ensurePlayer(index, awaitPreload: false);
      if (syncVersion != _windowSyncVersion) {
        _log(
          'syncWindowAroundCurrent[$syncVersion] aborted during ensurePlayer',
        );
        return;
      }
    }

    if (syncVersion != _windowSyncVersion) {
      _log('syncWindowAroundCurrent[$syncVersion] aborted after ensurePlayer');
      return;
    }

    final releaseTargets = _players.keys
        .where((index) => !desired.contains(index))
        .toList();
    for (final index in releaseTargets) {
      _rememberPosition(index);
      final player = _players.remove(index);
      if (player != null) {
        _log('releasing player at index=$index');
        await player.dispose();
      }
      // 释放出窗口即清掉内存封面缓存（磁盘文件缓存仍在，回滑时从文件读取）
      _coverCache.remove(index);
      update(['video_$index']);
      if (syncVersion != _windowSyncVersion) {
        _log('syncWindowAroundCurrent[$syncVersion] aborted during release');
        return;
      }
    }

    _trimResumePositions();
    if (syncVersion != _windowSyncVersion) {
      _log(
        'syncWindowAroundCurrent[$syncVersion] aborted before playback sync',
      );
      return;
    }
  }

  /// 确保 index 页的 player 已创建。
  /// - awaitPreload=true：当前页/回滑场景，等 preload 完成（含从队列插队），保证能播。
  /// - awaitPreload=false：窗口预加载，仅创建并入队，不阻塞调用方。
  Future<void> _ensurePlayer(int index, {bool awaitPreload = true}) async {
    final existing = _players[index];
    if (existing != null) {
      if (index < 0 || index >= videos.length) {
        return;
      }
      // 需要就绪但仍在等待队列：插队同步 preload
      if (awaitPreload &&
          !existing.isPreloaded &&
          !existing.isDisposed) {
        _preloadQueue.remove(index);
        _log('ensurePlayer: 当前页插队 preload index=$index');
        await existing.preload(
          startAt: _resumePositions[index] ?? Duration.zero,
        );
        if (!existing.isDisposed) {
          unawaited(_captureAndStoreCover(index, existing));
        }
        update(['video_$index', 'current_controls']);
      }
      return;
    }

    if (index < 0 || index >= videos.length) {
      _log(
        'ensurePlayer ignored: invalid index=$index total=${videos.length}',
      );
      return;
    }

    _log('creating player for index=$index url=${videos[index].url}');
    final player = _createManagedPlayer(
      index,
      attachVideoOutputInitially: _shouldAttachVideoOutputInitially(index),
    );

    _players[index] = player;
    update(['video_$index', 'current_controls']);
    if (awaitPreload) {
      await player.preload(startAt: _resumePositions[index] ?? Duration.zero);
      if (_players[index] == player && !player.isDisposed) {
        unawaited(_captureAndStoreCover(index, player));
      }
      update(['video_$index', 'current_controls']);
    } else {
      _enqueuePreload(index);
    }
  }

  /// 窗口预加载入队，由单个 worker 串行 drain（不并行，避免多实例并发解码）。
  void _enqueuePreload(int index) {
    _preloadQueue.add(index);
    unawaited(_drainPreloadQueue());
  }

  Future<void> _drainPreloadQueue() async {
    if (_drainingPreloads) {
      return;
    }
    _drainingPreloads = true;
    try {
      while (_preloadQueue.isNotEmpty) {
        final index = _preloadQueue.removeAt(0);
        final player = _players[index];
        if (player == null || player.isDisposed) {
          continue;
        }
        _log('preload queue start: index=$index');
        await player.preload(
          startAt: _resumePositions[index] ?? Duration.zero,
        );
        if (player.isDisposed || _players[index] != player) {
          continue;
        }
        unawaited(_captureAndStoreCover(index, player));
        update(['video_$index', 'current_controls']);
        _log('preload queue done: index=$index');
      }
    } finally {
      _drainingPreloads = false;
    }
  }

  ManagedVideoPlayer _createManagedPlayer(
    int index, {
    required bool attachVideoOutputInitially,
  }) {
    final item = videos[index];
    return ManagedVideoPlayer(
      index: index,
      item: item,
      attachVideoOutputInitially: attachVideoOutputInitially,
      initialCoverFrame: _coverCache[index],
      coverFileResolver: () => _coverFileForUrl(item.url),
      onCompleted: () async {
        if (index == currentIndex.value) {
          _log('player completed at current index=$index, advancing');
          await goToNextVideo();
        }
      },
    );
  }

  Future<void> _captureAndStoreCover(
    int index,
    ManagedVideoPlayer player,
  ) async {
    final bytes = await player.ensureCoverFrame();
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    _coverCache[index] = bytes;
    update(['video_$index']);
  }

  void _maybeAppendRandomLoop() {
    if (_appendingLoopBatch || _loopSeed.isEmpty) {
      return;
    }

    final remaining = videos.length - 1 - currentIndex.value;
    if (remaining > loopTriggerRemaining) {
      return;
    }

    _appendingLoopBatch = true;
    try {
      final appended = _loopSeed.toList()..shuffle();
      if (appended.isEmpty) {
        return;
      }

      final lastCurrent = videos.isEmpty ? null : videos.last.url;
      if (lastCurrent != null &&
          appended.length > 1 &&
          appended.first.url == lastCurrent) {
        appended.shuffle();
      }

      videos.addAll(appended);
      _log(
        'loop batch appended: +${appended.length}, total=${videos.length}, current=${currentIndex.value}',
      );
    } finally {
      _appendingLoopBatch = false;
    }
  }

  bool _shouldAttachVideoOutputInitially(int index) {
    if (index == currentIndex.value) {
      return true;
    }
    if (GetPlatform.isWindows && index == currentIndex.value + 1) {
      return true;
    }
    return false;
  }

  Future<void> _syncPlaybackStates() async {
    if (_playbackSyncRunning) {
      _playbackSyncQueued = true;
      return;
    }

    _playbackSyncRunning = true;
    try {
      do {
        _playbackSyncQueued = false;
        final current = currentIndex.value;
        final snapshot = _players.entries.toList(growable: false);

        update([
          for (final entry in snapshot) 'video_${entry.key}',
          'current_controls',
        ]);
        await WidgetsBinding.instance.endOfFrame;

        for (final entry in snapshot) {
          if (!_players.containsKey(entry.key)) {
            continue;
          }

          if (entry.key == current) {
            _log('syncPlaybackStates -> play index=${entry.key}');
            await entry.value.play();
          } else {
            _log('syncPlaybackStates -> pause index=${entry.key}');
            await entry.value.pause();
          }
        }

        update(['current_controls']);
      } while (_playbackSyncQueued);
    } finally {
      _playbackSyncRunning = false;
    }
  }

  void _rememberPosition(int index) {
    final player = _players[index];
    if (player == null) {
      return;
    }

    _resumePositions[index] = player.position.value;
    _log(
      'rememberPosition: index=$index positionMs=${player.position.value.inMilliseconds}',
    );
  }

  void _trimResumePositions() {
    final current = currentIndex.value;
    final removeKeys = _resumePositions.keys
        .where((index) => (index - current).abs() > resumeRadius)
        .toList();
    for (final key in removeKeys) {
      _resumePositions.remove(key);
    }
  }

  void _restartChromeTimer() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 2), () {
      showChrome.value = false;
    });
  }

  Future<void> _ensureCoverCacheDir() async {
    if (_coverCacheDir != null) {
      return;
    }
    final baseDir = await getTemporaryDirectory();
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}video_cover_cache',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _coverCacheDir = dir;
  }

  Future<void> _ensureMinTransitionDuration() async {
    final startedAt = _transitionStartedAt;
    if (startedAt == null) {
      return;
    }
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minTransitionDuration) {
      await Future<void>.delayed(minTransitionDuration - elapsed);
    }
  }

  Future<File?> _coverFileForUrl(String url) async {
    await (_coverCacheInitTask ??= _ensureCoverCacheDir());
    final dir = _coverCacheDir;
    if (dir == null) {
      return null;
    }
    final fileName = '${_stableHash(url)}.jpg';
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  String _stableHash(String input) {
    var hash = 2166136261;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  String _toReadableMessage(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return '加载失败，请重试';
  }

  Future<void> _disposeAllPlayers() async {
    final players = _players.values.toList(growable: false);
    _players.clear();
    _log('disposeAllPlayers: count=${players.length}');
    for (final player in players) {
      await player.dispose();
    }
  }

  @override
  Future<void> onClose() async {
    _windowSyncVersion++;
    _chromeTimer?.cancel();
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } on Object catch (_) {
      // 系统不支持时忽略
    }
    await _disposeAllPlayers();
    pageController.dispose();
    super.onClose();
  }
}

class ManagedVideoPlayer {
  static const int readyPositionThresholdMs = 100;

  ManagedVideoPlayer({
    required this.index,
    required this.item,
    required this.attachVideoOutputInitially,
    this.initialCoverFrame,
    this.coverFileResolver,
    required this.onCompleted,
  }) {
    if (initialCoverFrame != null && initialCoverFrame!.isNotEmpty) {
      coverFrame.value = initialCoverFrame;
    }
    if (attachVideoOutputInitially) {
      _videoController = VideoController(player);
    }
  }

  final int index;
  final VideoItem item;
  final bool attachVideoOutputInitially;
  final Uint8List? initialCoverFrame;
  final Future<File?> Function()? coverFileResolver;
  final Future<void> Function() onCompleted;

  late final Player player = Player();
  VideoController? _videoController;

  final RxBool playing = false.obs;
  final RxBool opening = true.obs;
  final RxBool buffering = true.obs;
  final RxString error = ''.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rxn<Uint8List> coverFrame = Rxn<Uint8List>();
  final RxBool firstFrameReady = false.obs;

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  bool _preloaded = false;
  bool _preloading = false;
  bool _capturingCover = false;
  bool _disposed = false;
  bool _playWhenReady = false;

  VideoController? get videoController => _videoController;

  bool get isDisposed => _disposed;
  bool get isPreloaded => _preloaded;

  void _log(String message) {
    AppLogger.debug('Player#$index', '[${item.title}] $message');
  }

  Future<void> preload({required Duration startAt}) async {
    if (_preloaded) {
      _log(
        'preload skipped: already preloaded, resumeAtMs=${startAt.inMilliseconds}',
      );
      if (startAt > Duration.zero) {
        await seek(startAt);
      }
      return;
    }

    _preloaded = true;
    _preloading = true;
    _log(
      'preload start, url=${item.url}, resumeAtMs=${startAt.inMilliseconds}',
    );
    _bindStreams();

    try {
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (_disposed) break;
        try {
          // 先清除之前的错误状态
          error.value = '';
          opening.value = true;

          await player.open(Media(item.url), play: false);

          // player.open() 返回后，media_kit 可能还会异步报告错误
          // （如 "Failed to open ..."），通过 stream.error 发出。
          // 需要等待 opening 状态变化或 error 流来确认是否真正成功。
          final openOk = await _waitForOpenResult();
          if (openOk) {
            if (startAt > Duration.zero) {
              await player.seek(startAt);
            }
            _log('preload open success (attempt $attempt)');
            opening.value = false;
            _maybePlayWhenReady();
            return;
          }

          // open 失败（stream.error 触发），尝试重试
          if (attempt < maxAttempts && !_disposed) {
            AppLogger.warn('Player#$index',
                'preload attempt $attempt failed (stream.error), retrying in 800ms: ${item.url}');
            await player.stop();
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }

          AppLogger.error('Player#$index',
              'preload failed after $maxAttempts attempts: ${item.url}',
              null, null);
          error.value = '视频加载失败';
        } catch (exception, stackTrace) {
          // player.open() 本身抛出异常（如 URL 格式错误）
          if (attempt < maxAttempts && !_disposed) {
            AppLogger.error('Player#$index',
                'preload attempt $attempt threw exception, retrying in 800ms: ${item.url}',
                exception, stackTrace);
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          AppLogger.error('Player#$index',
              'preload failed after $maxAttempts attempts: ${item.url}',
              exception, stackTrace);
          error.value = '视频加载失败';
        }
      }
      opening.value = false;
      _log('preload end, opening=${opening.value}, error=${error.value}');
    } finally {
      _preloading = false;
    }
  }

  /// 等待 player.open() 的真正结果。
  /// player.open() 返回后，media_kit 可能还会异步通过 stream.error
  /// 报告 "Failed to open" 错误。此方法等待最多 5 秒。
  /// 判定成功信号：视频宽度出现 或 duration>0（媒体已解析）；error 触发即失败。
  Future<bool> _waitForOpenResult() async {
    // 如果已经有错误（stream.error 在 await open 期间就触发了）
    if (error.value.isNotEmpty) {
      return false;
    }

    // 如果 opening 已经变为 false（某些情况下 open 成功会很快）
    if (!opening.value) {
      return true;
    }

    final completer = Completer<bool>();
    StreamSubscription<String>? errorSub;
    StreamSubscription<int?>? widthSub;
    StreamSubscription<Duration>? durationSub;

    void complete(bool result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    errorSub = player.stream.error.listen((message) {
      _log('stream.error during waitForOpen: $message');
      complete(false);
    });

    // 视频宽度从 null 变为非 null 说明媒体已成功打开并解析了视频轨道
    widthSub = player.stream.width.listen((width) {
      if (width != null && width > 0 && !completer.isCompleted) {
        _log('stream.width=$width during waitForOpen, open success');
        complete(true);
      }
    });

    // duration>0 说明媒体元数据已解析（部分视频 width 事件延迟，如 4K），
    // 可提前判成功，避免死等 width 拖满超时。
    durationSub = player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !completer.isCompleted) {
        _log('stream.duration=${duration.inMilliseconds}ms during waitForOpen, '
            'open success');
        complete(true);
      }
    });

    // 超时保护：5 秒后如果没有任何信号，检查当前状态
    Future<void>.delayed(const Duration(seconds: 5)).then((_) {
      if (!completer.isCompleted) {
        if (error.value.isNotEmpty) {
          complete(false);
        } else if (!opening.value) {
          complete(true);
        } else {
          // 超时但无明确错误，视为成功（可能只是网络慢）
          _log('waitForOpen timeout, assuming success');
          complete(true);
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      await errorSub.cancel();
      await widthSub.cancel();
      await durationSub.cancel();
    }
  }

  Future<void> ensureVideoController() async {
    if (_videoController != null) {
      return;
    }
    _log('attach video output');
    _videoController = VideoController(player);
  }

  Future<Uint8List?> ensureCoverFrame() async {
    if (_disposed ||
        _capturingCover ||
        coverFrame.value != null ||
        error.value.isNotEmpty) {
      return coverFrame.value;
    }

    _capturingCover = true;
    try {
      final cached = await _readCoverFromFile();
      if (cached != null && cached.isNotEmpty) {
        coverFrame.value = cached;
        _log('cover loaded from cache, bytes=${cached.length}');
        return cached;
      }

      await ensureVideoController();

      for (var i = 0; i < 4; i++) {
        if (_disposed) {
          return null;
        }
        if (coverFrame.value != null) {
          return coverFrame.value;
        }
        final shot = await player.screenshot(format: 'image/jpeg');
        if (shot != null && shot.isNotEmpty) {
          coverFrame.value = shot;
          await _writeCoverToFile(shot);
          _log('cover captured, bytes=${shot.length}');
          return shot;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      _log('cover capture skipped: no frame available yet');
    } catch (exception, stackTrace) {
      AppLogger.error('Player#$index', 'cover capture failed',
          exception, stackTrace);
    } finally {
      _capturingCover = false;
    }
    return coverFrame.value;
  }

  Future<void> play() async {
    if (_disposed) {
      return;
    }
    if (error.value.isNotEmpty) {
      _log('play skipped: error=${error.value}');
      return;
    }
    // 仍在 open 中（预加载未完成）：登记待播标记立即返回，不阻塞调用方，
    // preload 成功（opening=false）后会通过 _maybePlayWhenReady 真正播放。
    if (opening.value) {
      _playWhenReady = true;
      _log('play deferred: still opening, will auto-play on ready');
      return;
    }
    await _startPlayback();
  }

  /// opening 完成后的自动补播：仅当曾登记待播且状态可用时真正播放。
  void _maybePlayWhenReady() {
    if (!_playWhenReady ||
        _disposed ||
        opening.value ||
        error.value.isNotEmpty) {
      return;
    }
    _playWhenReady = false;
    unawaited(_startPlayback());
  }

  Future<void> _startPlayback() async {
    try {
      _log('play requested');
      await player.play();
    } catch (exception, stackTrace) {
      AppLogger.error('Player#$index', 'play failed', exception, stackTrace);
      error.value = '视频播放失败';
    }
  }

  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    _playWhenReady = false;
    try {
      _log('pause requested');
      await player.pause();
    } catch (exception, stackTrace) {
      AppLogger.error('Player#$index', 'pause failed', exception, stackTrace);
    }
  }

  Future<void> seek(Duration value) async {
    if (_disposed) {
      return;
    }
    try {
      _log('seek requested: targetMs=${value.inMilliseconds}');
      await player.seek(value);
    } catch (exception, stackTrace) {
      AppLogger.error('Player#$index', 'seek failed', exception, stackTrace);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _playWhenReady = false;
    _log('dispose start');
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    // 先 stop 卸载媒体：Android 下 surface 归零的 VideoOutput.Resize 会在
    // player 仍存活时处理完，避免 dispose 后 media_kit_video 的 widListener
    // 对已释放 player 调用 seek 抛 "[Player] has been disposed"。
    try {
      await player.stop();
    } on Object catch (e) {
      _log('dispose stop error: $e');
    }
    await player.dispose();
    _log('dispose end');
  }

  Future<Uint8List?> _readCoverFromFile() async {
    final resolver = coverFileResolver;
    if (resolver == null) {
      return null;
    }

    try {
      final file = await resolver();
      if (file == null || !await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCoverToFile(Uint8List bytes) async {
    final resolver = coverFileResolver;
    if (resolver == null || bytes.isEmpty) {
      return;
    }

    try {
      final file = await resolver();
      if (file == null) {
        return;
      }
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // ignore cache write errors
    }
  }

  void _bindStreams() {
    _subscriptions.add(
      player.stream.playing.listen((value) {
        playing.value = value;
        _log('stream.playing=$value');
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        buffering.value = value;
        _log('stream.buffering=$value');
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((value) {
        position.value = value;
        if (!firstFrameReady.value &&
            value.inMilliseconds >= readyPositionThresholdMs) {
          firstFrameReady.value = true;
          _log('first frame ready by position: ${value.inMilliseconds}ms');
        }
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        duration.value = value;
        _log('stream.durationMs=${value.inMilliseconds}');
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((message) {
        _log('stream.error=$message');
        // preload 重试期间不设置 error.value，由 _waitForOpenResult 处理
        if (_preloading) {
          return;
        }
        error.value = message.isEmpty ? '视频播放失败' : message;
        opening.value = false;
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((completed) async {
        _log('stream.completed=$completed');
        if (completed) {
          await onCompleted();
        }
      }),
    );
  }
}
