import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
      home: const HomeScreen(),
    );
  }
}

// ----------------------------------------------------------------------
// Sons (désactivés pour l'instant)
// ----------------------------------------------------------------------

/// Sons désactivés pour l'instant : aucune extension audio n'est nécessaire.
/// Les appels dans le jeu sont déjà en place, on pourra les brancher plus tard.
class Sfx {
  bool enabled = true;

  void step() {}
  void land() {}
  void deny() {}
  void capture() {}
  void arrive() {}
  void win() {}
  void roll() {}
  void dispose() {}
}

// ----------------------------------------------------------------------
// Modèles
// ----------------------------------------------------------------------

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

// ----------------------------------------------------------------------
// Écran d'accueil : choix du mode de jeu
// ----------------------------------------------------------------------

const BoxDecoration _appBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

TextStyle _logoStyle(Color color, double size) {
  return TextStyle(
    color: color,
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    height: 1.0,
    shadows: const [
      Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
    ],
  );
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [shade(color, 0.08), shade(color, -0.12)],
          ),
          border: Border.all(color: Colors.white54, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
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
                  const SizedBox(height: 2),
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
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _appBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const Text('👑', style: TextStyle(fontSize: 44)),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Ludo',
                        style: _logoStyle(Colors.white, 52),
                      ),
                      TextSpan(
                        text: 'Pro',
                        style: _logoStyle(const Color(0xFFFFC21A), 52),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Jouez • Gagnez • Amusez-vous !',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                _ModeCard(
                  color: const Color(0xFF22B14C),
                  icon: Icons.groups,
                  title: 'En présentiel',
                  subtitle: 'Les joueurs jouent sur le même plateau',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LudoGame(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ModeCard(
                  color: const Color(0xFF1E6BFF),
                  icon: Icons.public,
                  title: 'En ligne',
                  subtitle: 'Crée un compte pour jouer à distance',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OnlineScreen(),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Jeu en ligne : création de compte / connexion
// (le serveur n'est pas encore branché : l'écran est prêt, pas le compte)
// ----------------------------------------------------------------------

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  bool creating = true;
  bool hidePassword = true;

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(0.12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFC21A), width: 2),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? const Color(0xFFFFC21A)
                : Colors.white.withOpacity(0.12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF1A1F3A) : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _appBackground,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Text(
                      'Jeu en ligne',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black26,
                    border: Border.all(
                      color: const Color(0xFFFFC21A),
                      width: 1.5,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFFFC21A)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Le serveur en ligne n'est pas encore branché. "
                          'Les comptes et les parties à distance seront '
                          'activés dès qu\'il sera prêt.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _tab('Créer un compte', creating, () {
                      setState(() => creating = true);
                    }),
                    const SizedBox(width: 10),
                    _tab('Se connecter', !creating, () {
                      setState(() => creating = false);
                    }),
                  ],
                ),
                const SizedBox(height: 18),
                if (creating) ...[
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFFFFC21A),
                    decoration: _field('Pseudo', Icons.person),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFFC21A),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _field('E-mail', Icons.email),
                ),
                const SizedBox(height: 12),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFFC21A),
                  obscureText: hidePassword,
                  decoration: _field(
                    'Mot de passe',
                    Icons.lock,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => hidePassword = !hidePassword),
                      icon: Icon(
                        hidePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Disponible dès que le serveur en ligne sera branché.',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF6B7396), Color(0xFF454C70)],
                      ),
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Text(
                      creating ? 'Créer mon compte' : 'Me connecter',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key});

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
  // Cases étoiles (8 cases après chaque départ) et cases sûres (départs + étoiles)
  static const Set<int> safeStars = {8, 21, 34, 47};
  static const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  final Random random = Random();
  final Sfx sfx = Sfx();
  late final AnimationController _pulse;
  late final AnimationController _flight;

  final GlobalKey rootKey = GlobalKey();
  final GlobalKey boardKey = GlobalKey();
  final List<GlobalKey> diceKeys = List.generate(4, (_) => GlobalKey());

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
  int dice = 1; // valeur du dernier lancer validé
  int pendingDice = 1; // valeur en cours de lancer
  final List<int> lastRoll = [1, 1, 1, 1]; // face affichée sur le dé de chaque joueur
  bool hasRolled = false;
  bool isRolling = false;
  bool isMoving = false;
  bool gameOver = false;
  bool soundOn = true;
  bool forcedCapture = true; // capture obligatoire
  bool autoPlay = true; // coup unique joué automatiquement
  int stepMs = 170; // vitesse des pions (ms par case)

  // Dé : glissement et lancer
  bool diceDragging = false;
  Offset dragPos = Offset.zero;
  int flightPhase = 0; // 0 = au repos, 1 = lancer, 2 = posé / retour
  Offset flightFrom = Offset.zero;
  Offset flightTo = Offset.zero;
  List<int> faceSeq = [1, 2, 3, 4, 5, 6];

  int _token = 0; // sert à annuler les animations en attente
  String message = 'Touche ton dé ou glisse-le pour le lancer !';

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
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _flight.dispose();
    sfx.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Règles du jeu
  // ---------------------------------------------------------------------

  /// Progression d'un joueur : somme des cases parcourues par ses 4 pions,
  /// sur un total de 4 x 56 cases.
  double progressOf(Player player) {
    int total = 0;
    for (final pos in player.pawns) {
      if (pos > 0) total += pos;
    }
    return total / 224.0;
  }

  bool get canRollNow =>
      !hasRolled && !gameOver && !isRolling && !isMoving && flightPhase == 0;

  bool canPawnMove(int position) {
    if (position == -1) return dice == 6;
    return position + dice <= 56;
  }

  /// Ce coup capture-t-il un pion adverse ?
  bool moveCaptures(int pawnIndex) {
    final player = players[currentPlayer];
    final from = player.pawns[pawnIndex];
    if (!canPawnMove(from)) return false;

    final target = from == -1 ? 0 : from + dice;
    if (target >= 51) return false;

    final absolutePosition = (player.start + target) % 52;
    if (safeCells.contains(absolutePosition)) return false;

    for (int p = 0; p < players.length; p++) {
      if (p == currentPlayer) continue;
      for (final pos in players[p].pawns) {
        if (pos >= 0 &&
            pos < 51 &&
            (players[p].start + pos) % 52 == absolutePosition) {
          return true;
        }
      }
    }
    return false;
  }

  /// Coups autorisés. Si une capture est possible, elle est obligatoire.
  List<int> legalMoves() {
    final player = players[currentPlayer];
    final all = <int>[
      for (int i = 0; i < 4; i++)
        if (canPawnMove(player.pawns[i])) i,
    ];
    final captures = all.where(moveCaptures).toList();
    return (forcedCapture && captures.isNotEmpty) ? captures : all;
  }

  /// Retire les coups équivalents (pions au même endroit).
  List<int> distinctMoves(List<int> legal) {
    final player = players[currentPlayer];
    final seen = <int>{};
    final result = <int>[];
    for (final i in legal) {
      if (seen.add(player.pawns[i])) result.add(i);
    }
    return result;
  }

  Offset _toRoot(GlobalKey key, [Offset local = Offset.zero]) {
    final root = rootKey.currentContext!.findRenderObject() as RenderBox;
    final box = key.currentContext!.findRenderObject() as RenderBox;
    return root.globalToLocal(box.localToGlobal(local));
  }

  // --- Dé : glisser puis lâcher, ou simplement toucher -------------------

  void onDicePanStart(int p) {
    if (p != currentPlayer || !canRollNow) return;
    final origin = _toRoot(diceKeys[p]);
    setState(() {
      diceDragging = true;
      dragPos = origin;
    });
  }

  void onDicePanUpdate(DragUpdateDetails details) {
    if (!diceDragging) return;
    setState(() {
      dragPos += details.delta;
    });
  }

  void onDicePanEnd() {
    if (!diceDragging) return;
    final from = dragPos;
    setState(() {
      diceDragging = false;
    });
    throwDice(from);
  }

  Future<void> throwDice(Offset from) async {
    if (!canRollNow) return;

    final newDice = random.nextInt(6) + 1;
    final rollToken = ++_token;

    const flyingSize = 64.0;
    final boardBox = boardKey.currentContext!.findRenderObject() as RenderBox;
    final boardCenter =
        _toRoot(boardKey, boardBox.size.center(Offset.zero));
    final jitter = Offset(
      random.nextDouble() * 60 - 30,
      random.nextDouble() * 60 - 30,
    );

    setState(() {
      isRolling = true;
      pendingDice = newDice;
      faceSeq = List<int>.generate(6, (i) => i + 1)..shuffle(random);
      flightPhase = 1;
      flightFrom = from;
      flightTo = boardCenter -
          const Offset(flyingSize / 2, flyingSize / 2) +
          jitter;
      message = 'Le dé roule...';
    });
    sfx.roll();

    _flight.duration = const Duration(milliseconds: 1000);
    await _flight.forward(from: 0);
    if (!mounted || rollToken != _token) return;

    setState(() {
      dice = newDice;
      lastRoll[currentPlayer] = newDice;
      isRolling = false;
      hasRolled = true;
      flightPhase = 2;
    });
    sfx.land();

    final legal = legalMoves();
    final distinct = distinctMoves(legal);
    final forced =
        forcedCapture && legal.isNotEmpty && moveCaptures(legal.first);

    setState(() {
      if (legal.isEmpty) {
        message = '$dice ! Aucun déplacement possible.';
      } else if (autoPlay && distinct.length == 1) {
        message = forced
            ? 'Capture obligatoire ! Coup joué automatiquement.'
            : 'Un seul coup possible : joué automatiquement.';
      } else if (forced) {
        message = 'Capture obligatoire : choisis le pion qui capture.';
      } else if (dice == 6) {
        message = 'Un 6 ! Sors un pion ou avance.';
      } else {
        message = 'Touche un pion pour le déplacer.';
      }
    });

    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted || rollToken != _token) return;

    // Le dé retourne devant son joueur
    setState(() {
      flightFrom = _toRoot(diceKeys[currentPlayer]);
    });
    _flight.duration = const Duration(milliseconds: 380);
    await _flight.reverse();
    if (!mounted || rollToken != _token) return;
    setState(() {
      flightPhase = 0;
    });

    if (legal.isEmpty) {
      sfx.deny();
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || rollToken != _token || gameOver) return;
      nextTurn();
    } else if (autoPlay && distinct.length == 1) {
      // Un seul choix possible : le jeu joue à ta place
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted || rollToken != _token) return;
      movePawn(currentPlayer, distinct.first);
    }
  }

  void _advanceTurn() {
    currentPlayer = (currentPlayer + 1) % players.length;
    hasRolled = false;
    message = 'Touche ton dé ou glisse-le pour le lancer !';
  }

  void nextTurn() => setState(_advanceTurn);

  Future<void> movePawn(int playerIndex, int pawnIndex) async {
    if (!hasRolled ||
        gameOver ||
        isRolling ||
        isMoving ||
        flightPhase != 0 ||
        diceDragging ||
        playerIndex != currentPlayer) {
      return;
    }

    final player = players[playerIndex];
    final oldPosition = player.pawns[pawnIndex];

    if (oldPosition == 56) return;

    final legal = legalMoves();
    if (!legal.contains(pawnIndex)) {
      String reason;
      if (oldPosition == -1 && dice != 6) {
        reason = 'Il faut un 6 pour sortir ce pion.';
      } else if (oldPosition >= 0 && oldPosition + dice > 56) {
        reason = 'Ce pion ne peut pas finir avec ce lancer.';
      } else {
        reason = 'Capture obligatoire : prends un pion adverse !';
      }
      sfx.deny();
      setState(() {
        message = reason;
      });
      return;
    }

    final token = _token;
    setState(() {
      isMoving = true;
    });

    if (oldPosition == -1) {
      sfx.step();
      setState(() {
        player.pawns[pawnIndex] = 0;
      });
      await Future.delayed(Duration(milliseconds: stepMs + 90));
      if (!mounted || token != _token) return;
    } else {
      // Le pion avance case par case
      for (int s = 1; s <= dice; s++) {
        sfx.step();
        setState(() {
          player.pawns[pawnIndex] = oldPosition + s;
        });
        await Future.delayed(Duration(milliseconds: stepMs));
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

    final won = player.pawns.every((p) => p == 56);

    if (won) {
      sfx.win();
    } else if (captured) {
      sfx.capture();
    } else if (newPosition == 56) {
      sfx.arrive();
    }

    setState(() {
      isMoving = false;

      if (won) {
        gameOver = true;
        message = '🏆 Joueur ${player.display} remporte la partie !';
      } else if (dice == 6 || captured || newPosition == 56) {
        hasRolled = false;
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
    _flight.stop();
    _flight.value = 0;
    setState(() {
      for (final player in players) {
        player.pawns.fillRange(0, 4, -1);
      }
      for (int i = 0; i < 4; i++) {
        lastRoll[i] = 1;
      }
      currentPlayer = 0;
      dice = 1;
      hasRolled = false;
      isRolling = false;
      isMoving = false;
      gameOver = false;
      diceDragging = false;
      flightPhase = 0;
      message = 'Nouvelle partie ! Touche ton dé pour commencer.';
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
    if (!hasRolled ||
        isRolling ||
        isMoving ||
        gameOver ||
        flightPhase != 0 ||
        diceDragging) {
      return;
    }

    final tapRow = pos.dy / c;
    final tapCol = pos.dx / c;
    final legal = legalMoves();

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

      if (legal.contains(i) && dist < bestDist) {
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
    final legal = (hasRolled &&
            !isRolling &&
            !isMoving &&
            !gameOver &&
            flightPhase == 0)
        ? legalMoves()
        : <int>[];

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

      final movable = e.p == currentPlayer && legal.contains(e.i);

      return AnimatedPositioned(
        key: ValueKey('pawn_${e.p}_${e.i}'),
        duration: Duration(milliseconds: min(140, stepMs)),
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

  Widget buildBoard(double size) {
    return Container(
      key: boardKey,
      width: size,
      height: size,
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
    );
  }

  TextStyle logoStyle(Color color) {
    return TextStyle(
      color: color,
      fontSize: 28,
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
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Row(
        children: [
          PopupMenuButton<String>(
            color: const Color(0xFF14267A),
            onSelected: (value) {
              if (value == 'new') restartGame();
              if (value == 'home') Navigator.of(context).pop();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'new',
                child: Text(
                  'Nouvelle partie',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem<String>(
                value: 'home',
                child: Text(
                  "Retour à l'accueil",
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
                const Text('👑', style: TextStyle(fontSize: 15)),
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
                      'Mode : Présentiel',
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
    final progress = progressOf(player);
    final percent = (progress * 100).round();

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

    // Anneau de progression autour de l'avatar
    final avatarWithRing = SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, child) => CircularProgressIndicator(
                value: value,
                strokeWidth: 3.5,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          avatar,
        ],
      ),
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
        const SizedBox(height: 2),
        Text(
          '$percent %',
          style: const TextStyle(
            color: Color(0xFFFFE082),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
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
              ? [info, const SizedBox(width: 6), avatarWithRing]
              : [avatarWithRing, const SizedBox(width: 6), info],
        ),
      ),
    );
  }

  Widget diceBox(int value, Color color, {bool glow = false}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withOpacity(0.85),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: CustomPaint(painter: DicePainter(value)),
    );
  }

  /// Le dé d'un joueur : on le touche pour lancer, ou on le glisse puis on le lâche.
  Widget diceSlot(int p) {
    final player = players[p];
    final isActive = p == currentPlayer && !gameOver;
    final canRoll = isActive && canRollNow && !diceDragging;
    final lifted = isActive && (diceDragging || flightPhase != 0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isActive
          ? () {
              if (canRollNow) throwDice(_toRoot(diceKeys[p]));
            }
          : null,
      onPanStart: isActive ? (details) => onDicePanStart(p) : null,
      onPanUpdate: isActive ? onDicePanUpdate : null,
      onPanEnd: isActive ? (details) => onDicePanEnd() : null,
      onPanCancel: isActive
          ? () {
              if (diceDragging) {
                setState(() {
                  diceDragging = false;
                });
              }
            }
          : null,
      child: SizedBox(
        key: diceKeys[p],
        width: 52,
        height: 52,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Transform.scale(
            scale: canRoll ? 1.0 + _pulse.value * 0.08 : 1.0,
            child: child,
          ),
          child: Opacity(
            opacity: lifted ? 0.25 : (isActive ? 1.0 : 0.5),
            child: diceBox(lastRoll[p], player.color, glow: canRoll),
          ),
        ),
      ),
    );
  }

  /// Le dé qui suit le doigt, puis qui roule sur le plateau.
  Widget buildFlyingDie() {
    final color = players[currentPlayer].color;

    if (diceDragging) {
      return Positioned(
        left: dragPos.dx,
        top: dragPos.dy,
        width: 58,
        height: 58,
        child: IgnorePointer(
          child: diceBox(lastRoll[currentPlayer], color, glow: true),
        ),
      );
    }

    if (flightPhase == 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _flight,
      builder: (context, child) {
        final t = _flight.value;
        final eased = Curves.easeOutCubic.transform(t);
        final pos = Offset.lerp(flightFrom, flightTo, eased)!;
        final rolling = flightPhase == 1;
        final bounce = rolling ? sin(t * pi * 4).abs() * (1 - t) * 26 : 0.0;
        final size = 52.0 + 12.0 * eased;
        final face = (rolling && t < 0.85)
            ? faceSeq[(t * 14).floor() % 6]
            : pendingDice;
        final turns = rolling ? t * 3 : 0.0;

        return Positioned(
          left: pos.dx,
          top: pos.dy - bounce,
          width: size,
          height: size,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: turns * 2 * pi,
              child: diceBox(face, color, glow: true),
            ),
          ),
        );
      },
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

  void showSettings() {
    const speeds = <String, int>{'Lente': 300, 'Normale': 170, 'Rapide': 90};

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14267A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void update(VoidCallback change) {
              setState(change);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paramètres',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Capture obligatoire',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        "Tu dois prendre un pion adverse quand c'est possible",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      value: forcedCapture,
                      onChanged: (value) =>
                          update(() => forcedCapture = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Coup unique automatique',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        "Le jeu joue à ta place quand il n'y a qu'un seul choix",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      value: autoPlay,
                      onChanged: (value) => update(() => autoPlay = value),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Vitesse des pions',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in speeds.entries)
                          ChoiceChip(
                            label: Text(entry.key),
                            selected: stepMs == entry.value,
                            onSelected: (_) =>
                                update(() => stepMs = entry.value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Mode : en présentiel (tous les joueurs sur le même plateau)',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              Navigator.of(this.context).pop();
                            },
                            child: const Text('Accueil'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22B14C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              restartGame();
                            },
                            child: const Text('Nouvelle partie'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
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
          roundButton(Icons.settings, showSettings),
          const SizedBox(width: 8),
          roundButton(Icons.bar_chart, showStats),
        ],
      ),
    );
  }

  Widget badgesRow(int left, int right) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: playerBadge(left, avatarOnRight: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: playerBadge(right, avatarOnRight: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget diceRow(int left, int right) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [diceSlot(left), diceSlot(right)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        key: rootKey,
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Container(
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boardSize = min(
                      constraints.maxWidth - 24,
                      constraints.maxHeight - 440,
                    ).clamp(180.0, 700.0).toDouble();

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        buildHeader(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [badgesRow(0, 1), diceRow(0, 1)],
                        ),
                        buildBoard(boardSize),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [diceRow(3, 2), badgesRow(3, 2)],
                        ),
                        buildStatusBar(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          buildFlyingDie(),
        ],
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
