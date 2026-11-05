import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'game_chat.dart';
import 'lang.dart';
import 'main.dart';
import 'online_screen.dart';
import 'stake_field.dart';

// ----------------------------------------------------------------------
// Songô : jeu de semis (mancala) camerounais pour 2 joueurs.
//  • 14 cases (2 rangées de 7), 5 graines par case au départ (70 graines).
//  • Semis dans le sens des aiguilles d'une montre ; la case de départ est
//    toujours sautée (grenier).
//  • Capture : la dernière graine tombe chez l'adversaire et la case compte
//    2, 3 ou 4 graines -> on les prend, puis on remonte en arrière (rafle).
//    La première case du camp adverse (case d'entrée) n'est jamais prise.
//  • Interdit d'affamer : une rafle qui viendrait à vider tout le camp
//    adverse est annulée ; si l'adversaire n'a plus de graines, il faut lui
//    en envoyer.
//  • Victoire : 36 graines capturées ou plus.
// En ligne : collection Firestore « songo » (règles à ajouter).
// ----------------------------------------------------------------------

const int kSongoWin = 36;
const int kSongoMoveCap = 400;
const int kSongoTurnSecs = 45;

const BoxDecoration _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

const List<Color> _seatColor = [Color(0xFFFFC21A), Color(0xFF22B14C)];
const Color _gold = Color(0xFFFFC21A);
const Color _goldSoft = Color(0xFFFFE082);

// ======================================================================
// Règles du jeu
// ======================================================================

class SongoSow {
  SongoSow(this.board, this.captured, this.last, this.cancelled);
  final List<int> board;
  final int captured;
  final int last;
  final bool cancelled;
}

class SongoEngine {
  /// Premier index du camp du joueur [p] (0 : cases 0-6, 1 : cases 7-13).
  static int base(int p) => p * 7;
  static bool owns(int p, int i) => i >= base(p) && i < base(p) + 7;

  static int sideSum(List<int> b, int p) {
    var s = 0;
    for (int i = base(p); i < base(p) + 7; i++) {
      s += b[i];
    }
    return s;
  }

  static int total(List<int> b) => b.fold(0, (a, x) => a + x);

  static List<int> start() => List<int>.filled(14, 5);

  /// Joue la case [pit] du joueur [p] (sans vérifier la légalité).
  static SongoSow sow(List<int> board, int p, int pit) {
    final b = List<int>.from(board);
    var seeds = b[pit];
    b[pit] = 0;
    var i = pit;
    while (seeds > 0) {
      i = (i + 1) % 14;
      if (i == pit) continue; // la case de départ est sautée
      b[i]++;
      seeds--;
    }
    final opp = 1 - p;
    var captured = 0;
    var cancelled = false;
    if (owns(opp, i)) {
      final entry = base(opp); // case d'entrée : jamais capturée
      final taken = <int>[];
      var k = i;
      while (k > entry && b[k] >= 2 && b[k] <= 4) {
        taken.add(k);
        k--;
      }
      if (taken.isNotEmpty) {
        var take = 0;
        for (final x in taken) {
          take += b[x];
        }
        if (sideSum(b, opp) - take == 0) {
          cancelled = true; // interdit d'affamer l'adversaire
        } else {
          for (final x in taken) {
            b[x] = 0;
          }
          captured = take;
        }
      }
    }
    return SongoSow(b, captured, i, cancelled);
  }

  /// Cases jouables par [p]. Si l'adversaire n'a plus de graines, seuls les
  /// coups qui lui en envoient sont permis.
  static List<int> legalMoves(List<int> board, int p) {
    final moves = <int>[
      for (int i = base(p); i < base(p) + 7; i++)
        if (board[i] > 0) i,
    ];
    if (sideSum(board, 1 - p) == 0) {
      return [
        for (final m in moves)
          if (sideSum(sow(board, p, m).board, 1 - p) > 0) m,
      ];
    }
    return moves;
  }
}

/// État d'une partie (identique à ce qui est stocké dans Firestore).
class SongoGame {
  SongoGame({
    List<int>? board,
    List<int>? scores,
    this.cur = 0,
    this.over = false,
    List<int>? winners,
    this.moveN = 0,
    this.lastPit = -1,
    this.lastFrom = -1,
    this.lastCap = 0,
    this.lastCancelled = false,
  })  : board = board ?? SongoEngine.start(),
        scores = scores ?? [0, 0],
        winners = winners ?? [];

  List<int> board;
  List<int> scores;
  int cur;
  bool over;
  List<int> winners;
  int moveN;
  int lastPit;
  int lastFrom;
  int lastCap;
  bool lastCancelled;

  static List<int> _ints(dynamic l, List<int> fb) =>
      l is List ? l.map((e) => (e as num).toInt()).toList() : fb;

  factory SongoGame.fromDoc(Map<String, dynamic> d) {
    final b = _ints(d['board'], SongoEngine.start());
    return SongoGame(
      board: b.length == 14 ? b : SongoEngine.start(),
      scores: _ints(d['scores'], [0, 0]),
      cur: (d['cur'] as num?)?.toInt() ?? 0,
      over: d['over'] == true,
      winners: _ints(d['winners'], []),
      moveN: (d['moveN'] as num?)?.toInt() ?? 0,
      lastPit: (d['lastPit'] as num?)?.toInt() ?? -1,
      lastFrom: (d['lastFrom'] as num?)?.toInt() ?? -1,
      lastCap: (d['lastCap'] as num?)?.toInt() ?? 0,
      lastCancelled: d['lastCancelled'] == true,
    );
  }

