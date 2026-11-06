import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
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
// Damier : dames internationales 10x10 pour 2 joueurs.
//  • 20 pions chacun, cases sombres seulement.
//  • Le pion avance d'une case en diagonale ; il prend en avant et en
//    arrière en sautant un pion adverse (prise obligatoire).
//  • On doit jouer la rafle qui prend le plus de pièces.
//  • Un pion qui TERMINE son coup sur la dernière rangée devient dame.
//  • La dame glisse de plusieurs cases et prend de loin.
//  • Perd celui qui ne peut plus jouer (plus de pièces ou bloqué).
//  • Nulle : 3 fois la même position, 25 coups de dame sans prise ni pion,
//    ou 300 coups.
// En ligne : collection Firestore « damier ».
//
// Pièces : 1 / 2 = pion / dame du joueur 0 (blancs, en bas),
//         -1 / -2 = pion / dame du joueur 1 (noirs, en haut).
// ----------------------------------------------------------------------

const int kDamierTurnSecs = 60;
const int kDamierQuietPlies = 50;
const int kDamierMoveCap = 300;

const BoxDecoration _dBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

const List<Color> _dSeatColor = [Color(0xFFF5EBD0), Color(0xFF3A3A3A)];
const Color _dGold = Color(0xFFFFC21A);
const Color _dGoldSoft = Color(0xFFFFE082);

// ======================================================================
// Moteur de jeu
// ======================================================================

class DMove {
  const DMove(this.from, this.path, this.caps);

  /// Case de départ (r * 10 + c).
  final int from;

  /// Cases d'atterrissage successives (la dernière est l'arrivée).
  final List<int> path;

  /// Pièces prises, dans l'ordre (une par étape de [path]).
  final List<int> caps;

  int get to => path.last;

  bool sameAs(DMove o) {
    if (from != o.from || path.length != o.path.length) return false;
    for (int i = 0; i < path.length; i++) {
      if (path[i] != o.path[i]) return false;
    }
    return true;
  }
}

class DamierEngine {
  static const List<List<int>> _dirs = [
    [-1, -1],
    [-1, 1],
    [1, -1],
    [1, 1],
  ];

  static int owner(int p) => p > 0 ? 0 : 1;
  static bool isKing(int p) => p == 2 || p == -2;
  static bool _inb(int r, int c) => r >= 0 && r < 10 && c >= 0 && c < 10;

  static List<int> initial() {
    final b = List<int>.filled(100, 0);
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if ((r + c) % 2 != 1) continue;
        if (r < 4) {
          b[r * 10 + c] = -1;
        } else if (r >= 6) {
          b[r * 10 + c] = 1;
        }
      }
    }
    return b;
  }

  /// Plateau de départ avec handicap : [n] pions retirés au joueur [seat]
  /// (en commençant par le fond de son camp). seat < 0 ou n <= 0 : aucun.
  static List<int> initialH(int seat, int n) {
    final b = initial();
    if (seat < 0 || n <= 0) return b;
    int left = min(n, 19);
    final rows = seat == 0 ? [9, 8, 7, 6] : [0, 1, 2, 3];
    for (final r in rows) {
      for (int c = 0; c < 10 && left > 0; c++) {
        final p = b[r * 10 + c];
        if (p != 0 && owner(p) == seat) {
          b[r * 10 + c] = 0;
          left--;
        }
      }
    }
    return b;
  }

  /// Toutes les rafles possibles pour la pièce en [from].
  static List<DMove> _captures(List<int> board, int from) {
    final piece = board[from];
    final me = owner(piece);
    final king = isKing(piece);
    final res = <DMove>[];
    final b = List<int>.from(board);
    b[from] = 0; // la pièce a quitté sa case : elle ne gêne plus
    final capSet = <int>{};

    void dfs(int pos, List<int> path, List<int> caps) {
      bool found = false;
      final r = pos ~/ 10;
      final c = pos % 10;
      for (final d in _dirs) {
        final dr = d[0];
        final dc = d[1];
        if (!king) {
          final r1 = r + dr;
          final c1 = c + dc;
          final r2 = r + 2 * dr;
          final c2 = c + 2 * dc;
          if (!_inb(r2, c2)) continue;
          final m = b[r1 * 10 + c1];
          if (m != 0 &&
              owner(m) != me &&
              !capSet.contains(r1 * 10 + c1) &&
              b[r2 * 10 + c2] == 0) {
            found = true;
            capSet.add(r1 * 10 + c1);
            dfs(r2 * 10 + c2, [...path, r2 * 10 + c2], [...caps, r1 * 10 + c1]);
            capSet.remove(r1 * 10 + c1);
          }
        } else {
          int rr = r + dr;
          int cc = c + dc;
          while (_inb(rr, cc) && b[rr * 10 + cc] == 0) {
            rr += dr;
            cc += dc;
          }
          if (!_inb(rr, cc)) continue;
          final idx = rr * 10 + cc;
          final m = b[idx];
          if (owner(m) == me || capSet.contains(idx)) continue;
          int lr = rr + dr;
          int lc = cc + dc;
          while (_inb(lr, lc) && b[lr * 10 + lc] == 0) {
            found = true;
            capSet.add(idx);
            dfs(lr * 10 + lc, [...path, lr * 10 + lc], [...caps, idx]);
            capSet.remove(idx);
            lr += dr;
            lc += dc;
          }
        }
      }
      if (!found && caps.isNotEmpty) res.add(DMove(from, path, caps));
    }

    dfs(from, <int>[], <int>[]);
    return res;
  }

  /// Coups légaux du joueur [player] (prise obligatoire, rafle maximale).
  static List<DMove> legal(List<int> board, int player) {
    final caps = <DMove>[];
    for (int i = 0; i < 100; i++) {
      final p = board[i];
      if (p != 0 && owner(p) == player) caps.addAll(_captures(board, i));
    }
    if (caps.isNotEmpty) {
      int mx = 0;
      for (final m in caps) {
        if (m.caps.length > mx) mx = m.caps.length;
      }
      return [
        for (final m in caps)
          if (m.caps.length == mx) m,
      ];
    }
    final out = <DMove>[];
    for (int i = 0; i < 100; i++) {
      final p = board[i];
      if (p == 0 || owner(p) != player) continue;
      final r = i ~/ 10;
      final c = i % 10;
      if (!isKing(p)) {
        final dr = player == 0 ? -1 : 1;
        for (final dc in const [-1, 1]) {
          final r1 = r + dr;
          final c1 = c + dc;
          if (_inb(r1, c1) && board[r1 * 10 + c1] == 0) {
            out.add(DMove(i, [r1 * 10 + c1], const <int>[]));
          }
        }
      } else {
        for (final d in _dirs) {
          int rr = r + d[0];
          int cc = c + d[1];
          while (_inb(rr, cc) && board[rr * 10 + cc] == 0) {
            out.add(DMove(i, [rr * 10 + cc], const <int>[]));
            rr += d[0];
            cc += d[1];
          }
        }
      }
    }
    return out;
  }

  /// Plateau après le coup [m] (promotion comprise).
  static List<int> apply(List<int> board, DMove m) {
    final b = List<int>.from(board);
    final p = b[m.from];
    b[m.from] = 0;
    for (final k in m.caps) {
      b[k] = 0;
    }
    final end = m.to;
    int np = p;
    if (!isKing(p)) {
      final r = end ~/ 10;
      if ((owner(p) == 0 && r == 0) || (owner(p) == 1 && r == 9)) {
        np = p > 0 ? 2 : -2;
      }
    }
    b[end] = np;
    return b;
  }

  static int hash(List<int> board, int cur) {
    int h = 7;
    for (final p in board) {
      h = (h * 31 + p + 2) & 0x7fffffff;
    }
    return (h * 2 + cur) & 0x7fffffff;
  }
}

class DamierGame {
  DamierGame({int hSeat = -1, int hN = 0})
      : board = DamierEngine.initialH(hSeat, hN) {
    hist = [DamierEngine.hash(board, 0)];
  }

  List<int> board;
  int cur = 0;
  int moveN = 0;
  bool over = false;
  List<int> winners = [];
  int lastFrom = -1;
  List<int> lastPath = [];
  List<int> lastCaps = [];
  int quiet = 0;
  List<int> hist = [];
  String reason = ''; // '' | repeat | quiet | cap

  List<DMove> get legal =>
      over ? const <DMove>[] : DamierEngine.legal(board, cur);

  int count(int player) {
    int n = 0;
    for (final p in board) {
      if (p != 0 && DamierEngine.owner(p) == player) n++;
    }
    return n;
  }

  /// Joue le coup [m] s'il est légal. Renvoie faux sinon.
  bool play(DMove m) {
    if (over) return false;
    DMove? mv;
    for (final x in legal) {
      if (x.sameAs(m)) {
        mv = x;
        break;
      }
    }
    if (mv == null) return false;
    final piece = board[mv.from];
    final kingQuiet = DamierEngine.isKing(piece) && mv.caps.isEmpty;
    quiet = kingQuiet ? quiet + 1 : 0;
    board = DamierEngine.apply(board, mv);
    lastFrom = mv.from;
    lastPath = List<int>.from(mv.path);
    lastCaps = List<int>.from(mv.caps);
    moveN++;
    final mover = cur;
    cur = 1 - cur;
    final h = DamierEngine.hash(board, cur);
    hist.add(h);

    if (DamierEngine.legal(board, cur).isEmpty) {
      over = true;
      winners = [mover];
      return true;
    }
    int same = 0;
    for (final x in hist) {
      if (x == h) same++;
    }
    if (same >= 3) {
      over = true;
      winners = [0, 1];
      reason = 'repeat';
    } else if (quiet >= kDamierQuietPlies) {
      over = true;
      winners = [0, 1];
      reason = 'quiet';
    } else if (moveN >= kDamierMoveCap) {
      over = true;
      winners = [0, 1];
      reason = 'cap';
    }
    return true;
  }

