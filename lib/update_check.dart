
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dernière version publiée sur GitHub Releases et lien de l'APK.
const String kReleaseApi =
    'https://api.github.com/repos/yveslaurent85/katikagames-web/releases/latest';

const String kApkUrl =
    'https://github.com/yveslaurent85/katikagames-web/releases/latest/download/Katika.apk';

bool _updateChecked = false;

/// Vérifie une seule fois par lancement si une mise à jour est disponible.
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _check();
    });
  }

  Future<void> _check() async {
    if (kIsWeb || _updateChecked) return;

    _updateChecked = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;

      final response = await http
          .get(
            Uri.parse(kReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final versionMatch =
          RegExp(r'(\d+)').firstMatch('${data['name'] ?? ''}');

      final latest =
          versionMatch == null ? 0 : int.parse(versionMatch.group(1)!);

      if (current > 0 && latest > current && mounted) {
        await _showDialog(latest);
      }
    } catch (e) {
      // Pas de connexion ou GitHub inaccessible : aucune interruption.
    }
  }

  Future<void> _showDialog(int latest) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14267A),
          title: const Text(
            'Nouvelle version disponible',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Une version plus récente de Katika (n° $latest) est disponible. '
            'Télécharge-la et installe-la par-dessus : tes données sont '
            'conservées.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
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
                } catch (e) {
                  // Le téléchargement pourra être réessayé plus tard.
                }
              },
              child: const Text('Télécharger'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
