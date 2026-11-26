import 'package:flutter/material.dart' hide Text;

import 'lang.dart';

/// Fenêtre des règles d'un jeu (bouton « ? » en haut de l'écran de jeu).
void showRulesDialog(BuildContext context, String title, String text) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0B2FA6),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFE082),
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SingleChildScrollView(
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            'Fermer',
            style: TextStyle(color: Color(0xFFFFE082)),
          ),
        ),
      ],
    ),
  );
}

const String kLudoRules =
    'But : amener tous tes pions jusqu\'à l\'arrivée (56 cases à parcourir) '
    'avant les autres.\n\n'
    'Départ : il faut un 6 pour sortir un pion de la base (sauf avec les '
    'options « Position 54 » ou « Départ sur la case de départ », où les '
    'pions sont déjà sur le plateau).\n\n'
    'Déplacement : on avance son pion du nombre indiqué par le dé. À '
    'l\'arrivée, il faut le nombre exact : on ne peut pas dépasser.\n\n'
    'Rejouer : un 6, une capture ou un pion qui arrive à la maison donnent '
    'un nouveau lancer.\n\n'
    'Capture : si ton pion s\'arrête sur un pion adverse, celui-ci retourne '
    'à sa base et doit refaire un 6 pour ressortir. Les portes et les étoiles '
    'protègent les pions (selon les options de la partie). Avec les captures '
    'payantes, chaque capture rapporte de l\'argent.\n\n'
    'Équipes : en mode 2 contre 2, les binômes ne se capturent pas et '
    'l\'équipe gagne quand les deux joueurs ont fini.\n\n'
    'Mises : la cagnotte (mises de tous les joueurs) est versée au gagnant, '
    'moins la commission de Katika.';

const String kDeuxDesRules =
    'But : faire le plus grand total avec tes dés.\n\n'
    'Déroulement : chacun son tour, chaque joueur lance ses deux dés une '
    'seule fois. Le total des deux dés est son score. Quand tout le monde a '
    'lancé, la partie est finie.\n\n'
    'Gagnant : le joueur au score le plus élevé gagne. En cas d\'égalité, la '
    'cagnotte est partagée entre les gagnants.\n\n'
    'Temps : si un joueur ne lance pas dans les 30 secondes, le jeu lance '
    'pour lui.\n\n'
    'Mises : la cagnotte (mises de tous les joueurs) est versée au gagnant, '
    'moins la commission de Katika. Un jackpot peut aussi tomber.\n\n'
    'Paris entre joueurs (parties avec mise) : Duel (le plus gros score '
    'gagne) et Défi 7 (plus ou moins de 7). Il faut parier avant d\'avoir '
    'lancé ses dés ; à égalité ou 7 pile, les mises sont rendues.';

// ----------------------------------------------------------------------
// Bouton « Infos » : règles de TOUS les jeux (accueil, menus, tables).
// ----------------------------------------------------------------------

String _rTiah() => tr(
      'TIAH (2 à 6 joueurs) : atteins 21 sans dépasser.\n'
          '• Chacun reçoit 2 cartes. 10 cartes sont posées ouvertes au milieu.\n'
          '• Chacun son tour, un joueur ouvre ses cartes : les cartes du milieu, dans l\'ordre, '
          'viennent à lui tant que le total reste à 21 ou moins. On ne saute jamais une carte.\n'
          '• Le meilleur total (21 maximum) gagne. Deux as en main = TOUCX (22) : il bat tout.\n'
          '• Égalité : le gain est partagé. Chaque joueur a 10 secondes pour agir.\n'
          '• Mise : le gagnant prend la cagnotte moins la commission de Katika. '
          'Des paris entre joueurs (duel) sont possibles pendant la manche.\n• Pari CHAT : avant le départ, chaque joueur choisit un CHAT (1ER CHAT = 1re carte du milieu, 2ÈME CHAT = la suivante, etc.) avec la même mise. La carte de plus grande valeur gagne la cagnotte (commission 5 %). Égalité : la cagnotte est partagée. Un CHAT qui n\'existe pas est remboursé.',
      'TIAH (2-6 players): reach 21 without going over.\n'
          '• Everyone gets 2 cards. 10 cards are laid face up in the middle.\n'
          '• In turn, a player opens his cards: the middle cards, in order, come to him '
          'while his total stays at 21 or less. A card is never skipped.\n'
          '• The best total (21 max) wins. Two aces = TOUCX (22): beats everything.\n'
          '• Tie: the prize is shared. Each player has 10 seconds to act.\n'
          '• Stakes: the winner takes the pot minus Katika\'s commission. Duel bets are possible during the round.\n• CHAT bet: before the start, each player picks a CHAT (1ST CHAT = first middle card, 2ND CHAT = the next, etc.) with the same stake. The highest card value wins the pot (5% commission). Tie: the pot is shared. A CHAT that does not exist is refunded.',
    );

