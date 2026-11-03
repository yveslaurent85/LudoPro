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
        : tr('Joueur ${colorLabel(c)}', 'Player ${colorLabel(c)}');
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
                        ? tr('${_label(c)} : sans binôme', '${_label(c)}: no partner')
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

  String? get brokePlayer {
    if (!firebaseReady) return null;
    for (final s in seats) {
      final a = accounts[s];
      if (a != null && a.balance < stake + (capturePay ? captureAmount : 0)) {
        return a.name;
      }
    }
    return null;
  }

  Widget _stakePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JackpotBanner(),
        const SizedBox(height: 14),
        const Text(
          'Mise de chaque joueur (jetons)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        StakeField(
          stake: stake,
          players: seats.length,
          onChanged: (v) => setState(() => stake = v),
        ),
        _switch(
          'Captures payantes',
          'Chaque pion capturé rapporte de l\'argent au joueur qui capture, '
              'pris sur le solde du joueur capturé.',
          capturePay,
          (v) => setState(() => capturePay = v),
        ),
        if (capturePay) ...[
          Text(
            tr('Montant par capture (minimum ${Wallet.format(Wallet.minCapture)})',
                'Amount per capture (minimum ${Wallet.format(Wallet.minCapture)})'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in Wallet.captureAmounts)
                ChoiceChip(
                  label: Text('$v'),
                  selected: captureAmount == v,
                  onSelected: (_) => setState(() => captureAmount = v),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Chaque pion capturé : ${Wallet.format(captureAmount)} pris sur '
              'le solde du joueur capturé (ce qu\'il a, s\'il en a moins).',
              'Each captured pawn: ${Wallet.format(captureAmount)} taken from '
              'the captured player\'s balance (whatever they have, if less).',
            ),
            style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13),
          ),
        ],
      ],
    );
  }

  Future<void> _startGame() async {
    if (starting || stake < 0) return;
    String? localId;
    final uids = <String?>[null, null, null, null];

    if (firebaseReady) {
      setState(() => starting = true);
      try {
        final tokens = <String>[];
        for (final s in seats) {
          final a = accounts[s]!;
          uids[s] = a.uid;
          if (a.uid == FirebaseAuth.instance.currentUser?.uid) {
            final u = FirebaseAuth.instance.currentUser;
            tokens.add((await u?.getIdToken(true)) ?? '');
          } else {
            tokens.add(a.idToken ?? '');
          }
        }
        localId = await Wallet.startLocalGame(
          stake: stake,
          tokens: tokens,
          names: [for (final s in seats) accounts[s]!.name],
          game: 'ludo',
          capturePay: capturePay ? captureAmount : 0,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Wallet.errorText(e))),
        );
        return;
      }
      if (!mounted) return;
      setState(() => starting = false);
    }

    final rematch = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute<List<int>>(
        builder: (context) => LudoGame(
          numPlayers: numPlayers,
          pawnCount: startOut ? 2 : pawnCount,
          doorSafe: doorSafe,
          starSafe: starSafe,
          startOut: startOut,
          startDoor: startDoor,
          autoSecs: autoSecs,
          partners: teamMode ? List<int>.from(partners) : null,
          localGameId: localId,
          accountUids: uids,
          stake: firebaseReady ? stake : 0,
          capturePayLocal: (firebaseReady && capturePay) ? captureAmount : 0,
          names: [
            for (int i = 0; i < 4; i++)
              accounts[i]?.name ?? nameCtrls[i].text.trim(),
          ],
          avatars: List<IconData>.from(avatars),
        ),
      ),
    );
    if (!mounted) return;

    if (rematch != null && rematch.length >= 2) {
      await _rematch(rematch);
      return;
    }

    if (firebaseReady) {
      final u = FirebaseAuth.instance.currentUser;
      setState(() => accounts.removeWhere((k, _) => k != 0));
      if (u != null) _loadHost(u);
    }
  }

  Future<void> _rematch(List<int> accepted) async {
    final n = accepted.length;
    final newSeats = n == 2 ? [0, 2] : (n == 3 ? [0, 1, 2] : [0, 1, 2, 3]);
    final oldAcc = Map<int, PlayerAccount>.from(accounts);
    final oldAv = List<IconData>.from(avatars);
    final oldTxt = [for (final c in nameCtrls) c.text];
    setState(() {
      numPlayers = n;
      accounts.clear();
      for (int i = 0; i < n; i++) {
        final from = accepted[i];
        final to = newSeats[i];
        final a = oldAcc[from];
        if (a != null) accounts[to] = a;
        avatars[to] = oldAv[from];
        nameCtrls[to].text = oldTxt[from];
      }
      if (n != 4) {
        teamMode = false;
        _resetTeams();
      }
    });
    await _startGame();
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

  final Map<int, PlayerAccount> accounts = {};

  bool get allConnected =>
      !firebaseReady || seats.every((s) => accounts.containsKey(s));

  List<int> get seats =>
      numPlayers == 2 ? [0, 2] : (numPlayers == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

  @override
  void initState() {
    super.initState();
    nameCtrls = List.generate(4, (_) => TextEditingController());
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
    String? token;
    try {
      bal = await Wallet.ensure(FirebaseFirestore.instance, u);
      token = await u.getIdToken();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      accounts[0] = PlayerAccount(
        idToken: token,
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
      colorName: colorLabel(color),
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
                        label: Text(tr(
                          'Joueur ${colorLabel(color)} : se connecter',
                          'Player ${colorLabel(color)}: sign in',
                        )),
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
                          hintText: tr('Joueur ${colorLabel(color)}',
                              'Player ${colorLabel(color)}'),
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
              tooltip: tr('Changer de compte', 'Switch account'),
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
    void Function(int) onPick, {
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Column(
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
                      onTap: enabled ? () => onPick(v) : null,
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => optionsStep
                          ? setState(() => optionsStep = false)
                          : Navigator.of(context).pop(),
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
                if (!optionsStep) ...[
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
                    enabled: !startOut,
                  ),
                  if (startOut)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Position 54 : la partie se joue avec 2 pions chacun.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  if (firebaseReady) ...[
                    const SizedBox(height: 24),
                    _stakePicker(),
                  ],
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
                      "Les binômes ne se capturent pas.",
                      teamMode,
                      (v) => setState(() {
                        teamMode = v;
                        _resetTeams();
                      }),
                    ),
                  if (teamMode) _teamSection(),
                ] else ...[
                  Text(
                    tr('Options de jeu', 'Game options'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (!allConnected ||
                            !teamsReady ||
                            brokePlayer != null ||
                            starting)
                        ? null
                        : (optionsStep
                            ? _startGame
                            : () => setState(() => optionsStep = true)),
                    child: Text(
                      starting
                          ? 'Mise en cours...'
                          : !allConnected
                              ? 'Tous les joueurs doivent se connecter'
                              : (!teamsReady
                                  ? 'Forme les binômes'
                                  : (brokePlayer != null
                                      ? tr('Solde insuffisant : $brokePlayer',
                                          'Insufficient balance: $brokePlayer')
                                      : (!optionsStep
                                          ? tr('Suivant', 'Next')
                                          : firebaseReady
                                              ? (stake <= 0
                                                  ? 'Lancer · partie gratuite'
                                                  : tr(
                                                      'Lancer · mise ${Wallet.format(stake)}',
                                                      'Start · stake ${Wallet.format(stake)}'))
                                              : 'Lancer la partie'))),
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
// Le jeu (LudoGame complet)
// ----------------------------------------------------------------------

class LudoGame extends StatefulWidget {
  const LudoGame({
    super.key,
    this.numPlayers = 4,
    this.pawnCount = 4,
    this.doorSafe = true,
    this.starSafe = true,
    this.startOut = false,
    this.startDoor = false,
    this.autoSecs = 10,
    this.online,
    this.names,
    this.avatars,
    this.partners,
    this.localGameId,
    this.accountUids,
    this.stake = 0,
    this.capturePayLocal = 0,
  });

  final int numPlayers;
  final int pawnCount;
  final bool doorSafe;
  final bool starSafe;
  final bool startOut;
  final bool startDoor;
  final int autoSecs;
  final OnlineSession? online;
  final List<String>? names;
  final List<IconData>? avatars;
  final List<int>? partners;
  final String? localGameId;
  final List<String?>? accountUids;
  final int stake;
  final int capturePayLocal;

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
  static const Set<int> safeStars = {8, 21, 34, 47};
  static const Set<int> doorCells = {0, 13, 26, 39};

  Set<int> get safeCells => {
        if (widget.doorSafe) ...doorCells,
        if (widget.starSafe) ...safeStars,
      };

  final Random random = Random();
  late int numPlayers = widget.numPlayers;
  late int pawnCount = widget.pawnCount;

  int _startPosOf(int i) =>
      widget.startOut ? 43 + (i % 2) : (widget.startDoor ? 0 : -1);

  final Set<int> forfeited = {};
  int? winnerOverride;
  bool away = false
