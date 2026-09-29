import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/formatters.dart';

/// Network video player with custom play/pause + seek controls.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.url,
    this.onLoadError,
  });

  final String url;

  /// Called when the stream fails to load (e.g. expired signed URL).
  final VoidCallback? onLoadError;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late VideoPlayerController _controller;
  Object? _error;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _error = null;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize(_controller);
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (!mounted || controller != _controller) return;
      setState(() {});
    } catch (e) {
      if (!mounted || controller != _controller) return;
      setState(() => _error = e);
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      final old = _controller;
      _init();
      old.dispose();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final value = _controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      if (value.position >= value.duration && value.duration > Duration.zero) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTapSurface() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _retry() {
    final old = _controller;
    setState(_init);
    old.dispose();
    widget.onLoadError?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
              const SizedBox(height: 8),
              const Text(
                "Couldn't load the video",
                style: TextStyle(color: Colors.white),
              ),
              TextButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final aspect = value.isInitialized && value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
        return AspectRatio(
          aspectRatio: aspect,
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (value.isInitialized)
                  GestureDetector(
                    onTap: _onTapSurface,
                    child: VideoPlayer(_controller),
                  )
                else
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (value.isInitialized && value.isBuffering)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (value.isInitialized)
                  IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _Controls(
                        value: value,
                        onTogglePlay: _togglePlay,
                        onSeek: (position) {
                          _controller.seekTo(position);
                          if (value.isPlaying) _scheduleHide();
                        },
                        onBackgroundTap: _onTapSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.value,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onBackgroundTap,
  });

  final VideoPlayerValue value;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs <= 0 ? 0.0 : maxMs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBackgroundTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black54],
            begin: Alignment.center,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: IconButton.filled(
                iconSize: 40,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                ),
                onPressed: onTogglePlay,
                icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Row(
                children: [
                  Text(
                    formatClock(position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: maxMs <= 0 ? 0 : posMs.toDouble(),
                        max: maxMs <= 0 ? 1 : maxMs,
                        onChanged: maxMs <= 0
                            ? null
                            : (v) => onSeek(Duration(milliseconds: v.round())),
                      ),
                    ),
                  ),
                  Text(
                    formatClock(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
