import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'accounts.dart';
import 'lang.dart';

/// Administrateur : carte du Cameroun avec les joueurs inscrits dans chaque ville,
/// connectés (vus depuis moins de 5 minutes) ou non.

const Color _ink = Color(0xFF12183A);
const Color _muted = Color(0xFF56608A);
const Color _on = Color(0xFF17A34A);
const Color _off = Color(0xFF8A93B8);

/// Villes du Cameroun : clé (lettres minuscules sans accent) -> [latitude, longitude].
const Map<String, List<double>> _cityXY = {
  'douala': [4.05, 9.70], 'yaounde': [3.87, 11.52], 'bafoussam': [5.47, 10.42],
  'bamenda': [5.96, 10.15], 'garoua': [9.30, 13.40], 'maroua': [10.59, 14.32],
  'ngaoundere': [7.32, 13.58], 'bertoua': [4.58, 13.68], 'ebolowa': [2.90, 11.15],
  'buea': [4.15, 9.24], 'limbe': [4.02, 9.20], 'kribi': [2.94, 9.91],
  'nkongsamba': [4.95, 9.94], 'edea': [3.80, 10.13], 'dschang': [5.45, 10.07],
  'mbouda': [5.63, 10.25], 'foumban': [5.72, 10.90], 'bafang': [5.16, 10.18],
  'bangangte': [5.15, 10.52], 'kumba': [4.64, 9.45], 'mbalmayo': [3.52, 11.50],
  'sangmelima': [2.93, 11.98], 'kumbo': [6.20, 10.68], 'wum': [6.38, 10.07],
  'mokolo': [10.74, 13.80], 'kousseri': [12.08, 15.03], 'yagoua': [10.34, 15.24],
  'guider': [9.93, 13.94], 'meiganga': [6.52, 14.34], 'batouri': [4.43, 14.36],
  'yokadouma': [3.52, 15.05], 'abongmbang': [3.98, 13.17], 'ambam': [2.39, 11.28],
  'mamfe': [5.77, 9.29], 'eseka': [3.65, 10.77], 'bafia': [4.75, 11.23],
  'obala': [4.17, 11.53], 'mbanga': [4.50, 9.57], 'loum': [4.72, 9.73],
  'penja': [4.63, 9.68], 'tiko': [4.08, 9.36], 'bangem': [5.15, 9.67],
  'fontem': [5.47, 9.88], 'tibati': [6.47, 12.63], 'banyo': [6.75, 11.82],
  'kaele': [10.11, 14.45], 'mora': [11.05, 14.14], 'poli': [8.48, 13.24],
  'lomie': [3.16, 13.62], 'akonolinga': [3.77, 12.25], 'mbandjock': [4.45, 11.90],
  'nangaeboko': [4.68, 12.37], 'makenene': [4.88, 10.80], 'ndop': [6.00, 10.43],
  'foumbot': [5.50, 10.63], 'bangou': [5.35, 10.33], 'bandjoun': [5.37, 10.41],
  'mbouo': [5.40, 10.40], 'baham': [5.31, 10.40], 'kekem': [5.17, 10.03],
  'mutengene': [4.09, 9.31], 'muyuka': [4.29, 9.41], 'idenau': [4.00, 8.99],
  'ngoumou': [3.58, 11.27], 'mfou': [3.72, 11.64], 'monatele': [4.27, 11.17],
  'sa a': [4.37, 11.45], 'saa': [4.37, 11.45], 'yabassi': [4.46, 9.97], 'pouma': [3.94, 10.54],
  'bogo': [10.73, 14.61], 'tcholliré': [8.40, 14.17], 'tchollire': [8.40, 14.17],
  'garouaboulai': [5.89, 14.55], 'bangangtecentre': [5.15, 10.52], 'mbengwi': [6.02, 10.00],
  'nkambe': [6.64, 10.67], 'ndu': [6.50, 10.80], 'bali': [5.89, 10.02],
};

/// Contour approximatif du Cameroun (longitude, latitude) — carte indicative.
const List<List<double>> _outline = [
  [9.80, 2.35], [11.30, 2.20], [13.20, 2.25], [14.60, 2.20], [16.20, 2.25],
  [15.60, 3.40], [16.05, 3.80], [15.30, 4.80], [14.60, 5.90], [14.40, 6.70],
  [15.10, 7.40], [15.60, 7.70], [15.00, 8.50], [14.50, 9.10], [14.90, 9.90],
  [15.50, 10.00], [15.20, 11.00], [15.10, 12.00], [14.60, 13.05], [14.00, 12.60],
  [13.60, 11.90], [13.70, 11.20], [13.10, 10.50], [12.90, 9.70], [12.30, 8.60],
  [11.80, 7.40], [11.20, 6.90], [10.40, 6.90], [9.70, 6.30], [9.30, 5.50],
  [8.90, 4.95], [8.50, 4.65], [8.90, 4.30], [9.20, 4.00], [9.60, 3.95],
  [9.90, 2.90],
];