  Map<String, dynamic> toDoc() => {
        'board': board,
        'scores': scores,
        'cur': cur,
        'over': over,
        'winners': winners,
        'moveN': moveN,
        'lastPit': lastPit,
        'lastFrom': lastFrom,
        'lastCap': lastCap,
        'lastCancelled': lastCancelled,
      };

  List<int> get legal => over ? const [] : SongoEngine.legalMoves(board, cur);

  /// Joue la case [pit] pour le joueur au trait. Renvoie false si illégal.
  bool play(int pit) {
    if (over || !legal.contains(pit)) return false;
    final r = SongoEngine.sow(board, cur, pit);
    board = r.board;
    scores[cur] += r.captured;
    lastFrom = pit;
    lastPit = r.last;
    lastCap = r.captured;
    lastCancelled = r.cancelled;
    moveN++;
    cur = 1 - cur;
    _checkEnd();
    return true;
  }

  void _collect() {
    scores[0] += SongoEngine.sideSum(board, 0);
    scores[1] += SongoEngine.sideSum(board, 1);
    board = List<int>.filled(14, 0);
  }

  void _checkEnd() {
    if (scores[0] >= kSongoWin || scores[1] >= kSongoWin) {
      _finish();
      return;
    }
    if (SongoEngine.total(board) < 10 ||
        moveN >= kSongoMoveCap ||
        SongoEngine.legalMoves(board, cur).isEmpty) {
      _collect();
      _finish();
    }
  }

  void _finish() {
    over = true;
    winners = scores[0] > scores[1]
        ? [0]
        : scores[1] > scores[0]
            ? [1]
            : [0, 1];
  }
}

// ======================================================================
// Plateau
// ======================================================================

/// Sons du Songô (activables / coupables avec l'icône haut-parleur).
class SongoSound {
  static bool on = true;

  static Future<void> play(String file,
      {double volume = 1.0, double rate = 1.0}) async {
    if (!on) return;
    try {
      final p = AudioPlayer();
      var closed = false;
      void close() {
        if (closed) return;
        closed = true;
        try {
          p.dispose();
        } catch (_) {}
      }

      p.onPlayerComplete.first.then((_) => close(), onError: (_) => close());
      Future<void>.delayed(const Duration(seconds: 6), close);
      try {
        await p.setPlaybackRate(rate);
      } catch (_) {}
      await p.play(AssetSource(file), volume: volume);
    } catch (_) {}
  }

  static void drop(int i) =>
      play('songo_drop.wav', volume: 0.9, rate: 0.9 + 0.07 * (i % 5));
  static void pick() => play('songo_pick.wav', volume: 0.9);
}

/// Dessine les graines d'une case (dans une ellipse).
class _SeedPainter extends CustomPainter {
  _SeedPainter(this.n, this.salt);
  final int n;
  final int salt;

  @override
  void paint(Canvas canvas, Size size) {
    if (n <= 0) return;
    final c = size.center(Offset.zero);
    final rx = size.width * 0.34;
    final ry = size.height * 0.34;
    final r = min(size.width, size.height) * 0.12;
    final show = min(n, 30);
    final light = Paint()..color = const Color(0xFFFFE9A8);
    final dark = Paint()..color = const Color(0xFFC9801F);
    final edge = Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i < show; i++) {
      final a = (i + salt) * 2.399963;
      final k = sqrt((i + 0.5) / show);
      final o = c + Offset(cos(a) * rx * k, sin(a) * ry * k);
      canvas.drawCircle(o, r, i.isEven ? light : dark);
      canvas.drawCircle(o, r, edge);
    }
  }

  @override
  bool shouldRepaint(_SeedPainter old) => old.n != n;
}

/// Plateau en deux rangées horizontales (ta rangée en bas, celle de
/// l'adversaire en haut) qui remplit tout l'écran. Les graines sont semées une à une, avec
/// animation et sons.
class SongoBoardView extends StatefulWidget {
  const SongoBoardView({
    super.key,
    required this.board,
    required this.viewer,
    required this.legal,
    required this.onPit,
    required this.moveN,
    required this.lastFrom,
    required this.onSettled,
    this.over = false,
    this.names = const ['', ''],
  });

  final List<int> board;

  /// Joueur dont la rangée est en bas.
  final int viewer;
  final List<int> legal;
  final ValueChanged<int> onPit;

  /// Numéro du coup et case jouée : l'animation se déclenche à chaque coup.
  final int moveN;
  final int lastFrom;

  /// Appelé quand l'animation du coup [moveN] est terminée.
  final ValueChanged<int> onSettled;
  final bool over;
  final List<String> names;

  @override
  State<SongoBoardView> createState() => _SongoBoardViewState();
}

class _SongoBoardViewState extends State<SongoBoardView> {
  late List<int> _shown;
  late int _doneMove;
  bool _running = false;
  bool _alive = true;

  int _hand = 0;
  bool _flyOn = false;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  int _stepKey = 0;
  int _stepMs = 250;
  int _glow = -1;
  Set<int> _flash = {};
  final Map<int, Offset> _centers = {};
  final Sfx _sfx = Sfx();