String _rBoubayah() => tr(
      'BOUBAYAH (2 à 6 joueurs) : le plus gros total gagne.\n'
          '• Chacun reçoit 3 cartes simples puis 2 cartes BOUBAYAH, cachées jusqu\'à l\'ouverture.\n'
          '• Seul le total des 2 cartes BOUBAYAH compte. MILLION (deux 3) bat tout ; il sort un peu plus souvent que le hasard pur (environ 6 % par joueur et par manche).\n'
          '• Les joueurs ouvrent leurs cartes à tour de rôle (10 secondes chacun).\n'
          '• Égalité : le gain est partagé.\n'
          '• Mise : le gagnant prend la cagnotte moins la commission de Katika. '
          'Paris possibles : duel et Défi Fétiche 13.',
      'BOUBAYAH (2-6 players): the highest total wins.\n'
          '• Everyone gets 3 plain cards then 2 BOUBAYAH cards, hidden until opened.\n'
          '• Only the total of the 2 BOUBAYAH cards counts. MILLION (two 3s) beats everything; it comes up a bit more often than pure chance (about 6% per player each round).\n'
          '• Players open their cards in turn (10 seconds each).\n'
          '• Tie: the prize is shared.\n'
          '• Stakes: the winner takes the pot minus Katika\'s commission. Bets: duel and Fetish 13 challenge.',
    );

String _rFapFap() => tr(
      'FAP-FAP (2 à 4 joueurs, en ligne uniquement)\n'
          '• 31 cartes (3 à 10, sans le 10 de pique), 5 cartes chacun, 5 plis.\n'
          '• Il faut fournir la famille demandée si on peut. Le plus haut de la famille demandée gagne le pli et entame le suivant.\n'
          '• Combinaisons dès la distribution (la meilleure gagne tout de suite) : quatre 7 > total 16 (quatre 3 et un 4) > trois 7 > '
          'quatre cartes du même numéro (le plus petit numéro gagne) > total de 21 ou moins. Égalité : le 1er après le distributeur.\n'
          '• Sinon, le gagnant du dernier pli gagne ; avec un 3 : COURAT, gain doublé.\n'
          '• Après un 10 de la famille demandée (le 9 de pique remplace le 10 de pique), tu peux déjà jouer ta prochaine carte de cette famille.\n'
          '• Sans carte de la famille demandée, ta carte part toute seule, de la plus grande à la plus petite (le 3 reste pour la fin). Dernière carte : jouée seule.\n'
          '• 10 secondes par carte. 2 × la mise est bloquée : victoire normale = tu récupères ta mise et le gagnant prend les mises adverses.\n'
          '• À 3 ou 4 joueurs : localisation obligatoire et 150 m minimum entre les joueurs ; capture d\'écran bloquée sur Android.',
      'FAP-FAP (2-4 players, online only)\n'
          '• 31 cards (3 to 10, no 10 of spades), 5 cards each, 5 tricks.\n'
          '• Follow the led suit if you can. The highest card of the led suit wins the trick and leads the next.\n'
          '• Deal combinations win at once: four 7s > total 16 (four 3s and a 4) > three 7s > four of a kind (lowest number wins) > total of 21 or less. Tie: first after the dealer.\n'
          '• Otherwise the last trick winner wins; with a 3: COURAT, double win.\n'
          '• After a 10 of the led suit (the 9 of spades replaces the missing 10 of spades) you may already play your next card of that suit.\n'
          '• With no card of the led suit, your card is played automatically, highest to lowest (the 3 stays for last). Last card: played automatically.\n'
          '• 10 seconds per card. 2 x stake is locked: normal win = you get your stake back and the winner takes the others.\n'
          '• With 3-4 players: location required and 150 m minimum between players; screenshots blocked on Android.',
    );

