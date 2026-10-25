import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:http/http.dart' as http;

import 'lang.dart';

/// Adresse de ton Worker Cloudflare (sans « / » à la fin).
/// À remplacer après la publication du Worker.
const String kWorkerUrl = 'https://katika-api.ychachouang.workers.dev';

/// Erreur renvoyée par le serveur (message lisible pour le joueur).
class WalletException implements Exception {
  final String message;
  WalletException(this.message);
  @override
  String toString() => message;
}

/// Un joueur connecté à son propre compte (avec son compte d'argent).
class PlayerAccount {
  final String uid;
  final String name;
  final String email;
  final int balance;

  /// Jeton de connexion, utilisé par le serveur pour débiter la mise d'un
  /// joueur connecté sur le même téléphone (mode présentiel).
  final String? idToken;

  const PlayerAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.balance,
    this.idToken,
  });
}

/// Compte de jetons de chaque joueur : document Firestore `users/{uid}`.
/// Le solde ne se modifie PAS depuis l'appli (voir les règles Firestore) :
/// crédit de départ, mises, gains et recharges passent par le serveur
/// (Cloud Functions).
class Wallet {
  static const String currency = 'FCFA';

  /// Jetons offerts à chaque compte.
  static const int welcomeBonus = 10000;

  /// Mise minimale, et mises proposées.
  static const int minStake = 100;
  /// 0 = partie gratuite.
  static const List<int> stakes = [0, 100, 200, 500, 1000, 2000, 5000];

  static String stakeLabel(int v) => v == 0 ? 'Gratuit' : '$v';

  /// Commission de l'application sur la cagnotte en ligne (doit être la même
  /// que COMMISSION_PERCENT dans worker.js).
  static const int commissionPercent = 5;

  /// Commission en présentiel, sur tous les jeux (Ludo et Deux dés). Doit être
  /// la même que COMMISSION_LOCAL_PERCENT dans worker.js.
  static const int commissionLocalPercent = 10;

  /// Gain du gagnant pour une cagnotte donnée (après commission).
  /// [local] = true : partie en présentiel (commission de 10 %).
  static int prize(int pot, {bool local = false}) =>
      pot *
      (100 - (local ? commissionLocalPercent : commissionPercent)) ~/
      100;

  static String format(int amount) => '$amount $currency';

  static DocumentReference<Map<String, dynamic>> _ref(
    FirebaseFirestore db,
    String uid,
  ) =>
      db.collection('users').doc(uid);

