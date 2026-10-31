import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'game_chat.dart';
import 'dice3d.dart';
import 'lang.dart';
import 'main.dart';
import 'jackpot_live.dart';
import 'local_side_bets.dart';
import 'online_screen.dart';
import 'painters.dart';
import 'rejouer.dart';
import 'side_bets.dart';

// ----------------------------------------------------------------------
// Deux dés : chaque joueur a son compte, en présentiel comme en ligne.
// En ligne : collection Firestore « deuxdes » (voir les règles à ajouter).
// ----------------------------------------------------------------------

const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

const List<Color> _palette = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
  Color(0xFFFF8A1F),
  Color(0xFF8E44AD),
  Color(0xFFEC5FA6),
  Color(0xFF14B8B0),
];
const List<String> _colorNames = [
  'Rouge',
  'Vert',
  'Bleu',
  'Jaune',
  'Orange',
  'Violet',
  'Rose',
  'Turquoise',
];
const List<int> _counts = [2, 3, 4, 5, 6, 7, 8];

CollectionReference<Map<String, dynamic>> get _rooms =>
    FirebaseFirestore.instance.collection('deuxdes');

List<int> _ints(dynamic l, List<int> fallback) =>
    l is List ? l.map((e) => (e as num).toInt()).toList() : fallback;

List<int> _randomSpin(Random r) => [
      (r.nextBool() ? 1 : -1) * (1 + r.nextInt(2)),
      (r.nextBool() ? 1 : -1) * (2 + r.nextInt(2)),
      (r.nextBool() ? 1 : -1) * (1 + r.nextInt(2)),
    ];

String _userName(User u) {
  final n = u.displayName;
  if (n != null && n.isNotEmpty) return n;
  return u.email ?? 'Joueur';
}

String _newCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

List<Map<String, dynamic>> _playersOf(Map<String, dynamic> d) =>
    ((d['players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

/// Places gagnantes : celles qui ont le score le plus élevé (ex æquo possibles).
List<int> _winnersOf(List<int> scores) {
  if (scores.isEmpty) return const [];
  final best = scores.reduce(max);
  return [for (int i = 0; i < scores.length; i++) if (scores[i] == best) i];
}

/// Écran avec fond bleu, bouton retour et titre.
class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bg,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

Widget _hint(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );

Widget _tile(String title, String subtitle, String button, VoidCallback? onTap) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withOpacity(0.12),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22B14C),
            foregroundColor: Colors.white,
          ),
          onPressed: onTap,
          child: Text(button),
        ),
      ],
    ),
  );
}

// ----------------------------------------------------------------------
// Menu : présentiel ou en ligne
// ----------------------------------------------------------------------

class DeuxDesPage extends StatelessWidget {
  const DeuxDesPage({super.key});

  /// Il faut être connecté à son compte (sauf si Firebase est absent,
  /// auquel cas seul le présentiel sans compte est possible).
  void _go(BuildContext context, Widget Function(BuildContext) page) {
    final loggedIn =
        !firebaseReady || FirebaseAuth.instance.currentUser != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) =>
            loggedIn ? page(c) : OnlineScreen(onSignedIn: page),
      ),
    );
  }

  Widget _card(IconData icon, String title, String subtitle, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [shade(color, 0.08), shade(color, -0.12)],
          ),
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Deux dés',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _card(
              Icons.groups,
              'En présentiel',
              'Chaque joueur se connecte à son compte',
              const Color(0xFF22B14C),
              () => _go(context, (_) => const _LocalSetup()),
            ),
            const SizedBox(height: 14),
            _card(
              Icons.public,
              'En ligne',
              'Chacun joue depuis son téléphone',
              const Color(0xFF1E6BFF),
              () {
                if (!firebaseReady) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Le jeu en ligne est indisponible.'),
                    ),
                  );
                  return;
                }
                _go(context, (_) => const _OnlineHub());
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Plateau commun (présentiel et en ligne) : dés 3D, scores, fin de partie
// ----------------------------------------------------------------------

/// Choix de la mise + gain du gagnant (partagé entre présentiel et en ligne).
/// [local] = true : présentiel, commission de 10 % (5 % en ligne).
Widget _stakeBox(int stake, int players, void Function(int) onPick,
    {bool local = false}) {
  final pct =
      local ? Wallet.commissionLocalPercent : Wallet.commissionPercent;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in Wallet.stakes)
            ChoiceChip(
              label: Text(Wallet.stakeLabel(v)),
              selected: stake == v,
              onSelected: (_) => onPick(v),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        stake == 0
            ? 'Partie gratuite : aucun jeton en jeu, pas de jackpot.'
            : tr(
                'Gain du gagnant : ${Wallet.format(Wallet.prize(stake * players, local: local))} '
                '(cagnotte ${stake * players}, commission $pct %)',
                'Winner gets: ${Wallet.format(Wallet.prize(stake * players, local: local))} '
                '(pot ${stake * players}, commission $pct %)',
              ),
        style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13),
      ),
    ],
  );
}

String _stakeText(Map<String, dynamic> d) {
  final s = (d['stake'] as num?)?.toInt();
  if (s == null) return '';
  return s > 0 ? tr(' • mise $s', ' • stake $s') : tr(' • gratuite', ' • free');
}

