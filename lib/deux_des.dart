import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'dice3d.dart';
import 'lang.dart';
import 'main.dart';
import 'online_screen.dart';

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
];
const List<String> _colorNames = ['Rouge', 'Vert', 'Bleu', 'Jaune'];

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

/// Écran avec fond bleu, bouton retour et titre.
class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child});

  final String title;
  final Widget child;

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
                      onPressed: () => Navigator.of(context).pop(),
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
// Plateau commun (présentiel et en ligne) : dés 3D, scores, boutons
// ----------------------------------------------------------------------

class _DiceTable extends StatefulWidget {
  const _DiceTable({
    required this.names,
    required this.scores,
    required this.cur,
    required this.round,
    required this.d1,
    required this.d2,
    required this.spin1,
    required this.spin2,
    required this.rolled,
    required this.rollN,
    required this.canAct,
    required this.onRoll,
    required this.onNext,
  });

  final List<String> names;
  final List<int> scores;
  final int cur;
  final int round;
  final int d1;
  final int d2;
  final List<int> spin1;
  final List<int> spin2;

  /// Le joueur courant a déjà lancé ses dés ce tour-ci.
  final bool rolled;

  /// Compteur de lancers : chaque changement déclenche l'animation
  /// (donc aussi chez les adversaires en ligne).
  final int rollN;

  /// Cet appareil peut jouer le tour en cours.
  final bool canAct;
  final VoidCallback onRoll;
  final VoidCallback onNext;

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

