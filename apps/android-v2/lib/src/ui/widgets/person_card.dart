import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import '../theme/soup_tokens.dart';
import 'catalog_image.dart';
import 'focusable.dart';

/// Round headshot with name (and optional role) underneath. Only the avatar
/// takes focus, so the ring is a circle around the photo; tapping anywhere on
/// the card opens the person's titles.
class PersonCard extends StatelessWidget {
  const PersonCard({required this.person, this.showRole = false, super.key});

  final Person person;
  final bool showRole;

  static const _size = 120.0;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final role = showRole ? (p.role ?? p.type) : null;
    void open() => openSearch(context, person: p);
    return GestureDetector(
      onTap: open,
      child: SizedBox(
        width: 130,
        child: Column(
          children: [
            Focusable(
              radius: _size / 2,
              onActivate: open,
              builder: (context, _) => ClipOval(
                child: SizedBox.square(
                  dimension: _size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: SoupColors.elevated,
                        alignment: Alignment.center,
                        child: Text(
                          initials(p.name),
                          style: SoupType.style(
                            size: 32,
                            weight: 800,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                      CatalogImage(image: p.image, maxWidth: 256),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SoupType.style(size: 15, weight: 700),
            ),
            if (role != null)
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SoupType.style(size: 13, color: SoupColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
