import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';
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
  String get symbol => const ['♠', '♥', '♦', '♣'][suit];
  bool get red => suit == 1 || suit == 2;
}

List<_Card> _newDeck({required bool withAce}) {
  final d = <_Card>[];
  for (var s = 0; s < 4; s++) {
    for (var v = 3; v <= (withAce ? 11 : 10); v++) {
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

/// Cartes du milieu, classées dans l'ordre : la 1re est celle du dessus.
class _MiddleStrip extends StatelessWidget {
  const _MiddleStrip({required this.cards, this.w = 38});

  final List<_Card> cards; // la 1re = dessus du paquet
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
            child: _CardView(card: cards[i], w: w),
          ),
          Text('${i + 1}',
              style: TextStyle(color: i == 0 ? _gold : Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
    ]);
  }
}

// ----------------------------------------------------------------------
// Animation de distribution : les cartes partent du paquet vers chaque joueur
// ----------------------------------------------------------------------

class _DealOverlay extends StatefulWidget {
  const _DealOverlay({
    required this.names,
    required this.batches,
    required this.labels,
    required this.onDone,
    this.sfx,
  });

  /// Joueurs, dans l'ordre de distribution.
  final List<String> names;

  /// Nombre de cartes données à chacun à chaque tour de table (ex. [2] ou [3, 2]).
  final List<int> batches;
  final List<String> labels;
  final VoidCallback onDone;
  final Sfx? sfx;

  @override
  State<_DealOverlay> createState() => _DealOverlayState();
}

class _DealOverlayState extends State<_DealOverlay> with SingleTickerProviderStateMixin {
  static const int _gap = 150; // ms entre deux cartes
  static const int _fly = 520; // durée d'un vol
  late final AnimationController _c;
  final List<List<int>> _deals = []; // [siège, lot]
  late final int _totalMs;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    for (var b = 0; b < widget.batches.length; b++) {
      for (var r = 0; r < widget.batches[b]; r++) {
        for (var s = 0; s < widget.names.length; s++) {
          _deals.add([s, b]);
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
        child: LayoutBuilder(builder: (context, box) {
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
          // joueurs
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
          // paquet
          children.add(Positioned(
            left: center.dx - 22,
            top: center.dy - 31,
            child: Stack(children: [
              for (var k = 3; k >= 0; k--)
                Transform.translate(offset: Offset(k * 1.5, -k * 1.5), child: const _CardView(card: null, up: false, w: 44)),
            ]),
          ));
          // cartes en vol / arrivées
          final seatCount = List.filled(n, 0);
          for (var k = 0; k < _deals.length; k++) {
            final seat = _deals[k][0];
            final m = seatCount[seat]++;
            final t = ((elapsed - k * _gap) / _fly).clamp(0.0, 1.0);
            if (t <= 0) continue;
            final e = Curves.easeOutCubic.transform(t);
            final target = seatPos(seat) + Offset((m - 2) * 11.0, 46 + (m % 2) * 3.0);
            final pos = Offset.lerp(center, target, e)!;
            children.add(Positioned(
              left: pos.dx - 17,
              top: pos.dy - 24,
              child: Transform.rotate(
                angle: (1 - e) * (k.isEven ? 0.9 : -0.9),
                child: _CardView(card: null, up: false, w: 34),
              ),
            ));
          }
          children.add(Positioned(
            left: 0,
            right: 0,
            bottom: h * 0.08,
            child: Column(children: [
              Text(label,
                  style: const TextStyle(color: _goldSoft, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(tr('Touche pour passer', 'Tap to skip'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ));
          return Stack(children: children);
        }),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Page « Cartes »
// ----------------------------------------------------------------------

class CartesPage extends StatelessWidget {
  const CartesPage({super.key});

  void _go(BuildContext c, Widget p) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => p));

  Widget _card(String title, String sub, IconData icon, Color color, VoidCallback? onTap, {String? badge}) {
    final off = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: off
                ? [Colors.white.withOpacity(0.16), Colors.white.withOpacity(0.06)]
                : [color, Color.lerp(color, Colors.black, 0.28)!],
          ),
          border: Border.all(color: off ? Colors.white24 : Colors.white54, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2)),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
                          child: Text(badge,
                              style: const TextStyle(
                                  color: Color(0xFF1A1200), fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            if (!off) const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _felt,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Text(tr('Cartes', 'Cards'),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Text('TIAH ET TCHEK GAMES',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _goldSoft, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
                    const SizedBox(height: 14),
                    _card('TIAH', tr('Atteins 21 sans dépasser · 2 à 6 joueurs', 'Reach 21 without going over · 2-6 players'),
                        Icons.style, const Color(0xFFE5262B),
                        () => _pushLoggedIn(context, (_) => const _CardModePage(game: 'tiah')), badge: tr('NOUVEAU', 'NEW')),
                    const SizedBox(height: 14),
                    _card('BOUBAYAH', tr('Le plus gros total gagne · 2 à 6 joueurs', 'Highest total wins · 2-6 players'),
                        Icons.filter_5, const Color(0xFF7B1FA2),
                        () => _pushLoggedIn(context, (_) => const _CardModePage(game: 'boubayah')), badge: tr('NOUVEAU', 'NEW')),
                    const SizedBox(height: 14),
                    _card('TCHEK GAMES', tr('En ligne uniquement · bientôt disponible', 'Online only · coming soon'),
                        Icons.location_on, const Color(0xFF0277BD),
                        () => _go(context, const _TchekPage())),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TchekPage extends StatelessWidget {
  const _TchekPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _felt,
        child: SafeArea(
          child: Column(
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Text('TCHEK GAMES',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, color: _gold, size: 64),
                        const SizedBox(height: 12),
                        Text(tr('Bientôt disponible', 'Coming soon'),
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Text(
                          tr('Jeu 100 % en ligne, avec vérification de position (GPS) : deux joueurs à moins de 100 m ne peuvent pas jouer ensemble.',
                              'Online-only game with GPS verification: two players within 100 m cannot play together.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choix du mode d'un jeu de cartes.
class _CardModePage extends StatelessWidget {
  const _CardModePage({required this.game});

  final String game;

  @override
  Widget build(BuildContext context) {
    final tiah = game == 'tiah';
    final title = tiah ? 'TIAH' : 'BOUBAYAH';
    Widget tile(IconData i, String t, String s, Color c, VoidCallback? f) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GestureDetector(
            onTap: f,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: f == null
                      ? [Colors.white.withOpacity(0.16), Colors.white.withOpacity(0.06)]
                      : [c, Color.lerp(c, Colors.black, 0.25)!],
                ),
                border: Border.all(color: f == null ? Colors.white24 : Colors.white54, width: 2),
              ),
              child: Row(
                children: [
                  Icon(i, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                        Text(s, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _felt,
        child: SafeArea(
          child: Column(
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _CardView(card: _Card(11, 1), w: 90),
                        const SizedBox(height: 22),
                        tile(
                          Icons.groups,
                          tr('En présentiel', 'Face to face'),
                          tr('2 à 6 joueurs sur le même téléphone · mise ou gratuit',
                              '2-6 players on one phone · stake or free'),
                          const Color(0xFF22B14C),
                          () => _pushLoggedIn(
                            context,
                            (_) => tiah ? const TiahLocalPage() : const BoubayahLocalPage(),
                          ),
                        ),
                        tile(
                          Icons.public,
                          tr('En ligne', 'Online'),
                          tr('Chacun joue depuis son téléphone · mise ou gratuit', 'Everyone plays from their own phone · stake or free'),
                          const Color(0xFFE5262B),
                          () => _pushLoggedIn(context, (_) => CardsOnlineHub(game: game)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Table : joueurs, comptes, mises (présentiel)
// ----------------------------------------------------------------------

class _Table {
  _Table({required this.game, required this.stake, required this.accounts, required this.names});

  final String game; // 'tiah' | 'boubayah'
  final int stake;
  final List<PlayerAccount?> accounts;
  final List<String> names;
  String? localId;
  bool settled = false;
  final List<String> betLog = []; // paris de la manche en cours

  int get n => names.length;
  bool get staked => stake > 0 && firebaseReady;

  /// Débite les mises d'une manche (partie payante).
  Future<void> begin() async {
    settled = false;
    localId = null;
    betLog.clear();
    if (!staked) return;
    final tokens = <String>[];
    for (final a in accounts) {
      if (a!.uid == FirebaseAuth.instance.currentUser?.uid) {
        tokens.add((await FirebaseAuth.instance.currentUser?.getIdToken(true)) ?? '');
      } else {
        tokens.add(a.idToken ?? '');
      }
    }
    localId = await Wallet.startLocalGame(stake: stake, tokens: tokens, names: names, game: game);
  }

  /// Verse la cagnotte. Égalité générale / à 2 : remboursement sans commission
  /// (géré par le serveur). Renvoie le jackpot éventuel.
  Future<int> settle(List<int> winSeats, {List<int>? scores, List<int>? fscores}) async {
    final id = localId;
    if (id == null || settled || !staked) return 0;
    settled = true;
    try {
      final res = await Wallet.settleLocalFull(
        id,
        [for (final s in winSeats) accounts[s]!.uid],
        scores ?? [for (var i = 0; i < n; i++) winSeats.contains(i) ? 1 : 0],
        fscores: fscores,
      );
      return (res['jackpot'] as num?)?.toInt() ?? 0;
    } catch (_) {
      settled = false;
      rethrow;
    }
  }

  /// Jeton de connexion du joueur (le serveur vérifie que c'est bien lui).
  Future<String> tokenOf(int seat) async {
    final a = accounts[seat]!;
    if (a.uid == FirebaseAuth.instance.currentUser?.uid) {
      return (await FirebaseAuth.instance.currentUser?.getIdToken(true)) ?? '';
    }
    return a.idToken ?? '';
  }

  /// Gain de chaque gagnant, 0 si gratuit ; en cas d'égalité générale : remboursement.
  int payPerWinner(List<int> winSeats) {
    if (stake <= 0) return 0;
    if (winSeats.length == n) return stake; // remboursement
    return Wallet.prize(stake * n, local: true) ~/ winSeats.length;
  }
}

/// Paris en présentiel : Duel (TIAH, BOUBAYAH) et Défi Fétiche 13 (BOUBAYAH).
/// Possible avant la manche ou pendant, entre des joueurs qui n'ont pas encore ouvert leurs cartes.
Future<void> _showLocalBets(
  BuildContext context, {
  required _Table table,
  required Set<int> played,
  required bool boubayah,
}) {
  final seats = [for (var s = 0; s < table.n; s++) if (!played.contains(s)) s];
  String type = 'duel';
  int? pSeat = seats.isNotEmpty ? seats.first : null;
  int? oSeat = seats.length > 1 ? seats[1] : null;
  bool over = true;
  bool busy = false;
  final amountCtrl = TextEditingController(text: '${table.stake}');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF062E1C),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> submit() async {
        final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
        if (pSeat == null || oSeat == null || pSeat == oSeat) return;
        if (amount < Wallet.minStake) {
          ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(tr('Mise minimum : ${_fcfa(Wallet.minStake)}', 'Minimum: ${_fcfa(Wallet.minStake)}'))));
          return;
        }
        setS(() => busy = true);
        try {
          await Wallet.localBet(
            id: table.localId!,
            type: type,
            amount: amount,
            proposerToken: await table.tokenOf(pSeat!),
            opponentToken: await table.tokenOf(oSeat!),
            over7: over,
          );
          final pn = table.names[pSeat!];
          final on = table.names[oSeat!];
          table.betLog.add(type == 'duel'
              ? '$pn ⚔ $on · ${_fcfa(amount)}'
              : '$pn ${over ? tr('plus', 'over') : tr('moins', 'under')} ${tr('de', 'than')} 13 ${tr('contre', 'vs')} $on · ${_fcfa(amount)}');
          if (ctx.mounted) Navigator.of(ctx).pop();
        } catch (e) {
          if (ctx.mounted) {
            setS(() => busy = false);
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
          }
        }
      }

      Widget seatPicker(String label, int? value, void Function(int?) on, {int? exclude}) {
        return Row(children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              dropdownColor: const Color(0xFF0B4A2C),
              value: value,
              items: [
                for (final s in seats)
                  if (s != exclude)
                    DropdownMenuItem<int>(
                      value: s,
                      child: Text(table.names[s], style: const TextStyle(color: Colors.white)),
                    ),
              ],
              onChanged: busy ? null : (v) => setS(() => on(v)),
            ),
          ),
        ]);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Paris entre joueurs', 'Bets between players'),
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              tr('Possible tant que les joueurs concernés n\'ont pas ouvert leurs cartes. Les deux mises sont débitées tout de suite.',
                  'Possible until the players involved have opened their cards. Both stakes are charged right away.'),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (seats.length < 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  tr('Il faut au moins 2 joueurs qui n\'ont pas encore ouvert leurs cartes.',
                      'At least 2 players who have not opened their cards yet are needed.'),
                  style: const TextStyle(color: Color(0xFFFFCC80), fontWeight: FontWeight.w700),
                ),
              )
            else ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: Text(tr('Défier un adversaire', 'Challenge a rival')),
                  selected: type == 'duel',
                  selectedColor: _gold,
                  onSelected: (_) => setS(() => type = 'duel'),
                ),
                if (boubayah)
                  ChoiceChip(
                    label: Text(tr('Défi Fétiche (13)', 'Fetish challenge (13)')),
                    selected: type == 'fetiche',
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => type = 'fetiche'),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                type == 'duel'
                    ? tr(boubayah ? 'Le plus gros score gagne (FOMEKOU bat tout). Égalité : mises rendues.' : 'Le meilleur total (21 max) gagne. Égalité : mises rendues.',
                        boubayah ? 'Highest score wins (FOMEKOU beats all). Tie: stakes refunded.' : 'Best total (21 max) wins. Tie: stakes refunded.')
                    : tr('Le total BOUBAYAH du parieur est comparé à 13. FOMEKOU compte 6 (donc « moins de 13 »). 13 pile : mises rendues.',
                        "The bettor's BOUBAYAH total is compared with 13. FOMEKOU counts as 6 (so under 13). Exactly 13: stakes refunded."),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 8),
              seatPicker(tr('Parieur', 'Bettor'), pSeat, (v) {
                pSeat = v;
                if (oSeat == pSeat) oSeat = seats.firstWhere((s) => s != pSeat, orElse: () => seats.first);
              }),
              seatPicker(tr('Adversaire', 'Opponent'), oSeat, (v) => oSeat = v, exclude: pSeat),
              if (type == 'fetiche')
                Row(children: [
                  SizedBox(width: 100, child: Text(tr('Le parieur dit', 'Bettor says'), style: const TextStyle(color: Colors.white70))),
                  ChoiceChip(
                    label: Text(tr('Plus de 13', 'Over 13')),
                    selected: over,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => over = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(tr('Moins de 13', 'Under 13')),
                    selected: !over,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => over = false),
                  ),
                ]),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: tr('Mise du pari (FCFA)', 'Bet amount (FCFA)'),
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5262B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: busy || pSeat == null || oSeat == null || pSeat == oSeat ? null : submit,
                  child: Text(busy ? tr('Mise en cours...', 'Placing...') : tr('Valider le pari', 'Place the bet'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
            if (table.betLog.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr('Paris de cette manche', "This round's bets"),
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
              for (final l in table.betLog)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(l, style: const TextStyle(color: Colors.white))),
            ],
          ]),
        ),
      );
    }),
  ).whenComplete(amountCtrl.dispose);
}

class _CardsSetup extends StatefulWidget {
  const _CardsSetup({required this.title, required this.game, required this.onStart});

  final String title;
  final String game;
  final Future<void> Function(_Table t) onStart;

  @override
  State<_CardsSetup> createState() => _CardsSetupState();
}

class _CardsSetupState extends State<_CardsSetup> {
  int _n = 2;
  int _stake = 0;
  bool _starting = false;
  final Map<int, PlayerAccount> _acc = {};
  final List<TextEditingController> _c = List.generate(6, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) _loadHost(u);
    }
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHost(User u) async {
    int bal = 0;
    String? token;
    try {
      bal = await Wallet.ensure(FirebaseFirestore.instance, u);
      token = await u.getIdToken();
    } catch (_) {}
    if (!mounted) return;
    final n = (u.displayName != null && u.displayName!.isNotEmpty) ? u.displayName! : (u.email ?? 'Joueur');
    setState(() {
      _acc[0] = PlayerAccount(idToken: token, uid: u.uid, name: n, email: u.email ?? '', balance: bal);
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _connect(int seat) async {
    final acc = await showPlayerLogin(
      context,
      colorName: tr('Joueur ${seat + 1}', 'Player ${seat + 1}'),
      color: _seatColors[seat],
    );
    if (acc == null || !mounted) return;
    if (_acc.entries.any((e) => e.key != seat && e.value.uid == acc.uid)) {
      _snack(tr('Ce compte joue déjà dans la partie.', 'This account is already in the game.'));
      return;
    }
    setState(() => _acc[seat] = acc);
  }

  bool get _paid => _stake > 0 && firebaseReady;

  String? get _broke {
    if (!_paid) return null;
    for (var s = 0; s < _n; s++) {
      final a = _acc[s];
      if (a != null && a.balance < _stake) return a.name;
    }
    return null;
  }

  bool get _ready {
    if (_starting) return false;
    if (_stake == 0 || !firebaseReady) return true;
    if (_stake < Wallet.minStake) return false;
    for (var s = 0; s < _n; s++) {
      if (_acc[s] == null) return false;
    }
    return _broke == null;
  }

  Widget _row(int seat) {
    final acc = _acc[seat];
    final color = _seatColors[seat];
    Widget field;
    if (!_paid) {
      field = TextField(
        controller: _c[seat],
        maxLength: 14,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          hintText: tr('Joueur ${seat + 1}', 'Player ${seat + 1}'),
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      );
    } else if (acc != null) {
      field = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acc.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            Text('💰 ${_fcfa(acc.balance)}', style: const TextStyle(color: _goldSoft, fontSize: 12)),
          ],
        ),
      );
    } else {
      field = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: color, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _connect(seat),
        icon: const Icon(Icons.login),
        label: Text(tr('Joueur ${seat + 1} : se connecter', 'Player ${seat + 1}: sign in')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: color),
          const SizedBox(width: 12),
          Expanded(child: field),
          if (_paid && acc != null && seat != 0)
            IconButton(
              onPressed: () => setState(() => _acc.remove(seat)),
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final names = <String>[
      for (var i = 0; i < _n; i++)
        _paid
            ? _acc[i]!.name
            : (_c[i].text.trim().isNotEmpty ? _c[i].text.trim() : tr('Joueur ${i + 1}', 'Player ${i + 1}')),
    ];
    final t = _Table(
      game: widget.game,
      stake: firebaseReady ? _stake : 0,
      accounts: [for (var i = 0; i < _n; i++) _acc[i]],
      names: names,
    );
    setState(() => _starting = true);
    try {
      await t.begin();
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        _snack(Wallet.errorText(e));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _starting = false);
    await widget.onStart(t);
  }

  @override
  Widget build(BuildContext context) {
    final broke = _broke;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(tr('Nombre de joueurs', 'Number of players'),
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (var k = 2; k <= 6; k++)
              ChoiceChip(
                label: Text('$k'),
                selected: _n == k,
                selectedColor: _gold,
                onSelected: (_) => setState(() => _n = k),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (firebaseReady) ...[
          Text(tr('Mise de chaque joueur (0 = partie gratuite)', "Each player's stake (0 = free game)"),
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          StakeField(stake: _stake, players: _n, local: true, onChanged: (v) => setState(() => _stake = v)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _stake = 0),
              child: Text(tr('Jouer gratuit', 'Play for free'),
                  style: TextStyle(color: _stake == 0 ? _gold : Colors.white70, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
        Text(
          _paid
              ? tr('Joueurs (chacun se connecte à son compte)', 'Players (each one signs in)')
              : tr('Joueurs', 'Players'),
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _n; i++) _row(i),
        if (broke != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('Solde insuffisant : $broke', 'Insufficient balance: $broke'),
                style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
          ),
        if (_paid)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr('Cagnotte ${_fcfa(_stake * _n)} · commission Katika 5 %',
                  'Pot ${_fcfa(_stake * _n)} · Katika fee 5 %'),
              style: const TextStyle(color: Color(0xFF7CFFB0), fontWeight: FontWeight.w800),
            ),
          ),
        SizedBox(
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5262B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _ready ? _start : null,
            child: Text(
              _starting
                  ? tr('Mise en cours...', 'Placing stakes...')
                  : (_stake <= 0 || !firebaseReady
                      ? tr('Lancer · partie gratuite', 'Start · free game')
                      : tr('Lancer · mise ${_fcfa(_stake)}', 'Start · stake ${_fcfa(_stake)}')),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// TIAH — présentiel
// ======================================================================

class TiahLocalPage extends StatefulWidget {
  const TiahLocalPage({super.key});

  @override
  State<TiahLocalPage> createState() => _TiahLocalPageState();
}

class _TiahLocalPageState extends State<TiahLocalPage> {
  final Sfx _sfx = Sfx();
  _Table? _t;
  int _round = 0;

  // manche
  List<List<_Card>> _hands = [];
  List<_Card> _pile = [];
  List<int> _order = []; // ordre de passage (sièges)
  int _cur = 0; // index dans _order
  int _phase = 0; // 0 passer le téléphone, 1 cartes ouvertes, 2 résultat
  bool _dealing = false;
  bool _turnDone = false;
  bool _autoTaking = false; // les cartes du milieu partent toutes seules vers le joueur
  int _left = 30; // secondes restantes pour ouvrir ses cartes
  Timer? _timer;
  List<int> _winners = [];
  int _jackpot = 0;
  String? _settleError;
  final List<int> _wins = List.filled(6, 0);

  int get _n => _t!.n;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _t == null || _dealing || _phase != 0 || _autoTaking) return;
      if (_left > 0) setState(() => _left--);
      if (_left <= 0) _open();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Joueurs qui ont déjà ouvert leurs cartes (pas de pari possible avec eux).
  Set<int> get _played {
    final s = <int>{};
    if (_phase == 2) return {for (var i = 0; i < _n; i++) i};
    for (var k = 0; k < _cur; k++) {
      s.add(_order[k]);
    }
    if (_phase == 1) s.add(_order[_cur]);
    return s;
  }

  int _total(List<_Card> h) => h.fold(0, (a, c) => a + c.v);

  void _deal() {
    final deck = _newDeck(withAce: true);
    final n = _n;
    final start = _round % n; // le 1er joueur change à chaque manche (sens horaire)
    _hands = List.generate(n, (_) => <_Card>[]);
    for (var k = 0; k < 2 * n; k++) {
      _hands[(start + k) % n].add(deck.removeLast());
    }
    _pile = deck;
    _order = [for (var k = 0; k < n; k++) (start + k) % n];
    _cur = 0;
    _phase = 0;
    _turnDone = false;
    _autoTaking = false;
    _left = 30;
    _winners = [];
    _jackpot = 0;
    _settleError = null;
    _dealing = true;
  }

  /// Le joueur ouvre ses cartes : les cartes du milieu qui lui conviennent partent toutes seules,
  /// dans l'ordre (la 1re d'abord), tant que son total ne dépasse pas 21.
  Future<void> _open() async {
    if (_phase != 0 || _autoTaking) return;
    final seat = _order[_cur];
    setState(() {
      _phase = 1;
      _turnDone = false;
      _autoTaking = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    while (mounted && _pile.isNotEmpty && _total(_hands[seat]) + _pile.last.v <= 21) {
      setState(() => _hands[seat].add(_pile.removeLast()));
      _sfx.land();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (!mounted) return;
    if (_total(_hands[seat]) == 21) _sfx.win();
    setState(() {
      _autoTaking = false;
      _turnDone = true;
    });
  }

  Future<void> _next() async {
    if (_cur + 1 < _n) {
      setState(() {
        _cur++;
        _phase = 0;
        _turnDone = false;
        _left = 30;
      });
      return;
    }
    // Fin de manche
    final totals = [for (final h in _hands) _total(h)];
    var best = -1;
    for (final x in totals) {
      if (x <= 21 && x > best) best = x;
    }
    final w = <int>[
      for (var i = 0; i < _n; i++)
        if (best < 0 || totals[i] == best) i,
    ];
    setState(() {
      _winners = w;
      _phase = 2;
      for (final s in w) {
        if (w.length < _n) _wins[s]++;
      }
    });
    try {
      final jp = await _t!.settle(w, scores: _scores());
      if (mounted && jp > 0) setState(() => _jackpot = jp);
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  List<int> _scores() => [for (final h in _hands) _total(h) > 21 ? -1 : _total(h)];

  Future<void> _retrySettle() async {
    try {
      final jp = await _t!.settle(_winners, scores: _scores());
      if (mounted) {
        setState(() {
          _settleError = null;
          if (jp > 0) _jackpot = jp;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  Future<void> _rematch() async {
    try {
      await _t!.begin();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
      setState(() => _t = null);
      return;
    }
    setState(() {
      _round++;
      _deal();
    });
  }

  Widget _scaffold(Widget child) => Scaffold(
        body: Stack(children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: _felt,
            child: SafeArea(child: child),
          ),
          if (_dealing && _t != null)
            Positioned.fill(
              child: _DealOverlay(
                names: [for (final s in _order) _t!.names[s]],
                batches: const [2],
                labels: [tr('Distribution…', 'Dealing…')],
                sfx: _sfx,
                onDone: () {
                  if (mounted) setState(() => _dealing = false);
                },
              ),
            ),
        ]),
      );

  Widget _topBar() => Row(children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        Expanded(
          child: Text(
            'TIAH · ${tr('manche', 'round')} ${_round + 1}${_t!.staked ? ' · ${_fcfa(_t!.stake)}' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        if (_t!.staked && _phase != 2 && !_autoTaking)
          TextButton.icon(
            onPressed: () => _showLocalBets(context, table: _t!, played: _played, boubayah: false),
            icon: const Icon(Icons.casino, color: _goldSoft, size: 18),
            label: Text(tr('Paris', 'Bets'), style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w800)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.layers, color: _goldSoft, size: 16),
            const SizedBox(width: 4),
            Text('${_pile.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 8),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_t == null) {
      return _scaffold(_CardsSetup(
        title: 'TIAH · ${tr('présentiel', 'face to face')}',
        game: 'tiah',
        onStart: (t) async {
          setState(() {
            _t = t;
            _round = 0;
            _deal();
          });
        },
      ));
    }
    if (_phase == 2) return _scaffold(_results());
    final seat = _order[_cur];
    final name = _t!.names[seat];
    if (_phase == 0) {
      return _scaffold(Column(children: [
        _topBar(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(radius: 38, backgroundColor: _seatColors[seat],
                      child: Text((name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1200)))),
                  const SizedBox(height: 14),
                  Text(tr('Au tour de', 'Next up'),
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    tr('Passe-lui le téléphone : personne d\'autre ne doit voir ses cartes.',
                        'Hand over the phone: nobody else should see these cards.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < _n; i++)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: i == seat ? _gold : Colors.white24,
                          label: Text(_t!.names[_order[i]],
                              style: TextStyle(
                                  color: i == _cur ? const Color(0xFF1A1200) : Colors.white70, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('⏱ $_left s',
                      style: TextStyle(
                          color: _left <= 10 ? const Color(0xFFFF8A80) : _goldSoft,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  Text(tr('À 0, tes cartes s\'ouvrent toutes seules.', 'At 0 your cards open by themselves.'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5262B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: _open,
                      child: Text(tr('Ouvrir mes cartes', 'Open my cards'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]));
    }
    // phase 1 : cartes ouvertes + cartes du milieu à taper
    final hand = _hands[seat];
    final total = _total(hand);
    final bust = total > 21;
    return _scaffold(Column(children: [
      _topBar(),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          children: [
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < hand.length; i++)
                    _PopIn(
                      key: ValueKey('$seat-${hand[i].v}-${hand[i].suit}'),
                      delayMs: i >= 2 ? 0 : i * 250,
                      child: _CardView(card: hand[i], w: 56),
                    ),
                ],
              ),
            ),
            Center(
              child: Text('$total',
                  style: TextStyle(
                      color: total == 21 ? _gold : (bust ? const Color(0xFFFF8A80) : Colors.white),
                      fontSize: 54,
                      fontWeight: FontWeight.w900)),
            ),
            if (total == 21)
              const Center(
                child: Text('TIAH !',
                    style: TextStyle(color: _gold, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
              ),
            if (bust)
              Center(
                child: Text(tr('Plus de 21 : pas de score', 'Over 21: no score'),
                    style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 8),
            Text(
              _autoTaking
                  ? tr('Les cartes du milieu qui te conviennent arrivent, dans l\'ordre…',
                      'Matching middle cards are coming to you, in order…')
                  : (_turnDone
                      ? tr('Ton score est affiché. Passe le téléphone au suivant.',
                          'Your score is shown. Pass the phone on.')
                      : ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(tr('Cartes du milieu (dans l\'ordre)', 'Middle cards (in order)'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            _MiddleStrip(cards: _pile.reversed.toList(), w: 36),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22B14C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _turnDone ? _next : null,
            child: Text(
              _cur + 1 < _n
                  ? tr('Joueur suivant · passer le téléphone', 'Next player · pass the phone')
                  : tr('Voir le résultat de la manche', 'See the round result'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ]));
  }

  Widget _results() {
    final t = _t!;
    final totals = [for (final h in _hands) _total(h)];
    final idx = List<int>.generate(_n, (i) => i)
      ..sort((a, b) {
        final ta = totals[a] > 21 ? -1 : totals[a];
        final tb = totals[b] > 21 ? -1 : totals[b];
        return tb.compareTo(ta);
      });
    final pay = t.payPerWinner(_winners);
    final refund = _winners.length == _n;
    return Column(children: [
      _topBar(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: const Color(0xFF1B8A3A)),
              child: Column(children: [
                Text(
                  refund
                      ? tr('Égalité générale', 'General tie')
                      : (_winners.length == 1
                          ? tr('${t.names[_winners.first]} gagne !', '${t.names[_winners.first]} wins!')
                          : tr('Victoire partagée : ${_winners.map((s) => t.names[s]).join(', ')}',
                              'Shared win: ${_winners.map((s) => t.names[s]).join(', ')}')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                if (t.staked)
                  Text(
                    refund
                        ? tr('Chaque joueur récupère sa mise (${_fcfa(t.stake)}), sans commission.',
                            'Everyone gets their stake back (${_fcfa(t.stake)}), no fee.')
                        : tr('+ ${_fcfa(pay)} par gagnant (commission Katika 5 % déduite)',
                            '+ ${_fcfa(pay)} per winner (5 % Katika fee deducted)'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                if (_jackpot > 0)
                  Text(tr('🎰 Jackpot : ${_fcfa(_jackpot)} !', '🎰 Jackpot: ${_fcfa(_jackpot)}!'),
                      style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w900)),
              ]),
            ),
            if (_settleError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(_settleError!, style: const TextStyle(color: Color(0xFFFF8A80))),
                  ),
                  TextButton(onPressed: _retrySettle, child: Text(tr('Réessayer', 'Retry'))),
                ]),
              ),
            const SizedBox(height: 12),
            for (var r = 0; r < idx.length; r++) _resultRow(idx[r], r, totals),
            if (_remainingPileNote() != null) _remainingPileNote()!,
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5262B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _settleError != null ? null : _rematch,
              child: Text(
                t.staked
                    ? tr('Manche suivante · mise ${_fcfa(t.stake)}', 'Next round · stake ${_fcfa(t.stake)}')
                    : tr('Manche suivante', 'Next round'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _t = null),
            child: Text(tr('Changer la mise ou les joueurs', 'Change stake or players'),
                style: const TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    ]);
  }

  Widget? _remainingPileNote() => null;

  Widget _resultRow(int seat, int rank, List<int> totals) {
    final t = _t!;
    final win = _winners.contains(seat) && _winners.length < _n;
    final bust = totals[seat] > 21;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: win ? const Color(0x2E7CFFB0) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: win ? const Color(0xFF7CFFB0) : Colors.white24, width: 1.5),
      ),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: _seatColors[seat],
            child: Text('${rank + 1}', style: const TextStyle(color: Color(0xFF1A1200), fontWeight: FontWeight.w900))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.names[seat]}${_wins[seat] > 0 ? '  🏆${_wins[seat]}' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 3, children: [for (final c in _hands[seat]) _CardView(card: c, w: 26)]),
          ]),
        ),
        Column(children: [
          Text('${totals[seat]}',
              style: TextStyle(
                  color: totals[seat] == 21 ? _gold : (bust ? const Color(0xFFFF8A80) : Colors.white),
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          if (totals[seat] == 21)
            const Text('TIAH', style: TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 11)),
          if (bust) Text(tr('dépasse', 'bust'), style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11)),
        ]),
      ]),
    );
  }
}

// ======================================================================
// BOUBAYAH — présentiel
// ======================================================================

class BoubayahLocalPage extends StatefulWidget {
  const BoubayahLocalPage({super.key});

  @override
  State<BoubayahLocalPage> createState() => _BoubayahLocalPageState();
}

class _BoubayahLocalPageState extends State<BoubayahLocalPage> {
  final Sfx _sfx = Sfx();
  _Table? _t;
  int _round = 0;
  int _dealer = 0;

  List<List<_Card>> _plain = []; // 3 cartes ordinaires
  List<List<_Card>> _bouba = []; // 2 cartes BOUBAYAH
  final List<int> _revealed = []; // ordre de révélation (sièges)
  final Set<int> _peek = {};
  bool _over = false;
  List<int> _winners = [];
  bool _fomekou = false;
  int _nextDealer = 0;
  int _jackpot = 0;
  String? _settleError;
  final List<int> _wins = List.filled(6, 0);
  final List<String> _history = [];
  bool _dealing = false;
  int _left = 30; // secondes pour ouvrir son BOUBAYAH
  int _leftSeat = -1;
  Timer? _timer;

  int get _n => _t!.n;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _t == null || _dealing || _over) return;
      final s = _toReveal;
      if (s < 0) return;
      if (s != _leftSeat) {
        setState(() {
          _leftSeat = s;
          _left = 30;
        });
        return;
      }
      if (_left > 0) setState(() => _left--);
      if (_left <= 0) _reveal(s);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<int> _scores() => [for (var s = 0; s < _n; s++) _isFomekou(s) ? 100 : _total(s)];
  List<int> _fscores() => [for (var s = 0; s < _n; s++) _isFomekou(s) ? 6 : _total(s)];

  int _total(int s) => _bouba[s][0].v + _bouba[s][1].v;
  bool _isFomekou(int s) => _bouba[s][0].v == 3 && _bouba[s][1].v == 3;

  /// Ordre de révélation : à partir du joueur qui suit le distributeur.
  int get _toReveal {
    final order = [for (var k = 1; k <= _n; k++) (_dealer + k) % _n];
    for (final s in order) {
      if (!_revealed.contains(s)) return s;
    }
    return -1;
  }

  void _deal() {
    final deck = _newDeck(withAce: false); // 32 cartes : 3 à 10, 4 couleurs
    final n = _n;
    // 1re distribution : 3 cartes ordinaires ; 2e : 2 cartes BOUBAYAH
    _plain = List.generate(n, (_) => <_Card>[]);
    _bouba = List.generate(n, (_) => <_Card>[]);
    for (var k = 0; k < 3; k++) {
      for (var i = 0; i < n; i++) {
        _plain[(_dealer + 1 + i) % n].add(deck.removeLast());
      }
    }
    for (var k = 0; k < 2; k++) {
      for (var i = 0; i < n; i++) {
        _bouba[(_dealer + 1 + i) % n].add(deck.removeLast());
      }
    }
    _dealing = true;
    _left = 30;
    _leftSeat = -1;
    _revealed.clear();
    _peek.clear();
    _over = false;
    _winners = [];
    _fomekou = false;
    _jackpot = 0;
    _settleError = null;
  }

  Future<void> _reveal(int seat) async {
    if (_revealed.contains(seat) || _over) return;
    setState(() {
      _revealed.add(seat);
      _left = 30;
      _leftSeat = -1;
    });
    if (_isFomekou(seat)) _sfx.win();
    if (_revealed.length < _n) return;
    // Calcul du résultat
    final fom = [for (final s in _revealed) if (_isFomekou(s)) s]; // dans l'ordre de révélation
    List<int> w;
    int nd;
    if (fom.isNotEmpty) {
      w = fom;
      nd = fom.first;
    } else {
      var best = 0;
      for (var s = 0; s < _n; s++) {
        if (_total(s) > best) best = _total(s);
      }
      w = [for (final s in _revealed) if (_total(s) == best) s];
      nd = w.first;
    }
    setState(() {
      _over = true;
      _fomekou = fom.isNotEmpty;
      _winners = w;
      _nextDealer = nd;
      if (w.length < _n) {
        for (final s in w) {
          _wins[s]++;
        }
      }
      _history.insert(
          0,
          '${tr('Manche', 'Round')} ${_round + 1} : ${w.map((s) => _t!.names[s]).join(', ')}'
          '${_fomekou ? ' (FOMEKOU)' : ' (${_total(w.first)})'}');
    });
    try {
      final jp = await _t!.settle(w, scores: _scores(), fscores: _fscores());
      if (mounted && jp > 0) setState(() => _jackpot = jp);
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  Future<void> _retrySettle() async {
    try {
      final jp = await _t!.settle(_winners, scores: _scores(), fscores: _fscores());
      if (mounted) {
        setState(() {
          _settleError = null;
          if (jp > 0) _jackpot = jp;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  Future<void> _nextRound() async {
    try {
      await _t!.begin();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
      setState(() => _t = null);
      return;
    }
    setState(() {
      _round++;
      _dealer = _nextDealer; // le gagnant devient distributeur
      _deal();
    });
  }

  Widget _seatTile(int seat) {
    final t = _t!;
    final open = _revealed.contains(seat);
    final mine = _toReveal == seat && !_over;
    final win = _over && _winners.contains(seat) && _winners.length < _n;
    final peek = _peek.contains(seat);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: win ? const Color(0x2E7CFFB0) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: win ? const Color(0xFF7CFFB0) : (mine ? _gold : Colors.white24), width: mine || win ? 2 : 1.2),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 12, backgroundColor: _seatColors[seat]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t.names[seat]}${seat == _dealer ? '  🃏' : ''}${_wins[seat] > 0 ? '  🏆${_wins[seat]}' : ''}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          if (mine && !_dealing)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('⏱ $_left s',
                  style: TextStyle(
                      color: _left <= 10 ? const Color(0xFFFF8A80) : _goldSoft,
                      fontWeight: FontWeight.w900)),
            ),
          if (open)
            Text('${_total(seat)}',
                style: TextStyle(
                    color: _isFomekou(seat) ? _gold : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          GestureDetector(
            onTap: () => setState(() => peek ? _peek.remove(seat) : _peek.add(seat)),
            child: Row(children: [
              for (final c in _plain[seat])
                Padding(padding: const EdgeInsets.only(right: 3), child: _CardView(card: c, up: peek || _over, w: 28)),
            ]),
          ),
          const Spacer(),
          for (final c in _bouba[seat])
            Padding(padding: const EdgeInsets.only(left: 6), child: _CardView(card: c, up: open, w: 52)),
        ]),
        if (open && _isFomekou(seat))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('FOMEKOU !',
                style: TextStyle(color: _gold, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 18)),
          ),
        if (mine)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _reveal(seat),
                child: Text(tr('OUVRIR MON BOUBAYAH', 'OPEN MY BOUBAYAH'),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget wrap(Widget c) => Scaffold(
          body: Stack(children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: _felt,
              child: SafeArea(child: c),
            ),
            if (_dealing && _t != null)
              Positioned.fill(
                child: _DealOverlay(
                  names: [for (var k = 1; k <= _n; k++) _t!.names[(_dealer + k) % _n]],
                  batches: const [3, 2],
                  labels: [tr('Cartes ordinaires', 'Ordinary cards'), tr('Cartes BOUBAYAH', 'BOUBAYAH cards')],
                  sfx: _sfx,
                  onDone: () {
                    if (mounted) setState(() => _dealing = false);
                  },
                ),
              ),
          ]),
        );
    if (_t == null) {
      return wrap(_CardsSetup(
        title: 'BOUBAYAH · ${tr('présentiel', 'face to face')}',
        game: 'boubayah',
        onStart: (t) async {
          setState(() {
            _t = t;
            _round = 0;
            _dealer = 0;
            _wins.fillRange(0, 6, 0);
            _history.clear();
            _deal();
          });
        },
      ));
    }
    final t = _t!;
    final pay = t.payPerWinner(_winners);
    final refund = _over && _winners.length == _n;
    return wrap(Column(children: [
      Row(children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        Expanded(
          child: Text(
            'BOUBAYAH · ${tr('manche', 'round')} ${_round + 1}${t.staked ? ' · ${_fcfa(t.stake)}' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        if (t.staked && !_over && !_dealing)
          TextButton.icon(
            onPressed: () =>
                _showLocalBets(context, table: t, played: _revealed.toSet(), boubayah: true),
            icon: const Icon(Icons.casino, color: _goldSoft, size: 18),
            label: Text(tr('Paris', 'Bets'), style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w800)),
          ),
      ]),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _over
                    ? ''
                    : tr('🃏 Distributeur : ${t.names[_dealer]} · touche les petites cartes pour les voir',
                        '🃏 Dealer: ${t.names[_dealer]} · tap the small cards to peek'),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            if (_over)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: const Color(0xFF1B8A3A)),
                child: Column(children: [
                  if (_fomekou)
                    const Text('FOMEKOU !',
                        style: TextStyle(color: _gold, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  Text(
                    refund
                        ? tr('Égalité générale', 'General tie')
                        : (_winners.length == 1
                            ? tr('${t.names[_winners.first]} gagne !', '${t.names[_winners.first]} wins!')
                            : tr('Victoire partagée : ${_winners.map((s) => t.names[s]).join(', ')}',
                                'Shared win: ${_winners.map((s) => t.names[s]).join(', ')}')),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  if (t.staked)
                    Text(
                      refund
                          ? tr('Chaque joueur récupère sa mise, sans commission.',
                              'Everyone gets their stake back, no fee.')
                          : tr('+ ${_fcfa(pay)} par gagnant (commission 5 % déduite)',
                              '+ ${_fcfa(pay)} per winner (5 % fee deducted)'),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  Text(tr('Prochain distributeur : ${t.names[_nextDealer]}', 'Next dealer: ${t.names[_nextDealer]}'),
                      style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w800)),
                  if (_jackpot > 0)
                    Text(tr('🎰 Jackpot : ${_fcfa(_jackpot)} !', '🎰 Jackpot: ${_fcfa(_jackpot)}!'),
                        style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w900)),
                ]),
              ),
            if (_settleError != null)
              Row(children: [
                Expanded(child: Text(_settleError!, style: const TextStyle(color: Color(0xFFFF8A80)))),
                TextButton(onPressed: _retrySettle, child: Text(tr('Réessayer', 'Retry'))),
              ]),
            for (var k = 1; k <= _n; k++) _seatTile((_dealer + k) % _n),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(tr('Historique', 'History'),
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              for (final h in _history.take(8))
                Text(h, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      ),
      if (_over)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _settleError != null ? null : _nextRound,
                child: Text(
                  tr('${t.names[_nextDealer]} distribue la manche suivante${t.staked ? ' · ${_fcfa(t.stake)}' : ''}',
                      '${t.names[_nextDealer]} deals the next round${t.staked ? ' · ${_fcfa(t.stake)}' : ''}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _t = null),
              child: Text(tr('Changer la mise ou les joueurs', 'Change stake or players'),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ]),
        ),
    ]));
  }
}


// ======================================================================
// En ligne : salon (liste des salles) et salle de jeu
// ======================================================================

_Card _decode(int c) => _Card(c ~/ 4, c % 4);

List<_Card> _cardsOf(dynamic l) =>
    l is List ? [for (final x in l) _decode((x as num).toInt())] : <_Card>[];

String? _firstOf(Iterable<String> i) => i.isEmpty ? null : i.first;

String _gameTitle(String g) => g == 'tiah' ? 'TIAH' : 'BOUBAYAH';

class CardsOnlineHub extends StatefulWidget {
  const CardsOnlineHub({super.key, required this.game});

  final String game;

  @override
  State<CardsOnlineHub> createState() => _CardsOnlineHubState();
}

class _CardsOnlineHubState extends State<CardsOnlineHub> {
  Timer? _timer;
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _mine = [];
  int _stake = 0;
  int _max = 4;
  bool _public = true;
  bool _busy = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(dynamic l) =>
      l is List ? [for (final x in l) Map<String, dynamic>.from(x as Map)] : [];

  Future<void> _load() async {
    try {
      final r = await Wallet.cardsList(widget.game);
      if (!mounted) return;
      setState(() {
        _open = _list(r['open']);
        _mine = _list(r['mine']);
      });
    } catch (_) {}
  }

  void _snack(Object e) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));

  Future<void> _enter(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardsOnlineRoom(gameId: id)));
    if (mounted) _load();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final v = await Wallet.cardsCreate(
        game: widget.game,
        stake: _stake,
        maxPlayers: _max,
        isPublic: _public,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _enter(v['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e);
      }
    }
  }

  Future<void> _join({String? id, String? code}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final v = await Wallet.cardsJoin(gameId: id, code: code);
      if (!mounted) return;
      setState(() => _busy = false);
      await _enter(v['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e);
      }
    }
  }

  Widget _roomTile(Map<String, dynamic> r, String action, VoidCallback f) {
    final stake = (r['stake'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['hostName'] ?? ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            Text(
              '${stake > 0 ? _fcfa(stake) : tr('Gratuit', 'Free')} · ${r['count']}/${r['maxPlayers']} ${tr('joueurs', 'players')}'
              '${((r['round'] as num?)?.toInt() ?? 1) > 1 ? ' · ${tr('manche', 'round')} ${r['round']}' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: const Color(0xFF1A1200)),
          onPressed: _busy ? null : f,
          child: Text(action, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _felt,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                Expanded(
                  child: Text('${_gameTitle(widget.game)} · ${tr('en ligne', 'online')}',
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                ),
                if (uid != null)
                  StreamBuilder<int>(
                    stream: Wallet.watch(uid),
                    builder: (context, s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _gold, width: 1.5),
                      ),
                      child: Text(Wallet.format(s.data ?? 0),
                          style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
              ]),
              if (_mine.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('Mes parties en cours', 'My ongoing games'),
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final r in _mine) _roomTile(r, tr('Reprendre', 'Resume'), () => _enter(r['id'] as String)),
              ],
              const SizedBox(height: 10),
              Text(tr('Créer une salle', 'Create a room'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(tr('Mise de chaque joueur (0 = gratuit)', "Each player's stake (0 = free)"),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              StakeField(stake: _stake, players: _max, onChanged: (v) => setState(() => _stake = v)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _stake = 0),
                  child: Text(tr('Jouer gratuit', 'Play for free'),
                      style: TextStyle(color: _stake == 0 ? _gold : Colors.white70, fontWeight: FontWeight.w800)),
                ),
              ),
              Text(tr('Nombre de joueurs maximum', 'Maximum players'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Wrap(spacing: 8, children: [
                for (var k = 2; k <= 6; k++)
                  ChoiceChip(
                    label: Text('$k'),
                    selected: _max == k,
                    selectedColor: _gold,
                    onSelected: (_) => setState(() => _max = k),
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: _gold,
                title: Text(tr('Salle publique', 'Public room'), style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    tr('Sinon, on y entre avec le code seulement', 'Otherwise, join with the code only'),
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                value: _public,
                onChanged: (v) => setState(() => _public = v),
              ),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5262B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _busy ? null : _create,
                  child: Text(
                    _stake > 0
                        ? tr('Créer · mise ${_fcfa(_stake)}', 'Create · stake ${_fcfa(_stake)}')
                        : tr('Créer · salle gratuite', 'Create · free room'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(tr('Rejoindre avec un code', 'Join with a code'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 3),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      hintText: 'CODE',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: const Color(0xFF1A1200)),
                  onPressed: _busy || _code.text.trim().length < 4 ? null : () => _join(code: _code.text.trim()),
                  child: Text(tr('Rejoindre', 'Join'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ]),
              const SizedBox(height: 18),
              Text(tr('Salles ouvertes', 'Open rooms'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              if (_open.isEmpty)
                Text(tr('Aucune salle pour le moment : crée la tienne !', 'No room yet: create yours!'),
                    style: const TextStyle(color: Colors.white60)),
              for (final r in _open) _roomTile(r, tr('Rejoindre', 'Join'), () => _join(id: r['id'] as String)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Salle de jeu en ligne (TIAH ou BOUBAYAH) : le serveur est l'arbitre.
class CardsOnlineRoom extends StatefulWidget {
  const CardsOnlineRoom({super.key, required this.gameId});

  final String gameId;

  @override
  State<CardsOnlineRoom> createState() => _CardsOnlineRoomState();
}

class _CardsOnlineRoomState extends State<CardsOnlineRoom> {
  final Sfx _sfx = Sfx();
  Timer? _timer;
  Map<String, dynamic>? _v;
  DateTime _rx = DateTime.now();
  bool _busy = false;
  String? _err;
  final Set<String> _announced = {};
  String? _dealtFor;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _v != null && _v!['over'] != true) setState(() {});
    });
  }

  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _set(Map<String, dynamic> v) {
    if (!mounted) return;
    // « TIAH ! » / « FOMEKOU ! » : son dès qu'une main spéciale apparaît
    final pl = v['players'] as List? ?? [];
    for (final p in pl) {
      final m = Map<String, dynamic>.from(p as Map);
      final key = '${v['id']}-${m['uid']}';
      final special = v['game'] == 'tiah' ? m['total'] == 21 : m['fomekou'] == true;
      if (special && !_announced.contains(key)) {
        _announced.add(key);
        if (_v != null) _sfx.win();
      }
    }
    // Distribution déjà passée si la manche est déjà entamée à l'arrivée
    if (_v == null && (v['status'] != 'playing' || pl.any((p) => (p as Map)['opened'] == true))) {
      _dealtFor = '${v['id']}';
    }
    setState(() {
      _v = v;
      _rx = DateTime.now();
      _err = null;
    });
  }

  Future<void> _poll() async {
    if (_busy) return;
    try {
      _set(await Wallet.cardsGet(widget.gameId));
    } catch (e) {
      if (mounted && _v == null) setState(() => _err = Wallet.errorText(e));
    }
  }

  Future<void> _do(Future<Map<String, dynamic>> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _set(await f());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _goNext(Future<Map<String, dynamic>> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await f();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => CardsOnlineRoom(gameId: r['id'] as String)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
      }
    }
  }

  Future<void> _leave() async {
    final v = _v;
    if (v != null && v['status'] == 'waiting') {
      try {
        await Wallet.cardsLeave(widget.gameId);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _shell(Widget child, {Widget? overlay}) => Scaffold(
        body: Stack(children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: _felt,
            child: SafeArea(child: child),
          ),
          if (overlay != null) Positioned.fill(child: overlay),
        ]),
      );

  Widget _bar(Map<String, dynamic> v) {
    final stake = (v['stake'] as num?)?.toInt() ?? 0;
    return Row(children: [
      IconButton(
        onPressed: () {
          if (v['status'] == 'waiting') {
            _leave();
          } else {
            Navigator.of(context).maybePop();
          }
        },
        icon: const Icon(Icons.arrow_back, color: Colors.white),
      ),
      Expanded(
        child: Text(
          '${_gameTitle('${v['game']}')} · ${tr('manche', 'round')} ${v['round']}'
          '${stake > 0 ? ' · ${_fcfa(stake)}' : ''}',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return _shell(Center(
        child: _err != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  TextButton(onPressed: _poll, child: Text(tr('Réessayer', 'Retry'))),
                ]),
              )
            : const CircularProgressIndicator(color: _gold),
      ));
    }
    final status = '${v['status']}';
    if (status == 'cancelled') {
      return _shell(Center(child: Text(tr('Salle fermée', 'Room closed'), style: const TextStyle(color: Colors.white))));
    }
    if (status == 'waiting') return _shell(_lobby(v));
    final id = '${v['id']}';
    final needDeal = status == 'playing' && _dealtFor != id;
    Widget? overlay;
    if (needDeal) {
      final plv = [for (final p in v['players'] as List) Map<String, dynamic>.from(p as Map)];
      final seq = [for (final u in (v['seq'] as List? ?? [])) '$u'];
      final names = [
        for (final u in seq) _firstOf(plv.where((p) => p['uid'] == u).map((p) => '${p['name']}')) ?? '?',
      ];
      final tiahGame = v['game'] == 'tiah';
      overlay = _DealOverlay(
        names: names.isEmpty ? [for (final p in plv) '${p['name']}'] : names,
        batches: tiahGame ? const [2] : const [3, 2],
        labels: tiahGame
            ? [tr('Distribution…', 'Dealing…')]
            : [tr('Cartes ordinaires', 'Ordinary cards'), tr('Cartes BOUBAYAH', 'BOUBAYAH cards')],
        sfx: _sfx,
        onDone: () {
          if (mounted) setState(() => _dealtFor = id);
        },
      );
    }
    return _shell(_table(v), overlay: overlay);
  }

  // ---------------------------------------------------------------- salle d'attente

  Widget _lobby(Map<String, dynamic> v) {
    final players = [for (final p in v['players'] as List) Map<String, dynamic>.from(p as Map)];
    final stake = (v['stake'] as num?)?.toInt() ?? 0;
    final max = (v['maxPlayers'] as num?)?.toInt() ?? 6;
    final dealer = '${v['dealerUid']}';
    final canStart = v['canStart'] == true;
    final dealerName = _firstOf(players.where((p) => p['uid'] == dealer).map((p) => '${p['name']}'));
    return Column(children: [
      _bar(v),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Text(tr('Code de la salle', 'Room code'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '${v['code']}'));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr('Code copié', 'Code copied'))));
                  },
                  child: Text('${v['code']}',
                      style: const TextStyle(color: _gold, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6)),
                ),
                Text(tr('Touche le code pour le copier et invite tes amis', 'Tap the code to copy it and invite friends'),
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Text(
                  '${stake > 0 ? '${tr('Mise', 'Stake')} ${_fcfa(stake)} · ${tr('cagnotte', 'pot')} ${_fcfa((v['pot'] as num).toInt())}' : tr('Partie gratuite', 'Free game')}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text('${tr('Joueurs', 'Players')} ${players.length}/$max',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            for (var i = 0; i < players.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  CircleAvatar(radius: 12, backgroundColor: _seatColors[i % 6]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${players[i]['name']}${players[i]['uid'] == _me ? ' (${tr('toi', 'you')})' : ''}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  if (players[i]['uid'] == dealer) const Text('🃏', style: TextStyle(fontSize: 18)),
                ]),
              ),
            const SizedBox(height: 8),
            if (players.length < 2)
              Text(tr('En attente d\'autres joueurs…', 'Waiting for more players…'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            if (players.length >= 2 && !canStart)
              Text(
                tr('${dealerName ?? 'Le distributeur'} lance la manche.', '${dealerName ?? 'The dealer'} starts the round.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5262B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: canStart && !_busy ? () => _do(() => Wallet.cardsStart(widget.gameId)) : null,
              child: Text(
                tr('Lancer la manche (${players.length} joueurs)', 'Start the round (${players.length} players)'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          TextButton(
            onPressed: _leave,
            child: Text(tr('Quitter (mise remboursée)', 'Leave (stake refunded)'),
                style: const TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    ]);
  }

  // ---------------------------------------------------------------- table de jeu

  int get _secLeft {
    final v = _v!;
    final ms = (v['turnLeftMs'] as num?)?.toInt() ?? 0;
    final left = ms - DateTime.now().difference(_rx).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  Widget _table(Map<String, dynamic> v) {
    final tiah = v['game'] == 'tiah';
    final players = [for (final p in v['players'] as List) Map<String, dynamic>.from(p as Map)];
    final over = v['over'] == true;
    final turn = '${v['turnUid']}';
    final myTurn = !over && turn == _me;
    final winners = [for (final w in (v['winnerUids'] as List? ?? [])) '$w'];
    String nameOf(String uid) => _firstOf(players.where((p) => p['uid'] == uid).map((p) => '${p['name']}')) ?? '?';
    final stake = (v['stake'] as num?)?.toInt() ?? 0;
    final refund = over && winners.length == players.length;
    final iWon = winners.contains(_me) && !refund;
    final nextId = '${v['nextId']}';

    return Column(children: [
      _bar(v),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            if (!over)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      myTurn
                          ? tr('C\'est ton tour !', "It's your turn!")
                          : tr('Au tour de ${nameOf(turn)}', "${nameOf(turn)}'s turn"),
                      style: TextStyle(
                          color: myTurn ? _gold : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17),
                    ),
                  ),
                  if (tiah)
                    Text('🂠 ${v['pile']}', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 10),
                  Text('⏱ $_secLeft s', style: const TextStyle(color: Colors.white70)),
                ]),
              ),
            if (tiah && !over) _middlePile(v, players, myTurn),
            _betsPanel(v, players, tiah),
            if (over)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: iWon ? const Color(0xFF1B8A3A) : (refund ? const Color(0xFF546E7A) : const Color(0xFF8E2A22)),
                ),
                child: Column(children: [
                  if (v['fomekou'] == true)
                    const Text('FOMEKOU !',
                        style: TextStyle(color: _gold, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  Text(
                    refund
                        ? tr('Égalité générale', 'General tie')
                        : (iWon
                            ? tr('Tu as gagné !', 'You won!')
                            : (winners.length == 1
                                ? tr('${nameOf(winners.first)} gagne', '${nameOf(winners.first)} wins')
                                : tr('Victoire de ${winners.map(nameOf).join(', ')}',
                                    'Won by ${winners.map(nameOf).join(', ')}'))),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                  if (stake > 0 && (iWon || refund))
                    Text(
                      refund
                          ? tr('Mise remboursée : ${_fcfa(stake)}', 'Stake refunded: ${_fcfa(stake)}')
                          : tr('+ ${_fcfa((v['prize'] as num).toInt())} sur ton compte',
                              '+ ${_fcfa((v['prize'] as num).toInt())} to your account'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  if (!tiah && '${v['nextDealerUid']}'.isNotEmpty)
                    Text(tr('Prochain distributeur : ${nameOf('${v['nextDealerUid']}')}',
                            'Next dealer: ${nameOf('${v['nextDealerUid']}')}'),
                        style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w800)),
                ]),
              ),
            for (final p in players) _playerCard(v, p, turn, winners, over, tiah),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: over
            ? Column(children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE5262B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _goNext(() => nextId.isEmpty
                            ? Wallet.cardsRematch(widget.gameId)
                            : Wallet.cardsJoin(gameId: nextId)),
                    child: Text(
                      nextId.isEmpty
                          ? tr('Manche suivante${stake > 0 ? ' · ${_fcfa(stake)}' : ''}',
                              'Next round${stake > 0 ? ' · ${_fcfa(stake)}' : ''}')
                          : tr('Rejoindre la manche suivante${stake > 0 ? ' · ${_fcfa(stake)}' : ''}',
                              'Join the next round${stake > 0 ? ' · ${_fcfa(stake)}' : ''}'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(tr('Quitter la table', 'Leave the table'), style: const TextStyle(color: Colors.white70)),
                ),
              ])
            : SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B1FA2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: !myTurn || _busy ? null : () => _do(() => Wallet.cardsOpen(widget.gameId)),
                  child: Text(
                    tiah ? tr('OUVRIR MES CARTES', 'OPEN MY CARDS') : tr('OUVRIR MON BOUBAYAH', 'OPEN MY BOUBAYAH'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _playerCard(Map<String, dynamic> v, Map<String, dynamic> p, String turn, List<String> winners, bool over, bool tiah) {
    final uid = '${p['uid']}';
    final mine = uid == _me;
    final isTurn = !over && uid == turn;
    final win = over && winners.contains(uid) && winners.length < (v['players'] as List).length;
    final opened = p['opened'] == true;
    final total = (p['total'] as num?)?.toInt();
    final special = tiah ? total == 21 : p['fomekou'] == true;
    final dealer = uid == '${v['dealerUid']}';
    final idx = (v['players'] as List).indexWhere((x) => (x as Map)['uid'] == uid);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: win ? const Color(0x2E7CFFB0) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: win ? const Color(0xFF7CFFB0) : (isTurn ? _gold : Colors.white24), width: isTurn || win ? 2 : 1.2),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 12, backgroundColor: _seatColors[idx % 6]),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${p['name']}${mine ? ' (${tr('toi', 'you')})' : ''}${dealer ? '  🃏' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          if (total != null)
            Text('$total',
                style: TextStyle(color: special ? _gold : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        if (tiah) _tiahCards(p, opened || over) else _boubaCards(p, opened || over),
        if (special)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tiah ? 'TIAH !' : 'FOMEKOU !',
                style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 18)),
          ),
        if (tiah && total != null && total > 21)
          Text(tr('dépasse 21', 'over 21'), style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
      ]),
    );
  }

  /// Cartes du milieu, classées dans l'ordre : elles partent toutes seules vers le joueur qui ouvre.
  Widget _middlePile(Map<String, dynamic> v, List<Map<String, dynamic>> players, bool myTurn) {
    final cards = [for (final x in (v['pileCards'] as List? ?? [])) _decode((x as num).toInt())];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          tr('Cartes du milieu, dans l\'ordre (${cards.length})', 'Middle cards, in order (${cards.length})'),
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          tr('Dès qu\'un joueur ouvre ses cartes, celles qui lui conviennent (sans dépasser 21) partent vers lui, une par une.',
              'As soon as a player opens, the cards that fit (without going over 21) go to him, one by one.'),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _MiddleStrip(cards: cards, w: 36),
      ]),
    );
  }

  // ---------------------------------------------------------------- paris

  Widget _betsPanel(Map<String, dynamic> v, List<Map<String, dynamic>> players, bool tiah) {
    final bets = [for (final b in (v['bets'] as List? ?? [])) Map<String, dynamic>.from(b as Map)];
    final over = v['over'] == true;
    final stake = (v['stake'] as num?)?.toInt() ?? 0;
    if (stake <= 0 && bets.isEmpty) return const SizedBox.shrink();
    final myP = players.where((p) => p['uid'] == _me).toList();
    final iOpened = myP.isNotEmpty && myP.first['opened'] == true;
    String nameOf(String u) => _firstOf(players.where((p) => p['uid'] == u).map((p) => '${p['name']}')) ?? '?';
    String label(Map<String, dynamic> b) {
      final amt = _fcfa((b['amount'] as num).toInt());
      final who = '${b['proposerName']}';
      if (b['type'] == 'fetiche') {
        final side = b['side'] == 'under' ? tr('moins', 'under') : tr('plus', 'over');
        return '$who : $side ${tr('de', 'than')} 13 · $amt';
      }
      final tgt = '${b['targetName']}'.isEmpty ? tr('tous ses adversaires', 'all rivals') : '${b['targetName']}';
      return '$who ⚔ $tgt · $amt';
    }

    String status(Map<String, dynamic> b) {
      switch ('${b['status']}') {
        case 'open':
          return tr('en attente', 'waiting');
        case 'accepted':
          return '${tr('accepté par', 'accepted by')} ${b['opponentName']}';
        case 'cancelled':
          return tr('annulé', 'cancelled');
        case 'declined':
          return tr('refusé', 'declined');
        case 'expired':
          return tr('expiré · remboursé', 'expired · refunded');
        case 'settled':
          final w = '${b['winnerUid']}';
          if (b['result'] == 'refund' || w.isEmpty) return tr('égalité · remboursé', 'tie · refunded');
          return '${tr('gagné par', 'won by')} ${nameOf(w)}';
        default:
          return '${b['status']}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.casino, color: _goldSoft, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('Paris entre joueurs', 'Bets between players'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          if (!over && stake > 0 && !iOpened)
            TextButton(
              onPressed: _busy ? null : () => _newBet(v, players, tiah),
              child: Text(tr('+ Parier', '+ Bet'), style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
            ),
        ]),
        if (bets.isEmpty)
          Text(
            iOpened
                ? tr('Tu as ouvert tes cartes : plus de nouveau pari pour toi.', 'You opened your cards: no new bets for you.')
                : tr('Défie un adversaire avant qu\'il ouvre ses cartes.', 'Challenge a rival before he opens his cards.'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        for (final b in bets)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label(b), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(status(b), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              if ('${b['status']}' == 'open' && !over) ...[
                if (b['proposerUid'] == _me)
                  TextButton(
                    onPressed: _busy ? null : () => _do(() => Wallet.cardsBetCancel(widget.gameId, '${b['id']}')),
                    child: Text(tr('Annuler', 'Cancel')),
                  )
                else if (!iOpened && ('${b['targetUid']}'.isEmpty || b['targetUid'] == _me)) ...[
                  TextButton(
                    onPressed: _busy ? null : () => _do(() => Wallet.cardsBetAccept(widget.gameId, '${b['id']}')),
                    child: Text(tr('Relever', 'Accept'),
                        style: const TextStyle(color: Color(0xFF7CFFB0), fontWeight: FontWeight.w900)),
                  ),
                  if ('${b['targetUid']}' == _me)
                    TextButton(
                      onPressed: _busy ? null : () => _do(() => Wallet.cardsBetCancel(widget.gameId, '${b['id']}')),
                      child: Text(tr('Refuser', 'Decline')),
                    ),
                ],
              ],
            ]),
          ),
      ]),
    );
  }

  Future<void> _newBet(Map<String, dynamic> v, List<Map<String, dynamic>> players, bool tiah) async {
    final stake = (v['stake'] as num?)?.toInt() ?? 0;
    final amountCtrl = TextEditingController(text: '${stake > Wallet.minStake ? stake : Wallet.minStake}');
    final targets = [
      for (final p in players)
        if (p['uid'] != _me && p['opened'] != true) p,
    ];
    String type = 'duel';
    String target = ''; // '' = tous
    bool over = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF062E1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Nouveau pari', 'New bet'),
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: Text(tr('Défier ses adversaires', 'Challenge rivals')),
                  selected: type == 'duel',
                  selectedColor: _gold,
                  onSelected: (_) => setS(() => type = 'duel'),
                ),
                if (!tiah)
                  ChoiceChip(
                    label: Text(tr('Défi Fétiche (13)', 'Fetish challenge (13)')),
                    selected: type == 'fetiche',
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => type = 'fetiche'),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                type == 'duel'
                    ? tr(tiah ? 'Le meilleur total (21 max) gagne. Égalité : mises rendues.' : 'Le plus gros score gagne (FOMEKOU bat tout). Égalité : mises rendues.',
                        tiah ? 'Best total (21 max) wins. Tie: stakes refunded.' : 'Highest score wins (FOMEKOU beats all). Tie: stakes refunded.')
                    : tr('Ton total BOUBAYAH est comparé à 13. FOMEKOU compte 6 (donc « moins de 13 »). 13 pile : mises rendues.',
                        'Your BOUBAYAH total is compared with 13. FOMEKOU counts as 6 (so under 13). Exactly 13: stakes refunded.'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              if (type == 'duel') ...[
                const SizedBox(height: 8),
                DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0B4A2C),
                  value: target,
                  items: [
                    DropdownMenuItem<String>(
                        value: '',
                        child: Text(tr('Tous mes adversaires', 'All my rivals'), style: const TextStyle(color: Colors.white))),
                    for (final p in targets)
                      DropdownMenuItem<String>(
                          value: '${p['uid']}', child: Text('${p['name']}', style: const TextStyle(color: Colors.white))),
                  ],
                  onChanged: (x) => setS(() => target = x ?? ''),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(
                    label: Text(tr('Plus de 13', 'Over 13')),
                    selected: over,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => over = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(tr('Moins de 13', 'Under 13')),
                    selected: !over,
                    selectedColor: _gold,
                    onSelected: (_) => setS(() => over = false),
                  ),
                ]),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: tr('Mise du pari (FCFA)', 'Bet amount (FCFA)'),
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5262B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (amount < Wallet.minStake) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(tr('Mise minimum : ${_fcfa(Wallet.minStake)}', 'Minimum: ${_fcfa(Wallet.minStake)}'))));
                      return;
                    }
                    Navigator.of(ctx).pop();
                    _do(() => Wallet.cardsBetPropose(
                          gameId: widget.gameId,
                          type: type,
                          amount: amount,
                          targetUid: type == 'duel' && target.isNotEmpty ? target : null,
                          over: over,
                        ));
                  },
                  child: Text(tr('Proposer le pari', 'Offer the bet'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    amountCtrl.dispose();
  }

  Widget _tiahCards(Map<String, dynamic> p, bool show) {
    final cards = _cardsOf(p['cards']);
    if (show && cards.isNotEmpty) {
      return Wrap(spacing: 5, runSpacing: 5, children: [
        for (var i = 0; i < cards.length; i++)
          _PopIn(
            key: ValueKey('${p['uid']}-${cards[i].v}-${cards[i].suit}'),
            delayMs: i >= 2 ? i * 450 - 900 : 0,
            child: _CardView(card: cards[i], w: 40),
          ),
      ]);
    }
    final n = (p['count'] as num?)?.toInt() ?? 2;
    return Row(children: [for (var i = 0; i < n; i++) Padding(padding: const EdgeInsets.only(right: 5), child: _CardView(card: null, up: false, w: 40))]);
  }

  Widget _boubaCards(Map<String, dynamic> p, bool open) {
    final plain = _cardsOf(p['plain']);
    final bouba = _cardsOf(p['bouba']);
    final mine = '${p['uid']}' == _me;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < ((p['count'] as num?)?.toInt() ?? 3); i++)
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: _CardView(card: i < plain.length ? plain[i] : null, up: i < plain.length, w: 28),
        ),
      const Spacer(),
      for (var i = 0; i < 2; i++)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Opacity(
            opacity: mine && !open ? 0.8 : 1,
            child: _CardView(card: i < bouba.length ? bouba[i] : null, up: i < bouba.length, w: 50),
          ),
        ),
    ]);
  }
}
