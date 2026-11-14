import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';
import 'share_menu.dart';
import 'lobby_widgets.dart';
import 'main.dart' show firebaseReady, Sfx;
import 'online_screen.dart';
import 'stake_field.dart';

// ======================================================================
// Cartes : TIAH, BOUBAYAH, TCHEK GAMES (Tiah et Tchek Games)
// ======================================================================

const Color _gold = Color(0xFFFFC21A);
const Color _goldSoft = Color(0xFFFFE082);
const BoxDecoration _felt = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0E7A4B), Color(0xFF085C37), Color(0xFF04331F)],
  ),
);
const List<Color> _seatColors = [
  Color(0xFFFFC21A),
  Color(0xFF7CD4FF),
  Color(0xFFFF8A80),
  Color(0xFFB9F6CA),
  Color(0xFFE1BEE7),
  Color(0xFFFFCC80),
];

String _fcfa(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${b.toString()} FCFA';
}

// ----------------------------------------------------------------------
// Cartes
// ----------------------------------------------------------------------

class _Card {
  const _Card(this.v, this.suit);

  /// Valeur : 3 à 10, 11 = As.
  final int v;

  /// 0 ♠, 1 ♥, 2 ♦, 3 ♣
  final int suit;

  String get label => v == 11 ? 'A' : '$v';
  int get code => v * 4 + suit; // même codage que le serveur
  String get symbol => const ['♠', '♥', '♦', '♣'][suit];
  bool get red => suit == 1 || suit == 2;
}

List<_Card> _newDeck({required bool withAce}) {
  final d = <_Card>[];
  for (var s = 0; s < 4; s++) {
    for (var v = 3; v <= (withAce ? 11 : 10); v++) {
      if (withAce && v == 11 && s == 2) continue; // TIAH : pas d'as de carreau (3 as seulement)
      d.add(_Card(v, s));
    }
  }
  d.shuffle(Random.secure());
  return d;
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card, this.up = true, this.w = 54});

  final _Card? card;
  final bool up;
  final double w;

  @override
  Widget build(BuildContext context) {
    final h = w * 1.42;
    if (!up || card == null) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6)],
          ),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 5, offset: Offset(0, 3))],
        ),
        child: Center(
          child: Text('K',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: w * 0.5)),
        ),
      );
    }
    final c = card!;
    final col = c.red ? const Color(0xFFD32F2F) : const Color(0xFF212121);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.14),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 5, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: w * 0.1,
            top: w * 0.05,
            child: Column(
              children: [
                Text(c.label, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: w * 0.34, height: 1)),
                Text(c.symbol, style: TextStyle(color: col, fontSize: w * 0.28, height: 1)),
              ],
            ),
          ),
          Center(child: Text(c.symbol, style: TextStyle(color: col, fontSize: w * 0.62))),
        ],
      ),
    );
  }
}

/// Ouvre [page] seulement si le joueur est connecté ; sinon écran de connexion d'abord.
void _pushLoggedIn(BuildContext context, Widget Function(BuildContext) page) {
  final loggedIn = !firebaseReady || FirebaseAuth.instance.currentUser != null;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (c) => loggedIn ? page(c) : OnlineScreen(onSignedIn: page),
  ));
}

/// Une carte qui apparaît (prise, distribuée) : elle grossit et se fond.
class _PopIn extends StatelessWidget {
  const _PopIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final total = 450 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutBack),
      builder: (context, v, ch) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * -40),
          child: Transform.scale(scale: 0.6 + 0.4 * v, child: ch),
        ),
      ),
      child: child,
    );
  }
}

/// Animation de fin de manche : confettis, nom du gagnant et montant total des gains qui défile.
class _WinBurst extends StatefulWidget {
  const _WinBurst({super.key, required this.title, required this.amount, this.subtitle = ''});

  final String title;
  final String subtitle;
  final int amount; // 0 : partie gratuite, pas de montant

  @override
  State<_WinBurst> createState() => _WinBurstState();
}

