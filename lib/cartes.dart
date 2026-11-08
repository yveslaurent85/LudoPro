import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';
import 'main.dart' show firebaseReady, Sfx;
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
                        () => _go(context, const _CardModePage(game: 'tiah')), badge: tr('NOUVEAU', 'NEW')),
                    const SizedBox(height: 14),
                    _card('BOUBAYAH', tr('Le plus gros total gagne · 2 à 6 joueurs', 'Highest total wins · 2-6 players'),
                        Icons.filter_5, const Color(0xFF7B1FA2),
                        () => _go(context, const _CardModePage(game: 'boubayah')), badge: tr('NOUVEAU', 'NEW')),
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
                          () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => tiah ? const TiahLocalPage() : const BoubayahLocalPage(),
                          )),
                        ),
                        tile(
                          Icons.public,
                          tr('En ligne', 'Online'),
                          tr('Bientôt : chacun joue depuis son téléphone', 'Soon: everyone plays from their own phone'),
                          const Color(0xFFE5262B),
                          null,
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

  int get n => names.length;
  bool get staked => stake > 0 && firebaseReady;

  /// Débite les mises d'une manche (partie payante).
  Future<void> begin() async {
    settled = false;
    localId = null;
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
  Future<int> settle(List<int> winSeats) async {
    final id = localId;
    if (id == null || settled || !staked) return 0;
    settled = true;
    try {
      final res = await Wallet.settleLocalFull(
        id,
        [for (final s in winSeats) accounts[s]!.uid],
        [for (var i = 0; i < n; i++) winSeats.contains(i) ? 1 : 0],
      );
      return (res['jackpot'] as num?)?.toInt() ?? 0;
    } catch (_) {
      settled = false;
      rethrow;
    }
  }

  /// Gain de chaque gagnant, 0 si gratuit ; en cas d'égalité générale : remboursement.
  int payPerWinner(List<int> winSeats) {
    if (stake <= 0) return 0;
    if (winSeats.length == n) return stake; // remboursement
    return Wallet.prize(stake * n, local: true) ~/ winSeats.length;
  }
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
  bool _drawing = false;
  bool _turnDone = false;
  int _taken = 0; // cartes prises dans le tour courant
  List<int> _winners = [];
  int _jackpot = 0;
  String? _settleError;
  final List<int> _wins = List.filled(6, 0);

  int get _n => _t!.n;

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
    _taken = 0;
    _winners = [];
    _jackpot = 0;
    _settleError = null;
  }

  Future<void> _open() async {
    final seat = _order[_cur];
    setState(() {
      _phase = 1;
      _drawing = true;
      _turnDone = false;
      _taken = 0;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // Prise obligatoire tant que la carte du dessus ne fait pas dépasser 21.
    while (mounted && _pile.isNotEmpty && _total(_hands[seat]) + _pile.last.v <= 21) {
      setState(() {
        _hands[seat].add(_pile.removeLast());
        _taken++;
      });
      _sfx.land();
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    if (!mounted) return;
    if (_total(_hands[seat]) == 21) _sfx.win();
    setState(() {
      _drawing = false;
      _turnDone = true;
    });
  }

  Future<void> _next() async {
    if (_cur + 1 < _n) {
      setState(() {
        _cur++;
        _phase = 0;
        _turnDone = false;
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
      final jp = await _t!.settle(w);
      if (mounted && jp > 0) setState(() => _jackpot = jp);
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  Future<void> _retrySettle() async {
    try {
      final jp = await _t!.settle(_winners);
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
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: _felt,
          child: SafeArea(child: child),
        ),
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
                  const SizedBox(height: 22),
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
    // phase 1 : cartes ouvertes
    final hand = _hands[seat];
    final total = _total(hand);
    final bust = total > 21;
    return _scaffold(Column(children: [
      _topBar(),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < hand.length; i++)
                      Opacity(opacity: i < 2 ? 1 : 0.95, child: _CardView(card: hand[i], w: 60)),
                  ],
                ),
                const SizedBox(height: 18),
                Text('$total',
                    style: TextStyle(
                        color: total == 21 ? _gold : (bust ? const Color(0xFFFF8A80) : Colors.white),
                        fontSize: 64,
                        fontWeight: FontWeight.w900)),
                if (total == 21)
                  const Text('TIAH !',
                      style: TextStyle(color: _gold, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4)),
                if (bust)
                  Text(tr('Plus de 21 : pas de score', 'Over 21: no score'),
                      style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w800)),
                if (_drawing)
                  Text(tr('Prise des cartes du milieu…', 'Taking cards from the middle…'),
                      style: const TextStyle(color: Colors.white70))
                else if (_turnDone && _taken == 0 && !bust && total != 21)
                  Text(tr('La carte suivante ferait dépasser 21.', 'The next card would go over 21.'),
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                  ? tr('Cacher et passer le téléphone', 'Hide and pass the phone')
                  : tr('Terminer la manche', 'End the round'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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

  int get _n => _t!.n;

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
    _revealed.clear();
    _peek.clear();
    _over = false;
    _winners = [];
    _fomekou = false;
    _jackpot = 0;
    _settleError = null;
  }

  Future<void> _reveal(int seat) async {
    setState(() => _revealed.add(seat));
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
      final jp = await _t!.settle(w);
      if (mounted && jp > 0) setState(() => _jackpot = jp);
    } catch (e) {
      if (mounted) setState(() => _settleError = Wallet.errorText(e));
    }
  }

  Future<void> _retrySettle() async {
    try {
      final jp = await _t!.settle(_winners);
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
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: _felt,
            child: SafeArea(child: c),
          ),
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
