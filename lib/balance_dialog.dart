import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'deposit_screen.dart';
import 'lang.dart';

/// Fenêtre « Solde insuffisant » quand on rejoint (ou crée) une partie :
/// elle montre le solde, le montant requis, ce qui manque, et propose de recharger.
///
/// [stake] = mise à bloquer. [fee] = frais en plus (ex. prix d'une capture),
/// décrit par [feeLabel]. [lines] = autres infos sur la partie (une par ligne).
Future<void> showInsufficientBalance(
  BuildContext context, {
  required int balance,
  required int stake,
  int fee = 0,
  String? feeLabel,
  String? game,
  List<String> lines = const [],
}) async {
  final need = stake + fee;
  final missing = need > balance ? need - balance : 0;
  const red = Color(0xFF8E1B1B);
  Widget row(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(k, style: TextStyle(color: color ?? red, fontSize: 15))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color ?? red, fontSize: 15, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ),
        ]),
      );
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🎲', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  game == null ? tr('Rejoindre la partie', 'Join the game') : tr('Rejoindre · $game', 'Join · $game'),
                  style: const TextStyle(color: Color(0xFF111111), fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                icon: const Icon(Icons.close, color: Color(0xFF1B9E6B)),
              ),
            ]),
            const SizedBox(height: 8),
            for (final l in lines)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(12)),
                child: Text(l, style: const TextStyle(color: Color(0xFF222222), fontSize: 14)),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8D7DA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1B0B7)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.error_outline, color: red),
                  const SizedBox(width: 8),
                  Text(tr('Solde insuffisant', 'Insufficient balance'),
                      style: const TextStyle(color: red, fontSize: 18, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                row(tr('Votre solde :', 'Your balance:'), Wallet.format(balance), bold: true),
                row(tr('Mise :', 'Stake:'), Wallet.format(stake), bold: true),
                if (fee > 0) row(feeLabel ?? tr('Frais :', 'Fee:'), '+ ${Wallet.format(fee)}'),
                const Divider(color: Color(0xFFE5A6AD), height: 14),
                row(tr('Requis :', 'Required:'), Wallet.format(need), bold: true),
                row(tr('Il vous manque :', 'You are short by:'), Wallet.format(missing), bold: true),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B9E6B),
                    side: const BorderSide(color: Color(0xFF1B9E6B), width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(tr('Annuler', 'Cancel'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F6BFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(tr('Recharger mon compte', 'Top up my account'),
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DepositScreen()));
  }
}
