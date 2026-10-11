import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';
import 'package:video_player/video_player.dart';

/// A [SoupVideoController] that can also change playback speed. soup_core's
/// interface has no speed API, so the v2 player carries its own.
abstract interface class SpeedControllable {
  Future<void> setSpeed(double speed);
}

class SpeedVideoControllerFactory implements SoupVideoControllerFactory {
  const SpeedVideoControllerFactory();

  @override
  SoupVideoController create(Uri uri, {Future<String>? subtitleVtt}) =>
      SpeedVideoController(uri, subtitleVtt: subtitleVtt);
}

class SpeedVideoController extends ChangeNotifier
    implements SoupVideoController, SpeedControllable {
  SpeedVideoController(Uri uri, {Future<String>? subtitleVtt})
    : _controller = VideoPlayerController.networkUrl(
        uri,
        closedCaptionFile: subtitleVtt?.then(WebVTTCaptionFile.new),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
          mixWithOthers: false,
        ),
      ) {
    _controller.addListener(_sync);
  }

  final VideoPlayerController _controller;
  SoupVideoValue _value = const SoupVideoValue();

  @override
  SoupVideoValue get value => _value;

  void _sync() {
    final s = _controller.value;
    _value = SoupVideoValue(
      initialized: s.isInitialized,
      playing: s.isPlaying,
      buffering: s.isBuffering,
      position: s.position,
      duration: s.duration,
      aspectRatio: s.aspectRatio <= 0 ? 16 / 9 : s.aspectRatio,
      caption: s.caption.text,
      error: s.errorDescription,
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setSpeed(double speed) => _controller.setPlaybackSpeed(speed);

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> close() async {
    _controller.removeListener(_sync);
    await _controller.dispose();
    dispose();
  }
}