/// Date et heure de création d'une partie : « • 24/10/2026 19:55 ».
String _createdText(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return ' • ${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class _DiceTable extends StatefulWidget {
  const _DiceTable({
    required this.names,
    required this.scores,
    required this.cur,
    required this.d1,
    required this.d2,
    required this.spin1,
    required this.spin2,
    required this.rolled,
    required this.rollN,
    required this.canAct,
    required this.onRoll,
    required this.onNext,
    this.over = false,
    this.winners = const [],
    this.stake = 0,
    this.jackpot = 0,
    this.local = false,
    this.endExtra,
    this.onTimeout,
    this.onForce,
    this.uids = const [],
    this.reactions,
  });

  /// uid de chaque joueur (parties en ligne) : sert à envoyer un emoji.
  final List<String> uids;

  /// Emojis envoyés aux joueurs : ils s'affichent devant le joueur.
  final EmojiReactions? reactions;

  /// Le joueur n'a pas joué dans les 30 s : cet appareil joue à sa place
  /// (appelé seulement quand [canAct] est vrai).
  final VoidCallback? onTimeout;

  /// Joueur absent : 8 s après la fin du décompte, n'importe quel appareil
  /// peut jouer à sa place (parties en ligne).
  final VoidCallback? onForce;

  final List<String> names;
  final List<int> scores;
  final int cur;
  final int d1;
  final int d2;
  final List<int> spin1;
  final List<int> spin2;

  /// Le joueur courant a déjà lancé ses dés.
  final bool rolled;

  /// Compteur de lancers : chaque changement déclenche l'animation
  /// (donc aussi chez les adversaires en ligne).
  final int rollN;

  /// Cet appareil peut jouer le tour en cours.
  final bool canAct;
  final VoidCallback onRoll;
  final VoidCallback onNext;

  /// Partie finie : tous les joueurs ont lancé. [winners] = places gagnantes.
  final bool over;
  final List<int> winners;
  final int stake;
  final int jackpot;

  /// Présentiel : commission de 10 % au lieu de 5 %.
  final bool local;

  /// Proposition de rejouer, affichée dans le panneau de fin.
  final Widget? endExtra;

  @override
  State<_DiceTable> createState() => _DiceTableState();
}

