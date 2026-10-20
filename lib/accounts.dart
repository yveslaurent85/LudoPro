import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Un joueur connecté à son propre compte (avec son compte d'argent).
class PlayerAccount {
  final String uid;
  final String name;
  final String email;
  final int balance;

  const PlayerAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.balance,
  });
}

/// Compte d'argent de chaque joueur : document Firestore `users/{uid}`.
/// Le solde ne se modifie PAS depuis l'appli (voir les règles Firestore) :
/// la recharge passera plus tard par un serveur / paiement.
class Wallet {
  static const String currency = 'FCFA';

  static String format(int amount) => '$amount $currency';

  static DocumentReference<Map<String, dynamic>> _ref(
    FirebaseFirestore db,
    String uid,
  ) =>
      db.collection('users').doc(uid);

  /// Crée le compte d'argent (solde 0) s'il n'existe pas, renvoie le solde.
  static Future<int> ensure(
    FirebaseFirestore db,
    User user, {
    String? pseudo,
  }) async {
    final ref = _ref(db, user.uid);
    final snap = await ref.get();
    if (snap.exists) {
      final b = snap.data()?['balance'];
      return b is num ? b.toInt() : 0;
    }
    await ref.set({
      'name': pseudo ?? user.displayName ?? '',
      'email': user.email ?? '',
      'balance': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return 0;
  }

  /// Solde en direct (pour l'afficher et le voir changer après une recharge).
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
      balance = await ensure(FirebaseFirestore.instanceFor(app: app), user);
    } catch (_) {
      // Solde illisible : on laisse quand même jouer, solde affiché à 0.
    }
    final name = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.email ?? 'Joueur');
    final account = PlayerAccount(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      balance: balance,
    );
    await auth.signOut(); // la session invité n'est pas gardée
    return account;
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
      return 'Erreur : $code';
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
        borderSide: BorderSide(color: widget.color, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14267A),
      title: Text(
        'Connexion · Joueur ${widget.colorName}',
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
