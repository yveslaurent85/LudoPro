import 'dart:math';

import 'package:flutter/material.dart';

// ----------------------------------------------------------------------
// Dé 3D : un vrai cube qui tourne dans l'espace.
//
// value : face qui doit rester visible à la fin
// t     : progression du lancer (0 = début, 1 = posé)
// spin  : nombre de tours sur chaque axe pendant le lancer (peut être < 0)
// ----------------------------------------------------------------------

typedef _M = List<double>;

_M _mul(_M a, _M b) {
  final r = List<double>.filled(9, 0);
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      double s = 0;
      for (int k = 0; k < 3; k++) {
        s += a[i * 3 + k] * b[k * 3 + j];
      }
      r[i * 3 + j] = s;
    }
  }
  return r;
}

_M _rx(double a) {
  final c = cos(a), s = sin(a);
  return [1, 0, 0, 0, c, -s, 0, s, c];
}

_M _ry(double a) {
  final c = cos(a), s = sin(a);
  return [c, 0, s, 0, 1, 0, -s, 0, c];
}

_M _rz(double a) {
  final c = cos(a), s = sin(a);
  return [c, -s, 0, s, c, 0, 0, 0, 1];
}

List<double> _apply(_M m, List<double> v) => [
      m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
      m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
      m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ];

/// Rotation qui amène la face [v] face au joueur.
_M _align(int v) {
  switch (v) {
    case 6:
      return _ry(pi);
    case 3:
      return _ry(-pi / 2);
    case 4:
      return _ry(pi / 2);
    case 2:
      return _rx(pi / 2);
    case 5:
      return _rx(-pi / 2);
    default:
      return _rx(0);
  }
}

// valeur, normale (xyz), axe u (xyz), axe v (xyz)
const List<List<double>> _faces = [
  [1, 0, 0, 1, 1, 0, 0, 0, 1, 0],
  [6, 0, 0, -1, -1, 0, 0, 0, 1, 0],
  [3, 1, 0, 0, 0, 0, -1, 0, 1, 0],
  [4, -1, 0, 0, 0, 0, 1, 0, 1, 0],
  [2, 0, 1, 0, 1, 0, 0, 0, 0, -1],
  [5, 0, -1, 0, 1, 0, 0, 0, 0, 1],
];

const Map<int, List<int>> _pips = {
  1: [4],
  2: [0, 8],
  3: [0, 4, 8],
  4: [0, 2, 6, 8],
  5: [0, 2, 4, 6, 8],
  6: [0, 2, 3, 5, 6, 8],
};

class Die3D extends StatelessWidget {
  const Die3D({
    super.key,
    required this.value,
    this.t = 1.0,
    this.spin = const [2, 3, 1],
    this.glow = false,
    this.color = const Color(0xFFFFC21A),
  });

  final int value;
  final double t;
  final List<int> spin;
  final bool glow;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _Die3DPainter(value, t, spin, glow, color),
      ),
    );
  }
}

class _Die3DPainter extends CustomPainter {
  _Die3DPainter(this.value, this.t, this.spin, this.glow, this.color);

  final int value;
  final double t;
  final List<int> spin;
  final bool glow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rem = 1 - Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final sp = spin.length >= 3 ? spin : const [2, 3, 1];

    final spinM = _mul(
      _rx(sp[0] * 2 * pi * rem),
      _mul(_ry(sp[1] * 2 * pi * rem), _rz(sp[2] * 2 * pi * rem)),
    );
    // L'inclinaison disparaît à la fin : le dé se pose bien à plat et ne
    // montre qu'une seule face (le numéro).
    final k = 1 - Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final tilt = _mul(_rx(-0.42 * k), _ry(0.5 * k));
    final m = _mul(tilt, _mul(spinM, _align(value)));

    final cx = size.width / 2;
    final cy = size.height / 2;
    final sc = size.width * 0.5 / 1.45;

