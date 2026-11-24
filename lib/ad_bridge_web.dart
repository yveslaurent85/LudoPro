import 'dart:js_interop';

@JS('katikaAd')
external void _katikaAd(String mode);

/// Montre ou cache le bandeau 1xBet (défini dans web/index.html).
void setAdVisible(bool visible) {
  try {
    _katikaAd(visible ? '1' : '0');
  } catch (_) {}
}
