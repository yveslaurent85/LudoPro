import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'damier.dart';
import 'deux_des.dart';
import 'lang.dart';
import 'online.dart';
import 'replay_core.dart';
import 'songo.dart';

// ======================================================================
// Revoir une partie en ligne du début à la fin (joueur : ses parties ;
// administrateur : toutes les parties et celles de chaque compte).
// ======================================================================

const Color _rpBg1 = Color(0xFF14267A);
const Color _rpBg2 = Color(0xFF0B1550);
const Color _rpGold = Color(0xFFFFE082);

BoxDecoration _rpDeco() => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_rpBg1, _rpBg2],
      ),
    );

String _two(int n) => n < 10 ? '0$n' : '$n';

String _rpDate(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String rpKindName(String kind) {
  switch (kind) {
    case 'ludo':
      return 'Ludo';
    case 'deuxdes':
      return tr('Deux dés', 'Two dice');
    case 'songo':
      return 'Songô';
    case 'damier':
      return tr('Damier', 'Draughts');
    case 'tiah':
      return 'Tiah';
    case 'boubayah':
      return 'Boubayah';
  }
  return kind;
}

String _rpKindIcon(String kind) {
  switch (kind) {
    case 'ludo':
      return '🎲';
    case 'deuxdes':
      return '🎯';
    case 'songo':
      return '🌰';
    case 'damier':
      return '♟️';
  }
  return '🃏';
}

// ----------------------------------------------------------------------
// Construction des « images » (états successifs) d'une partie
// ----------------------------------------------------------------------

List<int> _ints(dynamic l) =>
    l is List ? l.map((e) => (e as num).toInt()).toList() : <int>[];

List<Map<String, dynamic>> _damierFrames(Map<String, dynamic> d) {
  final mv = ((d['mv'] as List?) ?? const []).map((e) => '$e').toList();
  if (mv.isEmpty) return const [];
  final g = DamierGame(
    hSeat: (d['hSeat'] as num?)?.toInt() ?? -1,
    hN: (d['hN'] as num?)?.toInt() ?? 0,
  );
  Map<String, dynamic> frame() => {
        ...d,
        ...g.toDoc(),
        'status': g.over ? 'finished' : 'playing',
        'clockMs': null,
        'forfeit': -1,
        'timeout': false,
      };
  final out = <Map<String, dynamic>>[frame()];
  var complete = true;
  for (final s in mv) {
    final p = s.split('>').map((e) => int.tryParse(e) ?? -1).toList();
    DMove? m;
    for (final lm in g.legal) {
      if (lm.from != p.first || lm.path.length != p.length - 1) continue;
      var ok = true;
      for (int i = 0; i < lm.path.length; i++) {
        if (lm.path[i] != p[i + 1]) ok = false;
      }
      if (ok) {
        m = lm;
        break;
      }
    }
    if (m == null) {
      complete = false;
      break;
    }
    g.play(m);
    out.add(frame());
  }
  // Dernière image : le vrai document (abandon, temps écoulé, résultat...).
  if (complete) {
    out[out.length - 1] = {...d};
  } else {
    out.add({...d});
  }
  return out;
}

List<Map<String, dynamic>> _songoFrames(Map<String, dynamic> d) {
  final mv = _ints(d['mv']);
  if (mv.isEmpty) return const [];
  final g = SongoGame();
  Map<String, dynamic> frame() => {
        ...d,
        ...g.toDoc(),
        'status': g.over ? 'finished' : 'playing',
        'forfeit': -1,
      };
  final out = <Map<String, dynamic>>[frame()];
  var complete = true;
  for (final p in mv) {
    if (!g.legal.contains(p)) {
      complete = false;
      break;
    }
    g.play(p);
    out.add(frame());
  }
  if (complete) {
    out[out.length - 1] = {...d};
  } else {
    out.add({...d});
  }
  return out;
}

List<Map<String, dynamic>> _deuxdesFrames(Map<String, dynamic> d) {
  final mv = ((d['mv'] as List?) ?? const []).map((e) => '$e').toList();
  if (mv.isEmpty) return const [];
  final n = _ints(d['scores']).length;
  final scores = List<int>.filled(n, 0);
  Map<String, dynamic> base(int cur, bool rolled, int rollN, int d1, int d2) => {
        ...d,
        'scores': List<int>.from(scores),
        'cur': cur,
        'rolled': rolled,
        'over': false,
        'status': 'playing',
        'winners': <int>[],
        'd1': d1,
        'd2': d2,
        'spin1': const [2, 3, 1],
        'spin2': const [3, 2, 2],
        'rollN': rollN,
      };
  final out = <Map<String, dynamic>>[base(0, false, 0, 1, 1)];
  for (int k = 0; k < mv.length && k < n; k++) {
    final ab = mv[k].split(',').map((e) => int.tryParse(e) ?? 1).toList();
    final a = ab.isNotEmpty ? ab[0] : 1;
    final b = ab.length > 1 ? ab[1] : 1;
    scores[k] = a + b;
    out.add(base(k, true, k + 1, a, b));
    if (k < n - 1) out.add(base(k + 1, false, k + 1, a, b));
  }
  out[out.length - 1] = {...d};
  return out;
}

List<Map<String, dynamic>> _ludoFrames(Map<String, dynamic> d) {
  final rp = ((d['rp'] as List?) ?? const []).map((e) => '$e').toList();
  final out = <Map<String, dynamic>>[];
  for (final s in rp) {
    try {
      final a = jsonDecode(s) as List;
      final over = (a[11] as num).toInt() == 1;
      out.add({
        ...d,
        'cur': (a[1] as num).toInt(),
        'dice': (a[2] as num).toInt(),
        'hasRolled': (a[3] as num).toInt() == 1,
        'winner': (a[4] as num).toInt(),
        'finishOrder': _ints(a[5]),
        'forfeited': _ints(a[6]),
        'p0': _ints(a[7]),
        'p1': _ints(a[8]),
        'p2': _ints(a[9]),
        'p3': _ints(a[10]),
        'over': over,
        'status': over ? 'finished' : 'playing',
        'roll': null,
        'msg': '',
      });
    } catch (_) {}
  }
  return out;
}

// ----------------------------------------------------------------------
// Écran de revue
// ----------------------------------------------------------------------

/// Revoir une partie : [kind] = ludo | deuxdes | songo | damier | tiah | boubayah.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.kind, required this.id, this.title});

  final String kind;
  final String id;
  final String? title;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  ReplayController? _ctrl;
  Map<String, dynamic>? _cards; // Tiah / Boubayah
  bool _loading = true;
  String? _err;
  bool _noLog = false;
  int _pos = 0;
  bool _playing = false;
  int _speed = 1;
  Timer? _timer;

  bool get _isCards => widget.kind == 'tiah' || widget.kind == 'boubayah';

  int get _count => _isCards
      ? (((_cards?['opened'] as List?)?.length ?? 0) + 2)
      : (_ctrl?.frames.length ?? 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  String get _col {
    switch (widget.kind) {
      case 'ludo':
        return 'games';
      default:
        return widget.kind;
    }
  }

  Future<void> _load() async {
    try {
      if (_isCards) {
        final r = await Wallet.cardsReplay(widget.id);
        if (!mounted) return;
        setState(() {
          _cards = r;
          _loading = false;
        });
        return;
      }
      final snap =
          await FirebaseFirestore.instance.collection(_col).doc(widget.id).get();
      final d = snap.data();
      if (d == null) throw Exception('absent');
      List<Map<String, dynamic>> frames;
      switch (widget.kind) {
        case 'ludo':
          frames = _ludoFrames(d);
          break;
        case 'deuxdes':
          frames = _deuxdesFrames(d);
          break;
        case 'songo':
          frames = _songoFrames(d);
          break;
        default:
          frames = _damierFrames(d);
      }
      if (!mounted) return;
      setState(() {
        if (frames.length >= 2) {
          _ctrl = ReplayController(frames);
        } else {
          _noLog = true;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e is WalletException ? Wallet.errorText(e) : tr('Partie introuvable.', 'Game not found.');
          _loading = false;
        });
      }
    }
  }

  void _go(int i) {
    final n = _count;
    if (n == 0) return;
    final p = i < 0 ? 0 : (i >= n ? n - 1 : i);
    setState(() => _pos = p);
    _ctrl?.seek(p);
    if (p >= n - 1) _stop();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (_pos >= _count - 1) _go(0);
    setState(() => _playing = true);
    _timer = Timer.periodic(Duration(milliseconds: _speed == 1 ? 1300 : 650), (_) {
      if (!mounted) return;
      _go(_pos + 1);
    });
  }

  void _setSpeed() {
    setState(() => _speed = _speed == 1 ? 2 : 1);
    if (_playing) {
      _stop();
      _togglePlay();
    }
  }

  Widget _board() {
    final c = _ctrl!;
    switch (widget.kind) {
      case 'ludo':
        return OnlineGameRoom(
            gameId: widget.id, spectate: true, adminView: true, replay: c);
      case 'deuxdes':
        return DeuxDesSpectator(roomId: widget.id, replay: c);
      case 'songo':
        return SongoSpectator(roomId: widget.id, replay: c);
      default:
        return DamierSpectator(roomId: widget.id, replay: c);
    }
  }

  Widget _controls() {
    final n = _count;
    final label = _isCards
        ? (_pos == 0
            ? tr('Distribution', 'Deal')
            : _pos >= n - 1
                ? tr('Résultat', 'Result')
                : tr('Ouverture $_pos', 'Opening $_pos'))
        : tr('Étape ${_pos + 1} / $n', 'Step ${_pos + 1} / $n');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1550),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _rpGold, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: _setSpeed,
                  child: Text(_speed == 1 ? '1×' : '2×',
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
            if (n > 1)
              Slider(
                min: 0,
                max: (n - 1).toDouble(),
                divisions: n > 1 ? n - 1 : null,
                value: _pos.clamp(0, n - 1).toDouble(),
                onChanged: (v) => _go(v.round()),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: tr('Début', 'Start'),
                  onPressed: () => _go(0),
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 30),
                ),
                IconButton(
                  tooltip: tr('Précédent', 'Previous'),
                  onPressed: () => _go(_pos - 1),
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 36),
                ),
                IconButton(
                  tooltip: _playing ? tr('Pause', 'Pause') : tr('Lecture', 'Play'),
                  onPressed: _togglePlay,
                  icon: Icon(
                    _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: _rpGold,
                    size: 46,
                  ),
                ),
                IconButton(
                  tooltip: tr('Suivant', 'Next'),
                  onPressed: () => _go(_pos + 1),
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 36),
                ),
                IconButton(
                  tooltip: tr('Fin', 'End'),
                  onPressed: () => _go(n - 1),
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {bool showFinal = false}) => Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: _rpDeco(),
          child: SafeArea(
            child: Column(
              children: [
                _rpHeader(context, widget.title ?? tr('Revoir la partie', 'Game replay')),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 15)),
                          if (showFinal) ...[
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => _finalPage()),
                              ),
                              child: Text(tr('Voir le plateau final', 'See the final board')),
                            ),
                          ],
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

  Widget _finalPage() {
    switch (widget.kind) {
      case 'ludo':
        return OnlineGameRoom(gameId: widget.id, spectate: true, adminView: true);
      case 'deuxdes':
        return DeuxDesSpectator(roomId: widget.id);
      case 'songo':
        return SongoSpectator(roomId: widget.id);
      default:
        return DamierSpectator(roomId: widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Container(
          decoration: _rpDeco(),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_err != null) return _message(_err!);
    if (_noLog) {
      return _message(
        tr(
          "Cette partie a été jouée avant l'ajout de l'enregistrement coup par coup : on ne peut voir que son résultat final.",
          'This game was played before move-by-move recording existed: only its final result can be shown.',
        ),
        showFinal: true,
      );
    }
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _isCards
                ? _CardsReplayBody(data: _cards!, step: _pos, title: widget.title)
                : _board(),
          ),
          _controls(),
        ],
      ),
    );
  }
}

