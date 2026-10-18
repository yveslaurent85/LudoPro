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
                        painter: ClassicLudoBoardPainter(players: players),
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

class ClassicLudoBoardPainter extends CustomPainter {
  final List<LudoPlayer> players;

  ClassicLudoBoardPainter({required this.players});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cellSize = w / 15;

    // Fond général du plateau (crème classique)
    final bgPaint = Paint()..color = const Color(0xFFF9F6EE);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)),
      bgPaint,
    );

    final colors = [Colors.red, Colors.green, Colors.blue, Colors.amber];

    // 1. Dessin des 4 grandes bases aux coins (6x6 cellules)
    final baseRects = [
      Rect.fromLTWH(0, 0, 6 * cellSize, 6 * cellSize),         // Rouge (Haut-Gauche)
      Rect.fromLTWH(9 * cellSize, 0, 6 * cellSize, 6 * cellSize),    // Vert (Haut-Droite)
      Rect.fromLTWH(0, 9 * cellSize, 6 * cellSize, 6 * cellSize),    // Jaune/Bleu (Bas-Gauche)
      Rect.fromLTWH(9 * cellSize, 9 * cellSize, 6 * cellSize, 6 * cellSize), // Jaune/Bleu (Bas-Droite)
    ];

    for (int i = 0; i < 4; i++) {
      final isActive = i < players.length;
      final paint = Paint()
        ..color = isActive ? colors[i] : Colors.grey.withValues(alpha: 0.3);
      canvas.drawRect(baseRects[i], paint);

      // Intérieur blanc de la maison
      final innerRect = baseRects[i].deflate(cellSize * 0.8);
      canvas.drawRect(innerRect, Paint()..color = Colors.white);
    }

    // 2. Grille des pistes extérieures et couloirs (15x15)
    final trackPaint = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 15; i++) {
      canvas.drawLine(Offset(i * cellSize, 0), Offset(i * cellSize, h), trackPaint);
      canvas.drawLine(Offset(0, i * cellSize), Offset(w, i * cellSize), trackPaint);
    }

    // 3. Couloirs de couleur (maisons d'arrivée)
    // Colonne centrale / Lignes centrales
    // Rouge (gauche)
    for (int i = 1; i <= 5; i++) {
      canvas.drawRect(Rect.fromLTWH(i * cellSize, 6 * cellSize, cellSize, cellSize), Paint()..color = Colors.red);
    }
    // Vert (haut)
    for (int i = 1; i <= 5; i++) {
      canvas.drawRect(Rect.fromLTWH(8 * cellSize, i * cellSize, cellSize, cellSize), Paint()..color = Colors.green);
    }
    // Jaune (droite)
    for (int i = 9; i <= 13; i++) {
      canvas.drawRect(Rect.fromLTWH(i * cellSize, 8 * cellSize, cellSize, cellSize), Paint()..color = Colors.amber);
    }
    // Bleu (bas)
    for (int i = 9; i <= 13; i++) {
      canvas.drawRect(Rect.fromLTWH(6 * cellSize, i * cellSize, cellSize, cellSize), Paint()..color = Colors.blue);
    }

    // Cases de départ / étoiles (repères classiques)
    _drawStar(canvas, Offset(1.5 * cellSize, 6.5 * cellSize), cellSize * 0.4, Colors.red);
    _drawStar(canvas, Offset(8.5 * cellSize, 1.5 * cellSize), cellSize * 0.4, Colors.green);
    _drawStar(canvas, Offset(13.5 * cellSize, 8.5 * cellSize), cellSize * 0.4, Colors.amber);
    _drawStar(canvas, Offset(6.5 * cellSize, 13.5 * cellSize), cellSize * 0.4, Colors.blue);

    // Centre du plateau (Triangles de victoire)
    final centerRect = Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize);
    // On dessine 4 triangles colorés au centre
    final pathRed = Path()..moveTo(6*cellSize, 6*cellSize)..lineTo(7.5*cellSize, 7.5*cellSize)..lineTo(6*cellSize, 9*cellSize)..close();
    final pathGreen = Path()..moveTo(6*cellSize, 6*cellSize)..lineTo(9*cellSize, 6*cellSize)..lineTo(7.5*cellSize, 7.5*cellSize)..close();
    final pathYellow = Path()..moveTo(9*cellSize, 6*cellSize)..lineTo(9*cellSize, 9*cellSize)..lineTo(7.5*cellSize, 7.5*cellSize)..close();
    final pathBlue = Path()..moveTo(6*cellSize, 9*cellSize)..lineTo(9*cellSize, 9*cellSize)..lineTo(7.5*cellSize, 7.5*cellSize)..close();

    canvas.drawPath(pathRed, Paint()..color = Colors.red);
    canvas.drawPath(pathGreen, Paint()..color = Colors.green);
    canvas.drawPath(pathYellow, Paint()..color = Colors.amber);
    canvas.drawPath(pathBlue, Paint()..color = Colors.blue);

    canvas.drawRect(centerRect, Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 2);

    // 4. Positionnement et affichage des pions des joueurs
    final homeOffsets = [
      [Offset(1.5, 1.5), Offset(4.5, 1.5), Offset(1.5, 4.5), Offset(4.5, 4.5)], // Rouge
      [Offset(10.5, 1.5), Offset(13.5, 1.5), Offset(10.5, 4.5), Offset(13.5, 4.5)], // Vert
      [Offset(10.5, 10.5), Offset(13.5, 10.5), Offset(10.5, 13.5), Offset(13.5, 13.5)], // Jaune/Bleu
      [Offset(1.5, 10.5), Offset(4.5, 10.5), Offset(1.5, 13.5), Offset(4.5, 13.5)], // Jaune/Bleu
    ];

    // Chemin global sur les 52 cases du pourtour (coordonnées en grille 15x15)
    final List<Offset> trackPath = [
      Offset(1, 6), Offset(2, 6), Offset(3, 6), Offset(4, 6), Offset(5, 6),
      Offset(6, 5), Offset(6, 4), Offset(6, 3), Offset(6, 2), Offset(6, 1), Offset(6, 0),
      Offset(7, 0),
      Offset(8, 0), Offset(8, 1), Offset(8, 2), Offset(8, 3), Offset(8, 4), Offset(8, 5),
      Offset(9, 6), Offset(10, 6), Offset(11, 6), Offset(12, 6), Offset(13, 6), Offset(14, 6),
      Offset(14, 7),
      Offset(14, 8), Offset(13, 8), Offset(12, 8), Offset(11, 8), Offset(10, 8), Offset(9, 8),
      Offset(8, 9), Offset(8, 10), Offset(8, 11), Offset(8, 12), Offset(8, 13), Offset(8, 14),
      Offset(7, 14),
      Offset(6, 14), Offset(6, 13), Offset(6, 12), Offset(6, 11), Offset(6, 10), Offset(6, 9),
      Offset(5, 8), Offset(4, 8), Offset(3, 8), Offset(2, 8), Offset(1, 8), Offset(0, 8),
      Offset(0, 7),
      Offset(0, 6),
    ];

    for (int p = 0; p < players.length; p++) {
      final player = players[p];

      for (int j = 0; j < player.pawns.length; j++) {
        final pos = player.pawns[j];
        Offset cellCoord;

        if (pos == -1) {
          // Dans la maison
          cellCoord = homeOffsets[p][j];
        } else if (pos <= 51) {
          // Sur le circuit extérieur
          final globalIndex = (player.start + pos) % 52;
          cellCoord = trackPath[globalIndex];
        } else if (pos < 57) {
          // Dans le couloir final
          final step = pos - 51;
          if (p == 0) cellCoord = Offset(step.toDouble(), 7.0);
          else if (p == 1) cellCoord = Offset(7.0, step.toDouble());
          else if (p == 2) cellCoord = Offset(14.0 - step, 7.0);
          else cellCoord = Offset(7.0, 14.0 - step);
        } else {
          // Au centre (Victoire)
          cellCoord = const Offset(7.0, 7.0);
        }

        final centerPos = Offset(cellCoord.dx * cellSize + cellSize / 2, cellCoord.dy * cellSize + cellSize / 2);
        final pawnRadius = cellSize * 0.35;

        // Dessin du pion
        canvas.drawCircle(centerPos, pawnRadius, Paint()..color = player.color);
        canvas.drawCircle(
          centerPos,
          pawnRadius,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2,
        );

        // Numéro du pion à l'intérieur
        final tp = TextPainter(
          text: TextSpan(
            text: '${j + 1}',
            style: TextStyle(color: Colors.white, fontSize: cellSize * 0.35, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(centerPos.dx - tp.width / 2, centerPos.dy - tp.height / 2));
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  @override
  bool shouldRepaint(covariant ClassicLudoBoardPainter oldDelegate) => true;
}
