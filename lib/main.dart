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
        brightness: Brightness.dark,
        useMaterial3: true,
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

  int dice = 1;
  int position = 0;
  int turn = 1;

  void rollDice() {
    setState(() {
      dice = random.nextInt(6) + 1;

      if (position + dice <= 56) {
        position += dice;
      }

      turn = turn == 1 ? 2 : 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081426),
      appBar: AppBar(
        backgroundColor: const Color(0xFF081426),
        title: const Text(
          'LudoPro',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Text(
                'Joue • Défie • Gagne',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 25),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 15,
                      color: Colors.black45,
                    ),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    painter: LudoBoardPainter(position),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111F35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Joueur',
                          style: TextStyle(color: Colors.white60),
                        ),
                        Text(
                          '$turn',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text(
                          'Dé',
                          style: TextStyle(color: Colors.white60),
                        ),
                        Text(
                          '$dice',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text(
                          'Position',
                          style: TextStyle(color: Colors.white60),
                        ),
                        Text(
                          '$position',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: rollDice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4DFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'LANCER LE DÉ 🎲',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    child: _menuButton(
                      Icons.people,
                      'Amis',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _menuButton(
                      Icons.emoji_events,
                      'Classement',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(IconData icon, String title) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: const Color(0xFF111F35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class LudoBoardPainter extends CustomPainter {
  final int position;

  LudoBoardPainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / 15;

    final Paint paint = Paint();

    // Fond
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );

    // Zones des joueurs
    paint.color = Colors.red.shade400;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cell * 6, cell * 6),
      paint,
    );

    paint.color = Colors.green.shade400;
    canvas.drawRect(
      Rect.fromLTWH(cell * 9, 0, cell * 6, cell * 6),
      paint,
    );

    paint.color = Colors.blue.shade400;
    canvas.drawRect(
      Rect.fromLTWH(0, cell * 9, cell * 6, cell * 6),
      paint,
    );

    paint.color = Colors.yellow.shade500;
    canvas.drawRect(
      Rect.fromLTWH(cell * 9, cell * 9, cell * 6, cell * 6),
      paint,
    );

    // Cases centrales
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(cell * 6, cell * 6, cell * 3, cell * 3),
      paint,
    );

    // Cases du parcours
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    paint.color = Colors.grey.shade400;

    for (int i = 0; i <= 15; i++) {
      canvas.drawLine(
        Offset(i * cell, 0),
        Offset(i * cell, size.height),
        paint,
      );

      canvas.drawLine(
        Offset(0, i * cell),
        Offset(size.width, i * cell),
        paint,
      );
    }

    paint.style = PaintingStyle.fill;

    // Pions
    _drawPawn(canvas, cell, 2, 2, Colors.red);
    _drawPawn(canvas, cell, 4, 2, Colors.red);
    _drawPawn(canvas, cell, 2, 4, Colors.red);
    _drawPawn(canvas, cell, 4, 4, Colors.red);

    _drawPawn(canvas, cell, 11, 2, Colors.green);
    _drawPawn(canvas, cell, 13, 2, Colors.green);
    _drawPawn(canvas, cell, 11, 4, Colors.green);
    _drawPawn(canvas, cell, 13, 4, Colors.green);

    _drawPawn(canvas, cell, 2, 11, Colors.blue);
    _drawPawn(canvas, cell, 4, 11, Colors.blue);
    _drawPawn(canvas, cell, 2, 13, Colors.blue);
    _drawPawn(canvas, cell, 4, 13, Colors.blue);

    _drawPawn(canvas, cell, 11, 11, Colors.yellow);
    _drawPawn(canvas, cell, 13, 11, Colors.yellow);
    _drawPawn(canvas, cell, 11, 13, Colors.yellow);
    _drawPawn(canvas, cell, 13, 13, Colors.yellow);

    // Pion actif
    final double progressX =
        cell * (6 + ((position % 3).toDouble()));

    final double progressY =
        cell * 7.0;

    paint.color = Colors.deepPurple;

    canvas.drawCircle(
      Offset(progressX + cell / 2, progressY + cell / 2),
      cell * 0.35,
      paint,
    );
  }

  void _drawPawn(
    Canvas canvas,
    double cell,
    int x,
    int y,
    Color color,
  ) {
    final Paint pawnPaint = Paint()..color = color;

    canvas.drawCircle(
      Offset(
        x * cell + cell / 2,
        y * cell + cell / 2,
      ),
      cell * 0.32,
      pawnPaint,
    );
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}