String _rAntiCote() => tr(
      'ANTI-COTE (2 à 5 joueurs, en ligne uniquement)\n'
          '• 3 cartes chacun, plus (joueurs + 1) cartes ouvertes au milieu.\n'
          '• Chacun joue 1 carte de la famille de la 1re carte du milieu (sinon n\'importe laquelle). Le plus haut ouvre en premier, '
          'puis chacun ouvre ses 2 cartes : les cartes du milieu viennent à lui tant que son total reste ≤ 21.\n'
          '• Victoires immédiates à la distribution : trois 7 > brelan (le plus petit) > total 10 > total 11.\n'
          '• THOUX : deux as restants. Trois 7 pris au milieu : CORAT. Un 3 seul de la famille jouée : CORAT. Sinon le plus haut total gagne (THIAH = 21).\n'
          '• CORAT : chaque adversaire paie 2 mises. Total inférieur à 18 = Koraté (paie 2 mises si le gagnant a 18 ou plus).\n'
          '• Égalité : tout le monde rejoue et remet sa mise, les Koratés le double (cagnotte) ; le vainqueur prend tout.\n'
          '• 10 secondes par action. À 3 joueurs ou plus : localisation obligatoire, 150 m minimum.\n'
          '• Défis : pendant la création de la table, deux joueurs peuvent se défier en misant entre eux. '
          'Le gagnant de la manche gagne son défi ; si un tiers gagne, le meilleur total gagne le défi.\n• Pari CHAT : avant le départ, chaque joueur choisit un CHAT (1ER CHAT = 1re carte du milieu, 2ÈME CHAT = la suivante, etc.) avec la même mise. La carte de plus grande valeur gagne la cagnotte (commission 5 %). Égalité : la cagnotte est partagée. Un CHAT qui n\'existe pas est remboursé.',
      'ANTI-COTE (2-5 players, online only)\n'
          '• 3 cards each, plus (players + 1) cards face up in the middle.\n'
          '• Everyone plays 1 card of the suit of the first middle card (otherwise any). The highest opens first, '
          'then everyone opens his 2 cards: middle cards come to him while his total stays <= 21.\n'
          '• Instant wins on the deal: three 7s > three of a kind (lowest) > total 10 > total 11.\n'
          '• THOUX: two aces left. Three 7s taken from the middle: CORAT. A lone 3 of the led suit: CORAT. Otherwise the highest total wins (THIAH = 21).\n'
          '• CORAT: each opponent pays 2 stakes. Total under 18 = Koraté (pays 2 stakes if the winner has 18 or more).\n'
          '• Tie: everyone replays and re-stakes, Koraté players double (jackpot); the winner takes all.\n'
          '• 10 seconds per action. With 3+ players: location required, 150 m minimum.\n'
          '• Challenges: while the table is being created, two players can bet against each other. '
          'The round winner wins his challenge; if a third player wins, the best total wins it.\n• CHAT bet: before the start, each player picks a CHAT (1ST CHAT = first middle card, 2ND CHAT = the next, etc.) with the same stake. The highest card value wins the pot (5% commission). Tie: the pot is shared. A CHAT that does not exist is refunded.',
    );

