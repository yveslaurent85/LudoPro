import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }
  runApp(const LudoProApp());
}

Color shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(
        (hsl.lightness + amount).clamp(0.0, 1.0).toDouble(),
      )
      .toColor();
}

const Color navy = Color(0xFF061A66);
const Color gold = Color(0xFFFFC21A);

const List<Color> playerColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
];

const List<Color> playerLights = [
  Color(0xFFFFE3E5),
  Color(0xFFDDF8E6),
  Color(0xFFDFEAFF),
  Color(0xFFFFF3CC),
];

const List<String> playerNames = ['Rouge', 'Vert', 'Bleu', 'Jaune'];

const List<IconData> playerAvatars = [
  Icons.person,
  Icons.face,
  Icons.face_3,
  Icons.person_outline,
];

const List<int> playerStarts = [0, 13, 26, 39];

const BoxDecoration appBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1F5BFF),
      Color(0xFF0B2FA6),
      Color(0xFF061A66),
    ],
  ),
);

class LudoProApp extends StatelessWidget {
  const LudoProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E6BFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ================================================================
// ACCUEIL
// ================================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget modeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      color: color,
      elevation: 8,
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor: Colors.white24,
          radius: 27,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.white,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: appBackground,
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const Spacer(),
                const Text('👑', style: TextStyle(fontSize: 55)),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                    children: [
                      TextSpan(
                        text: 'Ludo',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: 'Pro',
                        style: TextStyle(color: gold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jouez • Gagnez • Amusez-vous !',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 45),
                modeCard(
                  context,
                  title: 'En présentiel',
                  subtitle: 'Jouez ensemble sur le même téléphone',
                  icon: Icons.groups,
                  color: const Color(0xFF159447),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GameSetupScreen(
                          online: false,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                modeCard(
                  context,
                  title: 'En ligne',
                  subtitle: 'Créer un compte ou se connecter',
                  icon: Icons.public,
                  color: const Color(0xFF174FC7),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnlineScreen(),
                      ),
                    );
                  },
                ),
                const Spacer(),
                const Text(
                  'LudoPro • Version de développement',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// CONFIGURATION AVANT LA PARTIE
// ================================================================

class GameSetupScreen extends StatefulWidget {
  final bool online;

  const GameSetupScreen({
    super.key,
    required this.online,
  });

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  int playerCount = 4;
  int pawnCount = 4;

  Widget choiceButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: selected ? gold : Colors.white12,
            foregroundColor: selected ? navy : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Préparer la partie'),
        backgroundColor: navy,
      ),
      body: Container(
        width: double.infinity,
        decoration: appBackground,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Icon(
                    Icons.sports_esports,
                    color: gold,
                    size: 65,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nombre de joueurs',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choisis combien de joueurs participeront.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final n in [2, 3, 4])
                      choiceButton(
                        label: '$n joueurs',
                        selected: playerCount == n,
                        onTap: () => setState(() => playerCount = n),
                      ),
                  ],
                ),
                const SizedBox(height: 30),
                const Text(
                  'Pions par joueur',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chaque joueur utilisera le nombre de pions choisi.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final n in [1, 2, 3, 4])
                      choiceButton(
                        label: '$n',
                        selected: pawnCount == n,
                        onTap: () => setState(() => pawnCount = n),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Récapitulatif',
                        style: TextStyle(
                          color: gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Mode : ${widget.online ? "En ligne" : "Présentiel"}'),
                      Text('Joueurs : $playerCount'),
                      Text('Pions par joueur : $pawnCount'),
                      Text('Total de pions : ${playerCount * pawnCount}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final seat in _selectedSeats(playerCount))
                            Chip(
                              avatar: CircleAvatar(
                                backgroundColor: playerColors[seat],
                              ),
                              label: Text(playerNames[seat]),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text(
                      'LANCER LA PARTIE',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (widget.online) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'La configuration est prête. '
                              'Les salles et les parties à distance '
                              'doivent encore être développées.',
                            ),
                          ),
                        );
                        return;
                      }

                      Navigator.pushReplacement(
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
                if (widget.online) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Le mode en ligne nécessite encore la création '
                    'des salles, les invitations et la synchronisation '
                    'des coups entre joueurs.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<int> _selectedSeats(int count) {
  if (count == 2) return [0, 2];
  if (count == 3) return [0, 1, 2];
  return [0, 1, 2, 3];
}

// ================================================================
// CONNEXION FIREBASE
// ================================================================

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final pseudoCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool creating = true;
  bool hidePassword = true;
  bool busy = false;
  String? errorText;
  User? user;

  @override
  void initState() {
    super.initState();
    if (firebaseReady) {
      user = FirebaseAuth.instance.currentUser;
    }
  }

  @override
  void dispose() {
    pseudoCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  String errorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Cet e-mail est déjà utilisé.';
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'weak-password':
        return 'Le mot de passe doit contenir au moins 6 caractères.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou mot de passe incorrect.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessaie plus tard.';
      case 'network-request-failed':
        return 'Vérifie ta connexion internet.';
      case 'operation-not-allowed':
        return 'Active la connexion e-mail/mot de passe dans Firebase.';
      default:
        return 'Erreur : $code';
    }
  }

  Future<void> submit() async {
    if (!firebaseReady) {
      setState(() => errorText = 'Firebase ne démarre pas correctement.');
      return;
    }

    final email = emailCtrl.text.trim();
    final password = passCtrl.text;
    final pseudo = pseudoCtrl.text.trim();

    if (creating && pseudo.isEmpty) {
      setState(() => errorText = 'Choisis un pseudo.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => errorText = 'E-mail invalide.');
      return;
    }
    if (password.length < 6) {
      setState(() => errorText = 'Mot de passe : 6 caractères minimum.');
      return;
    }

    setState(() {
      busy = true;
      errorText = null;
    });

    try {
      final auth = FirebaseAuth.instance;

      if (creating) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await credential.user?.updateDisplayName(pseudo);
        await credential.user?.reload();
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;

      setState(() {
        user = auth.currentUser;
        passCtrl.clear();
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => errorText = errorMessage(e.code));
    } catch (_) {
      if (mounted) {
        setState(() => errorText = 'Une erreur est survenue.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jeu en ligne'),
        backgroundColor: navy,
      ),
      body: Container(
        decoration: appBackground,
        width: double.infinity,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!firebaseReady)
                  const Text(
                    'Firebase ne démarre pas. Vérifie sa configuration.',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                if (user != null) ...[
                  const Icon(
                    Icons.account_circle,
                    color: gold,
                    size: 70,
                  ),
                  Text(
                    'Connecté : ${user!.displayName ?? user!.email ?? "Joueur"}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ton compte est prêt. Les salles multijoueurs '
                    'et les invitations doivent encore être développées.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GameSetupScreen(
                            online: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Configurer une partie en ligne'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: signOut,
                    child: const Text('Se déconnecter'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() {
                            creating = true;
                            errorText = null;
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: creating ? gold : Colors.white12,
                            foregroundColor: creating ? navy : Colors.white,
                          ),
                          child: const Text('Créer un compte'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() {
                            creating = false;
                            errorText = null;
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !creating ? gold : Colors.white12,
                            foregroundColor: !creating ? navy : Colors.white,
                          ),
                          child: const Text('Connexion'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (creating)
                    TextField(
                      controller: pseudoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pseudo',
                        filled: true,
                        fillColor: Colors.white12,
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  if (creating) const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Adresse e-mail',
                      filled: true,
                      fillColor: Colors.white12,
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      filled: true,
                      fillColor: Colors.white12,
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => hidePassword = !hidePassword,
                        ),
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: busy || !firebaseReady ? null : submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Text(
                      busy
                          ? 'Patiente...'
                          : creating
                              ? 'Créer mon compte'
                              : 'Me connecter',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// MODÈLE JOUEUR
// ================================================================

class Player {
  final int seat;
  final int start;
  final List<int> pawns;

  Player({
    required this.seat,
    required int pawnCount,
  })  : start = playerStarts[seat],
        pawns = List<int>.filled(pawnCount, -1);

  String get display => playerNames[seat];
  Color get color => playerColors[seat];
  Color get lightColor => playerLights[seat];
  IconData get avatar => playerAvatars[seat];

  int get finished => pawns.where((p) => p == 56).length;
}

// ================================================================
// PARTIE DE LUDO
// ================================================================

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

class _LudoGameState extends State<LudoGame>
    with TickerProviderStateMixin {
  static const Set<int> safeCells = {
    0, 8, 13, 21, 26, 34, 39, 47,
  };

  final Random random = Random();

  late final List<Player> players;
  late final AnimationController pulse;

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

  int currentPlayer = 0;
  int dice = 1;
  bool hasRolled = false;
  bool isMoving = false;
  bool gameOver = false;
  bool forcedCapture = true;
  bool autoPlay = true;
  int stepMs = 170;
  String message = 'Lance le dé pour commencer !';

  @override
  void initState() {
    super.initState();

    players = [
      for (final seat in _selectedSeats(widget.playerCount))
        Player(seat: seat, pawnCount: widget.pawnCount),
    ];

    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  List<List<int>> homeLane(int seat) {
    switch (seat) {
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

  bool canMove(int position) {
    if (position == -1) return dice == 6;
    return position >= 0 && position + dice <= 56;
  }

  int targetPosition(Player player, int position) {
    final target = position == -1 ? 0 : position + dice;
    return (player.start + target) % 52;
  }

  bool captures(int playerIndex, int pawnIndex) {
    final player = players[playerIndex];
    final position = player.pawns[pawnIndex];

    if (!canMove(position)) return false;

    final target = position == -1 ? 0 : position + dice;
    if (target >= 51) return false;

    final absolute = targetPosition(player, position);

    if (safeCells.contains(absolute)) return false;

    for (int p = 0; p < players.length; p++) {
      if (p == playerIndex) continue;

      for (final opponentPosition in players[p].pawns) {
        if (opponentPosition >= 0 &&
            opponentPosition < 51 &&
            (players[p].start + opponentPosition) % 52 == absolute) {
          return true;
        }
      }
    }
    return false;
  }

  List<int> legalMoves() {
    final player = players[currentPlayer];

    final moves = [
      for (int i = 0; i < player.pawns.length; i++)
        if (canMove(player.pawns[i])) i,
    ];

    final captureMoves = moves
        .where((i) => captures(currentPlayer, i))
        .toList();

    if (forcedCapture && captureMoves.isNotEmpty) {
      return captureMoves;
    }

    return moves;
  }

  List<double> homeCenter(int seat, int index) {
    final rowStart = seat < 2 ? 0 : 9;
    final colStart = (seat == 0 || seat == 3) ? 0 : 9;
    final row = index < 2 ? 1.75 : 4.25;
    final col = index.isEven ? 1.75 : 4.25;

    return [rowStart + row, colStart + col];
  }

  List<double>? pawnCenter(int playerIndex, int pawnIndex) {
    final player = players[playerIndex];
    final position = player.pawns[pawnIndex];

    if (position == 56) return null;

    if (position == -1) {
      return homeCenter(player.seat, pawnIndex);
    }

    final cell = position >= 51
        ? homeLane(player.seat)[position - 51]
        : track[(player.start + position) % 52];

    return [cell[0] + 0.5, cell[1] + 0.5];
  }

  Future<void> rollDice() async {
    if (hasRolled || gameOver || isMoving) return;

    setState(() {
      dice = random.nextInt(6) + 1;
      hasRolled = true;
      message = 'Résultat : $dice';
    });

    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted || gameOver) return;

    final legal = legalMoves();

    if (legal.isEmpty) {
      setState(() => message = 'Aucun déplacement possible.');

      await Future.delayed(const Duration(milliseconds: 700));

      if (mounted && !gameOver) nextTurn();
      return;
    }

    final distinctPositions = legal
        .map((i) => players[currentPlayer].pawns[i])
        .toSet();

    if (autoPlay && distinctPositions.length == 1 && legal.length == 1) {
      await movePawn(currentPlayer, legal.first);
    } else {
      setState(() {
        message = dice == 6
            ? 'Un 6 ! Choisis un pion.'
            : 'Choisis le pion à déplacer.';
      });
    }
  }

  Future<void> movePawn(int playerIndex, int pawnIndex) async {
    if (!hasRolled || isMoving || gameOver ||
        playerIndex != currentPlayer) {
      return;
    }

    final player = players[playerIndex];
    if (pawnIndex < 0 || pawnIndex >= player.pawns.length) return;

    final oldPosition = player.pawns[pawnIndex];

    if (!legalMoves().contains(pawnIndex)) {
      setState(() {
        message = oldPosition == -1 && dice != 6
            ? 'Il faut obtenir un 6 pour sortir ce pion.'
            : 'Déplacement impossible.';
      });
      return;
    }

    setState(() => isMoving = true);

    if (oldPosition == -1) {
      setState(() => player.pawns[pawnIndex] = 0);
      await Future.delayed(Duration(milliseconds: stepMs + 80));
    } else {
      for (int step = 1; step <= dice; step++) {
        if (!mounted) return;

        setState(() {
          player.pawns[pawnIndex] = oldPosition + step;
        });

        await Future.delayed(Duration(milliseconds: stepMs));
      }
    }

    if (!mounted) return;

    final newPosition = player.pawns[pawnIndex];
    bool captured = false;

    if (newPosition < 51) {
      final absolute = (player.start + newPosition) % 52;

      if (!safeCells.contains(absolute)) {
        for (int p = 0; p < players.length; p++) {
          if (p == playerIndex) continue;

          for (int i = 0; i < players[p].pawns.length; i++) {
            final opponent = players[p].pawns[i];

            if (opponent >= 0 &&
                opponent < 51 &&
                (players[p].start + opponent) % 52 == absolute) {
              players[p].pawns[i] = -1;
              captured = true;
            }
          }
        }
      }
    }

    final won = player.pawns.every((position) => position == 56);

    setState(() {
      isMoving = false;

      if (won) {
        gameOver = true;
        message = '🏆 ${player.display} remporte la partie !';
      } else if (dice == 6 || captured || newPosition == 56) {
        hasRolled = false;
        message = captured
            ? 'Capture ! Tu rejoues.'
            : newPosition == 56
                ? 'Un pion est arrivé ! Tu rejoues.'
                : 'Un 6 ! Tu rejoues.';
      } else {
        nextTurnInternal();
      }
    });
  }

  void nextTurnInternal() {
    currentPlayer = (currentPlayer + 1) % players.length;
    hasRolled = false;
    message = 'Au tour de ${players[currentPlayer].display} : lance le dé.';
  }

  void nextTurn() {
    setState(nextTurnInternal);
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
      hasRolled = false;
      isMoving = false;
      gameOver = false;
      message = 'Nouvelle partie ! Lance le dé.';
    });
  }

  void onBoardTap(Offset position, double cellSize) {
    if (!hasRolled || isMoving || gameOver) return;

    final row = position.dy / cellSize;
    final col = position.dx / cellSize;

    final legal = legalMoves();
    int? bestPawn;
    double bestDistance = 1.8;

    for (int i = 0; i < players[currentPlayer].pawns.length; i++) {
      final center = pawnCenter(currentPlayer, i);
      if (center == null) continue;

      final dr = center[0] - 0.2 - row;
      final dc = center[1] - col;
      final distance = sqrt(dr * dr + dc * dc);

      if (legal.contains(i) && distance < bestDistance) {
        bestDistance = distance;
        bestPawn = i;
      }
    }

    if (bestPawn != null) {
      movePawn(currentPlayer, bestPawn);
    }
  }

  // ==============================================================
  // PIONS
  // ==============================================================

  List<Widget> buildPawns(double cellSize) {
    final widgets = <Widget>[];

    for (int p = 0; p < players.length; p++) {
      for (int i = 0; i < players[p].pawns.length; i++) {
        final center = pawnCenter(p, i);
        if (center == null) continue;

        final position = players[p].pawns[i];
        final atHome = position == -1;
        final size = atHome ? cellSize * 0.75 : cellSize * 0.58;

        final movable = p == currentPlayer &&
            !gameOver &&
            hasRolled &&
            !isMoving &&
            legalMoves().contains(i);

        widgets.add(
          AnimatedPositioned(
            key: ValueKey('pawn_${p}_$i'),
            duration: Duration(milliseconds: stepMs),
            curve: Curves.easeOut,
            left: center[1] * cellSize - size / 2,
            top: center[0] * cellSize - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, child) => Transform.scale(
                  scale: movable ? 1 + pulse.value * 0.12 : 1,
                  child: child,
                ),
                child: CustomPaint(
                  painter: PawnPainter(
                    color: players[p].color,
                    highlight: movable,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget buildBoard(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 15,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxWidth / 15;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  onBoardTap(details.localPosition, cell),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: BoardPainter(track: track),
                    ),
                  ),
                  ...buildPawns(cell),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==============================================================
  // INTERFACE DES JOUEURS
  // ==============================================================

  Widget playerCard(int index) {
    final player = players[index];
    final active = currentPlayer == index && !gameOver;
    final remaining = player.pawns.length - player.finished;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: player.color.withOpacity(active ? 0.65 : 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? Colors.white : player.color,
          width: active ? 2.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: player.color,
            child: Icon(player.avatar, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.display,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$remaining pions',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.home, color: Colors.white),
          ),
          const Expanded(
            child: Text(
              '👑 LudoPro',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          IconButton(
            onPressed: showSettings,
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget buildStatus() {
    final player = players[currentPlayer];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Text(
            gameOver ? 'PARTIE TERMINÉE' : 'Au tour de ${player.display}',
            style: TextStyle(
              color: shade(player.color, 0.25),
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget buildDice() {
    final player = players
