
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Configuration publique des mises à jour Katika.
const String kUpdateConfigUrl =
    'https://raw.githubusercontent.com/yveslaurent85/katikagames-web/main/update.json';

bool _updateChecked = false;

class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _check();
    });
  }

  Future<void> _check() async {
    if (kIsWeb || _updateChecked) return;

    _updateChecked = true;

    try {
      // Numéro de compilation installé.
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // Évite de récupérer une ancienne configuration en cache.
      final configUri = Uri.parse(
        '$kUpdateConfigUrl?cache=${DateTime.now().millisecondsSinceEpoch}',
      );

      final response = await http
          .get(
            configUri,
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final latestBuild =
          int.tryParse('${data['latestBuild'] ?? 0}') ?? 0;

      final version = '${data['version'] ?? ''}';

      final message = '${data['message'] ??
          'Une nouvelle version de Katika est disponible.'}';

      // true = obligatoire ; false = facultative.
      final isRequired = data['required'] == true;

      final apkUrl = '${data['apkUrl'] ?? ''}';

      if (latestBuild <= 0 || currentBuild <= 0) return;
      if (latestBuild <= currentBuild) return;
      if (apkUrl.isEmpty) return;

      final apkUri = Uri.tryParse(apkUrl);

      if (apkUri == null ||
          !apkUri.hasAuthority ||
          !['https', 'http'].contains(apkUri.scheme)) {
        return;
      }

      if (!mounted) return;

      await _showUpdateDialog(
        latestBuild: latestBuild,
        version: version,
        message: message,
        isRequired: isRequired,
        apkUri: apkUri,
      );
    } catch (e) {
      // Si Internet ou GitHub est inaccessible,
      // Katika continue de fonctionner normalement.
    }
  }

  Future<void> _showUpdateDialog({
    required int latestBuild,
    required String version,
    required String message,
    required bool isRequired,
    required Uri apkUri,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !isRequired,
      builder: (BuildContext ctx) {
        return PopScope(
          canPop: !isRequired,
          child: AlertDialog(
            backgroundColor: const Color(0xFF14267A),
            title: Text(
              isRequired
                  ? 'Mise à jour obligatoire'
                  : 'Nouvelle version disponible',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              '$message\n\n'
              'Version : ${version.isEmpty ? latestBuild : version}\n'
              'Compilation : $latestBuild\n\n'
              '${isRequired ? 'Tu dois installer cette mise à jour pour continuer à utiliser Katika.' : 'Tu peux installer cette mise à jour maintenant ou choisir de le faire plus tard.'}',
              style: const TextStyle(
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            actions: [
              if (!isRequired)
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
                  try {
                    final opened = await launchUrl(
                      apkUri,
                      mode: LaunchMode.externalApplication,
                    );

                    if (!opened && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Impossible d’ouvrir le téléchargement. Réessaie.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Erreur lors de l’ouverture du téléchargement.',
                          ),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Télécharger la mise à jour'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
