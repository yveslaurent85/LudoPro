import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

class BoutonTelechargerApk extends StatelessWidget {
  const BoutonTelechargerApk({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return ElevatedButton.icon(
      onPressed: () => launchUrl(
        Uri.base.resolve('katika.apk'),
        webOnlyWindowName: '_self',
      ),
      icon: const Icon(Icons.android),
      label: const Text("Télécharger l'application Android"),
    );
  }
}
