import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:firebase_auth/firebase_auth.dart';

import 'accounts.dart';
import 'lang.dart';

/// ZONING : ville du joueur, administration des zones, espace partenaire.

const Color _gold = Color(0xFFFFC21A);

/// Régions et principales villes du Cameroun (liste structurée). « Autre ville » = saisie libre.
const Map<String, List<String>> kCmCities = {
  'Adamaoua': ['Ngaoundéré', 'Meiganga', 'Tibati', 'Banyo', 'Tignère'],
  'Centre': ['Yaoundé', 'Mbalmayo', 'Bafia', 'Obala', 'Mfou', 'Akonolinga', 'Eséka', 'Monatélé'],
  'Est': ['Bertoua', 'Batouri', 'Abong-Mbang', 'Yokadouma', 'Garoua-Boulaï'],
  'Extrême-Nord': ['Maroua', 'Kousséri', 'Mokolo', 'Yagoua', 'Kaélé'],
  'Littoral': ['Douala', 'Edéa', 'Nkongsamba', 'Loum', 'Mbanga', 'Yabassi'],
  'Nord': ['Garoua', 'Guider', 'Figuil', 'Poli', 'Tcholliré'],
  'Nord-Ouest': ['Bamenda', 'Kumbo', 'Wum', 'Nkambé', 'Mbengwi'],
  'Ouest': ['Bafoussam', 'Dschang', 'Mbouda', 'Bafang', 'Foumban', 'Bangangté', 'Foumbot'],
  'Sud': ['Ebolowa', 'Kribi', 'Sangmélima', 'Ambam', 'Campo'],
  'Sud-Ouest': ['Buea', 'Limbe', 'Kumba', 'Mamfe', 'Tiko', 'Mutengene'],
};

/// Vrai quand le compte connecté est un partenaire exclusif de zone (menu « Mon espace partenaire »).
final ValueNotifier<bool> kZonePartner = ValueNotifier<bool>(false);

String _fcfa(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b FCFA';
}

BoxDecoration get _bg => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF3F6FF), Color(0xFFF3F6FF)],
      ),
    );

// ----------------------------------------------------------------------
// Ville du joueur
// ----------------------------------------------------------------------

/// Demande la ville au joueur connecté qui n'en a pas encore (obligatoire) et
/// retient s'il est partenaire. À placer autour de l'écran d'accueil.
class CityGate extends StatefulWidget {
  const CityGate({super.key, required this.child});

  final Widget child;

  @override
  State<CityGate> createState() => _CityGateState();
}

