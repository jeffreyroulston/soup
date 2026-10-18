import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:soup_core/soup_core.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../form_factor.dart';
import '../../platform.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/glass.dart';
import '../../utils/media.dart';
import 'playback_logic.dart';
import 'playback_panels.dart';
import 'playback_widgets.dart';
import 'speed_controller.dart';
import 'touch_widgets.dart';

/// Public sample used when the app runs in mock mode (no Jellyfin server).
const mockSampleUrl =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

enum _Panel { settings, chapters, episodes }

/// Full-screen player in the web player's style, drivable entirely by D-pad.
/// On touch devices it locks to landscape, toggles its chrome on tap, seeks
/// on double-tap and scrubs by dragging the seek bar.
///
/// [subtitleIndex]: null = use saved preference, -1 = off, otherwise a stream
/// index. [audioIndex]: null = default/preference. [maxBitrate]: null = saved
/// preference, 0 = Auto (no cap), otherwise a cap in bits/s.
///
/// Needs a [SoupScope] above it. Routes pushed from a screen do not inherit
/// the scope, so wrap them (see [PlaybackScreen.route]).
class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({
    required this.item,
    this.startTicks = 0,
    this.audioIndex,
    this.subtitleIndex,
    this.maxBitrate,
    this.controllerFactory = const SpeedVideoControllerFactory(),
    super.key,
  });

  final CatalogItem item;
  final int startTicks;
  final int? audioIndex;
  final int? subtitleIndex;
  final int? maxBitrate;
  final SoupVideoControllerFactory controllerFactory;

  /// A route that carries [scope] so the player can find its dependencies.
  static Route<void> route(
    SoupScope scope,
    CatalogItem item, {
    int startTicks = 0,
    int? audioIndex,
    int? subtitleIndex,
    int? maxBitrate,
    SoupVideoControllerFactory controllerFactory =
        const SpeedVideoControllerFactory(),
  }) => PageRouteBuilder<void>(
    opaque: true,
    pageBuilder: (_, _, _) => SoupScope(
      catalog: scope.catalog,
      prefs: scope.prefs,
      api: scope.api,
      session: scope.session,
      userLabel: scope.userLabel,
      onSignOut: scope.onSignOut,
      child: PlaybackScreen(
        item: item,
        startTicks: startTicks,
        audioIndex: audioIndex,
        subtitleIndex: subtitleIndex,
        maxBitrate: maxBitrate,
        controllerFactory: controllerFactory,
      ),
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen>
    with WidgetsBindingObserver {
  late final SoupScope _scope;
  late CatalogItem _item = widget.item;

  PlaybackBridge? _bridge;
  JellyfinPlaybackPlan? _plan;
  SoupVideoController? _controller;
  JellyfinPlayMethod _method = JellyfinPlayMethod.directPlay;
  JellyfinSubtitleTrack? _subtitle;
  int? _audioIndex;
  int? _maxBitrate;
  double _speed = 1;
  bool _optionsResolved = false;
  bool _fellBack = false;

  bool _loading = true;
  String? _error;
  bool _disposed = false;

  List<MediaSegment> _segments = const [];
  List<SkipRange> _skips = const [];
  Duration _skipsForDuration = Duration.zero;
  final _autoSkipped = <SkipRange>{};
  List<CatalogItem> _episodes = const [];
  CatalogItem? _next;

  // chrome / focus
  bool _chrome = true;
  _Panel? _panel;
  Timer? _hideTimer;
  final _rootFocus = FocusNode(debugLabel: 'playback root');
  final _seekFocus = FocusNode(debugLabel: 'playback seek');
  final _playFocus = FocusNode(debugLabel: 'playback play');
  final _settingsFocus = FocusNode(debugLabel: 'playback settings');
  final _chaptersFocus = FocusNode(debugLabel: 'playback chapters');
  final _episodesFocus = FocusNode(debugLabel: 'playback episodes');

  // touch
  late final bool _touch;
  Duration? _scrub; // seek-bar drag preview
  Duration? _scrubFrom; // where that drag started
  int _flashSide = 0; // -1 back, 1 forward: double-tap feedback
  int _flashSeconds = 0; // seconds stacked by repeated taps on that side
  Timer? _flashTimer;
  bool _fill = false; // crop the picture to fill the screen
  bool _locked = false; // controls locked against stray touches
  bool _lockHint = false;
  Timer? _lockTimer;

  // seeking / reporting
  Duration? _pendingSeek;
  Duration _lastReported = Duration.zero;
  Timer? _reportDebounce;
  bool? _reportedPlaying; // playing state Jellyfin last heard
  Timer? _pausedPing;
  Duration? _retryFrom; // where Try again picks up

  // trickplay
  final _sheets = <int, Future<Uint8List?>>{};
  bool _seekPreview = false; // TV: thumbnail above the seek bar after a seek
  Timer? _seekPreviewTimer;

  // next episode
  bool _nextActive = false;
  bool _nextDismissed = false;
  bool _endedHandled = false;
  int _countdown = 10;
  Timer? _countdownTimer;

  SoupVideoController? get _c => _controller;
  JellyfinApi? get _api => _scope.api;
  JellyfinSession? get _session => _scope.session;
  bool get _mock => _scope.isMock;

  @override
  void initState() {
    super.initState();
    _scope = context.getInheritedWidgetOfExactType<SoupScope>()!;
    _touch = FormFactor.read(context).isTouch;
    if (_touch) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  // ── loading ──────────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final startAt =
        _retryFrom ?? Duration(microseconds: widget.startTicks ~/ 10);
    try {
      // Every await below can outlive the screen (Back while loading), so
      // each one checks _disposed: _shutdown has already run by then and
      // won't see anything opened afterwards.
      await _enrichItem();
      if (_disposed) return;
      unawaited(_loadSegments());
      unawaited(_loadSiblings());
      if (_mock) {
        await _loadSample(startAt);
        return;
      }
      final api = _api!;
      final session = _session!;
      _bridge ??= PlaybackBridge(
        api.transport,
        session,
        api.authenticatedHeaders(session),
      );
      final plan = await api.getPlaybackPlan(
        session,
        toJellyfinItem(_item),
        startAt: startAt,
        profile: _scope.deviceProfile,
      );
      if (_disposed) return;
      await _bridge!.start();
      if (_disposed) {
        await _bridge!.close();
        return;
      }
      _plan = plan;
      _resolveOptions(plan);
      final wantsTranscode = _audioIndex != null || _maxBitrate != null;
      if (!wantsTranscode && plan.directUri != null) {
        try {
          await _load(
            plan.directMethod ?? JellyfinPlayMethod.directPlay,
            startAt,
          );
        } on Object {
          if (_disposed) return;
          await _load(JellyfinPlayMethod.transcode, startAt);
        }
      } else {
        await _load(JellyfinPlayMethod.transcode, startAt);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is JellyfinApiException
            ? error.message
            : 'Could not start playback. $error';
      });
    }
  }

  /// List queries omit chapters (and some streams); fetch the full item once.
  Future<void> _enrichItem() async {
    // Shelf/list items carry MediaStreams but never Chapters, so only skip
    // the fetch when chapters are already here.
    if (_item.chapters.isNotEmpty) return;
    try {
      final full = await _scope.catalog.item(_item.id);
      if (mounted) _item = full;
    } on Object {
      // Playback works without track metadata.
    }
  }

  void _resolveOptions(JellyfinPlaybackPlan plan) {
    if (_optionsResolved) return;
    _optionsResolved = true;
    final prefs = _scope.prefs;
    _maxBitrate = switch (widget.maxBitrate) {
      null => prefs.maxBitrate,
      0 => null,
      final cap => cap,
    };
    if (widget.audioIndex != null) {
      _audioIndex = widget.audioIndex;
    } else {
      final wanted = preferredAudioStream(_item, prefs.audioLanguage);
      final fallback = defaultAudioStream(_item);
      if (wanted != null && wanted.index != fallback?.index) {
        _audioIndex = wanted.index;
      }
    }
    final int? subtitleIndex = switch (widget.subtitleIndex) {
      -1 => null,
      final int index => index,
      null => preferredSubtitleStream(_item, prefs.subtitleLanguage)?.index,
    };
    _subtitle = subtitleIndex == null
        ? null
        : plan.subtitles.where((t) => t.index == subtitleIndex).firstOrNull;
  }

  Uri _transcodeUri() {
    final plan = _plan!;
    final base =
        plan.transcodeUri ??
        manualTranscodeUri(_api!, _session!, plan, _scope.deviceProfile);
    return withTranscodeOptions(
      base,
      audioIndex: _audioIndex,
      maxBitrate: _maxBitrate,
    );
  }

  Future<void> _loadSample(Duration startAt) async {
    if (!await _swapController(Uri.parse(mockSampleUrl), startAt)) return;
    _method = JellyfinPlayMethod.directPlay;
    if (!mounted) return;
    setState(() => _loading = false);
    _restartHide();
  }

  Future<void> _load(JellyfinPlayMethod method, Duration startAt) async {
    final plan = _plan!;
    final upstream = method == JellyfinPlayMethod.transcode
        ? _transcodeUri()
        : plan.directUri;
    if (upstream == null) {
      throw const JellyfinApiException('No playback source is available.');
    }
    Future<String>? vtt;
    final subtitle = _subtitle;
    if (subtitle != null) {
      vtt = _api!
          .getSubtitle(_session!, subtitle)
          .catchError((Object _) => 'WEBVTT\n');
    }
    final current = await _swapController(
      _bridge!.localUriFor(upstream),
      startAt,
      vtt: vtt,
    );
    // A newer load (another option change) took over; it reports instead.
    if (!current) return;
    _method = method;
    if (!mounted) return;
    setState(() => _loading = false);
    _restartHide();
    unawaited(
      _api!
          .reportPlaybackStarted(
            _session!,
            plan,
            method: method,
            position: startAt,
          )
          .catchError((Object _) {}),
    );
  }

  /// Swaps in a player for [uri]. False when it was abandoned: the screen
  /// closed, or a newer load replaced it while it was starting.
  Future<bool> _swapController(
    Uri uri,
    Duration startAt, {
    Future<String>? vtt,
  }) async {
    final old = _controller;
    if (old != null) {
      old.removeListener(_playerChanged);
      await old.close();
    }
    if (_disposed) return false;
    final controller = widget.controllerFactory.create(uri, subtitleVtt: vtt);
    _controller = controller;
    _endedHandled = false;
    controller.addListener(_playerChanged);
    Future<bool> abandoned() async {
      if (_disposed) {
        controller.removeListener(_playerChanged);
        await controller.close();
        return true;
      }
      // A newer load already replaced, and closed, this player.
      return !identical(_controller, controller);
    }

    try {
      await controller.initialize();
      if (await abandoned()) return false;
      if (startAt > Duration.zero) await controller.seekTo(startAt);
      if (await abandoned()) return false;
      if (_speed != 1 && controller is SpeedControllable) {
        await (controller as SpeedControllable).setSpeed(_speed);
        if (await abandoned()) return false;
      }
      await controller.play();
    } on Object {
      // Closed under a newer load: its failure is that load's business.
      if (await abandoned()) return false;
      rethrow;
    }
    return !await abandoned();
  }

  /// Try again from where playback got to, as a new play session.
  Future<void> _retry() async {
    final plan = _plan;
    final controller = _c;
    final position = _pendingSeek ?? controller?.value.position;
    if (position != null && position > Duration.zero) _retryFrom = position;
    if (plan != null && controller != null && !_mock) {
      unawaited(
        _api!
            .reportPlaybackStopped(
              _session!,
              plan,
              method: _method,
              position: position ?? Duration.zero,
            )
            .catchError((Object _) {}),
      );
    }
    _fellBack = false;
    _reportedPlaying = null;
    await _initialize();
  }

  int _reloads = 0;

  /// Rebuild the player at the current position with the current options.
  Future<void> _reload() async {
    final controller = _c;
    final plan = _plan;
    if (controller == null || plan == null) return;
    final position = _pendingSeek ?? controller.value.position;
    setState(() => _loading = true);
    final load = ++_reloads;
    try {
      final wantsTranscode = _audioIndex != null || _maxBitrate != null;
      await _load(
        wantsTranscode || plan.directUri == null
            ? JellyfinPlayMethod.transcode
            : (plan.directMethod ?? JellyfinPlayMethod.directPlay),
        position,
      );
    } on Object catch (error) {
      // A later option change superseded this one; its result stands.
      if (!mounted || load != _reloads) return;
      setState(() {
        _loading = false;
        _error = error is JellyfinApiException
            ? error.message
            : 'Could not change playback. $error';
      });
    }
  }

  Future<void> _loadSegments() async {
    try {
      final segments = await _scope.catalog.mediaSegments(_item.id);
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _skipsForDuration = Duration.zero; // recompute
      });
    } on Object {
      // No markers.
    }
  }

  Future<void> _loadSiblings() async {
    if (_item.type != 'Episode' || _item.seriesId == null) return;
    try {
      final eps = await _scope.catalog.episodes(_item.seriesId!, null);
      if (!mounted) return;
      final index = eps.indexWhere((e) => e.id == _item.id);
      setState(() {
        _episodes = eps;
        _next = index >= 0 && index + 1 < eps.length ? eps[index + 1] : null;
      });
    } on Object {
      // No episode navigation.
    }
  }

  // ── player events ────────────────────────────────────────────────────────
  void _playerChanged() {
    if (!mounted || _disposed) return;
    final controller = _c;
    if (controller == null) return;
    final v = controller.value;

    if (v.error != null && !_loading && _error == null) {
      unawaited(_fallbackToTranscode());
      return;
    }

    if (_skipsForDuration != v.duration && v.duration > Duration.zero) {
      _skipsForDuration = v.duration;
      _skips = skipRanges(
        _segments,
        _item.chapters,
        durationSeconds: v.duration.inMilliseconds / 1000,
      );
    }
    final seconds = v.position.inMilliseconds / 1000;
    if (_scope.prefs.autoSkipIntros) {
      for (final r in _skips) {
        if ((r.kind == SkipKind.intro || r.kind == SkipKind.recap) &&
            r.contains(seconds) &&
            _autoSkipped.add(r)) {
          unawaited(_skipTo(r));
        }
      }
    }
    _maybeActivateNext(v, seconds);
    final plan = _plan;
    // Report every play/pause however it happened (remote keys, the OS
    // pausing on background, the end of the stream), not just the button.
    if (plan != null && v.initialized && v.playing != _reportedPlaying) {
      _reportedPlaying = v.playing;
      _lastReported = v.position;
      unawaited(_report(paused: !v.playing));
      _pausedPing?.cancel();
      // Jellyfin drops sessions, and their transcodes, that go quiet.
      _pausedPing = v.playing
          ? null
          : Timer.periodic(
              const Duration(seconds: 30),
              (_) => unawaited(_report(paused: true)),
            );
    }
    if (plan != null &&
        (v.position - _lastReported).abs() >= const Duration(seconds: 10)) {
      _lastReported = v.position;
      unawaited(_report(paused: !v.playing));
    }
    if (v.initialized &&
        v.duration > Duration.zero &&
        !v.playing &&
        v.position >= v.duration - const Duration(milliseconds: 400)) {
      _onEnded();
    }
    // Keep the chrome from auto-hiding while paused; resume the timer on play.
    if (v.playing) {
      if (_hideTimer == null && _chrome && _panel == null) _restartHide();
    } else {
      _hideTimer?.cancel();
      _hideTimer = null;
    }
    setState(() {});
  }

  Future<void> _fallbackToTranscode() async {
    final plan = _plan;
    if (_fellBack || plan == null || _method == JellyfinPlayMethod.transcode) {
      setState(() => _error = _c?.value.error ?? 'Playback failed.');
      return;
    }
    _fellBack = true;
    final position = _c?.value.position ?? Duration.zero;
    setState(() => _loading = true);
    try {
      await _load(JellyfinPlayMethod.transcode, position);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not start playback. $error';
        });
      }
    }
  }

  Future<void> _report({required bool paused}) async {
    final plan = _plan;
    final controller = _c;
    if (plan == null || controller == null || _mock) return;
    try {
      await _api!.reportPlaybackProgress(
        _session!,
        plan,
        method: _method,
        position: _pendingSeek ?? controller.value.position,
        paused: paused,
      );
    } on Object {
      // Playback continues if presence reporting temporarily fails.
    }
  }

  // ── next episode ─────────────────────────────────────────────────────────
  void _maybeActivateNext(SoupVideoValue v, double seconds) {
    if (_next == null ||
        _nextActive ||
        _nextDismissed ||
        !_scope.prefs.autoplayNext ||
        v.duration <= Duration.zero) {
      return;
    }
    final total = v.duration.inMilliseconds / 1000;
    final inCredits = _skips.any(
      (r) => r.kind == SkipKind.outro && r.contains(seconds),
    );
    if (inCredits || total - seconds <= 25) _startCountdown(10);
  }

  void _startCountdown(int from) {
    _nextActive = true;
    _countdown = from;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      // Paused before the end: hold the count until playback resumes.
      final v = _c?.value;
      if (!_endedHandled && v != null && !v.playing) return;
      if (_countdown <= 1) {
        t.cancel();
        _playNext();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _dismissNext() {
    _countdownTimer?.cancel();
    setState(() {
      _nextActive = false;
      _nextDismissed = true;
    });
    _rootFocus.requestFocus();
  }

  void _onEnded() {
    if (_endedHandled) return;
    _endedHandled = true;
    if (_next != null && _scope.prefs.autoplayNext && !_nextDismissed) {
      if (!_nextActive) {
        _startCountdown(5);
      }
      return;
    }
    _exit();
  }

  void _playNext() {
    final next = _next;
    if (next == null) return;
    _goTo(next);
  }

  void _goTo(CatalogItem episode, {bool resume = false}) {
    _countdownTimer?.cancel();
    Navigator.of(context).pushReplacement(
      PlaybackScreen.route(
        _scope,
        episode,
        startTicks: resume ? episode.playbackPositionTicks : 0,
        controllerFactory: widget.controllerFactory,
      ),
    );
  }

  void _exit() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── controls ─────────────────────────────────────────────────────────────
  Future<void> _togglePlayback() async {
    final c = _c;
    if (c == null) return;
    if (c.value.playing) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  void _seekBy(Duration delta) {
    final c = _c;
    if (c == null) return;
    final duration = c.value.duration;
    final base = _pendingSeek ?? c.value.position;
    var target = base + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _pendingSeek = target;
    if (!_touch) _flashSeekPreview();
    setState(() {});
    unawaited(
      c.seekTo(target).whenComplete(() {
        if (_pendingSeek == target) {
          _pendingSeek = null;
          if (mounted) setState(() {});
        }
      }),
    );
    _reportDebounce?.cancel();
    _reportDebounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_report(paused: !c.value.playing)),
    );
    _restartHide();
  }

  ({String sourceId, Trickplay info})? get _trickplay =>
      _mock ? null : _item.trickplayFor(_plan?.mediaSourceId);

  /// Sprite sheets fetched this session (a few, each ~1 MB); failures retry.
  Future<Uint8List?> _trickplaySheet(int index) {
    final cached = _sheets.remove(index);
    if (cached != null) return _sheets[index] = cached;
    final trickplay = _trickplay;
    if (trickplay == null) return Future.value(null);
    final future = _scope.catalog.trickplaySheet(
      _item.id,
      trickplay.sourceId,
      trickplay.info.width,
      index,
    );
    _sheets[index] = future;
    if (_sheets.length > 6) _sheets.remove(_sheets.keys.first);
    unawaited(
      future.then((bytes) {
        if (bytes == null && identical(_sheets[index], future)) {
          _sheets.remove(index);
        }
      }),
    );
    return future;
  }

  /// TV: show the thumbnail above the seek bar until seeking pauses.
  void _flashSeekPreview() {
    if (_trickplay == null) return;
    _seekPreview = true;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _seekPreview = false);
    });
  }

  /// [panel] (the TV seek glass) with the trickplay thumbnail floating above
  /// the seek bar's thumb while seeking.
  Widget _withSeekPreview(SoupVideoValue v, Duration position, Widget panel) {
    final trickplay = _trickplay;
    if (trickplay == null || !_seekPreview) return panel;
    const width = 200.0;
    const inset = 20.0; // the glass's horizontal padding
    final info = trickplay.info;
    final height = info.height * width / info.width;
    final total = v.duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) => Stack(
        clipBehavior: Clip.none,
        children: [
          panel,
          Positioned(
            left: (inset + (c.maxWidth - inset * 2) * fraction - width / 2)
                .clamp(0.0, c.maxWidth - width),
            top: -(height + 12),
            child: IgnorePointer(
              child: TrickplayPreview(
                info: info,
                position: position,
                loadSheet: _trickplaySheet,
                width: width,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _skipTo(SkipRange range) async {
    final c = _c;
    if (c == null) return;
    final duration = c.value.duration;
    var end = Duration(milliseconds: (range.end * 1000).round());
    if (duration > Duration.zero &&
        end >= duration - const Duration(seconds: 1)) {
      if (_next != null && _scope.prefs.autoplayNext) return _playNext();
      end = duration - const Duration(milliseconds: 500);
    }
    await c.seekTo(end);
    unawaited(_report(paused: !c.value.playing));
  }

  /// Touch: tapping the picture toggles the chrome (or closes a panel).
  /// Right after a double-tap seek, taps on the same side keep seeking.
  void _onVideoTap(Offset at, double width) {
    if (_locked) return _showLockHint();
    if (_panel != null) return _closePanel();
    if (_flashSide != 0 && _sideOf(at, width) == _flashSide) {
      return _tapSeek(_flashSide);
    }
    if (_chrome) {
      _hideTimer?.cancel();
      _hideTimer = null;
      setState(() => _chrome = false);
    } else {
      _showChrome();
    }
  }

  /// Touch: double-tap the left/right half to seek ∓10 seconds.
  void _onVideoDoubleTap(Offset position, double width) {
    if (_locked) return _showLockHint();
    _tapSeek(_sideOf(position, width));
  }

  int _sideOf(Offset at, double width) => at.dx < width / 2 ? -1 : 1;

  void _tapSeek(int side) {
    _seekBy(Duration(seconds: 10 * side));
    _flashTimer?.cancel();
    setState(() {
      _flashSeconds = side == _flashSide ? _flashSeconds + 10 : 10;
      _flashSide = side;
    });
    _flashTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _flashSide = 0;
          _flashSeconds = 0;
        });
      }
    });
  }

  void _lock() {
    _hideTimer?.cancel();
    _hideTimer = null;
    setState(() {
      _locked = true;
      _chrome = false;
    });
    _showLockHint();
  }

  void _unlock() {
    _lockTimer?.cancel();
    setState(() {
      _locked = false;
      _lockHint = false;
    });
    _showChrome();
  }

  void _showLockHint() {
    _lockTimer?.cancel();
    setState(() => _lockHint = true);
    _lockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockHint = false);
    });
  }

  void _onScrub(Duration target) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _scrubFrom ??= _pendingSeek ?? _c?.value.position ?? Duration.zero;
    setState(() => _scrub = target);
  }

  void _onScrubEnd() {
    final target = _scrub;
    if (target == null) return;
    _scrub = null;
    _scrubFrom = null;
    final c = _c;
    if (c == null) return;
    _seekBy(target - (_pendingSeek ?? c.value.position));
  }

  SkipRange? _activeSkip(Duration position) {
    final seconds = position.inMilliseconds / 1000;
    return _skips.where((r) => r.contains(seconds)).firstOrNull;
  }

  Future<void> _setSpeed(double speed) async {
    _speed = speed;
    final c = _c;
    if (c is SpeedControllable) await (c as SpeedControllable).setSpeed(speed);
    if (mounted) setState(() {});
  }

  void _setSubtitle(JellyfinSubtitleTrack? track) {
    if (track == _subtitle) return;
    _subtitle = track;
    _closePanel();
    unawaited(_reload());
  }

  void _setAudio(MediaStreamInfo stream) {
    final def = defaultAudioStream(_item);
    final next = stream.index == def?.index ? null : stream.index;
    if (next == _audioIndex) return;
    _audioIndex = next;
    _closePanel();
    unawaited(_reload());
  }

  void _setQuality(int? bitrate) {
    if (bitrate == _maxBitrate) return;
    _maxBitrate = bitrate;
    _closePanel();
    unawaited(_reload());
  }

  // ── chrome ───────────────────────────────────────────────────────────────
  void _restartHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    final playing = _c?.value.playing ?? false;
    if (!playing ||
        _panel != null ||
        _loading ||
        _error != null ||
        _nextActive) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), _hideChrome);
  }

  void _showChrome({FocusNode? focus}) {
    if (_locked) return;
    if (!_chrome) setState(() => _chrome = true);
    _restartHide();
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  void _hideChrome() {
    if (!mounted || _panel != null) return;
    _hideTimer = null;
    setState(() => _chrome = false);
    _rootFocus.requestFocus();
  }

  void _openPanel(_Panel panel) {
    _hideTimer?.cancel();
    setState(() {
      _panel = panel;
      _chrome = true;
    });
  }

  void _closePanel() {
    final panel = _panel;
    if (panel == null) return;
    setState(() => _panel = null);
    _restartHide();
    if (_touch) return;
    final opener = switch (panel) {
      _Panel.settings => _settingsFocus,
      _Panel.chapters => _chaptersFocus,
      _Panel.episodes => _episodesFocus,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) opener.requestFocus();
    });
  }

  void _onBack() {
    if (_locked) return _showLockHint();
    if (_nextActive) return _dismissNext();
    if (_panel != null) return _closePanel();
    _exit();
  }

  KeyEventResult _rootKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_panel == null) _restartHide();

    // Media keys work from anywhere.
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        unawaited(_togglePlayback());
        _showChrome();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPlay) {
        unawaited(_c?.play());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPause) {
        unawaited(_c?.pause());
        _showChrome();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaFastForward) {
        _seekBy(const Duration(seconds: 30));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaRewind) {
        _seekBy(const Duration(seconds: -10));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackNext && _next != null) {
        _playNext();
        return KeyEventResult.handled;
      }
    }
    // The rest only applies when nothing in the chrome or a panel has focus,
    // and not over the error, whose buttons own the D-pad.
    if (_panel != null || _error != null || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }

    final isSelect =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isSelect && event is KeyDownEvent) {
      final skip = _activeSkip(_c?.value.position ?? Duration.zero);
      if (skip != null && !_chrome) {
        unawaited(_skipTo(skip));
      } else {
        unawaited(_togglePlayback());
        _showChrome(focus: _playFocus);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -10));
      _showChrome(focus: _seekFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 10));
      _showChrome(focus: _seekFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) _showChrome(focus: _playFocus);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── lifecycle ────────────────────────────────────────────────────────────
  Future<void> _shutdown() async {
    final controller = _c;
    final plan = _plan;
    if (controller != null) {
      if (plan != null && !_mock) {
        try {
          await _api!.reportPlaybackStopped(
            _session!,
            plan,
            method: _method,
            position: _pendingSeek ?? controller.value.position,
          );
        } on Object {
          // Closing the player must not be blocked by presence reporting.
        }
      }
      controller.removeListener(_playerChanged);
      await controller.close();
    }
    await _bridge?.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The app may never come back from the background, so Jellyfin hears
    // the position now rather than at the next 10s report.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_report(paused: true));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_touch) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _flashTimer?.cancel();
    _lockTimer?.cancel();
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _reportDebounce?.cancel();
    _seekPreviewTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pausedPing?.cancel();
    // Once Jellyfin has the stop position, refetch so resume points and
    // watched state on the screens underneath are current.
    final catalog = _scope.catalog;
    unawaited(_shutdown().whenComplete(catalog.refresh));
    for (final n in [
      _rootFocus,
      _seekFocus,
      _playFocus,
      _settingsFocus,
      _chaptersFocus,
      _episodesFocus,
    ]) {
      n.dispose();
    }
    super.dispose();
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final controller = _c;
    final v = controller?.value ?? const SoupVideoValue();
    final position = _scrub ?? _pendingSeek ?? v.position;
    final skip = _activeSkip(position);
    // Touch sheets cover the chrome; TV side panels sit beside it.
    final showChrome = _touch
        ? _chrome && _panel == null && !_locked
        : _chrome || _panel != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: videoBackdrop,
        body: Focus(
          focusNode: _rootFocus,
          onKeyEvent: _rootKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (v.initialized && controller != null)
                if (_touch && _fill)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: 1080 * v.aspectRatio,
                      height: 1080,
                      child: controller.buildView(),
                    ),
                  )
                else
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: controller.buildView(),
                    ),
                  ),
              if (_touch)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      Offset? doubleTapAt;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) =>
                            _onVideoTap(d.localPosition, constraints.maxWidth),
                        onDoubleTapDown: (d) => doubleTapAt = d.localPosition,
                        onDoubleTap: () => _onVideoDoubleTap(
                          doubleTapAt ?? Offset.zero,
                          constraints.maxWidth,
                        ),
                      );
                    },
                  ),
                ),
              if (_flashSide != 0 && _touch)
                _TapSeekRipple(side: _flashSide, seconds: _flashSeconds),
              if (_flashSide != 0 && !_touch)
                Align(
                  alignment: _flashSide < 0
                      ? const Alignment(-0.6, 0)
                      : const Alignment(0.6, 0),
                  child: IgnorePointer(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _flashSide < 0
                                ? PhosphorIconsRegular.arrowCounterClockwise
                                : PhosphorIconsRegular.clockClockwise,
                            size: 28,
                          ),
                          Text(
                            _flashSide < 0 ? '−10s' : '+10s',
                            style: SoupType.style(size: 13, weight: 800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (v.caption.isNotEmpty)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 80,
                  right: 80,
                  bottom: showChrome
                      ? (_touch ? 136 : 190)
                      : (_touch ? 24 : 40),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xA6000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        v.caption,
                        key: const ValueKey('playback-caption'),
                        textAlign: TextAlign.center,
                        style: SoupType.style(size: 22, weight: 700),
                      ),
                    ),
                  ),
                ),
              if (_touch && _scrub != null)
                const IgnorePointer(
                  child: ColoredBox(color: Color(0x73000000)),
                ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showChrome ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Column(
                    children: [
                      SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xB3000000), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      Spacer(),
                      SizedBox(
                        height: 240,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xCC000000)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ExcludeFocus(
                excluding: !showChrome || _panel != null,
                child: IgnorePointer(
                  ignoring: !showChrome,
                  child: AnimatedOpacity(
                    key: const ValueKey('playback-chrome'),
                    opacity: showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: SafeArea(
                      child: _touch
                          ? _touchChrome(v, position)
                          : _chromeBody(v, position),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: _touch ? 24 : 40,
                bottom: showChrome ? (_touch ? 136 : 176) : (_touch ? 24 : 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_nextActive && _next != null)
                      NextEpisodeCard(
                        title: _next!.name,
                        seconds: _countdown,
                        onPlayNow: _playNext,
                        onCancel: _dismissNext,
                      )
                    else if (skip != null &&
                        _panel == null &&
                        !_locked &&
                        _scrub == null)
                      SkipButton(
                        key: const ValueKey('skip-button'),
                        label: skip.kind.label,
                        onPressed: () => unawaited(_skipTo(skip)),
                      ),
                  ],
                ),
              ),
              if (_touch && !showChrome && _panel == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: _MiniProgress(
                      fraction: v.duration <= Duration.zero
                          ? 0
                          : (position.inMilliseconds /
                                    v.duration.inMilliseconds)
                                .clamp(0.0, 1.0),
                    ),
                  ),
                ),
              if (_locked && _lockHint)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: PlayerPill(
                          key: const ValueKey('unlock-button'),
                          icon: PhosphorIconsRegular.lockSimpleOpen,
                          label: 'Screen locked · Tap to unlock',
                          onPressed: _unlock,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_panel != null && _touch) ...[
                const IgnorePointer(
                  child: ColoredBox(color: Color(0x8C000000)),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _panel == _Panel.episodes
                          ? double.infinity
                          : 680,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
                    ),
                    child: _touchPanelBody(),
                  ),
                ),
              ] else if (_panel != null)
                Positioned(right: 24, top: 24, bottom: 24, child: _panelBody()),
              // With the chrome up, the play button shows the spinner instead.
              if ((_loading || v.buffering) && _error == null && !showChrome)
                const IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: SoupColors.ink,
                        backgroundColor: Color(0x33FFFFFF),
                      ),
                    ),
                  ),
                ),
              if (_error case final error?)
                PlaybackError(error: error, onRetry: _retry, onClose: _exit),
            ],
          ),
        ),
      ),
    );
  }

  (String, String) _titles() {
    final isEpisode = _item.type == 'Episode';
    final title = isEpisode ? (_item.seriesName ?? _item.name) : _item.name;
    final subtitle = isEpisode
        ? [
            episodeCodeOf(_item),
            _item.name,
          ].where((s) => s.isNotEmpty).join(' · ')
        : (_item.productionYear?.toString() ?? '');
    return (title, subtitle);
  }

  List<double> _chapterFractions(SoupVideoValue v) => [
    if (v.duration > Duration.zero)
      for (final c in _item.chapters)
        if (c.startTicks > 0)
          (c.startTicks / 10 / v.duration.inMicroseconds).clamp(0.0, 1.0),
  ];

  String? _chapterAt(Duration position) {
    String? name;
    for (final (i, c) in _item.chapters.indexed) {
      if (Duration(microseconds: c.startTicks ~/ 10) > position) break;
      name = c.name.isEmpty ? 'Chapter ${i + 1}' : c.name;
    }
    return name;
  }

  Widget _transport(SoupVideoValue v) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ChromeButton(
        icon: PhosphorIconsRegular.arrowCounterClockwise,
        label: 'Back 10 seconds',
        size: 56,
        iconSize: 28,
        onPressed: () => _seekBy(const Duration(seconds: -10)),
      ),
      const SizedBox(width: 28),
      ChromeButton(
        key: const ValueKey('play-pause-button'),
        icon: v.playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
        label: v.playing ? 'Pause' : 'Play',
        size: 76,
        iconSize: 36,
        focusNode: _playFocus,
        autofocus: true,
        filled: _touch,
        busy: (_loading || v.buffering) && _error == null,
        onPressed: () => unawaited(_togglePlayback()),
      ),
      const SizedBox(width: 28),
      ChromeButton(
        icon: PhosphorIconsRegular.clockClockwise,
        label: 'Forward 10 seconds',
        size: 56,
        iconSize: 28,
        onPressed: () => _seekBy(const Duration(seconds: 10)),
      ),
    ],
  );

  /// Phone layout: title bar on top, transport in the middle, edge-to-edge
  /// seek bar and a row of labelled actions along the bottom.
  Widget _touchChrome(SoupVideoValue v, Duration position) {
    final (title, subtitle) = _titles();
    final scrubFrom = _scrubFrom;
    final scrubbing = _scrub != null && scrubFrom != null;
    final chapter = _chapterAt(position);
    final remaining = v.duration > position
        ? v.duration - position
        : Duration.zero;
    final timeStyle = SoupType.style(
      size: 12,
      weight: 700,
      color: SoupColors.ink2,
    );
    final delta = scrubbing ? position - scrubFrom : Duration.zero;
    final trickplay = _trickplay;

    Widget fade(Widget child) => AnimatedOpacity(
      opacity: scrubbing ? 0 : 1,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(ignoring: scrubbing, child: child),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Column(
        children: [
          fade(
            Row(
              children: [
                ChromeButton(
                  icon: PhosphorIconsRegular.caretDown,
                  label: 'Close',
                  onPressed: _exit,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('playback-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: 17,
                          weight: 800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SoupType.style(
                            size: 13,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!_loading || _plan != null || _mock) ...[
                  MethodDot(method: _method),
                  const SizedBox(width: 8),
                ],
                ChromeButton(
                  key: const ValueKey('lock-button'),
                  icon: PhosphorIconsRegular.lockSimple,
                  label: 'Lock controls',
                  iconSize: 20,
                  onPressed: _lock,
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: scrubbing
                  ? Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xB3282828),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0x1AFFFFFF)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${delta.isNegative ? '−' : '+'}${formatTime(delta.abs())}',
                        key: const ValueKey('scrub-delta'),
                        style: SoupType.style(size: 14, weight: 800),
                      ),
                    )
                  : _transport(v),
            ),
          ),
          Row(
            children: [
              Text(
                formatTime(position),
                key: const ValueKey('playback-position'),
                style: timeStyle,
              ),
              Expanded(
                child: Text(
                  scrubbing ? '' : (chapter ?? ''),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: 12,
                    weight: 600,
                    color: SoupColors.muted,
                  ),
                ),
              ),
              Text('−${formatTime(remaining)}', style: timeStyle),
            ],
          ),
          TouchSeekBar(
            position: position,
            duration: v.duration,
            chapterFractions: _chapterFractions(v),
            onScrub: _onScrub,
            onScrubEnd: _onScrubEnd,
            scrubFrom: scrubbing ? scrubFrom : null,
            bubble: ScrubBubble(
              time: formatTime(position),
              chapter: chapter,
              preview: trickplay == null
                  ? null
                  : TrickplayPreview(
                      info: trickplay.info,
                      position: position,
                      loadSheet: _trickplaySheet,
                      width: TouchSeekBar.bubbleWidth,
                    ),
            ),
          ),
          const SizedBox(height: 2),
          fade(
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        PlayerPill(
                          key: const ValueKey('settings-button'),
                          icon: PhosphorIconsRegular.slidersHorizontal,
                          label: 'Settings',
                          onPressed: () => _openPanel(_Panel.settings),
                        ),
                        if (_item.chapters.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          PlayerPill(
                            key: const ValueKey('chapters-button'),
                            icon: PhosphorIconsRegular.listBullets,
                            label: 'Chapters',
                            onPressed: () => _openPanel(_Panel.chapters),
                          ),
                        ],
                        if (_episodes.length > 1) ...[
                          const SizedBox(width: 8),
                          PlayerPill(
                            key: const ValueKey('episodes-button'),
                            icon: PhosphorIconsRegular.stackSimple,
                            label: 'Episodes',
                            onPressed: () => _openPanel(_Panel.episodes),
                          ),
                        ],
                        const SizedBox(width: 8),
                        PlayerPill(
                          key: const ValueKey('fill-button'),
                          icon: _fill
                              ? PhosphorIconsRegular.cornersIn
                              : PhosphorIconsRegular.cornersOut,
                          label: _fill ? 'Fit' : 'Fill',
                          onPressed: () {
                            setState(() => _fill = !_fill);
                            _restartHide();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (_next != null) ...[
                  const SizedBox(width: 8),
                  PlayerPill(
                    key: const ValueKey('next-button'),
                    label: 'Next episode',
                    trailingIcon: PhosphorIconsFill.skipForward,
                    primary: true,
                    onPressed: _playNext,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chromeBody(SoupVideoValue v, Duration position) {
    final (title, subtitle) = _titles();
    final fractions = _chapterFractions(v);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        children: [
          Row(
            children: [
              ChromeButton(
                icon: PhosphorIconsRegular.x,
                label: 'Close',
                size: 48,
                onPressed: _exit,
              ),
            ],
          ),
          Expanded(child: Center(child: _transport(v))),
          _withSeekPreview(
            v,
            position,
            Glass(
              strong: true,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SeekBar(
                    focusNode: _seekFocus,
                    position: position,
                    duration: v.duration,
                    chapterFractions: fractions,
                    onSeekBy: _seekBy,
                    onScrub: _touch ? _onScrub : null,
                    onScrubEnd: _touch ? _onScrubEnd : null,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatTime(position),
                        key: const ValueKey('playback-position'),
                        style: SoupType.style(
                          size: 12,
                          weight: 600,
                          color: SoupColors.ink2,
                        ),
                      ),
                      Text(
                        formatTime(v.duration),
                        style: SoupType.style(
                          size: 12,
                          weight: 600,
                          color: SoupColors.ink2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              key: const ValueKey('playback-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(
                                size: 20,
                                weight: 800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SoupType.style(
                                  size: 13,
                                  color: SoupColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_next != null)
                        ChromeButton(
                          icon: PhosphorIconsRegular.skipForward,
                          label: 'Next episode',
                          onPressed: _playNext,
                        ),
                      if (_item.chapters.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ChromeButton(
                          key: const ValueKey('chapters-button'),
                          icon: PhosphorIconsRegular.listBullets,
                          label: 'Chapters',
                          focusNode: _chaptersFocus,
                          onPressed: () => _openPanel(_Panel.chapters),
                        ),
                      ],
                      if (_episodes.length > 1) ...[
                        const SizedBox(width: 8),
                        ChromeButton(
                          key: const ValueKey('episodes-button'),
                          icon: PhosphorIconsRegular.stackSimple,
                          label: 'Episodes',
                          focusNode: _episodesFocus,
                          onPressed: () => _openPanel(_Panel.episodes),
                        ),
                      ],
                      const SizedBox(width: 8),
                      ChromeButton(
                        key: const ValueKey('settings-button'),
                        icon: PhosphorIconsRegular.gear,
                        label: 'Settings',
                        focusNode: _settingsFocus,
                        onPressed: () => _openPanel(_Panel.settings),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelBody() {
    switch (_panel!) {
      case _Panel.settings:
        return _settingsPanel();
      case _Panel.chapters:
        return _chaptersPanel();
      case _Panel.episodes:
        return _episodesPanel();
    }
  }

  Widget _settingsPanel() {
    final plan = _plan;
    final audio = _item.streamsOf(StreamKind.audio);
    final defaultAudio = defaultAudioStream(_item);
    final hasImageSubs = _item
        .streamsOf(StreamKind.subtitle)
        .any((s) => !s.isTextSubtitle);
    return SidePanel(
      title: 'Settings',
      onClose: _closePanel,
      header: !_loading || _plan != null || _mock
          ? MethodPill(method: _method)
          : null,
      footer: _method == JellyfinPlayMethod.transcode
          ? 'Transcoding: the server converts this stream.'
          : null,
      sections: [
        PanelSection(
          title: 'Speed',
          chips: true,
          options: [
            for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              PanelOption(
                label: '${s == s.truncate() ? s.toInt() : s}×',
                selected: _speed == s,
                onSelect: () => unawaited(_setSpeed(s)),
              ),
          ],
        ),
        PanelSection(
          title: 'Subtitles',
          note: hasImageSubs ? "Image-based subtitles can't be shown." : null,
          options: [
            PanelOption(
              label: 'Off',
              selected: _subtitle == null,
              onSelect: () => _setSubtitle(null),
            ),
            for (final t in plan?.subtitles ?? const <JellyfinSubtitleTrack>[])
              PanelOption(
                label: t.label,
                selected: _subtitle == t,
                onSelect: () => _setSubtitle(t),
              ),
          ],
        ),
        if (audio.length > 1 && plan != null)
          PanelSection(
            title: 'Audio',
            note:
                'Switching away from the default track transcodes the stream.',
            options: [
              for (final s in audio)
                PanelOption(
                  label: s.label,
                  selected: (_audioIndex ?? defaultAudio?.index) == s.index,
                  onSelect: () => _setAudio(s),
                ),
            ],
          ),
        if (plan != null)
          PanelSection(
            title: 'Quality',
            options: [
              PanelOption(
                label: 'Auto',
                detail: 'Best available',
                selected: _maxBitrate == null,
                onSelect: () => _setQuality(null),
              ),
              for (final q in qualityCapsFor(_item))
                PanelOption(
                  label: q.label,
                  detail: q.detail,
                  selected: _maxBitrate == q.bitrate,
                  onSelect: () => _setQuality(q.bitrate),
                ),
            ],
          ),
      ],
    );
  }

  Widget _chaptersPanel() => SidePanel(
    title: 'Chapters',
    onClose: _closePanel,
    sections: [
      PanelSection(
        title: '${_item.chapters.length} chapters',
        options: _chapterOptions(),
      ),
    ],
  );

  List<PanelOption> _chapterOptions() {
    final position = _pendingSeek ?? _c?.value.position ?? Duration.zero;
    final chapters = _item.chapters;
    var current = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (Duration(microseconds: chapters[i].startTicks ~/ 10) <= position) {
        current = i;
      }
    }
    return [
      for (var i = 0; i < chapters.length; i++)
        PanelOption(
          label: chapters[i].name.isEmpty
              ? 'Chapter ${i + 1}'
              : chapters[i].name,
          detail: formatTime(
            Duration(microseconds: chapters[i].startTicks ~/ 10),
          ),
          selected: i == current,
          onSelect: () {
            final start = Duration(microseconds: chapters[i].startTicks ~/ 10);
            _closePanel();
            unawaited(_c?.seekTo(start));
          },
        ),
    ];
  }

  List<CatalogItem> _seasonEpisodes() {
    final season = _item.seasonId;
    return [
      for (final e in _episodes)
        if (season == null || e.seasonId == season) e,
    ];
  }

  String get _seasonTitle {
    final seasonNumber = _item.parentIndexNumber;
    return seasonNumber == null ? 'This season' : 'Season $seasonNumber';
  }

  void _pickEpisode(CatalogItem e) {
    if (e.id == _item.id) return _closePanel();
    _goTo(e, resume: e.playbackPositionTicks >= 100000000);
  }

  Widget _episodesPanel() {
    final list = _seasonEpisodes();
    return SidePanel(
      title: 'Episodes',
      onClose: _closePanel,
      sections: [
        PanelSection(
          title: _seasonTitle,
          options: [
            for (final e in list)
              PanelOption(
                label:
                    '${e.indexNumber ?? ''}${e.indexNumber == null ? '' : '. '}${e.name}',
                detail: e.runTimeTicks == null
                    ? null
                    : formatTime(Duration(microseconds: e.runTimeTicks! ~/ 10)),
                selected: e.id == _item.id,
                onSelect: () => _pickEpisode(e),
              ),
          ],
        ),
      ],
    );
  }

  // ── touch sheets ─────────────────────────────────────────────────────────
  Widget _touchPanelBody() => switch (_panel!) {
    _Panel.settings => _touchSettings(),
    _Panel.chapters => PlayerSheet(
      key: const ValueKey('panel-Chapters'),
      onClose: _closePanel,
      header: Text(
        'Chapters',
        style: SoupType.style(size: 16, weight: 800, letterSpacing: -0.3),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [for (final o in _chapterOptions()) PanelRow(option: o)],
      ),
    ),
    _Panel.episodes => EpisodesDrawer(
      title: _seasonTitle,
      episodes: _seasonEpisodes(),
      currentId: _item.id,
      onSelect: _pickEpisode,
      onClose: _closePanel,
    ),
  };

  /// Audio (with subtitles), Speed and Quality tabs in one sheet.
  Widget _touchSettings() {
    final plan = _plan;
    final audio = _item.streamsOf(StreamKind.audio);
    final defaultAudio = defaultAudioStream(_item);
    final hasImageSubs = _item
        .streamsOf(StreamKind.subtitle)
        .any((s) => !s.isTextSubtitle);

    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Text(
        text,
        style: SoupType.style(size: 12, color: SoupColors.muted),
      ),
    );
    Widget scroll(List<Widget> children) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 14),
      children: children,
    );

    final audioTab = scroll([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetLabel('Audio'),
                if (audio.isEmpty)
                  PanelRow(
                    option: PanelOption(
                      label: 'Default',
                      selected: true,
                      onSelect: () {},
                    ),
                  ),
                for (final s in audio)
                  PanelRow(
                    option: PanelOption(
                      label: s.label,
                      selected: (_audioIndex ?? defaultAudio?.index) == s.index,
                      enabled: plan != null && audio.length > 1,
                      onSelect: () => _setAudio(s),
                    ),
                  ),
                if (audio.length > 1 && plan != null)
                  note('Other tracks transcode the stream.'),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetLabel('Subtitles'),
                PanelRow(
                  option: PanelOption(
                    label: 'Off',
                    selected: _subtitle == null,
                    onSelect: () => _setSubtitle(null),
                  ),
                ),
                for (final t
                    in plan?.subtitles ?? const <JellyfinSubtitleTrack>[])
                  PanelRow(
                    option: PanelOption(
                      label: t.label,
                      selected: _subtitle == t,
                      onSelect: () => _setSubtitle(t),
                    ),
                  ),
                if (hasImageSubs) note("Image-based subtitles can't be shown."),
              ],
            ),
          ),
        ],
      ),
    ]);

    final speedTab = scroll([
      const SheetLabel('Playback speed'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final (i, s) in const [
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              2.0,
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: PanelChip(
                  option: PanelOption(
                    label: '${s == s.truncate() ? s.toInt() : s}×',
                    selected: _speed == s,
                    onSelect: () => unawaited(_setSpeed(s)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);

    final qualityTab = scroll([
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            MethodDot(method: _method),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _method == JellyfinPlayMethod.transcode
                    ? 'The server converts this stream.'
                    : 'Playing the original file.',
                style: SoupType.style(size: 12, color: SoupColors.muted),
              ),
            ),
          ],
        ),
      ),
      PanelRow(
        option: PanelOption(
          label: 'Auto',
          detail: 'Best available',
          selected: _maxBitrate == null,
          onSelect: () => _setQuality(null),
        ),
      ),
      for (final q in qualityCapsFor(_item))
        PanelRow(
          option: PanelOption(
            label: q.label,
            detail: q.detail,
            selected: _maxBitrate == q.bitrate,
            onSelect: () => _setQuality(q.bitrate),
          ),
        ),
    ]);

    return SettingsSheet(
      onClose: _closePanel,
      tabs: [
        ('Audio', audioTab),
        ('Speed', speedTab),
        if (plan != null) ('Quality', qualityTab),
      ],
    );
  }
}

/// Touch double-tap feedback: a lit half-ellipse on the tapped side with the
/// seconds stacked so far.
class _TapSeekRipple extends StatelessWidget {
  const _TapSeekRipple({required this.side, required this.seconds});
  final int side;
  final int seconds;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, c) {
        final edge = Radius.elliptical(c.maxWidth * 0.18, c.maxHeight * 0.6);
        return Align(
          alignment: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: c.maxWidth * 0.42,
            height: c.maxHeight,
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: side < 0
                  ? BorderRadius.horizontal(right: edge)
                  : BorderRadius.horizontal(left: edge),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  side < 0
                      ? PhosphorIconsFill.rewind
                      : PhosphorIconsFill.fastForward,
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  '${side < 0 ? '−' : '+'}$seconds s',
                  key: const ValueKey('tap-seek-label'),
                  style: SoupType.style(size: 20, weight: 800),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Thin progress line along the bottom edge while the chrome is hidden.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) => Container(
    height: 3,
    color: const Color(0x26FFFFFF),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: fraction,
      child: const ColoredBox(color: SoupColors.accent),
    ),
  );
}
