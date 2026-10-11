import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import '../soup_focus_policy.dart';
import '../theme/soup_tokens.dart';
import 'catalog_builder.dart';
import 'focusable.dart';
import 'glass.dart';

enum NavSection { home, library, search, settings, none }

/// Top navigation: wordmark, glass pill of Home + libraries, search, account.
class GlassNav extends StatelessWidget {
  const GlassNav({
    required this.section,
    this.libraryId,
    this.solid = false,
    this.activeFocusNode,
    super.key,
  });

  final NavSection section;
  final String? libraryId;

  /// Attached to the item for [section], so the page can focus it on Back.
  final FocusNode? activeFocusNode;

  /// Frosted canvas once the page has scrolled.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final scope = SoupScope.of(context);
    final bar = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SoupSpacing.gutter,
        vertical: 18,
      ),
      child: Row(
        children: [
          Text(
            'soup',
            style: SoupType.style(size: 30, weight: 800, letterSpacing: -1),
          ),
          Expanded(
            child: Center(
              child: CatalogBuilder<List<CatalogItem>>(
                load: (c) => c.libraries(),
                builder: (context, libraries, _) => Glass(
                  radius: 28,
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Tab(
                        'Home',
                        section == NavSection.home,
                        () => openHome(context),
                        autofocus: section == NavSection.home,
                        focusNode: section == NavSection.home
                            ? activeFocusNode
                            : null,
                      ),
                      if (libraries == null)
                        for (var i = 0; i < 2; i++)
                          Container(
                            width: 90,
                            height: 38,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0x14FFFFFF),
                              borderRadius: BorderRadius.circular(19),
                            ),
                          )
                      else
                        for (final lib in libraries)
                          _Tab(
                            lib.name,
                            section == NavSection.library &&
                                libraryId == lib.id,
                            () => openLibrary(context, lib),
                            focusNode:
                                section == NavSection.library &&
                                    libraryId == lib.id
                                ? activeFocusNode
                                : null,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _IconButton(
            icon: Icons.search_rounded,
            active: section == NavSection.search,
            onTap: () => openSearch(context),
            focusNode: section == NavSection.search ? activeFocusNode : null,
          ),
          const SizedBox(width: 12),
          _Avatar(
            label: scope.userLabel,
            active: section == NavSection.settings,
            focusNode: section == NavSection.settings ? activeFocusNode : null,
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? const Color(0xF20A0A0B) : Colors.transparent,
        gradient: solid
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
      ),
      child: FocusTraversalGroup(policy: SoupFocusPolicy(), child: bar),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(
    this.label,
    this.active,
    this.onTap, {
    this.autofocus = false,
    this.focusNode,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Focusable(
    focusNode: focusNode,
    scale: 1.0,
    radius: 19,
    onActivate: onTap,
    builder: (context, focused) => Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? SoupColors.ink
            : (focused ? const Color(0x26FFFFFF) : Colors.transparent),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Text(
        label,
        style: SoupType.style(
          size: 15,
          weight: active ? 800 : 600,
          color: active ? SoupColors.canvas : SoupColors.ink2,
        ),
      ),
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.focusNode,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Focusable(
    focusNode: focusNode,
    radius: 22,
    onActivate: onTap,
    builder: (context, focused) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active
            ? SoupColors.ink
            : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
        shape: BoxShape.circle,
        border: active ? null : Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Icon(
        icon,
        size: 22,
        color: active ? SoupColors.canvas : SoupColors.ink,
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.active, this.focusNode});
  final String label;
  final bool active;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Focusable(
    focusNode: focusNode,
    radius: 22,
    onActivate: () => _menu(context),
    builder: (context, focused) => Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: SoupColors.accent,
        shape: BoxShape.circle,
      ),
      child: Text(
        label.isEmpty ? '·' : label[0].toUpperCase(),
        style: SoupType.style(size: 18, weight: 800, color: SoupColors.canvas),
      ),
    ),
  );

  Future<void> _menu(BuildContext context) {
    final scope = SoupScope.of(context);
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (dialog) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 76, right: SoupSpacing.gutter),
          child: SizedBox(
            width: 280,
            child: Glass(
              strong: true,
              radius: SoupRadii.menu,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Text(
                      label.isEmpty ? initials('Soup') : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(size: 14, color: SoupColors.muted),
                    ),
                  ),
                  _MenuItem(
                    'Settings',
                    autofocus: true,
                    onTap: () {
                      Navigator.of(dialog).pop();
                      openSettings(context);
                    },
                  ),
                  _MenuItem(
                    'Sign out',
                    onTap: () {
                      Navigator.of(dialog).pop();
                      scope.onSignOut();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem(this.label, {required this.onTap, this.autofocus = false});
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    scale: 1.0,
    radius: 12,
    onActivate: onTap,
    builder: (context, focused) => Container(
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: focused ? const Color(0x26FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: SoupType.style(size: 17, weight: 600)),
    ),
  );
}