  @override
  void didUpdateWidget(covariant _DiceTable old) {
    super.didUpdateWidget(old);
    if (widget.rollN != old.rollN) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _name(int i) => i < widget.names.length ? widget.names[i] : '?';

  Widget _die(int value, List<int> spin) {
    final color = _palette[widget.cur % 4];
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

  @override
  Widget build(BuildContext context) {
    final color = _palette[widget.cur % 4];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            tr('Tour ${widget.round}', 'Round ${widget.round}'),
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const SizedBox(height: 28),
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
              if (!widget.canAct) {
                return Text(
                  tr('En attente de ${_name(widget.cur)}...',
                      'Waiting for ${_name(widget.cur)}...'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                      onPressed: (!widget.rolled && !busy) ? widget.onRoll : null,
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
                      onPressed: (widget.rolled && !busy) ? widget.onNext : null,
                      child: const Text('Joueur suivant'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < widget.names.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(i == widget.cur ? 0.2 : 0.1),
                border: Border.all(
                  color: _palette[i % 4],
                  width: i == widget.cur ? 2.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 9, backgroundColor: _palette[i % 4]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.names[i],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${i < widget.scores.length ? widget.scores[i] : 0}',
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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

  /// Nom et uid des joueurs connectés, par place (0 = joueur principal).
  final Map<int, String> names = {};
  final Map<int, String> uids = {};
  late final List<TextEditingController> ctrls =
      List.generate(4, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        names[0] = _userName(u);
        uids[0] = u.uid;
      }
    }
  }

  @override
  void dispose() {
    for (final c in ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool get ready =>
      !firebaseReady ||
      List.generate(numPlayers, (i) => i).every(names.containsKey);

  Future<void> _connect(int seat) async {
    final acc = await showPlayerLogin(
      context,
      colorName: _colorNames[seat],
      color: _palette[seat],
    );
    if (acc == null || !mounted) return;
    final already =
        uids.entries.any((e) => e.key != seat && e.value == acc.uid);
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce compte joue déjà dans la partie.')),
      );
      return;
    }
    setState(() {
      names[seat] = acc.name;
      uids[seat] = acc.uid;
    });
  }

  Widget _row(int seat) {
    final name = names[seat];
    Widget field;
    if (!firebaseReady) {
      field = TextField(
        controller: ctrls[seat],
        maxLength: 12,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          hintText: tr('Joueur ${_colorNames[seat]}',
              'Player ${_colorNames[seat]}'),
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
    } else if (name != null) {
      field = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: _palette[seat], width: 1.5),
        ),
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
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
          if (firebaseReady && name != null && seat != 0)
            IconButton(
              tooltip: tr('Changer de compte', 'Switch account'),
              onPressed: () => setState(() {
                names.remove(seat);
                uids.remove(seat);
              }),
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  void _start() {
    final list = <String>[
      for (int i = 0; i < numPlayers; i++)
        firebaseReady
            ? names[i]!
            : (ctrls[i].text.trim().isNotEmpty
                ? ctrls[i].text.trim()
                : tr('Joueur ${_colorNames[i]}', 'Player ${_colorNames[i]}')),
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _LocalGame(names: list)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Deux dés · présentiel',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('Nombre de joueurs'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [2, 3, 4])
                ChoiceChip(
                  label: Text('$n'),
                  selected: numPlayers == n,
                  onSelected: (_) => setState(() => numPlayers = n),
                ),
            ],
          ),
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
              onPressed: ready ? _start : null,
              child: Text(
                ready ? 'Lancer la partie' : 'Tous les joueurs doivent se connecter',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalGame extends StatefulWidget {
  const _LocalGame({required this.names});

  final List<String> names;

  @override
  State<_LocalGame> createState() => _LocalGameState();
}

class _LocalGameState extends State<_LocalGame> {
  final Random _random = Random();
  late final List<int> scores = List.filled(widget.names.length, 0);
  int cur = 0;
  int round = 1;
  int d1 = 1;
  int d2 = 1;
  int rollN = 0;
  bool rolled = false;
  List<int> spin1 = [2, 3, 1];
  List<int> spin2 = [3, 2, 2];

  void _roll() {
    setState(() {
      d1 = _random.nextInt(6) + 1;
      d2 = _random.nextInt(6) + 1;
      spin1 = _randomSpin(_random);
      spin2 = _randomSpin(_random);
      scores[cur] += d1 + d2;
      rolled = true;
      rollN++;
    });
  }

  void _next() {
    setState(() {
      cur = (cur + 1) % widget.names.length;
      if (cur == 0) round++;
      rolled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Deux dés',
      child: _DiceTable(
        names: widget.names,
        scores: scores,
        cur: cur,
        round: round,
        d1: d1,
        d2: d2,
        spin1: spin1,
        spin2: spin2,
        rolled: rolled,
        rollN: rollN,
        canAct: true,
        onRoll: _roll,
        onNext: _next,
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
  bool privateRoom = false;
  bool busy = false;
  String? error;
  final TextEditingController codeCtrl = TextEditingController();

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _rooms.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _rooms.where('uids', arrayContains: uid).snapshots();

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

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = _rooms.doc();
      await ref.set({
        'hostUid': user.uid,
        'hostName': _userName(user),
        'maxPlayers': maxPlayers,
        'private': privateRoom,
        'code': _newCode(),
        'status': 'waiting',
        'players': [
          {'uid': user.uid, 'name': _userName(user)},
        ],
        'uids': [user.uid],
        'scores': List<int>.filled(maxPlayers, 0),
        'cur': 0,
        'round': 1,
        'rolled': false,
        'd1': 1,
        'd2': 1,
        'spin1': [2, 3, 1],
        'spin2': [3, 2, 2],
        'rollN': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
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
        tx.update(ref, {
          'players': players,
          'uids': FieldValue.arrayUnion([user.uid]),
          // La salle est pleine : la partie démarre toute seule.
          if (players.length >= max) 'status': 'playing',
        });
        return null;
      });
      if (!mounted) return;
      if (result != null) {
        setState(() => error = result);
      } else {
        _open(id);
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
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  waiting
                      ? tr('En attente ($n/$max joueurs)',
                          'Waiting ($n/$max players)')
                      : tr('En cours', 'In progress'),
                  waiting ? 'Ouvrir' : 'Reprendre',
                  busy ? null : () => _open(doc.id),
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
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  tr('$n/$max joueurs', '$n/$max players'),
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
          _label('Créer une partie'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [2, 3, 4])
                ChoiceChip(
                  label: Text(tr('$n joueurs', '$n players')),
                  selected: maxPlayers == n,
                  onSelected: (_) => setState(() => maxPlayers = n),
                ),
            ],
          ),
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
          _label('Parties ouvertes'),
          _openList(),
        ],
      ),
    );
  }
}

/// Salle d'une partie en ligne : attente des joueurs, puis jeu.
class _OnlineRoom extends StatelessWidget {
  const _OnlineRoom({required this.roomId});

  final String roomId;

  DocumentReference<Map<String, dynamic>> get _ref => _rooms.doc(roomId);

  Widget _info(BuildContext context, String text, {bool loading = false}) {
    return _Shell(
      title: 'Deux dés',
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Quitter la salle d'attente (l'hôte annule la partie).
  Future<void> _leave(BuildContext context, Map<String, dynamic> d,
      String uid) async {
    Navigator.of(context).pop();
    try {
      if (d['hostUid'] == uid) {
        await _ref.delete();
      } else {
        await FirebaseFirestore.instance.runTransaction<void>((tx) async {
          final snap = await tx.get(_ref);
          final data = snap.data();
          if (data == null || data['status'] != 'waiting') return;
          final players = _playersOf(data)..removeWhere((p) => p['uid'] == uid);
          tx.update(_ref, {
            'players': players,
            'uids': FieldValue.arrayRemove([uid]),
          });
        });
      }
    } catch (_) {}
  }

  Future<void> _start() async {
    try {
      await _ref.update({'status': 'playing'});
    } catch (_) {}
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
        final scores = _ints(d['scores'], const []);
        if (seat >= scores.length) return;
        scores[seat] += a + b;
        tx.update(_ref, {
          'd1': a,
          'd2': b,
          'spin1': _randomSpin(r),
          'spin2': _randomSpin(r),
          'scores': scores,
          'rolled': true,
          'rollN': FieldValue.increment(1),
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
        if (cur != seat || d['rolled'] != true) return;
        final n = _playersOf(d).length;
        final next = (cur + 1) % n;
        tx.update(_ref, {
          'cur': next,
          'rolled': false,
          if (next == 0) 'round': FieldValue.increment(1),
        });
      });
    } catch (_) {}
  }

  Widget _waiting(BuildContext context, Map<String, dynamic> d,
      List<Map<String, dynamic>> players, String uid) {
    final max = (d['maxPlayers'] as num).toInt();
    final isHost = d['hostUid'] == uid;
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
          const SizedBox(height: 4),
          const Text(
            'La partie démarre dès que la salle est pleine.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
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
                border: Border.all(color: _palette[i % 4], width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: _palette[i % 4]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i < players.length
                          ? '${players[i]['name']}'
                          : "En attente d'un joueur...",
                      style: TextStyle(
                        color: i < players.length
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isHost && players.length >= 2 && players.length < max)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22B14C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _start,
                  child: Text(tr('Commencer à ${players.length}',
                      'Start with ${players.length}')),
                ),
              ),
            ),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: () => _leave(context, d, uid),
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
    if (user == null) return _info(context, 'Tu dois être connecté.');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _info(context, 'Erreur de connexion à la partie.');
        }
        if (!snap.hasData) return _info(context, '', loading: true);

        final d = snap.data!.data();
        if (d == null) return _info(context, "Cette partie n'existe plus.");

        final players = _playersOf(d);
        final seat = players.indexWhere((p) => p['uid'] == user.uid);
        if (seat < 0) {
          return _info(context, 'Tu ne fais pas partie de cette partie.');
        }
        if (d['status'] == 'waiting') {
          return _waiting(context, d, players, user.uid);
        }

        final cur = (d['cur'] as num?)?.toInt() ?? 0;
        return _Shell(
          title: 'Deux dés · en ligne',
          child: _DiceTable(
            names: [for (final p in players) '${p['name']}'],
            scores: _ints(d['scores'], const []),
            cur: cur,
            round: (d['round'] as num?)?.toInt() ?? 1,
            d1: (d['d1'] as num?)?.toInt() ?? 1,
            d2: (d['d2'] as num?)?.toInt() ?? 1,
            spin1: _ints(d['spin1'], const [2, 3, 1]),
            spin2: _ints(d['spin2'], const [3, 2, 2]),
            rolled: d['rolled'] == true,
            rollN: (d['rollN'] as num?)?.toInt() ?? 0,
            canAct: cur == seat,
            onRoll: () => _roll(seat),
            onNext: () => _next(seat),
          ),
        );
      },
    );
  }
}
