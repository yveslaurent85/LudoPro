import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const LudoProApp());
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
        scaffoldBackgroundColor: const Color(0xFF10152B),
      ),
      home: const LudoGame(),
    );
  }
}

class Player {
  final String name;
  final Color color;
  final Color lightColor;
  final int start;
  final List<int> pawns = [-1, -1, -1, -1];
  final IconData avatar;

  Player({
    required this.name,
    required this.color,
    required this.lightColor,
    required this.start,
    required this.avatar,
  });
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key});

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> {
  final Random random = Random();

  // Cases étoiles (8 cases après chaque départ) et cases sûres (départs + étoiles)
  static const Set<int> safeStars = {8, 21, 34, 47};
  static const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  late final List<Player> players = [
    Player(
      name: 'ROUGE',
      color: const Color(0xFFFF4057),
      lightColor: const Color(0xFFFFDCE1),
      start: 0,
      avatar: Icons.person,
    ),
    Player(
      name: 'VERT',
      color: const Color(0xFF19C784),
      lightColor: const Color(0xFFD7FFEC),
      start: 13,
      avatar: Icons.face,
    ),
    Player(
      name: 'JAUNE',
      color: const Color(0xFFFFC928),
      lightColor: const Color(0xFFFFF2C4),
      start: 26,
      avatar: Icons.person_outline,
    ),
    Player(
      name: 'BLEU',
      color: const Color(0xFF4385FF),
      lightColor: const Color(0xFFDCE8FF),
      start: 39,
      avatar: Icons.face_3,
    ),
  ];

  int currentPlayer = 0;
  int dice = 1;
  bool hasRolled = false;
  bool gameOver = false;
  int _token = 0; // sert à annuler un passage de tour en attente
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

  final List<List<List<int>>> homeSlots = const [
    [
      [1, 1], [1, 3], [3, 1], [3, 3]
    ],
    [
      [1, 11], [1, 13], [3, 11], [3, 13]
    ],
    [
      [11, 11], [11, 13], [13, 11], [13, 13]
    ],
    [
      [11, 1], [11, 3], [13, 1], [13, 3]
    ],
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

  void rollDice() {
    if (hasRolled || gameOver) return;

    final newDice = random.nextInt(6) + 1;
    final player = players[currentPlayer];
    final canMove = player.pawns.any(
      (p) => p == -1 ? newDice == 6 : p + newDice <= 56,
    );

    setState(() {
      dice = newDice;
      hasRolled = true;

      if (!canMove) {
        message = '$dice ! Aucun déplacement possible.';
      } else {
        message = dice == 6
            ? 'Super ! Tu peux sortir un pion ou avancer.'
            : 'Choisis un pion à déplacer.';
      }
    });

    // CORRECTION : si aucun pion ne peut bouger, on passe au joueur suivant
    if (!canMove) {
      final token = ++_token;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted || token != _token || gameOver) return;
        nextTurn();
      });
    }
  }

  void nextTurn() {
    setState(() {
      currentPlayer = (currentPlayer + 1) % players.length;
      hasRolled = false;
      dice = 1;
      message = 'Au tour de ${players[currentPlayer].name} !';
    });
  }

  void movePawn(int playerIndex, int pawnIndex) {
    if (!hasRolled || gameOver || playerIndex != currentPlayer) {
      return;
    }

    final player = players[playerIndex];
    final oldPosition = player.pawns[pawnIndex];

    if (oldPosition == 56) return;

    if (oldPosition == -1 && dice != 6) {
      setState(() {
        message = 'Il faut obtenir un 6 pour sortir ce pion.';
      });
      return;
    }

    if (oldPosition >= 0 && oldPosition + dice > 56) {
      setState(() {
        message = 'Ce pion ne peut pas terminer avec ce lancer.';
      });
      return;
    }

    setState(() {
      player.pawns[pawnIndex] = oldPosition == -1 ? 0 : oldPosition + dice;

      final newPosition = player.pawns[pawnIndex];

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
                message = 'Bravo ! Tu renvoies un pion à la maison.';
              }
            }
          }
        }
      }

      if (player.pawns.every((p) => p == 56)) {
        gameOver = true;
        message = '🏆 ${player.name} remporte la partie !';
      } else if (dice == 6) {
        hasRolled = false;
        dice = 1;
        message = 'Magnifique ! Tu rejoues.';
      } else {
        nextTurn();
      }
    });
  }

  bool isHomeCell(int row, int col, int player) {
    final rowStart = player < 2 ? 0 : 9;
    final colStart = player == 0 || player == 3 ? 0 : 9;

    return row >= rowStart &&
        row <= rowStart + 5 &&
        col >= colStart &&
        col <= colStart + 5;
  }

  List<Widget> pawnsAtCell(int row, int col) {
    final result = <Widget>[];

    for (int p = 0; p < players.length; p++) {
      for (int i = 0; i < 4; i++) {
        final position = players[p].pawns[i];

        // Pion arrivé : on ne l'affiche plus (il est compté dans le score)
        if (position == 56) continue;

        List<int> cell;

        if (position == -1) {
          // CORRECTION : les pions à la maison sont maintenant dessinés
          cell = homeSlots[p][i];
        } else if (position >= 51) {
          // CORRECTION : la couloir final commence à 51 (et non 52)
          cell = homeLane(p)[position - 51];
        } else {
          cell = track[(players[p].start + position) % 52];
        }

        if (cell[0] == row && cell[1] == col) {
          result.add(
            GestureDetector(
              onTap: () => movePawn(p, i),
              child: Container(
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: players[p].color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: players[p].color.withOpacity(0.4),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return result;
  }

  Widget buildCell(int row, int col) {
    Color background = Colors.white;
    Color borderColor = const Color(0xFFDDE2EF);

    for (int p = 0; p < 4; p++) {
      if (isHomeCell(row, col, p)) {
        background = players[p].lightColor;
      }
    }

    final trackIndex = track.indexWhere(
      (cell) => cell[0] == row && cell[1] == col,
    );

    if (trackIndex >= 0) {
      background = Colors.white;

      for (int p = 0; p < 4; p++) {
        if (trackIndex == players[p].start) {
          background = players[p].color;
        }
      }

      if (safeStars.contains(trackIndex)) {
        background = const Color(0xFFFFF1B8);
      }
    }

    // CORRECTION : couloirs d'arrivée colorés
    for (int p = 0; p < 4; p++) {
      if (homeLane(p).any((c) => c[0] == row && c[1] == col)) {
        background = players[p].color.withOpacity(0.55);
      }
    }

    if (row == 7 && col == 7) {
      background = const Color(0xFF10152B);
    }

    final pieces = pawnsAtCell(row, col);

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: borderColor,
          width: 0.35,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trackIndex >= 0 && safeStars.contains(trackIndex))
            const Center(
              child: Icon(Icons.star, size: 12, color: Color(0xFFE0A800)),
            ),
          if (isHomeCell(row, col, 0) && row == 2 && col == 2)
            const Icon(Icons.person, size: 11, color: Colors.red),
          if (isHomeCell(row, col, 1) && row == 2 && col == 11)
            const Icon(Icons.face, size: 11, color: Colors.green),
          if (isHomeCell(row, col, 2) && row == 11 && col == 11)
            const Icon(Icons.person_outline, size: 11, color: Colors.orange),
          if (isHomeCell(row, col, 3) && row == 11 && col == 2)
            const Icon(Icons.face_3, size: 11, color: Colors.blue),
          if (pieces.isNotEmpty)
            Center(
              child: pieces.length == 1
                  ? SizedBox.expand(child: pieces.first)
                  : Wrap(
                      alignment: WrapAlignment.center,
                      children: pieces
                          .map(
                            (piece) => SizedBox(
                              width: 12,
                              height: 12,
                              child: piece,
                            ),
                          )
                          .toList(),
                    ),
            ),
          if (row == 7 && col == 7)
            const Center(
              child: Icon(
                Icons.star,
                color: Colors.amber,
                size: 23,
              ),
            ),
        ],
      ),
    );
  }

  Widget buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 225,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 15,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemBuilder: (context, index) {
            return buildCell(index ~/ 15, index % 15);
          },
        ),
      ),
    );
  }

  Widget playerCard(int index) {
    final player = players[index];
    final active = index == currentPlayer;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
        decoration: BoxDecoration(
          color: active
              ? player.color.withOpacity(0.22)
              : const Color(0xFF1A203A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? player.color : Colors.white12,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: player.color,
              child: Icon(player.avatar, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 5),
            Text(
              player.name,
              style: TextStyle(
                color: player.color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${player.pawns.where((p) => p == 56).length}/4',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget diceWidget() {
    final faces = [
      '',
      '⚀',
      '⚁',
      '⚂',
      '⚃',
      '⚄',
      '⚅',
    ];

    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: players[currentPlayer].color.withOpacity(0.35),
            blurRadius: 15,
          ),
        ],
      ),
      child: Center(
        child: Text(
          faces[dice],
          style: const TextStyle(fontSize: 43, color: Colors.black87),
        ),
      ),
    );
  }

  void restartGame() {
    _token++; // annule un éventuel passage de tour en attente
    setState(() {
      for (final player in players) {
        player.pawns.fillRange(0, 4, -1);
      }
      currentPlayer = 0;
      dice = 1;
      hasRolled = false;
      gameOver = false;
      message = 'Nouvelle partie ! Lance le dé.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFC928),
                          Color(0xFFFF7043),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.casino,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LUDO PRO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'PLAY • ENJOY • WIN',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: restartGame,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Nouvelle partie',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(4, playerCard),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: buildBoard(),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A203A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      diceWidget(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOUR DE ${players[currentPlayer].name}',
                              style: TextStyle(
                                color: players[currentPlayer].color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Lance le dé et sélectionne ton pion.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton(
                                onPressed: gameOver
                                    ? restartGame
                                    : hasRolled
                                        ? null
                                        : rollDice,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      players[currentPlayer].color,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.white12,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  gameOver
                                      ? 'REJOUER'
                                      : hasRolled
                                          ? 'CHOISIS UN PION'
                                          : '🎲 LANCER LE DÉ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
