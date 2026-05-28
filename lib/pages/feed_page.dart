import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../controllers/feed_controller.dart';
import '../utils/duration_text.dart';

class FeedPage extends GetView<FeedController> {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        switch (controller.screenState.value) {
          case FeedScreenState.loading:
            return _StatusView(
              title: '正在查找服务',
              message: '正在后台扫描 192.168 网段的视频服务',
              loading: true,
              onRetry: controller.retryDiscovery,
            );
          case FeedScreenState.error:
            return _StatusView(
              title: '连接失败',
              message: controller.errorMessage.value,
              onRetry: controller.retryDiscovery,
            );
          case FeedScreenState.empty:
            return _StatusView(
              title: '没有可播放的视频',
              message: '服务端列表为空，请检查后端视频目录',
              onRetry: controller.retryDiscovery,
            );
          case FeedScreenState.ready:
            return PageView.builder(
              controller: controller.pageController,
              scrollDirection: Axis.vertical,
              itemCount: controller.videos.length,
              onPageChanged: (index) {
                controller.onPageChanged(index);
              },
              itemBuilder: (context, index) {
                return _VideoPageItem(index: index);
              },
            );
        }
      }),
    );
  }
}

class _VideoPageItem extends StatelessWidget {
  const _VideoPageItem({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FeedController>(
      id: 'video_$index',
      builder: (controller) {
        final item = controller.videos[index];
        final player = controller.playerAt(index);

        return Obx(() {
          final isCurrent = controller.currentIndex.value == index;
          final effectiveCover =
              player?.coverFrame.value ?? controller.coverFrameAt(index);
          final showInitialLoading = player == null ||
              !player.firstFrameReady.value ||
              player.opening.value;
          final showLoadingCover = isCurrent &&
              (controller.isPageTransitioning.value || showInitialLoading);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isCurrent ? controller.toggleChrome : null,
            onDoubleTap: isCurrent ? controller.togglePlayPause : null,
            onLongPress: isCurrent ? controller.toggleOrientationMode : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: player == null
                      ? const SizedBox.shrink()
                      : isCurrent
                          ? SizedBox.expand(
                              child: _VideoViewport(
                                player: player,
                                isCurrent: isCurrent,
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
                if (showLoadingCover)
                  Positioned.fill(
                    child: _VideoLoadingCover(
                      title: item.title,
                      coverFrame: effectiveCover,
                    ),
                  ),
                if (player?.error.value.isNotEmpty == true)
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Text(
                          player!.error.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                if (isCurrent)
                  _CurrentVideoOverlay(index: index, title: item.title),
              ],
            ),
          );
        });
      },
    );
  }
}

class _VideoLoadingCover extends StatelessWidget {
  const _VideoLoadingCover({required this.title, required this.coverFrame});

  final String title;
  final Uint8List? coverFrame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _LoadingCoverBackground(coverFrame: coverFrame),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFF6A3D)),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingCoverBackground extends StatelessWidget {
  const _LoadingCoverBackground({required this.coverFrame});

  final Uint8List? coverFrame;

  @override
  Widget build(BuildContext context) {
    final bytes = coverFrame;
    if (bytes == null || bytes.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1B1B), Color(0xFF131313), Color(0xFF090909)],
          ),
        ),
      );
    }

    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B1B1B), Color(0xFF131313), Color(0xFF090909)],
            ),
          ),
        );
      },
    );
  }
}

class _CurrentVideoOverlay extends StatelessWidget {
  const _CurrentVideoOverlay({required this.index, required this.title});

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FeedController>();

