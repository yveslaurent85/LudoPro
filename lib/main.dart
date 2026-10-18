import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;

  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Erreur Firebase : $e');
  }

  runApp(LudoProApp(firebaseReady: firebaseReady));
}

class LudoProApp extends StatelessWidget {
  final bool firebaseReady;

  const LudoProApp({
    super.key,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF10142B),
      ),
      home: HomeScreen(firebaseReady: firebaseReady),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final bool firebaseReady;

  const HomeScreen({
    super.key,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF10142B),
              Color(0xFF30205D),
              Color(0xFF126E82),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.casino,
                    size: 100,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'LudoPro',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Le plaisir du Ludo, partout avec vous !',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.people),
                      label: const Text(
                        'JOUER EN PRÉSENTIEL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GameSetupScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.public),
                      label: const Text(
                        'JOUER EN LIGNE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OnlineScreen(
                              firebaseReady: firebaseReady,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'LudoPro • Version en développement',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  int playerCount = 4;
  int pawnCount = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la partie')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.groups, size: 75, color: Colors.amber),
            const SizedBox(height: 12),
            const Text(
              'CHOISIS TES OPTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Nombre de joueurs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [2, 3, 4].map((count) {
                return ChoiceChip(
                  label: Text('$count joueurs'),
                  selected: playerCount == count,
                  onSelected: (_) {
                    setState(() => playerCount = count);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            const Text(
              'Nombre de pions par joueur',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [1, 2, 3, 4].map((count) {
                return ChoiceChip(
                  label: Text('$count pion${count > 1 ? 's' : ''}'),
                  selected: pawnCount == count,
                  onSelected: (_) {
                    setState(() => pawnCount = count);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Récapitulatif',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Joueurs : $playerCount'),
                  Text('Pions par joueur : $pawnCount'),
                  Text('Total des pions : ${playerCount * pawnCount}'),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text(
                  'COMMENCER LA PARTIE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LudoGame(
                        playerCount: playerCount,
                        pawnCount: pawnCount,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnlineScreen extends StatefulWidget {
  final bool firebaseReady;

  const OnlineScreen({
    super.key,
    required this.firebaseReady,
  });

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool loading = false;
  String message = '';

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> authenticate() async {
    if (!widget.firebaseReady) {
      setState(() {
        message = 'Firebase n’est pas initialisé. Vérifie sa configuration.';
      });
      return;
    }

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.length < 6) {
      setState(() {
        message = 'Entre un email valide et un mot de passe de 6 caractères minimum.';
      });
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        setState(() => message = 'Connexion réussie !');
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        setState(() => message = 'Compte créé avec succès !');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        message = switch (e.code) {
          'email-already-in-use' => 'Cette adresse email est déjà utilisée.',
          'invalid-email' => 'Adresse email invalide.',
          'weak-password' => 'Mot de passe trop faible.',
          'user-not-found' => 'Aucun compte trouvé avec cet email.',
          'wrong-password' => 'Mot de passe incorrect.',
          'invalid-credential' => 'Email ou mot de passe incorrect.',
          'network-request-failed' => 'Vérifie ta connexion Internet.',
          _ => e.message ?? 'Une erreur est survenue.',
        };
      });
    } catch (e) {
      setState(() => message = 'Erreur : $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.firebaseReady
        ? FirebaseAuth.instance.currentUser
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Espace en ligne')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.public, size: 75, color: Colors.cyanAccent),
            const SizedBox(height: 12),
            const Text(
              'LUDOPRO EN LIGNE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (user != null) ...[
              Text(
                'Connecté avec : ${user.email}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) setState(() => message = 'Déconnexion réussie.');
                },
                child: const Text('Se déconnecter'),
              ),
            ] else ...[
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: loading ? null : authenticate,
                  child: loading
                      ? const CircularProgressIndicator()
                      : Text(isLogin ? 'SE CONNECTER' : 'CRÉER UN COMPTE'),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    isLogin = !isLogin;
                    message = '';
                  });
                },
                child: Text(
                  isLogin
                      ? 'Pas encore de compte ? Inscris-toi'
                      : 'Tu as déjà un compte ? Connecte-toi',
                ),
              ),
            ],
            if (message.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'La connexion est disponible. Les parties à distance '
              'avec salons et invitations nécessitent une configuration '
              'supplémentaire.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class LudoGame extends StatefulWidget {
  final int playerCount;
  final int pawnCount;

  const LudoGame({
    super.key,
    this.playerCount = 4,
    this.pawnCount = 4,
  });

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class LudoPlayer {
  final String name;
  final Color color;
  final int start;
  final List<int> pawns;

  LudoPlayer({
    required this.name,
    required this.color,
    required this.start,
    required int pawnCount,
  }) : pawns = List.filled(pawnCount, -1);
}

class _LudoGameState extends State<LudoGame> {
  final Random random = Random();

  late List<LudoPlayer> players;

  int currentPlayer = 0;
  int dice = 1;
  int selectedPawn = -1;
  bool hasRolled = false;
  bool gameOver = false;
  String message = 'Appuie sur le dé pour commencer !';

  final Set<int> safeCells = {
    0, 8, 13, 21, 26, 34, 39, 47
  };

  @override
  void initState() {
    super.initState();
    initializePlayers();
  }

  void initializePlayers() {
    final colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.amber,
    ];

    final names = [
      'Rouge',
      'Vert',
      'Bleu',
      'Jaune',
    ];

    final starts = [0, 13, 26, 39];

    // Génère uniquement le nombre de joueurs choisi dans les paramètres
    players = List.generate(widget.playerCount, (index) {
      return LudoPlayer(
        name: names[index],
        color: colors[index],
        start: starts[index],
        pawnCount: widget.pawnCount,
      );
    });
  }

  LudoPlayer get activePlayer => players[currentPlayer];

  void rollDice() {
    if (hasRolled || gameOver) return;

    setState(() {
      dice = random.nextInt(6) + 1;
      hasRolled = true;
      selectedPawn = -1;

      final movable = <int>[];

      for (int i = 0; i < activePlayer.pawns.length; i++) {
        final position = activePlayer.pawns[i];

        if (position == -1 && dice == 6) {
          movable.add(i);
        } else if (position >= 0 && position < 57 &&
            position + dice <= 57) {
          movable.add(i);
        }
      }

      if (movable.isEmpty) {
        message = '${activePlayer.name} a obtenu $dice. '
            'Aucun pion ne peut avancer.';

        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted || gameOver || !hasRolled) return;

          setState(() {
            hasRolled = false;
            currentPlayer = (currentPlayer + 1) % players.length;
            message = 'Au tour de ${activePlayer.name}';
          });
        });
      } else {
        message = dice == 6
            ? 'Bravo ! Choisis un pion à sortir ou à avancer.'
            : 'Choisis le pion que tu veux déplacer.';
      }
    });
  }

  void movePawn(int pawnIndex) {
    if (!hasRolled || gameOver) return;

    final player = activePlayer;
    final oldPosition = player.pawns[pawnIndex];

    if (oldPosition == -1 && dice != 6) return;

    final newPosition = oldPosition == -1 ? 0 : oldPosition + dice;

    if (newPosition > 57) return;

    setState(() {
      player.pawns[pawnIndex] = newPosition;

      if (newPosition >= 0 && newPosition <= 51) {
        final cell = (player.start + newPosition) % 52;

        if (!safeCells.contains(cell)) {
          for (int p = 0; p < players.length; p++) {
            if (p == currentPlayer) continue;

            for (int j = 0; j < players[p].pawns.length; j++) {
              final opponentPosition = players[p].pawns[j];

              if (opponentPosition >= 0 &&
                  opponentPosition <= 51 &&
                  (players[p].start + opponentPosition) % 52 == cell) {
                players[p].pawns[j] = -1;
                message = 'Pion adverse capturé !';
              }
            }
          }
        }
      }

      final finished = player.pawns.every((position) => position == 57);

      if (finished) {
        gameOver = true;
        message = '🏆 ${player.name} a gagné la partie !';
        return;
      }

      if (player.pawns[pawnIndex] == 57) {
        message = 'Bravo ! Un pion est arrivé à destination.';
      } else if (message != 'Pion adverse capturé !') {
        message = '${player.name} a déplacé son pion.';
      }

      hasRolled = false;
      selectedPawn = -1;

      if (dice != 6) {
        currentPlayer = (currentPlayer + 1) % players.length;
      }

      if (!gameOver) {
        message += ' Au tour de ${activePlayer.name}.';
      }
    });
  }

  void restartGame() {
    setState(() {
      initializePlayers();
      currentPlayer = 0;
      dice = 1;
      selectedPawn = -1;
      hasRolled = false;
      gameOver = false;
      message = 'Nouvelle partie ! Appuie sur le dé.';
    });
  }

  Color get currentColor => activePlayer.color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LudoPro 🎲'),
        actions: [
          IconButton(
            tooltip: 'Recommencer',
            onPressed: restartGame,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF10142B),
              Color(0xFF29205A),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                'Joueur ${currentPlayer + 1} / ${players.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activePlayer.name.toUpperCase(),
                style: TextStyle(
                  color: currentColor,
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(
                        painter: BoardPainter(players: players),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < activePlayer.pawns.length; i++)
                      ElevatedButton(
                        onPressed: hasRolled && !gameOver
                            ? () => movePawn(i)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          'Pion ${i + 1}: '
                          '${activePlayer.pawns[i] == -1
                              ? "Maison"
                              : activePlayer.pawns[i] == 57
                                  ? "Terminé"
                                  : activePlayer.pawns[i]}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: hasRolled || gameOver ? null : rollDice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white24,
                    ),
                    icon: const Icon(Icons.casino, size: 28),
                    label: Text(
                      gameOver
                          ? 'PARTIE TERMINÉE'
                          : hasRolled
                              ? 'DÉ : $dice — CHOISIS UN PION'
                              : 'LANCER LE DÉ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  final List<LudoPlayer> players;

  BoardPainter({required this.players});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final unit = min(width, height);

    final background = Paint()
      ..color = const Color(0xFFF4F1E8);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, height),
        const Radius.circular(20),
      ),
      background,
    );

    final colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.amber,
    ];

    final positions = [
      const Offset(0.04, 0.04),
      const Offset(0.56, 0.04),
      const Offset(0.04, 0.56),
      const Offset(0.56, 0.56),
    ];

    final baseSize = unit * 0.38;

    for (int i = 0; i < 4; i++) {
      // Si le joueur est actif, on affiche sa couleur normale, sinon une base neutre/discrète
      final isActive = i < players.length;

      final rect = Rect.fromLTWH(
        positions[i].dx * width,
        positions[i].dy * height,
        baseSize,
        baseSize,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(14),
        ),
        Paint()
          ..color = isActive
              ? colors[i].withValues(alpha: 0.85)
              : Colors.grey.withValues(alpha: 0.15),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(unit * 0.045),
          const Radius.circular(10),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
    }

    final center = Offset(width / 2, height / 2);
    final radius = unit * 0.31;

    canvas.drawCircle(
      center,
      radius + unit * 0.045,
      Paint()..color = const Color(0xFFDED9CE),
    );

    for (int i = 0; i < 52; i++) {
      final angle = -pi / 2 + (2 * pi * i / 52);
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      final cellColor = switch (i) {
        0 => Colors.red,
        13 => Colors.green,
        26 => Colors.blue,
        39 => Colors.amber,
        _ => Colors.white,
      };

      canvas.drawCircle(
        point,
        unit * 0.022,
        Paint()..color = cellColor,
      );

      canvas.drawCircle(
        point,
        unit * 0.022,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    for (int p = 0; p < players.length; p++) {
      final player = players[p];

      for (int j = 0; j < player.pawns.length; j++) {
        final position = player.pawns[j];
        Offset point;

        if (position == -1) {
          final base = positions[p];
          final offsetX = j % 2 == 0 ? 0.10 : 0.26;
          final offsetY = j < 2 ? 0.10 : 0.26;

          point = Offset(
            (base.dx + offsetX) * width,
            (base.dy + offsetY) * height,
          );
        } else if (position <= 51) {
          final trackIndex = (player.start + position) % 52;
          final angle = -pi / 2 + (2 * pi * trackIndex / 52);

          point = Offset(
            center.dx + radius * cos(angle),
            center.dy + radius * sin(angle),
          );
        } else if (position < 57) {
          final progress = position - 51;
          final angle = -pi / 2 + (2 * pi * player.start / 52);
          final distance = radius * (1 - progress / 7);

          point = Offset(
            center.dx + distance * cos(angle),
            center.dy + distance * sin(angle),
          );
        } else {
          point = center;
        }

        final pawnRadius = unit * 0.027;

        canvas.drawCircle(
          point,
          pawnRadius,
          Paint()..color = player.color,
        );

        canvas.drawCircle(
          point,
          pawnRadius,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        final numberPainter = TextPainter(
          text: TextSpan(
            text: '${j + 1}',
            style: TextStyle(
              color: Colors.white,
              fontSize: unit * 0.022,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        numberPainter.layout();
        numberPainter.paint(
          canvas,
          Offset(
            point.dx - numberPainter.width / 2,
            point.dy - numberPainter.height / 2,
          ),
        );
      }
    }

    final centerPainter = TextPainter(
      text: const TextSpan(
        text: 'LUDO',
        style: TextStyle(
          color: Colors.deepPurple,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    centerPainter.layout();
    centerPainter.paint(
      canvas,
      Offset(
        center.dx - centerPainter.width / 2,
        center.dy - centerPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