  Map<String, dynamic> toDoc() => {
        'board': board,
        'cur': cur,
        'moveN': moveN,
        'over': over,
        'winners': winners,
        'lastFrom': lastFrom,
        'lastPath': lastPath,
        'lastCaps': lastCaps,
        'quiet': quiet,
        'hist': hist,
        'reason': reason,
      };

  static List<int> _ints(dynamic l, List<int> fb) =>
      l is List ? l.map((e) => (e as num).toInt()).toList() : fb;

  static DamierGame fromDoc(Map<String, dynamic> d) {
    final g = DamierGame();
    final b = _ints(d['board'], const <int>[]);
    if (b.length == 100) g.board = b;
    g.cur = (d['cur'] as num?)?.toInt() ?? 0;
    g.moveN = (d['moveN'] as num?)?.toInt() ?? 0;
    g.over = d['over'] == true;
    g.winners = _ints(d['winners'], <int>[]);
    g.lastFrom = (d['lastFrom'] as num?)?.toInt() ?? -1;
    g.lastPath = _ints(d['lastPath'], <int>[]);
    g.lastCaps = _ints(d['lastCaps'], <int>[]);
    g.quiet = (d['quiet'] as num?)?.toInt() ?? 0;
    g.hist = _ints(d['hist'], <int>[]);
    g.reason = (d['reason'] as String?) ?? '';
    return g;
  }
}

// ======================================================================
// Plateau (dessin, touches, animation du coup)
// ======================================================================

class DamierBoardView extends StatefulWidget {
  const DamierBoardView({
    super.key,
    required this.board,
    required this.flip,
    required this.legal,
    required this.onMove,
    required this.moveN,
    required this.lastFrom,
    required this.lastPath,
    required this.lastCaps,
    required this.onSettled,
  });

  final List<int> board;
  final bool flip; // plateau retourné (les noirs en bas)
  final List<DMove> legal; // vide si ce n'est pas à moi de jouer
  final void Function(DMove) onMove;
  final int moveN;
  final int lastFrom;
  final List<int> lastPath;
  final List<int> lastCaps;
  final void Function(int) onSettled;

  @override
  State<DamierBoardView> createState() => _DamierBoardViewState();
}

