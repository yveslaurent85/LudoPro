import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

// ----------------------------------------------------------------------
// Paris en présentiel (Deux dés, un seul téléphone) : Duel et Défi 7.
// Les deux mises sont débitées tout de suite par le serveur
// (Wallet.localBet) ; le règlement se fait à la fin de la partie
// (Wallet.settleLocalFull → { jackpot, bets }).
// ----------------------------------------------------------------------

const List<Color> _seatColors = [
  Color(0xFFE5262B),
  Color(0xFF22B14C),
  Color(0xFF1E6BFF),
  Color(0xFFFFC21A),
];

const List<int> _betAmounts = [100, 200, 500, 1000];

/// Pari préparé avant le début de la partie (placé dès que la partie
/// démarre, quand les mises sont débitées).
class PendingBet {
  const PendingBet(this.type, this.pSeat, this.oSeat, this.amount, this.over7);

  final String type; // 'duel' ou 'seven'
  final int pSeat;
  final int oSeat;
  final int amount;
  final bool over7;

  String describe(List<String> names) {
    String nm(int s) => s >= 0 && s < names.length ? names[s] : '?';
    final a = nm(pSeat);
    final b = nm(oSeat);
    return type == 'seven'
        ? tr('$a ${over7 ? 'plus de 7' : 'moins de 7'} vs $b · $amount',
            '$a ${over7 ? 'over 7' : 'under 7'} vs $b · $amount')
        : tr('Duel $a vs $b · $amount', 'Duel $a vs $b · $amount');
  }
}

/// Ouvre la fenêtre de pari avant la partie. Renvoie le pari préparé.
Future<PendingBet?> pickPendingBet(BuildContext context, List<String> names) {
  return showModalBottomSheet<PendingBet>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14267A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _BetSheet(
      localId: null,
      names: names,
      tokens: const [],
      cur: 0,
      rolled: false,
    ),
  );
}

/// Place les paris préparés (la partie vient de démarrer). Renvoie les
/// textes des paris placés et les erreurs éventuelles.
Future<({List<String> placed, List<String> errors})> placePendingBets({
  required String localId,
  required List<String> tokens,
  required List<String> names,
  required List<PendingBet> bets,
}) async {
  final placed = <String>[];
  final errors = <String>[];
  for (final b in bets) {
    if (b.pSeat >= tokens.length || b.oSeat >= tokens.length) continue;
    try {
      await Wallet.localBet(
        id: localId,
        type: b.type,
        amount: b.amount,
        proposerToken: tokens[b.pSeat],
        opponentToken: tokens[b.oSeat],
        over7: b.over7,
      );
      placed.add(b.describe(names));
    } catch (e) {
      errors.add('${b.describe(names)} : ${Wallet.errorText(e)}');
    }
  }
  return (placed: placed, errors: errors);
}

/// Bandeau « Paris » affiché pendant la partie en présentiel.
class LocalSideBetsBar extends StatefulWidget {
  const LocalSideBetsBar({
    super.key,
    required this.localId,
    required this.names,
    required this.uids,
    required this.tokens,
    required this.cur,
    required this.rolled,
    required this.over,
    this.initialPlaced = const [],
  });

  /// Paris déjà placés avant le début de la partie.
  final List<String> initialPlaced;

  final String localId;
  final List<String> names;
  final List<String?> uids;

  /// Jeton de connexion de chaque place (prouve le compte du joueur).
  final List<String> tokens;

  /// Place du joueur dont c'est le tour, et s'il a déjà lancé.
  final int cur;
  final bool rolled;
  final bool over;

  @override
  State<LocalSideBetsBar> createState() => _LocalSideBetsBarState();
}

class _LocalSideBetsBarState extends State<LocalSideBetsBar> {
  late final List<String> placed = [...widget.initialPlaced];

