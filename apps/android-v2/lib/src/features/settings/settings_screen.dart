import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';

import '../../app_scope.dart';
import '../../data/device_settings.dart';
import '../../data/playback_prefs.dart';
import '../../form_factor.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/select_menu.dart';
import '../../ui/widgets/soup_button.dart';
import '../../ui/widgets/soup_text_field.dart';

/// Web `pages/settings.vue`: account, playback preferences, sign out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return TouchScaffold(
        section: NavSection.settings,
        title: 'Settings',
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(child: _body(context, touch: true)),
          ),
        ],
      );
    }
    return PageScaffold(
      section: NavSection.settings,
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SoupSpacing.gutter,
                  120,
                  SoupSpacing.gutter,
                  0,
                ),
                child: _body(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, {bool touch = false}) {
    final scope = SoupScope.of(context);
    final prefs = scope.prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Touch shows the title in its top bar.
          if (!touch) ...[
            Text(
              'Settings',
              style: SoupType.style(
                size: 52,
                weight: 800,
                letterSpacing: -2,
                height: 1,
              ),
            ),
            const SizedBox(height: 32),
          ],
          _Section(
            title: 'Account',
            children: [
              Text(
                scope.userLabel.isEmpty ? 'Signed in' : scope.userLabel,
                style: SoupType.style(size: 17, color: SoupColors.ink2),
              ),
              // TV picks servers from the nav's account menu.
              if (touch) _Servers(scope: scope),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Playback',
            children: [
              _Toggle(
                label: 'Autoplay next episode',
                detail:
                    'Count down and start the next episode when the credits begin.',
                value: prefs.autoplayNext,
                onChanged: (v) => prefs.update(autoplayNext: v),
                autofocus: !touch,
              ),
              const SizedBox(height: 18),
              _Toggle(
                label: 'Skip intros and recaps',
                detail:
                    'Jump past them automatically instead of showing a Skip button.',
                value: prefs.autoSkipIntros,
                onChanged: (v) => prefs.update(autoSkipIntros: v),
              ),
              const SizedBox(height: 24),
              _Picker<int?>(
                label: 'Default quality',
                value: prefs.maxBitrate,
                options: [
                  const SelectOption(null, 'Auto', detail: 'Best available'),
                  for (final q in PlaybackPrefs.qualityCaps)
                    SelectOption(q.bitrate, q.label, detail: q.detail),
                ],
                onChanged: (v) => prefs.update(maxBitrate: v),
              ),
              const SizedBox(height: 14),
              _Picker<String?>(
                label: 'Audio language',
                value: prefs.audioLanguage,
                options: [
                  const SelectOption(null, 'File default'),
                  for (final l in PlaybackPrefs.languages)
                    SelectOption(l.$1, l.$2),
                ],
                onChanged: (v) => prefs.update(audioLanguage: v),
              ),
              const SizedBox(height: 14),
              _Picker<String?>(
                label: 'Subtitle language',
                value: prefs.subtitleLanguage,
                options: [
                  const SelectOption(null, 'Off'),
                  for (final l in PlaybackPrefs.languages)
                    SelectOption(l.$1, l.$2),
                ],
                onChanged: (v) => prefs.update(subtitleLanguage: v),
              ),
              const SizedBox(height: 14),
              _Picker<String>(
                label: 'Subtitle size',
                value: prefs.subtitleSize,
                options: [
                  for (final z in PlaybackPrefs.subtitleSizes)
                    SelectOption(z.id, z.label),
                ],
                onChanged: (v) => prefs.update(subtitleSize: v),
              ),
            ],
          ),
          if (scope.device case final device?) ...[
            const SizedBox(height: 20),
            _DeviceSection(device: device),
          ],
          const SizedBox(height: 28),
          SoupButton(label: 'Sign out', onPressed: scope.onSignOut),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Soup roster servers with the current one checked; tap to switch.
class _Servers extends StatefulWidget {
  const _Servers({required this.scope});
  final SoupScope scope;

  @override
  State<_Servers> createState() => _ServersState();
}

class _ServersState extends State<_Servers> {
  String? _error;

  Future<void> _select(String id) async {
    final select = widget.scope.onSelectServer;
    if (select == null) return;
    setState(() => _error = null);
    final error = await select(id);
    if (mounted && error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final soup = widget.scope.soupAuth;
    if (soup == null || widget.scope.onSelectServer == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: soup,
      builder: (context, _) {
        final servers = soup.roster?.servers ?? const [];
        if (servers.length < 2) return const SizedBox.shrink();
        final current = soup.selectedServer?.id;
        final switching = soup.switchingServerId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'SERVER',
              style: SoupType.style(
                size: 12,
                weight: 800,
                color: SoupColors.muted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            for (final server in servers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  server.name,
                  style: SoupType.style(size: 16, weight: 600),
                ),
                trailing: switching == server.id
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SoupColors.ink,
                        ),
                      )
                    : server.id == current
                    ? const Icon(Icons.check_rounded, color: SoupColors.ok)
                    : null,
                onTap: switching == null ? () => _select(server.id) : null,
              ),
            if (_error != null)
              Text(
                _error!,
                style: SoupType.style(
                  size: 13,
                  weight: 600,
                  color: SoupColors.accent,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Name, audio output and detected capabilities for this device only.
class _DeviceSection extends StatefulWidget {
  const _DeviceSection({required this.device});
  final DeviceSettings device;

  @override
  State<_DeviceSection> createState() => _DeviceSectionState();
}

class _DeviceSectionState extends State<_DeviceSection> {
  late final _name = TextEditingController(text: widget.device.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _saveName() {
    final value = _name.text.trim();
    final device = widget.device;
    final custom = value.isEmpty || value == device.device.detectedName
        ? null
        : value;
    if (custom == device.customName) return;
    unawaited(device.update(customName: custom));
    if (custom == null) _name.text = device.device.detectedName;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final caps = device.device.capabilities;
    return ListenableBuilder(
      listenable: device,
      builder: (context, _) => _Section(
        title: 'This device',
        children: [
          SoupTextField(
            controller: _name,
            label: 'Device name',
            hint: device.device.detectedName,
            onSubmitted: _saveName,
          ),
          const SizedBox(height: 6),
          _Detail(
            'How this device appears in Jellyfin. Applies after Soup restarts.',
          ),
          const SizedBox(height: 18),
          _Picker<AudioOutputMode>(
            label: 'Audio output',
            value: device.audioOutput,
            options: [
              for (final o in DeviceSettings.audioOutputOptions)
                SelectOption(o.$1, o.$2, detail: o.$3),
            ],
            onChanged: (v) => device.update(audioOutput: v),
          ),
          const SizedBox(height: 6),
          _Detail(switch (device.audioOutput) {
            AudioOutputMode.auto =>
              'Plays what this device decodes or passes through; converts the rest to 5.1 Dolby Digital, or stereo when the output is stereo.',
            AudioOutputMode.stereo =>
              'The server downmixes every track to two channels.',
            AudioOutputMode.surround =>
              'For soundbars and streamers that take Dolby Digital 5.1. Other surround formats are converted to it, keeping the subwoofer channel.',
            AudioOutputMode.passthrough =>
              'For receivers that decode TrueHD and DTS. Soup sends them untouched.',
          }),
          const SizedBox(height: 18),
          _Detail('Detected: ${caps.platform}'),
          if (device.device.detectionError case final error?)
            _Detail('Using defaults; detection failed: $error'),
          if (caps.summary.isNotEmpty) _Detail('Video: ${caps.summary}'),
          _Detail('Audio passthrough: ${caps.passthroughSummary}'),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      style: SoupType.style(size: 14, color: SoupColors.muted, height: 1.35),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: SoupColors.surface,
      borderRadius: BorderRadius.circular(SoupRadii.panel),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: SoupType.style(
            size: 13,
            weight: 800,
            color: SoupColors.muted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: SoupType.style(size: 17, weight: 600)),
      ),
      SelectMenu<T>(
        value: value,
        options: options,
        onChanged: onChanged,
        surface: true,
      ),
    ],
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    radius: 14,
    scale: 1.0,
    onActivate: () => onChanged(!value),
    builder: (context, focused) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: focused ? SoupColors.elevated : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SoupType.style(size: 17, weight: 700)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: SoupType.style(
                    size: 14,
                    color: SoupColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 32,
            padding: const EdgeInsets.all(4),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? SoupColors.ok : const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
