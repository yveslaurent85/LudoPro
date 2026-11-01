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