String _rTchek() => tr(
      'TCHEK GAMES (2 à 4 joueurs, en ligne uniquement)\n'
          '• 54 cartes (2 jokers), 4 cartes chacun. Se débarrasser de toutes ses cartes en premier.\n'
          '• On pose une carte de la même famille ou du même numéro que la dernière. Pioche volontaire possible (1 carte, le tour s\'arrête).\n'
          '• AS : le suivant passe son tour. 7 : +2 cartes. Joker : +4 cartes (rouge sur carte rouge, noir sur carte noire). '
          'Les pénalités se cumulent ; on riposte avec un 7 ou un joker, sinon on pioche tout et on perd son tour.\n'
          '• J : se pose sur toutes les familles et permet de choisir librement la famille suivante.\n'
          '• TCHEK : à annoncer en posant l\'avant-dernière carte, sinon +1 carte. La dernière carte peut être n\'importe laquelle.\n'
          '• 10 secondes par tour. À 3 ou 4 joueurs : localisation obligatoire, 150 m minimum entre joueurs.\n'
          '• Défis : pendant la création de la table, deux joueurs peuvent se défier en misant entre eux. '
          'Le gagnant de la manche gagne son défi ; si un tiers gagne, celui qui a le moins de cartes à la fin gagne le défi.',
      'TCHEK GAMES (2-4 players, online only)\n'
          '• 54 cards (2 jokers), 4 cards each. Be the first to get rid of all your cards.\n'
          '• Play a card of the same suit or number as the last one. You may draw 1 card voluntarily (your turn ends).\n'
          '• ACE: next player skips. 7: +2 cards. Joker: +4 cards (red on red, black on black). '
          'Penalties stack; reply with a 7 or a joker, otherwise draw them all and lose your turn.\n'
          '• J: can be played on any suit and lets you freely choose the next suit.\n'
          '• TCHEK: call it when playing your second-to-last card, otherwise +1 card. Any card can be the last one.\n'
          '• 10 seconds per turn. With 3-4 players: location required, 150 m minimum between players.\n'
          '• Challenges: while the table is being created, two players can bet against each other. '
          'The round winner wins his challenge; if a third player wins, the one with the fewest cards left wins it.',
    );

/// Noms des familles de cartes (comme sur les cartes).
String _rFamilies() => tr(
      'Familles : Carreau = Zing · Trèfle = Tchaka · Cœur = Koubi · Pique = Black.',
      'Suits: Diamonds = Zing · Clubs = Tchaka · Hearts = Koubi · Spades = Black.',
    );

String rulesTitle(String key) {
  switch (key) {
    case 'ludo':
      return tr('Règles du Ludo', 'Ludo rules');
    case 'deuxdes':
      return tr('Règles de Deux dés', 'Two dice rules');
    case 'tiah':
      return tr('Règles du TIAH', 'TIAH rules');
    case 'boubayah':
      return tr('Règles du BOUBAYAH', 'BOUBAYAH rules');
    case 'fapfap':
      return tr('Règles du FAP-FAP', 'FAP-FAP rules');
    case 'anticote':
      return tr('Règles d\'ANTI-COTE', 'ANTI-COTE rules');
    case 'tchek':
      return tr('Règles de TCHEK GAMES', 'TCHEK GAMES rules');
    case 'cartes':
      return tr('Jeux de cartes', 'Card games');
  }
  return tr('Règles', 'Rules');
}

String rulesBody(String key) {
  switch (key) {
    case 'ludo':
      return kLudoRules;
    case 'deuxdes':
      return kDeuxDesRules;
    case 'tiah':
      return '${_rTiah()}\n\n${_rFamilies()}';
    case 'boubayah':
      return '${_rBoubayah()}\n\n${_rFamilies()}';
    case 'fapfap':
      return '${_rFapFap()}\n\n${_rFamilies()}';
    case 'anticote':
      return '${_rAntiCote()}\n\n${_rFamilies()}';
    case 'tchek':
      return '${_rTchek()}\n\n${_rFamilies()}';
    case 'cartes':
      return '${_rFamilies()}\n\n${_rTiah()}\n\n${_rBoubayah()}\n\n${_rFapFap()}\n\n${_rAntiCote()}\n\n${_rTchek()}';
  }
  return '';
}

/// Ouvre la fenêtre « Infos » d'un jeu (clés : ludo, deuxdes,
/// tiah, boubayah, fapfap, anticote, tchek, cartes).
void showGameInfo(BuildContext context, String key) =>
    showRulesDialog(context, rulesTitle(key), rulesBody(key));

/// Petit bouton rond « i » à poser sur une tuile ou une barre de jeu.
class GameInfoButton extends StatelessWidget {
  const GameInfoButton({super.key, required this.gameKey, this.size = 30});

  final String gameKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showGameInfo(context, gameKey),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.35),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: Icon(Icons.info_outline, color: Colors.white, size: size * 0.62),
      ),
    );
  }
}