  @override
  void initState() {
    super.initState();
    // Valeurs de départ fixées ici (et non « late ») : sinon elles seraient
    // lues trop tard, après l'arrivée du premier coup.
    _shown = List<int>.from(widget.board);
    _doneMove = widget.moveN;
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  @override
  void didUpdateWidget(SongoBoardView old) {
    super.didUpdateWidget(old);
    if (!_running && widget.moveN != _doneMove) _run();
    if (!_running && widget.moveN == _doneMove) {
      // Même coup : le plateau reste celui du serveur.
      if (!_same(_shown, widget.board)) _shown = List<int>.from(widget.board);
    }
  }

  bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    _running = true;
    while (_alive && _doneMove != widget.moveN) {
      final target = List<int>.from(widget.board);
      final mv = widget.moveN;
      final from = widget.lastFrom;
      var animate = mv == _doneMove + 1 && from >= 0 && from < 14 && _shown[from] > 0;
      if (animate) {
        final p = SongoEngine.owns(0, from) ? 0 : 1;
        final sim = SongoEngine.sow(_shown, p, from);
        animate = _same(sim.board, target) || SongoEngine.total(target) == 0;
      }
      if (animate) {
        await _play(from, target);
      } else if (mounted) {
        setState(() => _shown = target);
      }
      if (!_alive) return;
      _doneMove = mv;
      widget.onSettled(mv);
    }
    _running = false;
    if (_alive && widget.over) _sfx.win();
  }

  Future<void> _play(int from, List<int> target) async {
    final seeds = _shown[from];
    final start = _centers[from] ?? Offset.zero;
    SongoSound.pick();
    setState(() {
      _shown[from] = 0;
      _hand = seeds;
      _flyOn = true;
      _from = start;
      _to = start;
      _glow = from;
      _stepKey++;
    });
    await _wait(450);
    var i = from;
    var rem = seeds;
    final ms = (7000 / seeds).clamp(300, 520).toInt();
    var n = 0;
    while (rem > 0 && _alive) {
      i = (i + 1) % 14;
      if (i == from) continue;
      final dest = _centers[i] ?? start;
      setState(() {
        _from = _to;
        _to = dest;
        _stepMs = ms;
        _stepKey++;
      });
      await _wait(ms);
      if (!_alive) return;
      rem--;
      n++;
      setState(() {
        _shown[i]++;
        _hand = rem;
        _glow = i;
        if (rem == 0) _flyOn = false;
      });
      SongoSound.drop(n);
      await _wait(160);
    }
    await _wait(300);
    if (!_alive) return;
    final diff = <int>{
      for (int k = 0; k < 14; k++)
        if (_shown[k] != target[k]) k,
    };
    if (diff.isNotEmpty) {
      setState(() => _flash = diff);
      _sfx.capture();
      await _wait(650);
      if (!_alive) return;
    }
    setState(() {
      _shown = target;
      _flash = {};
      _glow = -1;
      _flyOn = false;
      _hand = 0;
    });
  }

