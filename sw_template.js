// Service worker Katika : garde en mémoire l'application (code, moteur, polices)
// pour que les ouvertures suivantes soient quasi instantanées.
//  - APP    : fichiers de CETTE version de l'application (renouvelés à chaque mise à jour)
//  - ENGINE : moteur CanvasKit + polices (changent seulement avec Flutter)
const BUILD = '__BUILD__';
const ENGINE = '__ENGINE__';
const APP = 'katika-app-' + BUILD;
const ENG = 'katika-engine-' + ENGINE;

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keep = new Set([APP, ENG]);
    for (const k of await caches.keys()) {
      if (k.startsWith('katika-') && !keep.has(k)) await caches.delete(k);
    }
    await self.clients.claim();
  })());
});

function cacheFor(url) {
  const u = new URL(url);
  if (u.hostname === 'fonts.gstatic.com' || u.hostname === 'www.gstatic.com') return ENG;
  if (u.origin !== self.location.origin) return null;
  const p = u.pathname;
  if (p.includes('/canvaskit/') || p.endsWith('/flutter.js')) return ENG;
  // Fichiers de l'application (jamais l'API, ni les autres pages du site)
  const scope = new URL(self.registration.scope).pathname;
  if (!p.startsWith(scope)) return null;
  if (p.endsWith('/version.json')) return null; // toujours frais
  if (p.endsWith('/flutter_service_worker.js')) return null;
  return APP;
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const name = cacheFor(req.url);
  if (!name) return;
  event.respondWith((async () => {
    const cache = await caches.open(name);
    // La page d'accueil est indexée sans paramètres
    const key = req.mode === 'navigate' ? new Request(new URL('./', self.registration.scope).href) : req;
    const hit = await cache.match(key, { ignoreSearch: req.mode === 'navigate' });
    if (hit) {
      if (req.mode === 'navigate') {
        // Mise à jour discrète en arrière-plan : la prochaine ouverture sera à jour
        event.waitUntil(fetch(key, { cache: 'reload' }).then((r) => { if (r.ok) return cache.put(key, r); }).catch(() => {}));
      }
      return hit;
    }
    try {
      const res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque') && res.status !== 206) {
        cache.put(key, res.clone()).catch(() => {});
      }
      return res;
    } catch (e) {
      const any = await cache.match(key, { ignoreSearch: true });
      if (any) return any;
      throw e;
    }
  })());
});
