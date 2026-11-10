import 'package:flutter/material.dart' hide Text;

import 'lang.dart';

/// Gros bouton « Créer une partie » des salons en ligne : il ouvre les options de création.
Widget lobbyCreateButton(VoidCallback onTap, {String? label}) {
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22B14C),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.add_circle_outline),
        label: Text(
          label ?? tr('Créer une partie', 'Create a game'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );
}

/// Retour des options de création vers la liste des parties.
Widget lobbyBackButton(VoidCallback onTap) {
  return Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
      label: Text(
        tr('Retour aux parties', 'Back to games'),
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// Titre d'une rubrique du salon (« Parties ouvertes », « Parties en cours »).
Widget lobbySectionTitle(String s) {
  return Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(
      s,
      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
    ),
  );
}
