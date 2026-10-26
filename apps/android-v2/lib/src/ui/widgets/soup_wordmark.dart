import 'package:flutter/widgets.dart';

import '../theme/soup_tokens.dart';

/// The "fill line" wordmark: Manrope ExtraBold outlines with the o filled to
/// the line in [accent]. [size] matches the font size of the old text logo.
/// Outline data comes from docs/branding/generate.py.
class SoupWordmark extends StatelessWidget {
  const SoupWordmark({
    this.size = 30,
    this.color = SoupColors.ink,
    this.accent = SoupColors.accent,
    super.key,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'soup',
    image: true,
    child: CustomPaint(
      size: Size(_Glyphs.width * size, _Glyphs.height * size),
      painter: _WordmarkPainter(color, accent),
    ),
  );
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.color, this.accent);

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    canvas
      ..scale(size.height / _Glyphs.height)
      ..translate(-_Glyphs.left, -_Glyphs.top)
      ..drawPath(_Glyphs._sGlyph, ink)
      ..drawPath(_Glyphs._uGlyph, ink)
      ..drawPath(_Glyphs._pGlyph, ink)
      ..save()
      ..clipRect(const Rect.fromLTRB(-1, -2, 9, _Glyphs.level))
      ..drawPath(_Glyphs._oGlyph, ink)
      ..restore()
      ..clipRect(const Rect.fromLTRB(-1, _Glyphs.level, 9, 2))
      ..drawPath(_Glyphs._oGlyph, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      old.color != color || old.accent != accent;
}

/// Em-normalised outlines, y down, baseline at 0.
abstract final class _Glyphs {
  static const left = 0.04;
  static const top = -0.555;
  static const width = 2.234;
  static const height = 0.795;

  /// The fill line through the o, just below its optical centre.
  static const level = -0.2529;

  static final _sGlyph = Path()
    ..moveTo(0.281, 0.015)
    ..quadraticBezierTo(0.179, 0.015, 0.1163, -0.0312)
    ..quadraticBezierTo(0.0535, -0.0775, 0.04, -0.162)
    ..lineTo(0.179, -0.183)
    ..quadraticBezierTo(0.1875, -0.145, 0.2167, -0.1235)
    ..quadraticBezierTo(0.246, -0.102, 0.291, -0.102)
    ..quadraticBezierTo(0.328, -0.102, 0.348, -0.1163)
    ..quadraticBezierTo(0.368, -0.1305, 0.368, -0.156)
    ..quadraticBezierTo(0.368, -0.172, 0.36, -0.1817)
    ..quadraticBezierTo(0.352, -0.1915, 0.3242, -0.201)
    ..quadraticBezierTo(0.2965, -0.2105, 0.238, -0.226)
    ..quadraticBezierTo(0.172, -0.243, 0.1325, -0.264)
    ..quadraticBezierTo(0.093, -0.285, 0.0755, -0.3142)
    ..quadraticBezierTo(0.058, -0.3435, 0.058, -0.385)
    ..quadraticBezierTo(0.058, -0.437, 0.0845, -0.4753)
    ..quadraticBezierTo(0.111, -0.5135, 0.1593, -0.5343)
    ..quadraticBezierTo(0.2075, -0.555, 0.273, -0.555)
    ..quadraticBezierTo(0.3365, -0.555, 0.3855, -0.5355)
    ..quadraticBezierTo(0.4345, -0.516, 0.4647, -0.48)
    ..quadraticBezierTo(0.495, -0.444, 0.502, -0.395)
    ..lineTo(0.363, -0.37)
    ..quadraticBezierTo(0.3595, -0.4, 0.337, -0.4175)
    ..quadraticBezierTo(0.3145, -0.435, 0.276, -0.438)
    ..quadraticBezierTo(0.2385, -0.4405, 0.2157, -0.428)
    ..quadraticBezierTo(0.193, -0.4155, 0.193, -0.392)
    ..quadraticBezierTo(0.193, -0.378, 0.2028, -0.3685)
    ..quadraticBezierTo(0.2125, -0.359, 0.2432, -0.349)
    ..quadraticBezierTo(0.274, -0.339, 0.337, -0.323)
    ..quadraticBezierTo(0.3985, -0.307, 0.4358, -0.2858)
    ..quadraticBezierTo(0.473, -0.2645, 0.49, -0.2347)
    ..quadraticBezierTo(0.507, -0.205, 0.507, -0.163)
    ..quadraticBezierTo(0.507, -0.08, 0.447, -0.0325)
    ..quadraticBezierTo(0.387, 0.015, 0.281, 0.015)
    ..close();

