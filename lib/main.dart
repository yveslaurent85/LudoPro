import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const LudoProApp());
}

/// Éclaircit (amount > 0) ou assombrit (amount < 0) une couleur.
Color shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness + amount).clamp(0.0, 1.0).toDouble();
  return hsl.withLightness(lightness).toColor();
}

class LudoProApp extends StatelessWidget {
  const LudoProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF061A66),
      ),
      home: const LudoGame(),
    );
  }
}

class Player {
  final String display; // ex : Rouge
  final Color color;
  final Color lightColor;
  final int start;
  final IconData avatar;
  final List<int> pawns = [-1, -1, -1, -1];

  Player({
    required this.display,
    required this.color,
    required this.lightColor,
    required this.start,
    required this.avatar,
  });

  int get finished => pawns.where((p) => p == 56).length;
}

class _PawnEntry {
  final int p;
  final int i;
  final List<double> center;
  _PawnEntry(this.p, this.i, this.center);
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key});

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame>
    with SingleTickerProviderStateMixin {
  // Cases étoiles (8 cases après chaque départ) et cases sûres (départs + étoiles)
  static const Set<int> safeStars = {8, 21, 34, 47};
  static const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  final Random random = Random();
  late final AnimationController _pulse;

  // Ordre des tours (sens horaire) : Rouge, Vert, Bleu, Jaune
  late final List<Player> players = [
    Player(
      display: 'Rouge',
      color: const Color(0xFFE5262B),
      lightColor: const Color(0xFFFFE3E5),
      start: 0,
      avatar: Icons.person,
    ),
    Player(
      display: 'Vert',
      color: const Color(0xFF22B14C),
      lightColor: const Color(0xFFDDF8E6),
      start: 13,
      avatar: Icons.face,
    ),
    Player(
      display: 'Bleu',
      color: const Color(0xFF1E6BFF),
      lightColor: const Color(0xFFDFEAFF),
      start: 26,
      avatar: Icons.face_3,
    ),
    Player(
      display: 'Jaune',
      color: const Color(0xFFFFC21A),
      lightColor: const Color(0xFFFFF3CC),
      start: 39,
      avatar: Icons.person_outline,
    ),
  ];

  int currentPlayer = 0;
  int dice = 1;
  bool hasRolled = false;
  bool isRolling = false;
  bool isMoving = false;
  bool gameOver = false;
  bool soundOn = true;
  double diceTurns = 0;
  int _token = 0; // sert à annuler les animations en attente
  String message = 'Lance le dé pour commencer !';

  final List<List<int>> track = const [
    [6, 1], [6, 2], [6, 3], [6, 4], [6, 5],
    [5, 6], [4, 6], [3, 6], [2, 6], [1, 6],
    [0, 6], [0, 7], [0, 8],
    [1, 8], [2, 8], [3, 8], [4, 8], [5, 8],
    [6, 9], [6, 10], [6, 11], [6, 12], [6, 13],
    [6, 14], [7, 14], [8, 14],
    [8, 13], [8, 12], [8, 11], [8, 10], [8, 9],
    [9, 8], [10, 8], [11, 8], [12, 8], [13, 8],
    [14, 8], [14, 7], [14, 6],
    [13, 6], [12, 6], [11, 6], [10, 6], [9, 6],
    [8, 5], [8, 4], [8, 3], [8, 2], [8, 1],
    [8, 0], [7, 0], [6, 0],
  ];

  List<List<int>> homeLane(int player) {
    switch (player) {
      case 0:
        return const [
          [7, 1], [7, 2], [7, 3], [7, 4], [7, 5],
        ];
      case 1:
        return const [
          [1, 7], [2, 7], [3, 7], [4, 7], [5, 7],
        ];
      case 2:
        return const [
          [7, 13], [7, 12], [7, 11], [7, 10], [7, 9],
        ];
      default:
        return const [
          [13, 7], [12, 7], [11, 7], [10, 7], [9, 7],
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void click() {
    if (soundOn) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  // ---------------------------------------------------------------------
  // Règles du jeu
  // ---------------------------------------------------------------------

  bool canPawnMoveWith(int position, int value) {
    if (position == -1) return value == 6;
    return position + value <= 56;
  }

  bool canPawnMove(int position) => canPawnMoveWith(position, dice);

  Future<void> rollDice() async {
    if (hasRolled || gameOver || isRolling || isMoving) return;

    final newDice = random.nextInt(6) + 1;
    final player = players[currentPlayer];
    final rollToken = ++_token;

    setState(() {
      isRolling = true;
      message = 'Le dé roule...';
    });

    for (int i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted || rollToken != _token) return;
      click();
      setState(() {
        dice = random.nextInt(6) + 1;
        diceTurns += 0.25;
      });
    }

    final canMove = player.pawns.any((p) => canPawnMoveWith(p, newDice));

    setState(() {
      dice = newDice;
      isRolling = false;
      hasRolled = true;

      if (!canMove) {
        message = '$dice ! Aucun déplacement possible.';
      } else if (dice == 6) {
        message = 'Un 6 ! Sors un pion ou avance.';
      } else {
        message = 'Touche un pion pour le déplacer.';
      }
    });

    // Aucun pion ne peut bouger : on passe au joueur suivant
    if (!canMove) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || rollToken != _token || gameOver) return;
      nextTurn();
    }
  }

  void _advanceTurn() {
    currentPlayer = (currentPlayer + 1) % players.length;
    hasRolled = false;
    dice = 1;
    message = 'Lance le dé !';
  }

  void nextTurn() => setState(_advanceTurn);

  Future<void> movePawn(int playerIndex, int pawnIndex) async {
    if (!hasRolled ||
        gameOver ||
        isRolling ||
        isMoving ||
        playerIndex != currentPlayer) {
      return;
    }

    final player = players[playerIndex];
    final oldPosition = player.pawns[pawnIndex];

    if (oldPosition == 56) return;

    if (oldPosition == -1 && dice != 6) {
      setState(() {
        message = 'Il faut un 6 pour sortir ce pion.';
      });
      return;
    }

    if (oldPosition >= 0 && oldPosition + dice > 56) {
      setState(() {
        message = 'Ce pion ne peut pas finir avec ce lancer.';
      });
      return;
    }

    final token = _token;
    setState(() {
      isMoving = true;
    });

    if (oldPosition == -1) {
      click();
      setState(() {
        player.pawns[pawnIndex] = 0;
      });
      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted || token != _token) return;
    } else {
      // Le pion avance case par case
      for (int s = 1; s <= dice; s++) {
        click();
        setState(() {
          player.pawns[pawnIndex] = oldPosition + s;
        });
        await Future.delayed(const Duration(milliseconds: 170));
        if (!mounted || token != _token) return;
      }
    }

    final newPosition = player.pawns[pawnIndex];
    bool captured = false;

    // Capture possible uniquement sur le circuit commun (0..50), hors cases sûres
    if (newPosition < 51) {
      final absolutePosition = (player.start + newPosition) % 52;

      if (!safeCells.contains(absolutePosition)) {
        for (int p = 0; p < players.length; p++) {
          if (p == playerIndex) continue;

          for (int i = 0; i < players[p].pawns.length; i++) {
            final opponentPosition = players[p].pawns[i];

            if (opponentPosition >= 0 &&
                opponentPosition < 51 &&
                (players[p].start + opponentPosition) % 52 ==
                    absolutePosition) {
              players[p].pawns[i] = -1;
              captured = true;
            }
          }
        }
      }
    }

    setState(() {
      isMoving = false;

      if (player.pawns.every((p) => p == 56)) {
        gameOver = true;
        message = '🏆 Joueur ${player.display} remporte la partie !';
      } else if (dice == 6 || captured || newPosition == 56) {
        hasRolled = false;
        dice = 1;
        message = captured
            ? 'Capture ! Tu rejoues.'
            : newPosition == 56
                ? 'Un pion est arrivé ! Tu rejoues.'
                : 'Un 6 ! Tu rejoues.';
      } else {
        _advanceTurn();
      }
    });
  }

  void restartGame() {
    _token++; // annule les animations en attente
    setState(() {
      for (final player in players) {
        player.pawns.fillRange(0, 4, -1);
      }
      currentPlayer = 0;
      dice = 1;
      hasRolled = false;
      isRolling = false;
      isMoving = false;
      gameOver = false;
      message = 'Nouvelle partie ! Lance le dé.';
    });
  }

  // ---------------------------------------------------------------------
  // Positions des pions (en unités de cases)
  // ---------------------------------------------------------------------

  List<double> homeCenter(int p, int i) {
    final rowStart = p < 2 ? 0 : 9;
    final colStart = (p == 0 || p == 3) ? 0 : 9;
    final r = i < 2 ? 1.75 : 4.25;
    final c = i.isEven ? 1.75 : 4.25;
    return [rowStart + r, colStart + c];
  }

  List<double>? pawnCenter(int p, int i) {
    final position = players[p].pawns[i];
    if (position == 56) return null;
    if (position == -1) return homeCenter(p, i);

    final cell = position >= 51
        ? homeLane(p)[position - 51]
        : track[(players[p].start + position) % 52];
    return [cell[0] + 0.5, cell[1] + 0.5];
  }

  // Zone de toucher élargie : on joue le pion le plus proche du doigt
  void onBoardTap(Offset pos, double c) {
    if (!hasRolled || isRolling || isMoving || gameOver) return;

    final tapRow = pos.dy / c;
    final tapCol = pos.dx / c;
    final player = players[currentPlayer];

    int? best;
    double bestDist = 1.8; // rayon en nombre de cases
    int? nearest;
    double nearestDist = 1.2;

    for (int i = 0; i < 4; i++) {
      final center = pawnCenter(currentPlayer, i);
      if (center == null) continue;

      final dr = center[0] - 0.2 - tapRow; // le pion est dessiné un peu plus haut
      final dc = center[1] - tapCol;
      final dist = sqrt(dr * dr + dc * dc);

      if (canPawnMove(player.pawns[i]) && dist < bestDist) {
        bestDist = dist;
        best = i;
      }
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = i;
      }
    }

    if (best != null) {
      movePawn(currentPlayer, best);
    } else if (nearest != null) {
      movePawn(currentPlayer, nearest); // affiche le message d'explication
    }
  }

  // ---------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------

  List<Widget> buildPawns(double c) {
    final entries = <_PawnEntry>[];
    for (int p = 0; p < players.length; p++) {
      for (int i = 0; i < 4; i++) {
        final center = pawnCenter(p, i);
        if (center != null) entries.add(_PawnEntry(p, i, center));
      }
    }

    final groups = <String, List<_PawnEntry>>{};
    for (final e in entries) {
      groups
          .putIfAbsent('${e.center[0]}_${e.center[1]}', () => <_PawnEntry>[])
          .add(e);
    }

    // Les pions du bas sont dessinés par-dessus ceux du haut
    entries.sort((a, b) => a.center[0].compareTo(b.center[0]));

    return entries.map((e) {
      final group = groups['${e.center[0]}_${e.center[1]}']!;
      final n = group.length;
      final k = group.indexOf(e);
      final position = players[e.p].pawns[e.i];
      final atHome = position == -1;
      final stacked = n > 1 && !atHome;

      final w = (atHome ? c * 1.5 : c * 1.0) * (stacked ? 0.8 : 1.0);
      final h = w * 1.25;
      final dx = stacked ? (k - (n - 1) / 2) * c * 0.3 : 0.0;

      final movable = e.p == currentPlayer &&
          hasRolled &&
          !isRolling &&
          !isMoving &&
          !gameOver &&
          canPawnMove(position);

      return AnimatedPositioned(
        key: ValueKey('pawn_${e.p}_${e.i}'),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        left: e.center[1] * c - w / 2 + dx,
        top: e.center[0] * c - h * 0.65,
        width: w,
        height: h,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, movable ? -_pulse.value * c * 0.25 : 0),
              child: child,
            ),
            child: CustomPaint(
              painter: PawnPainter(
                color: players[e.p].color,
                highlight: movable,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final c = constraints.maxWidth / 15;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => onBoardTap(details.localPosition, c),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: BoardPainter(
                          colors: players.map((p) => p.color).toList(),
                          lights: players.map((p) => p.lightColor).toList(),
                          track: track,
                          lanes: [for (int p = 0; p < 4; p++) homeLane(p)],
                          starts: players.map((p) => p.start).toList(),
                          safeStars: safeStars,
                        ),
                      ),
                    ),
                    ...buildPawns(c),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  TextStyle logoStyle(Color color) {
    return TextStyle(
      color: color,
      fontSize: 30,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      height: 1.0,
      shadows: const [
        Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
      ],
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: [
          PopupMenuButton<String>(
            color: const Color(0xFF14267A),
            onSelected: (value) {
              if (value == 'new') restartGame();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'new',
                child: Text(
                  'Nouvelle partie',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              child: const Icon(Icons.menu, color: Colors.white),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👑', style: TextStyle(fontSize: 16)),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Ludo', style: logoStyle(Colors.white)),
                      TextSpan(
                        text: 'Pro',
                        style: logoStyle(const Color(0xFFFFC21A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Jouez • Gagnez • Amusez-vous !',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black26,
              border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events, color: Color(0xFFFFC21A), size: 22),
                SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode : Classique',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '4 Joueurs',
                      style: TextStyle(
                        color: Color(0xFFFFC21A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget playerBadge(int index, {required bool avatarOnRight}) {
    final player = players[index];
    final active = index == currentPlayer && !gameOver;
    final remaining = 4 - player.finished;

    final avatar = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [shade(player.color, 0.15), shade(player.color, -0.12)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: player.color.withOpacity(active ? 0.9 : 0.4),
            blurRadius: active ? 12 : 4,
            spreadRadius: active ? 2 : 0,
          ),
        ],
      ),
      child: Icon(player.avatar, color: Colors.white, size: 26),
    );

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          avatarOnRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          'Joueur ${player.display}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 15,
              child: CustomPaint(
                painter: PawnPainter(color: player.color, highlight: false),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$remaining pions',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: player.color.withOpacity(active ? 0.55 : 0.3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: active ? Colors.white : player.color.withOpacity(0.8),
          width: active ? 2 : 1.5,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: avatarOnRight
              ? [info, const SizedBox(width: 6), avatar]
              : [avatar, const SizedBox(width: 6), info],
        ),
      ),
    );
  }

  Widget buildDiceArea() {
    final player = players[currentPlayer];
    final canRoll = !gameOver && !hasRolled && !isRolling && !isMoving;
    final active = gameOver || canRoll;

    final label = gameOver
        ? 'Rejouer'
        : isRolling
            ? 'Le dé roule...'
            : isMoving
                ? 'Déplacement...'
                : hasRolled
                    ? 'Choisis un pion'
                    : 'Lancer le dé';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedRotation(
          turns: diceTurns,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: player.color.withOpacity(0.75),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CustomPaint(painter: DicePainter(dice)),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: gameOver ? restartGame : (canRoll ? rollDice : null),
          child: Container(
            width: 132,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: active
                    ? [const Color(0xFF55E05A), const Color(0xFF1B9E2B)]
                    : [const Color(0xFF6B7396), const Color(0xFF454C70)],
              ),
              border: Border.all(
                color: active ? const Color(0xFFFFD54F) : Colors.white24,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget roundButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0A1B66),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  void showStats() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14267A),
        title: const Text('Score', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in players)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(radius: 10, backgroundColor: p.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Joueur ${p.display}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    Text(
                      '${p.finished}/4 arrivés',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget buildStatusBar() {
    final player = players[currentPlayer];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1B66),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: Row(
                children: [
                  const Text('👑', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              const TextSpan(text: 'Au tour de : '),
                              TextSpan(
                                text: 'Joueur ${player.display}',
                                style: TextStyle(
                                  color: shade(player.color, 0.12),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          roundButton(
            soundOn ? Icons.volume_up : Icons.volume_off,
            () => setState(() => soundOn = !soundOn),
          ),
          const SizedBox(width: 8),
          roundButton(Icons.bar_chart, showStats),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1F5BFF),
              Color(0xFF0B2FA6),
              Color(0xFF061A66),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              buildHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: playerBadge(0, avatarOnRight: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: playerBadge(1, avatarOnRight: true),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Center(child: buildBoard()),
                ),
              ),
              SizedBox(
                height: 112,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: playerBadge(3, avatarOnRight: false),
                        ),
                      ),
                      buildDiceArea(),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: playerBadge(2, avatarOnRight: true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              buildStatusBar(),
            ],
          ),
        ),
      ),
    );
  }
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

  BoardPainter({
    required this.colors,
    required this.lights,
    required this.track,
    required this.lanes,
    required this.starts,
    required this.safeStars,
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
        _drawStar(canvas, rect.center, c * 0.3, Paint()..color = Colors.white);
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

  PawnPainter({required this.color, required this.highlight});

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
  }

  @override
  bool shouldRepaint(covariant PawnPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.highlight != highlight;
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
