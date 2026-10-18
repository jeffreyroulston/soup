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
import 'soup_wordmark.dart';

enum NavSection { home, library, myStuff, search, settings, none }

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
          const SoupWordmark(size: 30),
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
                      _Tab(
                        'My Stuff',
                        section == NavSection.myStuff,
                        () => openFavourites(context),
                        focusNode: section == NavSection.myStuff
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
            : (focused ? SoupColors.glassFocused : SoupColors.glass),
        shape: BoxShape.circle,
        border: active ? null : Border.all(color: SoupColors.faint),
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
              child: _AccountMenu(
                label: label,
                scope: scope,
                onSettings: () {
                  Navigator.of(dialog).pop();
                  openSettings(context);
                },
                onSignOut: () {
                  Navigator.of(dialog).pop();
                  scope.onSignOut();
                },
                onSwitched: () {
                  if (dialog.mounted) Navigator.of(dialog).pop();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Account label, Soup servers (a picker when there's more than one), then
/// Settings and Sign out, like the web account menu.
class _AccountMenu extends StatefulWidget {
  const _AccountMenu({
    required this.label,
    required this.scope,
    required this.onSettings,
    required this.onSignOut,
    required this.onSwitched,
  });
  final String label;
  final SoupScope scope;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final VoidCallback onSwitched;

  @override
  State<_AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<_AccountMenu> {
  String? _error;

  Future<void> _select(String serverId) async {
    final select = widget.scope.onSelectServer;
    if (select == null) return;
    setState(() => _error = null);
    final error = await select(serverId);
    if (!mounted) return;
    if (error == null) {
      widget.onSwitched();
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final soup = widget.scope.soupAuth;
    return ListenableBuilder(
      listenable: soup ?? const _NoChanges(),
      builder: (context, _) {
        final servers = soup?.roster?.servers ?? const [];
        final current = soup?.selectedServer;
        final switching = soup?.switchingServerId;
        final currentName =
            current?.name ?? widget.scope.session?.serverUrl.host ?? '';
        final picker =
            servers.length > 1 && widget.scope.onSelectServer != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Text(
                widget.label.isEmpty ? initials('Soup') : widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SoupType.style(size: 14, color: SoupColors.muted),
              ),
            ),
            if (picker) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: Text(
                  'SERVER',
                  style: SoupType.style(
                    size: 12,
                    weight: 800,
                    color: SoupColors.muted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              for (final server in servers)
                _MenuItem(
                  server.name,
                  autofocus: server.id == current?.id,
                  leading: switching == server.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SoupColors.ink,
                          ),
                        )
                      : _Dot(active: server.id == current?.id),
                  onTap: switching == null ? () => _select(server.id) : () {},
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Text(
                    _error!,
                    style: SoupType.style(
                      size: 13,
                      weight: 600,
                      color: SoupColors.accent,
                    ),
                  ),
                ),
              const _Divider(),
            ] else if (currentName.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(
                  children: [
                    const _Dot(active: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        currentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: 17,
                          weight: 600,
                          color: SoupColors.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const _Divider(),
            ],
            _MenuItem('Settings', autofocus: !picker, onTap: widget.onSettings),
            _MenuItem('Sign out', onTap: widget.onSignOut),
          ],
        );
      },
    );
  }
}

/// Stand-in listenable when there's no Soup sign-in to watch.
class _NoChanges implements Listenable {
  const _NoChanges();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: active ? SoupColors.ok : const Color(0x26FFFFFF),
      shape: BoxShape.circle,
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
    color: SoupColors.faint,
  );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem(
    this.label, {
    required this.onTap,
    this.autofocus = false,
    this.leading,
  });
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    scale: 1.0,
    // Rows sit flush against each other and the panel edge, so the ring is
    // drawn inside the row instead of around it.
    ring: false,
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
        border: Border.all(
          color: focused ? SoupColors.ink : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 14, child: Center(child: leading)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(size: 17, weight: 600),
            ),
          ),
        ],
      ),
    ),
  );
}