class _WinBurstState extends State<_WinBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _auto;
  bool _visible = true;
  late final List<List<double>> _bits;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _bits = [
      for (var i = 0; i < 70; i++)
        [rnd.nextDouble(), 0.5 + rnd.nextDouble() * 0.9, rnd.nextDouble() * 6.28, 6 + rnd.nextDouble() * 8,
        rnd.nextInt(5).toDouble(), rnd.nextDouble() * 6.28]
    ];
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _auto = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _visible = false),
      child: Container(
        color: Colors.black.withOpacity(0.72),
        child: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value)),
              ),
            ),
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.3, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B8A3A), Color(0xFF0B5A25)],
                  ),
                  border: Border.all(color: _gold, width: 3),
                  boxShadow: [BoxShadow(color: _gold.withOpacity(0.45), blurRadius: 30, spreadRadius: 2)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🏆', style: TextStyle(fontSize: 58)),
                  const SizedBox(height: 4),
                  Text(widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  if (widget.amount > 0) ...[
                    const SizedBox(height: 10),
                    Text(tr('Total des gains', 'Total winnings'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: widget.amount.toDouble()),
                      duration: const Duration(milliseconds: 2200),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(_fcfa(v.round()),
                          style: const TextStyle(
                              color: _gold, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ],
                  if (widget.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(widget.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                  const SizedBox(height: 14),
                  Text(tr('Touche pour continuer', 'Tap to continue'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);

  final List<List<double>> bits;
  final double t;

  static const _colors = [Color(0xFFFFC21A), Color(0xFFE5262B), Color(0xFF22B14C), Color(0xFF1E6BFF), Color(0xFFFFFFFF)];

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bits) {
      final y = ((b[2] / 6.28 + t * b[1]) % 1.15) * (size.height + 40) - 30;
      final x = b[0] * size.width + sin(t * 6.28 * 2 + b[2]) * 18;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b[5] + t * 6.28 * 2 * b[1]);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: b[3], height: b[3] * 0.55),
        Paint()..color = _colors[b[4].toInt() % _colors.length],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Cartes du milieu, classées dans l'ordre : la 1re est celle du dessus.
class _MiddleStrip extends StatelessWidget {
  const _MiddleStrip({required this.cards, this.w = 38});

  final List<_Card> cards;
  final double w;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Text(tr('Plus de carte au milieu.', 'No more cards in the middle.'),
          style: const TextStyle(color: Colors.white54, fontSize: 12));
    }
    return Wrap(alignment: WrapAlignment.center, spacing: 5, runSpacing: 6, children: [
      for (var i = 0; i < cards.length; i++)
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            decoration: i == 0
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(w * 0.18),
                    boxShadow: const [BoxShadow(color: _gold, blurRadius: 10, spreadRadius: 1)],
                  )
                : null,
            child: _PopIn(
              key: ValueKey('mid-${cards[i].v}-${cards[i].suit}'),
              delayMs: i * 170,
              child: _CardView(card: cards[i], w: w),
            ),
          ),
          Text('${i + 1}',
              style: TextStyle(color: i == 0 ? _gold : Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
    ]);
  }
}

/// Sabot : boîte de distribution avec la pile de cartes et la fente de sortie.
class _Shoe extends StatelessWidget {
  const _Shoe({this.left});

  final int? left;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 110,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          top: 18,
          child: Container(
            width: 80,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A2A1A), Color(0xFF14100B)],
              ),
              border: Border.all(color: _gold, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
            ),
          ),
        ),
        for (var k = 3; k >= 0; k--)
          Positioned(
            left: 12 + k * 1.5,
            top: 4 + k * 1.2,
            child: const _CardView(card: null, up: false, w: 40),
          ),
        Positioned(
          left: 0,
          top: 44,
          child: Container(
            width: 80,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14), top: Radius.circular(6)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4A3622), Color(0xFF1B140D)],
              ),
              border: Border.all(color: _goldSoft, width: 1.2),
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              width: 56,
              height: 5,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
        if (left != null)
          Positioned(
            right: -2,
            top: 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(10)),
              child: Text('$left',
                  style: const TextStyle(color: Color(0xFF1A1200), fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }
}

// ----------------------------------------------------------------------
// Animation de distribution
// ----------------------------------------------------------------------

class _DealOverlay extends StatefulWidget {
  const _DealOverlay({
    required this.names,
    required this.batches,
    required this.labels,
    required this.onDone,
    this.sfx,
    this.grouped = false,
    this.deckSize = 0,
  });

  final bool grouped;
  final int deckSize;
  final List<String> names;
  final List<int> batches;
  final List<String> labels;
  final VoidCallback onDone;
  final Sfx? sfx;

  @override
  State<_DealOverlay> createState() => _DealOverlayState();
}

class _DealOverlayState extends State<_DealOverlay> with SingleTickerProviderStateMixin {
  static const int _gap = 260;
  static const int _fly = 600;
  late final AnimationController _c;
  final List<List<int>> _deals = [];
  late final int _totalMs;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    for (var b = 0; b < widget.batches.length; b++) {
      if (widget.grouped) {
        for (var s = 0; s < widget.names.length; s++) {
          for (var r = 0; r < widget.batches[b]; r++) {
            _deals.add([s, b]);
          }
        }
      } else {
        for (var r = 0; r < widget.batches[b]; r++) {
          for (var s = 0; s < widget.names.length; s++) {
            _deals.add([s, b]);
          }
        }
      }
    }
    _totalMs = _deals.length * _gap + _fly + 600;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _totalMs))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _finish();
      })
      ..forward();
    for (var k = 0; k < _deals.length; k++) {
      Future<void>.delayed(Duration(milliseconds: k * _gap + 60), () {
        if (mounted && !_done) widget.sfx?.step();
      });
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.names.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Container(
        color: const Color(0xD9021A0E),
        child: AnimatedBuilder(animation: _c, builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final center = Offset(w / 2, h * 0.44);
          final rx = w * 0.36;
          final ry = h * 0.27;
          Offset seatPos(int i) {
            final a = pi / 2 + 2 * pi * i / n;
            return Offset(center.dx + rx * cos(a), center.dy + ry * sin(a));
          }

          final elapsed = _c.value * _totalMs;
          final cur = (elapsed / _gap).floor().clamp(0, _deals.length - 1);
          final label = widget.labels[min(_deals[cur][1], widget.labels.length - 1)];
          final children = <Widget>[];
          for (var i = 0; i < n; i++) {
            final p = seatPos(i);
            children.add(Positioned(
              left: p.dx - 40,
              top: p.dy - 34,
              width: 80,
              child: Column(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _seatColors[i % 6],
                  child: Text(widget.names[i].isEmpty ? '?' : widget.names[i].substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Color(0xFF1A1200), fontWeight: FontWeight.w900)),
                ),
                Text(widget.names[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ));
          }
          final slot = Offset(center.dx, center.dy + 36);
          final seatCount = List.filled(n, 0);
          var dealt = 0;
          final flying =
