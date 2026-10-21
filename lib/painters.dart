import 'dart:math';

import 'package:flutter/material.dart';

import 'main.dart' show shade;

// ----------------------------------------------------------------------
// Animation : confettis de fin de match
// ----------------------------------------------------------------------

const List<Color> _confettiColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
  Colors.white,
  Color(0xFFFF7AC6),
];

class _Piece {
  final double x;
  final double speed;
  final double phase;
  final double size;
  final double spin;
  final Color color;

  _Piece(Random r)
      : x = r.nextDouble(),
        speed = 0.6 + r.nextDouble() * 0.8,
        phase = r.nextDouble(),
        size = 6 + r.nextDouble() * 8,
        spin = 2 + r.nextDouble() * 6,
        color = _confettiColors[r.nextInt(_confettiColors.length)];
}

class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();
  final Random rnd = Random();
  late final List<_Piece> pieces = List.generate(80, (_) => _Piece(rnd));

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(pieces, ctrl.value),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double progress;

  _ConfettiPainter(this.pieces, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final y = t * (size.height + 40) - 20;
      final x = (p.x + sin(t * 6 + p.phase * 6) * 0.03) * size.width;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t * 2 * pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.55,
        ),
        Paint()..color = p.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

// ----------------------------------------------------------------------
// Animation : arrivée d'un pion à la maison
// ----------------------------------------------------------------------

class BurstPainter extends CustomPainter {
  final double t; // 0 -> 1
  final Color color;

  BurstPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final e = Curves.easeOut.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0).toDouble();

    // Deux anneaux qui s'étendent
    canvas.drawCircle(
      center,
      maxR * 0.9 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * fade + 1
        ..color = color.withOpacity(0.85 * fade),
    );
    canvas.drawCircle(
      center,
      maxR * 0.55 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.9 * fade),
    );

    // Étincelles qui partent dans toutes les directions
    for (int i = 0; i < 12; i++) {
      final ang = i * pi / 6;
      final r = maxR * (0.2 + 0.75 * e);
      final pos = center + Offset(cos(ang) * r, sin(ang) * r);
      canvas.drawCircle(
        pos,
        size.width * 0.035 * (1 - t) + 1.5,
        Paint()
          ..color = (i.isEven ? const Color(0xFFFFC21A) : Colors.white)
              .withOpacity(fade),
      );
    }

    // Étoile dorée au centre
    final starR = size.width * 0.14 * Curves.elasticOut.transform(min(1.0, t * 1.6));
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? starR : starR * 0.45;
      final a = -pi / 2 + i * pi / 5;
      final x = center.dx + r * cos(a);
      final y = center.dy + r * sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFC21A).withOpacity(fade.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant BurstPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

// ----------------------------------------------------------------------
// Dessin du plateau
// ----------------------------------------------------------------------

class BoardPainter extends CustomPainter {
  final List<Color> colors;
  final List<Color> lights;
  final List<List<int>> track;
  final List<List<List<int>>> lanes;
  final List<int> starts;
  final Set<int> safeStars;
  final bool showDoorStars;

  BoardPainter({
    required this.colors,
    required this.lights,
    required this.track,
    required this.lanes,
    required this.starts,
    required this.safeStars,
    required this.showDoorStars,
  });

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = -pi / 2 + i * pi / 5;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 15;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Les 4 bases colorées
    for (int p = 0; p < 4; p++) {
      final rowStart = p < 2 ? 0 : 9;
      final colStart = (p == 0 || p == 3) ? 0 : 9;
      final rect = Rect.fromLTWH(colStart * c, rowStart * c, 6 * c, 6 * c);

      final outer = RRect.fromRectAndRadius(rect, Radius.circular(c * 0.6));
      canvas.drawRRect(
        outer,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              shade(colors[p], 0.12),
              colors[p],
              shade(colors[p], -0.12),
            ],
          ).createShader(rect),
      );

      final inner = RRect.fromRectAndRadius(
        rect.deflate(c * 0.6),
        Radius.circular(c * 0.45),
      );
      canvas.drawRRect(
        inner.shift(Offset(0, c * 0.08)),
        Paint()..color = Colors.black.withOpacity(0.2),
      );
      canvas.drawRRect(inner, Paint()..color = lights[p]);
    }

    final cellStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFB8C2DD);
    final laneStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withOpacity(0.55);

    // Circuit commun
    for (int idx = 0; idx < track.length; idx++) {
      final cell = track[idx];
      final rect = Rect.fromLTWH(cell[1] * c, cell[0] * c, c, c);

      Color? fill;
      for (int p = 0; p < 4; p++) {
        if (starts[p] == idx) fill = colors[p];
      }

      canvas.drawRect(rect, Paint()..color = fill ?? Colors.white);
      canvas.drawRect(rect, cellStroke);

      if (fill != null) {
        if (showDoorStars) {
          _drawStar(canvas, rect.center, c * 0.3, Paint()..color = Colors.white);
        }
      } else if (safeStars.contains(idx)) {
        _drawStar(
          canvas,
          rect.center,
          c * 0.34,
          Paint()..color = const Color(0xFFFFB300),
        );
      }
    }

    // Couloirs d'arrivée
    for (int p = 0; p < 4; p++) {
      for (final cell in lanes[p]) {
        final rect = Rect.fromLTWH(cell[1] * c, cell[0] * c, c, c);
        canvas.drawRect(rect, Paint()..color = colors[p]);
        canvas.drawRect(rect, laneStroke);
      }
    }

    // Centre : 4 triangles de couleur
    final cx = 7.5 * c;
    final cy = 7.5 * c;
    final l = 6 * c;
    final r = 9 * c;

    void triangle(Color color, Offset a, Offset b) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(cx, cy)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    triangle(colors[0], Offset(l, l), Offset(l, r)); // gauche
    triangle(colors[1], Offset(l, l), Offset(r, l)); // haut
    triangle(colors[2], Offset(r, l), Offset(r, r)); // droite
    triangle(colors[3], Offset(l, r), Offset(r, r)); // bas

    final lines = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white70;
    canvas.drawLine(Offset(l, l), Offset(r, r), lines);
    canvas.drawLine(Offset(r, l), Offset(l, r), lines);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ----------------------------------------------------------------------