class _DamierBoardViewState extends State<DamierBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late List<int> _prev; // plateau avant le dernier coup (stable)
  bool _animating = false;
  List<int> _animPath = const [];
  List<int> _animCaps = const [];
  int _animFrom = -1;
  int _animPiece = 0;
  List<int> _animBoard = const [];

  int _sel = -1;
  List<int> _steps = [];

  @override
  void initState() {
    super.initState();
    _prev = List<int>.from(widget.board);
    _anim = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _animating = false;
      _prev = List<int>.from(widget.board);
    });
    widget.onSettled(widget.moveN);
  }

  @override
  void didUpdateWidget(DamierBoardView old) {
    super.didUpdateWidget(old);
    if (widget.moveN == old.moveN) {
      if (!_animating) _prev = List<int>.from(widget.board);
      return;
    }
    _sel = -1;
    _steps = [];
    final oneStep = widget.moveN == old.moveN + 1 && !_animating;
    if (_animating) _anim.stop();
    if (oneStep && widget.lastPath.isNotEmpty && widget.lastFrom >= 0) {
      _animBoard = List<int>.from(_prev);
      _animFrom = widget.lastFrom;
      _animPiece = _animBoard[_animFrom];
      _animBoard[_animFrom] = 0;
      _animPath = List<int>.from(widget.lastPath);
      _animCaps = List<int>.from(widget.lastCaps);
      _animating = true;
      final ms = min(1800, 220 * _animPath.length + 120);
      _anim.duration = Duration(milliseconds: ms);
      _anim.forward(from: 0);
      HapticFeedback.selectionClick();
    } else {
      _animating = false;
      _prev = List<int>.from(widget.board);
      final m = widget.moveN;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSettled(m);
      });
    }
  }

  List<DMove> get _cands {
    final out = <DMove>[];
    for (final m in widget.legal) {
      if (m.from != _sel || m.path.length < _steps.length) continue;
      bool ok = true;
      for (int i = 0; i < _steps.length; i++) {
        if (m.path[i] != _steps[i]) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(m);
    }
    return out;
  }

  bool _canPick(int idx) {
    for (final m in widget.legal) {
      if (m.from == idx) return true;
    }
    return false;
  }

  void _tap(int idx) {
    if (_animating || widget.legal.isEmpty) return;
    if (_sel == -1) {
      if (_canPick(idx)) {
        setState(() {
          _sel = idx;
          _steps = [];
        });
      }
      return;
    }
    final cands = _cands;
    final next = <DMove>[
      for (final m in cands)
        if (m.path.length > _steps.length && m.path[_steps.length] == idx) m,
    ];
    if (next.isEmpty) {
      setState(() {
        _sel = _canPick(idx) && idx != _sel ? idx : -1;
        _steps = [];
      });
      return;
    }
    final steps = [..._steps, idx];
    DMove? done;
    for (final m in next) {
      if (m.path.length == steps.length) {
        done = m;
        break;
      }
    }
    if (next.length == 1) done = next.first;
    if (done != null) {
      setState(() {
        _sel = -1;
        _steps = [];
      });
      widget.onMove(done);
    } else {
      setState(() => _steps = steps);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<int> shown = widget.board;
    int moverPiece = 0;
    Offset? moverPos;
    final hidden = <int>{};
    if (_animating) {
      shown = _animBoard;
      moverPiece = _animPiece;
      final n = _animPath.length;
      final pos = _anim.value * n;
      int seg = pos.floor();
      if (seg >= n) seg = n - 1;
      final frac = pos - seg;
      final pts = [_animFrom, ..._animPath];
      final a = pts[seg];
      final b = pts[seg + 1];
      moverPos = Offset(
        (a % 10) + ((b % 10) - (a % 10)) * frac,
        (a ~/ 10) + ((b ~/ 10) - (a ~/ 10)) * frac,
      );
      for (int i = 0; i < _animCaps.length; i++) {
        if (pos >= i + 0.8) hidden.add(_animCaps[i]);
      }
    }

    final targets = <int>{};
    final picks = <int>{};
    if (!_animating && widget.legal.isNotEmpty) {
      if (_sel == -1) {
        for (final m in widget.legal) {
          picks.add(m.from);
        }
      } else {
        for (final m in _cands) {
          if (m.path.length > _steps.length) targets.add(m.path[_steps.length]);
        }
      }
    }
    final last = <int>{};
    if (!_animating && widget.lastFrom >= 0 && widget.lastPath.isNotEmpty) {
      last.add(widget.lastFrom);
      last.add(widget.lastPath.last);
    }

    return LayoutBuilder(
      builder: (context, box) {
        final side = min(box.maxWidth, box.maxHeight);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final cell = side / 10;
                int c = (d.localPosition.dx / cell).floor();
                int r = (d.localPosition.dy / cell).floor();
                if (r < 0 || r > 9 || c < 0 || c > 9) return;
                if (widget.flip) {
                  r = 9 - r;
                  c = 9 - c;
                }
                _tap(r * 10 + c);
              },
              child: CustomPaint(
                painter: _DBoardPainter(
                  board: shown,
                  flip: widget.flip,
                  sel: _sel,
                  steps: _steps,
                  targets: targets,
                  picks: picks,
                  last: last,
                  moverPiece: moverPiece,
                  moverPos: moverPos,
                  hidden: hidden,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DBoardPainter extends CustomPainter {
  _DBoardPainter({
    required this.board,
    required this.flip,
    required this.sel,
    required this.steps,
    required this.targets,
    required this.picks,
    required this.last,
    required this.moverPiece,
    required this.moverPos,
    required this.hidden,
  });

  final List<int> board;
  final bool flip;
  final int sel;
  final List<int> steps;
  final Set<int> targets;
  final Set<int> picks;
  final Set<int> last;
  final int moverPiece;
  final Offset? moverPos;
  final Set<int> hidden;

  Offset _center(double r, double c, double cell) {
    final rr = flip ? 9 - r : r;
    final cc = flip ? 9 - c : c;
    return Offset((cc + 0.5) * cell, (rr + 0.5) * cell);
  }

  Rect _rect(int r, int c, double cell) {
    final rr = flip ? 9 - r : r;
    final cc = flip ? 9 - c : c;
    return Rect.fromLTWH(cc * cell, rr * cell, cell, cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 10;
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(frame);
    final light = Paint()..color = const Color(0xFFF1DDB0);
    final dark = Paint()..color = const Color(0xFF8D5A2B);
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        final rect = _rect(r, c, cell);
        canvas.drawRect(rect, (r + c) % 2 == 1 ? dark : light);
        final idx = r * 10 + c;
        if (last.contains(idx)) {
          canvas.drawRect(
            rect,
            Paint()..color = const Color(0xFFFFE082).withOpacity(0.45),
          );
        }
        if (idx == sel || steps.contains(idx)) {
          canvas.drawRect(
            rect,
            Paint()..color = const Color(0xFF22B14C).withOpacity(0.55),
          );
        }
        if (picks.contains(idx)) {
          canvas.drawRect(
            rect.deflate(cell * 0.06),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.07
              ..color = const Color(0xFFFFC21A),
          );
        }
      }
    }
    canvas.restore();

    for (int i = 0; i < 100; i++) {
      final p = board[i];
      if (p == 0 || hidden.contains(i)) continue;
      _piece(canvas, _center((i ~/ 10).toDouble(), (i % 10).toDouble(), cell),
          cell * 0.4, p);
    }

    for (final t in targets) {
      final c = _center((t ~/ 10).toDouble(), (t % 10).toDouble(), cell);
      canvas.drawCircle(
        c,
        cell * 0.16,
        Paint()..color = const Color(0xFF22B14C).withOpacity(0.9),
      );
      canvas.drawCircle(
        c,
        cell * 0.16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }

    final mp = moverPos;
    if (mp != null && moverPiece != 0) {
      _piece(canvas, _center(mp.dy, mp.dx, cell), cell * 0.4, moverPiece,
          lifted: true);
    }

    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF4A2A0E),
    );
  }

  void _piece(Canvas canvas, Offset c, double rad, int p,
      {bool lifted = false}) {
    final white = p > 0;
    canvas.drawCircle(
      c.translate(0, lifted ? rad * 0.18 : rad * 0.1),
      rad,
      Paint()..color = Colors.black.withOpacity(lifted ? 0.5 : 0.35),
    );
    final shader = RadialGradient(
      colors: white
          ? const [Color(0xFFFFFFFF), Color(0xFFE2CE9E)]
          : const [Color(0xFF6A6A6A), Color(0xFF111111)],
    ).createShader(
      Rect.fromCircle(center: c.translate(-rad * 0.25, -rad * 0.25), radius: rad * 1.3),
    );
    canvas.drawCircle(c, rad, Paint()..shader = shader);
    canvas.drawCircle(
      c,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.08
        ..color = white ? const Color(0xFF9C8450) : const Color(0xFF000000),
    );
    canvas.drawCircle(
      c,
      rad * 0.68,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.07
        ..color = white ? const Color(0xFFB8A070) : const Color(0xFF444444),
    );
    if (p == 2 || p == -2) {
      final r = rad * 0.5;
      final path = Path()
        ..moveTo(c.dx - r, c.dy + r * 0.55)
        ..lineTo(c.dx - r, c.dy - r * 0.35)
        ..lineTo(c.dx - r * 0.45, c.dy + r * 0.05)
        ..lineTo(c.dx, c.dy - r * 0.7)
        ..lineTo(c.dx + r * 0.45, c.dy + r * 0.05)
        ..lineTo(c.dx + r, c.dy - r * 0.35)
        ..lineTo(c.dx + r, c.dy + r * 0.55)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFFFC21A));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF8A5A00),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DBoardPainter old) => true;
}

// ======================================================================
// Éléments communs
// ======================================================================

class _DShell extends StatelessWidget {
  const _DShell({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _dBg,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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

String _dUserName(User u) {
  final n = u.displayName;
  if (n != null && n.isNotEmpty) return n;
  return u.email ?? 'Joueur';
}

String _dNewCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

List<Map<String, dynamic>> _dPlayersOf(Map<String, dynamic> d) =>
    ((d['players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

List<int> _dIntsOf(dynamic l, List<int> fb) =>
    l is List ? l.map((e) => (e as num).toInt()).toList() : fb;

String _dStakeText(Map<String, dynamic> d) {
  final s = (d['stake'] as num?)?.toInt();
  if (s == null) return '';
  return s > 0
      ? tr(' • mise $s', ' • stake $s')
      : tr(' • gratuite', ' • free');
}

CollectionReference<Map<String, dynamic>> get _dRooms =>
    FirebaseFirestore.instance.collection('damier');

String _dFmtClock(int ms) {
  final s = (max(0, ms) / 1000).ceil();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r < 10 ? '0' : ''}$r';
}

/// Choix du temps : 1 à 10 minutes pour chaque joueur (temps différents
/// possibles), bonus de 0 à 5 s par coup.
Widget _dClockPicker({
  required int timeMin,
  required int timeOpp,
  required int incSec,
  required ValueChanged<int> onMin,
  required ValueChanged<int> onOpp,
  required ValueChanged<int> onInc,
  String labelMe = '',
  String labelOpp = '',
}) {
  final me = labelMe.isEmpty ? tr('Mon temps', 'My time') : labelMe;
  final opp =
      labelOpp.isEmpty ? tr("Temps de l'adversaire", "Opponent's time") : labelOpp;
  Widget minutes(int cur, ValueChanged<int> on) => Wrap(
        spacing: 8,
        children: [
          for (int m = 1; m <= 10; m++)
            ChoiceChip(
              label: Text('$m min'),
              selected: cur == m,
              selectedColor: _dGold,
              onSelected: (_) => on(m),
            ),
        ],
      );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _dLabel('⏱️ $me'),
      minutes(timeMin, onMin),
      _dLabel('⏱️ $opp'),
      minutes(timeOpp, onOpp),
      _dLabel(tr('➕ Bonus après chaque coup', '➕ Bonus after each move')),
      Wrap(
        spacing: 8,
        children: [
          for (int b = 0; b <= 5; b++)
            ChoiceChip(
              label: Text('$b s'),
              selected: incSec == b,
              selectedColor: _dGold,
              onSelected: (_) => onInc(b),
            ),
        ],
      ),
    ],
  );
}

/// Fréquences possibles de la règle du nul : [numérateur, dénominateur].
const List<List<int>> _kDrawFreqs = [
  [1, 1],
  [1, 2],
  [1, 3],
  [1, 4],
  [2, 3],
];

String _dFreqText(int nn, int dd) {
  if (dd <= 1) return tr('à chaque nul', 'on every draw');
  return tr('tirage au sort : $nn chance${nn > 1 ? 's' : ''} sur $dd',
      'random draw: $nn chance${nn > 1 ? 's' : ''} in $dd');
}

/// Handicap (pions en moins) et règle du nul, choisis par le créateur.
Widget _dRulesPicker({
  required int hSeat,
  required int hN,
  required int drawSeat,
  required int drawNum,
  required int drawDen,
  required ValueChanged<int> onHSeat,
  required ValueChanged<int> onHN,
  required ValueChanged<int> onDrawSeat,
  required void Function(int, int) onFreq,
  String labelMe = '',
  String labelOpp = '',
}) {
  final me = labelMe.isEmpty ? tr('Moi', 'Me') : labelMe;
  final opp = labelOpp.isEmpty ? tr('Mon adversaire', 'My opponent') : labelOpp;
  Widget seatChips(int cur, String none, ValueChanged<int> on) => Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(none),
            selected: cur < 0,
            selectedColor: _dGold,
            onSelected: (_) => on(-1),
          ),
          ChoiceChip(
            label: Text(me),
            selected: cur == 0,
            selectedColor: _dGold,
            onSelected: (_) => on(0),
          ),
          ChoiceChip(
            label: Text(opp),
            selected: cur == 1,
            selectedColor: _dGold,
            onSelected: (_) => on(1),
          ),
        ],
      );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _dLabel(tr('🎁 Handicap : qui joue avec des pions en moins ?',
          '🎁 Handicap: who plays with fewer pieces?')),
      seatChips(hSeat, tr('Personne', 'Nobody'), onHSeat),
      if (hSeat >= 0) ...[
        _dLabel(tr('Nombre de pions en moins', 'Number of pieces fewer')),
        Wrap(
          spacing: 8,
          children: [
            for (int n = 1; n <= 8; n++)
              ChoiceChip(
                label: Text('−$n'),
                selected: hN == n,
                selectedColor: _dGold,
                onSelected: (_) => onHN(n),
              ),
          ],
        ),
      ],
      _dLabel(tr('🤝 En cas de nul, qui gagne ?',
          '🤝 On a draw, who wins?')),
      seatChips(drawSeat, tr('Personne (mises rendues)', 'Nobody (stakes refunded)'),
          onDrawSeat),
      if (drawSeat >= 0) ...[
        _dLabel(tr('Fréquence', 'Frequency')),
        Wrap(
          spacing: 8,
          children: [
            for (final f in _kDrawFreqs)
              ChoiceChip(
                label: Text(f[1] == 1
                    ? tr('Tous les nuls', 'Every draw')
                    : '${f[0]}/${f[1]}'),
                selected: drawNum == f[0] && drawDen == f[1],
                selectedColor: _dGold,
                onSelected: (_) => onFreq(f[0], f[1]),
              ),
          ],
        ),
      ],
    ],
  );
}