  /// Appelle une fonction du Worker avec le jeton de connexion du joueur.
  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body, {
    User? user,
  }) async {
    final u = user ?? FirebaseAuth.instance.currentUser;
    if (u == null) throw WalletException('Connexion requise.');
    final token = await u.getIdToken();
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$kWorkerUrl/$name'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw WalletException('Pas de connexion. Réessaie.');
    }
    Map<String, dynamic> j = {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {}
    if (res.statusCode != 200) {
      throw WalletException(
        (j['error'] as String?) ??
            tr('Erreur du serveur (${res.statusCode}).',
                'Server error (${res.statusCode}).'),
      );
    }
    final d = j['data'];
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  /// Message lisible à partir d'une erreur serveur.
  static String errorText(Object e) {
    if (e is WalletException) return e.message;
    return 'Pas de connexion. Réessaie.';
  }

  /// Crée le compte de jetons s'il n'existe pas (10 000 offerts) et renvoie
  /// le solde. Les comptes déjà existants reçoivent le crédit une seule fois.
  static Future<int> ensure(
    FirebaseFirestore db,
    User user, {
    String? pseudo,
    FirebaseApp? app,
  }) async {
    try {
      final res = await _call(
        'ensureWallet',
        <String, dynamic>{'pseudo': pseudo ?? user.displayName ?? ''},
        user: user,
      );
      final b = res['balance'];
      return b is num ? b.toInt() : 0;
    } catch (_) {
      // Serveur injoignable : on lit simplement le solde existant.
      try {
        final snap = await _ref(db, user.uid).get();
        final b = snap.data()?['balance'];
        return b is num ? b.toInt() : 0;
      } catch (_) {
        return 0;
      }
    }
  }

  /// Solde en direct (pour l'afficher et le voir changer).
  static Stream<int> watch(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) {
      final b = s.data()?['balance'];
      return b is num ? b.toInt() : 0;
    });
  }

  // --- Mises (toutes les opérations d'argent se font côté serveur) --------

  /// Partie en ligne : le joueur paie sa mise (idempotent).
  static Future<void> payStake(String gameId) async {
    await _call('payStake', <String, dynamic>{'gameId': gameId});
  }

  /// Partie en ligne pas encore commencée : quitter (ou annuler si on est
  /// le créateur) et récupérer sa mise.
  static Future<void> leaveGame(String gameId) async {
    await _call('leaveGame', <String, dynamic>{'gameId': gameId});
  }

  /// Fin d'une partie en ligne : le serveur verse la cagnotte au gagnant.
  static Future<void> settleOnline(String gameId) async {
    await _call('settleGame', <String, dynamic>{'gameId': gameId});
  }

  /// Présentiel : débite la mise de tous les joueurs connectés.
  /// [game] = 'ludo' ou 'deuxdes' (sert au tableau de bord administrateur).
  /// Renvoie l'identifiant de la partie côté serveur.
  static Future<String> startLocalGame({
    required int stake,
    required List<String> tokens,
    List<String> names = const [],
    String game = 'unknown',
  }) async {
    final res = await _call(
      'startLocalGame',
      <String, dynamic>{
        'stake': stake,
        'tokens': tokens,
        'names': names,
        'game': game,
      },
    );
    return res['id'] as String;
  }

  /// Présentiel : verse la cagnotte aux gagnants. Renvoie le jackpot gagné
  /// (0 si le jackpot n'est pas tombé).
  static Future<int> settleLocal(String id, List<String> winnerUids) async {
    final res = await _call(
      'settleLocalGame',
      <String, dynamic>{'id': id, 'winnerUids': winnerUids},
    );
    final j = res['jackpot'];
    return j is num ? j.toInt() : 0;
  }

  /// Présentiel : fin de partie avec les scores (règle aussi les paris).
  /// Renvoie { jackpot, bets }.
  static Future<Map<String, dynamic>> settleLocalFull(
  /// Tableau de bord administrateur : le serveur refuse tout compte qui
  /// n'est pas dans ADMIN_UIDS.
  static Future<Map<String, dynamic>> adminStats({int limit = 150}) {
    return _call('adminStats', <String, dynamic>{'limit': limit});
  }
    String id,
    List<String> winnerUids,
    List<int> scores,
  ) {
    return _call(
      'settleLocalGame',
      <String, dynamic>{
        'id': id,
        'winnerUids': winnerUids,
        'scores': scores,
      },
    );
  }

  /// Présentiel : crée un pari entre deux joueurs (les deux mises sont
  /// débitées tout de suite). Les jetons prouvent les deux comptes.
  static Future<void> localBet({
    required String id,
    required String type,
    required int amount,
    required String proposerToken,
    required String opponentToken,
    bool over7 = true,
  }) async {
    await _call('localBetCreate', <String, dynamic>{
      'id': id,
      'type': type,
      'amount': amount,
      'side': over7 ? 'over' : 'under',
      'proposerToken': proposerToken,
      'opponentToken': opponentToken,
    });
  }

  /// Montant actuel du jackpot (le seuil de déclenchement reste secret).
  static Stream<int> watchJackpot() {
    return FirebaseFirestore.instance
        .collection('app')
        .doc('jackpot')
        .snapshots()
        .map((s) {
      final p = s.data()?['pool'];
      return p is num ? p.toInt() : 0;
    });
  }

  /// Connexion d'un joueur "invité" sur le même téléphone, SANS déconnecter
  /// le joueur principal : on utilise une 2e instance Firebase.
  static Future<PlayerAccount> signInGuest(String email, String password) async {
    FirebaseApp app;
    try {
      app = Firebase.app('joueur');
    } catch (_) {
      app = await Firebase.initializeApp(
        name: 'joueur',
        options: Firebase.app().options,
      );
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final cred = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user!;
    int balance = 0;
    try {
      balance = await ensure(
        FirebaseFirestore.instanceFor(app: app),
        user,
        app: app,
      );
    } catch (_) {
      // Solde illisible : on laisse quand même jouer, solde affiché à 0.
    }
    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}
    final name = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.email ?? 'Joueur');
    final account = PlayerAccount(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      balance: balance,
      idToken: token,
    );
    await auth.signOut(); // la session invité n'est pas gardée
    return account;
  }
}