// Dessin d'un pion en relief
// ----------------------------------------------------------------------

class PawnPainter extends CustomPainter {
  final Color color;
  final bool highlight;
  final bool done; // pion arrivé : halo doré + étoile

  PawnPainter({
    required this.color,
    required this.highlight,
    this.done = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Ombre au sol
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.86),
        width: w * 0.9,
        height: h * 0.16,
      ),
      Paint()..color = Colors.black.withOpacity(0.28),
    );

    // Pion arrivé : halo doré sous le pion
    if (done) {
      final halo = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.86),
        width: w * 1.15,
        height: h * 0.26,
      );
      canvas.drawOval(
        halo,
        Paint()..color = const Color(0xFFFFC21A).withOpacity(0.55),
      );
      canvas.drawOval(
        halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFC21A),
      );
    }

    // Anneau lumineux : ce pion peut jouer
    if (highlight) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.86),
          width: w * 1.1,
          height: h * 0.22,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Colors.white.withOpacity(0.9),
      );
    }

    // Socle
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.8),
        width: w * 0.84,
        height: h * 0.2,
      ),
      Paint()..color = shade(color, -0.22),
    );

    // Corps
    final body = Path()
      ..moveTo(w * 0.14, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.72, w * 0.4, h * 0.5)
      ..lineTo(w * 0.6, h * 0.5)
      ..quadraticBezierTo(w * 0.7, h * 0.72, w * 0.86, h * 0.8)
      ..quadraticBezierTo(w * 0.5, h * 0.9, w * 0.14, h * 0.8)
      ..close();
    final bodyRect = Rect.fromLTWH(0, h * 0.5, w, h * 0.4);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            shade(color, -0.15),
            shade(color, 0.12),
            shade(color, -0.2),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(bodyRect),
    );

    // Tête
    final headCenter = Offset(w * 0.5, h * 0.33);
    final headRadius = w * 0.27;
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [shade(color, 0.3), color, shade(color, -0.2)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: headCenter, radius: headRadius)),
    );
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = shade(color, -0.3),
    );

    // Reflet
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.42, h * 0.26),
        width: w * 0.16,
        height: h * 0.1,
      ),
      Paint()..color = Colors.white.withOpacity(0.55),
    );

    // Pion arrivé : petite étoile dorée au-dessus de la tête
    if (done) {
      final sc = Offset(w * 0.5, h * 0.09);
      final sr = w * 0.22;
      final star = Path();
      for (int i = 0; i < 10; i++) {
        final r = i.isEven ? sr : sr * 0.45;
        final a = -pi / 2 + i * pi / 5;
        final x = sc.dx + r * cos(a);
        final y = sc.dy + r * sin(a);
        if (i == 0) {
          star.moveTo(x, y);
        } else {
          star.lineTo(x, y);
        }
      }
      star.close();
      canvas.drawPath(star, Paint()..color = const Color(0xFFFFC21A));
      canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PawnPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.highlight != highlight ||
      oldDelegate.done != done;
}

// ----------------------------------------------------------------------
// Dessin du dé
// ----------------------------------------------------------------------

class DicePainter extends CustomPainter {
  final int value;

  DicePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(
      rect.deflate(2),
      Radius.circular(size.width * 0.2),
    );

    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFD6DCEB)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFB0B8D0),
    );

    const patterns = <int, List<int>>{
      1: [4],
      2: [0, 8],
      3: [0, 4, 8],
      4: [0, 2, 6, 8],
      5: [0, 2, 4, 6, 8],
      6: [0, 2, 3, 5, 6, 8],
    };

    for (final i in patterns[value] ?? const <int>[]) {
      final dx = (0.25 + (i % 3) * 0.25) * size.width;
      final dy = (0.25 + (i ~/ 3) * 0.25) * size.height;
      canvas.drawCircle(
        Offset(dx, dy),
        size.width * 0.075,
        Paint()..color = const Color(0xFF1A1F3A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DicePainter oldDelegate) =>
      oldDelegate.value != value;
}
