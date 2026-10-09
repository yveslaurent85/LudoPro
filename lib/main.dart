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
        scaffoldBackgroundColor: const Color(0xFF10172A),
      ),
      home: const LudoHomePage(),
    );
  }
}

class LudoHomePage extends StatefulWidget {
  const LudoHomePage({super.key});

  @override
  State<LudoHomePage> createState() => _LudoHomePageState();
}

class _LudoHomePageState extends State<LudoHomePage> {
  final Random random = Random();

  int diceValue = 1;
  bool isRolling = false;
  int currentPlayer = 0;
  int totalRolls = 0;

  final List<Color> playerColors = [
    const Color(0xFFFF4757),
    const Color(0xFF00C896),
    const Color(0xFFFFC048),
    const Color(0xFF45AAFF),
  ];

  final List<String> playerNames = [
    'ROUGE',
    'VERT',
    'JAUNE',
    'BLEU',
  ];

  void rollDice() {
    if (isRolling) return;

    setState(() {
      isRolling = true;
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;

      setState(() {
        diceValue = random.nextInt(6) + 1;
        totalRolls++;
        isRolling = false;

        if (diceValue != 6) {
          currentPlayer = (currentPlayer + 1) % 4;
        }
      });

      if (diceValue == 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Six ! Tu peux jouer encore !',
              textAlign: TextAlign.center,
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF172554),
              Color(0xFF10172A),
              Color(0xFF251447),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                buildHeader(),
                const SizedBox(height: 22),
                buildWelcomeCard(),
                const SizedBox(height: 22),
                buildPlayers(),
                const SizedBox(height: 18),
                buildBoard(),
                const SizedBox(height: 22),
                buildDiceSection(),
                const SizedBox(height: 20),
                buildBottomInfo(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Row(
      children: [
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF8B5CF6),
                Color(0xFFEC4899),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.3),
                blurRadius: 15,
              ),
            ],
          ),
          child: const Icon(
            Icons.casino_rounded,
            color: Colors.white,
            size: 32,
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
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              Text(
                'PLAY • WIN • HAVE FUN',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  color: Color(0xFFB8C4E0),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.circle,
                size: 9,
                color: Color(0xFF00E6A0),
              ),
              SizedBox(width: 6),
              Text(
                'ONLINE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7C3AED),
            Color(0xFF4F46E5),
            Color(0xFF2563EB),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -15,
            child: Icon(
              Icons.stars_rounded,
              size: 105,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TON MOMENT DE GLOIRE !',
                style: TextStyle(
                  color: Color(0xFFFFE082),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Prêt à jouer ?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Lance le dé et mène tes pions vers la victoire.',
                style: TextStyle(
                  color: Color(0xFFE0E7FF),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFFFD54F),
                    size: 21,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$totalRolls lancers effectués',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildPlayers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.groups_rounded,
              color: Color(0xFFA78BFA),
              size: 23,
            ),
            SizedBox(width: 8),
            Text(
              'JOUEURS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(4, (index) {
            final bool active = currentPlayer == index;

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: index == 3 ? 0 : 8,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? playerColors[index].withValues(alpha: 0.17)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? playerColors[index]
                        : Colors.white.withValues(alpha: 0.09),
                    width: active ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: playerColors[index],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: playerColors[index]
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      playerNames[index],
                      style: TextStyle(
                        color: active
                            ? playerColors[index]
                            : Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (active)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'À TOI !',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget buildBoard() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: LudoBoardPainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget buildDiceSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        children: [
          Text(
            'AU TOUR DU JOUEUR ${currentPlayer + 1}',
            style: TextStyle(
              color: playerColors[currentPlayer],
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: rollDice,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 82,
              width: 82,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: playerColors[currentPlayer],
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: playerColors[currentPlayer]
                        .withValues(alpha: 0.3),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Center(
                child: isRolling
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Color(0xFF7C3AED),
                          strokeWidth: 4,
                        ),
                      )
                    : DiceFace(value: diceValue),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: isRolling ? null : rollDice,
              style: ElevatedButton.styleFrom(
                backgroundColor: playerColors[currentPlayer],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.casino_rounded, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    isRolling ? 'LANCEMENT...' : 'LANCER LE DÉ',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Obtiens un 6 pour rejouer !',
            style: TextStyle(
              color: Color(0xFFB8C4E0),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBottomInfo() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 15,
            color: Color(0xFFEC4899),
          ),
          SizedBox(width: 7),
          Text(
            'LudoPro • Le plaisir de jouer ensemble',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB8C4E0),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class DiceFace extends StatelessWidget {
  final int value;

  const DiceFace({
    super.key,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final List<Alignment> positions = [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.centerLeft,
      Alignment.center,
      Alignment.centerRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ];

    final List<List<int>> patterns = [
      [],
      [3],
      [0, 6],
      [0, 3, 6],
      [0, 1, 5, 6],
      [0, 1, 3, 5, 6],
      [0, 1, 2, 4, 5, 6],
    ];

    return Padding(
      padding: const EdgeInsets.all(13),
      child: Stack(
        children: [
          for (final position in patterns[value])
            Align(
              alignment: positions[position],
              child: Container(
                width: 11,
                height: 11,
                decoration: const BoxDecoration(
                  color: Color(0xFF172554),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LudoBoardPainter extends CustomPainter {
  static const Color red = Color(0xFFFF4757);
  static const Color green = Color(0xFF00B894);
  static const Color yellow = Color(0xFFFFC048);
  static const Color blue = Color(0xFF45AAFF);

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / 15;

    final Paint fill = Paint()
      ..style = PaintingStyle.fill;

    final Paint border = Paint()
      ..color = const Color(0xFFD9DEE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    void rect(
      int x,
      int y,
      int w,
      int h,
      Color color,
    ) {
      fill.color = color;
      final Rect r = Rect.fromLTWH(
        x * cell,
        y * cell,
        w * cell,
        h * cell,
      );
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }

    void circle(
      double x,
      double y,
      double radius,
      Color color,
    ) {
      fill.color = color;
      canvas.drawCircle(
        Offset(x * cell, y * cell),
        radius * cell,
        fill,
      );
    }

    final Color white = Colors.white;
    final Color paleRed = const Color(0xFFFFDDE1);
    final Color paleGreen = const Color(0xFFD7FFF0);
    final Color paleYellow = const Color(0xFFFFF2C6);
    final Color paleBlue = const Color(0xFFDDEEFF);

    rect(0, 0, 15, 15, white);

    // Four colored home areas.
    rect(0, 0, 6, 6, red);
    rect(9, 0, 6, 6, green);
    rect(0, 9, 6, 6, blue);
    rect(9, 9, 6, 6, yellow);

    // White bases inside the home areas.
    rect(1, 1, 4, 4, white);
    rect(10, 1, 4, 4, white);
    rect(1, 10, 4, 4, white);
    rect(10, 10, 4, 4, white);

    // Home tokens.
    final List<Color> colors = [red, green, blue, yellow];

    final List<List<Offset>> tokenPositions = [
      [
        const Offset(2, 2),
        const Offset(4, 2),
        const Offset(2, 4),
        const Offset(4, 4),
      ],
      [
        const Offset(11, 2),
        const Offset(13, 2),
        const Offset(11, 4),
        const Offset(13, 4),
      ],
      [
        const Offset(2, 11),
        const Offset(4, 11),
        const Offset(2, 13),
        const Offset(4, 13),
      ],
      [
        const Offset(11, 11),
        const Offset(13, 11),
        const Offset(11, 13),
        const Offset(13, 13),
      ],
    ];

    for (int p = 0; p < 4; p++) {
      for (final Offset token in tokenPositions[p]) {
        circle(
          token.dx + 0.5,
          token.dy + 0.5,
          0.40,
          colors[p],
        );
        circle(
          token.dx + 0.5,
          token.dy + 0.5,
          0.27,
          white,
        );
        circle(
          token.dx + 0.5,
          token.dy + 0.5,
          0.18,
          colors[p],
        );
      }
    }

    // Central cross-shaped track.
    for (int i = 0; i < 6; i++) {
      rect(6, i, 3, 1, white);
      rect(6, 9 + i, 3, 1, white);
      rect(i, 6, 1, 3, white);
      rect(9 + i, 6, 1, 3, white);
    }

    // Colored home lanes.
    for (int i = 0; i < 6; i++) {
      rect(7, i, 1, 1, i == 5 ? red : paleRed);
      rect(7, 9 + i, 1, 1, i == 0 ? yellow : paleYellow);
      rect(i, 7, 1, 1, i == 5 ? blue : paleBlue);
      rect(9 + i, 7, 1, 1, i == 0 ? green : paleGreen);
    }

    // Entry squares.
    rect(1, 6, 1, 1, blue);
    rect(8, 1, 1, 1, green);
    rect(13, 8, 1, 1, yellow);
    rect(6, 13, 1, 1, red);

    // Starting points.
    circle(1.5, 6.5, 0.22, blue);
    circle(8.5, 1.5, 0.22, green);
    circle(13.5, 8.5, 0.22, yellow);
    circle(6.5, 13.5, 0.22, red);

    // Center triangles.
    final double center = size.width / 2;
    final Path top = Path()
      ..moveTo(center, center)
      ..lineTo(6 * cell, 6 * cell)
      ..lineTo(9 * cell, 6 * cell)
      ..close();

    final Path right = Path()
      ..moveTo(center, center)
      ..lineTo(9 * cell, 6 * cell)
      ..lineTo(9 * cell, 9 * cell)
      ..close();

    final Path bottom = Path()
      ..moveTo(center, center)
      ..lineTo(9 * cell, 9 * cell)
      ..lineTo(6 * cell, 9 * cell)
      ..close();

    final Path left = Path()
      ..moveTo(center, center)
      ..lineTo(6 * cell, 9 * cell)
      ..lineTo(6 * cell, 6 * cell)
      ..close();

    fill.color = green;
    canvas.drawPath(top, fill);

    fill.color = yellow;
    canvas.drawPath(right, fill);

    fill.color = red;
    canvas.drawPath(bottom, fill);

    fill.color = blue;
    canvas.drawPath(left, fill);

    final Paint centerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(top, centerBorder);
    canvas.drawPath(right, centerBorder);
    canvas.drawPath(bottom, centerBorder);
    canvas.drawPath(left, centerBorder);

    // Outline around the whole board.
    final Paint outline = Paint()
      ..color = const Color(0xFFCFD5E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      outline,
    );
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) {
    return false;
  }
}