/// Bandeau « Jackpot » affiché dans le salon et avant la partie.
class JackpotBanner extends StatelessWidget {
  const JackpotBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Wallet.watchJackpot(),
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black26,
            border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
          ),
          child: Text(
            tr(
              '🎰 JACKPOT : ${Wallet.format(snap.data ?? 0)}\n'
              'Il peut tomber sur n\'importe quelle victoire !',
              '🎰 JACKPOT: ${Wallet.format(snap.data ?? 0)}\n'
              'It can drop on any win!',
            ),
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

/// Bandeau « Jackpot » compact, affiché pendant la partie.
/// Le montant est mis à jour en direct et défile quand il change.
class JackpotStrip extends StatefulWidget {
  const JackpotStrip({super.key, this.stake = 1});

  /// Mise de la partie (0 = partie gratuite : pas de jackpot à gagner).
  final int stake;

  @override
  State<JackpotStrip> createState() => _JackpotStripState();
}

class _JackpotStripState extends State<JackpotStrip> {
  // Le flux n'est créé qu'une fois : sinon il serait relancé (et le montant
  // retomberait à 0) à chaque coup joué.
  late final Stream<int> _stream = Wallet.watchJackpot();
  int _last = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final value = snap.data ?? _last;
        _last = value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black26,
            border: Border.all(color: const Color(0xFFFFC21A), width: 1.5),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: TweenAnimationBuilder<int>(
              tween: IntTween(begin: value, end: value),
              duration: const Duration(milliseconds: 900),
              builder: (context, shown, _) => Text(
                widget.stake > 0
                    ? tr(
                        '🎰 JACKPOT : ${Wallet.format(shown)}',
                        '🎰 JACKPOT: ${Wallet.format(shown)}',
                      )
                    : tr(
                        '🎰 JACKPOT : ${Wallet.format(shown)} (parties avec mise)',
                        '🎰 JACKPOT: ${Wallet.format(shown)} (stake games)',
                      ),
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _authError(String code) {
  switch (code) {
    case 'invalid-email':
      return 'E-mail invalide.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'E-mail ou mot de passe incorrect.';
    case 'too-many-requests':
      return "Trop d'essais. Réessaie dans quelques minutes.";
    case 'network-request-failed':
      return 'Pas de connexion internet.';
    default:
      return tr('Erreur : $code', 'Error: $code');
  }
}

/// Fenêtre de connexion d'un joueur. Renvoie son compte, ou null si annulé.
Future<PlayerAccount?> showPlayerLogin(
  BuildContext context, {
  required String colorName,
  required Color color,
}) {
  return showDialog<PlayerAccount>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _LoginDialog(colorName: colorName, color: color),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.colorName, required this.color});

  final String colorName;
  final Color color;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool hide = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;
    if (!email.contains('@') || pass.length < 6) {
      setState(() => error = 'E-mail ou mot de passe invalide.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final acc = await Wallet.signInGuest(email, pass);
      if (!mounted) return;
      Navigator.pop(context, acc);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = _authError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Une erreur est survenue. Réessaie.';
      });
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: tr(label),
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
        borderSide: BorderSide(color: widget.color, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14267A),
      title: Text(
        tr('Connexion · Joueur ${widget.colorName}',
            'Sign in · Player ${widget.colorName}'),
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('E-mail', Icons.email),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              enabled: !busy,
              obscureText: hide,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(
                'Mot de passe',
                Icons.lock,
                suffix: IconButton(
                  onPressed: () => setState(() => hide = !hide),
                  icon: Icon(
                    hide ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: busy ? null : _submit,
          child: Text(
            busy ? 'Patiente...' : 'Se connecter',
            style: const TextStyle(color: Color(0xFFFFC21A)),
          ),
        ),
      ],
    );
  }
}