Widget _rpHeader(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

// ----------------------------------------------------------------------
// Tiah / Boubayah : déroulé d'une manche
// ----------------------------------------------------------------------

class _CardsReplayBody extends StatelessWidget {
  const _CardsReplayBody({required this.data, required this.step, this.title});

  final Map<String, dynamic> data;
  final int step; // 0 distribution, 1..n ouvertures, n+1 résultat
  final String? title;

  Widget _card(int c, {bool back = false, bool gold = false}) {
    final v = c ~/ 4;
    final suit = c % 4;
    final red = suit == 1 || suit == 2;
    return Container(
      width: 40,
      height: 56,
      margin: const EdgeInsets.only(right: 5, bottom: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: back ? const Color(0xFF3949AB) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: gold ? const Color(0xFFFFC21A) : Colors.black26, width: gold ? 2.5 : 1),
      ),
      child: back
          ? const Text('?', style: TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w900))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(v == 11 ? 'A' : '$v',
                    style: TextStyle(
                        color: red ? const Color(0xFFD32F2F) : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                Text(const ['♠', '♥', '♦', '♣'][suit],
                    style: TextStyle(
                        color: red ? const Color(0xFFD32F2F) : Colors.black87, fontSize: 15)),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = [
      for (final p in (data['players'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)
    ];
    final opened = [for (final e in (data['opened'] as List? ?? const [])) '$e'];
    final seq = [for (final e in (data['seq'] as List? ?? const [])) '$e'];
    final winners = [for (final e in (data['winnerUids'] as List? ?? const [])) '$e'];
    final boub = data['game'] == 'boubayah';
    final shown = step <= 0 ? 0 : (step - 1 > opened.length ? opened.length : step - 1);
    final done = step >= opened.length + 1;
    final order = [
      ...seq.where((u) => players.any((p) => p['uid'] == u)),
      ...players.map((p) => '${p['uid']}').where((u) => !seq.contains(u)),
    ];
    return Container(
      decoration: _rpDeco(),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _rpHeader(
              context,
              '${title ?? (boub ? 'Boubayah' : 'Tiah')} · ${tr('manche', 'round')} ${data['round'] ?? 1}',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                children: [
                  if ((data['stake'] as num?)?.toInt() != null && (data['stake'] as num) > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        tr('Mise : ${data['stake']} FCFA', 'Stake: ${data['stake']} FCFA'),
                        style: const TextStyle(color: _rpGold, fontWeight: FontWeight.w800),
                      ),
                    ),
                  for (final u in order)
                    Builder(builder: (_) {
                      final p = players.firstWhere((x) => x['uid'] == u);
                      final idx = opened.indexOf(u);
                      final isOpen = idx >= 0 && idx < shown;
                      final win = done && winners.contains(u);
                      final cards = _ints(p['cards']);
                      final plain = _ints(p['plain']);
                      final bouba = _ints(p['bouba']);
                      final nb = boub ? plain.length + bouba.length : cards.length;
                      final turn = !done && shown < opened.length && opened[shown] == u && step > 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(win ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: win ? _rpGold : (turn ? Colors.lightBlueAccent : Colors.white24),
                            width: win || turn ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${win ? '🏆 ' : ''}${p['name']}${u == data['dealerUid'] ? ' 🂠' : ''}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                if (isOpen || done)
                                  Text(
                                    p['toucx'] == true
                                        ? 'TOUCX'
                                        : p['fomekou'] == true
                                            ? 'FOMEKOU'
                                            : '${p['total']}',
                                    style: const TextStyle(
                                        color: _rpGold, fontSize: 18, fontWeight: FontWeight.w900),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              children: [
                                if (boub) ...[
                                  for (final c in plain) _card(c, back: !(isOpen || done)),
                                  for (final c in bouba) _card(c, back: !(isOpen || done), gold: true),
                                ] else
                                  for (final c in cards) _card(c, back: !(isOpen || done)),
                                if (nb == 0)
                                  const Text('—', style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  if (done && data['refunded'] == true)
                    Text(tr('Mises remboursées.', 'Stakes refunded.'),
                        style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Liste des parties en ligne d'un joueur (le mien, ou un compte pour l'admin)
// ----------------------------------------------------------------------

class MyGamesScreen extends StatefulWidget {
  const MyGamesScreen({super.key, this.uid, this.name});

  final String? uid;
  final String? name;

  @override
  State<MyGamesScreen> createState() => _MyGamesScreenState();
}

class _MyGamesScreenState extends State<MyGamesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Wallet.playerGames(uid: widget.uid);
      if (!mounted) return;
      setState(() {
        _rows = [for (final e in (r['rows'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = Wallet.errorText(e);
          _loading = false;
        });
      }
    }
  }

  (String, Color) _result(String r) {
    switch (r) {
      case 'won':
        return (tr('Gagnée', 'Won'), const Color(0xFF4CAF50));
      case 'lost':
        return (tr('Perdue', 'Lost'), const Color(0xFFFF6B6B));
      case 'draw':
        return (tr('Égalité', 'Draw'), const Color(0xFFFFC21A));
      case 'refunded':
        return (tr('Remboursée', 'Refunded'), const Color(0xFF90CAF9));
      default:
        return (tr('En cours', 'Live'), const Color(0xFF81D4FA));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.uid == null
        ? tr('Mes parties en ligne', 'My online games')
        : tr('Parties de ${widget.name ?? 'ce joueur'}', "${widget.name ?? 'Player'}'s games");
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _rpDeco(),
        child: SafeArea(
          child: Column(
            children: [
              _rpHeader(context, title),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _err != null
                        ? Center(
                            child: Text(_err!, style: const TextStyle(color: Colors.white)))
                        : _rows.isEmpty
                            ? Center(
                                child: Text(tr('Aucune partie en ligne.', 'No online games.'),
                                    style: const TextStyle(color: Colors.white70)))
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        tr('Touche une partie pour la revoir du début à la fin.',
                                            'Tap a game to watch it from start to finish.'),
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    ),
                                    for (final r in _rows) _tile(r),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final kind = '${r['kind']}';
    final (label, color) = _result('${r['result']}');
    final names = [for (final n in (r['names'] as List? ?? const [])) '$n'];
    final stake = (r['stake'] as num?)?.toInt() ?? 0;
    final hasReplay = r['replay'] == true;
    return GestureDetector(
      onTap: () {
        if (r['result'] == 'live' && !hasReplay) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Partie en cours.', 'Game in progress.'))),
          );
          return;
        }
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ReplayScreen(kind: kind, id: '${r['id']}', title: rpKindName(kind)),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Text(_rpKindIcon(kind), style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rpKindName(kind)}${stake > 0 ? ' · $stake FCFA' : ''}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  Text(names.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(_rpDate((r['t'] as num?)?.toInt() ?? 0),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Icon(hasReplay ? Icons.play_circle_outline : Icons.visibility_outlined,
                    color: Colors.white54, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
