import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';
import 'legal_texts.dart';

/// Écran bloquant : 18 ans et plus + conditions d'utilisation.
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _age = false;
  bool _terms = false;
  bool _busy = false;
  String? _err;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Wallet.acceptTerms();
      if (mounted) widget.onAccepted();
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = Wallet.errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B3D2E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Text(tr('Conditions d\'utilisation', 'Terms of use'),
                  style: const TextStyle(color: Color(0xFFFFC21A), fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: Text(katikaTerms(), style: const TextStyle(color: Colors.white, height: 1.35)),
                  ),
                ),
              ),
              CheckboxListTile(
                value: _age,
                onChanged: (v) => setState(() => _age = v == true),
                activeColor: const Color(0xFF22B14C),
                title: Text(tr('J\'ai 18 ans ou plus', 'I am 18 or older'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _terms,
                onChanged: (v) => setState(() => _terms = v == true),
                activeColor: const Color(0xFF22B14C),
                title: Text(tr('J\'ai lu et j\'accepte les conditions', 'I have read and accept the terms'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_err!, style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: (_age && _terms && !_busy) ? _accept : null,
                  child: Text(tr('Continuer', 'Continue'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => FirebaseAuth.instance.signOut().then((_) => widget.onAccepted()),
                child: Text(tr('Je refuse (se déconnecter)', 'Decline (log out)'),
                    style: const TextStyle(color: Colors.white70)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