  static final _oGlyph = Path()
    ..moveTo(0.82, 0.015)
    ..quadraticBezierTo(0.7385, 0.015, 0.677, -0.0215)
    ..quadraticBezierTo(0.6155, -0.058, 0.5813, -0.1222)
    ..quadraticBezierTo(0.547, -0.1865, 0.547, -0.27)
    ..quadraticBezierTo(0.547, -0.3545, 0.582, -0.4188)
    ..quadraticBezierTo(0.617, -0.483, 0.6785, -0.519)
    ..quadraticBezierTo(0.74, -0.555, 0.82, -0.555)
    ..quadraticBezierTo(0.9015, -0.555, 0.9633, -0.5185)
    ..quadraticBezierTo(1.025, -0.482, 1.0595, -0.4178)
    ..quadraticBezierTo(1.094, -0.3535, 1.094, -0.27)
    ..quadraticBezierTo(1.094, -0.186, 1.0593, -0.1217)
    ..quadraticBezierTo(1.0245, -0.0575, 0.9627, -0.0213)
    ..quadraticBezierTo(0.901, 0.015, 0.82, 0.015)
    ..close()
    ..moveTo(0.82, -0.112)
    ..quadraticBezierTo(0.8855, -0.112, 0.9177, -0.1562)
    ..quadraticBezierTo(0.95, -0.2005, 0.95, -0.27)
    ..quadraticBezierTo(0.95, -0.342, 0.9173, -0.385)
    ..quadraticBezierTo(0.8845, -0.428, 0.82, -0.428)
    ..quadraticBezierTo(0.7755, -0.428, 0.747, -0.408)
    ..quadraticBezierTo(0.7185, -0.388, 0.7047, -0.3525)
    ..quadraticBezierTo(0.691, -0.317, 0.691, -0.27)
    ..quadraticBezierTo(0.691, -0.1975, 0.7238, -0.1547)
    ..quadraticBezierTo(0.7565, -0.112, 0.82, -0.112)
    ..close();

  static final _uGlyph = Path()
    ..moveTo(1.365, 0.016)
    ..quadraticBezierTo(1.3015, 0.016, 1.2615, -0.0055)
    ..quadraticBezierTo(1.2215, -0.027, 1.1992, -0.06)
    ..quadraticBezierTo(1.177, -0.093, 1.1675, -0.1288)
    ..quadraticBezierTo(1.158, -0.1645, 1.156, -0.194)
    ..quadraticBezierTo(1.154, -0.2235, 1.154, -0.237)
    ..lineTo(1.154, -0.54)
    ..lineTo(1.292, -0.54)
    ..lineTo(1.292, -0.285)
    ..quadraticBezierTo(1.292, -0.2665, 1.294, -0.2377)
    ..quadraticBezierTo(1.296, -0.209, 1.3065, -0.18)
    ..quadraticBezierTo(1.317, -0.151, 1.3408, -0.1315)
    ..quadraticBezierTo(1.3645, -0.112, 1.408, -0.112)
    ..quadraticBezierTo(1.4255, -0.112, 1.4455, -0.1175)
    ..quadraticBezierTo(1.4655, -0.123, 1.483, -0.1388)
    ..quadraticBezierTo(1.5005, -0.1545, 1.5117, -0.1852)
    ..quadraticBezierTo(1.523, -0.216, 1.523, -0.266)
    ..lineTo(1.601, -0.229)
    ..quadraticBezierTo(1.601, -0.165, 1.575, -0.109)
    ..quadraticBezierTo(1.549, -0.053, 1.4968, -0.0185)
    ..quadraticBezierTo(1.4445, 0.016, 1.365, 0.016)
    ..close()
    ..moveTo(1.54, 0)
    ..lineTo(1.54, -0.179)
    ..lineTo(1.523, -0.179)
    ..lineTo(1.523, -0.54)
    ..lineTo(1.66, -0.54)
    ..lineTo(1.66, 0)
    ..close();

  static final _pGlyph = Path()
    ..moveTo(2.025, 0.015)
    ..quadraticBezierTo(1.9445, 0.015, 1.8905, -0.0225)
    ..quadraticBezierTo(1.8365, -0.06, 1.8093, -0.1245)
    ..quadraticBezierTo(1.782, -0.189, 1.782, -0.27)
    ..quadraticBezierTo(1.782, -0.351, 1.809, -0.4155)
    ..quadraticBezierTo(1.836, -0.48, 1.8885, -0.5175)
    ..quadraticBezierTo(1.941, -0.555, 2.018, -0.555)
    ..quadraticBezierTo(2.0955, -0.555, 2.153, -0.518)
    ..quadraticBezierTo(2.2105, -0.481, 2.2422, -0.4168)
    ..quadraticBezierTo(2.274, -0.3525, 2.274, -0.27)
    ..quadraticBezierTo(2.274, -0.189, 2.2428, -0.1245)
    ..quadraticBezierTo(2.2115, -0.06, 2.1555, -0.0225)
    ..quadraticBezierTo(2.0995, 0.015, 2.025, 0.015)
    ..close()
    ..moveTo(1.759, 0.24)
    ..lineTo(1.759, -0.54)
    ..lineTo(1.879, -0.54)
    ..lineTo(1.879, -0.17)
    ..lineTo(1.896, -0.17)
    ..lineTo(1.896, 0.24)
    ..close()
    ..moveTo(2.003, -0.106)
    ..quadraticBezierTo(2.047, -0.106, 2.075, -0.128)
    ..quadraticBezierTo(2.103, -0.15, 2.1165, -0.1872)
    ..quadraticBezierTo(2.13, -0.2245, 2.13, -0.27)
    ..quadraticBezierTo(2.13, -0.315, 2.116, -0.3523)
    ..quadraticBezierTo(2.102, -0.3895, 2.0728, -0.4118)
    ..quadraticBezierTo(2.0435, -0.434, 1.998, -0.434)
    ..quadraticBezierTo(1.9555, -0.434, 1.9292, -0.4135)
    ..quadraticBezierTo(1.903, -0.393, 1.891, -0.356)
    ..quadraticBezierTo(1.879, -0.319, 1.879, -0.27)
    ..quadraticBezierTo(1.879, -0.221, 1.891, -0.184)
    ..quadraticBezierTo(1.903, -0.147, 1.9303, -0.1265)
    ..quadraticBezierTo(1.9575, -0.106, 2.003, -0.106)
    ..close();
}