/// Résumé des règles d'une partie en ligne (une ligne par règle).
String _dRulesLine(Map<String, dynamic> d, {List<String>? names}) {
  final parts = <String>[];
  final host = '${d['hostName'] ?? tr('Créateur', 'Host')}';
  final opp = tr("l'adversaire", 'the opponent');
  String who(int s) => s == 0
      ? host
      : ((names != null && names.length > 1 && names[1] != '?')
          ? names[1]
          : opp);
  final t0 = (d['timeMin'] as num?)?.toInt();
  final t1 = (d['timeMinOpp'] as num?)?.toInt() ?? t0;
  if (t0 != null) {
    parts.add(t0 == t1
        ? '⏱️ $t0 min'
        : '⏱️ ${who(0)} $t0 min · ${who(1)} $t1 min');
  }
  final hs = (d['hSeat'] as num?)?.toInt() ?? -1;
  final hn = (d['hN'] as num?)?.toInt() ?? 0;
  if (hs >= 0 && hn > 0) {
    parts.add(tr('🎁 ${who(hs)} joue avec $hn pion${hn > 1 ? 's' : ''} de moins',
        '🎁 ${who(hs)} plays with $hn fewer piece${hn > 1 ? 's' : ''}'));
  }
  final ds = (d['drawSeat'] as num?)?.toInt() ?? -1;
  if (ds >= 0) {
    final fn = (d['drawNum'] as num?)?.toInt() ?? 1;
    final fd = (d['drawDen'] as num?)?.toInt() ?? 1;
    parts.add(tr('🤝 En cas de nul, ${who(ds)} gagne (${_dFreqText(fn, fd)})',
        '🤝 On a draw, ${who(ds)} wins (${_dFreqText(fn, fd)})'));
  }
  return parts.join('\n');
}

/// Vrai si la partie a des règles spéciales (handicap, nul, temps différents).
bool _dSpecialRules(Map<String, dynamic> d) {
  final t0 = (d['timeMin'] as num?)?.toInt();
  final t1 = (d['timeMinOpp'] as num?)?.toInt() ?? t0;
  final handicap = ((d['hSeat'] as num?)?.toInt() ?? -1) >= 0 &&
      ((d['hN'] as num?)?.toInt() ?? 0) > 0;
  final drawRule = ((d['drawSeat'] as num?)?.toInt() ?? -1) >= 0;
  return handicap || drawRule || t0 != t1;
}

/// Phrase sur le résultat de la règle du nul (null = pas de règle).
String? _dDrawNote(Map<String, dynamic> d, List<String> names, bool draw) {
  final ds = (d['drawSeat'] as num?)?.toInt() ?? -1;
  if (ds < 0 || ds > 1) return null;
  final fn = (d['drawNum'] as num?)?.toInt() ?? 1;
  final fd = (d['drawDen'] as num?)?.toInt() ?? 1;
  final f = _dFreqText(fn, fd);
  if (d['drawRolled'] == true) {
    return d['drawWon'] == true
        ? tr('🎲 Règle du nul ($f) : ${names[ds]} gagne.',
            '🎲 Draw rule ($f): ${names[ds]} wins.')
        : tr('🎲 Règle du nul ($f) : pas de chance, le nul reste un nul.',
            '🎲 Draw rule ($f): no luck, the draw stands.');
  }
  if (draw) {
    return tr('🎲 Règle du nul ($f) : tirage au sort en cours…',
        '🎲 Draw rule ($f): drawing lots…');
  }
  return null;
}

Widget _dLabel(String s) => Padding(
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

Widget _dHint(String s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(s, style: const TextStyle(color: Colors.white70)),
    );

String _dRulesText() => tr(
      'Plateau 10x10, 20 pions chacun, on joue sur les cases sombres. Les '
          'blancs commencent.\n'
          'Un pion avance d\'une case en diagonale. Il prend en avant et en '
          'arrière en sautant un pion adverse.\n'
          'La prise est obligatoire, et il faut jouer la rafle qui prend le '
          'plus de pièces.\n'
          'Un pion qui termine son coup sur la dernière rangée devient dame. '
          'La dame glisse de plusieurs cases et prend de loin.\n'
          'Les pièces prises sont retirées à la fin de la rafle, et on ne '
          'peut pas sauter deux fois la même pièce.\n'
          'Perd celui qui ne peut plus jouer (plus de pièces ou bloqué).\n'
          'Nulle : même position 3 fois, 25 coups de dame sans prise ni '
          'mouvement de pion, ou 300 coups.',
      '10x10 board, 20 pieces each, played on the dark squares. White '
          'starts.\n'
          'A man moves one square diagonally. It captures forwards and '
          'backwards by jumping an enemy piece.\n'
          'Capturing is compulsory, and you must play the sequence that '
          'captures the most pieces.\n'
          'A man that ENDS its move on the last row becomes a king. A king '
          'slides any distance and captures from afar.\n'
          'Captured pieces are removed at the end of the sequence, and the '
          'same piece cannot be jumped twice.\n'
          'You lose if you cannot move (no pieces left or blocked).\n'
          'Draw: same position 3 times, 25 king moves without a capture or '
          'a man move, or 300 moves.',
    );

void _dShowRules(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0B2FA6),
      title: Text(tr('Règles du Damier', 'Draughts rules'),
          style: const TextStyle(
              color: _dGoldSoft, fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Text(_dRulesText(), style: const TextStyle(color: Colors.white)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('Fermer', 'Close'),
              style: const TextStyle(color: _dGoldSoft)),
        ),
      ],
    ),
  );
}

