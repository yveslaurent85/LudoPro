import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';
import 'main.dart' show firebaseReady;
import 'online.dart';
import 'recharge.dart';

const BoxDecoration _appBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5BFF), Color(0xFF0B2FA6), Color(0xFF061A66)],
  ),
);

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

