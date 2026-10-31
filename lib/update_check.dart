import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dernière version publiée (GitHub Releases du site) et lien de l'APK.
const String kReleaseApi =
'https://api.github.com/repos/yveslaurent85/katikagames-web/releases/latest';
const String kApkUrl =
'https://github.com/yveslaurent85/katikagames-web/releases/latest/download/Katika.apk';

bool _updateChecked = false; // une seule vérification par lancement

/// Widget invisible à placer sur l'accueil : au premier affichage, il compare
/// la version installée à la dernière version publiée et propose la mise à
/// jour si une version plus récente existe.
class UpdateChecker extends StatefulWidget {
const UpdateChecker({super.key});

@override
State<UpdateChecker> createState() => _UpdateCheckerState();
}

class UpdateCheckerState extends State<UpdateChecker> {
@override
void initState() {
super.initState();
WidgetsBinding.instance.addPostFrameCallback(() => _check());
}

Future<void> _check() async {
if (kIsWeb || _updateChecked) return;
_updateChecked = true;
try {
final info = await PackageInfo.fromPlatform();
final current = int.tryParse(info.buildNumber) ?? 0;
final res = await http
.get(
Uri.parse(kReleaseApi),
headers: const {'Accept': 'application/vnd.github+json'},
)
.timeout(const Duration(seconds: 8));
if (res.statusCode != 200) return;
final j = jsonDecode(res.body) as Map<String, dynamic>;
final m = RegExp(r'(\d+)').firstMatch('${j['name'] ?? ''}');
final latest = m == null ? 0 : int.parse(m.group(1)!);
if (current > 0 && latest > current && mounted) {
await showDialog(latest);
}
} catch () {
// Pas de connexion ou GitHub injoignable : on ne dit rien.
}
}

Future<void> showDialog(int latest) {
return showDialog<void>(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: const Color(0xFF14267A),
title: const Text(
'Nouvelle version disponible',
style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
),
content: Text(
'Une version plus récente de Katika (n° $latest) est disponible. '
'Télécharge-la et installe-la par-dessus : tes données sont '
'conservées.',
style: const TextStyle(color: Colors.white70),
),
actions: [
TextButton(
onPressed: () => Navigator.of(ctx).pop(),
child: const Text('Plus tard'),
),
ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: const Color(0xFF22B14C),
foregroundColor: Colors.white,
),
onPressed: () async {
Navigator.of(ctx).pop();
try {
await launchUrl(
Uri.parse(kApkUrl),
mode: LaunchMode.externalApplication,
);
} catch () {}
},
child: const Text('Télécharger'),
),
],
),
);
}

@override
Widget build(BuildContext context) => const SizedBox.shrink();
}
