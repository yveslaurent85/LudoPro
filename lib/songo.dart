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

class SongoOrient {
  static bool landscape = true;
  static final ValueNotifier<bool> mode = ValueNotifier<bool>(true);

  static void setLandscape(bool value) {
    landscape = value;
    mode.value = value;
    apply();
  }

  static void apply() {
    try {
      SystemChrome.setPreferredOrientations(landscape
          ? [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : [DeviceOrientation.portraitUp]);
    } catch (_) {}
  }

  static void release() {
    try {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    landscape = true;
    mode.value = true;
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
    return ValueListenableBuilder<bool>(
      valueListenable: SongoOrient.mode,
      builder: (context, landscape, _) {
        return IconButton(
          tooltip: tr('Pivoter l\'écran', 'Rotate the screen'),
          onPressed: () {
            SongoOrient.setLandscape(!landscape);
          },
          icon: Icon(
            landscape
                ? Icons.stay_current_portrait
                : Icons.stay_current_landscape,
            color: Colors.white,
          ),
        );
      },
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
              '${scores[i]} /$kSongoWin',
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
  Widget build(BuildContext context) => Row(children: [_chip(0), _chip(1)]);
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

List> _playersOf(Map<String, dynamic> d) =>
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

CollectionReference> get _rooms =>
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
            '${names[0]}${scores[0]}  –  ${scores[1]}${names[1]}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (stake > 0)
            Text(
              draw
                  ? tr('Égalité : la cagnotte est partagée.',
                      'Draw: the pot is shared.')
                  : tr(
                      'Gain : ${Wallet.format(Wallet.prize(stake * 2))} (commission${Wallet.commissionPercent} %)',
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
    '