String _key(String v) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final r in v.toLowerCase().runes) {
    var c = String.fromCharCode(r);
    final i = from.indexOf(c);
    if (i >= 0) c = to[i];
    if (RegExp(r'[a-z]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

List<double>? _locate(String key) {
  final k = _key(key);
  if (_cityXY.containsKey(k)) return _cityXY[k];
  for (final e in _cityXY.entries) {
    if (e.key.length >= 5 && k.startsWith(e.key)) return e.value;
  }
  return null;
}

class _Pt {
  _Pt(this.city, this.lat, this.lon);
  final Map<String, dynamic> city;
  final double lat;
  final double lon;
  int get total => (city['total'] as num?)?.toInt() ?? 0;
  int get online => (city['online'] as num?)?.toInt() ?? 0;
}

const double _lonMin = 8.2, _lonMax = 16.4, _latMin = 1.6, _latMax = 13.4;

Offset _proj(double lat, double lon, Size s) =>
    Offset((lon - _lonMin) / (_lonMax - _lonMin) * s.width, (_latMax - lat) / (_latMax - _latMin) * s.height);

double _radius(int total) => (6 + 3.2 * (total <= 1 ? 1 : total).toDouble().clamp(1, 400).toDouble().sqrtSafe()).clamp(7, 26).toDouble();

extension _Sq on double {
  double sqrtSafe() {
    var x = this;
    if (x <= 0) return 0;
    var g = x / 2 + 0.5;
    for (var i = 0; i < 12; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.pts, this.selected);
  final List<_Pt> pts;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _outline.length; i++) {
      final o = _proj(_outline[i][1], _outline[i][0], size);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE3EAFF));
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF8FA0D8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // Les plus petites villes en dernier (au-dessus).
    final sorted = [...pts]..sort((a, b) => b.total.compareTo(a.total));
    for (final p in sorted) {
      final o = _proj(p.lat, p.lon, size);
      final r = _radius(p.total);
      canvas.drawCircle(o, r, Paint()..color = _off.withOpacity(0.85));
      if (p.online > 0) {
        final ri = (r * (p.online / p.total)).clamp(4, r).toDouble();
        canvas.drawCircle(o, ri, Paint()..color = _on);
      }
      canvas.drawCircle(
          o,
          r,
          Paint()
            ..color = '${p.city['key']}' == selected ? _ink : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = '${p.city['key']}' == selected ? 3 : 1.5);
    }
    // Étiquettes : les villes les plus peuplées + la ville choisie.
    var shown = 0;
    for (final p in sorted) {
      if (shown >= 14 && '${p.city['key']}' != selected) continue;
      shown++;
      final o = _proj(p.lat, p.lon, size);
      final tp = TextPainter(
        text: TextSpan(
            text: '${p.city['name']} ${p.total}${p.online > 0 ? ' · ${p.online}●' : ''}',
            style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (o.dx + _radius(p.total) + 3 + tp.width > size.width) ? o.dx - _radius(p.total) - 3 - tp.width : o.dx + _radius(p.total) + 3;
      tp.paint(canvas, Offset(dx, o.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.pts != pts || old.selected != selected;
}

class AdminPlayersMapScreen extends StatefulWidget {
  const AdminPlayersMapScreen({super.key});

  @override
  State<AdminPlayersMapScreen> createState() => _AdminPlayersMapScreenState();
}

class _AdminPlayersMapScreenState extends State<AdminPlayersMapScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _loading = false;
  String? _sel;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final d = await Wallet.adminPlayersMap();
      if (mounted) setState(() {
        _d = d;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = Wallet.errorText(e));
    } finally {
      _loading = false;
    }
  }

  List<Map<String, dynamic>> get _cities =>
      [for (final c in (_d?['cities'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];

  void _tap(Offset p, Size size, List<_Pt> pts) {
    _Pt? best;
    var bd = 1e9;
    for (final pt in pts) {
      final o = _proj(pt.lat, pt.lon, size);
      final d = (o - p).distance;
      if (d < bd && d <= _radius(pt.total) + 10) {
        bd = d;
        best = pt;
      }
    }
    if (best != null) {
      setState(() => _sel = '${best!.city['key']}');
      _showCity(best.city);
    }
  }

  String _ago(int seen, int now) {
    if (seen <= 0) return tr('jamais vu', 'never seen');
    final m = ((now - seen) / 60000).floor();
    if (m < 1) return tr('à l\'instant', 'just now');
    if (m < 60) return tr('il y a $m min', '$m min ago');
    final h = (m / 60).floor();
    if (h < 48) return tr('il y a $h h', '$h h ago');
    return tr('il y a ${(h / 24).floor()} j', '${(h / 24).floor()} d ago');
  }

  void _showCity(Map<String, dynamic> c) {
    final now = (_d?['now'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final players = [for (final p in (c['players'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Row(children: [
              Expanded(
                child: Text('${c['name']}${'${c['region']}'.isEmpty ? '' : ' · ${c['region']}'}',
                    style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              Text('${c['total']} · ${c['online']} ${tr('connecté(s)', 'online')}',
                  style: const TextStyle(color: _on, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
              for (final p in players)
                () {
                  final seen = (p['seen'] as num?)?.toInt() ?? 0;
                  final on = seen > 0 && now - seen < 5 * 60 * 1000;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(width: 11, height: 11, decoration: BoxDecoration(color: on ? _on : _off, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${p['name']}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700))),
                      Text(on ? tr('connecté', 'online') : _ago(seen, now),
                          style: TextStyle(color: on ? _on : _muted, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  );
                }(),
              if ((c['total'] as num? ?? 0) > players.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tr('… et ${(c['total'] as num) - players.length} autres', '… and ${(c['total'] as num) - players.length} more'),
                      style: const TextStyle(color: _muted)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(color: const Color(0xFFE3EAFF), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cities = _cities;
    final pts = <_Pt>[];
    final unplaced = <Map<String, dynamic>>[];
    for (final c in cities) {
      final xy = _locate('${c['name']}');
      if (xy == null) {
        unplaced.add(c);
      } else {
        pts.add(_Pt(c, xy[0], xy[1]));
      }
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(tr('Carte des joueurs', 'Players map'), style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _d == null
          ? Center(
              child: _err != null
                  ? Padding(padding: const EdgeInsets.all(20), child: SelectableText(_err!, style: const TextStyle(color: Color(0xFFD32F2F))))
                  : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 30), children: [
              Row(children: [
                _stat(tr('Inscrits (avec ville)', 'Registered (with city)'), '${_d!['total']}', _ink),
                _stat(tr('Connectés maintenant', 'Online now'), '${_d!['online']}', _on),
                _stat(tr('Vus sur 24 h', 'Seen in 24 h'), '${_d!['day']}', _muted),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Container(width: 12, height: 12, decoration: const BoxDecoration(color: _on, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(tr('connectés', 'online'), style: const TextStyle(color: _ink, fontSize: 12)),
                const SizedBox(width: 14),
                Container(width: 12, height: 12, decoration: const BoxDecoration(color: _off, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(tr('non connectés', 'offline'), style: const TextStyle(color: _ink, fontSize: 12)),
                const Spacer(),
                Text(tr('Touche une ville', 'Tap a city'), style: const TextStyle(color: _muted, fontSize: 11)),
              ]),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: (_lonMax - _lonMin) / (_latMax - _latMin),
                child: LayoutBuilder(builder: (ctx, bc) {
                  final size = Size(bc.maxWidth, bc.maxHeight);
                  return GestureDetector(
                    onTapUp: (d) => _tap(d.localPosition, size, pts),
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFFF4F6FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD6DCF5))),
                      child: CustomPaint(size: size, painter: _MapPainter(pts, _sel)),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(tr('Carte indicative. Le cercle gris = inscrits, le vert = connectés (vus depuis moins de 5 min).',
                  'Indicative map. Grey circle = registered, green = online (seen within 5 min).'),
                  style: const TextStyle(color: _muted, fontSize: 11)),
              if (_d!['truncated'] == true)
                Text(tr('Liste limitée aux 4000 premiers joueurs.', 'List limited to the first 4000 players.'),
                    style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 11)),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(tr('Par ville', 'By city'), style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              for (final c in cities)
                InkWell(
                  onTap: () {
                    setState(() => _sel = '${c['key']}');
                    _showCity(c);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFE3EAFF), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(
                        child: Text('${c['name']}${'${c['region']}'.isEmpty ? '' : ' · ${c['region']}'}'
                            '${_locate('${c['name']}') == null ? ' · ${tr('hors carte', 'not on map')}' : ''}',
                            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                      ),
                      Text('${c['online']}', style: const TextStyle(color: _on, fontWeight: FontWeight.w900)),
                      Text(' / ${c['total']}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
