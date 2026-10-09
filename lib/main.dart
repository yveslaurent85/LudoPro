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
      debugShowCheckedModeBanner: false,
      title: 'LudoPro',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LudoGame(),
    );
  }
}

class Player {
  final String name;
  final Color color;
  final String emoji;
  final List<int> pawns;

  Player({
    required this.name,
    required this.color,
    required this.emoji,
  }) : pawns = [-1, -1, -1, -1];
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key});

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> {
  final Random random = Random();

  late List<Player> players;

  int currentPlayer = 0;
  int dice = 1;
  bool diceRolled = false;
  String message = 'Lance le dé pour commencer !';
  bool gameOver = false;

  @override
  void initState() {
    super.initState();

    players = [
      Player(name: 'Rouge', color: Colors.red, emoji: '🔴'),
      Player(name: 'Vert', color: Colors.green, emoji: '🟢'),
      Player(name: 'Jaune', color: Colors.amber, emoji: '🟡'),
      Player(name: 'Bleu', color: Colors.blue, emoji: '🔵'),
    ];
  }

  void rollDice() {
    if (diceRolled || gameOver) return;

    setState(() {
      dice = random.nextInt(6) + 1;
      diceRolled = true;

      final movable = players[currentPlayer].pawns.any(
        (position) => position == -1 ? dice == 6 : position < 39,
      );

      if (!movable) {
        message = '$dice ! Aucun pion ne peut avancer.';
      } else {
        message =
            '${players[currentPlayer].name} : choisis un pion à déplacer.';
      }
    });

    final movable = players[currentPlayer].pawns.any(
      (position) => position == -1 ? dice == 6 : position < 39,
    );

    if (!movable) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted || gameOver) return;

        setState(() {
          diceRolled = false;
          currentPlayer = (currentPlayer + 1) % 4;
          message = 'Au tour de ${players[currentPlayer].name} !';
        });
      });
    }
  }

  void movePawn(int pawnIndex) {
    if (!diceRolled || gameOver) return;

    final player = players[currentPlayer];
    final position = player.pawns[pawnIndex];

    if (position == -1 && dice != 6) {
      setState(() {
        message = 'Il faut obtenir un 6 pour sortir ce pion !';
      });
      return;
    }

    final newPosition = position == -1 ? 0 : position + dice;

    if (newPosition > 39) {
      setState(() {
        message = 'Il faut obtenir le bon nombre pour finir !';
      });
      return;
    }

    setState(() {
      player.pawns[pawnIndex] = newPosition;

      if (player.pawns.every((p) => p == 39)) {
        gameOver = true;
        message = '🏆 ${player.name} a gagné la partie !';
        return;
      }

      diceRolled = false;

      if (dice == 6) {
        message = 'Bravo ! Tu as fait 6. Rejoue !';
      } else {
        currentPlayer = (currentPlayer + 1) % 4;
        message = 'Au tour de ${players[currentPlayer].name} !';
      }
    });
  }

  void restartGame() {
    setState(() {
      for (final player in players) {
        for (int i = 0; i < player.pawns.length; i++) {
          player.pawns[i] = -1;
        }
      }

      currentPlayer = 0;
      dice = 1;
      diceRolled = false;
      gameOver = false;
      message = 'Nouvelle partie ! Lance le dé.';
    });
  }

  Widget buildPawn(Player player, int index) {
    final position = player.pawns[index];
    final isCurrent = players[currentPlayer] == player;

    return InkWell(
      onTap: isCurrent ? () => movePawn(index) : null,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: position == -1
              ? player.color.withValues(alpha: 0.15)
              : player.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isCurrent ? Colors.white : player.color,
            width: isCurrent ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: player.color.withValues(alpha: 0.2),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            position == -1 ? '${index + 1}' : '♟',
            style: TextStyle(
              color: position == -1 ? player.color : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPlayerCard(Player player, int index) {
    final active = currentPlayer == index;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: player.color.withValues(alpha: active ? 0.15 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? player.color : Colors.white10,
          width: active ? 3 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(player.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  player.name,
                  style: TextStyle(
                    color: player.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: List.generate(
              4,
              (i) => buildPawn(player, i),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${player.pawns.where((p) => p >= 0).length}/4 pions sortis',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget buildTrack() {
    final occupied = <int, List<int>>{};

    for (int p = 0; p < players.length; p++) {
      for (int i = 0; i < players[p].pawns.length; i++) {
        final pos = players[p].pawns[i];

        if (pos >= 0) {
          occupied.putIfAbsent(pos, () => []).add(p);
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF17233D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text(
            'PARCOURS DES PIONS',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 40,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              final colors = occupied[index] ?? [];

              return Container(
                decoration: BoxDecoration(
                  color: colors.isEmpty
                      ? const Color(0xFF263653)
                      : players[colors.first].color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: colors.isEmpty
                      ? Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        )
                      : const Icon(
                          Icons.circle,
                          color: Colors.white,
                          size: 14,
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Les cases représentent les positions des pions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePlayer = players[currentPlayer];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1224),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121D35),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          '🎲 LudoPro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: restartGame,
            icon: const Icon(Icons.refresh),
            tooltip: 'Nouvelle partie',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Text(
                'LE PLAISIR DE JOUER ENSEMBLE',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF263E72), Color(0xFF182746)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Text(
                      'C’EST AU TOUR DE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${activePlayer.emoji} ${activePlayer.name.toUpperCase()}',
                      style: TextStyle(
                        color: activePlayer.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: buildPlayerCard(players[0], 0)),
                  const SizedBox(width: 10),
                  Expanded(child: buildPlayerCard(players[1], 1)),
                ],
              ),
              const SizedBox(height: 10),
              buildTrack(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: buildPlayerCard(players[2], 2)),
                  const SizedBox(width: 10),
                  Expanded(child: buildPlayerCard(players[3], 3)),
                ],
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: rollDice,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: activePlayer.color,
                      width: 5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: activePlayer.color.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$dice',
                      style: const TextStyle(
                        color: Color(0xFF17233D),
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'APPUIE SUR LE DÉ POUR JOUER',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: restartGame,
                  icon: const Icon(Icons.replay),
                  label: const Text('RECOMMENCER LA PARTIE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: const Color(0xFF17233D),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'Version de test • LudoPro',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