    Offset proj(List<double> p) {
      final k = 1 / (1 - 0.10 * p[2]);
      return Offset(cx + p[0] * sc * k, cy + p[1] * sc * k);
    }

    // Halo / ombre
    if (glow) {
      canvas.drawCircle(
        Offset(cx, cy),
        size.width * 0.42,
        Paint()
          ..color = color.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + size.height * 0.42),
          width: size.width * 0.7,
          height: size.height * 0.12,
        ),
        Paint()..color = Colors.black.withOpacity(0.25),
      );
    }

    final light = [-0.3, -0.5, 0.8];

    for (final f in _faces) {
      final n = _apply(m, [f[1], f[2], f[3]]);
      if (n[2] <= 0.0) continue; // face cachée

      final u = _apply(m, [f[4], f[5], f[6]]);
      final v = _apply(m, [f[7], f[8], f[9]]);

      List<double> at(double a, double b) => [
            n[0] + a * u[0] + b * v[0],
            n[1] + a * u[1] + b * v[1],
            n[2] + a * u[2] + b * v[2],
          ];

      // Face en carré aux coins bien arrondis (comme un vrai dé).
      const double rr = 0.30; // rayon des coins
      const int seg = 6;
      final pts = <Offset>[];
      for (int c = 0; c < 4; c++) {
        final cxs = (c == 0 || c == 3) ? -1.0 : 1.0;
        final cys = (c < 2) ? -1.0 : 1.0;
        final a0 = pi + c * pi / 2; // début de l'arc du coin c
        final ccx = cxs * (1 - rr);
        final ccy = cys * (1 - rr);
        for (int i = 0; i <= seg; i++) {
          final ang = a0 + (pi / 2) * i / seg;
          pts.add(proj(at(ccx + rr * cos(ang), ccy + rr * sin(ang))));
        }
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      path.close();

      final b = (n[0] * light[0] + n[1] * light[1] + n[2] * light[2])
          .clamp(0.0, 1.0)
          .toDouble();
      final face = Color.lerp(const Color(0xFFA9B3D6), const Color(0xFFFFFCF2), b)!;
      final bounds = path.getBounds();

      // Fond de la face : dégradé doux (lumière en haut à gauche) + léger reflet.
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(face, Colors.white, 0.55)!,
              face,
              Color.lerp(face, const Color(0xFF6F7AA3), 0.28)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(bounds),
      );
      // Liseré de couleur du joueur + fine ligne de relief.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.4, size.width * 0.035)
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(color, const Color(0xFF2A3358), 0.55)!,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.8, size.width * 0.012)
          ..color = Colors.white.withOpacity(0.55 * b + 0.1),
      );

      // Points : billes brillantes (le 1 est plus gros, à la couleur du joueur).
      final isOne = f[0].toInt() == 1;
      final pipR = isOne ? 0.27 : 0.19;
      for (final idx in _pips[f[0].toInt()]!) {
        final gx = ((idx % 3) - 1) * 0.55;
        final gy = ((idx ~/ 3) - 1) * 0.55;
        final pip = Path();
        for (int k = 0; k < 18; k++) {
          final a = k * 2 * pi / 18;
          final o = proj(at(gx + pipR * cos(a), gy + pipR * sin(a)));
          if (k == 0) {
            pip.moveTo(o.dx, o.dy);
          } else {
            pip.lineTo(o.dx, o.dy);
          }
        }
        pip.close();
        final pb = pip.getBounds();
        final base = isOne ? Color.lerp(color, const Color(0xFF7A0A12), 0.35)! : const Color(0xFF141937);
        canvas.drawPath(
          pip,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.35),
              radius: 1.0,
              colors: [Color.lerp(base, Colors.white, 0.45)!, base, Color.lerp(base, Colors.black, 0.4)!],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(pb),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Die3DPainter old) =>
      old.value != value ||
      old.t != t ||
      old.glow != glow ||
      old.color != color ||
      old.spin != spin;
}