class _DiceTableState extends State<_DiceTable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1.0, // au repos
  );

  /// Sons : roulement des dés, « toc » à l'arrêt, fanfare de fin.
  final Sfx _sfx = Sfx();

  // --- Décompte de 30 s par joueur ------------------------------------
  static const int _limit = 30;
  Timer? _timer;
  int _left = _limit;
  int _turnKey = -1;
  int _fired = 0; // 0 : rien, 1 : appareil du joueur, 2 : relais

  @override
  void initState() {
    super.initState();
    _syncTurn();
  }

  void _syncTurn() {
    if (widget.over) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_turnKey != widget.cur) {
      _turnKey = widget.cur;
      _left = _limit;
      _fired = 0;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    if (widget.over) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    setState(() => _left--);
    if (_left <= 0 && widget.canAct && _fired < 1) {
      _fired = 1;
      widget.onTimeout?.call();
    }
    if (_left <= -8 && _fired < 2) {
      _fired = 2;
      widget.onForce?.call();
    }
  }

  @override
  void didUpdateWidget(covariant _DiceTable old) {
    super.didUpdateWidget(old);
    _syncTurn();
    if (widget.rollN != old.rollN) {
      _sfx.roll();
      _c.forward(from: 0).then((_) {
        if (!mounted) return;
        _sfx.land();
        if (widget.over) _sfx.win();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  String _name(int i) => i < widget.names.length ? widget.names[i] : '?';

  Widget _die(int value, List<int> spin) {
    final color = _palette[widget.cur % _palette.length];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final bounce = sin(t * pi * 4).abs() * (1 - t) * 30;
        return Transform.translate(
          offset: Offset(0, -bounce),
          child: SizedBox(
            width: 110,
            height: 110,
            child: Die3D(
              value: value,
              t: t,
              spin: spin,
              color: color,
              glow: _c.isAnimating,
            ),
          ),
        );
      },
    );
  }

  /// Félicitations au vainqueur (ou aux ex æquo) + « Katika décharge les caisses ».
  Widget _endPanel() {
    final w = widget.winners;
    final tie = w.length > 1;
    final color = _palette[(w.isEmpty ? 0 : w.first) % _palette.length];
    final who = w.map(_name).join(' & ');
    final pot = widget.stake * widget.names.length;
    final share =
        w.isEmpty ? 0 : Wallet.prize(pot, local: widget.local) ~/ w.length;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1B66),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.7),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            const Text('👑', style: TextStyle(fontSize: 52)),
            Text(
              tie
                  ? tr('🤝 Égalité : $who !', '🤝 It\'s a tie: $who!')
                  : tr('🏆 Félicitations $who !', '🏆 Congratulations $who!'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFC21A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (w.isNotEmpty)
              Text(
                tr('avec ${widget.scores[w.first]} points',
                    'with ${widget.scores[w.first]} points'),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            if (widget.stake > 0 && w.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                tie
                    ? tr('Cagnotte partagée : ${Wallet.format(share)} chacun',
                        'Pot shared: ${Wallet.format(share)} each')
                    : tr('Gain : ${Wallet.format(share)}',
                        'Prize: ${Wallet.format(share)}'),
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (widget.jackpot > 0) ...[
              const SizedBox(height: 6),
              Text(
                tr('🎰 JACKPOT gagné : ${Wallet.format(widget.jackpot)} !',
                    '🎰 JACKPOT won: ${Wallet.format(widget.jackpot)}!'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Katika décharge les caisses',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.endExtra != null) ...[
              const SizedBox(height: 12),
              widget.endExtra!,
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Accueil'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[widget.cur % _palette.length];
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  tr('Lancer ${widget.cur + 1}/${widget.names.length}',
                      'Roll ${widget.cur + 1}/${widget.names.length}'),
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xFF0A1B66),
                    border: Border.all(color: color, width: 2.5),
                  ),
                  child: Text(
                    tr('Au tour de : ${_name(widget.cur)}',
                        'Turn of: ${_name(widget.cur)}'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!widget.over) ...[
                  const SizedBox(height: 8),
                  Text(
                    '⏱ ${_left < 0 ? 0 : _left} s',
                    style: TextStyle(
                      color: _left <= 10
                          ? const Color(0xFFFF8A80)
                          : const Color(0xFFFFE082),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _die(widget.d1, widget.spin1),
                    const SizedBox(width: 24),
                    _die(widget.d2, widget.spin2),
                  ],
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Text(
                    _c.isAnimating
                        ? '...'
                        : (widget.rolled
                            ? 'Total : ${widget.d1 + widget.d2}'
                            : ' '),
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final busy = _c.isAnimating;
                    if (widget.over) {
                      return busy ? const SizedBox(height: 60) : _endPanel();
                    }
                    if (!widget.canAct) {
                      return Text(
                        tr('En attente de ${_name(widget.cur)}...',
                            'Waiting for ${_name(widget.cur)}...'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      );
                    }
                    return Column(
                      children: [
                        SizedBox(
                          width: 220,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22B14C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: (!widget.rolled && !busy)
                                ? widget.onRoll
                                : null,
                            child: const Text('Lancer'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 220,
                          height: 44,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: (widget.rolled && !busy)
                                ? widget.onNext
                                : null,
                            child: const Text('Joueur suivant'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final showEnd = widget.over && !_c.isAnimating;
                    return Column(
                      children: [
                        for (int i = 0; i < widget.names.length; i++)
                          Builder(
                            builder: (rowCtx) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // On touche un joueur pour lui envoyer un emoji.
                              onTap: (widget.reactions != null &&
                                      i < widget.uids.length)
                                  ? () => showEmojiPicker(
                                        rowCtx,
                                        title: tr(
                                            'Emoji pour ${widget.names[i]}',
                                            'Emoji for ${widget.names[i]}'),
                                        onPick: (e) => widget.reactions!
                                            .send(widget.uids[i], e),
                                      )
                                  : null,
                              child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white
                                  .withOpacity(i == widget.cur ? 0.2 : 0.1),
                              border: Border.all(
                                color: (showEnd && widget.winners.contains(i))
                                    ? const Color(0xFFFFC21A)
                                    : _palette[i % _palette.length],
                                width: (i == widget.cur || showEnd) ? 2.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                    radius: 9, backgroundColor: _palette[i % _palette.length]),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${widget.names[i]}'
                                    '${(showEnd && widget.winners.contains(i)) ? ' 👑' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                // Emoji reçu : il s'affiche devant le joueur.
                                if (widget.reactions != null &&
                                    i < widget.uids.length)
                                  SizedBox(
                                    width: 36,
                                    height: 30,
                                    child: Center(
                                      child: EmojiBubble(
                                        reactions: widget.reactions!,
                                        uid: widget.uids[i],
                                        size: 28,
                                        placeholder: true,
                                      ),
                                    ),
                                  ),
                                Text(
                                  // Le score du joueur qui lance reste caché
                                  // pendant que les dés roulent.
                                  (_c.isAnimating && i == widget.cur)
                                      ? '?'
                                      : '${i < widget.scores.length ? widget.scores[i] : 0}',
                                  style: const TextStyle(
                                    color: Color(0xFFFFE082),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        // Confettis quand les dés ont fini de rouler et que la partie est finie.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => (widget.over && !_c.isAnimating)
                  ? const Confetti()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Présentiel : chaque joueur se connecte à son compte, un seul téléphone
// ----------------------------------------------------------------------

class _LocalSetup extends StatefulWidget {
  const _LocalSetup();

  @override
  State<_LocalSetup> createState() => _LocalSetupState();
}

class _LocalSetupState extends State<_LocalSetup> {
  int numPlayers = 2;
  int stake = Wallet.minStake;
  bool starting = false;

  /// Paris préparés avant le début (placés dès que la partie démarre).
  final List<PendingBet> pending = [];

  /// Comptes connectés, par place (0 = joueur principal).
  final Map<int, PlayerAccount> accounts = {};
  late final List<TextEditingController> ctrls =
      List.generate(8, (_) => TextEditingController());

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
    for (final c in ctrls) {
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
    setState(() {
      accounts[0] = PlayerAccount(
        idToken: token,
        uid: u.uid,
        name: _userName(u),
        email: u.email ?? '',
        balance: bal,
      );
    });
  }

  /// Noms des joueurs de cette partie (compte connecté, sinon la couleur).
  List<String> get _seatNames => [
        for (int i = 0; i < numPlayers; i++)
          accounts[i]?.name ?? tr('Joueur ${_colorNames[i]}', 'Player ${_colorNames[i]}'),
      ];

  Future<void> _addPending() async {
    final b = await pickPendingBet(context, _seatNames);
    if (b != null && mounted) setState(() => pending.add(b));
  }

  /// Section « Paris avant la partie » (présentiel avec mise).
  Widget _pendingSection() {
    final names = _seatNames;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black26,
        border: Border.all(color: Colors.white38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('🎲 Paris avant la partie (Duel, Défi 7)',
                      '🎲 Bets before the game (Duel, 7 challenge)'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: numPlayers < 2 ? null : _addPending,
                child: Text(
                  tr('+ Parier', '+ Bet'),
                  style: const TextStyle(
                    color: Color(0xFFFFC21A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (pending.isEmpty)
            Text(
              tr('Tu peux aussi parier pendant la partie, tant que le joueur '
                  "n'a pas lancé ses dés.",
                  'You can also bet during the game, as long as the player has '
                      "not rolled yet."),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          for (int i = 0; i < pending.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    pending[i].describe(names),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => pending.removeAt(i)),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool get ready =>
      !firebaseReady ||
      List.generate(numPlayers, (i) => i).every(accounts.containsKey);

  /// Nom du premier joueur dont le solde ne couvre pas la mise.
  String? get brokePlayer {
    if (!firebaseReady) return null;
    for (int s = 0; s < numPlayers; s++) {
      final a = accounts[s];
      if (a != null && a.balance < stake) return a.name;
    }
    return null;
  }

  Future<void> _connect(int seat) async {
    final acc = await showPlayerLogin(
      context,
      colorName: _colorNames[seat],
      color: _palette[seat],
    );
    if (acc == null || !mounted) return;
    final already =
        accounts.entries.any((e) => e.key != seat && e.value.uid == acc.uid);
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce compte joue déjà dans la partie.')),
      );
      return;
    }
    setState(() => accounts[seat] = acc);
  }

  Widget _row(int seat) {
    final acc = accounts[seat];
    Widget field;
    if (!firebaseReady) {
      field = TextField(
        controller: ctrls[seat],
        maxLength: 12,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          hintText:
              tr('Joueur ${_colorNames[seat]}', 'Player ${_colorNames[seat]}'),
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
    } else if (acc != null) {
      field = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: _palette[seat], width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              acc.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '💰 ${Wallet.format(acc.balance)}',
              style: const TextStyle(color: Color(0xFFFFE082), fontSize: 12),
            ),
          ],
        ),
      );
    } else {
      field = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: _palette[seat], width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _connect(seat),
        icon: const Icon(Icons.login),
        label: Text(tr('Joueur ${_colorNames[seat]} : se connecter',
            'Player ${_colorNames[seat]}: sign in')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: _palette[seat]),
          const SizedBox(width: 12),
          Expanded(child: field),
          if (firebaseReady && acc != null && seat != 0)
            IconButton(
              tooltip: tr('Changer de compte', 'Switch account'),
              onPressed: () => setState(() => accounts.remove(seat)),
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  /// Débite les mises sur le serveur, puis lance la partie.
  Future<void> _start() async {
    if (starting) return;
    final n = numPlayers;
    String? localId;
    var tokenList = <String>[];
    final uids = List<String?>.filled(n, null);

    if (firebaseReady) {
      setState(() => starting = true);
      try {
        final tokens = <String>[];
        for (int s = 0; s < n; s++) {
          final a = accounts[s]!;
          uids[s] = a.uid;
          if (a.uid == FirebaseAuth.instance.currentUser?.uid) {
            final u = FirebaseAuth.instance.currentUser;
            tokens.add((await u?.getIdToken(true)) ?? '');
          } else {
            tokens.add(a.idToken ?? '');
          }
        }
        tokenList = tokens;
        localId = await Wallet.startLocalGame(
          stake: stake,
          tokens: tokens,
          names: [for (int s = 0; s < n; s++) accounts[s]!.name],
          game: 'deuxdes',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Wallet.errorText(e))),
        );
        return;
      }
      if (!mounted) return;
      setState(() => starting = false);
    }

    final names = <String>[
      for (int i = 0; i < n; i++)
        firebaseReady
            ? accounts[i]!.name
            : (ctrls[i].text.trim().isNotEmpty
                ? ctrls[i].text.trim()
                : tr('Joueur ${_colorNames[i]}', 'Player ${_colorNames[i]}')),
    ];

    // Paris préparés avant la partie : placés maintenant (mises débitées).
    var placedBets = <String>[];
    if (firebaseReady && localId != null && stake > 0 && pending.isNotEmpty) {
      final r = await placePendingBets(
        localId: localId,
        tokens: tokenList,
        names: names,
        bets: List<PendingBet>.from(pending),
      );
      placedBets = r.placed;
      if (r.errors.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.errors.first)),
        );
      }
    }
    if (mounted) setState(pending.clear);

    final rematch = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute<List<int>>(
        builder: (_) => _LocalGame(
          names: names,
          stake: firebaseReady ? stake : 0,
          localId: localId,
          uids: uids,
          tokens: tokenList,
          initialBets: placedBets,
        ),
      ),
    );
    if (!mounted) return;

    // Des joueurs veulent rejouer : on relance avec ceux qui ont accepté.
    if (rematch != null && rematch.length >= 2) {
      await _rematch(rematch);
      return;
    }

    // Soldes à jour : le joueur principal est rechargé, les invités se
    // reconnectent pour la partie suivante.
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      setState(() => accounts.removeWhere((k, _) => k != 0));
      if (u != null) _loadHost(u);
    }
  }

  /// Rejouer avec les joueurs qui ont accepté (leurs places dans la partie
  /// finie). Ils reprennent les premières places, chacun repaie sa mise.
  Future<void> _rematch(List<int> accepted) async {
    final oldAcc = Map<int, PlayerAccount>.from(accounts);
    final oldTxt = [for (final c in ctrls) c.text];
    setState(() {
      numPlayers = accepted.length;
      accounts.clear();
      for (int i = 0; i < accepted.length; i++) {
        final from = accepted[i];
        final a = oldAcc[from];
        if (a != null) accounts[i] = a;
        ctrls[i].text = oldTxt[from];
      }
    });
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final broke = brokePlayer;
    return _Shell(
      title: 'Deux dés · présentiel',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('Nombre de joueurs'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in _counts)
                ChoiceChip(
                  label: Text('$n'),
                  selected: numPlayers == n,
                  onSelected: (_) => setState(() {
                    numPlayers = n;
                    pending.removeWhere((b) => b.pSeat >= n || b.oSeat >= n);
                  }),
                ),
            ],
          ),
          if (firebaseReady) ...[
            const SizedBox(height: 14),
            const JackpotBanner(),
            _label('Mise de chaque joueur (jetons)'),
            _stakeBox(stake, numPlayers, (v) => setState(() => stake = v),
                local: true),
            if (stake > 0) _pendingSection(),
          ],
          _label(firebaseReady
              ? 'Joueurs (chacun se connecte à son compte)'
              : 'Joueurs'),
          for (int i = 0; i < numPlayers; i++) _row(i),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: (!ready || broke != null || starting) ? null : _start,
              child: Text(
                starting
                    ? 'Mise en cours...'
                    : !ready
                        ? 'Tous les joueurs doivent se connecter'
                        : (broke != null
                            ? tr('Solde insuffisant : $broke',
                                'Insufficient balance: $broke')
                            : (firebaseReady
                                ? (stake == 0
                                    ? 'Lancer · partie gratuite'
                                    : tr('Lancer · mise ${Wallet.format(stake)}',
                                        'Start · stake ${Wallet.format(stake)}'))
                                : 'Lancer la partie')),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalGame extends StatefulWidget {
  const _LocalGame({
    required this.names,
    this.stake = 0,
    this.localId,
    this.uids = const [],
    this.tokens = const [],
    this.initialBets = const [],
  });

  /// Paris déjà placés avant le début de la partie.
  final List<String> initialBets;

  final List<String> names;
  final int stake;

  /// Identifiant de la partie côté serveur (null = pas de mise).
  final String? localId;

  /// uid du compte de chaque place (pour verser les gains).
  final List<String?> uids;

  /// Jeton de connexion de chaque place (pour les paris).
  final List<String> tokens;

  @override
  State<_LocalGame> createState() => _LocalGameState();
}

class _LocalGameState extends State<_LocalGame> {
  final Random _random = Random();
  late final List<int> scores = List.filled(widget.names.length, 0);
  final DateTime created = DateTime.now();
  int cur = 0;
  int d1 = 1;
  int d2 = 1;
  int rollN = 0;
  bool rolled = false;
  bool over = false;
  List<int> winners = [];
  List<int> spin1 = [2, 3, 1];
  List<int> spin2 = [3, 2, 2];

  bool _settled = false;
  int _tries = 0;
  int jackpot = 0;

  /// Résultat des paris, renvoyé par le serveur à la fin de la partie.
  List<Map<String, dynamic>> betResults = [];

  String _two(int n) => n < 10 ? '0$n' : '$n';

  String get _createdLabel =>
      tr('Partie créée le ', 'Game created on ') +
      '${_two(created.day)}/${_two(created.month)}/${created.year} '
          '${_two(created.hour)}:${_two(created.minute)}';

  void _roll() {
    setState(() {
      d1 = _random.nextInt(6) + 1;
      d2 = _random.nextInt(6) + 1;
      spin1 = _randomSpin(_random);
      spin2 = _randomSpin(_random);
      scores[cur] += d1 + d2;
      rolled = true;
      rollN++;
      // Le dernier joueur vient de lancer : la partie est finie.
      if (cur == widget.names.length - 1) {
        over = true;
        winners = _winnersOf(scores);
      }
    });
    if (over) _settle();
  }

  void _next() {
    if (over) return;
    setState(() {
      cur++;
      rolled = false;
    });
  }

  /// 30 s écoulées : le système joue à la place du joueur (lancer, puis
  /// joueur suivant).
  Future<void> _autoPlay() async {
    if (over) return;
    final turn = cur;
    if (!rolled) {
      _roll();
      if (over) return;
      await Future.delayed(const Duration(milliseconds: 2800));
      if (!mounted || over || cur != turn) return;
    }
    _next();
  }

  /// Fin de partie avec mise : le serveur verse la cagnotte aux gagnants
  /// et règle les paris.
  Future<void> _settle() async {
    final id = widget.localId;
    if (id == null || _settled || !firebaseReady) return;
    _settled = true;
    try {
      final ws = <String>[
        for (final s in winners)
          if (s < widget.uids.length && widget.uids[s] != null)
            widget.uids[s]!,
      ];
      final res = await Wallet.settleLocalFull(
        id,
        ws,
        List<int>.from(scores),
      );
      final jp = (res['jackpot'] as num?)?.toInt() ?? 0;
      final bets = ((res['bets'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          if (jp > 0) jackpot = jp;
          betResults = bets;
        });
      }
    } catch (_) {
      _settled = false;
      if (mounted && ++_tries < 4) {
        Future.delayed(const Duration(seconds: 5), _settle);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Avec une mise, on ne quitte pas avant la fin (sinon la mise serait perdue).
    return PopScope(
      canPop: widget.localId == null || over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Termine la partie pour récupérer les gains.'),
            ),
          );
        }
      },
      child: _Shell(
        title: 'Deux dés',
        child: Column(
          children: [
            if (widget.stake > 0 && widget.localId != null)
              LocalSideBetsBar(
                key: const ValueKey('local_bets'),
                localId: widget.localId!,
                names: widget.names,
                uids: widget.uids,
                tokens: widget.tokens,
                initialPlaced: widget.initialBets,
                cur: cur,
                rolled: rolled,
                over: over,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _createdLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: _DiceTable(
                names: widget.names,
                scores: scores,
                cur: cur,
                d1: d1,
                d2: d2,
                spin1: spin1,
                spin2: spin2,
                rolled: rolled,
                rollN: rollN,
                canAct: true,
                onRoll: _roll,
                onNext: _next,
                onTimeout: _autoPlay,
                over: over,
                winners: winners,
                stake: widget.stake,
                jackpot: jackpot,
                local: true,
                endExtra: over
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (betResults.isNotEmpty) ...[
                            LocalBetsSummary(bets: betResults),
                            const SizedBox(height: 12),
                          ],
                          LocalRematchPanel(
                            names: widget.names,
                            ids: [
                              for (int i = 0; i < widget.names.length; i++) i,
                            ],
                            stake: widget.stake,
                            onRelaunch: (accepted) =>
                                Navigator.of(context).pop(accepted),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// En ligne : salon (créer / rejoindre) puis salle de jeu
// ----------------------------------------------------------------------

class _OnlineHub extends StatefulWidget {
  const _OnlineHub();

  @override
  State<_OnlineHub> createState() => _OnlineHubState();
}

class _OnlineHubState extends State<_OnlineHub> {
  int maxPlayers = 2;
  int stake = Wallet.minStake;
  bool privateRoom = false;
  bool busy = false;
  String? error;
  final TextEditingController codeCtrl = TextEditingController();

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _rooms.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> liveStream =
      _rooms.where('status', isEqualTo: 'playing').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _rooms.where('uids', arrayContains: uid).snapshots();

  bool showOpen = false; // liste « Parties ouvertes » dépliée
  bool showLive = false; // liste « Parties en cours » dépliée

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _open(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _OnlineRoom(roomId: id)),
    );
  }

  Future<int> _myBalance() async {
    final s =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final b = s.data()?['balance'];
    return b is num ? b.toInt() : 0;
  }

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (await _myBalance() < stake) {
        if (mounted) {
          setState(() => error = tr(
              'Solde insuffisant : il te faut au moins ${Wallet.format(stake)}.',
              'Insufficient balance: you need at least ${Wallet.format(stake)}.'));
        }
        return;
      }
      final ref = _rooms.doc();
      await ref.set({
        'hostUid': user.uid,
        'hostName': _userName(user),
        'maxPlayers': maxPlayers,
        'private': privateRoom,
        'stake': stake,
        'paid': <String>[],
        'pot': 0,
        'code': _newCode(),
        'status': 'waiting',
        'players': [
          {'uid': user.uid, 'name': _userName(user)},
        ],
        'uids': [user.uid],
        'scores': List<int>.filled(maxPlayers, 0),
        'cur': 0,
        'rolled': false,
        'over': false,
        'winners': <int>[],
        'd1': 1,
        'd2': 1,
        'spin1': [2, 3, 1],
        'spin2': [3, 2, 2],
        'rollN': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      try {
        await Wallet.payStake(ref.id);
      } catch (e) {
        try {
          await Wallet.leaveGame(ref.id);
        } catch (_) {}
        if (mounted) setState(() => error = Wallet.errorText(e));
        return;
      }
      if (mounted) _open(ref.id);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de créer la partie. Vérifie les '
            'règles Firestore (collection « deuxdes »).');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _join(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = _rooms.doc(id);
      final pre = await ref.get();
      final need = (pre.data()?['stake'] as num?)?.toInt() ?? 0;
      if (pre.exists && need > 0 && await _myBalance() < need) {
        if (mounted) {
          setState(() => error = tr(
              'Solde insuffisant : mise de ${Wallet.format(need)}.',
              'Insufficient balance: stake of ${Wallet.format(need)}.'));
        }
        return;
      }
      final result =
          await FirebaseFirestore.instance.runTransaction<String?>((tx) async {
        final snap = await tx.get(ref);
        final d = snap.data();
        if (d == null) return "Cette partie n'existe plus.";
        final players = _playersOf(d);
        if (players.any((p) => p['uid'] == user.uid)) return null;
        final max = (d['maxPlayers'] as num).toInt();
        if (d['status'] != 'waiting' || players.length >= max) {
          return 'Cette partie est déjà complète.';
        }
        players.add({'uid': user.uid, 'name': _userName(user)});
        // La partie démarre quand la salle est pleine ET que tout le monde
        // a payé sa mise (le serveur lance la partie, voir payStake).
        tx.update(ref, {
          'players': players,
          'uids': FieldValue.arrayUnion([user.uid]),
        });
        return null;
      });
      if (!mounted) return;
      if (result != null) {
        setState(() => error = result);
        return;
      }
      try {
        await Wallet.payStake(id);
        if (mounted) _open(id);
      } catch (e) {
        try {
          await Wallet.leaveGame(id);
        } catch (_) {}
        if (mounted) setState(() => error = Wallet.errorText(e));
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Impossible de rejoindre la partie.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _joinByCode() async {
    final code = codeCtrl.text.trim().toUpperCase();
    if (busy) return;
    if (code.length != 6) {
      setState(() => error = 'Entre le code à 6 caractères.');
      return;
    }
    String? id;
    try {
      final q = await _rooms.where('code', isEqualTo: code).limit(1).get();
      if (q.docs.isEmpty) {
        setState(() => error = 'Aucune partie avec ce code.');
      } else {
        id = q.docs.first.id;
      }
    } catch (_) {
      setState(() => error = 'Impossible de chercher la partie.');
    }
    if (id != null && mounted) await _join(id);
  }

  int _createdMs(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final t = doc.data()['createdAt'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  Widget _mine() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: mineStream,
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? [])
            .where((d) => d.data()['status'] != 'finished')
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Mes parties'),
            for (final doc in docs)
              Builder(builder: (context) {
                final d = doc.data();
                final waiting = d['status'] == 'waiting';
                final n = _playersOf(d).length;
                final max = (d['maxPlayers'] as num).toInt();
                final when = _createdText(d['createdAt']);
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  waiting
                      ? tr('En attente ($n/$max joueurs)${_stakeText(d)}$when',
                          'Waiting ($n/$max players)${_stakeText(d)}$when')
                      : tr('En cours${_stakeText(d)}$when',
                          'In progress${_stakeText(d)}$when'),
                  waiting ? 'Ouvrir' : 'Reprendre',
                  busy ? null : () => _open(doc.id),
                );
              }),
          ],
        );
      },
    );
  }

  /// Bouton qui déplie / replie une liste de parties.
  Widget _listButton(String label, bool open, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.16),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white30),
            ),
          ),
          onPressed: onTap,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  void _watch(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OnlineRoom(roomId: id, spectate: true),
      ),
    );
  }

  Widget _liveList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: liveStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint('Impossible de charger les parties en cours.');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs
            .where((d) => !((d.data()['uids'] as List?) ?? []).contains(uid))
            .where((d) => d.data()['private'] != true)
            .where((d) => d.data()['over'] != true)
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) {
          return _hint('Aucune partie en cours à regarder pour le moment.');
        }
        return Column(
          children: [
            for (final doc in docs)
              Builder(builder: (context) {
                final d = doc.data();
                final names = _playersOf(d).map((p) => '${p['name']}');
                final when = _createdText(d['createdAt']);
                return _tile(
                  names.join(' vs '),
                  tr(
                    '${(d['maxPlayers'] as num).toInt()} joueurs${_stakeText(d)}$when',
                    '${(d['maxPlayers'] as num).toInt()} players${_stakeText(d)}$when',
                  ),
                  'Regarder',
                  () => _watch(doc.id),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _openList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: openStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint('Impossible de charger les parties.');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs
            .where((d) => !((d.data()['uids'] as List?) ?? []).contains(uid))
            .where((d) => d.data()['private'] != true)
            .toList()
          ..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
        if (docs.isEmpty) {
          return _hint('Aucune partie ouverte pour le moment. Crée la tienne !');
        }
        return Column(
          children: [
            for (final doc in docs)
              Builder(builder: (context) {
                final d = doc.data();
                final n = _playersOf(d).length;
                final max = (d['maxPlayers'] as num).toInt();
                final when = _createdText(d['createdAt']);
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  tr('$n/$max joueurs${_stakeText(d)}$when',
                      '$n/$max players${_stakeText(d)}$when'),
                  'Rejoindre',
                  busy ? null : () => _join(doc.id),
                );
              }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Deux dés · en ligne',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const JackpotBanner(),
          _label('Créer une partie'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in _counts)
                ChoiceChip(
                  label: Text(tr('$n joueurs', '$n players')),
                  selected: maxPlayers == n,
                  onSelected: (_) => setState(() => maxPlayers = n),
                ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<int>(
            stream: Wallet.watch(uid),
            builder: (context, s) => Text(
              tr(
                'Mise de chaque joueur · ton solde : ${Wallet.format(s.data ?? 0)}',
                "Each player's stake · your balance: ${Wallet.format(s.data ?? 0)}",
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _stakeBox(stake, maxPlayers, (v) => setState(() => stake = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xFFFFC21A),
            title: const Text(
              'Partie privée',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Invisible dans la liste : on la rejoint avec un code',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: privateRoom,
            onChanged: (v) => setState(() => privateRoom = v),
          ),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: busy ? null : _create,
              child: Text(busy ? 'Patiente...' : 'Créer la partie'),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _label('Rejoindre avec un code'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'CODE',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22B14C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : _joinByCode,
                  child: const Text('Rejoindre'),
                ),
              ),
            ],
          ),
          _mine(),
          _listButton(
            '🎲 Parties ouvertes',
            showOpen,
            () => setState(() => showOpen = !showOpen),
          ),
          if (showOpen) _openList(),
          _listButton(
            '👀 Parties en cours',
            showLive,
            () => setState(() => showLive = !showLive),
          ),
          if (showLive) _liveList(),
        ],
      ),
    );
  }
}

/// Salle d'une partie en ligne : attente (mises payées), puis jeu.
/// Administrateur : revoit une partie de Deux dés en ligne (lecture seule).
class DeuxDesSpectator extends StatelessWidget {
  const DeuxDesSpectator({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) =>
      _OnlineRoom(roomId: roomId, spectate: true);
}

class _OnlineRoom extends StatefulWidget {
  const _OnlineRoom({required this.roomId, this.spectate = false});

  final String roomId;
  final bool spectate;

  @override
  State<_OnlineRoom> createState() => _OnlineRoomState();
}

class _OnlineRoomState extends State<_OnlineRoom> {
  bool _settled = false;
  int _tries = 0;

  /// Emojis envoyés aux joueurs (créé quand on est assis à la table).
  EmojiReactions? _reactions;

  @override
  void dispose() {
    _reactions?.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _ref => _rooms.doc(widget.roomId);

  Widget _info(String text, {bool loading = false}) {
    return _Shell(
      title: 'Deux dés',
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Quitter la salle d'attente : la mise est remboursée par le serveur.
  Future<void> _leave() async {
    Navigator.of(context).pop();
    try {
      await Wallet.leaveGame(widget.roomId);
    } catch (_) {}
  }

  /// Fin de partie avec mise : le serveur verse la cagnotte aux gagnants.
  Future<void> _settle() async {
    if (_settled) return;
    _settled = true;
    try {
      await Wallet.settleOnline(widget.roomId);
    } catch (_) {
      _settled = false;
      if (mounted && ++_tries < 4) {
        Future.delayed(const Duration(seconds: 5), _settle);
      }
    }
  }

  Future<void> _roll(int seat) async {
    final r = Random();
    final a = r.nextInt(6) + 1;
    final b = r.nextInt(6) + 1;
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null) return;
        if ((d['cur'] as num).toInt() != seat || d['rolled'] == true) return;
        if (d['over'] == true) return;
        final scores = _ints(d['scores'], const []);
        if (seat >= scores.length) return;
        scores[seat] += a + b;
        final isLast = seat == _playersOf(d).length - 1;
        tx.update(_ref, {
          'd1': a,
          'd2': b,
          'spin1': _randomSpin(r),
          'spin2': _randomSpin(r),
          'scores': scores,
          'rolled': true,
          'rollN': FieldValue.increment(1),
          // Le dernier joueur vient de lancer : la partie est finie.
          if (isLast) 'over': true,
          if (isLast) 'winners': _winnersOf(scores),
          if (isLast) 'status': 'finished',
        });
      });
    } catch (_) {}
  }

  Future<void> _next(int seat) async {
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null) return;
        final cur = (d['cur'] as num).toInt();
        if (cur != seat || d['rolled'] != true || d['over'] == true) return;
        tx.update(_ref, {'cur': cur + 1, 'rolled': false});
      });
    } catch (_) {}
  }

  /// 30 s écoulées : lance les dés (si besoin) puis passe au joueur suivant,
  /// à la place du joueur [seat] (n'importe quel appareil peut le faire).
  Future<void> _autoTurn(int seat, bool rolled) async {
    if (!rolled) {
      await _roll(seat);
      await Future.delayed(const Duration(milliseconds: 2800));
    }
    await _next(seat);
  }

  Widget _waiting(Map<String, dynamic> d, List<Map<String, dynamic>> players,
      String uid) {
    final max = (d['maxPlayers'] as num).toInt();
    final isHost = d['hostUid'] == uid;
    final stake = (d['stake'] as num?)?.toInt() ?? 0;
    // Cagnotte finale : mise x nombre de joueurs de la salle.
    final pot = stake * max;
    final paid = ((d['paid'] as List?) ?? const []).map((e) => '$e').toList();
    final createdLabel =
        _createdText(d['createdAt']).replaceFirst(' • ', '');

    return _Shell(
      title: "Salle d'attente",
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr('${players.length}/$max joueurs',
                '${players.length}/$max players'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (createdLabel.isNotEmpty)
            Text(
              tr('Créée le $createdLabel', 'Created on $createdLabel'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 4),
          const Text(
            "Le créateur lance la partie quand il veut, dès 2 joueurs (même "
            "si la salle n'est pas pleine) et quand tout le monde a payé sa mise.",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            stake > 0
                ? tr(
                    'Mise : ${Wallet.format(stake)} • '
                    'Cagnotte : ${Wallet.format(pot)} '
                    '(gain ${Wallet.format(Wallet.prize(pot))})',
                    'Stake: ${Wallet.format(stake)} • '
                    'Pot: ${Wallet.format(pot)} '
                    '(prize ${Wallet.format(Wallet.prize(pot))})',
                  )
                : 'Partie gratuite',
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!paid.contains(uid))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22B14C),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  try {
                    await Wallet.payStake(widget.roomId);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(Wallet.errorText(e))),
                      );
                    }
                  }
                },
                child: Text(
                  stake > 0
                      ? tr('Payer ma mise (${Wallet.format(stake)})',
                          'Pay my stake (${Wallet.format(stake)})')
                      : 'Valider ma participation',
                ),
              ),
            ),
          WaitingBell(collection: 'deuxdes', gameId: widget.roomId),
          HostStartButton(
            gameId: widget.roomId,
            isHost: isHost,
            playerCount: players.length,
            paidCount: paid.length,
          ),
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black26,
              border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${d['code']}',
                    style: const TextStyle(
                      color: Color(0xFFFFC21A),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${d['code']}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copié')),
                    );
                  },
                ),
              ],
            ),
          ),
          for (int i = 0; i < max; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.12),
                border: Border.all(color: _palette[i % _palette.length], width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: _palette[i % _palette.length]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i < players.length
                          ? '${players[i]['name']}'
                              '${paid.contains(players[i]['uid']) ? ' ✅' : ''}'
                          : "En attente d'un joueur...",
                      style: TextStyle(
                        color:
                            i < players.length ? Colors.white : Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: _leave,
              child: Text(isHost ? 'Annuler la partie' : 'Quitter la partie'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _info('Tu dois être connecté.');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _info('Erreur de connexion à la partie.');
        if (!snap.hasData) return _info('', loading: true);

        final d = snap.data!.data();
        if (d == null) return _info("Cette partie n'existe plus.");

        final players = _playersOf(d);
        final seat = players.indexWhere((p) => p['uid'] == user.uid);
        if (seat < 0 && !widget.spectate) {
          return _info('Tu ne fais pas partie de cette partie.');
        }
        if (seat < 0 && d['status'] == 'waiting') {
          return _info("Cette partie n'a pas encore commencé.");
        }
        if (d['status'] == 'waiting') {
          return _waiting(d, players, user.uid);
        }

        if (seat >= 0 && _reactions == null) {
          _reactions = EmojiReactions(
            collection: 'deuxdes',
            gameId: widget.roomId,
            myName: '${players[seat]['name']}',
          );
        }
        final over = d['over'] == true;
        if (over && seat >= 0) _settle();
        final cur = (d['cur'] as num?)?.toInt() ?? 0;
        final stake = (d['stake'] as num?)?.toInt() ?? 0;

        return PopScope(
          canPop: stake == 0 || over || seat < 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Termine la partie pour récupérer les gains.'),
                ),
              );
            }
          },
          child: _Shell(
            title: 'Deux dés · en ligne',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Salon d'attente : toutes les informations de la partie
                RoomInfoButton(
                  collection: 'deuxdes',
                  gameId: widget.roomId,
                ),
                if (seat >= 0) ...[
                  const SizedBox(width: 6),
                  GameChat(
                    collection: 'deuxdes',
                    gameId: widget.roomId,
                    myName: '${players[seat]['name']}',
                  ),
                ],
              ],
            ),
            child: Column(
              children: [
                if (stake > 0 && seat >= 0)
                  SideBetsBar(roomId: widget.roomId, uid: user.uid, room: d),
                Expanded(
                  child: _DiceTable(
                    names: [for (final p in players) '${p['name']}'],
                    uids: [for (final p in players) '${p['uid']}'],
                    reactions: seat >= 0 ? _reactions : null,
                    scores: _ints(d['scores'], const []),
                    cur: cur,
                    d1: (d['d1'] as num?)?.toInt() ?? 1,
                    d2: (d['d2'] as num?)?.toInt() ?? 1,
                    spin1: _ints(d['spin1'], const [2, 3, 1]),
                    spin2: _ints(d['spin2'], const [3, 2, 2]),
                    rolled: d['rolled'] == true,
                    rollN: (d['rollN'] as num?)?.toInt() ?? 0,
                    canAct: seat >= 0 && cur == seat && !over,
                    onRoll: () => _roll(seat),
                    onNext: () => _next(seat),
                    onTimeout: () => _autoTurn(cur, d['rolled'] == true),
                    onForce: seat < 0
                        ? null
                        : () => _autoTurn(cur, d['rolled'] == true),
                    over: over,
                    winners: _ints(d['winners'], const []),
                    stake: stake,
                    jackpot: (d['jackpot'] as num?)?.toInt() ?? 0,
                    endExtra: (over && seat >= 0)
                        ? RematchPanel(
                            collection: 'deuxdes',
                            gameId: widget.roomId,
                            data: d,
                            createRoom: createDeuxDesRematchRoom,
                            openRoom: (id) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => _OnlineRoom(roomId: id),
                                ),
                              );
                            },
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