  Widget _pit(int idx, Offset topLeft, double w, double h) {
    final mine = SongoEngine.owns(widget.viewer, idx);
    final owner = mine ? widget.viewer : 1 - widget.viewer;
    final canTap = !_running && widget.legal.contains(idx);
    final flash = _flash.contains(idx);
    final glow = idx == _glow;
    final border = flash
        ? const Color(0xFFFF5252)
        : canTap
            ? _gold
            : glow
                ? Colors.white
                : _seatColor[owner].withOpacity(0.5);
    final m = min(w, h);
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: GestureDetector(
        onTap: canTap ? () => widget.onPit(idx) : null,
        child: AnimatedScale(
          scale: glow && _running ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(m * 0.5),
            gradient: RadialGradient(
              colors: [
                flash
                    ? const Color(0xFF9B2C2C)
                    : canTap
                        ? const Color(0xFF8A5A2B)
                        : const Color(0xFF6B4423),
                const Color(0xFF301A0B),
              ],
            ),
            border: Border.all(
              color: border,
              width: canTap || glow || flash ? 4 : 2,
            ),
            boxShadow: [
              if (canTap)
                BoxShadow(
                  color: _gold.withOpacity(0.5),
                  blurRadius: 14,
                ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SeedPainter(_shown[idx], idx)),
              ),
              Positioned(
                right: m * 0.12,
                bottom: m * 0.04,
                child: Text(
                  '${_shown[idx]}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: max(16.0, min(34.0, m * 0.32)),
                    fontWeight: FontWeight.w900,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 5),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viewer;
    final opp = 1 - v;
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 8.0;
        const nameH = 22.0;
        final W = c.maxWidth;
        final H = c.maxHeight;
        final pw = (W - pad * 8) / 7;
        final ph = (H - nameH * 2 - pad * 3) / 2;
        final topY = nameH + pad;
        final botY = nameH + pad * 2 + ph;
        final children = <Widget>[];
        // Rangée du haut : l'adversaire (de gauche à droite : 0 -> 6).
        // Rangée du bas : toi (de gauche à droite : 6 -> 0).
        for (int k = 0; k < 7; k++) {
          final x = pad + k * (pw + pad);
          final ti = SongoEngine.base(opp) + k;
          final bi = SongoEngine.base(v) + (6 - k);
          _centers[ti] = Offset(x + pw / 2, topY + ph / 2);
          _centers[bi] = Offset(x + pw / 2, botY + ph / 2);
          children.add(_pit(ti, Offset(x, topY), pw, ph));
          children.add(_pit(bi, Offset(x, botY), pw, ph));
        }
        final double chip = (min(pw, ph) * 0.4).clamp(30.0, 46.0).toDouble();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF2A1708),
            border: Border.all(color: const Color(0xFFB8741A), width: 3),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 3,
                child: Text(
                  widget.names[opp],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _seatColor[opp],
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 3,
                child: Text(
                  widget.names[v],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _seatColor[v],
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              ...children,
              if (_flyOn)
                TweenAnimationBuilder<double>(
                  key: ValueKey(_stepKey),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: Duration(milliseconds: _stepMs),
                  curve: Curves.easeInOut,
                  builder: (context, t, _) {
                    final o = Offset.lerp(_from, _to, t)!;
                    final lift = sin(pi * t) * chip * 0.9;
                    return Positioned(
                      left: o.dx - chip / 2,
                      top: o.dy - chip / 2 - 6 - lift,
                      width: chip,
                      height: chip,
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                          child: Text(
                            '$_hand',
                            style: TextStyle(
                              color: const Color(0xFF3E2410),
                              fontWeight: FontWeight.w900,
                              fontSize: chip * 0.5,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Le Songô se joue en mode paysage (plateau plus grand) ; l'icône de
/// rotation permet de revenir en portrait.
class SongoOrient {
  static bool landscape = true;

  static void apply() {
    try {
      SystemChrome.setPreferredOrientations(landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
    } catch (_) {}
  }

  static void release() {
    try {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
  }
}

class _RotateToggle extends StatefulWidget {
  const _RotateToggle();

  @override
  State<_RotateToggle> createState() => _RotateToggleState();
}

class _RotateToggleState extends State<_RotateToggle> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Pivoter l\'écran', 'Rotate the screen'),
      onPressed: () {
        setState(() => SongoOrient.landscape = !SongoOrient.landscape);
        SongoOrient.apply();
      },
      icon: Icon(
        SongoOrient.landscape
            ? Icons.stay_current_portrait
            : Icons.stay_current_landscape,
        color: Colors.white,
      ),
    );
  }
}

class _SoundToggle extends StatefulWidget {
  const _SoundToggle();

  @override
  State<_SoundToggle> createState() => _SoundToggleState();
}

class _SoundToggleState extends State<_SoundToggle> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Son', 'Sound'),
      onPressed: () => setState(() => SongoSound.on = !SongoSound.on),
      icon: Icon(
        SongoSound.on ? Icons.volume_up : Icons.volume_off,
        color: Colors.white,
      ),
    );
  }
}

/// Boutons du haut de l'écran : son + règles.
Widget _gameActions(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _RotateToggle(),
        const _SoundToggle(),
        IconButton(
          tooltip: tr('Règles', 'Rules'),
          onPressed: () => _showRules(context),
          icon: const Icon(Icons.help_outline, color: Colors.white),
        ),
      ],
    );

/// Scores : graines capturées par chaque joueur, et à qui c'est de jouer.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.names,
    required this.scores,
    required this.cur,
    required this.over,
  });

  final List<String> names;
  final List<int> scores;
  final int cur;
  final bool over;

  Widget _chip(int i) {
    final turn = !over && cur == i;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(turn ? 0.22 : 0.1),
          border: Border.all(
            color: turn ? _seatColor[i] : Colors.white24,
            width: turn ? 3 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                turn ? '▶ ${names[i]}' : names[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _seatColor[i],
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${scores[i]} / $kSongoWin',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      Row(children: [_chip(0), _chip(1)]);
}

class _SShell extends StatelessWidget {
  const _SShell({required this.title, required this.child, this.trailing});
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

List<int> _intsOf(dynamic l, List<int> fb) =>
    l is List ? l.map((e) => (e as num).toInt()).toList() : fb;

String _stakeText(Map<String, dynamic> d) {
  final s = (d['stake'] as num?)?.toInt();
  if (s == null) return '';
  return s > 0
      ? tr(' • mise $s', ' • stake $s')
      : tr(' • gratuite', ' • free');
}

CollectionReference<Map<String, dynamic>> get _rooms =>
    FirebaseFirestore.instance.collection('songo');

Widget _label(String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        s,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

Widget _hint(String s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(s, style: const TextStyle(color: Colors.white70)),
    );

/// Panneau de fin de partie.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.names,
    required this.scores,
    required this.winners,
    required this.stake,
    this.forfeit = -1,
    this.jackpot = 0,
    this.extra,
  });

  final List<String> names;
  final List<int> scores;
  final List<int> winners;
  final int stake;
  final int forfeit;
  final int jackpot;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final draw = winners.length != 1;
    final head = draw
        ? tr('🤝 Égalité', '🤝 Draw')
        : tr('🏆 ${names[winners.first]} gagne !',
            '🏆 ${names[winners.first]} wins!');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.14),
        border: Border.all(color: _gold, width: 2),
      ),
      child: Column(
        children: [
          Text(
            head,
            style: const TextStyle(
              color: _gold,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (forfeit >= 0)
            Text(
              tr('${names[forfeit]} a abandonné.',
                  '${names[forfeit]} gave up.'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          Text(
            '${names[0]} ${scores[0]}  –  ${scores[1]} ${names[1]}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (stake > 0)
            Text(
              draw
                  ? tr('Égalité : la cagnotte est partagée.',
                      'Draw: the pot is shared.')
                  : tr(
                      'Gain : ${Wallet.format(Wallet.prize(stake * 2))} (commission ${Wallet.commissionPercent} %)',
                      'Prize: ${Wallet.format(Wallet.prize(stake * 2))} (${Wallet.commissionPercent} % commission)'),
              style: const TextStyle(color: _goldSoft, fontSize: 13),
            ),
          if (jackpot > 0)
            Text(
              tr('🎰 Jackpot gagné : ${Wallet.format(jackpot)}',
                  '🎰 Jackpot won: ${Wallet.format(jackpot)}'),
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

const String _rulesText =
    'Plateau : 14 cases (7 par joueur), 5 graines par case.\n'
    'On prend toutes les graines d\'une de ses cases et on les sème une à une '
    'dans le sens des aiguilles d\'une montre. La case de départ est sautée '
    'quand le semis fait le tour.\n'
    'Capture : si la dernière graine tombe chez l\'adversaire et que la case '
    'compte 2, 3 ou 4 graines, on les prend, puis on remonte en arrière '
    'tant que les cases ont 2, 3 ou 4 graines. La première case du camp '
    'adverse n\'est jamais prise.\n'
    'Interdit d\'affamer : une rafle qui viderait tout le camp adverse est '
    'annulée, et si l\'adversaire n\'a plus de graines il faut lui en envoyer.\n'
    'Fin : 36 graines capturées, ou moins de 10 graines sur le plateau, ou '
    'plus aucun coup possible (chacun garde les graines de son camp).';

void _showRules(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0B2FA6),
      title: const Text('Règles du Songô',
          style: TextStyle(color: _goldSoft, fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Text(_rulesText, style: const TextStyle(color: Colors.white)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fermer', style: TextStyle(color: _goldSoft)),
        ),
      ],
    ),
  );
}

// ======================================================================
// Page d'accueil du Songô
// ======================================================================

class SongoPage extends StatelessWidget {
  const SongoPage({super.key});

  void _go(BuildContext context, Widget Function(BuildContext) page) {
    final loggedIn =
        !firebaseReady || FirebaseAuth.instance.currentUser != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => loggedIn ? page(c) : OnlineScreen(onSignedIn: page),
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
            colors: [color.withOpacity(0.95), color.withOpacity(0.7)],
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
    return _SShell(
      title: 'Songô',
      trailing: IconButton(
        tooltip: tr('Règles', 'Rules'),
        onPressed: () => _showRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _card(
              Icons.groups,
              'En présentiel',
              'Deux joueurs sur un téléphone',
              const Color(0xFF22B14C),
              () => _go(context, (_) => const _SongoLocalSetup()),
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
                _go(context, (_) => const _SongoHub());
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Présentiel
// ======================================================================

class _SongoLocalSetup extends StatefulWidget {
  const _SongoLocalSetup();

  @override
  State<_SongoLocalSetup> createState() => _SongoLocalSetupState();
}

class _SongoLocalSetupState extends State<_SongoLocalSetup> {
  int stake = Wallet.minStake;
  bool starting = false;
  final Map<int, PlayerAccount> accounts = {};
  final List<TextEditingController> ctrls =
      List.generate(2, (_) => TextEditingController());

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

  Future<void> _connect(int seat) async {
    final acc = await showPlayerLogin(
      context,
      colorName: seat == 0 ? 'Jaune' : 'Vert',
      color: _seatColor[seat],
    );
    if (acc == null || !mounted) return;
    if (accounts.entries.any((e) => e.key != seat && e.value.uid == acc.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce compte joue déjà dans la partie.')),
      );
      return;
    }
    setState(() => accounts[seat] = acc);
  }

  bool get ready => !firebaseReady || accounts.length == 2;

  String? get brokePlayer {
    if (!firebaseReady) return null;
    for (int s = 0; s < 2; s++) {
      final a = accounts[s];
      if (a != null && a.balance < stake) return a.name;
    }
    return null;
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
          hintText: tr('Joueur ${seat + 1}', 'Player ${seat + 1}'),
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
          border: Border.all(color: _seatColor[seat], width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acc.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            Text('💰 ${Wallet.format(acc.balance)}',
                style: const TextStyle(color: _goldSoft, fontSize: 12)),
          ],
        ),
      );
    } else {
      field = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: _seatColor[seat], width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _connect(seat),
        icon: const Icon(Icons.login),
        label: Text(tr('Joueur ${seat + 1} : se connecter',
            'Player ${seat + 1}: sign in')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: _seatColor[seat]),
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

  Future<void> _start() async {
    if (starting || stake < 0) return;
    String? localId;
    final uids = <String?>[null, null];
    if (firebaseReady) {
      setState(() => starting = true);
      try {
        final tokens = <String>[];
        for (int s = 0; s < 2; s++) {
          final a = accounts[s]!;
          uids[s] = a.uid;
          if (a.uid == FirebaseAuth.instance.currentUser?.uid) {
            final u = FirebaseAuth.instance.currentUser;
            tokens.add((await u?.getIdToken(true)) ?? '');
          } else {
            tokens.add(a.idToken ?? '');
          }
        }
        localId = await Wallet.startLocalGame(
          stake: stake,
          tokens: tokens,
          names: [accounts[0]!.name, accounts[1]!.name],
          game: 'songo',
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
      for (int i = 0; i < 2; i++)
        firebaseReady
            ? accounts[i]!.name
            : (ctrls[i].text.trim().isNotEmpty
                ? ctrls[i].text.trim()
                : tr('Joueur ${i + 1}', 'Player ${i + 1}')),
    ];
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SongoLocalGame(
          names: names,
          stake: firebaseReady ? stake : 0,
          localId: localId,
          uids: uids,
        ),
      ),
    );
    if (!mounted) return;
    // Soldes à jour pour la partie suivante.
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      setState(() => accounts.removeWhere((k, v) => k != 0));
      if (u != null) await _loadHost(u);
    }
  }

  @override
  Widget build(BuildContext context) {
    final broke = brokePlayer;
    return _SShell(
      title: 'Songô · présentiel',
      trailing: IconButton(
        onPressed: () => _showRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (firebaseReady) ...[
            const JackpotBanner(),
            _label('Mise de chaque joueur'),
            StakeField(
              stake: stake,
              players: 2,
              local: true,
              onChanged: (v) => setState(() => stake = v),
            ),
          ],
          _label(firebaseReady
              ? 'Joueurs (chacun se connecte à son compte)'
              : 'Joueurs'),
          _row(0),
          _row(1),
          if (broke != null && stake > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                tr('Solde insuffisant : $broke', 'Insufficient balance: $broke'),
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22B14C),
                foregroundColor: Colors.white,
              ),
              onPressed: (!ready || starting || stake < 0 ||
                      (broke != null && stake > 0))
                  ? null
                  : _start,
              child: Text(
                starting
                    ? 'Mise en cours...'
                    : (stake <= 0
                        ? 'Lancer · partie gratuite'
                        : tr('Lancer · mise ${Wallet.format(stake)}',
                            'Start · stake ${Wallet.format(stake)}')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongoLocalGame extends StatefulWidget {
  const _SongoLocalGame({
    required this.names,
    this.stake = 0,
    this.localId,
    this.uids = const [],
  });

  final List<String> names;
  final int stake;
  final String? localId;
  final List<String?> uids;

  @override
  State<_SongoLocalGame> createState() => _SongoLocalGameState();
}

class _SongoLocalGameState extends State<_SongoLocalGame> {
  SongoGame g = SongoGame();
  bool _settled = false;
  int _tries = 0;
  int jackpot = 0;

  /// Dernier coup dont l'animation est terminée, et scores à ce moment-là.
  int _doneMove = 0;
  final Map<int, List<int>> _scoresAt = {0: [0, 0]};

  bool get _busy => g.moveN != _doneMove;
  bool get _overShown => g.over && !_busy;

  @override
  void initState() {
    super.initState();
    SongoOrient.apply();
  }

  @override
  void dispose() {
    SongoOrient.release();
    super.dispose();
  }

  void _tap(int pit) {
    if (_busy || !g.play(pit)) return;
    _scoresAt[g.moveN] = List<int>.from(g.scores);
    setState(() {});
  }

  void _settledMove(int m) {
    if (!mounted) return;
    setState(() => _doneMove = m);
    if (g.over && g.moveN == m) _settle();
  }

  Future<void> _settle() async {
    final id = widget.localId;
    if (id == null || _settled || !firebaseReady) return;
    _settled = true;
    try {
      final ws = <String>[
        for (final s in g.winners)
          if (s < widget.uids.length && widget.uids[s] != null)
            widget.uids[s]!,
      ];
      final res = await Wallet.settleLocalFull(id, ws, List<int>.from(g.scores));
      final jp = (res['jackpot'] as num?)?.toInt() ?? 0;
      if (mounted && jp > 0) setState(() => jackpot = jp);
    } catch (_) {
      _settled = false;
      if (mounted && ++_tries < 4) {
        Future.delayed(const Duration(seconds: 5), _settle);
      }
    }
  }

  String get _lastText {
    if (g.moveN == 0) return tr('À toi de commencer !', 'Your move!');
    final who = widget.names[1 - g.cur];
    if (g.lastCap > 0) {
      return tr('$who a pris ${g.lastCap} graines.',
          '$who captured ${g.lastCap} seeds.');
    }
    if (g.lastCancelled) {
      return tr('Rafle annulée : on ne peut pas affamer l\'adversaire.',
          'Capture cancelled: you cannot starve the opponent.');
    }
    return tr('$who a joué.', '$who played.');
  }

  @override
  Widget build(BuildContext context) {
    final shownScores = _scoresAt[_doneMove] ?? g.scores;
    return PopScope(
      canPop: widget.stake == 0 || g.over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Termine la partie pour régler les mises.'),
            ),
          );
        }
      },
      child: _SShell(
        title: 'Songô',
        trailing: _gameActions(context),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _ScoreBar(
                    names: widget.names,
                    scores: shownScores,
                    cur: g.cur,
                    over: _overShown,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SongoBoardView(
                      board: g.board,
                      viewer: 0,
                      legal: (_busy || g.over) ? const [] : g.legal,
                      onPit: _tap,
                      moveN: g.moveN,
                      lastFrom: g.lastFrom,
                      onSettled: _settledMove,
                      over: g.over,
                      names: widget.names,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _overShown || _busy ? ' ' : _lastText,
                    style: const TextStyle(color: _goldSoft, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (_overShown)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 440, maxHeight: 330),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: _ResultPanel(
                        names: widget.names,
                        scores: g.scores,
                        winners: g.winners,
                        stake: widget.stake,
                        jackpot: jackpot,
                        extra: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22B14C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Terminer'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// En ligne : salon
// ======================================================================

class _SongoHub extends StatefulWidget {
  const _SongoHub();

  @override
  State<_SongoHub> createState() => _SongoHubState();
}

class _SongoHubState extends State<_SongoHub> {
  int stake = Wallet.minStake;
  bool privateRoom = false;
  bool busy = false;
  String? error;
  bool showOpen = false;
  bool showLive = false;
  final TextEditingController codeCtrl = TextEditingController();

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _rooms.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> liveStream =
      _rooms.where('status', isEqualTo: 'playing').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _rooms.where('uids', arrayContains: uid).snapshots();

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _open(String id, {bool spectate = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SongoRoom(roomId: id, spectate: spectate),
      ),
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
    if (user == null || busy || stake < 0) return;
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
      final init = SongoGame();
      await ref.set({
        'hostUid': user.uid,
        'hostName': _userName(user),
        'maxPlayers': 2,
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
        'miss': [0, 0],
        ...init.toDoc(),
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
            'règles Firestore (collection « songo »).');
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
        if (d['status'] != 'waiting' || players.length >= 2) {
          return 'Cette partie est déjà complète.';
        }
        players.add({'uid': user.uid, 'name': _userName(user)});
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

  Widget _tile(String title, String sub, String btn, VoidCallback? onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Text(sub,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22B14C),
              foregroundColor: Colors.white,
            ),
            onPressed: onTap,
            child: Text(btn),
          ),
        ],
      ),
    );
  }

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
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
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
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  waiting
                      ? tr('En attente ($n/2 joueurs)${_stakeText(d)}',
                          'Waiting ($n/2 players)${_stakeText(d)}')
                      : tr('En cours${_stakeText(d)}',
                          'In progress${_stakeText(d)}'),
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
        if (snap.hasError) return _hint('Impossible de charger les parties.');
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
              _tile(
                tr("Partie de ${doc.data()['hostName']}",
                    "${doc.data()['hostName']}'s game"),
                '${_playersOf(doc.data()).length}/2${_stakeText(doc.data())}',
                'Rejoindre',
                busy ? null : () => _join(doc.id),
              ),
          ],
        );
      },
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
              _tile(
                _playersOf(doc.data()).map((p) => '${p['name']}').join(' vs '),
                _stakeText(doc.data()).replaceFirst(' • ', ''),
                'Regarder',
                () => _open(doc.id, spectate: true),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SShell(
      title: 'Songô · en ligne',
      trailing: IconButton(
        onPressed: () => _showRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const JackpotBanner(),
          _label('Créer une partie'),
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
          StakeField(
            stake: stake,
            players: 2,
            onChanged: (v) => setState(() => stake = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: _gold,
            title: const Text('Partie privée',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
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
              onPressed: (busy || stake < 0) ? null : _create,
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
          _listButton('🌰 Parties ouvertes', showOpen,
              () => setState(() => showOpen = !showOpen)),
          if (showOpen) _openList(),
          _listButton('👀 Parties en cours', showLive,
              () => setState(() => showLive = !showLive)),
          if (showLive) _liveList(),
        ],
      ),
    );
  }
}

// ======================================================================
// En ligne : salle d'attente puis partie
// ======================================================================

/// Revoir une partie de Songô en ligne (lecture seule) : tableau de bord admin.
/// Salle de jeu (pour les liens partagés).
Widget songoRoomPage(String id) => _SongoRoom(roomId: id);

class SongoSpectator extends StatelessWidget {
  const SongoSpectator({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) =>
      _SongoRoom(roomId: roomId, spectate: true);
}

class _SongoRoom extends StatefulWidget {
  const _SongoRoom({required this.roomId, this.spectate = false});

  final String roomId;
  final bool spectate;

  @override
  State<_SongoRoom> createState() => _SongoRoomState();
}

class _SongoRoomState extends State<_SongoRoom> {
  bool _settled = false;
  int _tries = 0;
  Timer? _timer;
  int _seenMove = -1;
  DateTime _stamp = DateTime.now();
  int _left = kSongoTurnSecs;
  bool _autoBusy = false;
  Map<String, dynamic>? _last;
  int _jackpotShown = 0;
  int _doneMove = -1;
  final Map<int, List<int>> _scoresAt = {};

  void _settledMove(int m) {
    if (!mounted) return;
    setState(() => _doneMove = m);
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      _rooms.doc(widget.roomId);

  bool _oriented = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_oriented) SongoOrient.release();
    super.dispose();
  }

  void _tick() {
    final d = _last;
    if (!mounted || d == null) return;
    if (d['status'] != 'playing' || d['over'] == true) return;
    final left = kSongoTurnSecs - DateTime.now().difference(_stamp).inSeconds;
    setState(() => _left = max(0, left));
    final players = _playersOf(d);
    final me = players.indexWhere(
        (p) => p['uid'] == FirebaseAuth.instance.currentUser?.uid);
    // Tous les joueurs assis peuvent jouer à la place d'un joueur absent.
    if (left <= -1 && me >= 0 && !_autoBusy) {
      _autoBusy = true;
      final g = SongoGame.fromDoc(d);
      _play(g.cur, null, g.moveN, auto: true).whenComplete(() {
        _autoBusy = false;
      });
    }
  }

  Widget _info(String text, {bool loading = false}) {
    return _SShell(
      title: 'Songô',
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _leave() async {
    Navigator.of(context).pop();
    try {
      await Wallet.leaveGame(widget.roomId);
    } catch (_) {}
  }

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

  /// Joue un coup (ou un coup automatique) dans une transaction.
  Future<void> _play(int seat, int? pit, int expectMove,
      {bool auto = false}) async {
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null) return;
        if (d['over'] == true || d['status'] != 'playing') return;
        final g = SongoGame.fromDoc(d);
        if (g.cur != seat || g.moveN != expectMove) return;
        final legal = g.legal;
        if (legal.isEmpty) return;
        var p = pit;
        if (p == null || !legal.contains(p)) {
          if (!auto) return;
          p = legal[Random().nextInt(legal.length)];
        }
        final miss = _intsOf(d['miss'], [0, 0]);
        while (miss.length < 2) {
          miss.add(0);
        }
        miss[seat] = auto ? miss[seat] + 1 : 0;
        if (auto && miss[seat] >= 3) {
          // Joueur absent : il perd la partie.
          tx.update(_ref, {
            'over': true,
            'status': 'finished',
            'forfeit': seat,
            'winners': [1 - seat],
            'miss': miss,
            'moveN': g.moveN + 1,
          });
          return;
        }
        g.play(p);
        tx.update(_ref, {
          ...g.toDoc(),
          'miss': miss,
          if (g.over) 'status': 'finished',
        });
      });
    } catch (_) {}
  }

  Future<void> _forfeit(int seat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner ?'),
        content: const Text('Tu perds la partie et ta mise.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null || d['over'] == true || d['status'] != 'playing') return;
        tx.update(_ref, {
          'over': true,
          'status': 'finished',
          'forfeit': seat,
          'winners': [1 - seat],
          'moveN': ((d['moveN'] as num?)?.toInt() ?? 0) + 1,
        });
      });
    } catch (_) {}
  }

  Widget _waiting(Map<String, dynamic> d, List<Map<String, dynamic>> players,
      String uid) {
    final isHost = d['hostUid'] == uid;
    final stake = (d['stake'] as num?)?.toInt() ?? 0;
    final pot = stake * 2;
    final paid = ((d['paid'] as List?) ?? const []).map((e) => '$e').toList();

    return _SShell(
      title: "Salle d'attente",
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr('${players.length}/2 joueurs', '${players.length}/2 players'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            "Le créateur lance la partie quand les deux joueurs ont payé leur mise.",
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
              color: _goldSoft,
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
          WaitingBell(collection: 'songo', gameId: widget.roomId),
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
              border: Border.all(color: _gold, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${d['code']}',
                    style: const TextStyle(
                      color: _gold,
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
          for (int i = 0; i < 2; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.12),
                border: Border.all(color: _seatColor[i], width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: _seatColor[i]),
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
        _last = d;

        final players = _playersOf(d);
        final seat = players.indexWhere((p) => p['uid'] == user.uid);
        if (seat < 0 && !widget.spectate) {
          return _info('Tu ne fais pas partie de cette partie.');
        }
        if (seat < 0 && d['status'] == 'waiting') {
          return _info("Cette partie n'a pas encore commencé.");
        }
        if (d['status'] == 'waiting') return _waiting(d, players, user.uid);

        if (!_oriented) {
          _oriented = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) SongoOrient.apply();
          });
        }
        final g = SongoGame.fromDoc(d);
        if (g.moveN != _seenMove) {
          _seenMove = g.moveN;
          _stamp = DateTime.now();
          _left = kSongoTurnSecs;
        }
        // Coup dont l'animation est terminée (au premier affichage : le coup
        // en cours, sans animation).
        if (_doneMove < 0) _doneMove = g.moveN;
        _scoresAt[g.moveN] = List<int>.from(g.scores);
        final busy = g.moveN != _doneMove;
        final shownScores = _scoresAt[_doneMove] ?? g.scores;

        final over = d['over'] == true;
        final overShown = over && !busy;
        if (overShown && seat >= 0) _settle();
        final stake = (d['stake'] as num?)?.toInt() ?? 0;
        final names = [
          for (int i = 0; i < 2; i++)
            i < players.length ? '${players[i]['name']}' : '?',
        ];
        final viewer = seat < 0 ? 0 : seat;
        final myTurn = seat >= 0 && g.cur == seat && !over && !busy;
        final forfeit = (d['forfeit'] as num?)?.toInt() ?? -1;
        final jp = (d['jackpot'] as num?)?.toInt() ?? 0;
        if (jp > 0) _jackpotShown = jp;

        String status;
        if (over || busy) {
          status = ' ';
        } else if (myTurn) {
          status = tr('À toi de jouer · $_left s', 'Your move · $_left s');
        } else {
          status = tr('${names[g.cur]} réfléchit · $_left s',
              '${names[g.cur]} is thinking · $_left s');
        }
        final lastInfo = g.moveN == 0 || over || busy
            ? ''
            : g.lastCap > 0
                ? tr('${names[1 - g.cur]} a pris ${g.lastCap} graines.',
                    '${names[1 - g.cur]} captured ${g.lastCap} seeds.')
                : g.lastCancelled
                    ? tr('Rafle annulée (interdit d\'affamer).',
                        'Capture cancelled (no starving).')
                    : '';

        return PopScope(
          canPop: stake == 0 || over || seat < 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Termine la partie (ou abandonne) pour régler la mise.'),
                ),
              );
            }
          },
          child: _SShell(
            title: 'Songô',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _gameActions(context),
                RoomInfoButton(collection: 'songo', gameId: widget.roomId),
                if (seat >= 0) ...[
                  const SizedBox(width: 6),
                  GameChat(
                    collection: 'songo',
                    gameId: widget.roomId,
                    myName: names[seat],
                  ),
                ],
              ],
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ScoreBar(
                        names: names,
                        scores: shownScores,
                        cur: g.cur,
                        over: overShown,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SongoBoardView(
                          board: g.board,
                          viewer: viewer,
                          legal: myTurn ? g.legal : const [],
                          onPit: (p) => _play(seat, p, g.moveN),
                          moveN: g.moveN,
                          lastFrom: g.lastFrom,
                          onSettled: _settledMove,
                          over: over,
                          names: names,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastInfo.isEmpty ? status : '$status  ·  $lastInfo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: myTurn ? _gold : _goldSoft,
                                fontSize: 15,
                                fontWeight:
                                    myTurn ? FontWeight.w900 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!over && seat >= 0)
                            TextButton(
                              onPressed: () => _forfeit(seat),
                              child: const Text(
                                'Abandonner',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (overShown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 440, maxHeight: 330),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: _ResultPanel(
                            names: names,
                            scores: g.scores,
                            winners: g.winners,
                            stake: stake,
                            forfeit: forfeit,
                            jackpot: _jackpotShown,
                            extra: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22B14C),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Terminer'),
                              ),
                            ),
                          ),
                        ),
                      ),
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