class _CityGateState extends State<CityGate> {
  StreamSubscription<User?>? _sub;
  String _checked = '';
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u == null) {
          kZonePartner.value = false;
          _checked = '';
        } else {
          _check(u.uid);
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check(String uid) async {
    if (_checked == uid || _showing) return;
    _checked = uid;
    try {
      final me = await Wallet.zoneMe();
      kZonePartner.value = me['isPartner'] == true;
      if (me['hasCity'] != true && mounted) {
        _showing = true;
        await showCityDialog(context, mandatory: true);
        _showing = false;
      }
    } catch (_) {
      _checked = ''; // on réessaiera à la prochaine connexion
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Choix de la ville. [mandatory] : première déclaration (obligatoire) ;
/// sinon : demande de changement de ville (examinée par l'administration).
Future<void> showCityDialog(BuildContext context, {bool mandatory = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (ctx) => _CityDialog(mandatory: mandatory),
  );
}

class _CityDialog extends StatefulWidget {
  const _CityDialog({required this.mandatory});

  final bool mandatory;

  @override
  State<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends State<_CityDialog> {
  static const String _other = '__other__';
  String? _region;
  String? _city;
  final _otherCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _otherCtrl.dispose();
    _quarterCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  String get _cityName => _city == _other ? _otherCtrl.text.trim() : (_city ?? '');

  Future<void> _submit() async {
    if (_region == null || _cityName.isEmpty) {
      setState(() => _err = tr('Choisis ta région et ta ville.', 'Pick your region and city.'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (widget.mandatory) {
        await Wallet.playerSetCity(region: _region!, city: _cityName, quarter: _quarterCtrl.text.trim());
      } else {
        await Wallet.cityChangeRequest(region: _region!, city: _cityName, reason: _reasonCtrl.text.trim());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.mandatory) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Demande envoyée : l\'administration va l\'examiner.', 'Request sent: the administration will review it.'))));
      }
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cities = _region == null ? <String>[] : (kCmCities[_region] ?? <String>[]);
    return PopScope(
      canPop: !widget.mandatory,
      child: AlertDialog(
        backgroundColor: const Color(0xFFF3F6FF),
        title: Text(
          widget.mandatory ? tr('Où habites-tu ?', 'Where do you live?') : tr('Changer de ville', 'Change city'),
          style: const TextStyle(color: Color(0xFF9A6B00), fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              widget.mandatory
                  ? tr('Indique ta région et ta ville. Cette information est obligatoire et ne pourra plus être changée librement.',
                      'Enter your region and city. This is required and cannot be changed freely later.')
                  : tr('Ta demande sera examinée par l\'administration. Tant qu\'elle n\'est pas acceptée, ta ville ne change pas.',
                      'The administration will review your request. Your city does not change until it is accepted.'),
              style: const TextStyle(color: Color(0xFF56608A), fontSize: 12),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _region,
              isExpanded: true,
              dropdownColor: Color(0xFF12183A),
              style: const TextStyle(color: Color(0xFF12183A)),
              decoration: InputDecoration(labelText: tr('Région', 'Region'), labelStyle: const TextStyle(color: Color(0xFF56608A))),
              items: [for (final r in kCmCities.keys) DropdownMenuItem(value: r, child: Text(r))],
              onChanged: (v) => setState(() {
                _region = v;
                _city = null;
              }),
            ),
            DropdownButtonFormField<String>(
              value: _city,
              isExpanded: true,
              dropdownColor: Color(0xFF12183A),
              style: const TextStyle(color: Color(0xFF12183A)),
              decoration: InputDecoration(labelText: tr('Ville', 'City'), labelStyle: const TextStyle(color: Color(0xFF56608A))),
              items: [
                for (final c in cities) DropdownMenuItem(value: c, child: Text(c)),
                if (_region != null) DropdownMenuItem(value: _other, child: Text(tr('Autre ville…', 'Other city…'))),
              ],
              onChanged: (v) => setState(() => _city = v),
            ),
            if (_city == _other)
              TextField(
                controller: _otherCtrl,
                style: const TextStyle(color: Color(0xFF12183A)),
                decoration: InputDecoration(labelText: tr('Nom de ta ville', 'Your city name'), labelStyle: const TextStyle(color: Color(0xFF56608A))),
              ),
            if (widget.mandatory)
              TextField(
                controller: _quarterCtrl,
                style: const TextStyle(color: Color(0xFF12183A)),
                decoration: InputDecoration(labelText: tr('Quartier (facultatif)', 'District (optional)'), labelStyle: const TextStyle(color: Color(0xFF56608A))),
              )
            else
              TextField(
                controller: _reasonCtrl,
                style: const TextStyle(color: Color(0xFF12183A)),
                decoration: InputDecoration(labelText: tr('Raison (facultatif)', 'Reason (optional)'), labelStyle: const TextStyle(color: Color(0xFF56608A))),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        actions: [
          if (!widget.mandatory)
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(widget.mandatory ? tr('Valider', 'Confirm') : tr('Envoyer la demande', 'Send request'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

/// Écran « Ma ville » : ville actuelle + demande de changement.
class MyCityScreen extends StatefulWidget {
  const MyCityScreen({super.key});

  @override
  State<MyCityScreen> createState() => _MyCityScreenState();
}

class _MyCityScreenState extends State<MyCityScreen> {
  Map<String, dynamic>? _me;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Wallet.zoneMe();
      if (mounted) setState(() => _me = m);
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _me;
    return Scaffold(
      body: Container(
        decoration: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Color(0xFF12183A))),
              Text(tr('Ma ville', 'My city'),
                  style: const TextStyle(color: Color(0xFF12183A), fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            Expanded(
              child: m == null
                  ? Center(
                      child: _err != null
                          ? Text(_err!, style: const TextStyle(color: Color(0xFF12183A)))
                          : const CircularProgressIndicator(color: _gold))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(18)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['hasCity'] == true ? '📍 ${m['city']}' : tr('Ville non renseignée', 'City not set'),
                              style: const TextStyle(color: Color(0xFF12183A), fontSize: 20, fontWeight: FontWeight.w900)),
                          if (m['hasCity'] == true)
                            Text('${m['region']}${'${m['quarter']}'.isEmpty ? '' : ' · ${m['quarter']}'}',
                                style: const TextStyle(color: Color(0xFF56608A))),
                          const SizedBox(height: 6),
                          Text(
                            m['attached'] == true
                                ? tr('Tu es suivi par le partenaire officiel de ta ville.', 'You are managed by your city\'s official partner.')
                                : tr('Ta ville n\'a pas encore de partenaire : tu es géré directement par Katika.',
                                    'Your city has no partner yet: you are managed directly by Katika.'),
                            style: const TextStyle(color: Color(0xFF68729A), fontSize: 12),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (m['pendingChange'] != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(14)),
                          child: Text(
                            tr('Demande en cours vers ${(m['pendingChange'] as Map)['city']} : en attente de l\'administration.',
                                'Pending request to ${(m['pendingChange'] as Map)['city']}: waiting for the administration.'),
                            style: const TextStyle(color: Color(0xFF5D4300), fontWeight: FontWeight.w700),
                          ),
                        )
                      else if (m['hasCity'] == true)
                        FilledButton.icon(
                          onPressed: () async {
                            await showCityDialog(context);
                            _load();
                          },
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(tr('Demander un changement de ville', 'Request a city change')),
                        )
                      else
                        FilledButton(
                          onPressed: () async {
                            await showCityDialog(context, mandatory: true);
                            _load();
                          },
                          child: Text(tr('Renseigner ma ville', 'Set my city')),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Administration du zoning
// ----------------------------------------------------------------------

class AdminZonesScreen extends StatefulWidget {
  const AdminZonesScreen({super.key});

  @override
  State<AdminZonesScreen> createState() => _AdminZonesScreenState();
}

class _AdminZonesScreenState extends State<AdminZonesScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Wallet.adminZones();
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() f, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await f();
      if (ok != null) _snack(ok);
      if (r['remaining'] is num && (r['remaining'] as num) > 0) {
        _snack('${r['attached']} joueur(s) rattaché(s), il en reste ${r['remaining']} : relance.');
      }
      await _load();
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addZone() async {
    final regions = [for (final r in (_d?['regions'] as List? ?? kCmCities.keys.toList())) '$r'];
    var region = regions.first;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Ajouter une ville'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: region,
              items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
              onChanged: (v) => setS(() => region = v ?? region),
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de la ville')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok == true && n.isNotEmpty) await _run(() => Wallet.adminZoneSave(name: n, region: region), ok: 'Ville enregistrée.');
  }

  Future<void> _assign(Map<String, dynamic> z) async {
    final code = TextEditingController();
    final rate = TextEditingController(text: '${_d?['maxRate'] ?? 10}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Partenaire de ${z['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Un seul partenaire actif par ville : le nouveau remplace l\'ancien à partir de maintenant (l\'historique est conservé).',
              style: TextStyle(fontSize: 12)),
          TextField(controller: code, decoration: const InputDecoration(labelText: 'Code promo du partenaire')),
          TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Taux de commission (max ${_d?['maxRate'] ?? 10} %)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Affecter')),
        ],
      ),
    );
    final c = code.text.trim();
    final r = int.tryParse(rate.text.trim()) ?? 10;
    code.dispose();
    rate.dispose();
    if (ok == true && c.isNotEmpty) {
      await _run(() => Wallet.adminZoneAssign(zoneId: '${z['id']}', code: c, rate: r), ok: 'Partenaire affecté.');
    }
  }

  Future<void> _players(Map<String, dynamic> z) async {
    try {
      final r = await Wallet.adminZonePlayers('${z['id']}');
      final list = [for (final p in (r['players'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Joueurs de ${z['name']} (${list.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? const Text('Aucun joueur.')
                : ListView(shrinkWrap: true, children: [
                    for (final p in list)
                      ListTile(
                        dense: true,
                        title: Text('${p['name']}'),
                        subtitle: Text('${'${p['quarter']}'.isEmpty ? '' : '${p['quarter']} · '}misé ${_fcfa((p['wagered'] as num?)?.toInt() ?? 0)}'),
                        trailing: Text(p['attached'] == true ? 'Partenaire' : 'Centrale',
                            style: TextStyle(color: p['attached'] == true ? Colors.green : Colors.grey, fontWeight: FontWeight.w800)),
                      ),
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
  }

  Future<void> _commissions(Map<String, dynamic> z) async {
    try {
      final r = await Wallet.adminZoneCommissions('${z['id']}');
      final rows = [for (final p in (r['rows'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
      final byGame = Map<String, dynamic>.from((r['byGame'] as Map?) ?? const {});
      final total = (r['total'] as num?)?.toInt() ?? 0;
      final count = (r['count'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Commissions · ${z['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              Text('Partenaire : ${'${z['partnerName']}'.isEmpty ? 'aucun' : z['partnerName']} · ${z['rate']} %',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Total gagné : ${_fcfa(total)} ($count opération(s))', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              if (byGame.isNotEmpty)
                Text([for (final e in byGame.entries) '${e.key} : ${_fcfa((e.value as num).toInt())}'].join(' · '),
                    style: const TextStyle(fontSize: 12)),
              const Divider(),
              if (rows.isEmpty)
                const Text('Aucune commission pour le moment.')
              else
                for (final c in rows)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${c['player']} · ${c['game']}'),
                    subtitle: Text('base ${_fcfa((c['base'] as num?)?.toInt() ?? 0)} · ${c['rate']} % · ${'${c['at']}'.length >= 10 ? '${c['at']}'.substring(0, 10) : ''}'),
                    trailing: Text('+${_fcfa((c['amount'] as num?)?.toInt() ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } catch (e) {
      _snack(Wallet.errorText(e));
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(color: Color(0xFF12183A), fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _zoneTile(Map<String, dynamic> z) {
    final suspended = z['status'] == 'suspended';
    final hasP = '${z['partnerUid']}'.isNotEmpty;
    final n = (z['players'] as num?)?.toInt() ?? 0;
    final a = (z['attached'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: suspended ? const Color(0xFFE5262B) : Color(0xFFD5DEF5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${z['name']} · ${z['region']}', style: const TextStyle(color: Color(0xFF12183A), fontWeight: FontWeight.w900)),
          ),
          if (suspended)
            const Text('SUSPENDUE', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        Text(
          hasP ? 'Partenaire : ${z['partnerName']} · ${z['rate']} %' : 'Aucun partenaire : gestion centrale',
          style: TextStyle(color: hasP ? _gold : Color(0xFF5E6890), fontSize: 13),
        ),
        Text('$n joueur(s) · $a rattaché(s) au partenaire', style: const TextStyle(color: Color(0xFF68729A), fontSize: 12)),
        const SizedBox(height: 6),
        Theme(
         data: Theme.of(context).copyWith(
           textButtonTheme: TextButtonThemeData(
             style: TextButton.styleFrom(
               foregroundColor: Colors.white,
               backgroundColor: Color(0xFFD5DEF5),
               disabledForegroundColor: Color(0xFF8A93B8),
               textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
             ),
           ),
         ),
         child: Wrap(spacing: 8, runSpacing: 6, children: [
          TextButton(onPressed: _busy ? null : () => _assign(z), child: Text(hasP ? 'Changer le partenaire' : 'Affecter un partenaire')),
          if (hasP)
            TextButton(
              onPressed: _busy ? null : () => _run(() => Wallet.adminZoneRelease('${z['id']}'), ok: 'Partenaire retiré.'),
              child: const Text('Retirer'),
            ),
          if (hasP && n > a)
            TextButton(
              onPressed: _busy ? null : () => _run(() => Wallet.adminZoneAttach('${z['id']}'), ok: 'Joueurs rattachés (sans commission rétroactive).'),
              child: const Text('Rattacher les joueurs existants'),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => Wallet.adminZoneStatus('${z['id']}', suspended ? 'active' : 'suspended'),
                    ok: suspended ? 'Zone réactivée.' : 'Zone suspendue.'),
            child: Text(suspended ? 'Réactiver' : 'Suspendre'),
          ),
          TextButton(onPressed: () => _players(z), child: const Text('Joueurs')),
          TextButton(onPressed: () => _commissions(z), child: const Text('Commissions')),
         ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final zones = [for (final z in (d?['zones'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    final reqs = [for (final z in (d?['cityRequests'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    final pays = [for (final z in (d?['payouts'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    return Scaffold(
      body: Container(
        decoration: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Color(0xFF12183A))),
              const Expanded(
                child: Text('🗺️ Administration du zoning',
                    style: TextStyle(color: Color(0xFF12183A), fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh, color: Color(0xFF12183A))),
            ]),
            Expanded(
              child: d == null
                  ? Center(
                      child: _err != null
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: SelectableText(_err!, style: const TextStyle(color: Color(0xFFD32F2F))))
                          : const CircularProgressIndicator(color: _gold))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _addZone,
                          icon: const Icon(Icons.add_location_alt),
                          label: const Text('Ajouter une ville'),
                        ),
                        if (reqs.isNotEmpty) ...[
                          _title('Demandes de changement de ville (${reqs.length})'),
                          for (final r in reqs)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(14)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${r['name']} : ${r['from']} → ${r['to']} (${r['toRegion']})',
                                    style: const TextStyle(color: Color(0xFF3A2A00), fontWeight: FontWeight.w900)),
                                if ('${r['reason']}'.isNotEmpty)
                                  Text('Raison : ${r['reason']}', style: const TextStyle(color: Color(0xFF5D4300), fontSize: 12)),
                                Row(children: [
                                  TextButton(
                                    onPressed: _busy ? null : () => _run(() => Wallet.adminCityChangeDecide('${r['id']}', true), ok: 'Changement accepté.'),
                                    child: const Text('Accepter'),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : () => _run(() => Wallet.adminCityChangeDecide('${r['id']}', false), ok: 'Demande refusée.'),
                                    child: const Text('Refuser'),
                                  ),
                                ]),
                              ]),
                            ),
                        ],
                        if (pays.isNotEmpty) ...[
                          _title('Paiements de commission à valider (${pays.length})'),
                          for (final p in pays)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFDDF8E4), borderRadius: BorderRadius.circular(14)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${p['name']} : ${_fcfa((p['amount'] as num?)?.toInt() ?? 0)}',
                                    style: const TextStyle(color: Color(0xFF0B3D1A), fontWeight: FontWeight.w900)),
                                Row(children: [
                                  TextButton(
                                    onPressed: _busy ? null : () => _run(() => Wallet.adminZonePayoutDecide('${p['id']}', true), ok: 'Paiement validé : versé sur son solde.'),
                                    child: const Text('Valider'),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : () => _run(() => Wallet.adminZonePayoutDecide('${p['id']}', false), ok: 'Paiement refusé : remis à disposition.'),
                                    child: const Text('Refuser'),
                                  ),
                                ]),
                              ]),
                            ),
                        ],
                        _title('Villes (${zones.length})'),
                        if (zones.isEmpty)
                          const Text('Aucune ville. Ajoute-en une, puis affecte-lui un partenaire.', style: TextStyle(color: Color(0xFF56608A))),
                        for (final z in zones) _zoneTile(z),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// MON ESPACE PARTENAIRE
// ----------------------------------------------------------------------

class PartnerZoneScreen extends StatefulWidget {
  const PartnerZoneScreen({super.key});

  @override
  State<PartnerZoneScreen> createState() => _PartnerZoneScreenState();
}

class _PartnerZoneScreenState extends State<PartnerZoneScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  String _period = 'month'; // today | yesterday | week | month | lastmonth

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Wallet.zoneMy();
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    }
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'today':
        return (today, today.add(const Duration(days: 1)));
      case 'yesterday':
        return (today.subtract(const Duration(days: 1)), today);
      case 'week':
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      case 'lastmonth':
        final first = DateTime(now.year, now.month - 1, 1);
        return (first, DateTime(now.year, now.month, 1));
      default:
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
    }
  }

  bool _in(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return false;
    final r = _range();
    return !t.isBefore(r.$1) && t.isBefore(r.$2);
  }

  Future<void> _payout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await Wallet.zonePayoutRequest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Demande de paiement de ${_fcfa((r['amount'] as num?)?.toInt() ?? 0)} envoyée à l\'administration.')));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Wallet.errorText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _stat(String k, String v, {Color color = const Color(0xFF12183A)}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFE3EAFF), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(k, style: const TextStyle(color: Color(0xFF56608A), fontSize: 11)),
          const SizedBox(height: 2),
          Text(v, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final zones = [for (final z in (d?['zones'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    final players = [for (final z in (d?['players'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    final comm = [for (final z in (d?['commissions'] as List? ?? const [])) Map<String, dynamic>.from(z as Map)];
    final inPeriod = comm.where((c) => _in('${c['createdAt']}')).toList();
    final periodAmount = inPeriod.fold<int>(0, (a, c) => a + ((c['amount'] as num?)?.toInt() ?? 0));
    final periodBase = inPeriod.fold<int>(0, (a, c) => a + ((c['base'] as num?)?.toInt() ?? 0));
    final newPlayers = players.where((p) => _in('${p['createdAt']}')).length;
    final activeIds = {for (final c in comm.where((c) => _in('${c['createdAt']}'))) '${c['playerUid']}'};
    final perPlayer = <String, int>{};
    for (final c in comm) {
      perPlayer['${c['playerUid']}'] = (perPlayer['${c['playerUid']}'] ?? 0) + ((c['amount'] as num?)?.toInt() ?? 0);
    }
    final avail = (d?['available'] as num?)?.toInt() ?? 0;
    final min = (d?['min'] as num?)?.toInt() ?? 5000;
    final minPlayers = (d?['minPlayers'] as num?)?.toInt() ?? 50;
    Widget chip(String id, String label) => ChoiceChip(label: Text(label), selected: _period == id, onSelected: (_) => setState(() => _period = id));
    return Scaffold(
      body: Container(
        decoration: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Color(0xFF12183A))),
              const Expanded(
                child: Text('🤝 Mon espace partenaire',
                    style: TextStyle(color: Color(0xFF12183A), fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh, color: Color(0xFF12183A))),
            ]),
            Expanded(
              child: d == null
                  ? Center(
                      child: _err != null
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: SelectableText(_err!, style: const TextStyle(color: Color(0xFFD32F2F))))
                          : const CircularProgressIndicator(color: _gold))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
                        if (zones.isEmpty)
                          const Text('Aucune zone ne t\'est affectée pour le moment.', style: TextStyle(color: Color(0xFF56608A)))
                        else
                          Text(
                            'Zone(s) : ${zones.map((z) => '${z['name']} (${z['rate']} %${z['status'] == 'suspended' ? ', suspendue' : ''})').join(' · ')}',
                            style: const TextStyle(color: _gold, fontWeight: FontWeight.w800),
                          ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, children: [
                          chip('today', 'Aujourd\'hui'),
                          chip('yesterday', 'Hier'),
                          chip('week', 'Cette semaine'),
                          chip('month', 'Ce mois'),
                          chip('lastmonth', 'Mois précédent'),
                        ]),
                        const SizedBox(height: 10),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.4,
                          children: [
                            _stat('Joueurs rattachés', '${players.length}'),
                            _stat('Nouveaux joueurs (période)', '$newPlayers'),
                            _stat('Joueurs actifs (période)', '${activeIds.length}'),
                            _stat('Joueurs inactifs', '${players.length - activeIds.length}'),
                            _stat('Activité éligible (période)', _fcfa(periodBase)),
                            _stat('Commission (période)', _fcfa(periodAmount), color: _gold),
                            _stat('Commission disponible', _fcfa(avail), color: const Color(0xFF17883F)),
                            _stat('Déjà payée', _fcfa((d['paid'] as num?)?.toInt() ?? 0)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (((d['held'] as num?)?.toInt() ?? 0) > 0)
                          Text('En attente de validation : ${_fcfa((d['held'] as num).toInt())}',
                              style: const TextStyle(color: Color(0xFF56608A), fontSize: 12)),
                        const SizedBox(height: 6),
                        FilledButton.icon(
                          onPressed: _busy || avail < min || players.length < minPlayers ? null : _payout,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(players.length < minPlayers
                              ? 'Paiement dès $minPlayers joueurs rattachés (${players.length}/$minPlayers)'
                              : avail < min
                                  ? 'Paiement possible à partir de ${_fcfa(min)}'
                                  : 'Demander le paiement de ${_fcfa(avail)}'),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 14, bottom: 6),
                          child: Text('Mes joueurs', style: TextStyle(color: Color(0xFF12183A), fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        if (players.isEmpty) const Text('Aucun joueur rattaché.', style: TextStyle(color: Color(0xFF56608A))),
                        for (final p in players)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFFE3EAFF), borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${p['name']}', style: const TextStyle(color: Color(0xFF12183A), fontWeight: FontWeight.w800)),
                                  Text('${p['city']}${'${p['quarter']}'.isEmpty ? '' : ' · ${p['quarter']}'} · misé ${_fcfa((p['wagered'] as num?)?.toInt() ?? 0)}',
                                      style: const TextStyle(color: Color(0xFF68729A), fontSize: 11)),
                                ]),
                              ),
                              Text(_fcfa(perPlayer['${p['id']}'] ?? 0), style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 14, bottom: 6),
                          child: Text('Dernières commissions', style: TextStyle(color: Color(0xFF12183A), fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        if (inPeriod.isEmpty) const Text('Aucune commission sur cette période.', style: TextStyle(color: Color(0xFF56608A))),
                        for (final c in inPeriod.take(60))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${'${c['createdAt']}'.length >= 16 ? '${c['createdAt']}'.substring(0, 16).replaceFirst('T', ' ') : ''} · ${c['playerName']} · ${c['game']} · ${c['rate']} % de ${_fcfa((c['base'] as num?)?.toInt() ?? 0)} = ${_fcfa((c['amount'] as num?)?.toInt() ?? 0)}',
                              style: const TextStyle(color: Color(0xFF56608A), fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tu ne vois que les joueurs de ta ville. Tu ne peux ni modifier les soldes, ni les résultats des jeux, ni les taux.',
                          style: TextStyle(color: Color(0xFF8A93B8), fontSize: 11),
                        ),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