  Future<void> _open() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14267A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _BetSheet(
        localId: widget.localId,
        names: widget.names,
        tokens: widget.tokens,
        cur: widget.cur,
        rolled: widget.rolled,
      ),
    );
    if (text != null && mounted) {
      setState(() => placed.add(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.over) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black26,
        border: Border.all(color: Colors.white38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  placed.isEmpty
                      ? tr('🎲 Paris entre joueurs',
                          '🎲 Side bets between players')
                      : tr('🎲 Paris : ${placed.length} en jeu',
                          '🎲 Bets: ${placed.length} placed'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _open,
                child: Text(
                  tr('Parier', 'Bet'),
                  style: const TextStyle(
                    color: Color(0xFFFFC21A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          for (final p in placed)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                p,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _BetSheet extends StatefulWidget {
  const _BetSheet({
    required this.localId,
    required this.names,
    required this.tokens,
    required this.cur,
    required this.rolled,
  });

  /// null : pari préparé avant la partie (rien n'est débité maintenant).
  final String? localId;
  final List<String> names;
  final List<String> tokens;
  final int cur;
  final bool rolled;

  @override
  State<_BetSheet> createState() => _BetSheetState();
}

class _BetSheetState extends State<_BetSheet> {
  String type = 'duel'; // 'duel' ou 'seven'
  int? pSeat;
  int? oSeat;
  bool over7 = true;
  int amount = _betAmounts.first;
  bool busy = false;
  String? error;

  int get n => widget.names.length;

  /// Ce joueur a déjà lancé ses dés : on ne peut plus parier sur lui.
  bool _rolled(int seat) =>
      seat < widget.cur || (seat == widget.cur && widget.rolled);

  List<int> get _proposers => [
        for (int i = 0; i < n; i++)
          if (!_rolled(i)) i,
      ];

  List<int> _opponents() => [
        for (int i = 0; i < n; i++)
          if (i != pSeat && (type == 'seven' || !_rolled(i))) i,
      ];

  /// Garde des choix valides quand le type ou le parieur change.
  void _fix() {
    final ps = _proposers;
    if (pSeat == null || !ps.contains(pSeat)) {
      pSeat = ps.isEmpty ? null : ps.first;
    }
    final os = _opponents();
    if (oSeat == null || !os.contains(oSeat)) {
      oSeat = os.isEmpty ? null : os.first;
    }
  }

  @override
  void initState() {
    super.initState();
    _fix();
  }

  Future<void> _submit() async {
    final p = pSeat;
    final o = oSeat;
    if (p == null || o == null || busy) return;
    if (widget.localId == null) {
      Navigator.pop(context, PendingBet(type, p, o, amount, over7));
      return;
    }
    final pt = p < widget.tokens.length ? widget.tokens[p] : '';
    final ot = o < widget.tokens.length ? widget.tokens[o] : '';
    if (pt.isEmpty || ot.isEmpty) {
      setState(() => error = tr(
          'Connexion expirée : relance la partie.',
          'Session expired: restart the game.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Wallet.localBet(
        id: widget.localId!,
        type: type,
        amount: amount,
        proposerToken: pt,
        opponentToken: ot,
        over7: over7,
      );
      if (!mounted) return;
      final a = widget.names[p];
      final b = widget.names[o];
      final txt = type == 'seven'
          ? tr('$a ${over7 ? 'plus de 7' : 'moins de 7'} vs $b · $amount',
              '$a ${over7 ? 'over 7' : 'under 7'} vs $b · $amount')
          : tr('Duel $a vs $b · $amount', 'Duel $a vs $b · $amount');
      Navigator.pop(context, txt);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = Wallet.errorText(e);
      });
    }
  }

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _seatChips(List<int> seats, int? selected, void Function(int) onPick) {
    if (seats.isEmpty) {
      return Text(
        tr('Aucun joueur disponible.', 'No player available.'),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final s in seats)
          ChoiceChip(
            avatar: CircleAvatar(
              radius: 7,
              backgroundColor: _seatColors[s % 4],
            ),
            label: Text(widget.names[s]),
            selected: selected == s,
            onSelected: busy ? null : (_) => onPick(s),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _fix();
    final noProposer = _proposers.isEmpty;
    final canSend = !busy && pSeat != null && oSeat != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Parier entre joueurs', 'Bet between players'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.localId == null
                    ? tr('Le pari sera placé au démarrage de la partie : les '
                        'deux mises seront débitées à ce moment-là.',
                        'The bet is placed when the game starts: both stakes '
                            'are taken then.')
                    : tr('Les deux mises sont débitées tout de suite. '
                    'On ne peut parier que sur un joueur qui n\'a pas encore lancé.',
                    'Both stakes are taken now. You can only bet on a player '
                        'who has not rolled yet.'),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              _title(tr('Type de pari', 'Bet type')),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(tr('Duel (le plus gros score)',
                        'Duel (highest score)')),
                    selected: type == 'duel',
                    onSelected: busy ? null : (_) => setState(() => type = 'duel'),
                  ),
                  ChoiceChip(
                    label: Text(tr('Défi 7', '7 challenge')),
                    selected: type == 'seven',
                    onSelected:
                        busy ? null : (_) => setState(() => type = 'seven'),
                  ),
                ],
              ),
              _title(type == 'seven'
                  ? tr('Qui lance et parie ?', 'Who rolls and bets?')
                  : tr('Parieur', 'Bettor')),
              _seatChips(_proposers, pSeat, (s) => setState(() => pSeat = s)),
              if (type == 'seven') ...[
                _title(tr('Son total sera…', 'Their total will be…')),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(tr('Plus de 7', 'Over 7')),
                      selected: over7,
                      onSelected: busy ? null : (_) => setState(() => over7 = true),
                    ),
                    ChoiceChip(
                      label: Text(tr('Moins de 7', 'Under 7')),
                      selected: !over7,
                      onSelected:
                          busy ? null : (_) => setState(() => over7 = false),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr('7 pile : les mises sont rendues.',
                        'Exactly 7: stakes are refunded.'),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
              _title(tr('Adversaire', 'Opponent')),
              _seatChips(_opponents(), oSeat, (s) => setState(() => oSeat = s)),
              _title(tr('Mise de chacun (commission ${Wallet.commissionLocalPercent} %)',
                  'Stake each (${Wallet.commissionLocalPercent} % commission)')),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in _betAmounts)
                    ChoiceChip(
                      label: Text('$a'),
                      selected: amount == a,
                      onSelected: busy ? null : (_) => setState(() => amount = a),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('Gain du vainqueur : ${Wallet.format(Wallet.prize(amount * 2, local: true))}',
                      'Winner gets: ${Wallet.format(Wallet.prize(amount * 2, local: true))}'),
                  style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13),
                ),
              ),
              if (noProposer)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr('Tous les joueurs ont déjà lancé.',
                        'Everyone has already rolled.'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: Text(tr('Annuler', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22B14C),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: canSend ? _submit : null,
                      child: Text(busy
                          ? tr('Patiente...', 'Please wait...')
                          : tr('Valider le pari', 'Place bet')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Résumé des paris réglés, affiché dans le panneau de fin de partie.
/// [bets] : liste renvoyée par le serveur (settleLocalGame → bets).
class LocalBetsSummary extends StatelessWidget {
  const LocalBetsSummary({super.key, required this.bets});

  final List<Map<String, dynamic>> bets;

  String _line(Map<String, dynamic> b) {
    final a = '${b['proposerName'] ?? '?'}';
    final o = '${b['opponentName'] ?? '?'}';
    final amount = (b['amount'] as num?)?.toInt() ?? 0;
    final prize = (b['prize'] as num?)?.toInt() ?? 0;
    final winner = b['winnerName'];
    final isSeven = b['type'] == 'seven';
    final head = isSeven
        ? tr('$a ${b['side'] == 'under' ? 'moins de 7' : 'plus de 7'} vs $o',
            '$a ${b['side'] == 'under' ? 'under 7' : 'over 7'} vs $o')
        : tr('Duel $a vs $o', 'Duel $a vs $o');
    if (winner == null) {
      return tr('$head : égalité, mises rendues ($amount)',
          '$head: tie, stakes refunded ($amount)');
    }
    return tr('$head : $winner gagne ${Wallet.format(prize)}',
        '$head: $winner wins ${Wallet.format(prize)}');
  }

  @override
  Widget build(BuildContext context) {
    if (bets.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('🎲 Résultat des paris', '🎲 Bet results'),
            style: const TextStyle(
              color: Color(0xFFFFC21A),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          for (final b in bets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _line(b),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
