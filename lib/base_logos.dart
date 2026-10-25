import 'package:flutter/material.dart';

// ----------------------------------------------------------------------
// Logos Katika dans les 4 bases du plateau (Rouge, Vert, Bleu, Jaune).
// Les images sont dans le dossier assets/ (voir pubspec.yaml).
// ----------------------------------------------------------------------

/// Un logo par couleur, dans l'ordre des joueurs : Rouge, Vert, Bleu, Jaune.
const List<String> kBaseLogos = [
  'assets/katika_logo_rouge.png',
  'assets/katika_logo.png', // vert
  'assets/katika_logo_bleu.png',
  'assets/katika_logo_jaune.png',
];

/// Dessine chaque logo au centre de sa base. [c] = taille d'une case.
/// À placer dans le Stack du plateau, AVANT les pions (ils passent dessus).
List<Widget> buildBaseLogos(double c) {
  const double size = 3.4; // taille du logo, en cases (la base fait 6 cases)
  const double offset = (6 - size) / 2; // centré dans la base

  return [
    for (int p = 0; p < 4; p++)
      Positioned(
        left: (((p == 0 || p == 3) ? 0 : 9) + offset) * c,
        top: ((p < 2 ? 0 : 9) + offset) * c,
        width: size * c,
        height: size * c,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c * 0.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: c * 0.35,
                  offset: Offset(0, c * 0.12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(c * 0.4),
              child: Image.asset(
                kBaseLogos[p],
                fit: BoxFit.cover,
                cacheWidth: 400,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
  ];
}
