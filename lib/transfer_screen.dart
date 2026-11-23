import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Transfert d'argent de compte à compte : on saisit le pseudo (ou le code
/// promo) du destinataire et le montant. Le serveur débite et crédite.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  static const Color _gold = Color(0xFFFFC21A);
  static const int _min = 25;
  static const int _max = 250000;

  final TextEditingController toCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();

  bool sending = false;
  String? error;
  String? success;

  late final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Suggestions de destinataires (dès 2 caractères)
  Timer? _deb;
  List<Map<String, String>> _sugg = [];
  bool _searching = false;
  String _pickedName = '';
  String _pickedCode = '';
  int _searchSeq = 0;

  void _onTo(String v) {
    _deb?.cancel();
    final q = v.trim();
    if (q != _pickedName) _pickedCode = '';
    if (q.length < 2) {
      setState(() {
        _sugg = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _deb = Timer(const Duration(milliseconds: 250), () async {
      final seq = ++_searchSeq;
      try {
        final r = await Wallet.searchPlayers(q);
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _sugg = r;
          _searching = false;
        });
      } catch (_) {
        if (mounted && seq == _searchSeq) setState(() => _searching = false);
      }
    });
  }

  void _pick(Map<String, String> p) {
    _deb?.cancel();
    _searchSeq++;
    setState(() {
      _pickedName = p['name'] ?? '';
      _pickedCode = p['code'] ?? '';
      toCtrl.text = _pickedName;
      toCtrl.selection = TextSelection.collapsed(offset: toCtrl.text.length);
      _sugg = [];
      _searching = false;
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    toCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (sending) return;
    final to = toCtrl.text.trim();
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    if (to.isEmpty) {
      setState(() {
        error = 'Indique le pseudo ou le code promo du destinataire.';
        success = null;
      });
      return;
    }
    if (amount < _min || amount > _max) {
      setState(() {
        error = 'Montant entre $_min et $_max FCFA.';
        success = null;
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Confirmer le transfert'),
        content: Text('Envoyer ${Wallet.format(amount)} à « $to » ?\n'
            'Cette opération est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      sending = true;
      error = null;
      success = null;
    });
    try {
      final res = await Wallet.transfer(_pickedCode.isNotEmpty && to == _pickedName ? _pickedCode : to, amount);
      if (!mounted) return;
      setState(() {
        success = '✅ ${Wallet.format(amount)} envoyés à ${res['toName']}.';
        toCtrl.clear();
        amountCtrl.clear();
        _pickedName = '';
        _pickedCode = '';
        _sugg = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = Wallet.errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF68729A)),
        filled: true,
        fillColor: const Color(0xFFE3EAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3F6FF), Color(0xFFF3F6FF)],
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
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF12183A)),
                    ),
                    const Expanded(
                      child: Text(
                        '🔁 Transférer de l\'argent',
                        style: TextStyle(
                          color: Color(0xFF12183A),
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
                        color: const Color(0xFFE3EAFF),
                        border: Border.all(color: _gold),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Mon solde',
                            style:
                                TextStyle(color: Color(0xFF56608A), fontSize: 13),
                          ),
                          StreamBuilder<int>(
                            stream: Wallet.watch(uid),
                            builder: (context, snap) => Text(
                              '💰 ${Wallet.format(snap.data ?? 0)}',
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Destinataire',
                      style: TextStyle(
                        color: Color(0xFF12183A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: toCtrl,
                      onChanged: _onTo,
                      autocorrect: false,
                      style: const TextStyle(color: Color(0xFF12183A)),
                      decoration: _dec('Tape 2 lettres du pseudo du joueur'),
                    ),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2, color: _gold),
                      ),
                    if (_sugg.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: Color(0xFF12183A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            for (final p in _sugg)
                              ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(0xFF1E6BFF),
                                  child: Icon(Icons.person, size: 16, color: Colors.white),
                                ),
                                title: Text(p['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B2FA6))),
                                subtitle: Text('@${p['code']}', style: const TextStyle(fontSize: 11)),
                                onTap: () => _pick(p),
                              ),
                          ],
                        ),
                      )
                    else if (toCtrl.text.trim().length >= 2 && !_searching && _pickedCode.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Aucun joueur trouvé avec ces lettres.',
                            style: TextStyle(color: Color(0xFF56608A), fontSize: 12)),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Montant (FCFA)',
                      style: TextStyle(
                        color: Color(0xFF12183A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Color(0xFF12183A)),
                      decoration: _dec('Entre $_min et $_max'),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22B14C),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: sending ? null : _send,
                        child: Text(
                          sending ? 'Envoi...' : 'Envoyer',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFD32F2F),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (success != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          success!,
                          style: const TextStyle(
                            color: Color(0xFF17883F),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Le destinataire est retrouvé grâce à son pseudo ou à son '
                      'code promo. Vérifie bien l\'orthographe : un transfert '
                      'ne peut pas être annulé.',
                      style: TextStyle(color: Color(0xFF56608A), fontSize: 12),
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
