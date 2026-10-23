import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

/// Bandeau « Jackpot » compact, affiché pendant la partie.
/// Le montant est mis à jour en direct et défile quand il change.
class JackpotLive extends StatefulWidget {
  const JackpotLive({super.key, this.stake = 1});

  /// Mise de la partie (0 = partie gratuite : pas de jackpot à gagner).
  final int stake;

  @override
  State<JackpotLive> createState() => _JackpotLiveState();
}

class _JackpotLiveState extends State<JackpotLive> {
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
