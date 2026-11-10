import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

/// Impression de tickets sur imprimante thermique Bluetooth (58 mm).
///
/// Principe : on fabrique les octets ESC/POS puis on les confie à l'appli
/// Android gratuite « RawBT » (via un lien rawbt:base64,…). RawBT sait parler
/// à presque toutes les imprimantes thermiques Bluetooth (jumelées dans les
/// réglages Bluetooth du téléphone). Aucun plugin natif n'est nécessaire.
class ThermalPrint {
  static const int width = 32; // caractères par ligne (papier 58 mm)

  /// Retire les accents (les imprimantes bon marché ne les gèrent pas tous).
  static String ascii(String s) {
    const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ’‘“”«»–—…€';
    const to = 'aaaaaceeeeiiiinooooouuuuyyAAAAACEEEEIIIINOOOOOUUUUY\'\'""""--.E';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      if (i >= 0) {
        b.write(to[i]);
      } else if (r < 128) {
        b.write(c);
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

  /// Ligne « gauche ........ droite ».
  static String row(String left, String right) {
    final l = ascii(left), r = ascii(right);
    final gap = width - l.length - r.length;
    if (gap >= 1) return l + ' ' * gap + r;
    return '${_cut(l, width - r.length - 1)} $r';
  }

  static List<int> build(Map<String, dynamic> t, {bool copy = false}) {
    final b = <int>[];
    void raw(List<int> x) => b.addAll(x);
    void line(String s) {
      b.addAll(ascii(s).codeUnits);
      b.add(10);
    }

    raw([0x1B, 0x40]); // init
    raw([0x1B, 0x74, 0x00]);
    raw([0x1B, 0x61, 1]); // centre
    raw([0x1B, 0x45, 1]);
    raw([0x1D, 0x21, 0x11]); // double taille
    line('KATIKA');
    raw([0x1D, 0x21, 0x00]);
    line('PARI COURSES');
    raw([0x1B, 0x45, 0]);
    line('-' * width);
    raw([0x1B, 0x61, 0]); // gauche
    final at = DateTime.fromMillisecondsSinceEpoch(
      (t['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    line(row('Ticket', '#${t['no']}'));
    line(row('Date', '${two(at.day)}/${two(at.month)}/${at.year} ${two(at.hour)}:${two(at.minute)}'));
    line(row('Course', '${t['race']}'));
    line(row('Formule', '${t['formula']}'));
    line(row('Caissiere', '${t['by']}'));
    line('-' * width);
    raw([0x1B, 0x61, 1]);
    raw([0x1B, 0x45, 1]);
    raw([0x1D, 0x21, 0x11]);
    line(((t['picks'] as List?) ?? const []).join(' - '));
    raw([0x1D, 0x21, 0x00]);
    raw([0x1B, 0x45, 0]);
    raw([0x1B, 0x61, 0]);
    line('-' * width);
    line(row('Coefficient', 'x${t['coef']}'));
    raw([0x1B, 0x45, 1]);
    line(row('MISE', '${t['stake']} FCFA'));
    raw([0x1B, 0x45, 0]);
    line('-' * width);
    raw([0x1B, 0x61, 1]);
    line('Gains payes sur presentation');
    line('de ce ticket apres la course.');
    line('Conservez-le. Jouez avec moderation.');
    if (copy) {
      raw([0x1B, 0x45, 1]);
      line('*** DUPLICATA ***');
      raw([0x1B, 0x45, 0]);
    }
    raw([0x0A, 0x0A, 0x0A, 0x0A]);
    raw([0x1D, 0x56, 0x00]); // coupe (ignoré si absent)
    return b;
  }

  /// Envoie le ticket à RawBT. Renvoie false si l'appli n'est pas installée.
  static Future<bool> printTicket(Map<String, dynamic> t, {bool copy = false}) async {
    final data = base64.encode(build(t, copy: copy));
    final uri = Uri.parse('rawbt:base64,$data');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
