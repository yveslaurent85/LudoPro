import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'lang.dart';
import 'legal_texts.dart';
import 'whatsapp_group.dart';

/// Aide, support et jeu responsable (limite de recharge, auto-exclusion).
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  Map<String, dynamic> _l = {};
  final TextEditingController _limit = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Wallet.myLimits();
      if (!mounted) return;
      setState(() {
        _l = r;
        final v = (r['depositLimitDay'] as num?)?.toInt() ?? 0;
        _limit.text = v > 0 ? '$v' : '';
      });
    } catch (_) {}
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save({int? limit, int? days}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Wallet.setLimits(depositLimitDay: limit, excludeDays: days);
      _snack(tr('Enregistré.', 'Saved.'));
      await _load();
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exclude(int days) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('T\'auto-exclure ?', 'Self-exclude?')),
        content: Text(tr(
          'Pendant $days jour(s) tu ne pourras plus jouer avec mise ni recharger. Tu pourras toujours retirer ton argent. Cette décision ne peut pas être annulée.',
          'For $days day(s) you will not be able to stake or deposit. You can still withdraw. This cannot be undone.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Je confirme', 'Confirm'))),
        ],
      ),
    );
    if (ok == true) await _save(days: days);
  }

  Widget _card(String title, List<Widget> kids) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Color(0xFFFFC21A), fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...kids,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final until = (_l['excludedUntil'] as num?)?.toInt() ?? 0;
    final excluded = until > DateTime.now().millisecondsSinceEpoch;
    final untilTxt = excluded
        ? DateTime.fromMillisecondsSinceEpoch(until).toLocal().toString().substring(0, 10)
        : '';
    return Scaffold(
      backgroundColor: const Color(0xFF0B3D2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B3D2E),
        foregroundColor: Colors.white,
        title: Text(tr('Aide et jeu responsable', 'Help and responsible play')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(tr('Besoin d\'aide ?', 'Need help?'), [
            Text(
              tr('Un problème de recharge, de retrait ou de partie ? Écris-nous sur WhatsApp en donnant ton pseudo et le montant concerné.',
                  'Problem with a deposit, withdrawal or game? Message us on WhatsApp with your username and the amount.'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: () => launchUrl(Uri.parse(kWhatsAppGroupUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat),
                label: Text(tr('Contacter le support (WhatsApp)', 'Contact support (WhatsApp)')),
              ),
            ),
          ]),
          _card(tr('Limite de recharge (24 h)', 'Deposit limit (24 h)'), [
            Text(
              tr('Fixe le maximum que tu peux recharger par 24 heures. Laisse vide pour aucune limite.',
                  'Set the most you can deposit per 24 hours. Leave empty for no limit.'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: tr('Montant en FCFA', 'Amount in FCFA'),
                labelStyle: const TextStyle(color: Colors.white70),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: _busy ? null : () => _save(limit: int.tryParse(_limit.text.trim()) ?? 0),
                child: Text(tr('Enregistrer la limite', 'Save limit')),
              ),
            ),
          ]),
          _card(tr('Auto-exclusion', 'Self-exclusion'), [
            if (excluded)
              Text(tr('Auto-exclusion active jusqu\'au $untilTxt.', 'Self-exclusion active until $untilTxt.'),
                  style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w800))
            else
              Text(
                tr('Besoin d\'une pause ? Tu ne pourras plus jouer avec mise ni recharger pendant la durée choisie. Tu peux toujours retirer ton argent.',
                    'Need a break? You will not be able to stake or deposit for the chosen period. You can still withdraw.'),
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in const [1, 7, 30, 90, 180])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  onPressed: _busy ? null : () => _exclude(d),
                  child: Text(d == 1 ? tr('24 heures', '24 hours') : tr('$d jours', '$d days')),
                ),
            ]),
          ]),
          _card(tr('Jouer sans risque', 'Play safely'), [
            Text(
              tr('• Ne joue que l\'argent que tu peux perdre.\n• Fixe-toi un budget avant de jouer.\n• Ne cherche pas à te « refaire ».\n• Fais des pauses. Si le jeu te pose problème, utilise l\'auto-exclusion.',
                  '• Only play money you can afford to lose.\n• Set a budget first.\n• Don\'t chase losses.\n• Take breaks. If gambling is a problem, use self-exclusion.'),
              style: const TextStyle(color: Colors.white),
            ),
          ]),
          _card(tr('Conditions d\'utilisation', 'Terms of use'), [
            Text(katikaTerms(), style: const TextStyle(color: Colors.white70, height: 1.35, fontSize: 12.5)),
          ]),
        ],
      ),
    );
  }
}