/// Barre des joueurs : nom, nombre de pièces, joueur actif en surbrillance.
/// Les photos instantanées de la partie (visibles par les deux joueurs).
void _showPhotos(BuildContext context, String roomId, List<String> names) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14267A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (ctx, scroll) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _dRooms.doc(roomId).snapshots(),
        builder: (ctx, roomSnap) {
          final uids = ((roomSnap.data?.data()?['players'] as List?) ?? const [])
              .map((e) => '${(e as Map)['uid']}')
              .toList();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _dRooms.doc(roomId).collection('photos').snapshots(),
            builder: (ctx, snap) {
              final docs = (snap.data?.docs ?? []).toList()
                ..sort((a, b) {
                  final x = a.data()['createdAt'];
                  final y = b.data()['createdAt'];
                  final xm = x is Timestamp ? x.millisecondsSinceEpoch : 0;
                  final ym = y is Timestamp ? y.millisecondsSinceEpoch : 0;
                  return xm.compareTo(ym);
                });
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    tr('📷 Photos de la partie', '📷 Game photos'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('5 photos instantanées par joueur, prises à des moments aléatoires pour éviter la triche.',
                        '5 instant photos per player, taken at random moments to prevent cheating.'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (docs.isEmpty)
                    Text(tr('Aucune photo pour le moment.', 'No photos yet.'),
                        style: const TextStyle(color: Colors.white)),
                  for (final doc in docs)
                    Builder(builder: (_) {
                      final x = doc.data();
                      final i = uids.indexOf('${x['uid']}');
                      final who = (i >= 0 && i < names.length) ? names[i] : '?';
                      final t = x['createdAt'];
                      String when = '';
                      if (t is Timestamp) {
                        final d = t.toDate();
                        String two(int n) => n < 10 ? '0$n' : '$n';
                        when = '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
                      }
                      Widget img;
                      try {
                        img = Image.memory(base64Decode('${x['b64']}'),
                            fit: BoxFit.cover, gaplessPlayback: true);
                      } catch (_) {
                        img = const SizedBox(height: 80);
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(13)),
                              child: SizedBox(
                                  width: double.infinity, height: 220, child: img),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '$who · ${tr('coup', 'move')} ${x['moveN']} · $when',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _DScoreBar extends StatelessWidget {
  const _DScoreBar({
    required this.names,
    required this.counts,
    required this.cur,
    required this.over,
    this.clocks,
  });

  final List<String> names;
  final List<int> counts;
  final int cur;
  final bool over;
  final List<String>? clocks;

  Widget _side(int i) {
    final active = !over && cur == i;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(active ? 0.28 : 0.12),
          border: Border.all(
            color: active ? _dGold : Colors.white24,
            width: active ? 2.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _dSeatColor[i],
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (clocks != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  clocks![i],
                  style: TextStyle(
                    color: active ? _dGold : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            Text(
              '${counts[i]}',
              style: const TextStyle(
                color: _dGold,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _side(0),
        const SizedBox(width: 8),
        _side(1),
      ],
    );
  }
}

/// Panneau de fin de partie.
class _DResultPanel extends StatelessWidget {
  const _DResultPanel({
    required this.names,
    required this.counts,
    required this.winners,
    required this.stake,
    this.reason = '',
    this.forfeit = -1,
    this.timeout = false,
    this.jackpot = 0,
    this.extra,
    this.drawNote,
  });

  final String? drawNote;
  final List<String> names;
  final List<int> counts;
  final List<int> winners;
  final int stake;
  final String reason;
  final int forfeit;
  final bool timeout;
  final int jackpot;
  final Widget? extra;

  String get _reasonText {
    switch (reason) {
      case 'repeat':
        return tr('Même position 3 fois.', 'Same position 3 times.');
      case 'quiet':
        return tr('25 coups de dame sans prise.',
            '25 king moves without a capture.');
      case 'cap':
        return tr('Limite de 300 coups atteinte.', '300-move limit reached.');
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final draw = winners.length != 1;
    final head = draw
        ? tr('🤝 Partie nulle', '🤝 Draw')
        : tr('🏆 ${names[winners.first]} gagne !',
            '🏆 ${names[winners.first]} wins!');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.14),
        border: Border.all(color: _dGold, width: 2),
      ),
      child: Column(
        children: [
          Text(
            head,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _dGold,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (forfeit >= 0)
            Text(
              timeout
                  ? tr('${names[forfeit]} a perdu au temps.',
                      '${names[forfeit]} lost on time.')
                  : tr('${names[forfeit]} a abandonné.',
                      '${names[forfeit]} gave up.'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (_reasonText.isNotEmpty)
            Text(_reasonText,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (drawNote != null)
            Text(drawNote!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _dGold, fontSize: 13, fontWeight: FontWeight.w800)),
          Text(
            '${names[0]} ${counts[0]}  –  ${counts[1]} ${names[1]}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (stake > 0)
            Text(
              draw
                  ? tr('Égalité : mises remboursées, aucune commission.',
                      'Draw: stakes refunded, no commission.')
                  : tr(
                      'Gain : ${Wallet.format(Wallet.prize(stake * 2))} (commission ${Wallet.commissionPercent} %)',
                      'Prize: ${Wallet.format(Wallet.prize(stake * 2))} (${Wallet.commissionPercent} % commission)'),
              style: const TextStyle(color: _dGoldSoft, fontSize: 13),
            ),
          if (jackpot > 0)
            Text(
              tr('🎰 Jackpot gagné : ${Wallet.format(jackpot)}',
                  '🎰 Jackpot won: ${Wallet.format(jackpot)}'),
              style: const TextStyle(
                color: _dGold,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

// ======================================================================
// Page d'accueil du Damier
// ======================================================================

class DamierPage extends StatelessWidget {
  const DamierPage({super.key});

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
    return _DShell(
      title: tr('Damier', 'Draughts'),
      trailing: IconButton(
        tooltip: tr('Règles', 'Rules'),
        onPressed: () => _dShowRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _card(
              Icons.groups,
              tr('En présentiel', 'Face to face'),
              tr('Deux joueurs sur un téléphone', 'Two players on one phone'),
              const Color(0xFF22B14C),
              () => _go(context, (_) => const _DamierLocalSetup()),
            ),
            const SizedBox(height: 14),
            _card(
              Icons.public,
              tr('En ligne', 'Online'),
              tr('Chacun joue depuis son téléphone',
                  'Everyone plays from their own phone'),
              const Color(0xFF1E6BFF),
              () {
                if (!firebaseReady) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr('Le jeu en ligne est indisponible.',
                          'Online play is unavailable.')),
                    ),
                  );
                  return;
                }
                _go(context, (_) => const _DamierHub());
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

class _DamierLocalSetup extends StatefulWidget {
  const _DamierLocalSetup();

  @override
  State<_DamierLocalSetup> createState() => _DamierLocalSetupState();
}

class _DamierLocalSetupState extends State<_DamierLocalSetup> {
  int stake = Wallet.minStake;
  int timeMin = 5;
  int timeOpp = 5;
  int incSec = 2;
  int hSeat = -1; // joueur qui a des pions en moins (-1 = personne)
  int hN = 2;
  int drawSeat = -1; // joueur qui gagne en cas de nul (-1 = personne)
  int drawNum = 1;
  int drawDen = 1;
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
        name: _dUserName(u),
        email: u.email ?? '',
        balance: bal,
      );
    });
  }

  Future<void> _connect(int seat) async {
    final acc = await showPlayerLogin(
      context,
      colorName: seat == 0 ? tr('Blancs', 'White') : tr('Noirs', 'Black'),
      color: _dSeatColor[seat],
    );
    if (acc == null || !mounted) return;
    if (accounts.entries.any((e) => e.key != seat && e.value.uid == acc.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Ce compte joue déjà dans la partie.',
              'This account is already in the game.')),
        ),
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
          border: Border.all(color: _dSeatColor[seat], width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acc.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            Text('💰 ${Wallet.format(acc.balance)}',
                style: const TextStyle(color: _dGoldSoft, fontSize: 12)),
          ],
        ),
      );
    } else {
      field = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: _dSeatColor[seat], width: 2),
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
          CircleAvatar(radius: 14, backgroundColor: _dSeatColor[seat]),
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
          game: 'damier',
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
        builder: (_) => _DamierLocalGame(
          names: names,
          stake: firebaseReady ? stake : 0,
          localId: localId,
          uids: uids,
          timeMin: timeMin,
          timeMinOpp: timeOpp,
          incSec: incSec,
          hSeat: hSeat,
          hN: hSeat >= 0 ? hN : 0,
          drawSeat: drawSeat,
          drawNum: drawNum,
          drawDen: drawDen,
        ),
      ),
    );
    if (!mounted) return;
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      setState(() => accounts.removeWhere((k, v) => k != 0));
      if (u != null) await _loadHost(u);
    }
  }

  @override
  Widget build(BuildContext context) {
    final broke = brokePlayer;
    return _DShell(
      title: tr('Damier · présentiel', 'Draughts · face to face'),
      trailing: IconButton(
        onPressed: () => _dShowRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (firebaseReady) ...[
            const JackpotBanner(),
            _dLabel(tr('Mise de chaque joueur', "Each player's stake")),
            StakeField(
              stake: stake,
              players: 2,
              local: true,
              onChanged: (v) => setState(() => stake = v),
            ),
          ],
          _dClockPicker(
            timeMin: timeMin,
            timeOpp: timeOpp,
            incSec: incSec,
            labelMe: tr('Temps des blancs', 'White time'),
            labelOpp: tr('Temps des noirs', 'Black time'),
            onMin: (v) => setState(() => timeMin = v),
            onOpp: (v) => setState(() => timeOpp = v),
            onInc: (v) => setState(() => incSec = v),
          ),
          _dRulesPicker(
            hSeat: hSeat,
            hN: hN,
            drawSeat: drawSeat,
            drawNum: drawNum,
            drawDen: drawDen,
            labelMe: tr('Blancs', 'White'),
            labelOpp: tr('Noirs', 'Black'),
            onHSeat: (v) => setState(() => hSeat = v),
            onHN: (v) => setState(() => hN = v),
            onDrawSeat: (v) => setState(() => drawSeat = v),
            onFreq: (n, d) => setState(() {
              drawNum = n;
              drawDen = d;
            }),
          ),
          _dLabel(firebaseReady
              ? tr('Joueurs (chacun se connecte à son compte)',
                  'Players (each one signs in to their account)')
              : tr('Joueurs (les blancs commencent)',
                  'Players (white starts)')),
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
              onPressed: (!ready ||
                      starting ||
                      stake < 0 ||
                      (broke != null && stake > 0))
                  ? null
                  : _start,
              child: Text(
                starting
                    ? tr('Mise en cours...', 'Placing stakes...')
                    : (stake <= 0
                        ? tr('Lancer · partie gratuite', 'Start · free game')
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

class _DamierLocalGame extends StatefulWidget {
  const _DamierLocalGame({
    required this.names,
    this.stake = 0,
    this.localId,
    this.uids = const [],
    this.timeMin = 5,
    this.timeMinOpp = 5,
    this.incSec = 2,
    this.hSeat = -1,
    this.hN = 0,
    this.drawSeat = -1,
    this.drawNum = 1,
    this.drawDen = 1,
  });

  final List<String> names;
  final int stake;
  final String? localId;
  final List<String?> uids;
  final int timeMin;
  final int timeMinOpp;
  final int incSec;
  final int hSeat;
  final int hN;
  final int drawSeat;
  final int drawNum;
  final int drawDen;

  @override
  State<_DamierLocalGame> createState() => _DamierLocalGameState();
}

class _DamierLocalGameState extends State<_DamierLocalGame> {
  late DamierGame g = DamierGame(hSeat: widget.hSeat, hN: widget.hN);
  bool _settled = false;
  int _tries = 0;
  int jackpot = 0;
  bool _flip = false;
  int _doneMove = 0;
  late final Map<int, List<int>> _countsAt = {
    0: [g.count(0), g.count(1)],
  };
  bool _drawRolled = false;
  bool _drawWon = false;

  /// Règle du nul (présentiel) : tirage au sort sur place, une seule fois.
  void _resolveDraw() {
    if (_drawRolled || !g.over || g.winners.length != 2) return;
    if (widget.drawSeat < 0 || widget.drawSeat > 1) return;
    if (_lostBy >= 0) return;
    _drawRolled = true;
    final den = widget.drawDen < 1 ? 1 : widget.drawDen;
    _drawWon = Random().nextInt(den) < widget.drawNum;
    if (_drawWon) g.winners = [widget.drawSeat];
  }

  String? get _drawNote {
    if (widget.drawSeat < 0 || !_drawRolled) return null;
    final f = _dFreqText(widget.drawNum, widget.drawDen);
    return _drawWon
        ? tr('🎲 Règle du nul ($f) : ${widget.names[widget.drawSeat]} gagne.',
            '🎲 Draw rule ($f): ${widget.names[widget.drawSeat]} wins.')
        : tr('🎲 Règle du nul ($f) : pas de chance, le nul reste un nul.',
            '🎲 Draw rule ($f): no luck, the draw stands.');
  }

  bool get _busy => g.moveN != _doneMove;
  bool get _overShown => g.over && !_busy;

  // --- Horloges (temps par joueur + bonus par coup) -----------------------
  late final List<int> _clock = [widget.timeMin * 60000, widget.timeMinOpp * 60000];
  DateTime _turnStart = DateTime.now();
  Timer? _ticker;
  int _lostBy = -1;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tickClock());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _remain(int i) =>
      _clock[i] -
      ((i == g.cur && !g.over && !_busy && g.moveN >= 2)
          ? DateTime.now().difference(_turnStart).inMilliseconds
          : 0);

  void _tickClock() {
    if (!mounted || g.over || _busy) return;
    if (g.moveN >= 2 && _remain(g.cur) <= 0) {
      _timeUp();
      return;
    }
    setState(() {});
  }

  void _timeUp() {
    final seat = g.cur;
    setState(() {
      _clock[seat] = 0;
      g.over = true;
      g.winners = [1 - seat];
      g.lastFrom = -1;
      g.lastPath = [];
      g.lastCaps = [];
      g.moveN++;
      _doneMove = g.moveN;
      _countsAt[g.moveN] = [g.count(0), g.count(1)];
      _lostBy = seat;
      _timedOut = true;
    });
    _settle();
  }

  void _onMove(DMove m) {
    if (_busy || g.over) return;
    final seat = g.cur;
    final firstMove = g.moveN < 2; // l'horloge démarre après le 1er coup
    if (!g.play(m)) return;
    if (!firstMove) {
      final used = min(DateTime.now().difference(_turnStart).inMilliseconds,
          max(0, _clock[seat] - 1));
      _clock[seat] = max(1000, _clock[seat] - used + widget.incSec * 1000);
    }
    _turnStart = DateTime.now();
    _countsAt[g.moveN] = [g.count(0), g.count(1)];
    setState(() {});
  }

  void _settledMove(int m) {
    if (!mounted) return;
    _turnStart = DateTime.now();
    if (g.over && g.moveN == m) _resolveDraw();
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
      final res = await Wallet.settleLocalFull(
          id, ws, [g.count(0), g.count(1)]);
      final jp = (res['jackpot'] as num?)?.toInt() ?? 0;
      if (mounted && jp > 0) setState(() => jackpot = jp);
    } catch (_) {
      _settled = false;
      if (mounted && ++_tries < 4) {
        Future.delayed(const Duration(seconds: 5), _settle);
      }
    }
  }

  Future<void> _giveUp() async {
    final seat = g.cur;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Abandonner ?', 'Give up?')),
        content: Text(tr('${widget.names[seat]} perd la partie.',
            '${widget.names[seat]} loses the game.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Non', 'No')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Abandonner', 'Give up')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || g.over) return;
    setState(() {
      g.over = true;
      g.winners = [1 - seat];
      g.lastFrom = -1;
      g.lastPath = [];
      g.lastCaps = [];
      g.moveN++;
      _doneMove = g.moveN;
      _countsAt[g.moveN] = [g.count(0), g.count(1)];
    });
    _settle();
  }

  String get _statusText {
    final mustCapture = g.legal.isNotEmpty && g.legal.first.caps.isNotEmpty;
    final who = widget.names[g.cur];
    if (mustCapture) {
      return tr('$who : prise obligatoire (${g.legal.first.caps.length})',
          '$who: capture is compulsory (${g.legal.first.caps.length})');
    }
    return tr('À $who de jouer', '$who to move');
  }

  @override
  Widget build(BuildContext context) {
    final shown = _countsAt[_doneMove] ?? [g.count(0), g.count(1)];
    return PopScope(
      canPop: widget.stake == 0 || g.over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('Termine la partie pour régler les mises.',
                  'Finish the game to settle the stakes.')),
            ),
          );
        }
      },
      child: _DShell(
        title: tr('Damier', 'Draughts'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: tr('Retourner le plateau', 'Flip the board'),
              onPressed: () => setState(() => _flip = !_flip),
              icon: const Icon(Icons.flip, color: Colors.white),
            ),
            IconButton(
              tooltip: tr('Règles', 'Rules'),
              onPressed: () => _dShowRules(context),
              icon: const Icon(Icons.help_outline, color: Colors.white),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _DScoreBar(
                    names: widget.names,
                    counts: shown,
                    cur: g.cur,
                    over: _overShown,
                    clocks: [_dFmtClock(_remain(0)), _dFmtClock(_remain(1))],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DamierBoardView(
                      board: g.board,
                      flip: _flip,
                      legal: (_busy || g.over) ? const <DMove>[] : g.legal,
                      onMove: _onMove,
                      moveN: g.moveN,
                      lastFrom: g.lastFrom,
                      lastPath: g.lastPath,
                      lastCaps: g.lastCaps,
                      onSettled: _settledMove,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _overShown || _busy ? ' ' : _statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _dGoldSoft,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!g.over)
                        TextButton(
                          onPressed: _giveUp,
                          child: Text(
                            tr('Abandonner', 'Give up'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
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
                        const BoxConstraints(maxWidth: 440, maxHeight: 340),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: _DResultPanel(
                        names: widget.names,
                        counts: [g.count(0), g.count(1)],
                        winners: g.winners,
                        stake: widget.stake,
                        reason: g.reason,
                        forfeit: _lostBy,
                        timeout: _timedOut,
                        drawNote: _drawNote,
                        jackpot: jackpot,
                        extra: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22B14C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(tr('Terminer', 'Finish')),
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

class _DamierHub extends StatefulWidget {
  const _DamierHub();

  @override
  State<_DamierHub> createState() => _DamierHubState();
}

class _DamierHubState extends State<_DamierHub> {
  int stake = Wallet.minStake;
  int timeMin = 5; // mon temps de réflexion (minutes)
  int timeOpp = 5; // temps de l'adversaire (minutes)
  int incSec = 2; // secondes ajoutées après chaque coup
  int hSeat = -1; // qui joue avec des pions en moins (-1 personne, 0 moi, 1 adversaire)
  int hN = 2; // nombre de pions en moins
  int drawSeat = -1; // qui gagne en cas de nul (-1 personne)
  int drawNum = 1; // fréquence du nul : drawNum / drawDen
  int drawDen = 1;
  bool privateRoom = false;
  bool busy = false;
  String? error;
  bool showOpen = false;
  bool showLive = false;
  final TextEditingController codeCtrl = TextEditingController();

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> openStream =
      _dRooms.where('status', isEqualTo: 'waiting').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> liveStream =
      _dRooms.where('status', isEqualTo: 'playing').limit(30).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> mineStream =
      _dRooms.where('uids', arrayContains: uid).snapshots();

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _open(String id, {bool spectate = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DamierRoom(roomId: id, spectate: spectate),
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
      final ref = _dRooms.doc();
      final init = DamierGame(hSeat: hSeat, hN: hSeat >= 0 ? hN : 0);
      await ref.set({
        'hostUid': user.uid,
        'hostName': _dUserName(user),
        'maxPlayers': 2,
        'private': privateRoom,
        'stake': stake,
        'paid': <String>[],
        'pot': 0,
        'code': _dNewCode(),
        'status': 'waiting',
        'players': [
          {'uid': user.uid, 'name': _dUserName(user)},
        ],
        'uids': [user.uid],
        'miss': [0, 0],
        'timeMin': timeMin,
        'timeMinOpp': timeOpp,
        'incSec': incSec,
        'clockMs': [timeMin * 60000, timeOpp * 60000],
        'hSeat': hSeat,
        'hN': hSeat >= 0 ? hN : 0,
        'drawSeat': drawSeat,
        'drawNum': drawNum,
        'drawDen': drawDen,
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
        setState(() => error = tr(
            'Impossible de créer la partie. Vérifie les règles Firestore '
                '(collection « damier »).',
            'Could not create the game. Check the Firestore rules '
                '("damier" collection).'));
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
      final ref = _dRooms.doc(id);
      final pre = await ref.get();
      final need = (pre.data()?['stake'] as num?)?.toInt() ?? 0;
      final pd = pre.data();
      if (pd != null && _dSpecialRules(pd) && !_dPlayersOf(pd).any((p) => p['uid'] == user.uid)) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Règles de cette partie', 'Rules of this game')),
            content: Text(_dRulesLine(pd)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr('Refuser', 'Decline')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr('Accepter et rejoindre', 'Accept and join')),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
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
        if (d == null) return tr("Cette partie n'existe plus.", 'This game no longer exists.');
        final players = _dPlayersOf(d);
        if (players.any((p) => p['uid'] == user.uid)) return null;
        if (d['status'] != 'waiting' || players.length >= 2) {
          return tr('Cette partie est déjà complète.', 'This game is already full.');
        }
        players.add({'uid': user.uid, 'name': _dUserName(user)});
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
      if (mounted) {
        setState(() => error = tr('Impossible de rejoindre la partie.',
            'Could not join the game.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _joinByCode() async {
    final code = codeCtrl.text.trim().toUpperCase();
    if (busy) return;
    if (code.length != 6) {
      setState(() => error = tr('Entre le code à 6 caractères.',
          'Enter the 6-character code.'));
      return;
    }
    String? id;
    try {
      final q = await _dRooms.where('code', isEqualTo: code).limit(1).get();
      if (q.docs.isEmpty) {
        setState(() => error =
            tr('Aucune partie avec ce code.', 'No game with this code.'));
      } else {
        id = q.docs.first.id;
      }
    } catch (_) {
      setState(() => error = tr('Impossible de chercher la partie.',
          'Could not look up the game.'));
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
            _dLabel(tr('Mes parties', 'My games')),
            for (final doc in docs)
              Builder(builder: (context) {
                final d = doc.data();
                final waiting = d['status'] == 'waiting';
                final n = _dPlayersOf(d).length;
                return _tile(
                  tr("Partie de ${d['hostName']}", "${d['hostName']}'s game"),
                  waiting
                      ? tr('En attente ($n/2 joueurs)${_dStakeText(d)}',
                          'Waiting ($n/2 players)${_dStakeText(d)}')
                      : tr('En cours${_dStakeText(d)}',
                          'In progress${_dStakeText(d)}'),
                  waiting ? tr('Ouvrir', 'Open') : tr('Reprendre', 'Resume'),
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
          return _dHint(tr('Impossible de charger les parties.',
              'Could not load the games.'));
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
          return _dHint(tr(
              'Aucune partie ouverte pour le moment. Crée la tienne !',
              'No open games right now. Create your own!'));
        }
        return Column(
          children: [
            for (final doc in docs)
              _tile(
                tr("Partie de ${doc.data()['hostName']}",
                    "${doc.data()['hostName']}'s game"),
                '${_dPlayersOf(doc.data()).length}/2${_dStakeText(doc.data())}'
                '${_dSpecialRules(doc.data()) ? '\n${_dRulesLine(doc.data()).replaceAll('\n', ' · ')}' : ''}',
                tr('Rejoindre', 'Join'),
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
          return _dHint(tr('Impossible de charger les parties en cours.',
              'Could not load the games in progress.'));
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
          return _dHint(tr('Aucune partie en cours à regarder pour le moment.',
              'No games in progress to watch right now.'));
        }
        return Column(
          children: [
            for (final doc in docs)
              _tile(
                _dPlayersOf(doc.data()).map((p) => '${p['name']}').join(' vs '),
                _dStakeText(doc.data()).replaceFirst(' • ', ''),
                tr('Regarder', 'Watch'),
                () => _open(doc.id, spectate: true),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DShell(
      title: tr('Damier · en ligne', 'Draughts · online'),
      trailing: IconButton(
        onPressed: () => _dShowRules(context),
        icon: const Icon(Icons.help_outline, color: Colors.white),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const JackpotBanner(),
          _dLabel(tr('Créer une partie', 'Create a game')),
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
          _dClockPicker(
            timeMin: timeMin,
            timeOpp: timeOpp,
            incSec: incSec,
            onMin: (v) => setState(() => timeMin = v),
            onOpp: (v) => setState(() => timeOpp = v),
            onInc: (v) => setState(() => incSec = v),
          ),
          _dRulesPicker(
            hSeat: hSeat,
            hN: hN,
            drawSeat: drawSeat,
            drawNum: drawNum,
            drawDen: drawDen,
            onHSeat: (v) => setState(() => hSeat = v),
            onHN: (v) => setState(() => hN = v),
            onDrawSeat: (v) => setState(() => drawSeat = v),
            onFreq: (n, d) => setState(() {
              drawNum = n;
              drawDen = d;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: _dGold,
            title: Text(tr('Partie privée', 'Private game'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text(
              tr('Invisible dans la liste : on la rejoint avec un code',
                  'Hidden from the list: join with a code'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
              child: Text(busy
                  ? tr('Patiente...', 'Please wait...')
                  : tr('Créer la partie', 'Create the game')),
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
          _dLabel(tr('Rejoindre avec un code', 'Join with a code')),
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
                  child: Text(tr('Rejoindre', 'Join')),
                ),
              ),
            ],
          ),
          _mine(),
          _listButton(tr('♟️ Parties ouvertes', '♟️ Open games'), showOpen,
              () => setState(() => showOpen = !showOpen)),
          if (showOpen) _openList(),
          _listButton(tr('👀 Parties en cours', '👀 Games in progress'),
              showLive, () => setState(() => showLive = !showLive)),
          if (showLive) _liveList(),
        ],
      ),
    );
  }
}

// ======================================================================
// En ligne : salle d'attente puis partie
// ======================================================================

/// Salle de jeu (pour les liens partagés).
Widget damierRoomPage(String id) => _DamierRoom(roomId: id);

/// Revoir une partie de Damier en ligne (lecture seule) : tableau de bord admin.
class DamierSpectator extends StatelessWidget {
  const DamierSpectator({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) =>
      _DamierRoom(roomId: roomId, spectate: true);
}

class _DamierRoom extends StatefulWidget {
  const _DamierRoom({required this.roomId, this.spectate = false});

  final String roomId;
  final bool spectate;

  @override
  State<_DamierRoom> createState() => _DamierRoomState();
}

class _DamierRoomState extends State<_DamierRoom> {
  bool _settled = false;
  int _tries = 0;
  Timer? _timer;
  int _seenMove = -1;
  DateTime _stamp = DateTime.now();
  int _left = kDamierTurnSecs;
  bool _autoBusy = false;
  Map<String, dynamic>? _last;
  int _jackpotShown = 0;

  // --- Photos instantanées (anti-triche) ---------------------------------
  CameraController? _cam;
  bool _camTried = false;
  final List<int> _plan = () {
    final r = Random.secure();
    final set = <int>{};
    while (set.length < 5) {
      set.add(1 + r.nextInt(14)); // 5 de mes tours, tirés au hasard
    }
    return set.toList();
  }();
  int _myTurns = 0;
  int _turnCounted = -1;
  int _shots = 0;

  Future<void> _initCam(String uid) async {
    if (_camTried) return;
    _camTried = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('no camera');
      final cam = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.low, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _cam = c;
    } catch (_) {
      try {
        await _ref.update({
          'camOff': FieldValue.arrayUnion([uid]),
        });
      } catch (_) {}
    }
  }

  Future<void> _snap(String uid, int moveN) async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _shots >= 5) return;
    try {
      final f = await c.takePicture();
      final bytes = await f.readAsBytes();
      final b64 = base64Encode(bytes);
      if (b64.length > 140000) return;
      final n = _shots;
      _shots++;
      await _ref.collection('photos').doc('${uid}_$n').set({
        'uid': uid,
        'b64': b64,
        'moveN': moveN,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _stopCam() {
    final c = _cam;
    _cam = null;
    c?.dispose();
  }

  List<int>? _clockOf(Map<String, dynamic> d) {
    final c = d['clockMs'];
    if (c is List && c.length == 2) {
      return [(c[0] as num).toInt(), (c[1] as num).toInt()];
    }
    return null;
  }

  String _fmtClock(int ms) {
    final s = (max(0, ms) / 1000).ceil();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r < 10 ? '0' : ''}$r';
  }
  int _doneMove = -1;
  final Map<int, List<int>> _countsAt = {};

  void _settledMove(int m) {
    if (!mounted) return;
    setState(() => _doneMove = m);
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      _dRooms.doc(widget.roomId);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopCam();
    super.dispose();
  }

  void _tick() {
    final d = _last;
    if (!mounted || d == null) return;
    if (d['status'] != 'playing' || d['over'] == true) return;
    final clock = _clockOf(d);
    if (clock != null) {
      final g0 = DamierGame.fromDoc(d);
      // L'horloge d'un joueur démarre après son 1er coup. Avant, il dispose
      // seulement de 60 s (pour qu'une partie ne reste pas bloquée).
      final first = g0.moveN < 2;
      final elapsed = DateTime.now().difference(_stamp).inMilliseconds;
      final rem = first ? clock[g0.cur] : clock[g0.cur] - elapsed;
      setState(() => _left = max(0, (rem / 1000).ceil()));
      final pl = _dPlayersOf(d);
      final meSeat = pl.indexWhere(
          (p) => p['uid'] == FirebaseAuth.instance.currentUser?.uid);
      final expired = first ? elapsed >= kDamierTurnSecs * 1000 : rem <= 0;
      if (expired && meSeat >= 0 && !_autoBusy) {
        _autoBusy = true;
        _flag(g0.cur, g0.moveN).whenComplete(() {
          _autoBusy = false;
        });
      }
      return;
    }
    final left = kDamierTurnSecs - DateTime.now().difference(_stamp).inSeconds;
    setState(() => _left = max(0, left));
    final players = _dPlayersOf(d);
    final me = players.indexWhere(
        (p) => p['uid'] == FirebaseAuth.instance.currentUser?.uid);
    // Tous les joueurs assis peuvent jouer à la place d'un joueur absent.
    if (left <= -1 && me >= 0 && !_autoBusy) {
      _autoBusy = true;
      final g = DamierGame.fromDoc(d);
      _play(g.cur, null, g.moveN, auto: true).whenComplete(() {
        _autoBusy = false;
      });
    }
  }

  Widget _info(String text, {bool loading = false}) {
    return _DShell(
      title: tr('Damier', 'Draughts'),
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
  Future<void> _play(int seat, DMove? move, int expectMove,
      {bool auto = false, int elapsedMs = 0}) async {
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null) return;
        if (d['over'] == true || d['status'] != 'playing') return;
        final g = DamierGame.fromDoc(d);
        if (g.cur != seat || g.moveN != expectMove) return;
        final legal = g.legal;
        if (legal.isEmpty) return;
        DMove? chosen;
        if (move != null) {
          for (final m in legal) {
            if (m.sameAs(move)) {
              chosen = m;
              break;
            }
          }
        }
        if (chosen == null) {
          if (!auto) return;
          chosen = legal[Random().nextInt(legal.length)];
        }
        final miss = _dIntsOf(d['miss'], [0, 0]);
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
            'lastFrom': -1,
            'lastPath': <int>[],
            'lastCaps': <int>[],
            'moveN': g.moveN + 1,
          });
          return;
        }
        final firstMove = g.moveN < 2;
        g.play(chosen);
        final clock = _clockOf(d);
        if (clock != null && !firstMove) {
          final inc = ((d['incSec'] as num?)?.toInt() ?? 0) * 1000;
          final used = min(max(0, elapsedMs), max(0, clock[seat] - 1));
          clock[seat] = max(1000, clock[seat] - used + inc);
        }
        tx.update(_ref, {
          ...g.toDoc(),
          'miss': miss,
          if (clock != null) 'clockMs': clock,
          if (g.over) 'status': 'finished',
        });
      });
    } catch (_) {}
  }

  /// Le temps d'un joueur est écoulé : il perd la partie.
  Future<void> _flag(int seat, int expectMove) async {
    try {
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(_ref);
        final d = snap.data();
        if (d == null) return;
        if (d['over'] == true || d['status'] != 'playing') return;
        final clock = _clockOf(d);
        if (clock == null) return;
        final g = DamierGame.fromDoc(d);
        if (g.cur != seat || g.moveN != expectMove) return;
        clock[seat] = 0;
        tx.update(_ref, {
          'over': true,
          'status': 'finished',
          'forfeit': seat,
          'timeout': true,
          'winners': [1 - seat],
          'clockMs': clock,
          'lastFrom': -1,
          'lastPath': <int>[],
          'lastCaps': <int>[],
          'moveN': g.moveN + 1,
        });
      });
    } catch (_) {}
  }

  Future<void> _forfeit(int seat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Abandonner ?', 'Give up?')),
        content: Text(tr('Tu perds la partie et ta mise.',
            'You lose the game and your stake.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Non', 'No')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Abandonner', 'Give up')),
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
          'lastFrom': -1,
          'lastPath': <int>[],
          'lastCaps': <int>[],
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

    return _DShell(
      title: tr("Salle d'attente", 'Waiting room'),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr('${players.length}/2 joueurs', '${players.length}/2 players'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Le créateur lance la partie quand les deux joueurs ont payé leur mise. Il joue les blancs et commence.',
                'The host starts the game once both players have paid their stake. The host plays white and moves first.'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                : tr('Partie gratuite', 'Free game'),
            style: const TextStyle(
              color: _dGoldSoft,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_dRulesLine(d, names: [
            for (int i = 0; i < 2; i++)
              i < players.length ? '${players[i]['name']}' : '?',
          ]).isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.black26,
                border: Border.all(color: _dGold, width: 1.2),
              ),
              child: Text(
                _dRulesLine(d, names: [
                  for (int i = 0; i < 2; i++)
                    i < players.length ? '${players[i]['name']}' : '?',
                ]),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, height: 1.5),
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
                      : tr('Valider ma participation', 'Confirm my participation'),
                ),
              ),
            ),
          WaitingBell(collection: 'damier', gameId: widget.roomId),
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
              border: Border.all(color: _dGold, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${d['code']}',
                    style: const TextStyle(
                      color: _dGold,
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
                      SnackBar(content: Text(tr('Code copié', 'Code copied'))),
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
                border: Border.all(color: _dSeatColor[i], width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: _dSeatColor[i]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i < players.length
                          ? '${players[i]['name']}'
                              '${paid.contains(players[i]['uid']) ? ' ✅' : ''}'
                          : tr("En attente d'un joueur...",
                              'Waiting for a player...'),
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
              child: Text(isHost
                  ? tr('Annuler la partie', 'Cancel the game')
                  : tr('Quitter la partie', 'Leave the game')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _info(tr('Tu dois être connecté.', 'You must be signed in.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _info(tr('Erreur de connexion à la partie.',
              'Connection error.'));
        }
        if (!snap.hasData) return _info('', loading: true);
        final d = snap.data!.data();
        if (d == null) {
          return _info(tr("Cette partie n'existe plus.",
              'This game no longer exists.'));
        }
        _last = d;

        final players = _dPlayersOf(d);
        final seat = players.indexWhere((p) => p['uid'] == user.uid);
        if (seat < 0 && !widget.spectate) {
          return _info(tr('Tu ne fais pas partie de cette partie.',
              'You are not part of this game.'));
        }
        if (seat < 0 && d['status'] == 'waiting') {
          return _info(tr("Cette partie n'a pas encore commencé.",
              "This game hasn't started yet."));
        }
        if (d['status'] == 'waiting') return _waiting(d, players, user.uid);

        final g = DamierGame.fromDoc(d);
        if (g.moveN != _seenMove) {
          _seenMove = g.moveN;
          _stamp = DateTime.now();
          _left = kDamierTurnSecs;
        }
        // Coup dont l'animation est terminée (au premier affichage : le coup
        // en cours, sans animation).
        if (_doneMove < 0) _doneMove = g.moveN;
        _countsAt[g.moveN] = [g.count(0), g.count(1)];
        final busy = g.moveN != _doneMove;
        final shown = _countsAt[_doneMove] ?? [g.count(0), g.count(1)];

        final over = d['over'] == true;
        final overShown = over && !busy;
        final clock = _clockOf(d);
        int remain(int i) =>
            (clock?[i] ?? 0) -
            ((i == g.cur && !over && !busy && g.moveN >= 2)
                ? DateTime.now().difference(_stamp).inMilliseconds
                : 0);
        if (seat >= 0 && !widget.spectate) {
          if (over) {
            if (_cam != null) _stopCam();
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _initCam(user.uid);
            });
            if (g.cur == seat && g.moveN != _turnCounted) {
              _turnCounted = g.moveN;
              _myTurns++;
              if (_plan.contains(_myTurns)) {
                final wait = 1 + Random().nextInt(6);
                final mv = g.moveN;
                Future.delayed(Duration(seconds: wait), () {
                  if (mounted) _snap(user.uid, mv);
                });
              }
            }
          }
        }
        final camOff = ((d['camOff'] as List?) ?? const []).map((e) => '$e').toList();
        final camWarn = <String>[
          for (int i = 0; i < players.length && i < 2; i++)
            if (camOff.contains(players[i]['uid'])) '${players[i]['name']}',
        ];
        if (overShown && seat >= 0) _settle();
        final stake = (d['stake'] as num?)?.toInt() ?? 0;
        final names = [
          for (int i = 0; i < 2; i++)
            i < players.length ? '${players[i]['name']}' : '?',
        ];
        final myTurn = seat >= 0 && g.cur == seat && !over && !busy;
        final forfeit = (d['forfeit'] as num?)?.toInt() ?? -1;
        final jp = (d['jackpot'] as num?)?.toInt() ?? 0;
        if (jp > 0) _jackpotShown = jp;

        final legal = (myTurn) ? g.legal : const <DMove>[];
        final mustCapture =
            myTurn && legal.isNotEmpty && legal.first.caps.isNotEmpty;

        final tl = clock != null
            ? (g.moveN < 2
                ? tr('l\'horloge démarre après le 1er coup',
                    'clock starts after the 1st move')
                : _fmtClock(remain(g.cur)))
            : '$_left s';
        String status;
        if (over || busy) {
          status = ' ';
        } else if (myTurn) {
          status = mustCapture
              ? tr('À toi · prise obligatoire · $tl',
                  'Your move · capture compulsory · $tl')
              : tr('À toi de jouer · $tl', 'Your move · $tl');
        } else {
          status = tr('${names[g.cur]} réfléchit · $tl',
              '${names[g.cur]} is thinking · $tl');
        }

        return PopScope(
          canPop: stake == 0 || over || seat < 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tr(
                      'Termine la partie (ou abandonne) pour régler la mise.',
                      'Finish the game (or give up) to settle the stake.')),
                ),
              );
            }
          },
          child: _DShell(
            title: tr('Damier', 'Draughts'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr('Règles', 'Rules'),
                  onPressed: () => _dShowRules(context),
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
                RoomInfoButton(collection: 'damier', gameId: widget.roomId),
                if (seat >= 0)
                  IconButton(
                    tooltip: tr('Photos de la partie', 'Game photos'),
                    onPressed: () => _showPhotos(context, widget.roomId, names),
                    icon: const Icon(Icons.photo_camera, color: Colors.white),
                  ),
                if (seat >= 0) ...[
                  const SizedBox(width: 6),
                  GameChat(
                    collection: 'damier',
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
                      child: _DScoreBar(
                        names: names,
                        counts: shown,
                        cur: g.cur,
                        over: overShown,
                        clocks: clock == null
                            ? null
                            : [_fmtClock(remain(0)), _fmtClock(remain(1))],
                      ),
                    ),
                    if (camWarn.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                        child: Text(
                          tr('📷 Caméra non autorisée : ${camWarn.join(', ')}',
                              '📷 Camera not allowed: ${camWarn.join(', ')}'),
                          style: const TextStyle(
                              color: Color(0xFFFFB74D),
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: DamierBoardView(
                          board: g.board,
                          flip: seat == 1,
                          legal: legal,
                          onMove: (m) => _play(seat, m, g.moveN,
                              elapsedMs: DateTime.now().difference(_stamp).inMilliseconds),
                          moveN: g.moveN,
                          lastFrom: g.lastFrom,
                          lastPath: g.lastPath,
                          lastCaps: g.lastCaps,
                          onSettled: _settledMove,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: myTurn ? _dGold : _dGoldSoft,
                                fontSize: 15,
                                fontWeight:
                                    myTurn ? FontWeight.w900 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!over && seat >= 0)
                            TextButton(
                              onPressed: () => _forfeit(seat),
                              child: Text(
                                tr('Abandonner', 'Give up'),
                                style: const TextStyle(color: Colors.white70),
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
                        constraints: const BoxConstraints(
                            maxWidth: 440, maxHeight: 340),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: _DResultPanel(
                            names: names,
                            counts: [g.count(0), g.count(1)],
                            winners: g.winners,
                            stake: stake,
                            reason: g.reason,
                            forfeit: forfeit,
                            timeout: d['timeout'] == true,
                            drawNote: _dDrawNote(d, names, g.winners.length != 1),
                            jackpot: _jackpotShown,
                            extra: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22B14C),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(tr('Terminer', 'Finish')),
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
