import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'admin_dashboard.dart';
import 'base_logos.dart';
import 'deposit_screen.dart';
import 'transfer_screen.dart';
import 'deux_des.dart';
import 'game_chat.dart';
import 'dice3d.dart';
import 'jackpot_live.dart';
import 'lang.dart';
import 'online.dart';
import 'online_screen.dart';
import 'painters.dart';
import 'rejouer.dart';
import 'promo_screen.dart';
import 'password_screen.dart';
import 'player_stats.dart';
import 'update_check.dart';
import 'stake_field.dart';
import 'firebase_web.dart';
import 'songo.dart';
import 'rules.dart';
import 'whatsapp_group.dart';

/// Vrai si Firebase a démarré correctement (sinon : pas de jeu en ligne).
bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: kIsWeb ? kWebFirebaseOptions : null,
    );
    firebaseReady = true;
  } catch (_) {
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
      title: 'Katika Dés et Ludo by CKY',
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
// Sons
// ----------------------------------------------------------------------

class Sfx {
  bool enabled = true;

  void _play(String file, [double volume = 1.0]) {
    if (!enabled) return;
    try {
      final player = AudioPlayer();
      var closed = false;
      void close() {
        if (closed) return;
        closed = true;
        try {
          player.dispose();
        } catch (_) {}
      }

      player.onPlayerComplete.first.then((_) => close(), onError: (_) => close());
      player.play(AssetSource(file), volume: volume).catchError((Object _) {
        close();
      });
      Future<void>.delayed(const Duration(seconds: 8), close);
    } catch (_) {}
  }

  void step() => _play('sfx_step.wav', 0.6);
  void land() => _play('sfx_land.wav');
  void deny() => _play('sfx_deny.wav', 0.8);
  void capture() => _play('sfx_capture.wav');
  void arrive() => _play('sfx_arrive.wav');
  void win() => _play('sfx_win.wav');
  void roll() => _play('sfx_roll.wav');
  void six() => _play('sfx_six.wav');

  void dispose() {}
}

// ----------------------------------------------------------------------
// Modèles
// ----------------------------------------------------------------------

class Player {
  final String display;
  final Color color;
  final Color lightColor;
  final int start;
  IconData avatar;
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
// Écran d'accueil
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
  final String? image;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    this.image,
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
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
              child: image == null
                  ? Icon(icon, color: Colors.white, size: 30)
                  : Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        image!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) =>
                            Icon(icon, color: Colors.white, size: 30),
                      ),
                    ),
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

  final bool resumable;

  void _requireLogin(BuildContext context, Widget Function(BuildContext) page) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => loggedIn ? page(c) : OnlineScreen(onSignedIn: page),
      ),
    );
  }

  void _openMenu(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1B66),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        void go(Widget Function(BuildContext) page) {
          Navigator.of(sheetCtx).pop();
          _requireLogin(context, page);
        }

        Widget item(IconData icon, String label, Color color, VoidCallback f) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: f,
                icon: Icon(icon),
                label: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(color: const Color(0xFFFFC21A)),
                  ),
                  child: user == null
                      ? const Text(
                          'Connecte-toi pour voir ton solde',
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        )
                      : Column(
                          children: [
                            const Text(
                              'Mon solde',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            StreamBuilder<int>(
                              stream: Wallet.watch(user.uid),
                              builder: (context, snap) {
                                return GestureDetector(
                                  onLongPress: () {
                                    final email = FirebaseAuth
                                        .instance.currentUser?.email
                                        ?.trim()
                                        .toLowerCase();

                                    if (email == 'ychachouang@gmail.com') {
                                      showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF0B2FA6),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          title: const Text(
                                            'Katika',
                                            style: TextStyle(
                                              color: Color(0xFFFFE082),
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 140,
                                                height: 140,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        const Color(0xFFFFE082),
                                                    width: 3,
                                                  ),
                                                ),
                                                child: ClipOval(
                                                  child: Image.asset(
                                                    'assets/createur.jpg',
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, __, ___) =>
                                                            const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                      size: 80,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              const Text(
                                                'Créateur et concepteur :\n'
                                                'Chachouang Kejouboui Yves',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(
                                                      dialogContext)
                                                  .pop(),
                                              child: const Text(
                                                'Fermer',
                                                style: TextStyle(
                                                  color: Color(0xFFFFE082),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                  child: Text(
                                    '💰 ${Wallet.format(snap.data ?? 0)}',
                                    style: const TextStyle(
                                      color: Color(0xFFFFE082),
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                ),
                item(Icons.add_card, 'Recharge', const Color(0xFF22B14C),
                    () => go((_) => const DepositScreen())),
                item(
                    Icons.swap_horiz,
                    'Transférer de l\'argent',
                    const Color(0xFF00897B),
                    () => go((_) => const TransferScreen())),
                item(Icons.payments_outlined, 'Retrait', const Color(0xFF1E6BFF),
                    () {
                  Navigator.of(sheetCtx).pop();
                  showDialog<void>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Retrait'),
                      content: const Text(
                        'Le retrait vers Mobile Money arrive bientôt. '
                        'Tes gains de parrainage se transfèrent déjà vers '
                        'ton solde depuis « Code promo ».',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }),
                item(Icons.chat, 'Groupe WhatsApp', const Color(0xFF25D366), () {
                  Navigator.of(sheetCtx).pop();
                  openWhatsAppGroup(context);
                }),
                item(Icons.card_giftcard, 'Code promo',
                    const Color(0xFF8E24AA), () => go((_) => const PromoScreen())),
                if (user != null)
                  item(Icons.bar_chart, 'Détails', const Color(0xFF00838F),
                      () => go((_) => const MyDetailsScreen())),
                if (user != null)
                  item(Icons.lock_reset, 'Modifier le mot de passe',
                      const Color(0xFF455A9E),
                      () => go((_) => const PasswordScreen())),
                if (user != null)
                  item(Icons.logout, 'Se déconnecter', const Color(0xFFE5262B),
                      () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(sheetCtx).pop();
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (_) {}
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Tu es déconnecté.')),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

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
                const UpdateChecker(),
                const WhatsAppInvite(),
                if (!resumable)
                  Row(
                    children: [
                      if (firebaseReady)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () => _openMenu(context),
                          icon: const Icon(Icons.menu),
                          label: const Text(
                            'Menu',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      const Spacer(),
                      const LanguageSwitcher(),
                    ],
                  ),
                const Spacer(flex: 2),
                GestureDetector(
                  onLongPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminDashboard(),
                    ),
                  ),
                  child: const Text('👑', style: TextStyle(fontSize: 44)),
                ),
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
                  'Dés et Ludo by CKY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                    icon: Icons.grid_view_rounded,
                    image: 'assets/game_ludo.png',
                    title: 'Ludo',
                    subtitle: 'En présentiel ou en ligne',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => _LudoModePage(
                          onLocal: () => _openLocal(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    color: const Color(0xFFFFA000),
                    icon: Icons.casino,
                    image: 'assets/game_deuxdes.png',
                    title: 'Deux dés',
                    subtitle: 'Lance deux dés',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const DeuxDesPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    color: const Color(0xFF8D5A2B),
                    icon: Icons.workspaces,
                    image: 'assets/game_songo.png',
                    title: 'Songô',
                    subtitle: 'Jeu de graines · présentiel ou en ligne',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const SongoPage(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const WhatsAppGroupButton(),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LudoModePage extends StatelessWidget {
  const _LudoModePage({required this.onLocal});

  final VoidCallback onLocal;

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
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Text(
                      'Ludo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _ModeCard(
                  color: const Color(0xFF22B14C),
                  icon: Icons.groups,
                  title: 'En présentiel',
                  subtitle: 'Chaque joueur se connecte à son compte',
                  onTap: onLocal,
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
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int numPlayers = 4;
  int pawnCount = 4;
  bool doorSafe = true;
  bool starSafe = true;
  bool startOut = false;
  bool startDoor = false;
  int autoSecs = 10;
  int stake = Wallet.minStake;
  bool capturePay = false;
  int captureAmount = Wallet.minCapture;
  bool starting = false;
  bool optionsStep = false;

  bool teamMode = false;
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
    return t.isNotEmpty
        ? t
        : tr('Joueur ${colorLabel(c)}', 'Player${colorLabel(c)}');
  }

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
          tr('${_label(from)} : inviter qui ?', '${_label(from)}: invite who?'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in free)
              ListTile(
                leading: CircleAvatar(backgroundColor: colorList[f], radius: 12),
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
          tr('${_label(target)}, invitation !', "${_label(target)}, you're invited!"),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          tr(
            "${_label(from)} t'invite comme binôme. Tu acceptes ?",
            '${_label(from)} invites you as a partner. Do you accept?',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () =>