    return GetBuilder<FeedController>(
      id: 'current_controls',
      builder: (_) {
        final player = controller.playerAt(index);
        if (player == null) {
          return const SizedBox.shrink();
        }

        return Obx(() {
          final chromeVisible = controller.showChrome.value;
          final showTitle = chromeVisible && !controller.isLandscapeMode.value;
          final showPlayButton = chromeVisible &&
              !player.playing.value &&
              !player.opening.value &&
              !player.buffering.value &&
              player.error.value.isEmpty;

          return Stack(
            fit: StackFit.expand,
            children: [
              if (showTitle)
                Positioned(
                  top: 20,
                  left: 24,
                  right: 24,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (showPlayButton)
                Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: controller.togglePlayPause,
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (chromeVisible)
                Positioned(
                  right: 0,
                  top: 80,
                  bottom: 96,
                  child: _RightSideQuickPanel(
                    currentIndex: index,
                    totalCount: controller.videos.length,
                    showSwitchButtons: GetPlatform.isWindows,
                    onPrevious: controller.goToPreviousVideo,
                    onNext: controller.goToNextVideo,
                  ),
                ),
              if (chromeVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: _ProgressBar(player: player),
                ),
            ],
          );
        });
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player});

  final ManagedVideoPlayer player;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FeedController>();

    return Obx(() {
      final duration = player.duration.value;
      final actualPosition = player.position.value;
      final dragValue = controller.draggingPositionMs.value;
      final shownPosition = dragValue == null
          ? actualPosition
          : Duration(milliseconds: dragValue.round());
      final totalMs = duration.inMilliseconds.toDouble();
      final maxValue = totalMs <= 0 ? 1.0 : totalMs;
      final progressMs = (dragValue?.clamp(0, maxValue) ??
              actualPosition.inMilliseconds
                  .clamp(0, maxValue.toInt())
                  .toDouble())
          .toDouble();
      final ratio =
          maxValue <= 0 ? 0.0 : (progressMs / maxValue).clamp(0.0, 1.0);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SeekBar(
                  currentValue: progressMs,
                  ratio: ratio,
                  maxValue: maxValue,
                  onStart: controller.onSeekStart,
                  onUpdate: controller.onSeekUpdate,
                  onEnd: controller.onSeekEnd,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatDuration(shownPosition),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      formatDuration(duration),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _VideoViewport extends StatelessWidget {
  const _VideoViewport({required this.player, required this.isCurrent});

  final ManagedVideoPlayer player;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final videoController = player.videoController;
    if (videoController == null) {
      return const SizedBox.shrink();
    }

    return Video(
      controller: videoController,
      fit: BoxFit.contain,
      controls: NoVideoControls,
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.currentValue,
    required this.ratio,
    required this.maxValue,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final double currentValue;
  final double ratio;
  final double maxValue;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;

  double _positionToValue(double dx, double width) {
    if (width <= 0) {
      return 0;
    }
    final progress = (dx / width).clamp(0.0, 1.0);
    return progress * maxValue;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final thumbCenter = (width * ratio).clamp(6.0, width - 6.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final value = _positionToValue(details.localPosition.dx, width);
              onStart(value);
              onEnd(value);
            },
            onHorizontalDragStart: (details) {
              onStart(_positionToValue(details.localPosition.dx, width));
            },
            onHorizontalDragUpdate: (details) {
              onUpdate(_positionToValue(details.localPosition.dx, width));
            },
            onHorizontalDragEnd: (_) {
              onEnd(currentValue);
            },
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6A3D),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbCenter - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6A3D),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF6A3D,
                          ).withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RightSideQuickPanel extends StatelessWidget {
  const _RightSideQuickPanel({
    required this.currentIndex,
    required this.totalCount,
    required this.showSwitchButtons,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int totalCount;
  final bool showSwitchButtons;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showSwitchButtons)
          _WindowsVideoSwitchGroup(
            hasPrevious: currentIndex > 0,
            hasNext: currentIndex < totalCount - 1,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        if (showSwitchButtons) const SizedBox(height: 10),
        _UpcomingVideoList(currentIndex: currentIndex, totalCount: totalCount),
      ],
    );
  }
}

class _UpcomingVideoList extends StatelessWidget {
  const _UpcomingVideoList({
    required this.currentIndex,
    required this.totalCount,
  });

  final int currentIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FeedController>();
    final lastIndex = (currentIndex + 10).clamp(0, totalCount - 1);
    final items = <int>[for (var i = currentIndex + 1; i <= lastIndex; i++) i];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, idx) {
            final itemIndex = items[idx];
            final item = controller.videos[itemIndex];

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => controller.jumpToIndex(itemIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WindowsVideoSwitchGroup extends StatelessWidget {
  const _WindowsVideoSwitchGroup({
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool hasPrevious;
  final bool hasNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WindowsVideoSwitchButton(
              icon: Icons.keyboard_arrow_up_rounded,
              label: '上一个',
              enabled: hasPrevious,
              onTap: onPrevious,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                width: 32,
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            _WindowsVideoSwitchButton(
              icon: Icons.keyboard_arrow_down_rounded,
              label: '下一个',
              enabled: hasNext,
              onTap: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowsVideoSwitchButton extends StatelessWidget {
  const _WindowsVideoSwitchButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : Colors.white38;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onTap() : null,
        child: SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    required this.message,
    required this.onRetry,
    this.loading = false,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0D0D), Color(0xFF181818), Color(0xFF080808)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: CircularProgressIndicator(color: Color(0xFFFF6A3D)),
                  ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: loading ? null : onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6A3D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('重新扫描'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
