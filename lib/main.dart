import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';
import 'online.dart';
import 'recharge.dart';
import 'deux_des.dart';

/// Vrai si Firebase a démarré correctement (sinon : pas de jeu en ligne).
bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    // L'appli s'ouvre quand même : le mode présentiel reste jouable.
    firebaseReady = false;
  }
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
      title: 'Katika',
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
  IconData avatar; // modifiable : le joueur choisit son avatar
  List<int> pawns = [-1, -1, -1, -1];

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
  const HomeScreen({super.key, this.resumable = false});

  /// Vrai quand une partie est en cours : on propose de la reprendre.
  final bool resumable;

  /// Présentiel : il faut d'abord être connecté à son compte.
  /// Si Firebase n'a pas démarré, on laisse jouer quand même.
  void _openLocal(BuildContext context) {
    final loggedIn =
        !firebaseReady || FirebaseAuth.instance.currentUser != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => loggedIn
            ? const SetupScreen()
            : OnlineScreen(onSignedIn: (context) => const SetupScreen()),
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
                        text: 'Kati',
                        style: _logoStyle(Colors.white, 52),
                      ),
                      TextSpan(
                        text: 'ka',
                        style: _logoStyle(const Color(0xFFFFC21A), 52),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ludo et Dés',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (resumable)
                  _ModeCard(
                    color: const Color(0xFFE5262B),
                    icon: Icons.play_arrow,
                    title: 'Reprendre la partie',
                    subtitle: 'Le pilote automatique joue en attendant',
                    onTap: () => Navigator.of(context).pop(),
                  )
                else ...[
                  _ModeCard(
                    color: const Color(0xFF22B14C),
                    icon: Icons.groups,
                    title: 'En présentiel',
                    subtitle: 'Chaque joueur se connecte à son compte',
                    onTap: () => _openLocal(context),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    color: const Color(0xFF1E6BFF),
                    icon: Icons.public,
                    title: 'En ligne',
                    subtitle: 'Crée un compte pour jouer à distance',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const OnlineScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    color: const Color(0xFFFFA000),
                    icon: Icons.casino,
                    title: 'Deux dés',
                    subtitle: 'Lance deux dés',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const DeuxDesPage(),
                      ),
                    ),
                  ),
                ],
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
// Préparation de la partie : joueurs (compte + avatar) et pions
// ----------------------------------------------------------------------

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int numPlayers = 4;
  int pawnCount = 4;
  bool doorSafe = true; // protection des portes (cases de départ)
  bool starSafe = true; // protection des étoiles

  // --- Mode équipe (2 contre 2) ---------------------------------------
  bool teamMode = false;

  /// Binôme de chaque couleur (-1 = pas encore de binôme).
  final List<int> partners = [-1, -1, -1, -1];

  bool get teamsReady => !teamMode || partners.every((p) => p != -1);

  void _resetTeams() {
    for (int i = 0; i < 4; i++) {
      partners[i] = -1;
    }
  }

  String _label(int c) {
    if (accounts[c] != null) return accounts[c]!.name;
    final t = nameCtrls[c].text.trim();
    return t.isNotEmpty ? t : 'Joueur ${colorNames[c]}';
  }

  /// Le joueur [from] invite un autre joueur libre comme binôme.
  /// L'invité peut accepter ou refuser.
  Future<void> _invite(int from) async {
    final free = [
      for (final s in seats)
        if (s != from && partners[s] == -1) s,
    ];
    if (free.isEmpty) return;

    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14267A),
        title: Text(
          '${_label(from)} : inviter qui ?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in free)
              ListTile(
                leading:
                    CircleAvatar(backgroundColor: colorList[f], radius: 12),
                title: Text(
                  _label(f),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, f),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14267A),
        title: Text(
          '${_label(target)}, invitation !',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "${_label(from)} t'invite comme binôme. Tu acceptes ?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Refuser',
              style: TextStyle(color: Color(0xFFFF8A80)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accepter'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      setState(() {
        partners[from] = target;
        partners[target] = from;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_label(target)} a refusé le binôme avec ${_label(from)}.',
          ),
        ),
      );
    }
  }

  void _breakTeam(int c) {
    setState(() {
      final m = partners[c];
      partners[c] = -1;
      if (m != -1) partners[m] = -1;
    });
  }

  Widget _teamSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          'Binômes',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final c in seats)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                CircleAvatar(radius: 10, backgroundColor: colorList[c]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    partners[c] == -1
                        ? '${_label(c)} : sans binôme'
                        : '${_label(c)} + ${_label(partners[c])}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                partners[c] == -1
                    ? TextButton(
                        onPressed: () => _invite(c),
                        child: const Text('Inviter'),
                      )
                    : TextButton(
                        onPressed: () => _breakTeam(c),
                        child: const Text('Annuler'),
                      ),
              ],
            ),
          ),
      ],
    );
  }

  static const List<IconData> avatarChoices = [
    Icons.person,
    Icons.face,
    Icons.face_3,
    Icons.person_outline,
    Icons.sports_esports,
    Icons.pets,
    Icons.rocket_launch,
    Icons.star,
    Icons.emoji_emotions,
    Icons.android,
    Icons.local_fire_department,
    Icons.music_note,
  ];
  static const List<String> colorNames = ['Rouge', 'Vert', 'Bleu', 'Jaune'];
  static const List<Color> colorList = [
    Color(0xFFE5262B),
    Color(0xFF22B14C),
    Color(0xFF1E6BFF),
    Color(0xFFFFC21A),
  ];

  late final List<TextEditingController> nameCtrls;
  final List<IconData> avatars = [
    Icons.person,
    Icons.face,
    Icons.face_3,
    Icons.person_outline,
  ];

  /// Comptes connectés, indexés par couleur (0 = Rouge = joueur principal).
  final Map<int, PlayerAccount> accounts = {};

  /// Tous les joueurs de la partie sont connectés (ou Firebase absent).
  bool get allConnected =>
      !firebaseReady || seats.every((s) => accounts.containsKey(s));

  /// Couleurs utilisées selon le nombre de joueurs (comme dans LudoGame).
  List<int> get seats =>
      numPlayers == 2 ? [0, 2] : (numPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

  @override
  void initState() {
    super.initState();
    nameCtrls = List.generate(4, (_) => TextEditingController());
    // Le premier joueur est le compte déjà connecté.
    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) _loadHost(u);
    }
  }

  @override
  void dispose() {
    for (final c in nameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHost(User u) async {
    int bal = 0;
    try {
      bal = await Wallet.ensure(FirebaseFirestore.instance, u);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      accounts[0] = PlayerAccount(
        uid: u.uid,
        name: (u.displayName != null && u.displayName!.isNotEmpty)
            ? u.displayName!
            : (u.email ?? 'Joueur'),
        email: u.email ?? '',
        balance: bal,
      );
    });
  }

  Future<void> _connect(int color) async {
    final acc = await showPlayerLogin(
      context,
      colorName: colorNames[color],
      color: colorList[color],
    );
    if (acc == null || !mounted) return;
    final already = accounts.entries
        .any((e) => e.key != color && e.value.uid == acc.uid);
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce compte joue déjà dans la partie.')),
      );
      return;
    }
    setState(() => accounts[color] = acc);
  }

  Future<void> _pickAvatar(int color) async {
    final choice = await showDialog<IconData>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14267A),
        title: const Text(
          'Choisis ton avatar',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in avatarChoices)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, a),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: colorList[color],
                    child: Container(
                      decoration: a == avatars[color]
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                            )
                          : null,
                      alignment: Alignment.center,
                      child: Icon(a, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null) setState(() => avatars[color] = choice);
  }

  Widget _playerRow(int color) {
    final acc = accounts[color];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _pickAvatar(color),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorList[color],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(avatars[color], color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: acc != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withOpacity(0.12),
                      border: Border.all(color: colorList[color], width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '💰 ${Wallet.format(acc.balance)}',
                          style: const TextStyle(
                            color: Color(0xFFFFE082),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : (firebaseReady
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: colorList[color], width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _connect(color),
                        icon: const Icon(Icons.login),
                        label: Text(
                            'Joueur ${colorNames[color]} : se connecter'),
                      )
                    : TextField(
                        controller: nameCtrls[color],
                        maxLength: 12,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white),
                        cursorColor: const Color(0xFFFFC21A),
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          hintText: 'Joueur ${colorNames[color]}',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.12),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: Color(0xFFFFC21A), width: 2),
                          ),
                        ),
                      )),
          ),
          if (acc != null && color != 0)
            IconButton(
              tooltip: 'Changer de compte',
              onPressed: () => setState(() => accounts.remove(color)),
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _switch(String title, String subtitle, bool value,
      void Function(bool) onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFFFFC21A),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _picker(
    String title,
    List<int> values,
    int current,
    void Function(int) onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final v in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onPick(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: v == current
                            ? const Color(0xFFFFC21A)
                            : Colors.white.withOpacity(0.12),
                      ),
                      child: Text(
                        '$v',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: v == current
                              ? const Color(0xFF1A1F3A)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
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
            padding: const EdgeInsets.all(20),
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
                      'Préparer la partie',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _picker(
                  'Nombre de joueurs',
                  const [2, 3, 4],
                  numPlayers,
                  (v) => setState(() {
                    numPlayers = v;
                    if (v != 4) {
                      teamMode = false;
                      _resetTeams();
                    }
                  }),
                ),
                const SizedBox(height: 24),
                _picker(
                  'Nombre de pions par joueur',
                  const [1, 2, 3, 4],
                  pawnCount,
                  (v) => setState(() => pawnCount = v),
                ),
                const SizedBox(height: 24),
                Text(
                  firebaseReady
                      ? 'Joueurs (chacun se connecte à son compte)'
                      : 'Joueurs (touche le rond pour changer d\'avatar)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (final s in seats) _playerRow(s),
                if (numPlayers == 4)
                  _switch(
                    'Jouer en équipe (2 contre 2)',
                    "Les binômes ne se capturent pas. L'équipe gagne quand "
                        'les deux ont fini.',
                    teamMode,
                    (v) => setState(() {
                      teamMode = v;
                      _resetTeams();
                    }),
                  ),
                if (teamMode) _teamSection(),
                const SizedBox(height: 6),
                _switch(
                  'Protection des portes',
                  'Un pion sur une case de départ ne peut pas être capturé',
                  doorSafe,
                  (v) => setState(() => doorSafe = v),
                ),
                _switch(
                  "Protection des étoiles",
                  'Un pion sur une étoile ne peut pas être capturé',
                  starSafe,
                  (v) => setState(() => starSafe = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (!allConnected || !teamsReady)
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => LudoGame(
                                  numPlayers: numPlayers,
                                  pawnCount: pawnCount,
                                  doorSafe: doorSafe,
                                  starSafe: starSafe,
                                  partners: teamMode
                                      ? List<int>.from(partners)
                                      : null,
                                  names: [
                                    for (int i = 0; i < 4; i++)
                                      accounts[i]?.name ??
                                          nameCtrls[i].text.trim(),
                                  ],
                                  avatars: List<IconData>.from(avatars),
                                ),
                              ),
                            ),
                    child: Text(
                      !allConnected
                          ? 'Tous les joueurs doivent se connecter'
                          : (!teamsReady
                              ? 'Forme les binômes'
                              : 'Lancer la partie'),
                      style: const TextStyle(
                        fontSize: 17,
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

// ----------------------------------------------------------------------
// Jeu en ligne : création de compte / connexion
// (comptes gérés par Firebase Authentication)
// ----------------------------------------------------------------------

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, this.onSignedIn});

  /// Si renseigné (mode présentiel) : après la connexion, on ouvre
  /// directement cet écran à la place de celui-ci.
  final WidgetBuilder? onSignedIn;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final TextEditingController pseudoCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();

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

  String _errorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Cet e-mail est déjà utilisé.';
      case 'invalid-email':
        return 'E-mail invalide.';
      case 'weak-password':
        return 'Mot de passe trop faible (6 caractères minimum).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou mot de passe incorrect.';
      case 'too-many-requests':
        return "Trop d'essais. Réessaie dans quelques minutes.";
      case 'network-request-failed':
        return 'Pas de connexion internet.';
      case 'operation-not-allowed':
        return "La connexion par e-mail n'est pas activée dans Firebase.";
      default:
        return 'Erreur : $code';
    }
  }

  Future<void> _submit() async {
    if (!firebaseReady) {
      setState(() {
        errorText = "Le serveur en ligne n'est pas configuré dans l'appli.";
      });
      return;
    }

    final pseudo = pseudoCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final password = passCtrl.text;

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
        final cred = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await cred.user?.updateDisplayName(pseudo);
        await cred.user?.reload();
        // Création du compte d'argent (solde 0).
        if (cred.user != null) {
          try {
            await Wallet.ensure(
              FirebaseFirestore.instance,
              cred.user!,
              pseudo: pseudo,
            );
          } catch (_) {}
        }
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
      // Mode présentiel : connexion réussie, on passe à la préparation.
      final next = widget.onSignedIn;
      if (next != null && auth.currentUser != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: next),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => errorText = _errorMessage(e.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => errorText = 'Une erreur est survenue. Réessaie.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      user = null;
    });
  }

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

  Widget _banner(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black26,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: enabled
                ? const [Color(0xFF55E05A), Color(0xFF1B9E2B)]
                : const [Color(0xFF6B7396), Color(0xFF454C70)],
          ),
          border: Border.all(
            color: enabled ? const Color(0xFFFFD54F) : Colors.white24,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  List<Widget> _signedInView(User current) {
    final name =
        (current.displayName != null && current.displayName!.isNotEmpty)
            ? current.displayName!
            : (current.email ?? 'Joueur');

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white30),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFF22B14C),
              child: Icon(Icons.person, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connecté',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (current.email != null)
                    Text(
                      current.email!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      StreamBuilder<int>(
        stream: Wallet.watch(current.uid),
        builder: (context, snap) => _banner(
          Icons.account_balance_wallet,
          const Color(0xFFFFC21A),
          'Mon compte : ${Wallet.format(snap.data ?? 0)}\n'
          'La recharge sera disponible bientôt.',
        ),
      ),
      const SizedBox(height: 12),
      _primaryButton(
        'Recharger mon compte',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const RechargeScreen(),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _primaryButton(
        'Jouer en ligne',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const OnlineLobbyScreen(),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _primaryButton('Se déconnecter', _signOut),
    ];
  }

  List<Widget> _formView() {
    return [
      Row(
        children: [
          _tab('Créer un compte', creating, () {
            setState(() {
              creating = true;
              errorText = null;
            });
          }),
          const SizedBox(width: 10),
          _tab('Se connecter', !creating, () {
            setState(() {
              creating = false;
              errorText = null;
            });
          }),
        ],
      ),
      const SizedBox(height: 18),
      if (creating) ...[
        TextField(
          controller: pseudoCtrl,
          enabled: !busy,
          style: const TextStyle(color: Colors.white),
          cursorColor: const Color(0xFFFFC21A),
          decoration: _field('Pseudo', Icons.person),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: emailCtrl,
        enabled: !busy,
        style: const TextStyle(color: Colors.white),
        cursorColor: const Color(0xFFFFC21A),
        keyboardType: TextInputType.emailAddress,
        decoration: _field('E-mail', Icons.email),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: passCtrl,
        enabled: !busy,
        style: const TextStyle(color: Colors.white),
        cursorColor: const Color(0xFFFFC21A),
        obscureText: hidePassword,
        decoration: _field(
          'Mot de passe',
          Icons.lock,
          suffix: IconButton(
            onPressed: () => setState(() => hidePassword = !hidePassword),
            icon: Icon(
              hidePassword ? Icons.visibility : Icons.visibility_off,
              color: Colors.white70,
            ),
          ),
        ),
      ),
      if (errorText != null) ...[
        const SizedBox(height: 12),
        Text(
          errorText!,
          style: const TextStyle(
            color: Color(0xFFFF8A80),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
      const SizedBox(height: 22),
      _primaryButton(
        busy
            ? 'Patiente...'
            : (creating ? 'Créer mon compte' : 'Me connecter'),
        busy ? null : _submit,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final current = user;
    final forLocal = widget.onSignedIn != null;

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
                    Text(
                      forLocal ? 'Connexion' : 'Jeu en ligne',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!firebaseReady)
                  _banner(
                    Icons.warning_amber_rounded,
                    const Color(0xFFFF8A65),
                    "Le serveur en ligne n'est pas configuré : Firebase n'a pas "
                    'démarré. Le mode présentiel reste disponible.',
                  )
                else if (current == null)
                  _banner(
                    Icons.info_outline,
                    const Color(0xFFFFC21A),
                    forLocal
                        ? 'Connecte-toi à ton compte avant de lancer une '
                            'partie en présentiel.'
                        : 'Crée un compte ou connecte-toi pour jouer en ligne.',
                  ),
                const SizedBox(height: 20),
                if (current != null)
                  ..._signedInView(current)
                else
                  ..._formView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Le jeu (présentiel)
// ----------------------------------------------------------------------

class LudoGame extends StatefulWidget {
  const LudoGame({
    super.key,
    this.numPlayers = 4,
    this.pawnCount = 4,
    this.doorSafe = true,
    this.starSafe = true,
    this.online,
    this.names,
    this.avatars,
    this.partners,
  });

  final int numPlayers;
  final int pawnCount;
  final bool doorSafe; // portes (cases de départ) protégées
  final bool starSafe; // étoiles protégées
  final OnlineSession? online; // null = jeu en présentiel

  /// Pseudos choisis, indexés par couleur (Rouge, Vert, Bleu, Jaune).
  /// Une chaîne vide = nom par défaut.
  final List<String>? names;

  /// Avatars choisis, indexés par couleur.
  final List<IconData>? avatars;

  /// Binôme de chaque couleur (-1 = aucun). null = pas de mode équipe.
  final List<int>? partners;

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
  // Cases étoiles (8 cases après chaque départ) et cases sûres (départs + étoiles)
  static const Set<int> safeStars = {8, 21, 34, 47};
  static const Set<int> doorCells = {0, 13, 26, 39};

  /// Cases protégées, selon les options choisies avant la partie.
  Set<int> get safeCells => {
        if (widget.doorSafe) ...doorCells,
        if (widget.starSafe) ...safeStars,
      };

  final Random random = Random();
  late int numPlayers = widget.numPlayers;
  late int pawnCount = widget.pawnCount;

  // --- Abandon et retour à l'accueil ----------------------------------
  /// Couleurs des joueurs qui ont abandonné (ils perdent la partie).
  final Set<int> forfeited = {};

  /// Gagnant désigné par abandon (null = gagnant normal par les pions).
  int? winnerOverride;

  /// Vrai quand le joueur est revenu à l'accueil : le jeu joue à sa place.
  bool away = false;

  /// Un lancer, un déplacement ou un glisser de dé est en cours.
  bool get _busy => isRolling || isMoving || flightPhase != 0 || diceDragging;

  // --- Jeu en ligne ---------------------------------------------------
  bool get isOnline => widget.online != null;
  int get _myColor => isOnline ? baseIdx[widget.online!.mySeat] : -1;
  bool get _isMyTurn => !isOnline || currentPlayer == _myColor;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _firstSnap = true;

  // --- Mode équipe (2 contre 2) ---------------------------------------
  /// Binôme d'une couleur (-1 = aucun).
  int _mateOf(int c) => widget.partners == null ? -1 : widget.partners![c];

  /// a et b sont-ils dans la même équipe ?
  bool _isMate(int a, int b) =>
      widget.partners != null && widget.partners![a] == b;

  /// « Anna & Paul » en mode équipe, sinon juste le nom.
  String teamLabel(int c) {
    final m = _mateOf(c);
    return m == -1 ? nameOf(c) : '${nameOf(c)} & ${nameOf(m)}';
  }

  /// Ce joueur a fini tous ses pions (utilisé en mode équipe seulement :
  /// son binôme continue de jouer, on saute son tour).
  bool _finishedAll(int c) =>
      widget.partners != null && players[c].pawns.every((x) => x == 56);

  /// Il ne reste qu'un camp en jeu (un joueur, ou deux binômes).
  bool get _oneSideLeft {
    final a = activeIdx;
    return a.length == 1 ||
        (widget.partners != null && a.length == 2 && _mateOf(a[0]) == a[1]);
  }

  /// Nom affiché pour une couleur (pseudo choisi, pseudo en ligne,
  /// « Joueur Rouge » sinon).
  String nameOf(int colorIndex) {
    final custom = widget.names;
    if (widget.online == null &&
        custom != null &&
        colorIndex < custom.length &&
        custom[colorIndex].isNotEmpty) {
      return custom[colorIndex];
    }
    final o = widget.online;
    if (o != null) {
      final seat = baseIdx.indexOf(colorIndex);
      if (seat >= 0 && seat < o.names.length) return o.names[seat];
    }
    return 'Joueur ${players[colorIndex].display}';
  }

  /// Couleur du gagnant (null tant que la partie n'est pas finie).
  int? get winnerColor {
    if (!gameOver) return null;
    if (winnerOverride != null) return winnerOverride;
    for (final i in activeIdx) {
      final pw = players[i].pawns;
      if (pw.isNotEmpty && pw.every((p) => p == 56)) return i;
    }
    return null;
  }

  /// Classement en direct : pions arrivés, puis progression.
  /// Le gagnant est toujours premier une fois la partie finie.
  List<int> get ranking {
    final list = [...activeIdx];
    list.sort((a, b) {
      final fa = players[a].finished;
      final fb = players[b].finished;
      if (fa != fb) return fb.compareTo(fa);
      return progressOf(players[b]).compareTo(progressOf(players[a]));
    });
    final w = winnerColor;
    if (w != null && list.remove(w)) list.insert(0, w);
    return list;
  }

  /// Appelé chaque seconde : si le joueur ne fait rien pendant
  /// [autoSeconds] secondes, le jeu joue à sa place.
  /// Quand le joueur est à l'accueil, le jeu joue au hasard, sans attendre.
  void _tickAutopilot() {
    if (!mounted) return;
    if (away && !gameOver) {
      _bgPlay();
      return;
    }
    if (!autoPilot || gameOver) {
      _idle = 0;
      return;
    }
    final busyNow = isRolling || isMoving || flightPhase != 0 || diceDragging;
    final sig = '$currentPlayer|$hasRolled|'
        '${players.map((p) => p.pawns.join(',')).join(';')}';
    if (busyNow || sig != _lastSig || !_isMyTurn) {
      _lastSig = sig;
      _idle = 0;
      return;
    }
    _idle++;
    if (_idle >= autoSeconds) {
      _idle = 0;
      _autoPlay();
    }
  }

  /// Joue un coup au hasard, sans animation (joueur à l'accueil).
  void _bgPlay() {
    if (!_isMyTurn || gameOver || _busy) return;

    if (!hasRolled) {
      final v = _rollValue();
      setState(() {
        dice = v;
        pendingDice = v;
        lastRoll[currentPlayer] = v;
        hasRolled = true;
        gameStarted = true;
        message = 'Pilotage automatique : $v.';
      });
      if (legalMoves().isEmpty) {
        if (v == 6) {
          setState(() {
            hasRolled = false;
            message = 'Un 6 ! Tu rejoues.';
          });
          _pushState();
        } else {
          nextTurn();
        }
      } else {
        _pushState();
      }
      return;
    }

    final legal = legalMoves();
    if (legal.isEmpty) {
      nextTurn();
      return;
    }
    movePawn(currentPlayer, legal[random.nextInt(legal.length)]);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  /// Retour à l'accueil : la partie reste en mémoire, le jeu joue au hasard
  /// à ta place jusqu'à ce que tu reviennes avec « Reprendre la partie ».
  Future<void> _goHome() async {
    if (gameOver) {
      Navigator.of(context).pop(); // partie finie : on quitte vraiment
      return;
    }
    if (_busy) {
      _snack('Attends la fin du coup en cours.');
      return;
    }
    _token++; // annule les suites d'animation en attente
    setState(() => away = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const HomeScreen(resumable: true),
      ),
    );
    if (!mounted) return;
    setState(() {
      away = false;
      _idle = 0;
    });
  }

  /// Abandon : le joueur qui abandonne perd la partie.
  /// À 2 joueurs, l'autre gagne. À 3 ou 4, il est éliminé et la partie continue.
  /// En mode équipe, c'est toute l'équipe qui perd.
  Future<void> abandonGame() async {
    if (gameOver) return;
    if (_busy) {
      _snack('Attends la fin du coup en cours.');
      return;
    }
    final who = isOnline ? _myColor : currentPlayer;
    if (forfeited.contains(who)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14267A),
        title: const Text(
          'Abandonner la partie ?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          widget.partners != null
              ? "${teamLabel(who)} perdront la partie."
              : '${nameOf(who)} perdra la partie.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Abandonner',
              style: TextStyle(color: Color(0xFFFF8A80)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || gameOver || _busy) return;
    if (forfeited.contains(who)) return;

    final mate = _mateOf(who);
    int next = who;

    setState(() {
      forfeited.add(who);
      players[who].pawns = List<int>.filled(pawnCount, -1);
      if (mate != -1) {
        forfeited.add(mate);
        players[mate].pawns = List<int>.filled(pawnCount, -1);
      }
      _token++;

      // Prochain joueur encore en jeu, dans l'ordre des tours
      final order = baseIdx;
      for (int k = 1; k <= order.length; k++) {
        final c = order[(order.indexOf(who) + k) % order.length];
        if (!forfeited.contains(c)) {
          next = c;
          break;
        }
      }

      if (_oneSideLeft) {
        winnerOverride = activeIdx.first;
        gameOver = true;
        message = '🏆 ${teamLabel(winnerOverride!)} gagne : '
            '${teamLabel(who)} a abandonné.';
      } else if (forfeited.contains(currentPlayer)) {
        currentPlayer = next;
        hasRolled = false;
        message = '${nameOf(who)} a abandonné. Au tour de ${nameOf(next)}.';
      } else {
        message = '${nameOf(who)} a abandonné.';
        if (hasRolled && legalMoves().isEmpty) _advanceTurn();
      }
    });
    _pushState();
  }

  /// Face aléatoire avec un 6 plus fréquent : 30 % de chances
  /// (45 % si tous les pions du joueur sont encore à la base).
  /// Pour régler la difficulté, change les deux pourcentages ci-dessous.
  int _randomFace() {
    final allHome = players[currentPlayer].pawns.every((x) => x == -1);
    final sixChance = allHome ? 45 : 30;
    if (random.nextInt(100) < sixChance) return 6;
    return random.nextInt(5) + 1;
  }

  /// Valeur du prochain lancer. À l'arrivée, quand il ne reste qu'un pion
  /// à finir et qu'un seul lancer suffit, le joueur gagne en 5 lancers
  /// maximum : le 5e lancer donne exactement le nombre qu'il faut.
  int _rollValue() {
    final cp = currentPlayer;
    final left = players[cp].pawns.where((x) => x != 56).toList();
    if (left.length == 1 && left.first >= 0) {
      final remaining = 56 - left.first;
      if (remaining >= 1 && remaining <= 6) {
        if (finishThrows[cp] >= maxFinishThrows - 1) {
          finishThrows[cp] = 0;
          return remaining;
        }
        finishThrows[cp]++;
        return _randomFace();
      }
    }
    finishThrows[cp] = 0;
    return _randomFace();
  }

  void _autoPlay() {
    if (!_isMyTurn || gameOver) return;

    if (canRollNow) {
      // Le dé n'a pas été lancé : on le lance
      throwDice(_toRoot(diceKeys[currentPlayer]));
      return;
    }

    if (hasRolled && !isRolling && !isMoving && flightPhase == 0) {
      final legal = legalMoves();
      if (legal.isEmpty) return;

      // Priorité : capture > arrivée > sortir un pion > pion le plus avancé
      int score(int i) {
        final pos = players[currentPlayer].pawns[i];
        if (moveCaptures(i)) return 1000;
        if (pos != -1 && pos + dice == 56) return 500;
        if (pos == -1) return 300;
        return pos;
      }

      var best = legal.first;
      for (final i in legal) {
        if (score(i) > score(best)) best = i;
      }
      setState(() => message = 'Pilotage automatique : coup joué pour toi.');
      movePawn(currentPlayer, best);
    }
  }

  void _listenOnline() {
    final o = widget.online;
    if (o == null || !firebaseReady) return;
    _sub = FirebaseFirestore.instance
        .collection('games')
        .doc(o.gameId)
        .snapshots()
        .listen((snap) {
      final d = snap.data();
      if (d == null || !mounted) return;
      if (snap.metadata.hasPendingWrites) return;
      final first = _firstSnap;
      _firstSnap = false;
      if (!first && d['writer'] == o.uid) return; // c'est mon propre coup
      _applyRemote(d);
    });
  }

  void _applyRemote(Map<String, dynamic> d) {
    setState(() {
      for (int i = 0; i < 4; i++) {
        final l = d['p$i'];
        if (l is List) {
          players[i].pawns = l.map((e) => (e as num).toInt()).toList();
        }
      }
      currentPlayer = (d['cur'] as num?)?.toInt() ?? currentPlayer;
      hasRolled = d['hasRolled'] == true;
      dice = (d['dice'] as num?)?.toInt() ?? dice;
      final lr = d['lastRoll'];
      if (lr is List && lr.length == 4) {
        for (int i = 0; i < 4; i++) {
          lastRoll[i] = (lr[i] as num).toInt();
        }
      }
      final f = d['forfeited'];
      if (f is List) {
        forfeited
          ..clear()
          ..addAll(f.map((e) => (e as num).toInt()));
      }
      final w = (d['winner'] as num?)?.toInt() ?? -1;
      winnerOverride = w >= 0 ? w : null;
      message = (d['msg'] as String?) ?? message;
      gameOver = d['over'] == true;
      if (((d['rev'] as num?) ?? 0) > 0) gameStarted = true;
      isRolling = false;
      isMoving = false;
      diceDragging = false;
      flightPhase = 0;
    });
  }

  /// Envoie l'état du plateau aux autres joueurs.
  Future<void> _pushState() async {
    final o = widget.online;
    if (o == null || !firebaseReady) return;
    try {
      await FirebaseFirestore.instance.collection('games').doc(o.gameId).update({
        for (int i = 0; i < 4; i++) 'p$i': players[i].pawns,
        'cur': currentPlayer,
        'hasRolled': hasRolled,
        'dice': dice,
        'lastRoll': lastRoll,
        'msg': message,
        'over': gameOver,
        'forfeited': forfeited.toList(),
        'winner': winnerOverride ?? -1,
        'writer': o.uid,
        'rev': FieldValue.increment(1),
        if (gameOver) 'status': 'finished',
      });
    } catch (_) {
      // Connexion perdue : le prochain coup renverra l'état complet.
    }
  }

  /// Joueurs de la partie au départ : 2 = Rouge + Bleu (face à face),
  /// 3 = Rouge + Vert + Bleu, 4 = tous.
  List<int> get baseIdx => numPlayers == 2
      ? [0, 2]
      : (numPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

  /// Joueurs encore en jeu (sans ceux qui ont abandonné).
  List<int> get activeIdx =>
      baseIdx.where((i) => !forfeited.contains(i)).toList();

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
  bool autoPilot = true; // pilotage automatique si le joueur tarde
  final int autoSeconds = 10; // délai avant le pilotage automatique
  bool gameStarted = false; // devient vrai au premier lancer de dé
  final int maxFinishThrows = 5; // à l'arrivée : 5 lancers maximum
  final List<int> finishThrows = [0, 0, 0, 0];
  Timer? _autoTimer;
  String _lastSig = '';
  int _idle = 0;
  int stepMs = 170; // vitesse des pions (ms par case)
  DateTime? _lastBack; // dernier appui sur « retour » (double retour pour aller à l'accueil)

  // Animation d'arrivée à la maison
  int? arrivalColor; // couleur du joueur dont un pion vient d'arriver
  int arrivalKey = 0; // change à chaque arrivée pour relancer l'animation

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
    for (final p in players) {
      p.pawns = List<int>.filled(pawnCount, -1);
    }
    // Avatars choisis avant la partie
    final av = widget.avatars;
    if (av != null) {
      for (int i = 0; i < 4 && i < av.length; i++) {
        players[i].avatar = av[i];
      }
    }
    _listenOnline();
    _autoTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickAutopilot(),
    );
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
    _sub?.cancel();
    _autoTimer?.cancel();
    _pulse.dispose();
    _flight.dispose();
    sfx.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Règles du jeu
  // ---------------------------------------------------------------------

  /// Progression d'un joueur : somme des cases parcourues par ses pions,
  /// sur un total de (nombre de pions) x 56 cases.
  double progressOf(Player player) {
    int total = 0;
    for (final pos in player.pawns) {
      if (pos > 0) total += pos;
    }
    return total / (pawnCount * 56.0);
  }

  bool get canRollNow =>
      _isMyTurn &&
      !hasRolled &&
      !gameOver &&
      !isRolling &&
      !isMoving &&
      flightPhase == 0;

  bool canPawnMove(int position) {
    if (position == -1) return dice == 6;
    return position + dice <= 56;
  }

  /// Ce coup capture-t-il un pion adverse ? (jamais un pion du binôme)
  bool moveCaptures(int pawnIndex) {
    final player = players[currentPlayer];
    final from = player.pawns[pawnIndex];
    if (!canPawnMove(from)) return false;

    final target = from == -1 ? 0 : from + dice;
    if (target >= 51) return false;

    final absolutePosition = (player.start + target) % 52;
    if (safeCells.contains(absolutePosition)) return false;

    for (int p = 0; p < players.length; p++) {
      if (p == currentPlayer || _isMate(p, currentPlayer)) continue;
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
      for (int i = 0; i < player.pawns.length; i++)
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

    final newDice = _rollValue();
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
      gameStarted = true;
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
        message = dice == 6
            ? '6 ! Aucun déplacement possible, mais tu rejoues.'
            : '$dice ! Aucun déplacement possible.';
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
    _pushState();

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
      if (dice == 6) {
        // Un 6 donne toujours un nouveau lancer, même pendant la finition.
        setState(() {
          hasRolled = false;
          message = 'Un 6 ! Tu rejoues.';
        });
        _pushState();
      } else {
        nextTurn();
      }
    } else if (autoPlay && distinct.length == 1) {
      // Un seul choix possible : le jeu joue à ta place
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted || rollToken != _token) return;
      movePawn(currentPlayer, distinct.first);
    }
  }

  /// Passe au joueur suivant, en sautant ceux qui ont déjà fini
  /// tous leurs pions (mode équipe : leur binôme continue).
  void _advanceTurn() {
    final act = activeIdx;
    var next = currentPlayer;
    for (int k = 0; k < act.length; k++) {
      next = act[(act.indexOf(next) + 1) % act.length];
      if (!_finishedAll(next)) break;
    }
    currentPlayer = next;
    hasRolled = false;
    message = 'Touche ton dé ou glisse-le pour le lancer !';
  }

  void nextTurn() {
    setState(_advanceTurn);
    _pushState();
  }

  Future<void> movePawn(int playerIndex, int pawnIndex) async {
    if (!hasRolled ||
        gameOver ||
        isRolling ||
        isMoving ||
        flightPhase != 0 ||
        diceDragging ||
        playerIndex != currentPlayer ||
        forfeited.contains(playerIndex) ||
        !_isMyTurn) {
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
    // et jamais contre le binôme.
    if (newPosition < 51) {
      final absolutePosition = (player.start + newPosition) % 52;

      if (!safeCells.contains(absolutePosition)) {
        for (int p = 0; p < players.length; p++) {
          if (p == playerIndex || _isMate(p, playerIndex)) continue;

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

    // Victoire : seul, tous ses pions arrivés ; en équipe, les deux binômes.
    final mate = _mateOf(playerIndex);
    final selfDone = player.pawns.every((p) => p == 56);
    final won = selfDone &&
        (mate == -1 || players[mate].pawns.every((p) => p == 56));

    if (won) {
      sfx.win();
    } else if (captured) {
      sfx.capture();
    } else if (newPosition == 56) {
      sfx.arrive();
    }

    setState(() {
      isMoving = false;

      // Animation d'arrivée à la maison
      if (newPosition == 56) {
        arrivalColor = playerIndex;
        arrivalKey++;
      }

      if (won) {
        gameOver = true;
        message = '🏆 ${teamLabel(playerIndex)} remporte la partie !';
      } else if (selfDone) {
        // Il a fini, son binôme continue : on passe la main.
        _advanceTurn();
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
    _pushState();

    if (newPosition == 56) {
      final k = arrivalKey;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && k == arrivalKey) setState(() => arrivalColor = null);
      });
    }
  }

  /// Remet la partie à zéro (utilisé quand on change le nombre de joueurs
  /// ou de pions dans les paramètres, ou avec « Rejouer » en fin de partie).
  void restartGame() {
    if (isOnline) {
      setState(() => message = 'Pas de nouvelle partie en ligne.');
      return;
    }
    _token++; // annule les animations en attente
    _flight.stop();
    _flight.value = 0;
    setState(() {
      for (final player in players) {
        player.pawns = List<int>.filled(pawnCount, -1);
      }
      for (int i = 0; i < 4; i++) {
        lastRoll[i] = 1;
        finishThrows[i] = 0;
      }
      forfeited.clear();
      winnerOverride = null;
      arrivalColor = null;
      gameStarted = false;
      currentPlayer = 0;
      dice = 1;
      hasRolled = false;
      isRolling = false;
      isMoving = false;
      gameOver = false;
      diceDragging = false;
      flightPhase = 0;
      message = 'Touche ton dé ou glisse-le pour le lancer !';
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

    for (int i = 0; i < players[currentPlayer].pawns.length; i++) {
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
    final legal = (_isMyTurn &&
            hasRolled &&
            !isRolling &&
            !isMoving &&
            !gameOver &&
            flightPhase == 0)
        ? legalMoves()
        : <int>[];

    final entries = <_PawnEntry>[];
    for (final p in activeIdx) {
      for (int i = 0; i < players[p].pawns.length; i++) {
        // Un pion arrivé (56) reste visible dans sa base.
        final center = pawnCenter(p, i) ?? homeCenter(p, i);
        entries.add(_PawnEntry(p, i, center));
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
      final done = position == 56;
      final atHome = position == -1 || done;
      final stacked = n > 1 && !atHome;

      final w = (done ? c * 1.35 : (atHome ? c * 1.5 : c * 1.0)) *
          (stacked ? 0.8 : 1.0);
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
                done: done,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Explosion d'étincelles au centre du plateau quand un pion arrive à la maison.
  List<Widget> buildArrival(double c) {
    final a = arrivalColor;
    if (a == null || gameOver) return const <Widget>[];

    // Centre du triangle d'arrivée de chaque couleur (en cases)
    const xs = [6.75, 7.5, 8.25, 7.5];
    const ys = [7.5, 6.75, 7.5, 8.25];
    final size = c * 5.0;

    return [
      Positioned(
        left: xs[a] * c - size / 2,
        top: ys[a] * c - size / 2,
        width: size,
        height: size,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('arrival_$arrivalKey'),
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1300),
            builder: (context, t, child) => CustomPaint(
              painter: BurstPainter(t, players[a].color),
            ),
          ),
        ),
      ),
    ];
  }

  /// Couronne dans la base du gagnant + « Victoire » au centre du plateau.
  List<Widget> buildVictory(double c) {
    final w = winnerColor;
    if (w == null) return const <Widget>[];
    final winner = players[w];

    final rowStart = w < 2 ? 0 : 9;
    final colStart = (w == 0 || w == 3) ? 0 : 9;
    final crownBox = c * 3.2;

    return [
      // Couronne dans la case (base) du gagnant
      Positioned(
        left: (colStart + 3) * c - crownBox / 2,
        top: (rowStart + 3) * c - crownBox / 2,
        width: crownBox,
        height: crownBox,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.2, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Center(
              child: Text('👑', style: TextStyle(fontSize: c * 2.3)),
            ),
          ),
        ),
      ),
      // Bandeau « Victoire » au milieu du plateau
      Positioned(
        left: 7.5 * c - c * 4.0,
        top: 7.5 * c - c * 1.6,
        width: c * 8.0,
        height: c * 3.2,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(c * 0.7),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [shade(winner.color, 0.1), shade(winner.color, -0.15)],
                ),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VICTOIRE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: c * 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                      Text(
                        teamLabel(w),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: c * 0.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Katika décharge les caisses',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: c * 0.6,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget buildBoard(double size) {
    // Le cadre du plateau prend la couleur du joueur dont c'est le tour.
    final turnColor = players[currentPlayer].color;
    return Container(
      key: boardKey,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: turnColor, width: 5),
        boxShadow: [
          BoxShadow(
            color: turnColor.withOpacity(0.65),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
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
                        safeStars: widget.starSafe ? safeStars : const <int>{},
                        showDoorStars: widget.doorSafe,
                      ),
                    ),
                  ),
                  ...buildPawns(c),
                  ...buildArrival(c),
                  ...buildVictory(c),
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
              if (value == 'quit') abandonGame();
              if (value == 'home') _goHome();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'home',
                child: Text(
                  "Retour à l'accueil",
                  style: TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem<String>(
                value: 'quit',
                child: Text(
                  'Abandonner la partie',
                  style: TextStyle(color: Color(0xFFFF8A80)),
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
                      TextSpan(text: 'Kati', style: logoStyle(Colors.white)),
                      TextSpan(
                        text: 'ka',
                        style: logoStyle(const Color(0xFFFFC21A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Ludo et Dés',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    letterSpacing: 1.0,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events,
                  color: Color(0xFFFFC21A),
                  size: 22,
                ),
                const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline
                          ? 'Mode : En ligne'
                          : (widget.partners != null
                              ? 'Mode : Équipes 2v2'
                              : 'Mode : Présentiel'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$numPlayers Joueurs',
                      style: const TextStyle(
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

  /// Classement en direct, affiché sous l'en-tête pendant toute la partie.
  Widget buildRanking() {
    final order = ranking;
    const medals = ['🥇', '🥈', '🥉', '4️⃣'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          for (int k = 0; k < order.length; k++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(
                  color: players[order[k]].color.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: players[order[k]].color,
                    width: order[k] == currentPlayer && !gameOver ? 2 : 1,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${medals[k]} ${nameOf(order[k])} '
                    '${(progressOf(players[order[k]]) * 100).round()} %',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget playerBadge(int index, {required bool avatarOnRight}) {
    if (!activeIdx.contains(index)) return const SizedBox(height: 52);

    final player = players[index];
    final active = index == currentPlayer && !gameOver;
    final remaining = pawnCount - player.finished;
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
          nameOf(index),
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
              '$remaining pion${remaining > 1 ? 's' : ''}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          active ? '▶ À TOI · $percent %' : '$percent %',
          style: const TextStyle(
            color: Color(0xFFFFE082),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );

    // Le badge du joueur actif pulse et brille.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: player.color.withOpacity(active ? 0.6 : 0.3),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: active ? Colors.white : player.color.withOpacity(0.8),
            width: active ? 2.5 : 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: player.color.withOpacity(0.9),
                    blurRadius: 8 + _pulse.value * 14,
                    spreadRadius: 1 + _pulse.value * 3,
                  ),
                ]
              : null,
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
    if (!activeIdx.contains(p)) return const SizedBox(width: 52, height: 52);

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
      isScrollControlled: true,
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
              child: SingleChildScrollView(
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Pilotage automatique',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Si tu ne joues pas pendant $autoSeconds secondes, '
                        'le jeu joue à ta place',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      value: autoPilot,
                      onChanged: (value) => update(() => autoPilot = value),
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
                      'Nombre de pions par joueur',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in [1, 2, 3, 4])
                          ChoiceChip(
                            label: Text('$n'),
                            selected: pawnCount == n,
                            onSelected: isOnline
                                ? null
                                : (_) {
                                    update(() => pawnCount = n);
                                    restartGame();
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Nombre de joueurs',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in [2, 3, 4])
                          ChoiceChip(
                            label: Text('$n'),
                            selected: numPlayers == n,
                            // En mode équipe : toujours 4 joueurs.
                            onSelected: (isOnline || widget.partners != null)
                                ? null
                                : (_) {
                                    update(() => numPlayers = n);
                                    restartGame();
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Changer ces deux réglages remet la partie à zéro.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isOnline
                          ? 'Mode : en ligne'
                          : (widget.partners != null
                              ? 'Mode : équipes 2 contre 2 (même plateau)'
                              : 'Mode : en présentiel (tous les joueurs sur le même plateau)'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
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
                              _goHome();
                            },
                            child: const Text('Accueil'),
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
        title: const Text('Classement', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in ranking.map((i) => players[i]))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(radius: 10, backgroundColor: p.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        nameOf(players.indexOf(p)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    Text(
                      '${p.finished}/$pawnCount arrivés',
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
                // Bordure à la couleur du joueur dont c'est le tour
                border: Border.all(
                  color: gameOver ? Colors.white24 : player.color,
                  width: 2.5,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: player.color,
                    child: Icon(player.avatar, color: Colors.white, size: 18),
                  ),
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
                                text: nameOf(currentPlayer),
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
          if (!gameStarted) ...[
            const SizedBox(width: 8),
            roundButton(Icons.settings, showSettings),
          ],
          const SizedBox(width: 8),
          roundButton(Icons.bar_chart, showStats),
        ],
      ),
    );
  }

  /// Panneau de fin de match : gagnant + boutons Rejouer / Accueil.
  Widget buildEndPanel() {
    final w = winnerColor;
    final color = w == null ? const Color(0xFFFFC21A) : players[w].color;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 10,
      child: SafeArea(
        top: false,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Transform.translate(
            offset: Offset(0, (1 - v) * 140),
            child: Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: child),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1B66),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.7),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  w == null
                      ? '🏁 Partie terminée'
                      : '🏆 ${teamLabel(w)} remporte la partie !',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFC21A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (!isOnline) ...[
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22B14C),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: restartGame,
                          child: const Text('Rejouer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Accueil'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  /// Double retour : un 1er appui affiche un message, un 2e appui
  /// dans les 2 secondes ramène à l'accueil (la partie reste en mémoire).
  void _onBackPressed(bool didPop, Object? result) {
    if (didPop) return;
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      _goHome();
    } else {
      _lastBack = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Appuie encore sur retour pour aller à l'accueil"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackPressed,
      child: Scaffold(
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
                        constraints.maxHeight - 470,
                      ).clamp(180.0, 700.0).toDouble();

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          buildHeader(),
                          buildRanking(),
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
            // Fin de match : confettis + panneau de résultat
            if (gameOver)
              const Positioned.fill(
                child: IgnorePointer(child: _Confetti()),
              ),
            if (gameOver) buildEndPanel(),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Animation : confettis de fin de match
// ----------------------------------------------------------------------

const List<Color> _confettiColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
  Colors.white,
  Color(0xFFFF7AC6),
];

class _Piece {
  final double x;
  final double speed;
  final double phase;
  final double size;
  final double spin;
  final Color color;

  _Piece(Random r)
      : x = r.nextDouble(),
        speed = 0.6 + r.nextDouble() * 0.8,
        phase = r.nextDouble(),
        size = 6 + r.nextDouble() * 8,
        spin = 2 + r.nextDouble() * 6,
        color = _confettiColors[r.nextInt(_confettiColors.length)];
}

class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();
  final Random rnd = Random();
  late final List<_Piece> pieces = List.generate(80, (_) => _Piece(rnd));

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(pieces, ctrl.value),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double progress;

  _ConfettiPainter(this.pieces, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final y = t * (size.height + 40) - 20;
      final x = (p.x + sin(t * 6 + p.phase * 6) * 0.03) * size.width;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t * 2 * pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.55,
        ),
        Paint()..color = p.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

// ----------------------------------------------------------------------
// Animation : arrivée d'un pion à la maison
// ----------------------------------------------------------------------

class BurstPainter extends CustomPainter {
  final double t; // 0 -> 1
  final Color color;

  BurstPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final e = Curves.easeOut.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0).toDouble();

    // Deux anneaux qui s'étendent
    canvas.drawCircle(
      center,
      maxR * 0.9 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * fade + 1
        ..color = color.withOpacity(0.85 * fade),
    );
    canvas.drawCircle(
      center,
      maxR * 0.55 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.9 * fade),
    );

    // Étincelles qui partent dans toutes les directions
    for (int i = 0; i < 12; i++) {
      final ang = i * pi / 6;
      final r = maxR * (0.2 + 0.75 * e);
      final pos = center + Offset(cos(ang) * r, sin(ang) * r);
      canvas.drawCircle(
        pos,
        size.width * 0.035 * (1 - t) + 1.5,
        Paint()
          ..color = (i.isEven ? const Color(0xFFFFC21A) : Colors.white)
              .withOpacity(fade),
      );
    }

    // Étoile dorée au centre
    final starR = size.width * 0.14 * Curves.elasticOut.transform(min(1.0, t * 1.6));
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? starR : starR * 0.45;
      final a = -pi / 2 + i * pi / 5;
      final x = center.dx + r * cos(a);
      final y = center.dy + r * sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFC21A).withOpacity(fade.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant BurstPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
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
  final bool showDoorStars;

  BoardPainter({
    required this.colors,
    required this.lights,
    required this.track,
    required this.lanes,
    required this.starts,
    required this.safeStars,
    required this.showDoorStars,
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
        if (showDoorStars) {
          _drawStar(canvas, rect.center, c * 0.3, Paint()..color = Colors.white);
        }
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

    final lines = Pa
Aperçu tronqué pour fichier volumineux
