import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Modifier le mot de passe. Si le joueur ne se souvient plus de son mot de
/// passe actuel, « Mot de passe oublié ? » lui envoie un email de
/// récupération (lien pour en choisir un nouveau).
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  static const Color _gold = Color(0xFFFFC21A);

  final TextEditingController currentCtrl = TextEditingController();
  final TextEditingController newCtrl = TextEditingController();
  final TextEditingController confirmCtrl = TextEditingController();
  bool busy = false;
  bool resetBusy = false;
  bool hideCurrent = true;
  bool hideNew = true;
  String? error;
  String? info;

  @override
  void dispose() {
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  String _errorText(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return 'Mot de passe actuel incorrect.';
        case 'weak-password':
          return 'Nouveau mot de passe trop faible (6 caractères minimum).';
        case 'too-many-requests':
          return 'Trop d\'essais. Réessaie dans quelques minutes.';
        case 'requires-recent-login':
          return 'Reconnecte-toi puis recommence.';
        case 'network-request-failed':
          return 'Pas de connexion internet.';
        case 'user-not-found':
          return 'Aucun compte avec cet email.';
        case 'invalid-email':
          return 'Adresse email invalide.';
      }
      return e.message ?? 'Erreur : ${e.code}';
    }
    return '$e';
  }

  Future<void> _change() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      setState(() => error = 'Ce compte n\'a pas d\'adresse email.');
      return;
    }
    final cur = currentCtrl.text;
    final nw = newCtrl.text;
    if (cur.isEmpty) {
      setState(() => error = 'Entre ton mot de passe actuel.');
      return;
    }
    if (nw.length < 6) {
      setState(() => error = 'Le nouveau mot de passe doit avoir au moins '
          '6 caractères.');
      return;
    }
    if (nw != confirmCtrl.text) {
      setState(() => error = 'Les deux mots de passe ne sont pas identiques.');
      return;
    }
    if (nw == cur) {
      setState(() => error = 'Le nouveau mot de passe est le même que '
          'l\'ancien.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: cur),
      );
      await user.updatePassword(nw);
      if (!mounted) return;
      currentCtrl.clear();
      newCtrl.clear();
      confirmCtrl.clear();
      setState(() => info = 'Mot de passe modifié !');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié !')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Récupération par email : Firebase envoie un lien de réinitialisation.
  Future<void> _forgot() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      setState(() => error = 'Ce compte n\'a pas d\'adresse email.');
      return;
    }
    setState(() {
      resetBusy = true;
      error = null;
      info = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => info = 'Un email de récupération a été envoyé à $email. '
          'Ouvre-le et suis le lien pour choisir un nouveau mot de passe '
          '(regarde aussi dans les spams).');
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _errorText(e));
    } finally {
      if (mounted) setState(() => resetBusy = false);
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        '🔒 Mot de passe',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Modifier le mot de passe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (email.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                email,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: currentCtrl,
                            enabled: !busy,
                            obscureText: hideCurrent,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dec(
                              'Mot de passe actuel',
                              suffix: IconButton(
                                icon: Icon(
                                  hideCurrent
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Colors.white54,
                                ),
                                onPressed: () =>
                                    setState(() => hideCurrent = !hideCurrent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: newCtrl,
                            enabled: !busy,
                            obscureText: hideNew,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dec(
                              'Nouveau mot de passe',
                              suffix: IconButton(
                                icon: Icon(
                                  hideNew
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Colors.white54,
                                ),
                                onPressed: () =>
                                    setState(() => hideNew = !hideNew),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: confirmCtrl,
                            enabled: !busy,
                            obscureText: hideNew,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dec('Confirmer le nouveau mot de passe'),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                error!,
                                style: const TextStyle(
                                  color: Color(0xFFFF8A80),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (info != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                info!,
                                style: const TextStyle(
                                  color: Color(0xFF7CFFB0),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22B14C),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: busy ? null : _change,
                              child: Text(
                                busy ? '...' : 'Modifier le mot de passe',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton(
                              onPressed: resetBusy ? null : _forgot,
                              child: Text(
                                resetBusy ? '...' : 'Mot de passe oublié ?',
                                style: const TextStyle(
                                  color: _gold,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            'Mot de passe oublié : un email de récupération '
                            'est envoyé à l\'adresse de ton compte.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
