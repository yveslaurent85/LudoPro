
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateChecker {
  static const String versionUrl =
      'https://raw.githubusercontent.com/yveslaurent85/katikagames-web/main/version.json';

  static Future<void> check(BuildContext context) async {
    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final latestVersion = data['latestVersion'] as String?;
      final minimumVersion = data['minimumVersion'] as String?;
      final apkUrl = data['apkUrl'] as String?;
      final message = data['message'] as String? ??
          'Une nouvelle version de Katika est disponible.';

      if (latestVersion == null ||
          minimumVersion == null ||
          apkUrl == null ||
          !context.mounted) {
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      if (!context.mounted) return;

      final installedVersion = packageInfo.version;

      final mustUpdate =
          _compareVersions(installedVersion, minimumVersion) < 0;
      final hasUpdate =
          _compareVersions(installedVersion, latestVersion) < 0;

      if (!mustUpdate && !hasUpdate) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !mustUpdate,
        builder: (dialogContext) {
          return PopScope(
            canPop: !mustUpdate,
            child: AlertDialog(
              title: Text(
                mustUpdate
                    ? 'Mise à jour obligatoire'
                    : 'Mise à jour disponible',
              ),
              content: Text(
                mustUpdate
                    ? 'Ta version de Katika est trop ancienne. '
                        'Mets l’application à jour pour continuer.\n\n$message'
                    : '$message\n\n'
                        'Version installée : $installedVersion\n'
                        'Nouvelle version : $latestVersion',
              ),
              actions: [
                if (!mustUpdate)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Plus tard'),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(apkUrl);
                    if (uri == null ||
                        uri.scheme != 'https' ||
                        !await canLaunchUrl(uri)) {
                      return;
                    }

                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text('Mettre à jour'),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      // En cas de problème Internet, Katika peut continuer normalement.
    }
  }

  static int _compareVersions(String first, String second) {
    final a = first.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final b = second.split('.').map((v) => int.tryParse(v) ?? 0).toList();

    final length = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < length; i++) {
      final partA = i < a.length ? a[i] : 0;
      final partB = i < b.length ? b[i] : 0;

      if (partA < partB) return -1;
      if (partA > partB) return 1;
    }

    return 0;
  }
}
