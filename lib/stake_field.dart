import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'lang.dart';

/// Mise maximale autorisée (doit être la même que MAX_STAKE dans worker.js).
const int kMaxStake = 250000;

/// 250000 -> « 250 000 ».
String _fmtSpaces(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Choix de la mise : boutons rapides + case où le joueur écrit son montant.
/// [onChanged] reçoit : 0 (gratuit), un montant valide, ou -1 si le montant
/// écrit est invalide (moins que le minimum ou plus que le maximum).
class StakeField extends StatefulWidget {
  const StakeField({
    super.key,
    required this.stake,
    required this.players,
    required this.onChanged,
    this.local = false,
  });

  final int stake;
  final int players;
  final bool local;
  final ValueChanged<int> onChanged;

  @override
  State<StakeField> createState() => _StakeFieldState();
}

class _StakeFieldState extends State<StakeField> {
  static const Color _gold = Color(0xFFFFE082);
  late final TextEditingController _ctrl;
  late int _last;

  @override
  void initState() {
    super.initState();
    _last = widget.stake;
    _ctrl = TextEditingController(text: widget.stake > 0 ? '${widget.stake}' : '');
  }

  @override
  void didUpdateWidget(StakeField old) {
    super.didUpdateWidget(old);
    if (widget.stake != _last) {
      _last = widget.stake;
      _ctrl.text = widget.stake > 0 ? '${widget.stake}' : '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pick(int v) {
    _last = v;
    _ctrl.text = v > 0 ? '$v' : '';
    widget.onChanged(v);
  }

  void _typed(String t) {
    final v = int.tryParse(t) ?? 0;
    final out = v == 0 ? 0 : ((v < Wallet.minStake || v > kMaxStake) ? -1 : v);
    _last = out;
    widget.onChanged(out);
  }

  @override
  Widget build(BuildContext context) {
    final stake = widget.stake;
    final pct = widget.local
        ? Wallet.commissionLocalPercent
        : Wallet.commissionPercent;
    final prize = stake > 0
        ? Wallet.format(
            Wallet.prize(stake * widget.players, local: widget.local))
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final v in Wallet.stakes)
              ChoiceChip(
                label: Text(Wallet.stakeLabel(v)),
                selected: stake == v,
                onSelected: (_) => _pick(v),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(7),
          ],
          onChanged: _typed,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            hintText: tr('Écris ta mise', 'Type your stake'),
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.payments_outlined, color: Colors.white70),
            suffixText: 'FCFA',
            suffixStyle: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Minimum : ${_fmtSpaces(Wallet.minStake)} FCFA  ·  '
                'Maximum : ${_fmtSpaces(kMaxStake)} FCFA',
            'Minimum: ${_fmtSpaces(Wallet.minStake)} FCFA  ·  '
                'Maximum: ${_fmtSpaces(kMaxStake)} FCFA',
          ),
          style: TextStyle(
            color: stake < 0 ? const Color(0xFFFF8A80) : _gold,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          stake < 0
              ? tr('Montant invalide : respecte le minimum et le maximum.',
                  'Invalid amount: stay between the minimum and maximum.')
              : stake == 0
                  ? tr('Partie gratuite : aucun jeton en jeu, pas de jackpot.',
                      'Free game: no tokens at stake, no jackpot.')
                  : tr(
                      'Gain du gagnant : $prize '
                          '(cagnotte ${stake * widget.players}, commission $pct %)',
                      'Winner gets: $prize '
                          '(pot ${stake * widget.players}, commission $pct %)',
                    ),
          style: TextStyle(
            color: stake < 0 ? const Color(0xFFFF8A80) : _gold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

/// Case « Écris ton montant » pour un pari (Duel, Défi 7). [onChanged] reçoit
/// le montant valide, ou -1 si la case est vide ou hors limites.
class BetAmountField extends StatefulWidget {
  const BetAmountField({
    super.key,
    required this.amount,
    required this.onChanged,
    this.enabled = true,
  });

  final int amount;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<BetAmountField> createState() => _BetAmountFieldState();
}

class _BetAmountFieldState extends State<BetAmountField> {
  static const Color _gold = Color(0xFFFFE082);
  late final TextEditingController _ctrl;
  late int _last;

  @override
  void initState() {
    super.initState();
    _last = widget.amount;
    _ctrl = TextEditingController(text: widget.amount > 0 ? '${widget.amount}' : '');
  }

  @override
  void didUpdateWidget(BetAmountField old) {
    super.didUpdateWidget(old);
    if (widget.amount != _last) {
      _last = widget.amount;
      _ctrl.text = widget.amount > 0 ? '${widget.amount}' : '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _typed(String t) {
    final v = int.tryParse(t) ?? 0;
    final out = (v < Wallet.minStake || v > kMaxStake) ? -1 : v;
    _last = out;
    widget.onChanged(out);
  }

  @override
  Widget build(BuildContext context) {
    final bad = widget.amount < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(7),
          ],
          onChanged: _typed,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            hintText: tr('Écris ta mise', 'Type your stake'),
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon:
                const Icon(Icons.payments_outlined, color: Colors.white70),
            suffixText: 'FCFA',
            suffixStyle:
                const TextStyle(color: _gold, fontWeight: FontWeight.w800),
            filled: true,
            fillColor: Colors.white.withOpacity(0.12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Minimum : ${_fmtSpaces(Wallet.minStake)} FCFA  ·  '
                'Maximum : ${_fmtSpaces(kMaxStake)} FCFA',
            'Minimum: ${_fmtSpaces(Wallet.minStake)} FCFA  ·  '
                'Maximum: ${_fmtSpaces(kMaxStake)} FCFA',
          ),
          style: TextStyle(
            color: bad ? const Color(0xFFFF8A80) : _gold,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
