import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';

/// Recharge du compte par Orange Money ou MTN MoMo (via CamPay / TAKWID).
/// Le montant n'est ajouté au solde que par le serveur, après confirmation.
class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  static const List<int> quick = [25, 1000, 2000, 5000];

  final amountCtrl = TextEditingController(text: '1000');
  final phoneCtrl = TextEditingController();

  final FirebaseFunctions fn =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  bool busy = false;
  bool waiting = false;
  String? info;
  String? error;
  Timer? poll;
  int tries = 0;

  @override
  void dispose() {
    poll?.cancel();
    amountCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    final phone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (amount < 25) {
      setState(() => error = 'Montant minimum : 25 FCFA.');
      return;
    }
    if (!(phone.length == 9 && phone.startsWith('6'))) {
      setState(() => error = 'Numéro à 9 chiffres (Orange ou MTN).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final res = await fn
          .httpsCallable('startRecharge')
          .call(<String, dynamic>{'amount': amount, 'phone': phone});
      final data = Map<String, dynamic>.from(res.data as Map);
      final id = data['id'] as String;
      final ussd = data['ussd'] as String?;
      if (!mounted) return;
      setState(() {
        busy = false;
        waiting = true;
        info = ussd != null && ussd.isNotEmpty
            ? 'Valide le paiement sur ton téléphone (ou compose $ussd).'
            : 'Valide le paiement sur ton téléphone avec ton code secret.';
      });
      _startPolling(id);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message ?? 'Erreur : ${e.code}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Pas de connexion. Réessaie.';
      });
    }
  }

  void _startPolling(String id) {
    tries = 0;
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 4), (t) async {
      tries++;
      if (tries > 30) {
        t.cancel();
        if (!mounted) return;
        setState(() {
          waiting = false;
          error = 'Paiement non confirmé. Si tu as été débité, '
              'ton solde sera mis à jour après vérification.';
        });
        return;
      }
      try {
        final res =
            await fn.httpsCallable('checkRecharge').call(<String, dynamic>{
          'id': id,
        });
        final status = (res.data as Map)['status'] as String? ?? 'pending';
        if (status == 'pending') return;
        t.cancel();
        if (!mounted) return;
        setState(() {
          waiting = false;
          if (status == 'done') {
            info = '✅ Recharge réussie ! Ton solde est à jour.';
            error = null;
          } else {
            info = null;
            error = 'Le paiement a échoué ou a été refusé.';
          }
        });
      } catch (_) {
        // erreur réseau passagère : on réessaie au prochain tour
      }
    });
  }

  InputDecoration _dec(String label, IconData icon, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      suffixStyle: const TextStyle(color: Colors.white70),
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
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

  @override
  Widget build(BuildContext context) {
    final locked = busy || waiting;
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
                      'Recharger mon compte',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Orange Money ou MTN MoMo : l\'opérateur est détecté '
                  'd\'après ton numéro.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in quick)
                      ChoiceChip(
                        label: Text('$q'),
                        selected: amountCtrl.text == '$q',
                        onSelected: locked
                            ? null
                            : (_) => setState(() => amountCtrl.text = '$q'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: _dec('Montant', Icons.payments, suffix: Wallet.currency),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  enabled: !locked,
                  keyboardType: TextInputType.phone,
                  maxLength: 9,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('Numéro Orange / MTN (9 chiffres)', Icons.phone)
                      .copyWith(counterText: '', prefixText: '+237 ',
                          prefixStyle: const TextStyle(color: Colors.white70)),
                ),
                if (info != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    info!,
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (waiting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22B14C),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: locked ? null : _start,
                    child: Text(
                      busy
                          ? 'Patiente...'
                          : (waiting ? 'En attente de ta validation...' : 'Recharger'),
                      style: const TextStyle(
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
