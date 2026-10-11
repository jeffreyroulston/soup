import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/playback_prefs.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/select_menu.dart';
import '../../ui/widgets/soup_button.dart';

/// Web `pages/settings.vue`: account, server, playback preferences, sign out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SoupScope.of(context);
    final prefs = scope.prefs;
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
                child: ListenableBuilder(
                  listenable: prefs,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      _Section(
                        title: 'Account',
                        children: [
                          Text(
                            scope.userLabel.isEmpty
                                ? 'Signed in'
                                : scope.userLabel,
                            style: SoupType.style(
                              size: 17,
                              color: SoupColors.ink2,
                            ),
                          ),
                        ],
                      ),
                      if (scope.session != null) ...[
                        const SizedBox(height: 20),
                        _Section(
                          title: 'Server',
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: SoupColors.ok,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    scope.session!.serverUrl.toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SoupType.style(
                                      size: 17,
                                      color: SoupColors.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
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
                            autofocus: true,
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
                              const SelectOption(
                                null,
                                'Auto',
                                detail: 'Best available',
                              ),
                              for (final q in PlaybackPrefs.qualityCaps)
                                SelectOption(q.$1, q.$2, detail: q.$3),
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
                        ],
                      ),
                      const SizedBox(height: 28),
                      SoupButton(label: 'Sign out', onPressed: scope.onSignOut),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
