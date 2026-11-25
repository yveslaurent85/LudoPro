// worker.js — serveur Katika sur Cloudflare Workers (gratuit).
// Remplace les Cloud Functions Firebase (stakes.js) : mêmes fonctions,
// mêmes règles, mais les données restent dans Firestore (API REST).
//
// Réglages :
//   - variable  FIREBASE_PROJECT_ID  (wrangler.toml)
//   - secret    SERVICE_ACCOUNT      (JSON du compte de service Firebase)
//   - variable  ADMIN_UIDS           (identifiant(s) du/des administrateur(s),
//                                     séparés par des virgules : tableau de bord).
//                                     L'ORDRE COMPTE : les commissions sont
//                                     partagées 50 % pour le 1er identifiant et
//                                     50 % pour le 2e.
//   - variable  CAMPAY_BASE_URL      (https://demo.campay.net en test,
//                                     https://www.campay.net en réel)
//   - secrets   CAMPAY_USERNAME, CAMPAY_PASSWORD, CAMPAY_WEBHOOK_KEY
//
// Appel : POST https://<ton-worker>/<fonction>
//   en-tête  Authorization: Bearer <ID token Firebase du joueur>
//   corps    JSON (les mêmes données que les anciennes fonctions « callable »)
//   réponse  { "data": ... }  ou  { "error": "message lisible" }
//
// Exception : /campay/webhook est appelé par Campay (sans connexion joueur).

const WELCOME = 0; // plus de jetons offerts : seul l'argent réel compte
const MIN_STAKE = 100; // mise minimale
const MAX_STAKE = 250000; // mise maximale
const MIN_CAPTURE = 100; // capture payante : montant minimum par pion
const MAX_CAPTURE = 5000; // et maximum
const COMMISSION_PERCENT = 5; // en ligne : part gardée par Katika sur la cagnotte (0-100)
const COMMISSION_LOCAL_PERCENT = 5; // présentiel (Ludo, Deux dés et Songô)
const TRANSFER_MIN = 25; // transfert de compte à compte
const TRANSFER_MAX = 250000;
const JACKPOT_ENABLED = false; // jackpot désactivé : toute la commission reste à Katika
const JACKPOT_PERCENT = 0; // part de la commission versée au jackpot (inutilisée)
const PARTNER_PERCENT = 40; // part du partenaire sur (commission - part du parrain)
const PARTNER_MIN_REFERRALS = 25; // retrait partenaire : nombre de filleuls actifs requis
const PARTNER_MIN_WAGERED = 1000; // ... chacun ayant misé au moins ce total (FCFA) : mises des parties + paris (Duel, Défi 7)
const PARTNER_WITHDRAW_MIN = 500; // gains de partenaire minimum pour les transférer vers le solde
const REVIVE_AFTER_MIN = 180; // parties bloquées depuis plus de 3 h
const REFERRAL_PERCENT = 12.5; // palier de départ (1 à 10 filleuls) ; voir REFERRAL_TIERS
// Commission des affiliés par paliers, selon le nombre de joueurs inscrits avec leur code : [jusqu'à N filleuls, %].
const REFERRAL_TIERS = [[10, 12.5], [20, 15], [30, 20], [40, 25], [65, 30], [100, 35], [150, 37.5]];
const REFERRAL_TOP_PERCENT = 40; // au-delà de 150 filleuls
function referralPercentFor(n) {
  const c = Math.max(0, Math.floor(Number(n) || 0));
  for (const [max, p] of REFERRAL_TIERS) if (c <= max) return p;
  return REFERRAL_TOP_PERCENT;
}

/** Nombre de filleuls d'un joueur (requête de comptage, hors transaction). */
async function referralCountOf(env, uid) {
  try {
    const r = await fsCall(env, 'runAggregationQuery', {
      structuredAggregationQuery: {
        structuredQuery: { from: [{ collectionId: 'users' }], where: eqFilter('referrerUid', uid) },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    return Number(r[0].result.aggregateFields.n.integerValue) || 0;
  } catch (_) {
    return -1;
  }
}
const JACKPOT_MIN = 550; // le jackpot se déclenche entre ces deux montants
const JACKPOT_MAX = 650;
const HOUSE_WITHDRAW_MIN = 2500; // commissions de Katika : seuil pour pouvoir les retirer (FCFA)
const REFERRAL_WITHDRAW_MIN = 500; // gains de parrainage minimum pour pouvoir les retirer vers le solde

// Parties en ligne gérées : le Ludo (« games »), Deux dés (« deuxdes »), Songô et Damier.
const ONLINE_COLLECTIONS = ['games', 'deuxdes', 'songo', 'damier', 'pileface', 'cards'];
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

/** Lance une tâche de fond (notification, ménage…) APRÈS avoir répondu au joueur. */
function later(env, promise) {
  const p = Promise.resolve(promise).catch(() => {});
  try {
    if (env && env.__ctx && env.__ctx.waitUntil) env.__ctx.waitUntil(p);
  } catch (_) {}
}

class HttpError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const STATUS = {
  unauthenticated: 401,
  'permission-denied': 403,
  'not-found': 404,
  'invalid-argument': 400,
  'failed-precondition': 412,
  internal: 500,
};

// ======================================================================
// Outils : encodage, jetons Google, vérification des comptes
// ======================================================================

const te = new TextEncoder();
const td = new TextDecoder();

function b64urlEncode(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(str) {
  let s = str.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

// Compte de service : le secret peut s'appeler SERVICE_ACCOUNT (ou
// FIREBASE_SERVICE_ACCOUNT / GOOGLE_SERVICE_ACCOUNT). L'identifiant du projet
// est lu dans ce JSON si la variable FIREBASE_PROJECT_ID n'existe pas.
let saCache = null;

function serviceAccount(env) {
  if (saCache) return saCache;
  const raw =
    env.SERVICE_ACCOUNT || env.FIREBASE_SERVICE_ACCOUNT || env.GOOGLE_SERVICE_ACCOUNT;
  if (!raw) throw new HttpError('internal', 'Compte de service manquant.');
  let sa;
  try {
    sa = JSON.parse(raw);
  } catch (_) {
    sa = JSON.parse(atob(raw));
  }
  saCache = sa;
  return sa;
}

function projectId(env) {
  return env.FIREBASE_PROJECT_ID || serviceAccount(env).project_id;
}

// Jeton d'accès du compte de service (mis en cache ~1 h).
const tokenCaches = {};

async function accessToken(env, scope = 'https://www.googleapis.com/auth/datastore') {
  const now = Math.floor(Date.now() / 1000);
  const cached = tokenCaches[scope];
  if (cached && cached.value && cached.exp - 60 > now) return cached.value;

  const sa = serviceAccount(env);
  const header = b64urlEncode(te.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claim = b64urlEncode(
    te.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope,
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, te.encode(`${header}.${claim}`)),
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claim}.${b64urlEncode(sig)}`,
    }),
  });
  const j = await res.json();
  if (!res.ok) throw new HttpError('internal', 'Accès serveur impossible.');
  tokenCaches[scope] = { value: j.access_token, exp: now + (j.expires_in || 3600) };
  return j.access_token;
}

// Clés publiques de Firebase Auth (mises en cache 1 h).
let jwksCache = { keys: null, exp: 0 };

const jwkKeyCache = new Map();

async function googleKeys() {
  if (jwksCache.keys && jwksCache.exp > Date.now()) return jwksCache.keys;
  const res = await fetch(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  );
  const j = await res.json();
  jwksCache = { keys: j.keys || [], exp: Date.now() + 3600 * 1000 };
  return jwksCache.keys;
}

/** Vérifie un ID token Firebase et renvoie l'uid du joueur. */
async function verifyIdToken(token, env) {
  const bad = () => new HttpError('unauthenticated', 'Connexion expirée : reconnecte-toi.');
  const parts = String(token).split('.');
  if (parts.length !== 3) throw bad();

  let header;
  let payload;
  try {
    header = JSON.parse(td.decode(b64urlDecode(parts[0])));
    payload = JSON.parse(td.decode(b64urlDecode(parts[1])));
  } catch (_) {
    throw bad();
  }
  if (header.alg !== 'RS256') throw bad();

  let jwk = (await googleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) {
    jwksCache.exp = 0; // clés renouvelées : on recharge une fois
    jwk = (await googleKeys()).find((k) => k.kid === header.kid);
  }
  if (!jwk) throw bad();

  let key = jwkKeyCache.get(header.kid);
  if (!key) {
    key = await crypto.subtle.importKey(
      'jwk',
      jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    if (jwkKeyCache.size > 20) jwkKeyCache.clear();
    jwkKeyCache.set(header.kid, key);
  }
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlDecode(parts[2]),
    te.encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw bad();

  const now = Math.floor(Date.now() / 1000);
  const pid = projectId(env);
  if (
    payload.aud !== pid ||
    payload.iss !== `https://securetoken.google.com/${pid}` ||
    !payload.sub ||
    payload.exp <= now ||
    payload.iat > now + 300
  ) {
    throw bad();
  }
  return payload.sub;
}

// ======================================================================
// Firestore (API REST) avec transactions
// ======================================================================

function docName(env, path) {
  return `projects/${projectId(env)}/databases/(default)/documents/${path}`;
}

async function fsCall(env, method, body) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId(env)}/databases/(default)/documents:${method}`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${await accessToken(env)}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  const txt = await res.text().catch(() => '');
  let j = {};
  try {
    j = JSON.parse(txt);
  } catch (_) {}
  if (!res.ok) {
    const je = Array.isArray(j) ? (j[0] && j[0].error) || {} : j.error || {};
    const err = new Error(je.message || `Firestore HTTP ${res.status} ${String(txt).slice(0, 120)}`);
    err.fsStatus = je.status;
    throw err;
  }
  return j;
}

function toFs(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFs) } };
  return {
    mapValue: {
      fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toFs(x)])),
    },
  };
}

function fromFs(v) {
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromFs);
  if ('mapValue' in v) return fieldsToObj(v.mapValue.fields || {});
  return null;
}

function fieldsToObj(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, x]) => [k, fromFs(x)]));
}

/**
 * Exécute fn(tx) dans une transaction Firestore (avec nouvelles tentatives).
 *   tx.get(path)            -> objet ou null
 *   tx.write(path, {set, incr, union, remove, serverTime, create})
 *   tx.delete(path)
 * Les écritures sont envoyées d'un coup à la fin.
 */
async function runTx(env, fn) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { transaction } = await fsCall(env, 'beginTransaction', {
      options: { readWrite: {} },
    });
    const ops = new Map();
    const deletes = [];

    const tx = {
      env,
      async get(path) {
        const r = await fsCall(env, 'batchGet', {
          documents: [docName(env, path)],
          transaction,
        });
        const first = Array.isArray(r) ? r[0] : r;
        return first && first.found ? fieldsToObj(first.found.fields || {}) : null;
      },
      /** Lit plusieurs documents en un seul aller-retour (même ordre que `paths`). */
      async getMany(paths) {
        const r = await fsCall(env, 'batchGet', {
          documents: paths.map((p) => docName(env, p)),
          transaction,
        });
        const byName = new Map();
        for (const x of Array.isArray(r) ? r : [r]) {
          if (x && x.found) byName.set(x.found.name, fieldsToObj(x.found.fields || {}));
        }
        return paths.map((p) => byName.get(docName(env, p)) || null);
      },
      write(path, o = {}) {
        const e = ops.get(path) || {
          set: {},
          incr: {},
          union: {},
          remove: {},
          serverTime: [],
          create: false,
        };
        Object.assign(e.set, o.set || {});
        for (const [k, v] of Object.entries(o.incr || {})) e.incr[k] = (e.incr[k] || 0) + v;
        for (const [k, v] of Object.entries(o.union || {})) e.union[k] = (e.union[k] || []).concat(v);
        for (const [k, v] of Object.entries(o.remove || {})) e.remove[k] = (e.remove[k] || []).concat(v);
        e.serverTime.push(...(o.serverTime || []));
        e.create = e.create || !!o.create;
        ops.set(path, e);
      },
      delete(path) {
        deletes.push(path);
      },
    };

    try {
      const result = await fn(tx);

      const writes = [];
      for (const [path, e] of ops) {
        const w = {
          update: {
            name: docName(env, path),
            fields: Object.fromEntries(Object.entries(e.set).map(([k, v]) => [k, toFs(v)])),
          },
          updateMask: { fieldPaths: Object.keys(e.set) },
        };
        const t = [];
        for (const [k, n] of Object.entries(e.incr)) {
          t.push({ fieldPath: k, increment: { integerValue: String(n) } });
        }
        for (const [k, v] of Object.entries(e.union)) {
          t.push({ fieldPath: k, appendMissingElements: { values: v.map(toFs) } });
        }
        for (const [k, v] of Object.entries(e.remove)) {
          t.push({ fieldPath: k, removeAllFromArray: { values: v.map(toFs) } });
        }
        for (const k of e.serverTime) {
          t.push({ fieldPath: k, setToServerValue: 'REQUEST_TIME' });
        }
        if (t.length) w.updateTransforms = t;
        if (e.create) w.currentDocument = { exists: false };
        writes.push(w);
      }
      for (const p of deletes) writes.push({ delete: docName(env, p) });

      await fsCall(env, 'commit', { writes, transaction });
      return result;
    } catch (err) {
      if (err && err.fsStatus === 'ABORTED' && attempt < 4) continue;
      if (!(err && err.fsStatus === 'ABORTED')) {
        await fsCall(env, 'rollback', { transaction }).catch(() => {});
      }
      throw err;
    }
  }
  throw new HttpError('internal', 'Serveur occupé, réessaie.');
}

// ======================================================================
// Petits outils métier
// ======================================================================

function balanceOf(d) {
  return d && typeof d.balance === 'number' ? d.balance : 0;
}

function intOr(v, def) {
  return typeof v === 'number' && Number.isFinite(v) ? Math.floor(v) : def;
}

function idOf(data) {
  const v = data && (data.gameId || data.id || data.localId);
  return typeof v === 'string' && ID_RE.test(v) ? v : '';
}

function newId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (b) => chars[b % chars.length]).join('');
}

/** Identifiant de partie : uniquement des chiffres (10 chiffres, jamais de 0 au début). */
function newGameId() {
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes, (b, i) => (i === 0 ? 1 + (b % 9) : b % 10)).join('');
}

/** Gain du gagnant : la cagnotte moins la commission (5 % en ligne et en présentiel). */
function prizeOf(pot, percent = COMMISSION_PERCENT) {
  // percent peut avoir une décimale (ex. 7,5 %) : on calcule en dixièmes.
  return Math.floor((pot * (1000 - Math.round(percent * 10))) / 1000);
}

function newTarget() {
  return JACKPOT_MIN + Math.floor(Math.random() * (JACKPOT_MAX - JACKPOT_MIN + 1));
}

function playersOf(d) {
  return Array.isArray(d.players) ? d.players : [];
}

/** Retrouve une partie en ligne (Ludo ou Deux dés) à partir de son id. */
async function locate(tx, gameId) {
  if (!gameId) return null;
  const paths = ONLINE_COLLECTIONS.map((col) => `${col}/${gameId}`);
  const docs = await tx.getMany(paths);
  for (let i = 0; i < docs.length; i++) {
    if (docs[i]) return { path: paths[i], data: docs[i], col: ONLINE_COLLECTIONS[i] };
  }
  return null;
}

/** Mise d'un joueur dans une partie. Damier : le créateur fixe sa mise (stake)
 *  et celle de l'adversaire (stakeOpp). Sans stakeOpp : mise unique. */
function stakeFor(d, uid) {
  if (d && d.game === 'anticote' && d.esc && Number.isFinite(d.esc[uid])) return d.esc[uid]; // Anti-Cote : montant réellement bloqué
  const base = Math.max(0, intOr(d && d.stake, 0)) * (d && isEsc2(d.game) ? 2 : 1); // Fap-Fap / Anti-Cote : 2 x M bloqués
  if (!d || d.stakeOpp === undefined || d.stakeOpp === null) return base;
  if (d.hostUid === uid) return base;
  return Math.max(0, intOr(d.stakeOpp, 0));
}

/** Nombre de places qu'un joueur occupe dans une partie en ligne (Ludo par
 *  équipes : un joueur peut payer et jouer 2 places). */
function seatsOf(d, uid) {
  const n = playersOf(d).filter((p) => p.uid === uid).length;
  return Math.max(1, n);
}

/** Mise totale d'un joueur = mise par place x nombre de places. */
function stakeTotal(d, uid) {
  return stakeFor(d, uid) * seatsOf(d, uid);
}

/** Joueurs réellement débités : en salle d'attente « différée », personne n'a
 *  encore été débité (la mise n'est prélevée qu'au lancement par le créateur). */
function chargedPaid(d) {
  const paid = Array.isArray(d && d.paid) ? d.paid : [];
  return d && d.deferred === true && d.charged !== true ? [] : paid;
}

function refund(tx, uids, stake, d) {
  for (const uid of uids) {
    const s = d ? stakeTotal(d, uid) : stake;
    if (s > 0) tx.write(`users/${uid}`, { incr: { balance: s } });
  }
}

// --- Parrainage (code promo = pseudo) ----------------------------------
// promoCodes/{code} : { uid }  (le code appartient au premier joueur qui le prend)
// users/{uid}       : promoCode, referrerUid, referrerCode, referralEarned
// Le parrain touche REFERRAL_PERCENT % de la part de commission de chaque
// joueur parrainé présent dans la partie (commission ÷ nombre de joueurs).
// Cette somme est prélevée sur la commission de Katika. Elle est versée dans
// users/{uid}.referralBalance, puis transférée vers le solde par referralWithdraw.

/** Code promo d'un pseudo : minuscules, sans accents, sans espaces ni symboles. */
function promoKey(pseudo) {
  const k = String(pseudo || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '')
    .replace(/^[_-]+|[_-]+$/g, '');
  return k.length >= 2 && k.length <= 30 ? k : '';
}

/** Réserve le code promo (= pseudo) du joueur, premier arrivé premier servi.
 *  Renvoie le code, ou '' s'il est impossible (pseudo vide ou déjà pris).
 *  À appeler avant les écritures de la transaction. */
async function claimPromo(tx, uid, userDoc, pseudo) {
  const key = promoKey((userDoc && userDoc.pseudo) || pseudo);
  if (!key) return '';
  if (userDoc && userDoc.promoCode === key) return key;
  const owner = await tx.get(`promoCodes/${key}`);
  if (owner) {
    if (owner.uid !== uid) return ''; // déjà pris par un autre joueur
    tx.write(`users/${uid}`, { set: { promoCode: key } });
    return key;
  }
  tx.write(`promoCodes/${key}`, { create: true, set: { uid } });
  tx.write(`users/${uid}`, { set: { promoCode: key } });
  return key;
}

/** Verse aux parrains leur part de la commission, et aux partenaires leur part
 *  du reste. Pour chaque joueur parrainé : le parrain touche REFERRAL_PERCENT %
 *  de la part de commission du joueur ; si ce parrain (ou le parrain de ce
 *  parrain) est un compte partenaire, il touche PARTNER_PERCENT % de ce qui
 *  reste. Renvoie { referral, partner } : totaux versés. */
async function referralPayout(tx, participants, commission, info = {}) {
  const list = [...new Set(participants.filter((u) => typeof u === 'string'))];
  if (!(commission > 0) || list.length === 0) return { referral: 0, partner: 0 };
  const share = commission / list.length;

  const gains = new Map();
  const pGains = new Map();
  for (const u of list) {
    const d = await tx.get(`users/${u}`);
    const r = d && typeof d.referrerUid === 'string' ? d.referrerUid : '';
    if (!r || r === u) continue;
    // Hôtesse : son code sert seulement à compter les inscrits, sans commission.
    const rh = await tx.get(`users/${r}`);
    if (!rh) continue; // parrain dont le compte a été supprimé
    if (rh.hostess === true) continue;
    // Palier du parrain selon son nombre de filleuls (compteur refCount, calculé une fois si absent).
    let nKids = typeof rh.refCount === 'number' ? rh.refCount : -1;
    if (nKids < 0 && tx.env) {
      nKids = await referralCountOf(tx.env, r);
      if (nKids >= 0) {
        tx.write(`users/${r}`, { set: { refCount: nKids } });
        rh.refCount = nKids;
      }
    }
    const bonus = Math.floor((share * referralPercentFor(Math.max(0, nKids))) / 100);
    const partnerBonus = Math.floor(((share - bonus) * PARTNER_PERCENT) / 100);
    if (bonus > 0) gains.set(r, (gains.get(r) || 0) + bonus);

    if (partnerBonus > 0) {
      const rd = await tx.get(`users/${r}`);
      let partner = '';
      if (rd && rd.partner === true) partner = r;
      else if (rd && typeof rd.referrerUid === 'string' && rd.referrerUid) {
        const pd = await tx.get(`users/${rd.referrerUid}`);
        if (pd && pd.partner === true) partner = rd.referrerUid;
      }
      if (partner && partner !== u) {
        pGains.set(partner, (pGains.get(partner) || 0) + partnerBonus);
      }
    }
  }
  let referral = 0;
  for (const [r, g] of gains) {
    tx.write(`users/${r}`, { incr: { referralBalance: g, referralEarned: g } });
    referral += g;
  }
  const zone = await zonePayout(tx, list, share, info);
  let partner = 0;
  for (const [p, g] of pGains) {
    tx.write(`users/${p}`, { incr: { partnerBalance: g, partnerEarned: g } });
    tx.write(`partnerEarnings/${newId()}`, {
      create: true,
      set: {
        partner: p,
        amount: g,
        gameId: String(info.gameId || ''),
        mode: String(info.mode || ''),
      },
      serverTime: ['createdAt'],
    });
    partner += g;
  }
  // Commission des partenaires exclusifs de zone : comptée avec les partenaires pour la part de Katika.
  return { referral, partner: partner + zone, zone };
}

// --- Jackpot ----------------------------------------------------------
// app/jackpot       : { pool }   (lisible par les joueurs, pour l'afficher)
// app/jackpotTarget : { target } (secret : tirage au sort entre 550 et 650)
// Quand la cagnotte du jackpot a atteint le seuil tiré au sort, le gagnant de
// la partie suivante remporte tout le jackpot, puis un nouveau seuil est tiré.

/** Verse les gains, gère le jackpot et les commissions de parrainage.
 *  Renvoie { jackpot, referral } : jackpot remporté (0 si aucun) et total
 *  versé aux parrains. `participants` = tous les joueurs qui ont misé. */
async function payOut(
  tx,
  { stake, pot, winners, percent = COMMISSION_PERCENT, participants = [], gameId = '', mode = '', stakeOf = null },
) {
  if (!(stake > 0) || !(pot > 0) || winners.length === 0) {
    return { jackpot: 0, referral: 0, partner: 0, house: 0 };
  }

  const n = winners.length;
  const prize = prizeOf(pot, percent);
  const commission = pot - prize;
  const prizeShare = Math.floor(prize / n);

  // Jackpot désactivé : aucune part prélevée, rien n'est versé.
  let jackpot = 0;
  let jackpotCut = 0;
  let jackpotShare = 0;
  if (JACKPOT_ENABLED) {
    const jack = await tx.get('app/jackpot');
    const targ = await tx.get('app/jackpotTarget');
    let pool = intOr(jack ? jack.pool : 0, 0);
    let target = intOr(targ ? targ.target : 0, 0);
    if (target <= 0) target = newTarget();
    if (pool >= target) {
      jackpot = pool;
      pool = 0;
      target = newTarget();
    }
    jackpotShare = Math.floor(jackpot / n);
    jackpotCut = Math.floor((commission * JACKPOT_PERCENT) / 100);
    pool += jackpotCut + (jackpot - jackpotShare * n);
    tx.write('app/jackpot', { set: { pool } });
    tx.write('app/jackpotTarget', { set: { target } });
  }

  const { referral, partner } = await referralPayout(tx, participants, commission, {
    gameId,
    mode,
  });

  // Total misé par chaque joueur (users/{uid}.wagered) : sert à savoir quels
  // filleuls sont « actifs » pour le retrait des partenaires.
  const toCount = new Set(participants.filter((u) => typeof u === 'string'));
  for (const uid of winners) {
    tx.write(`users/${uid}`, {
      incr: {
        balance: prizeShare + jackpotShare,
        ...(toCount.delete(uid) ? { wagered: stakeOf ? stakeOf(uid) : stake } : {}),
      },
    });
  }
  for (const uid of toCount) tx.write(`users/${uid}`, { incr: { wagered: stakeOf ? stakeOf(uid) : stake } });
  // Part nette de Katika : commission - jackpot - parrains - partenaires.
  const house = Math.max(0, commission - jackpotCut - referral - partner);
  return { jackpot: jackpotShare * n, referral, partner, house };
}

// --- Commissions de Katika (compte de l'administrateur) ----------------
// house/ledger : { balance, earned, withdrawn }
//   earned    = total des commissions revenues à Katika (cumul)
//   balance   = part pas encore retirée
//   withdrawn = total déjà transféré vers le compte principal de l'admin
// Part de Katika sur une partie = commission - part du jackpot - part des
// parrains. Les commissions sur les paris gagnés reviennent entièrement à
// Katika. Ce document n'est lisible que par le serveur (aucune règle Firestore
// ne doit l'ouvrir aux joueurs).
const HOUSE_PATH = 'house/ledger';

// Caisse commune : toutes les commissions s'accumulent dans une seule caisse
// (house/ledger.balance). N'importe quel compte de ADMIN_UIDS peut retirer
// tout ce qui est disponible vers son propre compte. Les champs bal0/bal1 des
// anciennes versions sont regroupés : balance = bal0 + bal1.

/** Solde disponible de la caisse (ancien format 50/50 inclus). */
function houseTotal(h) {
  if (h && h.bal0 !== undefined && h.bal0 !== null && h.bal1 !== undefined && h.bal1 !== null) {
    return Math.max(0, intOr(h.bal0, 0)) + Math.max(0, intOr(h.bal1, 0));
  }
  return Math.max(0, intOr(h ? h.balance : 0, 0));
}

/** Ajoute `amount` à la caisse commune (à appeler UNE fois par transaction). */
async function houseAdd(tx, amount) {
  amount = Math.floor(amount);
  if (!(amount > 0)) return;
  const h = await tx.get(HOUSE_PATH);
  const total = houseTotal(h) + amount;
  tx.write(HOUSE_PATH, {
    set: {
      bal0: total,
      bal1: 0,
      balance: total,
      earned: Math.max(0, intOr(h ? h.earned : 0, 0)) + amount,
    },
  });
}

// --- Qui a gagné ? ----------------------------------------------------

function colorsFor(max) {
  return max === 2 ? [0, 2] : max === 3 ? [0, 1, 2] : [0, 1, 2, 3];
}

/** Ludo : gagnant désigné (abandon) ou premier camp dont tous les pions sont
 *  arrivés (56). En équipe, le binôme gagne aussi. Renvoie des uid. */
function ludoWinners(d, uids) {
  const colors = colorsFor(intOr(d.maxPlayers, 4));
  const forfeited = Array.isArray(d.forfeited) ? d.forfeited : [];
  let w = intOr(d.winner, -1);
  if (w < 0) {
    const found = colors.find((c) => {
      const p = d['p' + c];
      return (
        !forfeited.includes(c) &&
        Array.isArray(p) &&
        p.length > 0 &&
        p.every((x) => x === 56)
      );
    });
    w = found === undefined ? -1 : found;
  }
  if (w < 0) return [];

  const list = [w];
  if (d.teamMode === true && Array.isArray(d.partners)) {
    const mate = intOr(d.partners[w], -1);
    if (mate >= 0 && mate !== w) list.push(mate);
  }
  return list.map((c) => uids[colors.indexOf(c)]).filter((u) => typeof u === 'string');
}

/** Deux dés : le(s) joueur(s) au score le plus élevé (ex æquo possibles). */
function deuxDesWinners(d, uids) {
  const scores = Array.isArray(d.scores) ? d.scores : [];
  if (scores.length !== uids.length || scores.length === 0) return [];
  const best = Math.max(...scores);
  return uids.filter((_, i) => scores[i] === best);
}

/** Songô : abandon (forfeit = place du perdant) sinon le plus de graines. */
function songoWinners(d, uids) {
  const f = intOr(d.forfeit, -1);
  if (f === 0 || f === 1) return uids[1 - f] ? [uids[1 - f]] : [];
  return deuxDesWinners(d, uids);
}

/** Damier : abandon (forfeit = place du perdant) sinon les places listées dans
 *  `winners` (une place, ou les deux en cas de partie nulle). */
function damierWinners(d, uids) {
  const f = intOr(d.forfeit, -1);
  if (f === 0 || f === 1) return uids[1 - f] ? [uids[1 - f]] : [];
  const seats = Array.isArray(d.winners) ? d.winners : [];
  return seats
    .filter((s) => s === 0 || s === 1)
    .map((s) => uids[s])
    .filter((u) => typeof u === 'string');
}

/** Damier : règle du nul choisie par le créateur (drawSeat = place qui gagne,
 *  drawNum/drawDen = chances). Tirage au sort fait ICI, côté serveur, au moment
 *  du règlement. Renvoie null s'il n'y a pas de règle ou pas de nul. */
function resolveDamierDraw(d, uids) {
  const f = intOr(d.forfeit, -1);
  if (f === 0 || f === 1) return null;
  const seats = Array.isArray(d.winners) ? d.winners : [];
  if (!(seats.includes(0) && seats.includes(1))) return null; // pas un nul
  const ds = intOr(d.drawSeat, -1);
  if (ds !== 0 && ds !== 1) return null;
  const den = intOr(d.drawDen, 1);
  const num = intOr(d.drawNum, 1);
  if (den < 1 || den > 4 || num < 1 || num > den) return null;
  if (typeof uids[ds] !== 'string') return null;
  const roll = crypto.getRandomValues(new Uint32Array(1))[0] % den;
  const won = roll < num;
  return {
    winners: won ? [uids[ds]] : null,
    extra: won
      ? { drawRolled: true, drawWon: true, winners: [ds] }
      : { drawRolled: true, drawWon: false },
  };
}

function winnersFor(col, d, uids) {
  if (col === 'deuxdes') return deuxDesWinners(d, uids);
  if (col === 'damier') return damierWinners(d, uids);
  if (col === 'songo') return songoWinners(d, uids);
  if (col === 'pileface') return typeof d.winnerUid === 'string' ? [d.winnerUid] : [];
  if (col === 'cards') return Array.isArray(d.winnerUids) ? d.winnerUids : [];
  return ludoWinners(d, uids);
}

// ======================================================================
// Les fonctions (mêmes noms que les anciennes Cloud Functions)
// ======================================================================

/** Crée le portefeuille (jetons de bienvenue) et renvoie le solde.
 *  Réserve aussi le code promo du joueur (son pseudo). */
async function ensureWallet({ uid, data, env }) {
  const pseudo = typeof data.pseudo === 'string' ? data.pseudo.trim().slice(0, 40) : '';
  const balance = await runTx(env, async (tx) => {
    const d = await tx.get(`users/${uid}`);
    await claimPromo(tx, uid, d, pseudo);
    if (d && typeof d.balance === 'number') {
      if (pseudo && !d.pseudo) tx.write(`users/${uid}`, { set: { pseudo } });
      return d.balance;
    }
    tx.write(`users/${uid}`, {
      set: { balance: WELCOME, ...(pseudo ? { pseudo } : {}) },
      serverTime: ['createdAt'],
    });
    return WELCOME;
  });
  later(env, maybeSweep(env));
  return { balance };
}

/** Parrainage : le joueur saisit le code promo (pseudo) de son parrain.
 *  Une seule fois, définitif. */
async function applyPromo({ uid, data, env }) {
  const key = promoKey(data.code);
  if (!key) throw new HttpError('invalid-argument', 'Code promo invalide.');

  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (typeof me.referrerUid === 'string' && me.referrerUid) {
      throw new HttpError('failed-precondition', 'Tu as déjà un parrain.');
    }
    const owner = await tx.get(`promoCodes/${key}`);
    if (!owner || typeof owner.uid !== 'string') {
      throw new HttpError('not-found', "Ce code promo n'existe pas.");
    }
    if (owner.uid === uid) {
      throw new HttpError('invalid-argument', 'Tu ne peux pas utiliser ton propre code.');
    }
    const sponsor = await tx.get(`users/${owner.uid}`);
    if (!sponsor) throw new HttpError('not-found', "Ce code promo n'existe pas.");
    if (sponsor.referrerUid === uid) {
      throw new HttpError('invalid-argument', 'Ce joueur est déjà ton filleul.');
    }
    tx.write(`users/${uid}`, {
      set: { referrerUid: owner.uid, referrerCode: key },
      serverTime: ['referredAt'],
    });
    // Compteur de filleuls du parrain (sert aux paliers de commission).
    if (typeof sponsor.refCount === 'number') {
      tx.write(`users/${owner.uid}`, { incr: { refCount: 1 } });
    } else {
      const n = await referralCountOf(env, owner.uid);
      if (n >= 0) tx.write(`users/${owner.uid}`, { set: { refCount: n + 1 } });
    }
    return { sponsor: sponsor.pseudo || key };
  });
}

/** Parrainage : mon code, mon parrain, mon nombre de filleuls et mes gains. */
async function referralInfo({ uid, data, env }) {
  const pseudo = typeof data.pseudo === 'string' ? data.pseudo.trim().slice(0, 40) : '';
  const info = await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const code = await claimPromo(tx, uid, me, pseudo);
    let sponsor = null;
    if (typeof me.referrerUid === 'string' && me.referrerUid) {
      const s = await tx.get(`users/${me.referrerUid}`);
      sponsor = (s && s.pseudo) || me.referrerCode || '?';
    }
    let reason = null;
    if (!code) reason = promoKey(me.pseudo || pseudo) ? 'taken' : 'nopseudo';
    const earned = Math.max(0, intOr(me.referralEarned, 0));
    // Gains de parrainage pas encore transférés vers le solde principal.
    const available = Math.max(0, intOr(me.referralBalance, 0));
    return {
      code: code || null,
      reason,
      sponsor,
      earned,
      available,
      minWithdraw: REFERRAL_WITHDRAW_MIN,
      canWithdraw: available >= REFERRAL_WITHDRAW_MIN,
    };
  });

  let referrals = 0;
  try {
    const r = await fsCall(env, 'runAggregationQuery', {
      structuredAggregationQuery: {
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'referrerUid' },
              op: 'EQUAL',
              value: { stringValue: uid },
            },
          },
        },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    referrals = Number(r[0].result.aggregateFields.n.integerValue) || 0;
  } catch (_) {}

  const tiers = [];
  let prev = 0;
  for (const [max, p] of REFERRAL_TIERS) {
    tiers.push({ from: prev + 1, to: max, percent: p });
    prev = max;
  }
  tiers.push({ from: prev + 1, to: 0, percent: REFERRAL_TOP_PERCENT });
  return { ...info, referrals, percent: referralPercentFor(referrals), tiers };
}

/** Paie la mise. Salle pleine + tout le monde a payé (+ binômes formés en
 *  équipe) : la partie démarre. */
async function payStake({ uid, data, env }) {
  const gameId = idOf(data);
  const announce = await runTx(env, async (tx) => {
    const [g, me] = await Promise.all([locate(tx, gameId), tx.get(`users/${uid}`)]);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const d = g.data;

    const players = playersOf(d);
    if (!players.some((p) => p.uid === uid)) {
      throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    }
    const paid = Array.isArray(d.paid) ? d.paid : [];
    if (paid.includes(uid)) return null; // déjà payé
    if (d.status !== 'waiting') {
      throw new HttpError('failed-precondition', 'La partie a déjà commencé.');
    }

    const perSeat = stakeFor(d, uid);
    if (perSeat > 0 && (perSeat < MIN_STAKE || perSeat > MAX_STAKE)) {
      throw new HttpError('failed-precondition', 'Mise invalide.');
    }
    const stake = perSeat * seatsOf(d, uid); // 2 places = 2 mises
    // Mises différentes : les deux doivent être payantes (ou les deux gratuites).
    if (d.stakeOpp !== undefined && d.stakeOpp !== null && (intOr(d.stake, 0) > 0) !== (intOr(d.stakeOpp, 0) > 0)) {
      throw new HttpError('failed-precondition', 'Mise invalide.');
    }
    // Captures payantes : il faut aussi pouvoir payer au moins une capture.
    const capNeed = g.col === 'games' ? capFeeOf(d) : 0;
    if ((stake > 0 || capNeed > 0) && balanceOf(me) < stake + capNeed) {
      throw new HttpError(
        'failed-precondition',
        capNeed > 0
          ? `Solde insuffisant : il faut au moins ${stake + capNeed} FCFA (mise + une capture de ${capNeed} FCFA).`
          : 'Solde insuffisant.',
      );
    }

    const max = intOr(d.maxPlayers, 2);
    const team = d.teamMode === true;
    const partners = Array.isArray(d.partners) ? d.partners : [];
    const teamsReady = !team || (partners.length === 4 && partners.every((p) => p !== -1));
    const ready = players.length >= max && paid.length + 1 >= max && teamsReady;

    // Mise différée : le solde reste intact jusqu'au lancement (startGame).
    const defer = d.deferred === true || (paid.length === 0 && d.charged !== true);
    if (defer) {
      tx.write(g.path, { union: { paid: [uid] }, set: { deferred: true } });
    } else {
      if (stake > 0) tx.write(`users/${uid}`, { incr: { balance: -stake } });
      tx.write(g.path, {
        union: { paid: [uid] },
        incr: { pot: stake },
        // La partie ne démarre plus toute seule : le créateur la lance (startGame).
        set: {},
      });
    }
    // Nouvelle partie publique créée par son créateur : on préviendra les joueurs.
    if (d.hostUid === uid && d.private !== true && players.length === 1 && paid.length === 0) {
      return {
        col: g.col,
        host: typeof d.hostName === 'string' ? d.hostName : '',
        stake,
      };
    }
    return null;
  });
  if (announce) later(env, pushNewGame(env, uid, announce));
  return { ok: true };
}

// ======================================================================
// Notifications push (version web) : « Nouvelle partie »
// ======================================================================

const GAME_LABELS = { games: 'Ludo', deuxdes: 'Deux dés', songo: 'Songô', damier: 'Damier' };

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', te.encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Le joueur active (enabled = true) ou coupe (false) les notifications
 *  sur cet appareil. data : { token, enabled } */
async function setPush({ uid, data, env }) {
  const token = typeof data.token === 'string' ? data.token.trim() : '';
  if (token.length < 20 || token.length > 4096) {
    throw new HttpError('invalid-argument', 'Jeton de notification invalide.');
  }
  const id = (await sha256Hex(token)).slice(0, 40);
  await runTx(env, async (tx) => {
    if (data.enabled === false) {
      tx.delete(`pushTokens/${id}`);
    } else {
      tx.write(`pushTokens/${id}`, { set: { uid, token }, serverTime: ['createdAt'] });
    }
  });
  return { ok: true };
}

/** Notification push à UN joueur (tous ses appareils inscrits). Sans effet si aucun appareil. */
async function pushToUser(env, uid, title, body) {
  try {
    if (!uid) return;
    const docs = await queryDocs(env, 'pushTokens', eqFilter('uid', uid), 20);
    const targets = docs.filter((x) => typeof x.token === 'string');
    if (!targets.length) return;
    const access = await accessToken(env, 'https://www.googleapis.com/auth/firebase.messaging');
    const url = `https://fcm.googleapis.com/v1/projects/${projectId(env)}/messages:send`;
    const dead = [];
    await Promise.allSettled(
      targets.map(async (t) => {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', authorization: `Bearer ${access}` },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title, body },
              webpush: { headers: { Urgency: 'high', TTL: '86400' } },
            },
          }),
        });
        if (res.status === 404) dead.push(t.id);
      }),
    );
    if (dead.length) {
      await runTx(env, async (tx) => {
        for (const id of dead) tx.delete(`pushTokens/${id}`);
      });
    }
  } catch (_) {
    /* sans effet */
  }
}

/** Envoie « Nouvelle partie » à tous les appareils inscrits, sauf au créateur. */
async function pushNewGame(env, hostUid, info) {
  try {
    // Anti-spam : au plus une alerte par créateur et par jeu toutes les 20 secondes
    // (chaque partie créée par quelqu'un d'autre prévient les joueurs).
    const key = (String(info.label || info.col || 'x').replace(/[^A-Za-z0-9]/g, '').slice(0, 20) || 'x') + '_' + String(hostUid || '').slice(0, 24);
    const last = await readDoc(env, `pushThrottle/${key}`);
    if (last && Date.now() - intOr(last.ms, 0) < 20000) return;
    await runTx(env, async (tx) => tx.write(`pushThrottle/${key}`, { set: { ms: Date.now() } }));
    const docs = await queryDocs(env, 'pushTokens', undefined, 300);
    const targets = docs.filter((x) => x.uid !== hostUid && typeof x.token === 'string');
    if (!targets.length) return;
    const access = await accessToken(env, 'https://www.googleapis.com/auth/firebase.messaging');
    const label = info.label || GAME_LABELS[info.col] || 'Katika';
    const who = info.host || 'Un joueur';
    const title = `🎲 Nouvelle partie de ${label}`;
    const body = info.stake > 0
      ? `${who} mise ${info.stake} FCFA 🔥 Rejoins-le !`
      : `${who} a créé une partie 🔥 Rejoins-le !`;
    const url = `https://fcm.googleapis.com/v1/projects/${projectId(env)}/messages:send`;
    const dead = [];
    let sent = 0;
    let firstErr = '';
    await Promise.allSettled(
      targets.map(async (t) => {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', authorization: `Bearer ${access}` },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title, body },
              webpush: {
                headers: { Urgency: 'high', TTL: '3600' },
                fcm_options: { link: 'https://katikagames.com/jouer/' },
              },
            },
          }),
        });
        if (res.ok) sent++;
        else {
          if (res.status === 404) dead.push(t.id);
          if (!firstErr) firstErr = `HTTP ${res.status} ${(await res.text().catch(() => '')).slice(0, 160)}`;
        }
      }),
    );
    if (sent === 0 && firstErr) {
      console.error('pushNewGame', firstErr);
    }
    if (dead.length) {
      await runTx(env, async (tx) => {
        for (const id of dead) tx.delete(`pushTokens/${id}`);
      });
    }
  } catch (e) {
    /* une notification ratée ne doit jamais bloquer la création de la partie */
    console.error('pushNewGame', e && e.message ? e.message : e);
  }
}

/** Montant d'une capture payante fixé à la création de la partie (0 = aucun). */
function capFeeOf(d) {
  const c = intOr(d && d.capturePay, 0);
  return c >= MIN_CAPTURE ? Math.min(c, MAX_CAPTURE) : 0;
}

/** Capture payante (Ludo en ligne) : le montant fixé à la création de la
 *  partie passe du solde du joueur capturé à celui du joueur qui capture
 *  (au plus ce que le joueur capturé possède). Chaque capture n'est payée
 *  qu'une fois (eventId) et leur nombre est plafonné par le nombre de coups
 *  joués dans la partie. */
async function captureFee({ uid, data, env }) {
  const gameId = idOf(data);
  const capturer = typeof data.capturerUid === 'string' ? data.capturerUid : '';
  const victim = typeof data.victimUid === 'string' ? data.victimUid : '';
  const eventId = typeof data.eventId === 'string' ? data.eventId : '';
  if (!gameId || !capturer || !victim || capturer === victim || !/^[A-Za-z0-9]{6,48}$/.test(eventId)) {
    throw new HttpError('invalid-argument', 'Capture invalide.');
  }
  return runTx(env, async (tx) => {
    // Partie en ligne (games) ou en présentiel (localGames).
    let g = await locate(tx, gameId);
    let local = false;
    if (!g) {
      const ld = await tx.get(`localGames/${gameId}`);
      if (ld) {
        g = { path: `localGames/${gameId}`, data: ld, col: 'localGames' };
        local = true;
      }
    }
    if (!g || (!local && g.col !== 'games')) {
      throw new HttpError('not-found', "Cette partie n'existe plus.");
    }
    const d = g.data;
    if (local && (d.hostUid !== uid || d.settled === true)) {
      throw new HttpError('permission-denied', 'Seul le joueur principal peut déclarer une capture.');
    }
    const uids = Array.isArray(d.uids) ? d.uids : [];
    if (!uids.includes(uid) || !uids.includes(capturer) || !uids.includes(victim)) {
      throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    }
    if (d.status !== 'playing') {
      throw new HttpError('failed-precondition', "La partie n'est pas en cours.");
    }
    const fee = capFeeOf(d);
    if (fee <= 0) return { amount: 0 };

    const evPath = `${g.path}/captures/${eventId}`;
    const done = await tx.get(evPath);
    if (done) return { amount: intOr(done.amount, 0), eliminated: done.eliminated === true };

    // Plafond : un coup capturant = au moins 2 mises à jour de la partie.
    const metaPath = `${g.path}/captures/meta`;
    const meta = await tx.get(metaPath);
    const count = intOr(meta && meta.count, 0);
    const cap = local ? 300 : Math.floor(intOr(d.rev, 0) / 2) + 2;
    if (count + 1 > cap) {
      throw new HttpError('failed-precondition', 'Trop de captures pour cette partie.');
    }

    const v = await tx.get(`users/${victim}`);
    const c = await tx.get(`users/${capturer}`);
    if (!c) throw new HttpError('not-found', 'Compte introuvable.');
    const amount = Math.max(0, Math.min(fee, balanceOf(v)));
    // Le capturé n'a pas assez pour payer toute la capture : il perd la partie.
    const eliminated = balanceOf(v) < fee;

    // Commission Katika (5 %) sur chaque capture payante, comme sur tous les paris.
    const net = prizeOf(amount);
    const cut = amount - net;
    tx.write(evPath, {
      create: true,
      set: { amount, net, fee: cut, capturer, victim, eliminated },
      serverTime: ['createdAt'],
    });
    tx.write(metaPath, { incr: { count: 1 } });
    if (amount > 0) {
      tx.write(`users/${victim}`, { incr: { balance: -amount } });
      tx.write(`users/${capturer}`, { incr: { balance: net } });
      if (cut > 0) {
        const ref = await referralPayout(tx, [capturer, victim], cut, { gameId, mode: 'capture', ref: eventId });
        await houseAdd(tx, cut - ref.referral - ref.partner);
      }
      // Avis affiché à l'écran des deux joueurs : gain / perte + nouveau solde (aucun frais sur les captures).
      const at = Date.now();
      tx.write(`users/${capturer}`, {
        set: { capNotice: { id: eventId, kind: 'gain', amount, fee: cut, balance: balanceOf(c) + net, other: tournName(v), at } },
      });
      tx.write(`users/${victim}`, {
        set: { capNotice: { id: eventId, kind: 'loss', amount, fee: cut, balance: balanceOf(v) - amount, other: tournName(c), at } },
      });
    }
    return { amount, net, fee: cut, eliminated, balance: balanceOf(c) + net };
  });
}

/** Le créateur lance la partie quand il le veut, dès 2 joueurs, même si la
 *  salle n'est pas pleine (4 places, 1 seul joueur arrivé : il lance à 2).
 *  Tous les joueurs présents doivent avoir validé leur mise. Le nombre de
 *  places devient le nombre de joueurs réellement présents. */
async function startGame({ uid, data, env }) {
  const gameId = idOf(data);
  return runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const d = g.data;
    if (d.hostUid !== uid) {
      throw new HttpError('permission-denied', 'Seul le créateur peut lancer la partie.');
    }
    if (d.status === 'playing') return { started: true };
    if (d.status !== 'waiting') {
      throw new HttpError('failed-precondition', 'Cette partie ne peut plus être lancée.');
    }
    const players = playersOf(d);
    const paid = Array.isArray(d.paid) ? d.paid : [];
    if (players.length < 2) {
      throw new HttpError('failed-precondition', 'Il faut au moins 2 joueurs pour lancer la partie.');
    }
    const unpaid = players.filter((p) => !paid.includes(p.uid));
    if (unpaid.length > 0) {
      throw new HttpError(
        'failed-precondition',
        `${unpaid.map((p) => p.name || 'Un joueur').join(', ')} n'a pas encore validé sa mise.`,
      );
    }
    const set = { status: 'playing', maxPlayers: players.length };
    // Mises prélevées maintenant (salle « différée ») : chacun doit avoir le solde.
    const inc = {};
    if (d.deferred === true && d.charged !== true) {
      const capNeed = g.col === 'games' ? capFeeOf(d) : 0;
      const ids = [...new Set(players.map((p) => p.uid))];
      const docs = await Promise.all(ids.map((u) => tx.get(`users/${u}`)));
      const short = [];
      let pot = 0;
      ids.forEach((u, i) => {
        const st = stakeTotal(d, u);
        if ((st > 0 || capNeed > 0) && balanceOf(docs[i]) < st + capNeed) {
          const pl = players.find((p) => p.uid === u);
          short.push((pl && pl.name) || 'Un joueur');
        }
        pot += st;
      });
      if (short.length > 0) {
        throw new HttpError(
          'failed-precondition',
          `${short.join(', ')} n'a pas assez de solde pour la mise. Le joueur doit recharger ou quitter la salle.`,
        );
      }
      ids.forEach((u) => {
        const st = stakeTotal(d, u);
        if (st > 0) tx.write(`users/${u}`, { incr: { balance: -st } });
      });
      set.charged = true;
      inc.pot = pot;
    }
    // Revanche : le gagnant de la partie précédente commence.
    if (g.col === 'games' && typeof d.starterUid === 'string') {
      const si = players.findIndex((p) => p.uid === d.starterUid);
      if (si >= 0) set.cur = colorsFor(players.length)[si];
    }
    if (g.col === 'games' && d.teamMode === true) {
      const partners = Array.isArray(d.partners) ? d.partners : [];
      const ready = players.length === 4 && partners.length === 4 && partners.every((p) => p !== -1);
      if (!ready) {
        if (players.length < 4) set.teamMode = false;
        else throw new HttpError('failed-precondition', 'Forme les binômes avant de lancer la partie.');
      }
    }
    if ((g.col === 'games' || g.col === 'deuxdes') && String(env.SERVER_AUTH || '') === '1') set.srv = true;
    // Ludo lancé à moins de joueurs que de places : les autres peuvent encore
    // entrer tant que personne n'a joué de 6 (voir ludoJoinRunning).
    const cap = intOr(d.maxPlayers, 2);
    if (g.col === 'games' && set.srv === true && set.teamMode !== true && d.teamMode !== true && players.length < cap) {
      set.lateOpen = true;
      set.lateCap = cap;
    }
    tx.write(g.path, Object.keys(inc).length ? { set, incr: inc, serverTime: ['startedAt'] } : { set, serverTime: ['startedAt'] });
    return { started: true, players: players.length };
  });
}

/** Quitte une salle d'attente : mise remboursée. L'hôte annule la partie et
 *  tout le monde est remboursé. */
async function leaveGame({ uid, data, env }) {
  const gameId = idOf(data);
  await runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
    if (!g) return;
    const d = g.data;
    if (d.status !== 'waiting') return; // en cours : on abandonne dans le jeu

    const players = playersOf(d);
    const paid = Array.isArray(d.paid) ? d.paid : [];
    const debited = chargedPaid(d);
    const stake = Math.max(0, intOr(d.stake, 0));
    const isHost = d.hostUid === uid;
    if (!isHost && !players.some((p) => p.uid === uid)) return;

    if (isHost) {
      refund(tx, debited, stake, d);
      tx.delete(g.path);
      return;
    }

    const o = {
      set: { players: players.filter((p) => p.uid !== uid) },
      remove: { uids: [uid] },
    };
    if (paid.includes(uid)) {
      o.remove.paid = [uid];
      if (debited.includes(uid)) {
        const mine = stakeTotal(d, uid);
        refund(tx, [uid], mine);
        o.incr = { pot: -mine };
      }
    }
    // Les places changent quand quelqu'un part : on refait les binômes.
    if (d.teamMode === true) {
      o.set.partners = d.dbl === true ? [1, 0, -1, -1] : [-1, -1, -1, -1]; // joueur à 2 places : binôme fixe
      o.set.invites = [];
    }
    tx.write(g.path, o);
  });
  return { ok: true };
}

/** Fin d'une partie en ligne : verse la cagnotte (une seule fois).
 *  La commission et la part versée aux parrains sont enregistrées sur la
 *  partie (tableau de bord). */
/** Statistiques des joueurs, mises à jour à la fin d'une partie avec gagnant :
 *  users/{uid} : statPlayed, statWon, statLost, statStaked (mises jouées),
 *  statWonAmt (gains reçus), statLostAmt (mises perdues). */
function recordStats(tx, participants, winners, stake, pot, percent, jackpot, stakeOf = null) {
  const all = [...new Set((participants || []).filter((u) => typeof u === 'string'))];
  const win = new Set(winners || []);
  const n = Math.max(1, win.size);
  const prizeShare =
    stake > 0 && pot > 0
      ? Math.floor(prizeOf(pot, percent) / n) + Math.floor(intOr(jackpot, 0) / n)
      : 0;
  for (const u of all) {
    const isWin = win.has(u);
    const mine = stakeOf ? stakeOf(u) : stake;
    tx.write(`users/${u}`, {
      incr: {
        statPlayed: 1,
        statStaked: mine > 0 ? mine : 0,
        ...(isWin
          ? { statWon: 1, statWonAmt: prizeShare }
          : { statLost: 1, statLostAmt: mine > 0 ? mine : 0 }),
      },
    });
  }
}

/** Administrateur : ajoute aux statistiques des joueurs les parties EN LIGNE
 *  terminées avant la date `before` (ISO) et pas encore comptées. À relancer
 *  tant que `remaining` > 0. Les parties en présentiel ne peuvent pas être
 *  reprises (leurs gagnants n'avaient pas été enregistrés). Chaque partie
 *  traitée reçoit le marqueur statsBackfilled : aucun double comptage. */
async function adminBackfillStats({ uid, data, env }) {
  requireAdmin(uid, env);
  const before = typeof data.before === 'string' ? data.before : '';
  if (!before || Number.isNaN(Date.parse(before))) {
    throw new HttpError('invalid-argument', 'Date invalide.');
  }
  const maxGames = Math.min(400, Math.max(40, intOr(data.max, 200)));

  const todo = [];
  for (const col of ONLINE_COLLECTIONS) {
    const list = await queryDocs(env, col, eqFilter('settled', true), 1000);
    for (const g of list) {
      if (g.statsBackfilled === true || g.refunded === true) continue;
      if (typeof g.createdAt !== 'string' || g.createdAt >= before) continue;
      todo.push({ path: `${col}/${g.id}`, col });
    }
  }

  const batch = todo.slice(0, maxGames);
  let counted = 0;
  for (let i = 0; i < batch.length; i += 40) {
    const chunk = batch.slice(i, i + 40);
    counted += await runTx(env, async (tx) => {
      let n = 0;
      for (const item of chunk) {
        const g = await tx.get(item.path);
        if (!g || g.settled !== true || g.statsBackfilled === true || g.refunded === true) continue;
        const uids = playersOf(g).map((p) => p.uid);
        const paid = Array.isArray(g.paid) ? g.paid : [];
        const stake = Math.max(0, intOr(g.stake, 0));
        const pot = Math.max(0, intOr(g.pot, 0));
        let winners = winnersFor(item.col, g, uids);
        if (stake > 0) winners = winners.filter((u) => paid.includes(u));
        if (winners.length > 0) {
          recordStats(tx, paid.length ? paid : uids, winners, stake, pot, COMMISSION_PERCENT, intOr(g.jackpot, 0), (u) => stakeTotal(g, u));
          n++;
        }
        tx.write(item.path, { set: { statsBackfilled: true } });
      }
      return n;
    });
  }
  return { counted, processed: batch.length, remaining: Math.max(0, todo.length - batch.length) };
}

/** Administrateur : tous les joueurs inscrits avec leurs statistiques. */
async function adminPlayers({ uid, data, env }) {
  requireAdmin(uid, env);
  const limit = Math.min(2000, Math.max(50, intOr(data.limit, 1000)));
  const res = await fsCall(env, 'runQuery', {
    structuredQuery: { from: [{ collectionId: 'users' }], limit },
  });
  const players = (Array.isArray(res) ? res : [])
    .filter((r) => r.document)
    .map((r) => {
      const id = r.document.name.split('/').pop();
      const u = fieldsToObj(r.document.fields || {});
      const played = intOr(u.statPlayed, 0);
      const won = intOr(u.statWon, 0);
      return {
        uid: id,
        pseudo: typeof u.pseudo === 'string' ? u.pseudo : '',
        balance: balanceOf(u),
        createdAt: typeof u.createdAt === 'string' ? u.createdAt : null,
        played,
        won,
        lost: intOr(u.statLost, 0),
        staked: intOr(u.statStaked, 0),
        wonAmt: intOr(u.statWonAmt, 0),
        lostAmt: intOr(u.statLostAmt, 0),
        winRate: played > 0 ? Math.floor((won * 1000) / played) / 10 : 0,
        partner: u.partner === true,
        risk: riskOf(u),
        cleared: u.riskCleared === true,
      };
    })
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
  return { players, total: players.length };
}

async function settleGameCore({ uid, data, env }) {
  const gameId = idOf(data);
  return runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const d = g.data;

    const uids = playersOf(d).map((p) => p.uid);
    if (!uids.includes(uid)) {
      throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    }
    if (d.settled === true) return { jackpot: intOr(d.jackpot, 0) };
    if (d.over !== true) {
      throw new HttpError('failed-precondition', "La partie n'est pas terminée.");
    }

    const stake = Math.max(0, intOr(d.stake, 0));
    const pot = Math.max(0, intOr(d.pot, 0));
    const paid = Array.isArray(d.paid) ? d.paid : [];

    let winners = winnersFor(g.col, d, uids);
    let drawExtra = {};
    if (g.col === 'damier') {
      const dr = resolveDamierDraw(d, uids);
      if (dr) {
        drawExtra = dr.extra;
        if (dr.winners) winners = dr.winners;
      }
    }
    if (stake > 0) winners = winners.filter((u) => paid.includes(u));
    winners = [...new Set(winners)]; // un joueur à 2 places gagne une seule fois

    // Aucun gagnant, ou égalité entre tous les joueurs : chacun récupère sa
    // mise en entier, sans aucune commission.
    const allTie = stake > 0 && paid.length >= 2 && winners.length === paid.length;
    if (winners.length === 0 || allTie) {
      refund(tx, paid, stake, d);
      tx.write(g.path, {
        set: {
          ...drawExtra,
          settled: true,
          jackpot: 0,
          status: 'finished',
          commission: 0,
          refunded: true,
          referralPaid: 0,
          partnerPaid: 0,
        },
      });
      return { jackpot: 0 };
    }

    // Fap-Fap : 2 x M étaient bloqués. Victoire normale : chacun récupère M et le
    // vainqueur gagne les M adverses. Corat : tout le séquestre (2 x M) est en jeu.
    const fap = g.col === 'cards' && d.game === 'fapfap';
    const acg = g.col === 'cards' && d.game === 'anticote';
    const acC = d.contrib || {};
    let effStake = stake;
    let effPot = pot;
    if (acg && stake > 0) {
      // Anti-Cote : chacun a perdu sa contribution (mises, CORAT, cagnotte) ; le reste du séquestre est rendu.
      const acE = d.esc || {};
      effPot = 0;
      for (const u of paid) {
        const c = intOr(acC[u], stake);
        effPot += c;
        const spare = intOr(acE[u], stake * 2) - c;
        if (spare > 0) tx.write(`users/${u}`, { incr: { balance: spare } });
      }
    } else if (fap && stake > 0) {
      if (d.corat === true) {
        effStake = stake * 2;
        effPot = stake * 2 * paid.length;
      } else {
        effPot = stake * paid.length;
        for (const u of paid) tx.write(`users/${u}`, { incr: { balance: stake } });
      }
    }
    const { jackpot, referral, partner, house } = await payOut(tx, {
      stake: effStake,
      pot: effPot,
      winners,
      participants: paid,
      gameId,
      mode: 'online',
      stakeOf: fap ? () => effStake : acg ? (u) => intOr(acC[u], stake) : (u) => stakeTotal(d, u),
    });
    recordStats(tx, paid.length ? paid : [...new Set(uids)], winners, effStake, effPot, COMMISSION_PERCENT, jackpot, fap ? () => effStake : acg ? (u) => intOr(acC[u], stake) : (u) => stakeTotal(d, u));
    await houseAdd(tx, house);
    const commission = effStake > 0 && effPot > 0 ? effPot - prizeOf(effPot) : 0;
    tx.write(g.path, {
      set: {
        ...drawExtra,
        settled: true,
        jackpot,
        status: 'finished',
        commission,
        referralPaid: referral,
        partnerPaid: partner,
      },
    });
    return { jackpot };
  });
}

/** Présentiel : débite la mise de chaque joueur (le jeton de chacun prouve que
 *  c'est bien lui) et crée la partie. `game` = 'ludo' ou 'deuxdes'. */
async function startLocalGame({ uid: hostUid, data, env }) {
  const stake = intOr(data.stake, -1);
  if (stake < 0 || (stake > 0 && (stake < MIN_STAKE || stake > MAX_STAKE))) {
    throw new HttpError('invalid-argument', 'Mise invalide.');
  }
  const game =
    data.game === 'deuxdes' || data.game === 'ludo' || data.game === 'songo' || data.game === 'damier' || data.game === 'pileface' || data.game === 'tiah' || data.game === 'boubayah'
      ? data.game
      : 'unknown';
  const maxLocal = game === 'deuxdes' ? 8 : game === 'songo' || game === 'damier' || game === 'pileface' ? 2 : game === 'tiah' || game === 'boubayah' ? 6 : game === 'fapfap' ? 4 : 4; // Deux dés : jusqu'à 8 joueurs
  const tokens = Array.isArray(data.tokens) ? data.tokens : [];
  if (tokens.length < 2 || tokens.length > maxLocal) {
    throw new HttpError('invalid-argument', 'Nombre de joueurs invalide.');
  }
  const names = Array.isArray(data.names) ? data.names.map(String) : [];
  const capAsked = intOr(data.capturePay, 0);
  const capturePay = capAsked >= MIN_CAPTURE ? Math.min(capAsked, MAX_CAPTURE) : 0;

  const uids = [];
  for (const t of tokens) uids.push(await verifyIdToken(t, env));
  // Ludo par équipes : un même compte peut jouer 2 places (il paie 2 mises).
  const seatCount = {};
  for (const u of uids) seatCount[u] = (seatCount[u] || 0) + 1;
  const dup = Object.values(seatCount).some((n) => n > 1);
  if (dup && !(game === 'ludo' && data.team === true && Object.values(seatCount).every((n) => n <= 2))) {
    throw new HttpError('invalid-argument', 'Un compte joue deux fois.');
  }
  const id = newGameId();
  const escMult = game === 'fapfap' ? 2 : 1; // Fap-Fap : 2 x M bloqués
  await runTx(env, async (tx) => {
    if (stake > 0) {
      for (const u of Object.keys(seatCount)) {
        const i = uids.indexOf(u);
        const doc = await tx.get(`users/${u}`);
        if (balanceOf(doc) < stake * escMult * seatCount[u] + capturePay) {
          throw new HttpError(
            'failed-precondition',
            `Solde insuffisant : ${names[i] || 'un joueur'}`,
          );
        }
      }
      for (const u of Object.keys(seatCount)) tx.write(`users/${u}`, { incr: { balance: -stake * escMult * seatCount[u] } });
    }
    tx.write(`localGames/${id}`, {
      create: true,
      set: {
        hostUid,
        uids,
        names,
        game,
        stake,
        capturePay,
        pot: stake * uids.length,
        status: 'playing',
        settled: false,
        jackpot: 0,
      },
      serverTime: ['createdAt'],
    });
  });
  return { gameId: id, id, localId: id };
}

/** Fin d'une partie en présentiel : verse la cagnotte aux gagnants désignés
 *  (commission de 5 %), règle les paris (Duel / Défi 7) avec les scores
 *  envoyés par l'appli et renvoie le jackpot éventuel + le résumé des paris.
 *  Les commissions (partie + paris) et la part des parrains sont enregistrées
 *  pour le tableau de bord. */
async function settleLocalGame({ uid, data, env }) {
  const gameId = idOf(data);
  const raw = data.winners || data.winnerUids || data.uids;
  const asked = Array.isArray(raw) ? raw.map(String) : [];
  const scores = Array.isArray(data.scores)
    ? data.scores.map((x) => (typeof x === 'number' && Number.isFinite(x) ? x : null))
    : [];
  const fscores = Array.isArray(data.fscores)
    ? data.fscores.map((x) => (typeof x === 'number' && Number.isFinite(x) ? x : null))
    : [];
  if (!gameId) throw new HttpError('invalid-argument', 'Partie inconnue.');

  return runTx(env, async (tx) => {
    const path = `localGames/${gameId}`;
    const d = await tx.get(path);
    if (!d) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (d.hostUid !== uid) {
      throw new HttpError('permission-denied', 'Seul le joueur principal peut clore la partie.');
    }
    if (d.settled === true) {
      return {
        jackpot: intOr(d.jackpot, 0),
        bets: Array.isArray(d.betsSummary) ? d.betsSummary : [],
      };
    }

    const seatUids = Array.isArray(d.uids) ? d.uids : []; // une entrée par place
    const players = [...new Set(seatUids)]; // les comptes (un compte peut avoir 2 places)
    const seatN = (u) => seatUids.filter((x) => x === u).length;
    const winners = [...new Set(asked)].filter((u) => players.includes(u));
    if (winners.length === 0) {
      throw new HttpError('invalid-argument', 'Aucun gagnant valide.');
    }

    let stake = Math.max(0, intOr(d.stake, 0));
    let pot = Math.max(0, intOr(d.pot, 0));
    const bets = await loadLocalBets(tx, gameId);
    // Égalité entre tous les joueurs : les mises sont rendues, sans commission.
    const allTie = stake > 0 && players.length >= 2 && winners.length === players.length;
    const fapLocal = d.game === 'fapfap' && stake > 0;
    const fapStake = stake;
    if (fapLocal && !allTie) {
      if (data.corat === true) {
        stake = fapStake * 2;
        pot = fapStake * 2 * seatUids.length;
      } else {
        pot = fapStake * seatUids.length;
        for (const u of seatUids) tx.write(`users/${u}`, { incr: { balance: fapStake } });
      }
    }
    let jackpot = 0;
    let referral = 0;
    let partner = 0;
    let house = 0;
    if (allTie) {
      refund(tx, seatUids, fapLocal ? fapStake * 2 : stake);
    } else {
      const r = await payOut(tx, {
        stake,
        pot,
        winners,
        percent: COMMISSION_LOCAL_PERCENT,
        participants: players,
        gameId,
        mode: 'local',
        stakeOf: (u) => stake * seatN(u),
      });
      jackpot = r.jackpot;
      referral = r.referral;
      partner = r.partner;
      house = r.house;
      recordStats(tx, players, winners, stake, pot, COMMISSION_LOCAL_PERCENT, jackpot, (u) => stake * seatN(u));
    }
    const betsSummary = settleLocalBets(
      tx,
      bets,
      players,
      scores,
      Array.isArray(d.names) ? d.names : [],
      fscores,
    );
    const commission =
      !allTie && stake > 0 && pot > 0 ? pot - prizeOf(pot, COMMISSION_LOCAL_PERCENT) : 0;
    // Commission sur les paris : 2 mises moins le gain, pour chaque pari gagné.
    const betCommission = betsSummary
      .filter((b) => b.result === 'win')
      .reduce((s, b) => s + (2 * b.amount - b.prize), 0);
    await houseAdd(tx, house + betCommission);
    tx.write(path, {
      set: {
        settled: true,
        jackpot,
        status: 'finished',
        betsSummary,
        commission,
        ...(allTie ? { refunded: true } : {}),
        betCommission,
        referralPaid: referral,
        partnerPaid: partner,
      },
    });
    return { jackpot, bets: betsSummary };
  });
}

// ======================================================================
// Paris entre joueurs : Duel et Défi 7 (Deux dés en ligne, avec mise)
// ======================================================================
// Données :
//   deuxdes/{roomId}/bets/{betId}   le pari (lisible par les joueurs)
//   deuxdes/{roomId}/betMeta/index  { ids: [...] } liste tenue par le serveur
// La liste est gardée à part (et pas dans le salon) pour qu'un joueur ne
// puisse pas la fausser depuis l'appli.
//
// Les mises sont débitées à la proposition / à l'acceptation, puis rendues
// ou versées par sideBetSync. Gain = 2 mises moins la commission (prizeOf).

const BET_MIN = MIN_STAKE;
const BET_MAX = MAX_STAKE;
const BET_MAX_OPEN_PER_PLAYER = 3;
const BET_MAX_PER_ROOM = 40; // jusqu'à 8 joueurs

const betPath = (roomId, id) => `deuxdes/${roomId}/bets/${id}`;
const betIndexPath = (roomId) => `deuxdes/${roomId}/betMeta/index`;

function idStr(v) {
  return typeof v === 'string' && ID_RE.test(v) ? v : '';
}

function seatOf(room, uid) {
  return playersOf(room).findIndex((p) => p.uid === uid);
}

/** Ce joueur a déjà lancé ses dés (ou la partie est finie). */
function hasRolled(room, seat) {
  const cur = intOr(room.cur, 0);
  return seat < 0 || room.over === true || cur > seat || (cur === seat && room.rolled === true);
}

/** Lit tous les paris d'un salon (au plus BET_MAX_PER_ROOM). */
async function loadBets(tx, roomId) {
  const idx = await tx.get(betIndexPath(roomId));
  const ids = idx && Array.isArray(idx.ids) ? idx.ids.slice(0, BET_MAX_PER_ROOM) : [];
  const out = [];
  for (const id of ids) {
    const b = await tx.get(betPath(roomId, id));
    if (b) out.push({ id, path: betPath(roomId, id), b });
  }
  return out;
}

/** Propose un pari (la mise du parieur est débitée tout de suite). */
async function sideBetPropose({ uid, data, env }) {
  const roomId = idStr(data.roomId);
  const type = data.type;
  const amount = intOr(data.amount, -1);
  const targetUid = typeof data.targetUid === 'string' && data.targetUid ? data.targetUid : null;
  const side = data.side === 'under' ? 'under' : 'over';
  let inviter = '';

  if (!roomId || (type !== 'duel' && type !== 'seven')) {
    throw new HttpError('invalid-argument', 'Pari invalide.');
  }
  if (amount < BET_MIN || amount > BET_MAX) {
    throw new HttpError('invalid-argument', 'Mise invalide.');
  }

  await runTx(env, async (tx) => {
    const room = await tx.get(`deuxdes/${roomId}`);
    if (!room) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (intOr(room.stake, 0) <= 0) {
      throw new HttpError('failed-precondition', 'Pas de pari dans une partie gratuite.');
    }
    if (room.status !== 'playing' || room.over === true) {
      throw new HttpError('failed-precondition', "La partie n'est pas en cours.");
    }
    const seat = seatOf(room, uid);
    if (seat < 0) {
      throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    }
    if (hasRolled(room, seat)) {
      throw new HttpError('failed-precondition', 'Tu as déjà lancé tes dés.');
    }

    let target = null;
    if (type === 'duel' && targetUid) {
      const ts = seatOf(room, targetUid);
      if (ts < 0 || targetUid === uid) {
        throw new HttpError('invalid-argument', 'Adversaire invalide.');
      }
      if (hasRolled(room, ts)) {
        throw new HttpError('failed-precondition', 'Ce joueur a déjà lancé ses dés.');
      }
      target = playersOf(room)[ts];
    }

    const bets = await loadBets(tx, roomId);
    if (bets.length >= BET_MAX_PER_ROOM) {
      throw new HttpError('failed-precondition', 'Trop de paris dans cette partie.');
    }
    const mine = bets.filter((x) => x.b.status === 'open' && x.b.proposerUid === uid);
    if (mine.length >= BET_MAX_OPEN_PER_PLAYER) {
      throw new HttpError('failed-precondition', 'Trop de paris en attente.');
    }

    const me = await tx.get(`users/${uid}`);
    if (balanceOf(me) < amount) {
      throw new HttpError('failed-precondition', 'Solde insuffisant.');
    }
    inviter = playersOf(room)[seat].name || 'Un joueur';

    const id = newId();
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(betPath(roomId, id), {
      create: true,
      set: {
        type,
        amount,
        prize: prizeOf(amount * 2),
        side: type === 'seven' ? side : null,
        proposerUid: uid,
        proposerName: playersOf(room)[seat].name || 'Joueur',
        targetUid: target ? target.uid : null,
        targetName: target ? target.name || null : null,
        opponentUid: null,
        opponentName: null,
        status: 'open',
      },
      serverTime: ['createdAt'],
    });
    tx.write(betIndexPath(roomId), {
      set: { n: bets.length + 1 },
      union: { ids: [id] },
    });
  });
  // Invitation : le joueur défié reçoit une notification (il accepte ou refuse dans la partie).
  if (type === 'duel' && targetUid) {
    later(env, pushToUser(env, targetUid, '⚔️ Défi reçu', `${inviter} te défie de ${amount} FCFA au Deux dés. Ouvre la partie pour accepter ou refuser.`));
  }
  return { ok: true };
}

/** Relève un pari ouvert (la mise de l'adversaire est débitée). */
async function sideBetAccept({ uid, data, env }) {
  const roomId = idStr(data.roomId);
  const id = idStr(data.betId);
  if (!roomId || !id) throw new HttpError('invalid-argument', 'Pari invalide.');

  await runTx(env, async (tx) => {
    const room = await tx.get(`deuxdes/${roomId}`);
    const bet = await tx.get(betPath(roomId, id));
    if (!room || !bet) throw new HttpError('not-found', 'Pari introuvable.');
    if (bet.status !== 'open') {
      throw new HttpError('failed-precondition', "Ce pari n'est plus disponible.");
    }
    if (bet.proposerUid === uid) {
      throw new HttpError('failed-precondition', 'Tu ne peux pas relever ton propre pari.');
    }
    if (bet.targetUid && bet.targetUid !== uid) {
      throw new HttpError('permission-denied', "Ce pari ne t'est pas destiné.");
    }
    if (room.over === true || room.status !== 'playing') {
      throw new HttpError('failed-precondition', "La partie n'est pas en cours.");
    }
    const seat = seatOf(room, uid);
    if (seat < 0) {
      throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    }
    if (hasRolled(room, seat)) {
      throw new HttpError('failed-precondition', 'Tu as déjà lancé tes dés.');
    }
    if (hasRolled(room, seatOf(room, bet.proposerUid))) {
      throw new HttpError('failed-precondition', 'Le parieur a déjà lancé ses dés.');
    }
    const me = await tx.get(`users/${uid}`);
    if (balanceOf(me) < bet.amount) {
      throw new HttpError('failed-precondition', 'Solde insuffisant.');
    }

    tx.write(`users/${uid}`, { incr: { balance: -bet.amount } });
    tx.write(betPath(roomId, id), {
      set: {
        status: 'accepted',
        opponentUid: uid,
        opponentName: playersOf(room)[seat].name || 'Joueur',
      },
      serverTime: ['acceptedAt'],
    });
  });
  return { ok: true };
}

/** Annule (le parieur) ou refuse (l'adversaire visé) : mise rendue. */
async function sideBetCancel({ uid, data, env }) {
  const roomId = idStr(data.roomId);
  const id = idStr(data.betId);
  if (!roomId || !id) throw new HttpError('invalid-argument', 'Pari invalide.');

  await runTx(env, async (tx) => {
    const bet = await tx.get(betPath(roomId, id));
    if (!bet) throw new HttpError('not-found', 'Pari introuvable.');
    if (bet.status !== 'open') {
      throw new HttpError('failed-precondition', "Ce pari n'est plus en attente.");
    }
    const isProposer = bet.proposerUid === uid;
    if (!isProposer && bet.targetUid !== uid) {
      throw new HttpError('permission-denied', "Ce pari n'est pas le tien.");
    }
    tx.write(`users/${bet.proposerUid}`, { incr: { balance: bet.amount } });
    tx.write(betPath(roomId, id), {
      set: { status: isProposer ? 'cancelled' : 'declined' },
      serverTime: ['closedAt'],
    });
  });
  return { ok: true };
}

/** Règle les paris prêts : gains, remboursements, paris expirés.
 *  Appelée par les appareils à chaque lancer et en fin de partie ;
 *  sans danger si elle est appelée plusieurs fois.
 *  La commission de chaque pari gagné est ajoutée à la partie (betCommission). */
/** Avis de gain / perte d'un pari, affiché chez le joueur (+gain net ou −mise) avec son nouveau solde.
 *  Le solde est lu par l'appli dans le même document (users/{uid}), donc toujours à jour. */
function betNote(tx, uid, delta, label, detail) {
  if (!uid || !delta) return;
  tx.write(`users/${uid}`, { set: { betNotice: { id: newId(), delta, label, detail: detail || '', at: Date.now() } } });
}
function betNoteWinLose(tx, b, winner, label) {
  const loser = winner === b.proposerUid ? b.opponentUid : b.proposerUid;
  const cut = 2 * b.amount - b.prize;
  betNote(tx, winner, b.prize - b.amount, label, cut > 0 ? `commission ${cut} FCFA déduite` : '');
  betNote(tx, loser, -b.amount, label, '');
}

async function sideBetSync({ uid, data, env }) {
  const roomId = idStr(data.roomId);
  if (!roomId) throw new HttpError('invalid-argument', 'Partie invalide.');

  await runTx(env, async (tx) => {
    const room = await tx.get(`deuxdes/${roomId}`);
    if (!room) return;
    if (!playersOf(room).some((p) => p.uid === uid)) {
      throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    }
    const bets = await loadBets(tx, roomId);
    const scores = Array.isArray(room.scores) ? room.scores : [];
    let houseBets = 0; // commissions de Katika sur les paris gagnés

    for (const { path, b } of bets) {
      const pSeat = seatOf(room, b.proposerUid);

      // Pari jamais relevé : fermé dès qu'on ne peut plus le relever.
      if (b.status === 'open') {
        const expired =
          room.over === true ||
          hasRolled(room, pSeat) ||
          (b.targetUid && hasRolled(room, seatOf(room, b.targetUid)));
        if (expired) {
          tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
          tx.write(path, { set: { status: 'expired' }, serverTime: ['closedAt'] });
        }
        continue;
      }
      if (b.status !== 'accepted') continue;

      // Pari relevé : on cherche le gagnant (null = égalité).
      const oSeat = seatOf(room, b.opponentUid);
      let winner;
      if (b.type === 'seven') {
        if (!hasRolled(room, pSeat)) continue;
        const s = scores[pSeat];
        if (typeof s !== 'number') continue;
        if (s === 7) winner = null;
        else winner = s > 7 === (b.side !== 'under') ? b.proposerUid : b.opponentUid;
      } else {
        if (room.over !== true) continue;
        const a = scores[pSeat];
        const c = scores[oSeat];
        if (typeof a !== 'number' || typeof c !== 'number') continue;
        winner = a === c ? null : a > c ? b.proposerUid : b.opponentUid;
      }

      if (winner === null) {
        tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
        tx.write(`users/${b.opponentUid}`, { incr: { balance: b.amount } });
        tx.write(path, { set: { status: 'settled', result: 'refund' }, serverTime: ['closedAt'] });
      } else {
        tx.write(`users/${winner}`, { incr: { balance: b.prize } });
        betNoteWinLose(tx, b, winner, b.type === 'seven' ? 'Défi 7' : 'Duel');
        // Les paris (Duel, Défi 7) comptent dans le total misé des deux joueurs.
        tx.write(`users/${b.proposerUid}`, { incr: { wagered: b.amount } });
        tx.write(`users/${b.opponentUid}`, { incr: { wagered: b.amount } });
        tx.write(`deuxdes/${roomId}`, { incr: { betCommission: 2 * b.amount - b.prize } });
        houseBets += 2 * b.amount - b.prize;
        tx.write(path, {
          set: { status: 'settled', result: 'win', winnerUid: winner },
          serverTime: ['closedAt'],
        });
      }
    }
    await houseAdd(tx, houseBets);
  });
  return { ok: true };
}

// ======================================================================
// Paris en présentiel (Deux dés, un seul téléphone) — commission 5 %
// ======================================================================
// localGames/{id}/bets/{betId}      le pari
// localGames/{id}/betMeta/index     { ids: [...] }
// Le joueur principal envoie les jetons du parieur et de l'adversaire :
// les deux mises sont débitées tout de suite. Règlement dans settleLocalGame.

const localBetPath = (id, betId) => `localGames/${id}/bets/${betId}`;
const localBetIndexPath = (id) => `localGames/${id}/betMeta/index`;

async function loadLocalBets(tx, id) {
  const idx = await tx.get(localBetIndexPath(id));
  const ids = idx && Array.isArray(idx.ids) ? idx.ids.slice(0, BET_MAX_PER_ROOM) : [];
  const out = [];
  for (const betId of ids) {
    const b = await tx.get(localBetPath(id, betId));
    if (b) out.push({ id: betId, path: localBetPath(id, betId), b });
  }
  return out;
}

async function localBetCreate({ uid, data, env }) {
  const id = idOf(data);
  const type = data.type;
  const amount = intOr(data.amount, -1);
  const side = data.side === 'under' ? 'under' : 'over';
  if (!id || (type !== 'duel' && type !== 'seven' && type !== 'fetiche')) {
    throw new HttpError('invalid-argument', 'Pari invalide.');
  }
  if (amount < BET_MIN || amount > BET_MAX) {
    throw new HttpError('invalid-argument', 'Mise invalide.');
  }
  const pUid = await verifyIdToken(String(data.proposerToken || ''), env);
  const oUid = await verifyIdToken(String(data.opponentToken || ''), env);
  if (pUid === oUid) {
    throw new HttpError('invalid-argument', 'Choisis deux joueurs différents.');
  }

  await runTx(env, async (tx) => {
    const g = await tx.get(`localGames/${id}`);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (g.hostUid !== uid) {
      throw new HttpError('permission-denied', 'Seul le joueur principal peut créer un pari.');
    }
    if (g.settled === true || g.status !== 'playing') {
      throw new HttpError('failed-precondition', 'La partie est terminée.');
    }
    if (intOr(g.stake, 0) <= 0) {
      throw new HttpError('failed-precondition', 'Pas de pari dans une partie gratuite.');
    }
    if (type === 'fetiche' && g.game !== 'boubayah') {
      throw new HttpError('invalid-argument', 'Le défi Fétiche existe seulement au BOUBAYAH.');
    }
    const players = Array.isArray(g.uids) ? g.uids : [];
    if (!players.includes(pUid) || !players.includes(oUid)) {
      throw new HttpError('permission-denied', 'Ces joueurs ne sont pas dans la partie.');
    }
    const names = Array.isArray(g.names) ? g.names : [];
    const nameOf = (u) => String(names[players.indexOf(u)] || 'Joueur');

    const bets = await loadLocalBets(tx, id);
    if (bets.length >= BET_MAX_PER_ROOM) {
      throw new HttpError('failed-precondition', 'Trop de paris dans cette partie.');
    }
    const p = await tx.get(`users/${pUid}`);
    const o = await tx.get(`users/${oUid}`);
    if (balanceOf(p) < amount) {
      throw new HttpError('failed-precondition', `Solde insuffisant : ${nameOf(pUid)}`);
    }
    if (balanceOf(o) < amount) {
      throw new HttpError('failed-precondition', `Solde insuffisant : ${nameOf(oUid)}`);
    }

    const betId = newId();
    tx.write(`users/${pUid}`, { incr: { balance: -amount } });
    tx.write(`users/${oUid}`, { incr: { balance: -amount } });
    tx.write(localBetPath(id, betId), {
      create: true,
      set: {
        type,
        amount,
        prize: prizeOf(amount * 2, COMMISSION_LOCAL_PERCENT),
        side: type === 'seven' || type === 'fetiche' ? side : null,
        proposerUid: pUid,
        proposerName: nameOf(pUid),
        opponentUid: oUid,
        opponentName: nameOf(oUid),
        status: 'accepted',
      },
      serverTime: ['createdAt'],
    });
    tx.write(localBetIndexPath(id), {
      set: { n: bets.length + 1 },
      union: { ids: [betId] },
    });
  });
  return { ok: true };
}

/** Règle les paris d'une partie en présentiel. Scores alignés sur `players`.
 *  Score manquant, égalité ou 7 pile : mises remboursées. */
function settleLocalBets(tx, bets, players, scores, names, fscores = []) {
  const out = [];
  const nameOf = (u) => String(names[players.indexOf(u)] || 'Joueur');
  for (const { path, b } of bets) {
    if (b.status !== 'accepted') continue;
    const ps = scores[players.indexOf(b.proposerUid)];
    const os = scores[players.indexOf(b.opponentUid)];
    let winner = null;
    if (b.type === 'seven') {
      if (typeof ps === 'number' && ps !== 7) {
        winner = ps > 7 === (b.side !== 'under') ? b.proposerUid : b.opponentUid;
      }
    } else if (b.type === 'fetiche') {
      const fs = fscores[players.indexOf(b.proposerUid)];
      if (typeof fs === 'number' && fs !== 13) {
        winner = fs > 13 === (b.side !== 'under') ? b.proposerUid : b.opponentUid;
      }
    } else if (typeof ps === 'number' && typeof os === 'number' && ps !== os) {
      winner = ps > os ? b.proposerUid : b.opponentUid;
    }

    if (winner === null) {
      tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
      tx.write(`users/${b.opponentUid}`, { incr: { balance: b.amount } });
      tx.write(path, { set: { status: 'settled', result: 'refund' }, serverTime: ['closedAt'] });
    } else {
      tx.write(`users/${winner}`, { incr: { balance: b.prize } });
      // Les paris (Duel, Défi 7) comptent dans le total misé des deux joueurs.
      tx.write(`users/${b.proposerUid}`, { incr: { wagered: b.amount } });
      tx.write(`users/${b.opponentUid}`, { incr: { wagered: b.amount } });
      tx.write(path, {
        set: { status: 'settled', result: 'win', winnerUid: winner },
        serverTime: ['closedAt'],
      });
    }
    out.push({
      type: b.type,
      side: b.side || null,
      amount: b.amount,
      prize: b.prize,
      proposerName: nameOf(b.proposerUid),
      opponentName: nameOf(b.opponentUid),
      winnerName: winner === null ? null : nameOf(winner),
      result: winner === null ? 'refund' : 'win',
    });
  }
  return out;
}

// ======================================================================
// Tableau de bord administrateur (commissions, parties)
// ======================================================================
// Réservé aux comptes dont l'identifiant figure dans la variable ADMIN_UIDS.
// Lit les parties récentes (Ludo en ligne, Deux dés en ligne, présentiel) et
// (et Songô) renvoie une ligne par partie : l'appli calcule les totaux.

function adminIds(env) {
  return String(env.ADMIN_UIDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Dernières parties d'une collection (champs utiles seulement : plus léger). */

/** Ligne d'admin d'un pari Sports (P2P). */
function adminSportRow(d) {
  const amount = Math.max(0, intOr(d.amount, 0));
  const st = d.status;
  const matched = st === 'matched' || st === 'settled';
  return {
    id: d.id,
    kind: 'sports',
    mode: 'online',
    state: st === 'settled' ? 'done' : st === 'matched' ? 'playing' : st === 'open' ? 'waiting' : 'refund',
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : null,
    stake: amount,
    pot: matched ? amount * 2 : amount,
    players: matched ? 2 : 1,
    names: [d.proposerName, d.opponentName].filter((x) => x).map(String),
    commission: st === 'settled' ? Math.max(0, intOr(d.commission, 0)) : 0,
    prize: st === 'settled' ? Math.max(0, intOr(d.prize, 0)) : 0,
    betCommission: 0,
    referralPaid: 0,
    partnerPaid: 0,
    jackpot: 0,
  };
}

/** Ligne d'admin du règlement d'une formule de course (pari mutuel). */
function adminRaceRow(d) {
  const gross = Math.max(0, intOr(d.gross, 0));
  return {
    id: d.id,
    kind: 'courses',
    mode: 'online',
    state: 'done',
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : null,
    stake: gross,
    pot: gross,
    players: Math.max(0, intOr(d.winners, 0)),
    names: [String(d.formula || 'course')],
    commission: Math.max(0, intOr(d.commission, 0)),
    prize: Math.max(0, intOr(d.net, 0)),
    betCommission: 0,
    referralPaid: 0,
    partnerPaid: 0,
    jackpot: 0,
  };
}

async function recentDocs(env, collectionId, limit, extra = []) {
  const fields = [
    'createdAt', 'status', 'stake', 'pot', 'settled', 'jackpot', 'commission',
    'betCommission', 'referralPaid', 'partnerPaid', 'refunded', 'maxPlayers', 'players', 'names',
    'uids', 'game', ...extra,
  ];
  const res = await fsCall(env, 'runQuery', {
    structuredQuery: {
      from: [{ collectionId }],
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
      select: { fields: fields.map((f) => ({ fieldPath: f })) },
      limit,
    },
  });
  return (Array.isArray(res) ? res : [])
    .filter((r) => r.document)
    .map((r) => ({
      id: r.document.name.split('/').pop(),
      ...fieldsToObj(r.document.fields || {}),
    }));
}

/** Une partie => une ligne du tableau de bord. */
function adminRow(kind, mode, d) {
  const stake = Math.max(0, intOr(d.stake, 0));
  const pot = Math.max(0, intOr(d.pot, 0));
  const percent = mode === 'local' ? COMMISSION_LOCAL_PERCENT : COMMISSION_PERCENT;
  const settled = d.settled === true;
  const refunded = d.refunded === true;

  // Commission enregistrée à la fin de la partie ; sinon estimée (anciennes parties).
  let commission = 0;
  if (typeof d.commission === 'number') commission = d.commission;
  else if (settled && stake > 0 && pot > 0) commission = pot - prizeOf(pot, percent);

  const names =
    mode === 'local'
      ? (Array.isArray(d.names) ? d.names : []).map(String)
      : playersOf(d).map((p) => String((p && p.name) || '?'));
  const count =
    mode === 'local' ? (Array.isArray(d.uids) ? d.uids.length : names.length) : names.length;

  let state = 'playing';
  if (settled) state = refunded ? 'refund' : 'done';
  else if (d.review === true) state = 'review';
  else if (d.status === 'waiting') state = 'waiting';

  return {
    id: d.id,
    kind,
    mode,
    state,
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : null,
    stake,
    pot,
    players: count,
    names,
    reviewReason: typeof d.reviewReason === 'string' ? d.reviewReason : '',
    commission: refunded ? 0 : commission,
    prize: settled && !refunded ? Math.max(0, pot - commission) : 0,
    betCommission: Math.max(0, intOr(d.betCommission, 0)),
    referralPaid: Math.max(0, intOr(d.referralPaid, 0)),
    partnerPaid: Math.max(0, intOr(d.partnerPaid, 0)),
    jackpot: Math.max(0, intOr(d.jackpot, 0)),
  };
}

// ======================================================================
// ZONING : partenaires exclusifs par ville
// ======================================================================
// zones/{zoneId}              : { name, region, country, status: active|suspended, partnerUid, partnerName, rate, partnerSince }
// users/{uid}                 : country, region, city, quarter, zoneId, zoneAttached (rattaché à un partenaire),
//                               zoneBalance / zoneEarned / zonePaid / zoneHeld (partenaire), zonePartner
// player_attributions/{id}    : historique des rattachements
// partner_assignments/{id}    : historique des affectations ville <-> partenaire
// partner_commissions/{id}    : une commission par joueur et par opération (id déterministe = idempotence)
// partner_payouts/{id}        : demandes de paiement des partenaires
// city_change_requests/{id}   : demandes de changement de ville
// partner_audit_logs/{id}     : actions sensibles
// Règle : un joueur est rattaché seulement s'il s'inscrit dans une ville qui a déjà un partenaire actif,
// ou si l'administration le décide explicitement (aucune commission rétroactive).
// La commission du partenaire = ZONE rate % (15 % max) de la part de commission de chaque joueur.

const ZONE_MAX_RATE = 10; // commission du partenaire de zone : 10 %
const ZONE_PAYOUT_MIN = 5000; // retrait des commissions de zone : 5 000 FCFA minimum
const ZONE_PAYOUT_MIN_PLAYERS = 50; // ... et au moins 50 joueurs rattachés au partenaire
const CM_REGIONS = ['Adamaoua', 'Centre', 'Est', 'Extrême-Nord', 'Littoral', 'Nord', 'Nord-Ouest', 'Ouest', 'Sud', 'Sud-Ouest'];

function zoneClean(v, max = 40) {
  return String(v == null ? '' : v).trim().replace(/\s+/g, ' ').slice(0, max);
}

function zoneKey(city) {
  return promoKey(city);
}

function zoneAudit(tx, uid, action, info = {}) {
  tx.write(`partner_audit_logs/${newId()}`, {
    create: true,
    set: { by: uid, action, ...info },
    serverTime: ['createdAt'],
  });
}

async function zoneCount(env, zid, attachedOnly = false) {
  try {
    const filters = [{ fieldFilter: { field: { fieldPath: 'zoneId' }, op: 'EQUAL', value: { stringValue: zid } } }];
    if (attachedOnly) filters.push({ fieldFilter: { field: { fieldPath: 'zoneAttached' }, op: 'EQUAL', value: { booleanValue: true } } });
    const r = await fsCall(env, 'runAggregationQuery', {
      structuredAggregationQuery: {
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: filters.length === 1 ? filters[0] : { compositeFilter: { op: 'AND', filters } },
        },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    return Number(r[0].result.aggregateFields.n.integerValue) || 0;
  } catch (_) {
    return 0;
  }
}

/** Commission des partenaires exclusifs : ZONE rate % (15 % max) de la part de commission de chaque
 *  joueur rattaché à une zone active. Idempotent (un document par joueur et par opération).
 *  Renvoie le total versé aux partenaires. */
async function zonePayout(tx, list, share, info = {}) {
  if (!(share > 0) || list.length === 0) return 0;
  const users = await tx.getMany(list.map((u) => `users/${u}`));
  const zids = [...new Set(users.filter((d) => d && d.zoneAttached === true && d.zoneId).map((d) => d.zoneId))];
  if (zids.length === 0) return 0;
  const zdocs = await tx.getMany(zids.map((z) => `zones/${z}`));
  const zones = new Map(zids.map((z, i) => [z, zdocs[i]]));
  const cands = [];
  list.forEach((u, i) => {
    const d = users[i];
    if (!d || d.zoneAttached !== true || !d.zoneId) return;
    const z = zones.get(d.zoneId);
    if (!z || z.status !== 'active' || !z.partnerUid || z.partnerUid === u) return;
    const rate = Math.min(ZONE_MAX_RATE, Math.max(0, intOr(z.rate, ZONE_MAX_RATE)));
    const amount = Math.floor((share * rate) / 100);
    if (!(amount > 0)) return;
    const cid = `${String(info.mode || 'g')}_${String(info.gameId || 'x')}_${String(info.ref || '0')}_${u}`.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 140);
    cands.push({ u, d, z, rate, amount, cid, zid: d.zoneId });
  });
  if (cands.length === 0) return 0;
  const seen = await tx.getMany(cands.map((c) => `partner_commissions/${c.cid}`));
  const gains = new Map();
  let total = 0;
  cands.forEach((c, i) => {
    if (seen[i]) return; // déjà comptabilisée : jamais de doublon
    tx.write(`partner_commissions/${c.cid}`, {
      create: true,
      set: {
        partnerUid: c.z.partnerUid,
        playerUid: c.u,
        playerName: tournName(c.d),
        zoneId: c.zid,
        city: String(c.z.name || ''),
        game: String(info.mode || ''),
        gameId: String(info.gameId || ''),
        base: Math.floor(share),
        rate: c.rate,
        amount: c.amount,
        status: 'validated',
      },
      serverTime: ['createdAt'],
    });
    gains.set(c.z.partnerUid, (gains.get(c.z.partnerUid) || 0) + c.amount);
    total += c.amount;
  });
  for (const [p, g] of gains) tx.write(`users/${p}`, { incr: { zoneBalance: g, zoneEarned: g } });
  return total;
}

// --- Joueur ------------------------------------------------------------

/** Profil territorial du joueur connecté + indicateur « compte partenaire ». */
async function zoneMe({ uid, env }) {
  const u = (await readDoc(env, `users/${uid}`)) || {};
  const mine = await queryDocs(env, 'zones', eqFilter('partnerUid', uid), 30);
  const reqs = await queryDocs(env, 'city_change_requests', eqFilter('uid', uid), 10);
  const pending = reqs.find((r) => r.status === 'pending');
  return {
    hasCity: !!u.city,
    city: String(u.city || ''),
    region: String(u.region || ''),
    quarter: String(u.quarter || ''),
    attached: u.zoneAttached === true,
    isPartner: mine.length > 0 || u.zonePartner === true,
    pendingChange: pending ? { city: pending.toCity, region: pending.toRegion } : null,
    regions: CM_REGIONS,
  };
}

/** Première déclaration de ville (obligatoire). La ville ne peut plus être changée librement. */
async function playerSetCity({ uid, data, env }) {
  const region = zoneClean(data.region);
  const city = zoneClean(data.city);
  const quarter = zoneClean(data.quarter);
  if (!CM_REGIONS.includes(region)) throw new HttpError('invalid-argument', 'Choisis ta région.');
  const zid = zoneKey(city);
  if (!zid) throw new HttpError('invalid-argument', 'Indique ta ville.');
  return runTx(env, async (tx) => {
    const [me, z] = await tx.getMany([`users/${uid}`, `zones/${zid}`]);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (me.city) {
      throw new HttpError('failed-precondition', 'Ta ville est déjà enregistrée. Fais une demande de changement de ville.');
    }
    const attached = !!(z && z.status === 'active' && z.partnerUid && z.partnerUid !== uid);
    tx.write(`users/${uid}`, {
      set: { country: 'Cameroun', region, city, quarter, zoneId: zid, zoneAttached: attached },
      serverTime: ['citySetAt'],
    });
    tx.write(`player_attributions/${newId()}`, {
      create: true,
      set: { uid, zoneId: zid, city, region, partnerUid: attached ? z.partnerUid : '', reason: 'inscription', managed: attached ? 'partenaire' : 'centrale' },
      serverTime: ['createdAt'],
    });
    return { ok: true, city, region, attached };
  });
}

/** Demande de changement de ville (examinée par l'administration). */
async function cityChangeRequest({ uid, data, env }) {
  const region = zoneClean(data.region);
  const city = zoneClean(data.city);
  const reason = zoneClean(data.reason, 200);
  if (!CM_REGIONS.includes(region)) throw new HttpError('invalid-argument', 'Choisis la région.');
  if (!zoneKey(city)) throw new HttpError('invalid-argument', 'Indique la nouvelle ville.');
  const me = await readDoc(env, `users/${uid}`);
  if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
  if (!me.city) throw new HttpError('failed-precondition', 'Enregistre d\'abord ta ville.');
  if (zoneKey(me.city) === zoneKey(city)) throw new HttpError('invalid-argument', 'C\'est déjà ta ville.');
  const old = await queryDocs(env, 'city_change_requests', eqFilter('uid', uid), 20);
  if (old.some((r) => r.status === 'pending')) throw new HttpError('failed-precondition', 'Une demande est déjà en cours.');
  const id = newId();
  await runTx(env, async (tx) => {
    tx.write(`city_change_requests/${id}`, {
      create: true,
      set: { uid, name: tournName(me), fromCity: String(me.city), fromRegion: String(me.region || ''), toCity: city, toRegion: region, reason, status: 'pending' },
      serverTime: ['createdAt'],
    });
  });
  return { ok: true, id };
}

// --- Partenaire ---------------------------------------------------------

/** MON ESPACE PARTENAIRE : uniquement les zones dont l'appelant est le partenaire. */
async function zoneMy({ uid, env }) {
  const zones = await queryDocs(env, 'zones', eqFilter('partnerUid', uid), 30);
  const me = (await readDoc(env, `users/${uid}`)) || {};
  const players = [];
  for (const z of zones) {
    const list = await queryDocs(env, 'users', eqFilter('zoneId', z.id), 300);
    for (const p of list) {
      if (p.zoneAttached !== true || p.id === uid) continue;
      players.push({
        id: p.id,
        name: tournName(p),
        city: String(z.name || p.city || ''),
        quarter: String(p.quarter || ''),
        createdAt: typeof p.createdAt === 'string' ? p.createdAt : '',
        wagered: Math.max(0, intOr(p.wagered, 0)),
      });
    }
  }
  const comm = await queryDocs(env, 'partner_commissions', eqFilter('partnerUid', uid), 500);
  const rows = comm
    .map((c) => ({
      id: c.id,
      playerUid: String(c.playerUid || ''),
      playerName: String(c.playerName || ''),
      city: String(c.city || ''),
      game: String(c.game || ''),
      base: intOr(c.base, 0),
      rate: intOr(c.rate, 0),
      amount: intOr(c.amount, 0),
      status: String(c.status || ''),
      createdAt: typeof c.createdAt === 'string' ? c.createdAt : '',
    }))
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  const payouts = await queryDocs(env, 'partner_payouts', eqFilter('partnerUid', uid), 30);
  return {
    zones: zones.map((z) => ({ id: z.id, name: String(z.name || ''), region: String(z.region || ''), status: String(z.status || ''), rate: intOr(z.rate, ZONE_MAX_RATE) })),
    players,
    commissions: rows,
    available: Math.max(0, intOr(me.zoneBalance, 0)),
    held: Math.max(0, intOr(me.zoneHeld, 0)),
    paid: Math.max(0, intOr(me.zonePaid, 0)),
    earned: Math.max(0, intOr(me.zoneEarned, 0)),
    min: ZONE_PAYOUT_MIN,
    minPlayers: ZONE_PAYOUT_MIN_PLAYERS,
    payouts: payouts
      .map((p) => ({ id: p.id, amount: intOr(p.amount, 0), status: String(p.status || ''), createdAt: typeof p.createdAt === 'string' ? p.createdAt : '' }))
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
  };
}

/** Le partenaire demande le paiement de sa commission disponible (validé ensuite par l'administration). */
async function zonePayoutRequest({ uid, env }) {
  const zones = await queryDocs(env, 'zones', eqFilter('partnerUid', uid), 5);
  const attachedN = (await Promise.all(zones.map((z) => zoneCount(env, z.id, true)))).reduce((x, y) => x + y, 0);
  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (zones.length === 0 && me.zonePartner !== true) throw new HttpError('permission-denied', 'Réservé aux partenaires.');
    const amount = Math.max(0, intOr(me.zoneBalance, 0));
    if (attachedN < ZONE_PAYOUT_MIN_PLAYERS) {
      throw new HttpError('failed-precondition', `Paiement possible à partir de ${ZONE_PAYOUT_MIN_PLAYERS} joueurs rattachés (tu en as ${attachedN}).`);
    }
    if (amount < ZONE_PAYOUT_MIN) {
      throw new HttpError('failed-precondition', `Demande possible à partir de ${ZONE_PAYOUT_MIN} FCFA de commission.`);
    }
    const id = newId();
    tx.write(`users/${uid}`, { incr: { zoneBalance: -amount, zoneHeld: amount } });
    tx.write(`partner_payouts/${id}`, {
      create: true,
      set: { partnerUid: uid, name: tournName(me), amount, status: 'pending' },
      serverTime: ['createdAt'],
    });
    return { ok: true, id, amount };
  });
}

// --- Administration -------------------------------------------------------

async function adminZones({ uid, env }) {
  requireAdmin(uid, env);
  const zones = await queryDocs(env, 'zones', undefined, 300);
  const slice = zones.slice(0, 80);
  const counts = await Promise.all(slice.map((z) => zoneCount(env, z.id)));
  const att = await Promise.all(slice.map((z) => zoneCount(env, z.id, true)));
  const reqs = await queryDocs(env, 'city_change_requests', eqFilter('status', 'pending'), 100);
  const pays = await queryDocs(env, 'partner_payouts', eqFilter('status', 'pending'), 100);
  return {
    regions: CM_REGIONS,
    maxRate: ZONE_MAX_RATE,
    zones: slice
      .map((z, i) => ({
        id: z.id,
        name: String(z.name || ''),
        region: String(z.region || ''),
        status: String(z.status || 'active'),
        partnerUid: String(z.partnerUid || ''),
        partnerName: String(z.partnerName || ''),
        rate: Math.min(ZONE_MAX_RATE, intOr(z.rate, ZONE_MAX_RATE)),
        players: counts[i],
        attached: att[i],
      }))
      .sort((a, b) => a.region.localeCompare(b.region) || a.name.localeCompare(b.name)),
    cityRequests: reqs.map((r) => ({
      id: r.id,
      name: String(r.name || ''),
      from: String(r.fromCity || ''),
      to: String(r.toCity || ''),
      toRegion: String(r.toRegion || ''),
      reason: String(r.reason || ''),
      createdAt: typeof r.createdAt === 'string' ? r.createdAt : '',
    })),
    payouts: pays.map((p) => ({
      id: p.id,
      name: String(p.name || ''),
      amount: intOr(p.amount, 0),
      createdAt: typeof p.createdAt === 'string' ? p.createdAt : '',
    })),
  };
}

/** Ajoute (ou renomme) une ville. */
async function adminZoneSave({ uid, data, env }) {
  requireAdmin(uid, env);
  const name = zoneClean(data.name);
  const region = zoneClean(data.region);
  if (!CM_REGIONS.includes(region)) throw new HttpError('invalid-argument', 'Région invalide.');
  const zid = zoneKey(name);
  if (!zid) throw new HttpError('invalid-argument', 'Nom de ville invalide.');
  return runTx(env, async (tx) => {
    const z = await tx.get(`zones/${zid}`);
    if (z) {
      tx.write(`zones/${zid}`, { set: { name, region } });
    } else {
      tx.write(`zones/${zid}`, {
        create: true,
        set: { name, region, country: 'Cameroun', status: 'active', partnerUid: '', partnerName: '', rate: ZONE_MAX_RATE },
        serverTime: ['createdAt'],
      });
    }
    zoneAudit(tx, uid, z ? 'zone_update' : 'zone_create', { zoneId: zid });
    return { ok: true, id: zid };
  });
}

/** Affecte (ou remplace) le partenaire exclusif d'une ville. Une ville = un seul partenaire actif. */
async function adminZoneAssign({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  const code = promoKey(data.code);
  if (!zid || !code) throw new HttpError('invalid-argument', 'Ville ou code promo invalide.');
  const rate = Math.min(ZONE_MAX_RATE, Math.max(1, intOr(data.rate, ZONE_MAX_RATE)));
  return runTx(env, async (tx) => {
    const [z, owner] = await tx.getMany([`zones/${zid}`, `promoCodes/${code}`]);
    if (!z) throw new HttpError('not-found', 'Ville inconnue.');
    if (z.status !== 'active') throw new HttpError('failed-precondition', 'Cette zone est suspendue.');
    if (!owner || typeof owner.uid !== 'string') throw new HttpError('not-found', 'Aucun joueur avec ce code promo.');
    const p = await tx.get(`users/${owner.uid}`);
    if (!p) throw new HttpError('not-found', 'Compte partenaire introuvable.');
    const prev = String(z.partnerUid || '');
    tx.write(`zones/${zid}`, {
      set: { partnerUid: owner.uid, partnerName: tournName(p), rate },
      ...(prev !== owner.uid ? { serverTime: ['partnerSince'] } : {}),
    });
    tx.write(`users/${owner.uid}`, { set: { zonePartner: true } });
    tx.write(`partner_assignments/${newId()}`, {
      create: true,
      set: { zoneId: zid, partnerUid: owner.uid, previousPartnerUid: prev, rate, by: uid },
      serverTime: ['createdAt'],
    });
    zoneAudit(tx, uid, prev && prev !== owner.uid ? 'partner_replaced' : 'partner_assigned', { zoneId: zid, partnerUid: owner.uid, rate });
    return { ok: true, partnerUid: owner.uid, partnerName: tournName(p), rate };
  });
}

/** Retire le partenaire d'une ville (partenaire suspendu ou résilié) : l'historique est conservé. */
async function adminZoneRelease({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  return runTx(env, async (tx) => {
    const z = await tx.get(`zones/${zid}`);
    if (!z) throw new HttpError('not-found', 'Ville inconnue.');
    const prev = String(z.partnerUid || '');
    tx.write(`zones/${zid}`, { set: { partnerUid: '', partnerName: '' } });
    tx.write(`partner_assignments/${newId()}`, {
      create: true,
      set: { zoneId: zid, partnerUid: '', previousPartnerUid: prev, rate: 0, by: uid },
      serverTime: ['createdAt'],
    });
    zoneAudit(tx, uid, 'partner_released', { zoneId: zid, partnerUid: prev });
    return { ok: true };
  });
}

/** Suspend ou réactive une zone (aucune commission pendant la suspension). */
async function adminZoneStatus({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  const status = data.status === 'suspended' ? 'suspended' : 'active';
  return runTx(env, async (tx) => {
    const z = await tx.get(`zones/${zid}`);
    if (!z) throw new HttpError('not-found', 'Ville inconnue.');
    tx.write(`zones/${zid}`, { set: { status } });
    zoneAudit(tx, uid, status === 'suspended' ? 'zone_suspended' : 'zone_reactivated', { zoneId: zid });
    return { ok: true, status };
  });
}

/** Décision explicite : rattache au partenaire actuel les joueurs déjà inscrits dans la ville
 *  (par lots de 100). Aucune commission rétroactive n'est créée. */
async function adminZoneAttach({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  const z = await readDoc(env, `zones/${zid}`);
  if (!z || !z.partnerUid || z.status !== 'active') throw new HttpError('failed-precondition', 'La ville doit avoir un partenaire actif.');
  const list = (await queryDocs(env, 'users', eqFilter('zoneId', zid), 400)).filter((p) => p.zoneAttached !== true && p.id !== z.partnerUid);
  const batch = list.slice(0, 100);
  if (batch.length) {
    await runTx(env, async (tx) => {
      for (const p of batch) {
        tx.write(`users/${p.id}`, { set: { zoneAttached: true } });
        tx.write(`player_attributions/${newId()}`, {
          create: true,
          set: { uid: p.id, zoneId: zid, city: String(z.name || ''), region: String(z.region || ''), partnerUid: z.partnerUid, reason: 'decision_admin', managed: 'partenaire' },
          serverTime: ['createdAt'],
        });
      }
      zoneAudit(tx, uid, 'players_attached', { zoneId: zid, count: batch.length });
    });
  }
  return { ok: true, attached: batch.length, remaining: Math.max(0, list.length - batch.length) };
}

async function adminZonePlayers({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  const list = await queryDocs(env, 'users', eqFilter('zoneId', zid), 300);
  return {
    players: list.map((p) => ({
      id: p.id,
      name: tournName(p),
      quarter: String(p.quarter || ''),
      attached: p.zoneAttached === true,
      wagered: Math.max(0, intOr(p.wagered, 0)),
    })),
  };
}

/** Commissions versées au partenaire d'une zone : total, nombre, par jeu, et dernières lignes. */
async function adminZoneCommissions({ uid, data, env }) {
  requireAdmin(uid, env);
  const zid = zoneKey(zoneClean(data.zoneId));
  const list = await queryDocs(env, 'partner_commissions', eqFilter('zoneId', zid), 500);
  let total = 0;
  const byGame = {};
  for (const c of list) {
    const amt = Math.max(0, intOr(c.amount, 0));
    total += amt;
    const g = String(c.game || '?');
    byGame[g] = (byGame[g] || 0) + amt;
  }
  const rows = list
    .map((c) => ({
      player: String(c.playerName || ''),
      game: String(c.game || ''),
      base: intOr(c.base, 0),
      rate: intOr(c.rate, 0),
      amount: Math.max(0, intOr(c.amount, 0)),
      at: typeof c.createdAt === 'string' ? c.createdAt : '',
    }))
    .sort((a, b) => String(b.at).localeCompare(String(a.at)))
    .slice(0, 60);
  return { total, count: list.length, byGame, rows, partnerUid: list[0] ? String(list[0].partnerUid || '') : '' };
}

/** Accepte ou refuse un changement de ville. Acceptation : nouveau rattachement dès maintenant,
 *  les commissions passées restent à l'ancien partenaire. */
async function adminCityChangeDecide({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  if (!id) throw new HttpError('invalid-argument', 'Demande inconnue.');
  const accept = data.accept === true;
  return runTx(env, async (tx) => {
    const r = await tx.get(`city_change_requests/${id}`);
    if (!r || r.status !== 'pending') throw new HttpError('failed-precondition', 'Demande déjà traitée.');
    if (!accept) {
      tx.write(`city_change_requests/${id}`, { set: { status: 'refused', by: uid }, serverTime: ['closedAt'] });
      zoneAudit(tx, uid, 'city_change_refused', { requestId: id, playerUid: r.uid });
      return { ok: true, status: 'refused' };
    }
    const zid = zoneKey(r.toCity);
    const z = await tx.get(`zones/${zid}`);
    const attached = !!(z && z.status === 'active' && z.partnerUid && z.partnerUid !== r.uid);
    tx.write(`users/${r.uid}`, {
      set: { city: String(r.toCity), region: String(r.toRegion), zoneId: zid, zoneAttached: attached },
      serverTime: ['citySetAt'],
    });
    tx.write(`player_attributions/${newId()}`, {
      create: true,
      set: { uid: r.uid, zoneId: zid, city: String(r.toCity), region: String(r.toRegion), partnerUid: attached ? z.partnerUid : '', reason: 'changement_ville', managed: attached ? 'partenaire' : 'centrale', fromCity: String(r.fromCity || '') },
      serverTime: ['createdAt'],
    });
    tx.write(`city_change_requests/${id}`, { set: { status: 'accepted', by: uid }, serverTime: ['closedAt'] });
    zoneAudit(tx, uid, 'city_change_accepted', { requestId: id, playerUid: r.uid, zoneId: zid });
    return { ok: true, status: 'accepted' };
  });
}

/** Valide ou refuse une demande de paiement de commission d'un partenaire. */
async function adminZonePayoutDecide({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  if (!id) throw new HttpError('invalid-argument', 'Demande inconnue.');
  const accept = data.accept === true;
  return runTx(env, async (tx) => {
    const p = await tx.get(`partner_payouts/${id}`);
    if (!p || p.status !== 'pending') throw new HttpError('failed-precondition', 'Demande déjà traitée.');
    const amount = Math.max(0, intOr(p.amount, 0));
    if (accept) {
      tx.write(`users/${p.partnerUid}`, { incr: { balance: amount, zoneHeld: -amount, zonePaid: amount } });
      tx.write(`partner_payouts/${id}`, { set: { status: 'paid', by: uid }, serverTime: ['closedAt'] });
    } else {
      tx.write(`users/${p.partnerUid}`, { incr: { zoneBalance: amount, zoneHeld: -amount } });
      tx.write(`partner_payouts/${id}`, { set: { status: 'refused', by: uid }, serverTime: ['closedAt'] });
    }
    zoneAudit(tx, uid, accept ? 'payout_paid' : 'payout_refused', { payoutId: id, partnerUid: p.partnerUid, amount });
    return { ok: true, status: accept ? 'paid' : 'refused' };
  });
}

/** Administrateur : retrouve une partie par son identifiant (début de l'id,
 *  au moins 4 caractères) ou par le code de la salle de cartes. */
async function adminFindGame({ uid, data, env }) {
  requireAdmin(uid, env);
  const q = String(data.q || '').trim();
  if (q.length < 4 || q.length > 40 || /[\/\s]/.test(q)) {
    throw new HttpError('invalid-argument', 'Saisis au moins 4 caractères de l\'identifiant.');
  }
  await accessToken(env);
  const cols = ['games', 'deuxdes', 'songo', 'damier', 'pileface', 'cards', 'localGames'];
  const found = new Map();
  const add = (col, d) => {
    if (!d || !d.id || found.has(d.id)) return;
    let kind = col === 'games' ? 'ludo' : col;
    let mode = 'online';
    if (col === 'cards') kind = ['boubayah', 'fapfap', 'anticote', 'tchek'].includes(d.game) ? d.game : 'tiah';
    if (col === 'localGames') {
      mode = 'local';
      kind = ['deuxdes', 'ludo', 'songo', 'damier', 'pileface', 'tiah', 'boubayah'].includes(d.game) ? d.game : 'unknown';
    }
    found.set(d.id, adminRow(kind, mode, d));
  };
  await Promise.all(
    cols.map(async (col) => {
      try {
        const lo = docName(env, `${col}/${q}`);
        const hi = docName(env, `${col}/${q}\uf8ff`);
        const res = await fsCall(env, 'runQuery', {
          structuredQuery: {
            from: [{ collectionId: col }],
            where: {
              compositeFilter: {
                op: 'AND',
                filters: [
                  { fieldFilter: { field: { fieldPath: '__name__' }, op: 'GREATER_THAN_OR_EQUAL', value: { referenceValue: lo } } },
                  { fieldFilter: { field: { fieldPath: '__name__' }, op: 'LESS_THAN_OR_EQUAL', value: { referenceValue: hi } } },
                ],
              },
            },
            limit: 5,
          },
        });
        for (const r of Array.isArray(res) ? res : []) {
          if (r.document) add(col, { id: r.document.name.split('/').pop(), ...fieldsToObj(r.document.fields || {}) });
        }
      } catch (_) {}
    }),
  );
  try {
    for (const d of await queryDocs(env, 'cards', eqFilter('code', q.toUpperCase()), 5)) add('cards', d);
  } catch (_) {}
  return { rows: [...found.values()].slice(0, 20) };
}

/** Administrateur : dernières recharges (Campay, manuelles, International) pour la cloche de l'appli. */
async function adminRechargeFeed({ uid, env }) {
  requireAdmin(uid, env);
  await accessToken(env);
  const extra = ['uid', 'name', 'amount', 'operator'];
  const [camp, man, seb] = await Promise.all([
    recentDocs(env, 'deposits', 6, extra).catch(() => []),
    recentDocs(env, 'manualDeposits', 6, extra).catch(() => []),
    recentDocs(env, 'sebpayDeposits', 6, extra).catch(() => []),
  ]);
  const row = (src, d) => ({
    id: d.id,
    src,
    amount: Math.max(0, intOr(d.amount, 0)),
    name: String(d.name || ''),
    status: String(d.status || ''),
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : '',
  });
  const rows = [
    ...camp.map((d) => row('campay', d)),
    ...man.map((d) => row('manuel', d)),
    ...seb.map((d) => row('international', d)),
  ]
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, 25);
  return { rows };
}

async function adminStats({ uid, data, env }) {
  if (!adminIds(env).includes(uid)) {
    throw new HttpError(
      'permission-denied',
      `Accès réservé à l'administrateur. Ton identifiant : ${uid}`,
    );
  }
  const limit = Math.min(500, Math.max(20, intOr(data.limit, 150)));
  await accessToken(env); // un seul jeton pour les 4 requêtes parallèles

  const [ludo, deux, songo, damier, local, pile, cartes, sportB, raceS] = await Promise.all([
    recentDocs(env, 'games', limit),
    recentDocs(env, 'deuxdes', limit),
    recentDocs(env, 'songo', limit),
    recentDocs(env, 'damier', limit),
    recentDocs(env, 'localGames', limit),
    recentDocs(env, 'pileface', limit).catch(() => []),
    recentDocs(env, 'cards', limit).catch(() => []),
    recentDocs(env, 'sportBets', limit, ['amount', 'proposerName', 'opponentName', 'prize']).catch(() => []),
    recentDocs(env, 'raceSettle', limit, ['gross', 'formula', 'winners', 'net']).catch(() => []),
  ]);

  const rows = [
    ...ludo.map((d) => adminRow('ludo', 'online', d)),
    ...deux.map((d) => adminRow('deuxdes', 'online', d)),
    ...songo.map((d) => adminRow('songo', 'online', d)),
    ...damier.map((d) => adminRow('damier', 'online', d)),
    ...pile.map((d) => adminRow('pileface', 'online', d)),
    ...cartes.map((d) => adminRow(d.game === 'boubayah' || d.game === 'fapfap' || d.game === 'anticote' || d.game === 'tchek' ? d.game : 'tiah', 'online', d)),
    ...sportB.map((d) => adminSportRow(d)),
    ...raceS.map((d) => adminRaceRow(d)),
    ...local.map((d) =>
      adminRow(
        d.game === 'deuxdes' ? 'deuxdes' : d.game === 'ludo' ? 'ludo' : d.game === 'songo' ? 'songo' : d.game === 'damier' ? 'damier' : d.game === 'pileface' ? 'pileface' : d.game === 'tiah' ? 'tiah' : d.game === 'boubayah' ? 'boubayah' : 'unknown',
        'local',
        d,
      ),
    ),
  ].sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

  // Jackpot actuel
  let pool = 0;
  try {
    const jr = await fsCall(env, 'batchGet', { documents: [docName(env, 'app/jackpot')] });
    const f = Array.isArray(jr) && jr[0] && jr[0].found;
    if (f) pool = intOr(fieldsToObj(f.fields || {}).pool, 0);
  } catch (_) {}

  // Commissions de Katika : caisse commune, visible par tous les administrateurs.
  const adminList = adminIds(env);
  const myIdx = adminList.indexOf(uid);
  let house = { available: 0, earned: 0, withdrawn: 0, totalEarned: 0 };
  try {
    const hr = await fsCall(env, 'batchGet', { documents: [docName(env, HOUSE_PATH)] });
    const hf = Array.isArray(hr) && hr[0] && hr[0].found;
    if (hf) {
      const h = fieldsToObj(hf.fields || {});
      const avail = houseTotal(h);
      const wd = Math.max(0, intOr(h.withdrawn, 0));
      house = {
        available: avail,
        earned: avail + wd,
        withdrawn: wd,
        totalEarned: Math.max(0, intOr(h.earned, 0)),
      };
    }
  } catch (_) {}

  // Nombre de comptes joueurs
  let users = null;
  try {
    const r = await fsCall(env, 'runAggregationQuery', {
      structuredAggregationQuery: {
        structuredQuery: { from: [{ collectionId: 'users' }] },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    users = Number(r[0].result.aggregateFields.n.integerValue);
  } catch (_) {}

  return {
    rows,
    pool,
    users,
    limit,
    fetched: { ludo: ludo.length, deuxdes: deux.length, songo: songo.length, damier: damier.length, local: local.length, pileface: pile.length, cards: cartes.length, sports: sportB.length, courses: raceS.length },
    jackpotPercent: JACKPOT_PERCENT,
    referralPercent: REFERRAL_PERCENT,
    house: {
      ...house,
      sharePercent: 100,
      min: HOUSE_WITHDRAW_MIN,
      canWithdraw: myIdx >= 0 && house.available >= HOUSE_WITHDRAW_MIN,
    },
  };
}

/** Administrateur : transfère toute la caisse des commissions de Katika vers
 *  son compte principal (jetons). Possible quand elle atteint HOUSE_WITHDRAW_MIN. */
async function adminHouseWithdraw({ uid, env }) {
  const ids = adminIds(env);
  if (!ids.includes(uid)) {
    throw new HttpError('permission-denied', "Accès réservé à l'administrateur.");
  }
  return runTx(env, async (tx) => {
    const h = await tx.get(HOUSE_PATH);
    const amount = houseTotal(h);
    if (amount < HOUSE_WITHDRAW_MIN) {
      throw new HttpError(
        'failed-precondition',
        `Retrait possible à partir de ${HOUSE_WITHDRAW_MIN} FCFA de commissions.`,
      );
    }
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    tx.write(`users/${uid}`, { incr: { balance: amount } });
    tx.write(HOUSE_PATH, {
      set: {
        bal0: 0,
        bal1: 0,
        balance: 0,
        withdrawn: Math.max(0, intOr(h.withdrawn, 0)) + amount,
        ['withdrawn' + (ids.indexOf(uid) === 1 ? '1' : '0')]:
          Math.max(0, intOr(h['withdrawn' + (ids.indexOf(uid) === 1 ? '1' : '0')], 0)) + amount,
      },
    });
    return { amount, balance: balanceOf(me) + amount };
  });
}

// ======================================================================
// Dépôts Mobile Money via Campay
// ======================================================================
// deposits/{id} : { uid, amount, phone, status, campayRef, tokens, operator }
//   status : pending -> credited | failed | mismatch
// Variables : CAMPAY_BASE_URL, CAMPAY_USERNAME, CAMPAY_PASSWORD, CAMPAY_WEBHOOK_KEY
// Le portefeuille n'est crédité qu'après avoir redemandé le statut à Campay,
// et une seule fois par dépôt (transaction Firestore).

const TOKENS_PER_XAF = 1; // 1 FCFA = 1 jeton

// --- Règle « première recharge » ----------------------------------------------------------
// Le montant de la 1re recharge d'un compte doit être entièrement misé avant tout retrait
// (ou transfert). Les recharges suivantes ne sont pas concernées.
//   users/{uid}.firstDep      : montant de la 1re recharge (0 = compte ancien, déjà rechargé : exempté)
//   users/{uid}.firstDepBase  : total misé (wagered) au moment de cette 1re recharge
/** Avant le crédit : vrai si ce compte n'a encore jamais été rechargé (aucune recharge créditée). */
async function isFirstDeposit(env, uid) {
  const u = await readDoc(env, `users/${uid}`);
  if (!u || u.firstDep !== undefined) return false;
  for (const col of ['deposits', 'manualDeposits', 'sebpayDeposits']) {
    const list = await queryDocs(env, col, eqFilter('uid', uid), 20);
    if (list.some((x) => x.status === 'credited')) return false;
  }
  return true;
}
/** Dans la transaction de crédit : enregistre la 1re recharge (ou marque un ancien compte comme exempté). */
async function markFirstDeposit(tx, uid, amount, isFirst) {
  const u = await tx.get(`users/${uid}`);
  if (!u || u.firstDep !== undefined) return;
  tx.write(`users/${uid}`, { set: { firstDep: isFirst ? Math.max(0, Math.floor(amount)) : 0, firstDepBase: intOr(u.wagered, 0) } });
}
/** Reste à miser sur la 1re recharge (0 = aucune contrainte). */
function wagerLeft(u) {
  const need = intOr(u && u.firstDep, 0);
  if (need <= 0) return 0;
  return Math.max(0, need - Math.max(0, intOr(u.wagered, 0) - intOr(u.firstDepBase, 0)));
}
function assertWagerDone(u) {
  const left = wagerLeft(u);
  if (left > 0) {
    throw new HttpError(
      'failed-precondition',
      `Retrait impossible pour l'instant : tu dois d'abord miser en entier le montant de ta première recharge (${intOr(u.firstDep, 0)} FCFA). Il te reste ${left} FCFA à miser.`,
    );
  }
}
const DEPOSIT_MIN = 25; // le mode test de Campay (demo) accepte 25 FCFA
const DEPOSIT_MAX = 250000;

let campayTokenCache = { value: null, exp: 0 };

function campayBase(env) {
  const b = String(env.CAMPAY_BASE_URL || '').replace(/\/+$/, '');
  if (!b) throw new HttpError('internal', 'Campay non configuré.');
  return b;
}

async function campayToken(env) {
  const now = Date.now();
  if (campayTokenCache.value && campayTokenCache.exp - 60000 > now) {
    return campayTokenCache.value;
  }
  const res = await fetch(`${campayBase(env)}/api/token/`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: env.CAMPAY_USERNAME, password: env.CAMPAY_PASSWORD }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.token) {
    console.error('Campay token', res.status, JSON.stringify(j));
    throw new HttpError('internal', 'Paiement indisponible.');
  }
  campayTokenCache = { value: j.token, exp: now + (Number(j.expires_in) || 3000) * 1000 };
  return j.token;
}

async function campayCall(env, method, path, body) {
  const res = await fetch(`${campayBase(env)}${path}`, {
    method,
    headers: {
      authorization: `Token ${await campayToken(env)}`,
      'content-type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, j };
}

function normPhone(p) {
  let s = String(p || '').replace(/\D/g, '');
  if (s.length === 9) s = '237' + s;
  return /^2376\d{8}$/.test(s) ? s : '';
}

async function hs256Verify(token, secret) {
  const parts = String(token).split('.');
  if (parts.length !== 3 || !secret) return false;
  try {
    const key = await crypto.subtle.importKey(
      'raw',
      te.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    return await crypto.subtle.verify(
      'HMAC',
      key,
      b64urlDecode(parts[2]),
      te.encode(`${parts[0]}.${parts[1]}`),
    );
  } catch (_) {
    return false;
  }
}

/** Demande un dépôt : le joueur reçoit la demande de paiement sur son téléphone. */
async function campayDeposit({ uid, data, env }) {
  if (!CAMPAY_ENABLED) {
    throw new HttpError('failed-precondition', 'La recharge Campay est désactivée. Utilise le code marchand Orange Money.');
  }
  const amount = intOr(data.amount, -1);
  if (amount < DEPOSIT_MIN || amount > DEPOSIT_MAX) {
    throw new HttpError('invalid-argument', `Montant entre ${DEPOSIT_MIN} et ${DEPOSIT_MAX} FCFA.`);
  }
  const phone = normPhone(data.phone);
  if (!phone) throw new HttpError('invalid-argument', 'Numéro MTN ou Orange invalide.');

  const id = newId();
  await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    tx.write(`deposits/${id}`, {
      create: true,
      set: { uid, amount, phone, status: 'pending' },
      serverTime: ['createdAt'],
    });
  });

  const r = await campayCall(env, 'POST', '/api/collect/', {
    amount: String(amount),
    currency: 'XAF',
    from: phone,
    description: 'Depot Katika',
    external_reference: id,
  });
  if (!r.ok || !r.j.reference) {
    console.error('Campay collect', r.status, JSON.stringify(r.j));
    await runTx(env, async (tx) => tx.write(`deposits/${id}`, { set: { status: 'failed' } }));
    throw new HttpError('failed-precondition', r.j.message || 'Campay a refusé la demande.');
  }
  await runTx(env, async (tx) =>
    tx.write(`deposits/${id}`, { set: { campayRef: r.j.reference } }),
  );
  return { depositId: id, reference: r.j.reference };
}

/** Interroge Campay et crédite le portefeuille si le paiement a réussi (une seule fois). */
async function settleDepositCore(env, id) {
  const dep = await readDoc(env, `deposits/${id}`);
  if (!dep) return { status: 'unknown' };
  if (dep.status !== 'pending' || !dep.campayRef) return { status: dep.status };
  const firstFlag = await isFirstDeposit(env, dep.uid);

  const r = await campayCall(env, 'GET', `/api/transaction/${encodeURIComponent(dep.campayRef)}/`);
  if (!r.ok) {
    console.error('Campay status', r.status, JSON.stringify(r.j));
    return { status: 'pending' };
  }
  const st = String(r.j.status || '').toUpperCase();
  if (!st || st === 'PENDING') return { status: 'pending' };

  return runTx(env, async (tx) => {
    const d = await tx.get(`deposits/${id}`);
    if (!d || d.status !== 'pending') return { status: d ? d.status : 'unknown' };

    if (st !== 'SUCCESSFUL') {
      tx.write(`deposits/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] });
      return { status: 'failed' };
    }
    const sameAmount = Number(r.j.amount) === d.amount;
    const sameRef = !r.j.external_reference || r.j.external_reference === id;
    if (!sameAmount || !sameRef) {
      tx.write(`deposits/${id}`, { set: { status: 'mismatch' }, serverTime: ['closedAt'] });
      return { status: 'mismatch' };
    }
    const tokens = d.amount * TOKENS_PER_XAF;
    await markFirstDeposit(tx, d.uid, d.amount, firstFlag);
    tx.write(`users/${d.uid}`, { incr: { balance: tokens } });
    tx.write(`deposits/${id}`, {
      set: { status: 'credited', tokens, operator: r.j.operator || null },
      serverTime: ['closedAt'],
    });
    return { status: 'credited' };
  });
}

/** L'appli demande où en est son dépôt. */
async function campayDepositStatus({ uid, data, env }) {
  const id = idStr(data.depositId);
  const dep = id ? await readDoc(env, `deposits/${id}`) : null;
  if (!dep || dep.uid !== uid) throw new HttpError('not-found', 'Dépôt introuvable.');
  const r = await settleDeposit(env, id);
  const me = await readDoc(env, `users/${uid}`);
  return { status: r.status, balance: balanceOf(me) };
}

// ----------------------------------------------------------------------
// Retrait des gains de parrainage vers le solde principal
// ----------------------------------------------------------------------
// Les commissions de parrainage s'accumulent dans users/{uid}.referralBalance
// (et dans referralEarned, cumul total). Quand referralBalance atteint
// REFERRAL_WITHDRAW_MIN, le joueur peut les « retirer » : elles sont ajoutées
// à son solde principal (balance) et referralBalance repart à zéro.

/** Transfère les gains de parrainage vers le solde principal. */
async function referralWithdraw({ uid, env }) {
  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const amount = Math.max(0, intOr(me.referralBalance, 0));
    if (amount < REFERRAL_WITHDRAW_MIN) {
      throw new HttpError(
        'failed-precondition',
        `Retrait possible à partir de ${REFERRAL_WITHDRAW_MIN} FCFA de gains.`,
      );
    }
    tx.write(`users/${uid}`, {
      incr: { balance: amount, referralBalance: -amount, referralWithdrawn: amount },
    });
    return { amount, balance: balanceOf(me) + amount };
  });
}

// ======================================================================
// Comptes partenaires et débloquage des parties
// ======================================================================
// Un compte partenaire (users/{uid}.partner = true, désigné par
// l'administrateur grâce à son code promo) touche PARTNER_PERCENT % de la
// commission de Katika, après la part du parrain, sur les parties des joueurs
// qu'il a parrainés (ou que ses filleuls ont parrainés). Gains : partnerBalance
// (disponible), partnerEarned (cumul), partnerWithdrawn ; historique dans
// partnerEarnings/{id}.

function requireAdmin(uid, env) {
  if (!adminIds(env).includes(uid)) {
    throw new HttpError('permission-denied', "Accès réservé à l'administrateur.");
  }
}

/** Compte caissière : users/{uid}.cashier = true (activé par l'administrateur). */
async function isCashier(env, uid) {
  const u = await readDoc(env, `users/${uid}`);
  return !!u && u.cashier === true;
}

/** Administrateur ou caissière. Renvoie 'admin' ou 'cashier'. */
async function requireStaff(uid, env) {
  if (adminIds(env).includes(uid)) return 'admin';
  if (await isCashier(env, uid)) return 'cashier';
  throw new HttpError('permission-denied', 'Accès réservé aux administrateurs et caissières.');
}

/** Mon rôle : { admin, cashier }. */
async function myRole({ uid, env }) {
  return { admin: adminIds(env).includes(uid), cashier: await isCashier(env, uid) };
}

/** Administrateur : active ou retire le rôle de caissière (par code promo du compte). */
async function adminSetCashier({ uid, data, env }) {
  requireAdmin(uid, env);
  const key = promoKey(data.code);
  if (!key) throw new HttpError('invalid-argument', 'Code promo invalide.');
  const on = data.on !== false;
  return runTx(env, async (tx) => {
    const owner = await tx.get(`promoCodes/${key}`);
    if (!owner || typeof owner.uid !== 'string') {
      throw new HttpError('not-found', 'Aucun joueur avec ce code promo.');
    }
    tx.write(`users/${owner.uid}`, { set: { cashier: on } });
    return { ok: true, uid: owner.uid, code: key, cashier: on };
  });
}

/** Administrateur : liste des caissières. */
async function adminCashiers({ uid, env }) {
  requireAdmin(uid, env);
  const list = await queryDocs(env, 'users', eqFilter('cashier', true), 200);
  return {
    cashiers: list.map((u) => ({
      uid: u.id,
      name: typeof u.pseudo === 'string' ? u.pseudo : '',
      code: typeof u.promoCode === 'string' ? u.promoCode : typeof u.pseudo === 'string' ? u.pseudo : '',
      balance: Math.floor(balanceOf(u) / TOKENS_PER_XAF),
    })),
  };
}

/** Jeux interdits aux caissières (elles ne gardent que les courses). */
const CASHIER_BLOCKED = new Set([
  'cardsBetPropose', 'cardsBetAccept', 'cardsRematch',
  'startGame', 'payStake', 'startLocalGame', 'ludoJoinRunning',
  'cardsCreate', 'cardsJoin', 'tournamentRegister', 'tournamentTeamCreate', 'tournamentTeamJoin',
  'sportBetCreate', 'sportBetAccept', 'sideBetPropose', 'sideBetAccept', 'localBetCreate', 'transfer',
]);

// ----------------------------------------------------------------------
// Conformité et jeu responsable
// ----------------------------------------------------------------------
const TERMS_VERSION = 1;
const MONEY_IN = new Set(['campayDeposit', 'manualDepositRequest', 'sebpayDeposit']);
const MONEY_OUT = new Set(['manualWithdrawRequest', 'sebpayWithdrawRequest']);
// Bloqués pendant une auto-exclusion : tout ce qui joue ou recharge (les retraits restent possibles).
const EXCLUDE_BLOCKED = new Set([
  ...[...CASHIER_BLOCKED].filter((n) => n !== 'transfer'),
  ...MONEY_IN,
  'raceBetCreate',
]);

// ----------------------------------------------------------------------
// Détection des comptes suspects (robots, comptes truqués) : signaux, pas des preuves.
// L'administrateur décide ; « marquer comme vérifié » (riskCleared) lève l'alerte.
// ----------------------------------------------------------------------
function riskOf(u) {
  if (!u || u.riskCleared === true) return [];
  const reasons = [];
  const played = intOr(u.statPlayed, 0);
  const won = intOr(u.statWon, 0);
  if (played >= 30 && won * 100 >= played * 80) {
    reasons.push(`${Math.round((won * 100) / played)} % de victoires sur ${played} parties`);
  }
  const tg = intOr(u.tmGames, 0);
  const tf = intOr(u.tmFast, 0);
  if (tg >= 8 && tf * 100 >= tg * 60) {
    reasons.push(`rythme de jeu très rapide et régulier (${tf} parties sur ${tg})`);
  }
  return reasons;
}

// Temps moyen par coup en dessous duquel un humain ne joue pas (ms).
const FAST_MS = { games: 800, deuxdes: 800, songo: 1000, damier: 1000 };

/** Après règlement d'une partie à mise : mesure le rythme de jeu (une seule fois par partie). */
async function recordTiming(env, gameId) {
  for (const col of ['games', 'deuxdes', 'songo', 'damier']) {
    const d = await readDoc(env, `${col}/${gameId}`);
    if (!d) continue;
    if (d.settled !== true || d.refunded === true || !(intOr(d.stake, 0) > 0) || d.timingDone === true) return;
    const started = typeof d.startedAt === 'string' ? Date.parse(d.startedAt) : 0;
    const rev = intOr(d.rev, 0);
    await runTx(env, async (tx) => {
      const g = await tx.get(`${col}/${gameId}`);
      if (!g || g.timingDone === true) return;
      tx.write(`${col}/${gameId}`, { set: { timingDone: true } });
      if (!(started > 0) || rev < 10) return;
      const avg = (Date.now() - started) / rev;
      const fast = avg < FAST_MS[col] ? 1 : 0;
      for (const p of playersOf(g)) {
        if (p && p.uid) tx.write(`users/${p.uid}`, { incr: { tmGames: 1, tmFast: fast } });
      }
    });
    return;
  }
}

/** Administrateur : marque un compte comme vérifié (on) ou remet la surveillance (off). */
async function adminRiskClear({ uid, data, env }) {
  requireAdmin(uid, env);
  const target = typeof data.uid === 'string' && ID_RE.test(data.uid) ? data.uid : '';
  if (!target) throw new HttpError('invalid-argument', 'Joueur invalide.');
  const on = data.on !== false;
  await runTx(env, async (tx) => {
    tx.write(`users/${target}`, { set: { riskCleared: on, ...(on ? {} : { riskAlerted: false }) } });
  });
  return { ok: true, cleared: on };
}

/** Balayage horaire : prévient l'administrateur des nouveaux comptes suspects. */
async function riskScan(env) {
  try {
    const st = await readDoc(env, 'app/riskScan');
    if (st && Date.now() - intOr(st.lastMs, 0) < 6 * 3600000) return; // toutes les 6 h (économie de lectures)
    await runTx(env, async (tx) => {
      tx.write('app/riskScan', { set: { lastMs: Date.now() } });
    });
    const gte = (field, v) => ({ fieldFilter: { field: { fieldPath: field }, op: 'GREATER_THAN_OR_EQUAL', value: toFs(v) } });
    const [a, b] = await Promise.all([
      queryDocs(env, 'users', gte('statPlayed', 30), 200).catch(() => []),
      queryDocs(env, 'users', gte('tmGames', 8), 200).catch(() => []),
    ]);
    const seen = new Set();
    for (const u of [...a, ...b]) {
      if (seen.has(u.id)) continue;
      seen.add(u.id);
      const reasons = riskOf(u);
      if (!reasons.length || u.riskAlerted === true) continue;
      await runTx(env, async (tx) => {
        tx.write(`users/${u.id}`, { set: { riskAlerted: true } });
      });
      await notifyAdmin(env, `🕵️ Compte suspect : ${String(u.pseudo || u.id)}\n${reasons.join('\n')}\nOuvre Katika > Admin > Joueurs.`).catch(() => {});
    }
  } catch (e) {
    console.error('riskScan', e);
  }
}

async function sumRecent(env, uid, cols) {
  const cutoff = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  let sum = 0;
  for (const col of cols) {
    const docs = await queryDocs(env, col, eqFilter('uid', uid), 200).catch(() => []);
    for (const d of docs) {
      if (typeof d.createdAt !== 'string' || d.createdAt <= cutoff) continue;
      if (d.status === 'rejected' || d.status === 'failed') continue;
      sum += intOr(d.amount, 0);
    }
  }
  return sum;
}

/** Contrôles avant d'exécuter une fonction : caissière, CGU/18 ans, auto-exclusion, plafonds. */
async function guardRequest(env, uid, name, data) {
  const inn = MONEY_IN.has(name);
  const out = MONEY_OUT.has(name);
  if (!CASHIER_BLOCKED.has(name) && !EXCLUDE_BLOCKED.has(name) && !inn && !out) return { risk: [] };
  const u = (await readDoc(env, `users/${uid}`)) || {};
  if (u.cashier === true && CASHIER_BLOCKED.has(name)) {
    throw new HttpError('permission-denied', 'Compte caissière : seules les courses sont autorisées.');
  }
  if ((inn || out) && intOr(u.termsV, 0) < TERMS_VERSION) {
    throw new HttpError('failed-precondition', "Accepte d'abord les conditions d'utilisation (18 ans et plus).");
  }
  if (EXCLUDE_BLOCKED.has(name) && intOr(u.excludedUntil, 0) > Date.now()) {
    const d = new Date(intOr(u.excludedUntil, 0)).toLocaleDateString('fr-FR', { timeZone: 'Africa/Douala' });
    throw new HttpError('permission-denied', `Auto-exclusion active jusqu'au ${d}.`);
  }
  const amount = Math.max(0, intOr(data && data.amount, 0));
  if (inn) {
    const lim = intOr(u.depositLimitDay, 0);
    if (lim > 0) {
      const used = await sumRecent(env, uid, ['deposits', 'manualDeposits', 'sebpayDeposits']);
      if (used + amount > lim) {
        throw new HttpError('failed-precondition', `Limite de recharge atteinte (${lim} FCFA par 24 h, déjà ${used}).`);
      }
    }
  }
  const risk = out ? riskOf(u) : [];
  if (out && risk.length && name === 'sebpayWithdrawRequest') {
    throw new HttpError('failed-precondition', "Ton compte est en vérification : utilise le retrait « Local Cameroun », validé par l'administrateur.");
  }
  if (out) {
    const cap = intOr(env.WITHDRAW_DAILY_MAX, 300000);
    const used = await sumRecent(env, uid, ['manualWithdrawals', 'sebpayPayouts']);
    if (used + amount > cap) {
      throw new HttpError('failed-precondition', `Plafond de retrait : ${cap} FCFA par 24 h (déjà ${used}). Contacte le support pour un montant plus élevé.`);
    }
  }
  return { risk };
}

// Quelqu'un rejoint ta partie : push à l'hôte.
const JOIN_HANDLERS = new Set(['cardsJoin']);

async function pushJoined(env, uid, data) {
  const gameId = idOf(data);
  if (!gameId) return;
  for (const col of ['deuxdes', 'songo', 'damier', 'pileface', 'cards']) {
    const g = await readDoc(env, `${col}/${gameId}`);
    if (!g) continue;
    const host = typeof g.hostUid === 'string' ? g.hostUid : '';
    if (!host || host === uid) return;
    const me = await readDoc(env, `users/${uid}`);
    const who = me ? String(me.pseudo || me.promoCode || 'Un joueur') : 'Un joueur';
    const label = col === 'cards' ? (g.game === 'boubayah' ? 'BOUBAYAH' : g.game === 'fapfap' ? 'FAP-FAP' : g.game === 'anticote' ? 'ANTI-COTE' : g.game === 'tchek' ? 'TCHEK GAMES' : 'TIAH') : GAME_LABELS[col] || (col === 'pileface' ? 'Pile ou Face' : 'Katika');
    await pushToUser(env, host, '👋 Un joueur a rejoint', `${who} a rejoint ta partie de ${label}.`);
    return;
  }
}

async function myLimits({ uid, env }) {
  const u = (await readDoc(env, `users/${uid}`)) || {};
  return {
    termsV: intOr(u.termsV, 0),
    termsVersion: TERMS_VERSION,
    depositLimitDay: intOr(u.depositLimitDay, 0),
    excludedUntil: intOr(u.excludedUntil, 0),
    withdrawDailyMax: intOr(env.WITHDRAW_DAILY_MAX, 300000),
  };
}

/** Le joueur confirme avoir 18 ans ou plus et accepte les conditions. */
async function acceptTerms({ uid, data, env }) {
  if (data.age18 !== true || data.terms !== true) {
    throw new HttpError('invalid-argument', 'Tu dois confirmer ton âge et accepter les conditions.');
  }
  await runTx(env, async (tx) => {
    tx.write(`users/${uid}`, { set: { termsV: TERMS_VERSION, age18: true }, serverTime: ['termsAt'] });
  });
  return { ok: true };
}

/** Limite de recharge par 24 h (0 = aucune) et auto-exclusion (ne peut pas être raccourcie). */
async function setLimits({ uid, data, env }) {
  const set = {};
  if (data.depositLimitDay !== undefined) {
    const v = intOr(data.depositLimitDay, -1);
    if (v < 0 || v > 5000000) throw new HttpError('invalid-argument', 'Limite invalide.');
    set.depositLimitDay = v;
  }
  const days = intOr(data.excludeDays, 0);
  if (days > 0 && ![1, 7, 30, 90, 180, 365].includes(days)) {
    throw new HttpError('invalid-argument', 'Durée invalide.');
  }
  return runTx(env, async (tx) => {
    const u = (await tx.get(`users/${uid}`)) || {};
    if (days > 0) {
      set.excludedUntil = Math.max(intOr(u.excludedUntil, 0), Date.now() + days * 86400000);
    }
    if (Object.keys(set).length) tx.write(`users/${uid}`, { set });
    return {
      depositLimitDay: set.depositLimitDay !== undefined ? set.depositLimitDay : intOr(u.depositLimitDay, 0),
      excludedUntil: set.excludedUntil !== undefined ? set.excludedUntil : intOr(u.excludedUntil, 0),
    };
  });
}

/** Administrateur : journal des validations des caissières (et de l'administrateur). */
async function adminCashierLog({ uid, data, env }) {
  requireAdmin(uid, env);
  const who = typeof data.uid === 'string' && ID_RE.test(data.uid) ? data.uid : '';
  const list = await queryDocs(env, 'cashierLog', who ? eqFilter('uid', who) : undefined, 300);
  const items = list
    .map((d) => ({
      id: d.id,
      by: String(d.byName || ''),
      byUid: String(d.uid || ''),
      role: String(d.role || ''),
      kind: String(d.kind || ''),
      player: String(d.playerName || ''),
      amount: intOr(d.amount, 0),
      action: String(d.action || ''),
      at: typeof d.createdAt === 'string' ? d.createdAt : null,
    }))
    .sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')))
    .slice(0, 120);
  return { items };
}

function eqFilter(field, value) {
  return {
    fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: toFs(value) },
  };
}

async function queryDocs(env, collectionId, where, limit = 200) {
  const res = await fsCall(env, 'runQuery', {
    structuredQuery: { from: [{ collectionId }], where, limit },
  });
  return (Array.isArray(res) ? res : [])
    .filter((r) => r.document)
    .map((r) => ({
      id: r.document.name.split('/').pop(),
      ...fieldsToObj(r.document.fields || {}),
    }));
}

/** Administrateur : donne ou retire le statut de partenaire (par code promo). */
async function adminSetPartner({ uid, data, env }) {
  requireAdmin(uid, env);
  const key = promoKey(data.code);
  if (!key) throw new HttpError('invalid-argument', 'Code promo invalide.');
  const on = data.on !== false;
  return runTx(env, async (tx) => {
    const owner = await tx.get(`promoCodes/${key}`);
    if (!owner || typeof owner.uid !== 'string') {
      throw new HttpError('not-found', 'Aucun joueur avec ce code promo.');
    }
    tx.write(`users/${owner.uid}`, { set: { partner: on } });
    return { ok: true, uid: owner.uid, code: key, partner: on };
  });
}

// --- Hôtesses ---------------------------------------------------------
// Une hôtesse est un compte (users/{uid}.hostess = true) dont le code promo
// sert uniquement à compter les joueurs qu'elle inscrit : aucune commission.

/** Administrateur : donne ou retire le statut d'hôtesse (par code promo). */
async function adminSetHostess({ uid, data, env }) {
  requireAdmin(uid, env);
  const key = promoKey(data.code);
  if (!key) throw new HttpError('invalid-argument', 'Code promo invalide.');
  const on = data.on !== false;
  return runTx(env, async (tx) => {
    const owner = await tx.get(`promoCodes/${key}`);
    if (!owner || typeof owner.uid !== 'string') {
      throw new HttpError('not-found', 'Aucun joueur avec ce code promo.');
    }
    tx.write(`users/${owner.uid}`, { set: { hostess: on } });
    return { ok: true, uid: owner.uid, code: key, hostess: on };
  });
}

function periodOf(data) {
  const from = typeof data.from === 'string' && data.from ? data.from : null;
  const to = typeof data.to === 'string' && data.to ? data.to : null;
  return { from, to };
}

/** Joueurs inscrits avec le code d'une hôtesse, sur une période. */
async function hostessReport(env, uid, from, to) {
  const kids = await queryDocs(env, 'users', eqFilter('referrerUid', uid), 5000);
  const all = kids.map((k) => {
    const at = typeof k.referredAt === 'string' ? k.referredAt : k.createdAt;
    return { pseudo: String(k.pseudo || '?'), at: typeof at === 'string' ? at : null };
  });
  const members = all
    .filter((m) => m.at && (!from || m.at >= from) && (!to || m.at < to))
    .sort((a, b) => String(b.at).localeCompare(String(a.at)));
  return { total: all.length, count: members.length, members: members.slice(0, 1000) };
}

/** Administrateur : liste des hôtesses avec leurs inscrits sur la période. */
async function adminHostesses({ uid, data, env }) {
  requireAdmin(uid, env);
  const { from, to } = periodOf(data);
  const list = await queryDocs(env, 'users', eqFilter('hostess', true), 200);
  const hostesses = await Promise.all(
    list.map(async (u) => {
      const r = await hostessReport(env, u.id, from, to);
      return {
        uid: u.id,
        code: String(u.promoCode || u.pseudo || '?'),
        pseudo: String(u.pseudo || ''),
        total: r.total,
        count: r.count,
      };
    }),
  );
  hostesses.sort((a, b) => b.count - a.count);
  return { hostesses, count: hostesses.reduce((s, h) => s + h.count, 0) };
}

/** Hôtesse : ses inscrits sur la période. L'administrateur peut consulter
 *  une hôtesse précise en donnant son code promo. */
async function hostessStats({ uid, data, env }) {
  const { from, to } = periodOf(data);
  let target = uid;
  let code = '';
  if (typeof data.code === 'string' && data.code.trim()) {
    requireAdmin(uid, env);
    const key = promoKey(data.code);
    const owner = key ? await readDoc(env, `promoCodes/${key}`) : null;
    if (!owner || typeof owner.uid !== 'string') {
      throw new HttpError('not-found', 'Aucune hôtesse avec ce code.');
    }
    target = owner.uid;
    code = key;
  }
  const me = await readDoc(env, `users/${target}`);
  if (!me || me.hostess !== true) {
    throw new HttpError('permission-denied', 'Accès réservé aux hôtesses.');
  }
  if (!code) code = String(me.promoCode || me.pseudo || '');
  const r = await hostessReport(env, target, from, to);
  return { code, pseudo: String(me.pseudo || ''), ...r };
}

/** Administrateur : liste des partenaires et de leurs gains. */
async function adminPartners({ uid, env }) {
  requireAdmin(uid, env);
  const list = await queryDocs(env, 'users', eqFilter('partner', true), 100);
  return {
    percent: PARTNER_PERCENT,
    partners: list.map((u) => ({
      uid: u.id,
      code: String(u.promoCode || u.pseudo || '?'),
      earned: Math.max(0, intOr(u.partnerEarned, 0)),
      available: Math.max(0, intOr(u.partnerBalance, 0)),
      withdrawn: Math.max(0, intOr(u.partnerWithdrawn, 0)),
    })),
  };
}

/** Filleuls directs d'un partenaire : total, et nombre de filleuls « actifs »
 *  (ceux qui ont misé au moins PARTNER_MIN_WAGERED FCFA au total). */
async function partnerQualified(env, uid) {
  const kids = await queryDocs(env, 'users', eqFilter('referrerUid', uid), 500);
  const qualified = kids.filter(
    (k) => Math.max(0, intOr(k.wagered, 0)) >= PARTNER_MIN_WAGERED,
  ).length;
  return { total: kids.length, qualified };
}

/** Partenaire : ses gains, ses filleuls et son historique. */
async function partnerStats({ uid, env }) {
  const me = await readDoc(env, `users/${uid}`);
  if (!me || me.partner !== true) {
    throw new HttpError('permission-denied', 'Accès réservé aux administrateurs et partenaires.');
  }
  let referrals = 0;
  try {
    const r = await fsCall(env, 'runAggregationQuery', {
      structuredAggregationQuery: {
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: eqFilter('referrerUid', uid),
        },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    referrals = Number(r[0].result.aggregateFields.n.integerValue) || 0;
  } catch (_) {}
  const list = await queryDocs(env, 'partnerEarnings', eqFilter('partner', uid), 300);
  list.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
  const available = Math.max(0, intOr(me.partnerBalance, 0));
  const { qualified } = await partnerQualified(env, uid);
  const conditionsMet = qualified >= PARTNER_MIN_REFERRALS;
  return {
    code: String(me.promoCode || me.pseudo || ''),
    percent: PARTNER_PERCENT,
    earned: Math.max(0, intOr(me.partnerEarned, 0)),
    available,
    withdrawn: Math.max(0, intOr(me.partnerWithdrawn, 0)),
    min: PARTNER_WITHDRAW_MIN,
    canWithdraw: available >= PARTNER_WITHDRAW_MIN && conditionsMet,
    // Conditions de retrait : 25 filleuls ayant chacun misé au moins 1000 FCFA
    qualified,
    needReferrals: PARTNER_MIN_REFERRALS,
    needWagered: PARTNER_MIN_WAGERED,
    conditionsMet,
    referrals,
    games: list.length,
    recent: list.slice(0, 50).map((e) => ({
      amount: intOr(e.amount, 0),
      mode: String(e.mode || ''),
      createdAt: typeof e.createdAt === 'string' ? e.createdAt : null,
    })),
  };
}

/** Partenaire : transfère ses gains vers son solde principal. */
async function partnerWithdraw({ uid, env }) {
  // Condition : au moins PARTNER_MIN_REFERRALS filleuls ayant chacun misé au
  // moins PARTNER_MIN_WAGERED FCFA au total.
  const { qualified } = await partnerQualified(env, uid);
  if (qualified < PARTNER_MIN_REFERRALS) {
    throw new HttpError(
      'failed-precondition',
      `Retrait possible quand ${PARTNER_MIN_REFERRALS} filleuls ont chacun misé au moins ` +
        `${PARTNER_MIN_WAGERED} FCFA (actuellement ${qualified}).`,
    );
  }
  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me || me.partner !== true) {
      throw new HttpError('permission-denied', 'Réservé aux partenaires.');
    }
    const amount = Math.max(0, intOr(me.partnerBalance, 0));
    if (amount < PARTNER_WITHDRAW_MIN) {
      throw new HttpError(
        'failed-precondition',
        `Retrait possible à partir de ${PARTNER_WITHDRAW_MIN} FCFA de gains.`,
      );
    }
    tx.write(`users/${uid}`, {
      incr: { balance: amount, partnerBalance: -amount, partnerWithdrawn: amount },
    });
    return { amount, balance: balanceOf(me) + amount };
  });
}

async function readDoc(env, path) {
  const r = await fsCall(env, 'batchGet', { documents: [docName(env, path)] });
  const f = Array.isArray(r) && r[0] && r[0].found;
  return f ? fieldsToObj(f.fields || {}) : null;
}

/** Administrateur : débloque les parties restées bloquées depuis plus de
 *  REVIVE_AFTER_MIN minutes (en attente ou en cours, jamais terminées) :
 *  toutes les mises sont remboursées et la partie est clôturée. */
async function adminReviveGames({ uid, env }) {
  requireAdmin(uid, env);
  await accessToken(env);
  const limitMs = Date.now() - REVIVE_AFTER_MIN * 60 * 1000;
  const targets = [];
  for (const col of ['games', 'deuxdes', 'songo', 'damier', 'pileface', 'cards', 'localGames']) {
    for (const status of ['waiting', 'playing']) {
      const docs = await queryDocs(env, col, eqFilter('status', status), 200);
      for (const d of docs) {
        const t = typeof d.createdAt === 'string' ? Date.parse(d.createdAt) : 0;
        if (d.settled !== true && d.over !== true && t > 0 && t < limitMs) targets.push({ col, id: d.id });
      }
    }
  }
  let revived = 0;
  let refunded = 0;
  for (const { col, id } of targets) {
    try {
      const amount = await runTx(env, async (tx) => {
        const path = `${col}/${id}`;
        const d = await tx.get(path);
        if (!d || d.settled === true) return -1;
        if (d.status !== 'waiting' && d.status !== 'playing') return -1;
        if (d.over === true) return -1; // terminée : les joueurs la règlent à l'ouverture
        const stake = Math.max(0, intOr(d.stake, 0));
        const who =
          col === 'localGames'
            ? (Array.isArray(d.uids) ? d.uids : [])
            : chargedPaid(d);
        refund(tx, who, stake, d);
        tx.write(path, {
          set: {
            settled: true,
            refunded: true,
            status: 'finished',
            over: true,
            commission: 0,
            referralPaid: 0,
            partnerPaid: 0,
          },
        });
        return stake > 0 ? stake * who.length : 0;
      });
      if (amount >= 0) {
        revived++;
        refunded += amount;
      }
    } catch (_) {}
  }
  return { found: targets.length, revived, refunded, afterMinutes: REVIVE_AFTER_MIN };
}

/** Transfert d'argent d'un joueur vers un autre (par pseudo ou code promo). */
/** Suggestions de destinataires : dès 2 caractères, joueurs dont le code promo (= pseudo)
 *  commence par ce texte. On ne renvoie que le pseudo et le code, jamais l'identifiant. */
async function searchPlayers({ uid, data, env }) {
  const q = String(data.q || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '')
    .slice(0, 30);
  if (q.length < 2) return { players: [] };
  const col = (id) => docName(env, `promoCodes/${id}`);
  const res = await fsCall(env, 'runQuery', {
    structuredQuery: {
      from: [{ collectionId: 'promoCodes' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            { fieldFilter: { field: { fieldPath: '__name__' }, op: 'GREATER_THAN_OR_EQUAL', value: { referenceValue: col(q) } } },
            { fieldFilter: { field: { fieldPath: '__name__' }, op: 'LESS_THAN', value: { referenceValue: col(q + '\uf8ff') } } },
          ],
        },
      },
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: 8,
    },
  });
  const rows = (Array.isArray(res) ? res : [])
    .filter((r) => r.document)
    .map((r) => ({ code: r.document.name.split('/').pop(), ...fieldsToObj(r.document.fields || {}) }))
    .filter((r) => typeof r.uid === 'string' && r.uid !== uid);
  if (!rows.length) return { players: [] };
  const got = await fsCall(env, 'batchGet', { documents: rows.map((r) => docName(env, `users/${r.uid}`)) });
  const byName = {};
  for (const g of Array.isArray(got) ? got : []) {
    if (g.found) byName[g.found.name.split('/').pop()] = fieldsToObj(g.found.fields || {});
  }
  const players = rows
    .map((r) => {
      const u = byName[r.uid] || {};
      return { name: String(u.pseudo || r.code), code: r.code };
    })
    .slice(0, 8);
  return { players };
}

async function transfer({ uid, data, env }) {
  const amount = intOr(data.amount, -1);
  if (amount < TRANSFER_MIN || amount > TRANSFER_MAX) {
    throw new HttpError('invalid-argument', `Montant entre ${TRANSFER_MIN} et ${TRANSFER_MAX} FCFA.`);
  }
  const raw = String(data.to || '').trim().slice(0, 60);
  if (!raw) throw new HttpError('invalid-argument', 'Indique le pseudo du destinataire.');

  // Retrouve le destinataire : code promo (= pseudo) d'abord, puis pseudo exact.
  let toUid = '';
  const key = promoKey(raw);
  if (key) {
    const o = await readDoc(env, `promoCodes/${key}`);
    if (o && typeof o.uid === 'string') toUid = o.uid;
  }
  if (!toUid) {
    const list = await queryDocs(env, 'users', eqFilter('pseudo', raw), 2);
    if (list.length > 1) {
      throw new HttpError('failed-precondition', 'Plusieurs joueurs ont ce pseudo : utilise son code promo.');
    }
    if (list.length === 1) toUid = list[0].id;
  }
  if (!toUid) throw new HttpError('not-found', 'Aucun joueur avec ce pseudo ou ce code promo.');
  if (toUid === uid) throw new HttpError('invalid-argument', "Tu ne peux pas t'envoyer de l'argent.");

  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    const to = await tx.get(`users/${toUid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (!to) throw new HttpError('not-found', 'Compte du destinataire introuvable.');
    if (balanceOf(me) < amount) {
      throw new HttpError('failed-precondition', 'Solde insuffisant.');
    }
    assertWagerDone(me); // évite de contourner la règle en envoyant l'argent à un autre compte
    const toName = String(to.pseudo || to.promoCode || raw);
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(`users/${toUid}`, { incr: { balance: amount } });
    tx.write(`transfers/${newId()}`, {
      create: true,
      set: {
        from: uid,
        to: toUid,
        amount,
        fromName: String(me.pseudo || me.promoCode || ''),
        toName,
      },
      serverTime: ['createdAt'],
    });
    return { amount, toName, balance: balanceOf(me) - amount };
  });
}

/** Appelé par Campay (sans connexion joueur) : déclenche la vérification du dépôt. */
async function campayWebhook(request, env) {
  const p = Object.fromEntries(new URL(request.url).searchParams);
  if (request.method === 'POST') {
    try {
      Object.assign(p, await request.json());
    } catch (_) {}
  }
  if (p.signature && !(await hs256Verify(p.signature, env.CAMPAY_WEBHOOK_KEY))) {
    return new Response('bad signature', { status: 401 });
  }
  const id = idStr(p.external_reference);
  if (id) {
    try {
      await settleDeposit(env, id);
    } catch (e) {
      console.error(e);
      return new Response('error', { status: 500 });
    }
  }
  return new Response('ok');
}

// ======================================================================
// Recharge et retrait MANUELS par code marchand Orange Money
// ======================================================================
// manualDeposits/{id}    : { uid, name, amount, phone, txRef, status, createdAt, closedAt, closedBy }
//                          status : pending | credited | rejected
// manualWithdrawals/{id} : { uid, name, amount, tokens, phone, status, createdAt, closedAt, closedBy }
//                          status : pending | paid | rejected
// manualRefs/{txRef}     : identifiant de transaction déjà utilisé (une seule fois)
// L'administrateur compare avec ses SMS / son historique Orange Money, puis
// confirme (la recharge est créditée) ou refuse. Pour un retrait, le montant
// est retiré du solde au moment de la demande ; refusé = remboursé.

const CAMPAY_ENABLED = false; // Campay désactivé : recharge uniquement par code marchand
const OM_MERCHANT_CODE = '0529831'; // peut être remplacé par la variable OM_MERCHANT_CODE
const OM_USSD_TEMPLATE = '#150*47*{code}*{amount}*2#'; // {amount} = montant saisi par le client
const MTN_MERCHANT_CODE = '98152898'; // code marchand MTN MoMo (variable MTN_MERCHANT_CODE pour le changer)
const MTN_USSD_TEMPLATE = '*126*4*{code}*{amount}#';
const MANUAL_DEPOSIT_MIN = 100;
const MANUAL_DEPOSIT_MAX = 250000;
const MANUAL_WITHDRAW_MIN = 500;
const MANUAL_WITHDRAW_MAX = 250000;
const MANUAL_MAX_PENDING_DEPOSITS = 5;
const MANUAL_MAX_PENDING_WITHDRAWALS = 3;

function merchantCode(env) {
  return String((env && env.OM_MERCHANT_CODE) || OM_MERCHANT_CODE);
}

function mtnMerchantCode(env) {
  return String((env && env.MTN_MERCHANT_CODE) || MTN_MERCHANT_CODE);
}

function normTxRef(v) {
  const s = String(v || '').toUpperCase().replace(/[^A-Z0-9.]/g, '');
  return s.length >= 6 && s.length <= 30 ? s : '';
}

function manualPublic(d) {
  return {
    id: d.id,
    amount: intOr(d.amount, 0),
    phone: typeof d.phone === 'string' ? d.phone : '',
    txRef: typeof d.txRef === 'string' ? d.txRef : '',
    operator: d.operator === 'mtn' ? 'mtn' : 'orange',
    status: typeof d.status === 'string' ? d.status : 'pending',
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : null,
    closedAt: typeof d.closedAt === 'string' ? d.closedAt : null,
  };
}

const byDateDesc = (k) => (a, b) => String(b[k] || '').localeCompare(String(a[k] || ''));

/** Infos affichées dans l'appli : code marchand, USSD, limites. */
async function manualInfo({ env }) {
  return {
    code: merchantCode(env),
    ussd: OM_USSD_TEMPLATE.replace('{code}', merchantCode(env)),
    mtn: {
      code: mtnMerchantCode(env),
      ussd: MTN_USSD_TEMPLATE.replace('{code}', mtnMerchantCode(env)),
    },
    depositMin: MANUAL_DEPOSIT_MIN,
    depositMax: MANUAL_DEPOSIT_MAX,
    withdrawMin: MANUAL_WITHDRAW_MIN,
    withdrawMax: MANUAL_WITHDRAW_MAX,
  };
}

/** Le joueur a payé au code marchand : il envoie le montant et l'identifiant de la transaction. */
/** Prévient l'administrateur sur ntfy, WhatsApp et/ou Telegram (selon les
 *  variables définies). Ne bloque jamais la demande du joueur. */
async function notifyAdmin(env, text, opts = {}) {
  const tasks = [];
  // ntfy en premier et en parallèle : un service lent (WhatsApp) ne bloque plus les autres.
  if (env.NTFY_TOPIC && !opts.skipNtfy) {
    tasks.push(
      ntfyPost(env, { Title: 'Katika', Priority: 'high', Tags: 'moneybag' }, text)
    );
  }
  // WhatsApp (service CallMeBot) : variables WHATSAPP_PHONE et WHATSAPP_APIKEY.
  if (env.WHATSAPP_PHONE && env.WHATSAPP_APIKEY) {
    const phone = String(env.WHATSAPP_PHONE).replace(/\D/g, '');
    const url =
      `https://api.callmebot.com/whatsapp.php?phone=${phone}` +
      `&text=${encodeURIComponent(text)}&apikey=${encodeURIComponent(env.WHATSAPP_APIKEY)}`;
    tasks.push(fetchQuiet(url, undefined, 'WhatsApp'));
  }
  // Telegram (facultatif) : TELEGRAM_BOT_TOKEN et TELEGRAM_CHAT_ID.
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
    tasks.push(
      fetchQuiet(
        `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
        {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
        },
        'Telegram'
      )
    );
  }
  await Promise.all(tasks);
}

/** Appel réseau qui ne lève jamais d'erreur, avec délai maximum de 6 s. */
async function fetchQuiet(url, init, label) {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 6000);
    const r = await fetch(url, { ...(init || {}), signal: ctl.signal });
    clearTimeout(timer);
    if (!r.ok) console.error(`${label} : réponse ${r.status}`);
    return r;
  } catch (e) {
    console.error(`${label} : échec`, e && e.message);
    return null;
  }
}

/** Envoi ntfy : un second essai si le service répond 429 ou une erreur. */
async function ntfyPost(env, headers, body) {
  const url = `https://ntfy.sh/${encodeURIComponent(env.NTFY_TOPIC)}`;
  // Les en-têtes ne doivent contenir que de l'ASCII : le texte accentué va dans le corps.
  for (let attempt = 0; attempt < 2; attempt++) {
    const r = await fetchQuiet(url, { method: 'POST', headers, body }, 'ntfy');
    if (r && r.ok) return;
    await new Promise((res) => setTimeout(res, 1200));
  }
}

async function manualDepositRequest({ uid, data, env }) {
  const amount = intOr(data.amount, -1);
  if (amount < MANUAL_DEPOSIT_MIN || amount > MANUAL_DEPOSIT_MAX) {
    throw new HttpError('invalid-argument', `Montant entre ${MANUAL_DEPOSIT_MIN} et ${MANUAL_DEPOSIT_MAX} FCFA.`);
  }
  const operator = data.operator === 'mtn' ? 'mtn' : 'orange';
  const phone = normPhone(data.phone);
  if (!phone) {
    throw new HttpError(
      'invalid-argument',
      operator === 'mtn' ? 'Numéro MTN invalide (ex : 670000000).' : 'Numéro Orange invalide (ex : 690000000).',
    );
  }
  const txRef = normTxRef(data.txRef);
  if (!txRef) {
    throw new HttpError('invalid-argument', "Entre l'identifiant de la transaction reçu par SMS (6 à 30 caractères).");
  }
  const mine = await queryDocs(env, 'manualDeposits', eqFilter('uid', uid), 100);
  if (mine.filter((x) => x.status === 'pending').length >= MANUAL_MAX_PENDING_DEPOSITS) {
    throw new HttpError('failed-precondition', 'Tu as déjà trop de demandes en attente. Patiente le temps de la confirmation.');
  }
  const id = newId();
  await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const used = await tx.get(`manualRefs/${txRef}`);
    if (used) throw new HttpError('failed-precondition', 'Cet identifiant de transaction a déjà été utilisé.');
    tx.write(`manualRefs/${txRef}`, { create: true, set: { uid, depositId: id }, serverTime: ['createdAt'] });
    tx.write(`manualDeposits/${id}`, {
      create: true,
      set: { uid, name: typeof me.pseudo === 'string' ? me.pseudo : '', amount, phone, txRef, operator, status: 'pending' },
      serverTime: ['createdAt'],
    });
  });
  const depText = `⬇️ Recharge à confirmer (${operator === 'mtn' ? 'MTN MoMo' : 'Orange Money'})\n${amount} FCFA · ${phone}\nTransaction : ${txRef}\nOuvre Katika > Admin > Recharges et retraits.`;
  // ntfy attendu (même chemin que l'alerte « recharge validée », qui fonctionne) ; autres canaux en arrière-plan.
  await ntfyTx(env, uid, 'inbox_tray', depText);
  later(env, notifyAdmin(env, depText, { skipNtfy: true }));
  return { id };
}

/** Demande de retrait : le montant est retiré du solde tout de suite. */
async function manualWithdrawRequest({ uid, data, env }) {
  const amount = intOr(data.amount, -1);
  if (amount < MANUAL_WITHDRAW_MIN || amount > MANUAL_WITHDRAW_MAX) {
    throw new HttpError('invalid-argument', `Montant entre ${MANUAL_WITHDRAW_MIN} et ${MANUAL_WITHDRAW_MAX} FCFA.`);
  }
  const phone = normPhone(data.phone);
  if (!phone) throw new HttpError('invalid-argument', 'Numéro Orange Money invalide (ex : 690000000).');
  const mine = await queryDocs(env, 'manualWithdrawals', eqFilter('uid', uid), 100);
  if (mine.filter((x) => x.status === 'pending').length >= MANUAL_MAX_PENDING_WITHDRAWALS) {
    throw new HttpError('failed-precondition', 'Tu as déjà des retraits en attente.');
  }
  const tokens = amount * TOKENS_PER_XAF;
  const id = newId();
  const balance = await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (balanceOf(me) < tokens) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    assertWagerDone(me);
    tx.write(`users/${uid}`, { incr: { balance: -tokens } });
    tx.write(`manualWithdrawals/${id}`, {
      create: true,
      set: { uid, name: typeof me.pseudo === 'string' ? me.pseudo : '', amount, tokens, phone, status: 'pending' },
      serverTime: ['createdAt'],
    });
    return balanceOf(me) - tokens;
  });
  const witText = `⬆️ Retrait à payer\n${amount} FCFA vers ${phone}\nOuvre Katika > Admin > Recharges et retraits.`;
  await ntfyTx(env, uid, 'outbox_tray', witText);
  later(env, notifyAdmin(env, witText, { skipNtfy: true }));
  return { id, balance };
}

/** Mes dernières demandes de recharge et de retrait. */
async function manualMine({ uid, env }) {
  const [dep, wit] = await Promise.all([
    queryDocs(env, 'manualDeposits', eqFilter('uid', uid), 60),
    queryDocs(env, 'manualWithdrawals', eqFilter('uid', uid), 60),
  ]);
  return {
    deposits: dep.map(manualPublic).sort(byDateDesc('createdAt')).slice(0, 20),
    withdrawals: wit.map(manualPublic).sort(byDateDesc('createdAt')).slice(0, 20),
  };
}

/** Administrateur : demandes en attente + dernières demandes traitées. */
async function adminManualList({ uid, env }) {
  await requireStaff(uid, env);
  await accessToken(env);
  const row = (kind) => (d) => ({
    ...manualPublic(d),
    kind,
    uid: d.uid,
    name: typeof d.name === 'string' ? d.name : '',
  });
  const [dp, wp, d1, d2, w1, w2] = await Promise.all([
    queryDocs(env, 'manualDeposits', eqFilter('status', 'pending'), 200),
    queryDocs(env, 'manualWithdrawals', eqFilter('status', 'pending'), 200),
    queryDocs(env, 'manualDeposits', eqFilter('status', 'credited'), 30),
    queryDocs(env, 'manualDeposits', eqFilter('status', 'rejected'), 30),
    queryDocs(env, 'manualWithdrawals', eqFilter('status', 'paid'), 30),
    queryDocs(env, 'manualWithdrawals', eqFilter('status', 'rejected'), 30),
  ]);
  const recent = [...d1.map(row('deposit')), ...d2.map(row('deposit')), ...w1.map(row('withdrawal')), ...w2.map(row('withdrawal'))]
    .sort(byDateDesc('closedAt'))
    .slice(0, 40);
  const withdrawals = wp.map(row('withdrawal')).sort(byDateDesc('createdAt'));
  for (const w of withdrawals) {
    try {
      const u = await readDoc(env, `users/${w.uid}`);
      const rk = riskOf(u);
      if (rk.length) w.risk = rk.join(' ; ');
    } catch (_) {}
  }
  return {
    deposits: dp.map(row('deposit')).sort(byDateDesc('createdAt')),
    withdrawals,
    recent,
  };
}

/** Administrateur : confirme ou refuse une demande.
 *  data : { kind: 'deposit' | 'withdrawal', id, action: 'approve' | 'reject' } */
/** Administrateur : remet TOUS les soldes à zéro (action unique, irréversible).
 *  Il faut envoyer confirm = 'ZERO'. */
async function adminResetBalances({ uid, data, env }) {
  requireAdmin(uid, env);
  if (data.confirm !== 'ZERO') throw new HttpError('invalid-argument', 'Confirmation manquante.');
  const gt0 = {
    fieldFilter: { field: { fieldPath: 'balance' }, op: 'GREATER_THAN', value: toFs(0) },
  };
  const lt0 = {
    fieldFilter: { field: { fieldPath: 'balance' }, op: 'LESS_THAN', value: toFs(0) },
  };
  let count = 0;
  for (const where of [gt0, lt0]) {
    for (let round = 0; round < 50; round++) {
      const docs = await queryDocs(env, 'users', where, 200);
      if (!docs.length) break;
      await runTx(env, async (tx) => {
        for (const d of docs) tx.write(`users/${d.id}`, { set: { balance: 0 } });
      });
      count += docs.length;
    }
  }
  return { reset: count };
}

async function adminManualDecideCore({ uid, data, env }) {
  const role = await requireStaff(uid, env);
  const id = idStr(data.id);
  const kind = data.kind === 'withdrawal' ? 'withdrawal' : data.kind === 'deposit' ? 'deposit' : '';
  const approve = data.action === 'approve';
  if (!id || !kind || (!approve && data.action !== 'reject')) {
    throw new HttpError('invalid-argument', 'Demande invalide.');
  }
  const path = kind === 'deposit' ? `manualDeposits/${id}` : `manualWithdrawals/${id}`;
  if (role === 'cashier' && approve) {
    // Plafond journalier de validation par caissière.
    const pre = await readDoc(env, path);
    const cap = intOr(env.CASHIER_DAILY_MAX, 1000000);
    const cutoff = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const mine = await queryDocs(env, 'cashierLog', eqFilter('uid', uid), 300).catch(() => []);
    const used = mine
      .filter((x) => typeof x.createdAt === 'string' && x.createdAt > cutoff && (x.action === 'credited' || x.action === 'paid'))
      .reduce((a, x) => a + intOr(x.amount, 0), 0);
    if (pre && used + intOr(pre.amount, 0) > cap) {
      throw new HttpError('failed-precondition', `Plafond journalier de validation atteint (${cap} FCFA par 24 h).`);
    }
  }
  let firstFlag = false;
  if (kind === 'deposit' && approve) {
    const pre0 = await readDoc(env, path);
    if (pre0 && pre0.status === 'pending' && pre0.uid) firstFlag = await isFirstDeposit(env, pre0.uid);
  }
  return runTx(env, async (tx) => {
    const d = await tx.get(path);
    if (!d) throw new HttpError('not-found', 'Demande introuvable.');
    if (d.status !== 'pending') throw new HttpError('failed-precondition', 'Cette demande est déjà traitée.');
    if (role !== 'admin' && d.uid === uid) {
      throw new HttpError('permission-denied', 'Une caissière ne peut pas valider ses propres demandes.');
    }
    const tokens = kind === 'deposit' ? intOr(d.amount, 0) * TOKENS_PER_XAF : intOr(d.tokens, 0);
    let status;
    if (kind === 'deposit') {
      status = approve ? 'credited' : 'rejected';
      if (approve) {
        await markFirstDeposit(tx, d.uid, intOr(d.amount, 0), firstFlag);
        tx.write(`users/${d.uid}`, { incr: { balance: tokens } });
      }
    } else {
      status = approve ? 'paid' : 'rejected';
      if (!approve) tx.write(`users/${d.uid}`, { incr: { balance: tokens } }); // remboursé
    }
    tx.write(path, { set: { status, closedBy: uid, closedByRole: role }, serverTime: ['closedAt'] });
    const staff = await tx.get(`users/${uid}`);
    tx.write(`cashierLog/${newId()}`, {
      create: true,
      set: {
        uid,
        role,
        byName: staff ? String(staff.pseudo || staff.promoCode || '') : '',
        kind,
        reqId: id,
        playerUid: String(d.uid || ''),
        playerName: String(d.name || ''),
        amount: intOr(d.amount, 0),
        action: status,
      },
      serverTime: ['createdAt'],
    });
    return { status };
  });
}

// ======================================================================
// Paiement AUTOMATIQUE par SebPay (recharge + retrait)
// ======================================================================
// Secrets Cloudflare (worker katika-api) : SEBPAY_PUBLIC_KEY (pk_live_...) et
// SEBPAY_SECRET_KEY (sk_live_...). Facultatif : SEBPAY_OP_ORANGE, SEBPAY_OP_MTN
// (code ou slug de l'opérateur renvoyé par GET /operators, si celui par défaut
// est refusé) et SEBPAY_CALLBACK_URL.
// sebpayDeposits/{id}  : { uid, name, amount, phone, operator, status, sebpayTx }
//                        status : pending | credited | failed | mismatch
// sebpayPayouts/{id}   : { uid, name, amount, tokens, phone, operator, status, sebpayTx }
//                        status : pending | paid | failed (jetons remboursés)
// external_reference envoyée à SebPay : "D" + id (recharge) ou "W" + id (retrait).
// Un crédit n'est fait qu'après lecture de la transaction chez SebPay
// (GET /collections), jamais sur la seule foi d'un webhook.

const SEBPAY_BASE = 'https://newapi.sebpay.bj/api/v1';
const SEBPAY_CALLBACK = 'https://katika-api.ychachouang.workers.dev/sebpay/webhook';
const SEBPAY_COUNTRY = 'CM';
const SEBPAY_CURRENCY = 'XAF';
const SEBPAY_DEPOSIT_MIN = 100;
const SEBPAY_DEPOSIT_MAX = 250000;
const SEBPAY_WITHDRAW_MIN = 500;
const SEBPAY_WITHDRAW_MAX = 100000; // au-delà : retrait manuel validé par l'administrateur
const SEBPAY_MAX_PENDING_DEPOSITS = 3;
const SEBPAY_MAX_PENDING_PAYOUTS = 3;
const SEBPAY_OPERATORS = {
  orange: { label: 'Orange Money', code: 'orange-cm' },
  mtn: { label: 'MTN MoMo', code: 'mtn-cm' },
};

function sebpayEnabled(env) {
  return !!(env.SEBPAY_PUBLIC_KEY && env.SEBPAY_SECRET_KEY);
}

function sebpayOperatorCode(env, key) {
  const o = SEBPAY_OPERATORS[String(key || '')];
  if (!o) return '';
  return String(env['SEBPAY_OP_' + String(key).toUpperCase()] || o.code);
}

async function sebpayCall(env, method, path, body) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 20000);
  try {
    // SebPay n'accepte que des adresses IP fixes : si SEBPAY_RELAY_URL est défini,
    // l'appel passe par le serveur relais (IP fixe) qui le transmet à SebPay.
    const relay = String(env.SEBPAY_RELAY_URL || '').replace(/\/+$/, '');
    const res = await fetch((relay || SEBPAY_BASE) + path, {
      method,
      headers: {
        'X-Public-Key': env.SEBPAY_PUBLIC_KEY,
        'X-Secret-Key': env.SEBPAY_SECRET_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(relay ? { 'X-Relay-Key': String(env.SEBPAY_RELAY_KEY || '') } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    let j = {};
    try {
      j = (await res.json()) || {};
    } catch (_) {}
    const data = j && typeof j.data === 'object' && j.data ? j.data : j;
    return { ok: res.ok, status: res.status, j, data, raw: JSON.stringify(j) };
  } catch (e) {
    return { ok: false, status: 0, network: true, j: {}, data: {}, raw: 'NETWORK' };
  } finally {
    clearTimeout(timer);
  }
}

const sebpayHas = (r, code) => String(r.raw || '').includes(code);
const sebpayMsg = (r) => (typeof r.j.message === 'string' && r.j.message) || '';

function sebpayAgeMs(d) {
  const t = Date.parse(d && d.createdAt);
  return Number.isFinite(t) ? Date.now() - t : 0;
}

function sebpayPublic(d) {
  return {
    id: d.id,
    amount: intOr(d.amount, 0),
    phone: typeof d.phone === 'string' ? d.phone : '',
    operator: typeof d.operator === 'string' ? d.operator : '',
    status: typeof d.status === 'string' ? d.status : 'pending',
    createdAt: typeof d.createdAt === 'string' ? d.createdAt : null,
    closedAt: typeof d.closedAt === 'string' ? d.closedAt : null,
  };
}

/** Infos pour l'appli : SebPay disponible ? opérateurs, limites. */
async function sebpayInfo({ env }) {
  return {
    enabled: sebpayEnabled(env),
    operators: Object.entries(SEBPAY_OPERATORS).map(([id, o]) => ({ id, label: o.label })),
    depositMin: SEBPAY_DEPOSIT_MIN,
    depositMax: SEBPAY_DEPOSIT_MAX,
    withdrawMin: SEBPAY_WITHDRAW_MIN,
    withdrawMax: SEBPAY_WITHDRAW_MAX,
  };
}

/** Recharge automatique : le joueur reçoit la demande de validation sur son téléphone. */
async function sebpayDeposit({ uid, data, env }) {
  if (!sebpayEnabled(env)) throw new HttpError('failed-precondition', 'Le paiement automatique est indisponible.');
  const amount = intOr(data.amount, -1);
  if (amount < SEBPAY_DEPOSIT_MIN || amount > SEBPAY_DEPOSIT_MAX) {
    throw new HttpError('invalid-argument', `Montant entre ${SEBPAY_DEPOSIT_MIN} et ${SEBPAY_DEPOSIT_MAX} FCFA.`);
  }
  const phone = normPhone(data.phone);
  if (!phone) throw new HttpError('invalid-argument', 'Numéro invalide (ex : 690000000).');
  const opKey = String(data.operator || '');
  const operator = sebpayOperatorCode(env, opKey);
  if (!operator) throw new HttpError('invalid-argument', 'Choisis Orange Money ou MTN MoMo.');

  const mine = await queryDocs(env, 'sebpayDeposits', eqFilter('uid', uid), 100);
  if (mine.filter((x) => x.status === 'pending').length >= SEBPAY_MAX_PENDING_DEPOSITS) {
    throw new HttpError('failed-precondition', 'Tu as déjà des recharges en attente. Valide-les sur ton téléphone ou patiente.');
  }
  const id = newId();
  let pseudo = '';
  await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    pseudo = typeof me.pseudo === 'string' ? me.pseudo : '';
    tx.write(`sebpayDeposits/${id}`, {
      create: true,
      set: { uid, name: pseudo, amount, phone, operator: opKey, status: 'pending' },
      serverTime: ['createdAt'],
    });
  });

  const body = {
    amount,
    currency: SEBPAY_CURRENCY,
    phone,
    operator,
    country: SEBPAY_COUNTRY,
    external_reference: 'D' + id,
    callback_url: String(env.SEBPAY_CALLBACK_URL || SEBPAY_CALLBACK),
  };
  if (pseudo) body.customer_name = pseudo.slice(0, 80);
  const otp = String(data.otp || '').replace(/\D/g, '');
  if (otp) body.otp_code = otp;

  const r = await sebpayCall(env, 'POST', '/collections', body);
  if (r.network || r.status >= 500) {
    // Réponse inconnue : la demande a peut-être été créée. On la laisse en attente (vérifiée ensuite).
    console.error('SebPay collect (réponse incertaine)', r.status, r.raw);
    return { id, status: 'pending', providerLink: null };
  }
  if (!r.ok) {
    console.error('SebPay collect', r.status, r.raw);
    await runTx(env, async (tx) =>
      tx.write(`sebpayDeposits/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] }),
    );
    if (sebpayHas(r, 'OTP_REQUIRED')) {
      throw new HttpError('failed-precondition', 'Cet opérateur demande un code OTP. Compose le code de ton opérateur puis réessaie.');
    }
    if (sebpayHas(r, 'AMOUNT_TOO_LOW')) throw new HttpError('invalid-argument', 'Montant trop faible pour cet opérateur.');
    if (sebpayHas(r, 'OPERATOR_MAINTENANCE')) {
      throw new HttpError('failed-precondition', "Cet opérateur est en maintenance. Réessaie plus tard ou choisis l'autre.");
    }
    if (sebpayHas(r, 'PAYMENT_DECLINED')) {
      throw new HttpError('failed-precondition', "L'opérateur a refusé la demande. Vérifie le numéro et l'opérateur choisis.");
    }
    if (r.status === 401 || r.status === 403) {
      await notifyAdmin(env, `⚠️ SebPay refuse nos clés (${r.status}). Vérifie SEBPAY_PUBLIC_KEY / SEBPAY_SECRET_KEY.`);
    }
    throw new HttpError('failed-precondition', sebpayMsg(r) || 'La demande de paiement a été refusée.');
  }
  const tx = String(r.data.transaction_id || '');
  if (tx) await runTx(env, async (t) => t.write(`sebpayDeposits/${id}`, { set: { sebpayTx: tx } }));
  const link = typeof r.data.provider_link === 'string' && r.data.provider_link ? r.data.provider_link : null;
  later(env, notifyAdmin(env, `🔔 Recharge lancée (${opKey === 'mtn' ? 'MTN MoMo' : 'Orange Money'})\n${pseudo || 'Un joueur'} · ${amount} FCFA · ${phone}\nEn attente de sa validation sur le téléphone.`));
  return { id, status: 'pending', providerLink: link };
}

/** Lit la collecte chez SebPay et crédite le solde (une seule fois). */
async function settleSebpayDepositCore(env, id) {
  const dep = await readDoc(env, `sebpayDeposits/${id}`);
  if (!dep) return { status: 'unknown' };
  if (dep.status !== 'pending') return { status: dep.status };
  const firstFlag = await isFirstDeposit(env, dep.uid);

  const r = await sebpayCall(env, 'GET', `/collections/${encodeURIComponent('D' + id)}`);
  if (!r.ok) {
    if (r.status === 404 && sebpayAgeMs(dep) > 15 * 60 * 1000) {
      await runTx(env, async (tx) => {
        const d = await tx.get(`sebpayDeposits/${id}`);
        if (d && d.status === 'pending') tx.write(`sebpayDeposits/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] });
      });
      return { status: 'failed' };
    }
    return { status: 'pending' };
  }
  const st = String(r.data.status || '').toLowerCase();
  if (st !== 'approved' && st !== 'rejected') return { status: 'pending' };

  const res = await runTx(env, async (tx) => {
    const d = await tx.get(`sebpayDeposits/${id}`);
    if (!d || d.status !== 'pending') return { status: d ? d.status : 'unknown' };
    if (st === 'rejected') {
      tx.write(`sebpayDeposits/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] });
      return { status: 'failed' };
    }
    const paid = Number(r.data.amount);
    const refOk = !r.data.external_reference || r.data.external_reference === 'D' + id;
    if (!refOk || (Number.isFinite(paid) && paid !== d.amount)) {
      tx.write(`sebpayDeposits/${id}`, { set: { status: 'mismatch', paidAmount: Number.isFinite(paid) ? paid : 0 }, serverTime: ['closedAt'] });
      return { status: 'mismatch', amount: d.amount, paid };
    }
    const tokens = d.amount * TOKENS_PER_XAF;
    await markFirstDeposit(tx, d.uid, d.amount, firstFlag);
    tx.write(`users/${d.uid}`, { incr: { balance: tokens } });
    tx.write(`sebpayDeposits/${id}`, {
      set: { status: 'credited', tokens, sebpayTx: String(r.data.transaction_id || d.sebpayTx || '') },
      serverTime: ['closedAt'],
    });
    return { status: 'credited', amount: d.amount };
  });
  if (res.status === 'credited') {
    later(env, notifyAdmin(env, `✅ Recharge créditée : ${res.amount} FCFA (D${id}).`));
  }
  if (res.status === 'mismatch') {
    await notifyAdmin(env, `⚠️ Recharge SebPay à vérifier : demandé ${res.amount}, reçu ${res.paid}. Référence D${id}.`);
  }
  return { status: res.status };
}

/** L'appli demande où en est sa recharge. */
async function sebpayDepositStatus({ uid, data, env }) {
  const id = idStr(data.id);
  const dep = id ? await readDoc(env, `sebpayDeposits/${id}`) : null;
  if (!dep || dep.uid !== uid) throw new HttpError('not-found', 'Recharge introuvable.');
  const r = await settleSebpayDeposit(env, id);
  const me = await readDoc(env, `users/${uid}`);
  return { status: r.status, balance: balanceOf(me) };
}

/** Retrait automatique : le solde est débité tout de suite, SebPay envoie l'argent. */
async function sebpayWithdrawRequest({ uid, data, env }) {
  if (!sebpayEnabled(env)) throw new HttpError('failed-precondition', 'Le retrait automatique est indisponible.');
  const amount = intOr(data.amount, -1);
  if (amount < SEBPAY_WITHDRAW_MIN) {
    throw new HttpError('invalid-argument', `Retrait automatique à partir de ${SEBPAY_WITHDRAW_MIN} FCFA.`);
  }
  if (amount > SEBPAY_WITHDRAW_MAX) {
    throw new HttpError('invalid-argument', `Retrait automatique limité à ${SEBPAY_WITHDRAW_MAX} FCFA. Pour plus, utilise le retrait manuel.`);
  }
  const phone = normPhone(data.phone);
  if (!phone) throw new HttpError('invalid-argument', 'Numéro invalide (ex : 690000000).');
  const opKey = String(data.operator || '');
  const operator = sebpayOperatorCode(env, opKey);
  if (!operator) throw new HttpError('invalid-argument', 'Choisis Orange Money ou MTN MoMo.');

  const mine = await queryDocs(env, 'sebpayPayouts', eqFilter('uid', uid), 100);
  if (mine.filter((x) => x.status === 'pending').length >= SEBPAY_MAX_PENDING_PAYOUTS) {
    throw new HttpError('failed-precondition', 'Tu as déjà des retraits en attente.');
  }
  const tokens = amount * TOKENS_PER_XAF;
  const id = newId();
  let pseudo = '';
  const balance = await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (balanceOf(me) < tokens) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    assertWagerDone(me);
    pseudo = typeof me.pseudo === 'string' ? me.pseudo : '';
    tx.write(`users/${uid}`, { incr: { balance: -tokens } });
    tx.write(`sebpayPayouts/${id}`, {
      create: true,
      set: { uid, name: pseudo, amount, tokens, phone, operator: opKey, status: 'pending' },
      serverTime: ['createdAt'],
    });
    return balanceOf(me) - tokens;
  });

  const r = await sebpayCall(env, 'POST', '/payouts', {
    recipient_name: (pseudo || 'Joueur Katika').slice(0, 180),
    phone,
    operator,
    country: SEBPAY_COUNTRY,
    amount,
    currency: SEBPAY_CURRENCY,
    external_reference: 'W' + id,
    callback_url: String(env.SEBPAY_CALLBACK_URL || SEBPAY_CALLBACK),
    description: 'Retrait Katika',
  });
  if (r.ok) {
    const tx = String(r.data.transaction_id || '');
    if (tx) await runTx(env, async (t) => t.write(`sebpayPayouts/${id}`, { set: { sebpayTx: tx } }));
    return { id, status: 'pending', balance };
  }
  if (r.network || r.status >= 500) {
    // Réponse inconnue : le retrait a peut-être été créé. Il reste en attente, vérifié ensuite.
    console.error('SebPay payout (réponse incertaine)', r.status, r.raw);
    return { id, status: 'pending', balance };
  }
  // Refus net : on rend les jetons.
  console.error('SebPay payout', r.status, r.raw);
  const back = await runTx(env, async (tx) => {
    const d = await tx.get(`sebpayPayouts/${id}`);
    if (!d || d.status !== 'pending') return false;
    tx.write(`users/${uid}`, { incr: { balance: tokens } });
    tx.write(`sebpayPayouts/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] });
    return true;
  });
  if (sebpayHas(r, 'INSUFFICIENT_BALANCE') || sebpayHas(r, 'PAYOUTS_FROZEN') || sebpayHas(r, 'PAYOUTS_LOCKED') || r.status === 401 || r.status === 403) {
    await notifyAdmin(env, `⚠️ Retrait SebPay refusé (${r.status}) : ${sebpayMsg(r) || 'solde SebPay insuffisant ou compte bloqué'}. Recharge ton compte SebPay.`);
    throw new HttpError('failed-precondition', 'Retrait automatique momentanément indisponible. Réessaie plus tard ou utilise le retrait manuel.');
  }
  if (sebpayHas(r, 'AMOUNT_TOO_LOW')) throw new HttpError('invalid-argument', 'Montant trop faible pour cet opérateur.');
  if (sebpayHas(r, 'PAYOUT_DECLINED')) {
    throw new HttpError('failed-precondition', "L'opérateur a refusé le retrait. Vérifie le numéro et l'opérateur choisis.");
  }
  void back;
  throw new HttpError('failed-precondition', sebpayMsg(r) || 'Le retrait a été refusé.');
}

/** Lit le payout chez SebPay : payé, ou échoué (jetons remboursés une seule fois). */
async function settleSebpayPayoutCore(env, id) {
  const p = await readDoc(env, `sebpayPayouts/${id}`);
  if (!p) return { status: 'unknown' };
  if (p.status !== 'pending') return { status: p.status };

  const r = await sebpayCall(env, 'GET', `/payouts/${encodeURIComponent('W' + id)}`);
  let st = '';
  if (r.ok) {
    st = String(r.data.status || '').toLowerCase();
  } else if (r.status === 404 && sebpayAgeMs(p) > 30 * 60 * 1000) {
    st = 'rejected'; // jamais créé chez SebPay
  }
  if (st !== 'approved' && st !== 'rejected') return { status: 'pending' };

  return runTx(env, async (tx) => {
    const d = await tx.get(`sebpayPayouts/${id}`);
    if (!d || d.status !== 'pending') return { status: d ? d.status : 'unknown' };
    if (st === 'approved') {
      tx.write(`sebpayPayouts/${id}`, { set: { status: 'paid' }, serverTime: ['closedAt'] });
      return { status: 'paid' };
    }
    tx.write(`users/${d.uid}`, { incr: { balance: intOr(d.tokens, 0) } });
    tx.write(`sebpayPayouts/${id}`, { set: { status: 'failed' }, serverTime: ['closedAt'] });
    return { status: 'failed' };
  });
}

/** Mes dernières recharges et retraits SebPay (met à jour ceux qui sont en attente). */
async function sebpayMine({ uid, env }) {
  const [dep, pay] = await Promise.all([
    queryDocs(env, 'sebpayDeposits', eqFilter('uid', uid), 60),
    queryDocs(env, 'sebpayPayouts', eqFilter('uid', uid), 60),
  ]);
  if (sebpayEnabled(env)) {
    const pd = dep.filter((x) => x.status === 'pending').slice(0, 3);
    const pp = pay.filter((x) => x.status === 'pending').slice(0, 3);
    try {
      for (const d of pd) d.status = (await settleSebpayDeposit(env, d.id)).status;
      for (const p of pp) p.status = (await settleSebpayPayout(env, p.id)).status;
    } catch (e) {
      console.error(e);
    }
  }
  const me = await readDoc(env, `users/${uid}`);
  return {
    deposits: dep.map(sebpayPublic).sort(byDateDesc('createdAt')).slice(0, 20),
    withdrawals: pay.map(sebpayPublic).sort(byDateDesc('createdAt')).slice(0, 20),
    balance: balanceOf(me),
  };
}

async function sebpayHmacHex(secret, raw) {
  const key = await crypto.subtle.importKey('raw', te.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, te.encode(raw)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, '0')).join('');
}

function sebpayEqual(a, b) {
  const x = String(a || '').toLowerCase();
  const y = String(b || '').toLowerCase();
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

/** Appelé par SebPay (sans connexion joueur). Signature vérifiée, puis lecture chez SebPay avant tout crédit. */
async function sebpayWebhook(request, env) {
  if (request.method !== 'POST') return new Response('POST requis', { status: 405 });
  if (!env.SEBPAY_SECRET_KEY) return new Response('non configuré', { status: 503 });
  const raw = await request.text();
  const expected = await sebpayHmacHex(env.SEBPAY_SECRET_KEY, raw);
  if (!sebpayEqual(expected, request.headers.get('x-sebpay-signature'))) {
    return new Response('bad signature', { status: 401 });
  }
  let p = {};
  try {
    p = JSON.parse(raw) || {};
  } catch (_) {
    return new Response('bad json', { status: 400 });
  }
  const ref = String(p.external_reference || '');
  const id = idStr(ref.slice(1));
  if (id) {
    try {
      if (ref[0] === 'D') await settleSebpayDeposit(env, id);
      else if (ref[0] === 'W') await settleSebpayPayout(env, id);
    } catch (e) {
      console.error(e);
      return new Response('error', { status: 500 });
    }
  }
  return new Response('ok');
}

// ======================================================================
// Point d'entrée
// ======================================================================

// ======================================================================
// Tournois (étape 1 : création, inscription payée, équipes, départ, annulation)
// ======================================================================
// Collections (accès réservé au serveur) :
//   tournaments/{id}            : l'événement
//   tournamentEntries/{tid_uid} : une inscription payée par joueur
//   tournamentTeams/{id}        : les duos du tournoi « Katika Tournament »

const TOURN_TEMPLATES = {
  katika: {
    title: 'Katika Tournament',
    fee: 2500,
    capacity: 64,
    teamSize: 2,
    prizes: [100000, 70000, 42000, 35000],
  },
  mondly: {
    title: 'Katika Mondly',
    fee: 2000,
    capacity: 32,
    teamSize: 1,
    prizes: [34500, 24000, 15050, 11000],
  },
};

function tournName(u) {
  return String((u && (u.pseudo || u.promoCode)) || 'Joueur').slice(0, 30);
}

function tournCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, (b) => chars[b % chars.length]).join('');
}

function tournTid(data) {
  const tid = idStr(data.tid);
  if (!tid) throw new HttpError('invalid-argument', 'Tournoi inconnu.');
  return tid;
}

/** Vérifie que le tournoi accepte encore des inscriptions. */
function tournOpenCheck(t, type) {
  if (!t) throw new HttpError('not-found', 'Tournoi introuvable.');
  if (t.status !== 'open') {
    throw new HttpError('failed-precondition', "Les inscriptions ne sont plus ouvertes.");
  }
  if (Date.now() >= intOr(t.regDeadline, 0)) {
    throw new HttpError('failed-precondition', "La date limite d'inscription est dépassée.");
  }
  if (type && t.type !== type) {
    throw new HttpError('failed-precondition', 'Ce tournoi ne fonctionne pas ainsi.');
  }
}

/** Administrateur : crée un tournoi à partir d'un modèle (katika ou mondly). */
async function adminTournamentCreate({ uid, data, env }) {
  requireAdmin(uid, env);
  const tpl = TOURN_TEMPLATES[String(data.type || '')];
  if (!tpl) throw new HttpError('invalid-argument', 'Type de tournoi inconnu.');
  const startAt = intOr(data.startAt, 0);
  const regDeadline = intOr(data.regDeadline, 0);
  const now = Date.now();
  if (startAt <= now) throw new HttpError('invalid-argument', 'La date de début doit être dans le futur.');
  if (regDeadline <= now || regDeadline > startAt) {
    throw new HttpError('invalid-argument', "La clôture des inscriptions doit être entre maintenant et le début.");
  }
  let fee = Math.max(100, intOr(data.fee, tpl.fee));
  let capacity = tpl.capacity;
  let prizes = tpl.prizes;
  let title = String(data.title || tpl.title).slice(0, 60);
  if (data.test === true) {
    // Tournoi d'essai : 4 joueurs, 100 FCFA, gains = total des inscriptions.
    fee = 100;
    capacity = 4;
    prizes = String(data.type) === 'katika' ? [250, 150, 0, 0] : [200, 100, 50, 50];
    title += ' (TEST)';
  }
  const id = newId();
  await runTx(env, async (tx) => {
    tx.write(`tournaments/${id}`, {
      create: true,
      set: {
        type: String(data.type),
        title,
        fee,
        capacity,
        teamSize: tpl.teamSize,
        prizes,
        startAt,
        regDeadline,
        status: 'open',
        taken: 0,
        paid: 0,
      },
      serverTime: ['createdAt'],
    });
  });
  return { id };
}

/** Liste des tournois + mes inscriptions. Clôture au passage les inscriptions échues. */
async function tournamentList({ uid, env }) {
  await accessToken(env);
  const now = Date.now();
  const open = await queryDocs(env, 'tournaments', eqFilter('status', 'open'), 30);
  for (const t of open) {
    if (intOr(t.regDeadline, 0) <= now) {
      try {
        await cancelTournament(env, t.id, 'deadline');
      } catch (e) {
        console.error('tournoi echeance', e);
      }
    }
  }
  for (const st of ['ready', 'running']) {
    const docs = await queryDocs(env, 'tournaments', eqFilter('status', st), 30);
    for (const t of docs) {
      try {
        if (st === 'ready') await startTournament(env, t.id, false);
        else await advanceTournament(env, t.id);
      } catch (e) {
        console.error('tournoi avance', e);
      }
    }
  }
  const out = [];
  for (const st of ['open', 'ready', 'running', 'finished', 'cancelled']) {
    const docs = await queryDocs(env, 'tournaments', eqFilter('status', st), st === 'open' || st === 'ready' || st === 'running' ? 30 : 8);
    for (const t of docs) out.push(t);
  }
  const live = (t) => t.status === 'open' || t.status === 'ready' || t.status === 'running';
  out.sort((a, b) => {
    if (live(a) !== live(b)) return live(a) ? -1 : 1;
    return live(a) ? intOr(a.startAt, 0) - intOr(b.startAt, 0) : intOr(b.startAt, 0) - intOr(a.startAt, 0);
  });
  const ids = new Set(out.map((t) => t.id));
  const mineAll = await queryDocs(env, 'tournamentEntries', eqFilter('uid', uid), 100);
  const mine = [];
  for (const e of mineAll) {
    if (e.status !== 'paid' || !ids.has(e.tid)) continue;
    let team = null;
    if (e.teamId) {
      const tm = await readDoc(env, `tournamentTeams/${e.teamId}`);
      if (tm && tm.status !== 'cancelled') {
        const leader = tm.leaderUid === uid;
        team = {
          id: e.teamId,
          name: tm.name || '',
          status: tm.status,
          leader,
          names: Array.isArray(tm.names) ? tm.names : [],
          code: leader && tm.status === 'pending' ? tm.inviteCode : '',
        };
      }
    }
    mine.push({ tid: e.tid, team });
  }
  const tournaments = out.map((t) => ({
    id: t.id,
    type: t.type,
    title: t.title,
    fee: intOr(t.fee, 0),
    capacity: intOr(t.capacity, 0),
    teamSize: intOr(t.teamSize, 1),
    prizes: Array.isArray(t.prizes) ? t.prizes : [],
    startAt: intOr(t.startAt, 0),
    regDeadline: intOr(t.regDeadline, 0),
    status: t.status,
    taken: intOr(t.taken, 0),
    paid: intOr(t.paid, 0),
    rounds: intOr(t.rounds, 0),
    placings: Array.isArray(t.placings) ? t.placings : [],
  }));
  const matchesMine = await myTournMatches(env, uid, ids);
  return { tournaments, mine, matches: matchesMine, now, admin: adminIds(env).includes(uid) };
}

/** Écrit l'inscription payée d'un joueur (appelé dans une transaction). */
function tournPay(tx, t, tid, uid, me, teamId) {
  const fee = intOr(t.fee, 0);
  if (balanceOf(me) < fee) throw new HttpError('failed-precondition', 'Solde insuffisant.');
  tx.write(`users/${uid}`, { incr: { balance: -fee } });
  tx.write(`tournamentEntries/${tid}_${uid}`, {
    set: { tid, uid, name: tournName(me), teamId: teamId || '', status: 'paid', fee },
    serverTime: ['createdAt'],
  });
}

/** Inscription individuelle (Katika Mondly). */
async function tournamentRegister({ uid, data, env }) {
  const tid = tournTid(data);
  return runTx(env, async (tx) => {
    const t = await tx.get(`tournaments/${tid}`);
    tournOpenCheck(t, 'mondly');
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const old = await tx.get(`tournamentEntries/${tid}_${uid}`);
    if (old && old.status === 'paid') throw new HttpError('failed-precondition', 'Tu es déjà inscrit.');
    if (intOr(t.taken, 0) >= intOr(t.capacity, 0)) {
      throw new HttpError('failed-precondition', 'Le tournoi est complet.');
    }
    tournPay(tx, t, tid, uid, me, '');
    const paid = intOr(t.paid, 0) + 1;
    const set = {};
    if (paid >= intOr(t.capacity, 0)) set.status = 'ready';
    tx.write(`tournaments/${tid}`, { incr: { taken: 1, paid: 1 }, set });
    return { balance: balanceOf(me) - intOr(t.fee, 0) };
  });
}

/** Katika Tournament : le chef d'équipe crée le duo, paie, et reçoit un code à donner à son partenaire. */
async function tournamentTeamCreate({ uid, data, env }) {
  const tid = tournTid(data);
  const code = tournCode();
  const teamId = newId();
  return runTx(env, async (tx) => {
    const t = await tx.get(`tournaments/${tid}`);
    tournOpenCheck(t, 'katika');
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const old = await tx.get(`tournamentEntries/${tid}_${uid}`);
    if (old && old.status === 'paid') throw new HttpError('failed-precondition', 'Tu es déjà inscrit.');
    if (intOr(t.taken, 0) + 2 > intOr(t.capacity, 0)) {
      throw new HttpError('failed-precondition', 'Plus de place pour une équipe.');
    }
    tournPay(tx, t, tid, uid, me, teamId);
    const nm = tournName(me);
    tx.write(`tournamentTeams/${teamId}`, {
      create: true,
      set: {
        tid,
        name: String(data.teamName || `Équipe ${nm}`).trim().slice(0, 30),
        leaderUid: uid,
        members: [uid],
        names: [nm],
        paid: 1,
        inviteCode: code,
        status: 'pending',
      },
      serverTime: ['createdAt'],
    });
    tx.write(`tournaments/${tid}`, { incr: { taken: 2, paid: 1 } });
    return { teamId, code, balance: balanceOf(me) - intOr(t.fee, 0) };
  });
}

/** Le partenaire rejoint le duo avec le code et paie sa part. */
async function tournamentTeamJoin({ uid, data, env }) {
  const code = String(data.code || '').trim().toUpperCase().slice(0, 12);
  if (!code) throw new HttpError('invalid-argument', "Entre le code d'équipe.");
  const found = await queryDocs(env, 'tournamentTeams', eqFilter('inviteCode', code), 5);
  const team0 = found.find((x) => x.status === 'pending');
  if (!team0) throw new HttpError('not-found', 'Code inconnu ou équipe déjà complète.');
  const tid = team0.tid;
  const teamId = team0.id;
  return runTx(env, async (tx) => {
    const t = await tx.get(`tournaments/${tid}`);
    tournOpenCheck(t, 'katika');
    const team = await tx.get(`tournamentTeams/${teamId}`);
    if (!team || team.status !== 'pending') {
      throw new HttpError('failed-precondition', 'Équipe déjà complète ou annulée.');
    }
    if (team.leaderUid === uid) {
      throw new HttpError('invalid-argument', 'Tu es déjà le chef de cette équipe.');
    }
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const old = await tx.get(`tournamentEntries/${tid}_${uid}`);
    if (old && old.status === 'paid') throw new HttpError('failed-precondition', 'Tu es déjà inscrit à ce tournoi.');
    tournPay(tx, t, tid, uid, me, teamId);
    tx.write(`tournamentTeams/${teamId}`, {
      set: {
        members: [team.leaderUid, uid],
        names: [...(Array.isArray(team.names) ? team.names : []), tournName(me)],
        paid: 2,
        status: 'complete',
      },
    });
    const paid = intOr(t.paid, 0) + 1;
    const set = {};
    if (paid >= intOr(t.capacity, 0)) set.status = 'ready';
    tx.write(`tournaments/${tid}`, { incr: { paid: 1 }, set });
    return { tid, balance: balanceOf(me) - intOr(t.fee, 0) };
  });
}

/** Désinscription (avant la date limite) : remboursement intégral. */
async function tournamentLeave({ uid, data, env }) {
  const tid = tournTid(data);
  return runTx(env, async (tx) => {
    const t = await tx.get(`tournaments/${tid}`);
    if (!t) throw new HttpError('not-found', 'Tournoi introuvable.');
    if (!(t.status === 'open' || t.status === 'ready') || Date.now() >= intOr(t.regDeadline, 0)) {
      throw new HttpError('failed-precondition', 'Tu ne peux plus te désinscrire.');
    }
    const me = await tx.get(`users/${uid}`);
    const en = await tx.get(`tournamentEntries/${tid}_${uid}`);
    if (!me || !en || en.status !== 'paid') {
      throw new HttpError('failed-precondition', "Tu n'es pas inscrit.");
    }
    const fee = intOr(en.fee, intOr(t.fee, 0));
    const refund = (u, e, who) => {
      tx.write(`users/${who}`, { incr: { balance: fee } });
      tx.write(`tournamentEntries/${tid}_${who}`, { set: { status: 'refunded' } });
    };
    let dTaken = -1;
    let dPaid = -1;
    if (!en.teamId) {
      refund(me, en, uid);
    } else {
      const team = await tx.get(`tournamentTeams/${en.teamId}`);
      if (!team) throw new HttpError('not-found', 'Équipe introuvable.');
      if (team.leaderUid === uid) {
        refund(me, en, uid);
        dTaken = -2;
        if (team.status === 'complete') {
          const other = (team.members || []).find((m) => m !== uid);
          const oe = other ? await tx.get(`tournamentEntries/${tid}_${other}`) : null;
          if (oe && oe.status === 'paid') {
            tx.write(`users/${other}`, { incr: { balance: fee } });
            tx.write(`tournamentEntries/${tid}_${other}`, { set: { status: 'refunded' } });
            dPaid = -2;
          }
        }
        tx.write(`tournamentTeams/${en.teamId}`, { set: { status: 'cancelled' } });
      } else {
        refund(me, en, uid);
        dTaken = 0;
        tx.write(`tournamentTeams/${en.teamId}`, {
          set: {
            members: [team.leaderUid],
            names: [(Array.isArray(team.names) && team.names[0]) || ''],
            paid: 1,
            status: 'pending',
          },
        });
      }
    }
    const set = t.status === 'ready' ? { status: 'open' } : {};
    tx.write(`tournaments/${tid}`, { incr: { taken: dTaken, paid: dPaid }, set });
    return { refunded: fee, balance: balanceOf(me) + fee };
  });
}

// ======================================================================
// Tournois, étape 2 : tableau, parties Ludo automatiques, résultats, gains
// ======================================================================
// tournamentMatches/{id} : une table (Mondly : 4 joueurs) ou un match
//   (Katika : 2 équipes de 2). Chaque match crée une partie Ludo dans « games »
//   (sans mise : les frais d'inscription forment la cagnotte du tournoi).

const MATCH_MAX_MS = 60 * 60 * 1000; // au-delà : le serveur tranche à la progression

function cryptoShuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function arrayContainsFilter(field, value) {
  return {
    fieldFilter: { field: { fieldPath: field }, op: 'ARRAY_CONTAINS', value: toFs(value) },
  };
}

function pawnsProgress(g, c) {
  const p = g['p' + c];
  return Array.isArray(p) ? p.reduce((s, x) => s + Math.max(0, intOr(x, 0)), 0) : 0;
}

function pawnsAllHome(g, c) {
  const p = g['p' + c];
  return Array.isArray(p) && p.length > 0 && p.every((x) => x === 56);
}

/** Document « games » d'une table : 4 places, sans mise, salle privée. */
function tournGameDoc(t, tid, mid, seats, teamMode) {
  const pawns = () => [-1, -1, -1, -1];
  return {
    hostUid: seats[0].uid,
    hostName: seats[0].name,
    maxPlayers: 4,
    pawnCount: 4,
    doorSafe: true,
    starSafe: true,
    startOut: false,
    startDoor: false,
    autoSecs: 10,
    private: true,
    teamMode,
    capturePay: 0,
    stake: 0,
    paid: [],
    pot: 0,
    partners: teamMode ? [2, 3, 0, 1] : [-1, -1, -1, -1],
    invites: [],
    code: tournCode(),
    status: 'playing',
    players: seats.map((s) => ({ uid: s.uid, name: s.name })),
    uids: seats.map((s) => s.uid),
    p0: pawns(),
    p1: pawns(),
    p2: pawns(),
    p3: pawns(),
    cur: 0,
    hasRolled: false,
    dice: 1,
    lastRoll: [1, 1, 1, 1],
    msg: 'Touche ton dé ou glisse-le pour le lancer !',
    over: false,
    writer: '',
    rev: 0,
    tournamentId: tid,
    matchId: mid,
    finishTarget: t.type === 'mondly' ? 2 : 1,
    finishOrder: [],
  };
}

/** Crée une table / un match et sa partie Ludo.
 *  spec : { round, idx, kind, players:[{uid,name}×4] }  (Mondly)
 *      ou { round, idx, kind, teams:[{id,name,uids,names}×2] } (Katika) */
async function createTournMatch(env, t, tid, spec) {
  const mid = newId();
  const gid = newGameId();
  let seats;
  const base = { tid, round: spec.round, idx: spec.idx, kind: spec.kind, mode: t.type };
  const mdoc = { ...base, gameId: gid, status: 'playing', startedMs: Date.now() };
  if (t.type === 'katika') {
    const [A, B] = spec.teams;
    seats = [
      { uid: A.uids[0], name: A.names[0] },
      { uid: B.uids[0], name: B.names[0] },
      { uid: A.uids[1], name: A.names[1] },
      { uid: B.uids[1], name: B.names[1] },
    ];
    mdoc.teams = spec.teams;
  } else {
    seats = cryptoShuffle(spec.players);
    mdoc.players = seats;
  }
  mdoc.uids = seats.map((s) => s.uid);
  await runTx(env, async (tx) => {
    tx.write(`games/${gid}`, {
      create: true,
      set: tournGameDoc(t, tid, mid, seats, t.type === 'katika'),
      serverTime: ['createdAt', 'startedAt'],
    });
    tx.write(`tournamentMatches/${mid}`, { create: true, set: mdoc });
  });
  return { id: mid, ...mdoc };
}

/** Passe un tournoi « ready » en « running » et crée le premier tour. */
async function startTournament(env, tid, force) {
  let t = null;
  await runTx(env, async (tx) => {
    const cur = await tx.get(`tournaments/${tid}`);
    if (!cur) throw new HttpError('not-found', 'Tournoi introuvable.');
    if (cur.status !== 'ready') throw new HttpError('failed-precondition', "Le tournoi n'est pas complet.");
    if (!force && Date.now() < intOr(cur.startAt, 0)) return;
    const cap = intOr(cur.capacity, 0);
    const first = cur.type === 'katika' ? cap / 2 : cap / 4;
    const rounds = cur.type === 'katika' ? Math.log2(first) : Math.log2(first) + 1;
    tx.write(`tournaments/${tid}`, {
      set: { status: 'running', rounds, bracketBuilt: false },
      serverTime: ['runningAt'],
    });
    t = { ...cur, status: 'running', rounds };
  });
  if (!t) return false;
  await buildBracket(env, tid, t);
  return true;
}

async function buildBracket(env, tid, t) {
  const existing = await queryDocs(env, 'tournamentMatches', eqFilter('tid', tid), 5);
  if (existing.length === 0) {
    if (t.type === 'katika') {
      const teams = (await queryDocs(env, 'tournamentTeams', eqFilter('tid', tid), 100))
        .filter((x) => x.status === 'complete')
        .map((x) => ({
          id: x.id,
          name: x.name || '',
          uids: x.members,
          names: x.names,
        }));
      const sh = cryptoShuffle(teams);
      for (let i = 0; i + 1 < sh.length; i += 2) {
        await createTournMatch(env, t, tid, { round: 1, idx: i / 2, kind: 'main', teams: [sh[i], sh[i + 1]] });
      }
    } else {
      const ps = (await queryDocs(env, 'tournamentEntries', eqFilter('tid', tid), 300))
        .filter((e) => e.status === 'paid')
        .map((e) => ({ uid: e.uid, name: e.name || '' }));
      const sh = cryptoShuffle(ps);
      for (let i = 0; i + 3 < sh.length; i += 4) {
        await createTournMatch(env, t, tid, { round: 1, idx: i / 4, kind: 'main', players: sh.slice(i, i + 4) });
      }
    }
  }
  await runTx(env, async (tx) => {
    tx.write(`tournaments/${tid}`, { set: { bracketBuilt: true } });
  });
}

/** Résultat Katika : numéro (0/1) de l'équipe gagnante. Les places 0 et 2 = équipe A, 1 et 3 = équipe B. */
function katikaWinnerTeam(g) {
  const forf = Array.isArray(g.forfeited) ? g.forfeited : [];
  let w = intOr(g.winner, -1);
  if (w < 0) {
    const f = [0, 1, 2, 3].find((c) => !forf.includes(c) && pawnsAllHome(g, c));
    w = f === undefined ? -1 : f;
  }
  if (w >= 0) return w % 2;
  const sc = [0, 0];
  for (const c of [0, 1, 2, 3]) if (!forf.includes(c)) sc[c % 2] += pawnsProgress(g, c);
  if (sc[0] === sc[1]) return crypto.getRandomValues(new Uint8Array(1))[0] % 2;
  return sc[0] > sc[1] ? 0 : 1;
}

/** Résultat Mondly : couleurs classées. Arrivés dans l'ordre, puis les autres selon leur progression. */
function mondlyRanking(g) {
  const forf = Array.isArray(g.forfeited) ? g.forfeited : [];
  const fo = (Array.isArray(g.finishOrder) ? g.finishOrder : []).map((x) => intOr(x, -1));
  const order = [];
  for (const c of fo) if (c >= 0 && c < 4 && !order.includes(c) && pawnsAllHome(g, c)) order.push(c);
  for (const c of [0, 1, 2, 3]) {
    if (!order.includes(c) && !forf.includes(c) && pawnsAllHome(g, c)) order.push(c);
  }
  const rest = [0, 1, 2, 3]
    .filter((c) => !order.includes(c))
    .sort((a, b) => {
      const sa = forf.includes(a) ? -1 : pawnsProgress(g, a);
      const sb = forf.includes(b) ? -1 : pawnsProgress(g, b);
      return sb - sa;
    });
  return [...order, ...rest];
}

/** Fait avancer un tournoi en cours : enregistre les parties finies, crée les matchs suivants, paie les gains. */
async function advanceTournament(env, tid) {
  const t = await readDoc(env, `tournaments/${tid}`);
  if (!t || t.status !== 'running') return;
  if (!t.bracketBuilt) {
    await buildBracket(env, tid, t);
  }
  const matches = await queryDocs(env, 'tournamentMatches', eqFilter('tid', tid), 200);
  const rounds = intOr(t.rounds, 1);
  const now = Date.now();

  for (const m of matches) {
    if (m.status !== 'playing') continue;
    const g = await readDoc(env, `games/${m.gameId}`);
    if (!g) continue;
    let over = g.over === true;
    if (!over && now - intOr(m.startedMs, now) > MATCH_MAX_MS) {
      over = true;
      await runTx(env, async (tx) => {
        tx.write(`games/${m.gameId}`, { set: { over: true, status: 'finished', msg: 'Temps écoulé : décision du serveur.' } });
      });
    }
    if (!over) continue;
    const res = { status: 'done' };
    if (m.mode === 'katika') {
      const wt = katikaWinnerTeam(g);
      res.winnerTeam = wt;
      res.advance = m.teams[wt].uids;
    } else {
      const rk = mondlyRanking(g).map((c) => m.players[c]);
      res.ranking = rk;
      res.advance = [rk[0].uid, rk[1].uid];
    }
    await runTx(env, async (tx) => {
      tx.write(`tournamentMatches/${m.id}`, { set: res, serverTime: ['doneAt'] });
    });
    Object.assign(m, res);
  }

  const find = (round, idx, kind) => matches.find((x) => x.round === round && x.idx === idx && x.kind === kind);
  const winnerTeam = (m) => m.teams[m.winnerTeam];
  const loserTeam = (m) => m.teams[1 - m.winnerTeam];

  for (let r = 1; r < rounds; r++) {
    for (let j = 0; ; j++) {
      const a = find(r, j * 2, 'main');
      const b = find(r, j * 2 + 1, 'main');
      if (!a || !b) break;
      if (a.status !== 'done' || b.status !== 'done') continue;
      if (find(r + 1, j, 'main')) continue;
      let nm;
      if (t.type === 'katika') {
        nm = await createTournMatch(env, t, tid, { round: r + 1, idx: j, kind: 'main', teams: [winnerTeam(a), winnerTeam(b)] });
      } else {
        const ps = [...a.ranking.slice(0, 2), ...b.ranking.slice(0, 2)];
        nm = await createTournMatch(env, t, tid, { round: r + 1, idx: j, kind: 'main', players: ps });
      }
      matches.push(nm);
    }
  }
  // Katika : petite finale entre les deux perdants des demi-finales.
  if (t.type === 'katika' && rounds >= 2 && !find(rounds, 0, 'third')) {
    const s0 = find(rounds - 1, 0, 'main');
    const s1 = find(rounds - 1, 1, 'main');
    if (s0 && s1 && s0.status === 'done' && s1.status === 'done') {
      const nm = await createTournMatch(env, t, tid, { round: rounds, idx: 0, kind: 'third', teams: [loserTeam(s0), loserTeam(s1)] });
      matches.push(nm);
    }
  }

  const fin = find(rounds, 0, 'main');
  const third = find(rounds, 0, 'third');
  if (fin && fin.status === 'done' && (t.type === 'mondly' || rounds === 1 || (third && third.status === 'done'))) {
    await finishTournament(env, tid, t, fin, third);
  }
}

/** Calcule le classement final et verse les gains (une seule fois). */
async function finishTournament(env, tid, t, fin, third) {
  const prizes = (Array.isArray(t.prizes) ? t.prizes : []).map((x) => intOr(x, 0));
  const places = []; // { place, label, uids }
  if (t.type === 'katika') {
    places.push({ place: 1, label: fin.teams[fin.winnerTeam].name, uids: fin.teams[fin.winnerTeam].uids });
    places.push({ place: 2, label: fin.teams[1 - fin.winnerTeam].name, uids: fin.teams[1 - fin.winnerTeam].uids });
    if (third) {
      places.push({ place: 3, label: third.teams[third.winnerTeam].name, uids: third.teams[third.winnerTeam].uids });
      places.push({ place: 4, label: third.teams[1 - third.winnerTeam].name, uids: third.teams[1 - third.winnerTeam].uids });
    }
  } else {
    fin.ranking.forEach((p, i) => places.push({ place: i + 1, label: p.name, uids: [p.uid] }));
  }
  let paid = false;
  await runTx(env, async (tx) => {
    const cur = await tx.get(`tournaments/${tid}`);
    if (!cur || cur.status !== 'running') return;
    for (const pl of places) {
      const total = prizes[pl.place - 1] || 0;
      if (total <= 0) continue;
      const each = Math.floor(total / pl.uids.length);
      for (const u of pl.uids) {
        tx.write(`users/${u}`, { incr: { balance: each } });
        tx.write(`tournamentPayouts/${newId()}`, {
          create: true,
          set: { tid, uid: u, place: pl.place, amount: each },
          serverTime: ['createdAt'],
        });
      }
    }
    tx.write(`tournaments/${tid}`, {
      set: { status: 'finished', placings: places.map((p) => ({ place: p.place, label: p.label, uids: p.uids })) },
      serverTime: ['finishedAt'],
    });
    paid = true;
  });
  if (paid) {
    await notifyAdmin(env, `Tournoi « ${t.title} » terminé. Vainqueur : ${places[0] ? places[0].label : '?'}. Gains versés.`).catch(() => {});
  }
}

/** Administrateur : démarre tout de suite un tournoi complet (sans attendre l'heure prévue). */
async function adminTournamentStart({ uid, data, env }) {
  requireAdmin(uid, env);
  await accessToken(env);
  const ok = await startTournament(env, tournTid(data), true);
  return { started: ok };
}

/** Mes tables (en cours et récentes) pour la liste des tournois. */
async function myTournMatches(env, uid, ids) {
  const list = await queryDocs(env, 'tournamentMatches', arrayContainsFilter('uids', uid), 60);
  return list
    .filter((m) => ids.has(m.tid))
    .map((m) => ({
      tid: m.tid,
      id: m.id,
      gameId: m.gameId,
      round: intOr(m.round, 1),
      kind: m.kind,
      status: m.status,
      advanced: Array.isArray(m.advance) && m.advance.includes(uid),
      startedMs: intOr(m.startedMs, 0),
    }))
    .sort((a, b) => b.startedMs - a.startedMs);
}

/** Annule un tournoi et rembourse tous les inscrits payés (reprise possible si interrompu). */
async function cancelTournament(env, tid, why) {
  let announce = false;
  await runTx(env, async (tx) => {
    const t = await tx.get(`tournaments/${tid}`);
    if (!t) throw new HttpError('not-found', 'Tournoi introuvable.');
    if (t.status === 'cancelled') return;
    if (t.status === 'running' || t.status === 'finished') {
      throw new HttpError('failed-precondition', 'Ce tournoi a déjà commencé.');
    }
    if (why === 'deadline' && t.status !== 'open') return; // complet : il peut démarrer
    tx.write(`tournaments/${tid}`, { set: { status: 'cancelled', cancelReason: why } });
    announce = true;
  });
  const t2 = await readDoc(env, `tournaments/${tid}`);
  if (!t2 || t2.status !== 'cancelled') return { refunded: 0 };
  const entries = await queryDocs(env, 'tournamentEntries', eqFilter('tid', tid), 300);
  let refunded = 0;
  for (const e of entries) {
    if (e.status !== 'paid') continue;
    const ok = await runTx(env, async (tx) => {
      const en = await tx.get(`tournamentEntries/${tid}_${e.uid}`);
      if (!en || en.status !== 'paid') return false;
      const fee = intOr(en.fee, intOr(t2.fee, 0));
      tx.write(`users/${e.uid}`, { incr: { balance: fee } });
      tx.write(`tournamentEntries/${tid}_${e.uid}`, { set: { status: 'refunded' } });
      return true;
    });
    if (ok) refunded++;
  }
  const teams = await queryDocs(env, 'tournamentTeams', eqFilter('tid', tid), 100);
  for (const tm of teams) {
    if (tm.status === 'cancelled') continue;
    await runTx(env, async (tx) => {
      tx.write(`tournamentTeams/${tm.id}`, { set: { status: 'cancelled' } });
    });
  }
  if (announce) {
    await notifyAdmin(
      env,
      `Tournoi « ${t2.title} » annulé (${why === 'deadline' ? 'pas assez d\'inscrits' : 'décision admin'}) — ${refunded} joueur(s) remboursé(s).`,
    ).catch(() => {});
  }
  return { refunded };
}

async function adminTournamentCancel({ uid, data, env }) {
  requireAdmin(uid, env);
  await accessToken(env);
  return cancelTournament(env, tournTid(data), 'admin');
}

/** Administrateur : liste des inscrits payés d'un tournoi. */
async function adminTournamentEntries({ uid, data, env }) {
  requireAdmin(uid, env);
  await accessToken(env);
  const tid = tournTid(data);
  const list = await queryDocs(env, 'tournamentEntries', eqFilter('tid', tid), 300);
  return {
    entries: list
      .filter((e) => e.status === 'paid')
      .map((e) => ({ uid: e.uid, name: e.name || '', teamId: e.teamId || '' })),
  };
}

// ======================================================================
// Cartes en ligne : TIAH et BOUBAYAH (2 à 6 joueurs)
// ======================================================================
// cards/{id} : une manche = un document (mise et règlement par settleGame).
//   game ('tiah'|'boubayah'), hostUid, dealerUid, code, isPublic, stake, pot,
//   maxPlayers, status ('waiting'|'playing'|'finished'|'cancelled'),
//   players [{uid,name}], uids, paid, order (ordre des sièges de la manche précédente),
//   round, prevId, nextId, createdAtMs,
//   ... en jeu : deck, hands | plain+bouba, first, seq, turnIdx, opened, turnAt,
//   ... fin : over, winnerUids, fomekou, nextDealerUid.
// Le serveur mélange, distribue et garde les cartes ; chaque joueur ne reçoit que
// ce qu'il a le droit de voir (cardsView). Un joueur inactif est joué automatiquement
// après CARDS_TURN_MS (l'ouverture est la seule action possible).

const CARDS_TURN_MS = 10000; // 10 s par joueur et par action, pour tous les jeux de cartes
const CARDS_MAX_OPEN_PER_HOST = 3;
const CARDS_START_AFTER_MS = 120000;

const cardVal = (c) => Math.floor(c / 4);
/** Jeux en ligne seulement, 2 x M bloqués, position obligatoire à 3+ joueurs. */
const isFl = (g) => g === 'fapfap' || g === 'anticote' || g === 'tchek'; // en ligne seulement, position à 3+ joueurs
const isEsc2 = (g) => g === 'fapfap' || g === 'anticote'; // 2 x M bloqués

function cardsDeck(game) {
  const top = game === 'tiah' || game === 'anticote' ? 11 : 10;
  const d = [];
  if (game === 'fapfap') {
    // 31 cartes : 3 à 10 dans les 4 familles, sans le 10 de pique (famille 0).
    for (let v = 3; v <= 10; v++) for (let s = 0; s < 4; s++) if (!(v === 10 && s === 0)) d.push(v * 4 + s);
    for (let i = d.length - 1; i > 0; i--) {
      const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
      [d[i], d[j]] = [d[j], d[i]];
    }
    return d;
  }
  // TIAH : l'as de carreau est retiré (3 as seulement), donc deux joueurs ne peuvent pas avoir TOUCX ensemble.
  for (let v = 3; v <= top; v++) for (let s = 0; s < 4; s++) if (!((game === 'tiah' || game === 'anticote') && v === 11 && s === 2)) d.push(v * 4 + s);
  for (let i = d.length - 1; i > 0; i--) {
    const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [d[i], d[j]] = [d[j], d[i]];
  }
  return d;
}

function cardsGameOf(v) {
  if (v !== 'tiah' && v !== 'boubayah' && v !== 'fapfap' && v !== 'anticote' && v !== 'tchek') throw new HttpError('invalid-argument', 'Jeu inconnu.');
  return v;
}

/** FAP-FAP et ANTI-COTE démarrent à 50 FCFA ; les autres jeux de cartes à MIN_STAKE. */
const CARDS_MIN_STAKE_LOW = 50;
function cardsMinStake(game) {
  return game === 'fapfap' || game === 'anticote' ? CARDS_MIN_STAKE_LOW : MIN_STAKE;
}

function cardsStakeOf(data, game) {
  const stake = intOr(data.stake, 0);
  const min = cardsMinStake(game);
  if (stake !== 0 && (stake < min || stake > MAX_STAKE)) {
    throw new HttpError('invalid-argument', `Mise : 0 (gratuit) ou entre ${min} et ${MAX_STAKE} FCFA.`);
  }
  return stake;
}

const cardsTotal = (hand) => (hand || []).reduce((a, c) => a + cardVal(c), 0);
/** TOUCX : deux as en main (22) ; bat tout, même 21, et ne peut jamais être égalé. */
const cardsIsToucx = (hand) => (hand || []).length === 2 && (hand || []).every((c) => cardVal(c) === 11);
const cardsBoubaTotal = (d, uid) => ((d.bouba && d.bouba[uid]) || []).reduce((a, c) => a + cardVal(c), 0);
const MILLION_BOOST_PERCENT = 6; // chance par joueur de recevoir MILLION à la distribution (≈1 % sans ce réglage)
const cardsIsFomekou = (d, uid) => {
  const b = (d.bouba && d.bouba[uid]) || [];
  return b.length === 2 && cardVal(b[0]) === 3 && cardVal(b[1]) === 3;
};

// ----------------------------------------------------------------------
// FAP-FAP (2 à 4 joueurs) : 31 cartes (3..10, sans le 10 de pique), 5 cartes chacun
// (3 puis 2), 5 plis. Il faut fournir la famille demandée si on peut ; le plus haut de
// la famille demandée gagne le pli et entame le suivant. Mise bloquée 2 x M ;
// Corat = gain doublé (voir settleGameCore).
// ----------------------------------------------------------------------
const FAP_TURN_MS = 10000; // 10 s par carte
// Anti-triche Fap-Fap : position obligatoire, 150 m minimum entre 2 joueurs d'une même table.
const FAP_MIN_DIST_M = 150;
const FAP_MAX_ACC_M = 100; // précision GPS exigée
const FAP_LOC_FRESH_MS = 120000; // position à jour au lancement de la manche

/** Position envoyée par l'appli : { lat, lng, acc }. Refuse l'absence de position. */
function fapLoc(data) {
  const l = data && data.loc;
  const lat = Number(l && l.lat);
  const lng = Number(l && l.lng);
  const acc = Number(l && l.acc);
  if (!l || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) {
    throw new HttpError('failed-precondition', 'GEO_REQUIRED');
  }
  if (!Number.isFinite(acc) || acc > FAP_MAX_ACC_M) {
    throw new HttpError('failed-precondition', `Position trop imprécise (${Math.round(acc) || '?'} m). Active le GPS (localisation précise), sors si tu es dans un bâtiment et réessaie.`);
  }
  return { lat, lng, acc: Math.round(acc), ms: Date.now() };
}

/** Distance en mètres entre deux points (haversine). */
function geoDistM(a, b) {
  const R = 6371000;
  const rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

/** Vrai si `loc` est à moins de 150 m d'un AUTRE joueur de la salle. */
function fapTooClose(locs, uid, loc) {
  for (const [u, o] of Object.entries(locs || {})) {
    if (u === uid || !o) continue;
    if (geoDistM(loc, o) < FAP_MIN_DIST_M) return true;
  }
  return false;
}
const FAP_CLOSE_MSG = 'Tu es trop près d\'un autre joueur de cette table (minimum 150 m entre deux joueurs).';
const cardsTurnMs = (d) => (d && (d.game === 'fapfap' || d.game === 'anticote') ? FAP_TURN_MS : CARDS_TURN_MS);
const cardSuit = (c) => c % 4;

/** Combinaison gagnante d'une main de 5 cartes (ou null).
 *  Ordre de force : 4 sept (Corat) > total 16 (Corat) > 3 sept > 4 cartes du même
 *  numéro (le plus petit numéro gagne) > total <= 21. rank : plus petit = plus fort. */
function fapCombo(hand) {
  const vals = (hand || []).map(cardVal);
  if (vals.length !== 5) return null;
  const total = vals.reduce((a, b) => a + b, 0);
  const cnt = {};
  for (const v of vals) cnt[v] = (cnt[v] || 0) + 1;
  if ((cnt[7] || 0) >= 4) return { corat: true, rule: 'four7', rank: 0 };
  if (total === 16 && cnt[3] === 4 && cnt[4] === 1) return { corat: true, rule: 'sum16', rank: 1 };
  let four = 0;
  for (const k of Object.keys(cnt)) if (cnt[k] >= 4 && (!four || Number(k) < four)) four = Number(k);
  if ((cnt[7] || 0) >= 3) return { corat: false, rule: 'three7', rank: 2 };
  if (four) return { corat: false, rule: 'four', rank: 10 + four, value: four };
  if (total <= 21) return { corat: false, rule: 'le21', rank: 200, total };
  return null;
}

/** Vainqueur par combinaison à la distribution : le meilleur rang, puis
 *  1er joueur après le distributeur (ordre de seq). */
function fapDealWinner(hands, seq) {
  let best = null;
  seq.forEach((u, i) => {
    const c = fapCombo(hands[u]);
    if (!c) return;
    const key = [0, c.rank, i];
    if (!best || key[0] < best.key[0] || (key[0] === best.key[0] && (key[1] < best.key[1] || (key[1] === best.key[1] && key[2] < best.key[2])))) {
      best = { uid: u, combo: c, key };
    }
  });
  return best;
}

function fapLegal(hand, trick) {
  if (!trick || !trick.length) return [...hand];
  const lead = cardSuit(trick[0].card);
  const same = hand.filter((c) => cardSuit(c) === lead);
  return same.length ? same : [...hand];
}

/** Prochain joueur à jouer dans le pli (ceux « en passe » sont sautés) ; -1 si le pli est complet. */
function fapNextIdx(d, trick, passedUids) {
  const seq = d.seq || [];
  const leader = intOr(d.leaderIdx, 0);
  for (let k = 0; k < seq.length; k++) {
    const idx = (leader + k) % seq.length;
    const u = seq[idx];
    if (!trick.some((t) => t.uid === u) && !passedUids.includes(u)) return idx;
  }
  return -1;
}

/** Joue la carte `card` pour `uid`. Renvoie le patch Firestore. */
function fapPlay(d, uid, card) {
  const seq = d.seq || [];
  const hand = [...((d.hands && d.hands[uid]) || [])];
  const idx = hand.indexOf(card);
  if (idx < 0) throw new HttpError('failed-precondition', "Cette carte n'est pas dans ta main.");
  const trick = Array.isArray(d.trick) ? [...d.trick] : [];
  if (!fapLegal(hand, trick).includes(card)) {
    throw new HttpError('failed-precondition', 'Tu dois jouer la famille demandée.');
  }
  hand.splice(idx, 1);
  trick.push({ uid, card });
  const hands = { ...(d.hands || {}), [uid]: hand };
  const tbl = { ...(d.tbl || {}) };
  tbl[uid] = [...(tbl[uid] || []), card];
  return fapAfter(d, { hands, trick, tbl, turnAt: Date.now() });
}

/** Suite d'un coup : joueur suivant, ou fin du pli. Les joueurs « en passe » jouent leur carte
 *  gardée à la toute fin du pli (elle ne peut pas gagner), puis le gagnant entame. */
function fapAfter(d, patch) {
  const seq = d.seq || [];
  const passed = Array.isArray(d.passed) ? d.passed : [];
  const nxt = fapNextIdx(d, patch.trick, passed.map((p) => p.uid));
  if (nxt >= 0) {
    patch.turnIdx = nxt;
    // Dernière carte (une seule carte en main) : elle part toute seule dès que le joueur
    // précédent a joué (aucun choix possible). Sauf carte déjà jouée d'avance.
    const nu = seq[nxt];
    const nh = (patch.hands && patch.hands[nu]) || [];
    if (nh.length === 1 && !(d.early && d.early.uid === nu)) {
      const p2 = fapPlay({ ...d, ...patch }, nu, nh[0]);
      return { ...patch, ...p2 };
    }
    return patch;
  }
  const hands = patch.hands;
  const trick = patch.trick;
  const tbl = patch.tbl;
  for (const p of passed) {
    hands[p.uid] = (hands[p.uid] || []).filter((c) => c !== p.card);
    trick.push({ uid: p.uid, card: p.card });
    tbl[p.uid] = [...(tbl[p.uid] || []), p.card];
  }
  patch.passed = [];
  // pli complet : le plus haut de la famille demandée l'emporte
  const lead = cardSuit(trick[0].card);
  let win = trick[0];
  for (const p of trick) if (cardSuit(p.card) === lead && cardVal(p.card) > cardVal(win.card)) win = p;
  patch.prevTrick = { plays: trick, winner: win.uid };
  patch.trick = [];
  patch.trickNo = intOr(d.trickNo, 0) + 1;
  patch.leaderIdx = seq.indexOf(win.uid);
  patch.turnIdx = patch.leaderIdx;
  patch.early = null;
  if (patch.trickNo >= 5 || Object.values(hands).every((h) => h.length === 0)) {
    Object.assign(patch, {
      over: true,
      finishedMs: Date.now(),
      winnerUids: [win.uid],
      corat: cardVal(win.card) === 3,
      fapRule: cardVal(win.card) === 3 ? 'last3' : 'last',
      nextDealerUid: win.uid,
    });
    return patch;
  }
  // Le gagnant du pli entame : sa carte jouée d'avance (après un 10) puis sa dernière carte
  // (une seule carte en main) partent automatiquement.
  const lh = hands[win.uid] || [];
  const ea = d.early && d.early.uid === win.uid && lh.includes(d.early.card) ? d.early.card : -1;
  const auto = ea >= 0 ? ea : lh.length === 1 ? lh[0] : -1;
  if (auto >= 0) {
    const p2 = fapPlay({ ...d, ...patch, passed: [], early: null }, win.uid, auto);
    return { ...patch, ...p2, early: null };
  }
  return patch;
}

/** Après avoir joué un 10 de la famille demandée (le pli est gagné), cartes de la même
 *  famille que le joueur peut déjà jouer pour le pli suivant, sans attendre les adversaires. */
function fapEarlyOptions(d, uid) {
  if (!d || d.game !== 'fapfap' || d.status !== 'playing' || d.over === true) return [];
  const trick = Array.isArray(d.trick) ? d.trick : [];
  if (!trick.length || d.early) return [];
  const lead = cardSuit(trick[0].card);
  const mine = trick.find((t) => t.uid === uid);
  if (!mine || cardVal(mine.card) !== 10 || cardSuit(mine.card) !== lead) return [];
  const hand = (d.hands && d.hands[uid]) || [];
  return hand.filter((c) => cardSuit(c) === lead);
}

function fapEarly(d, uid, card) {
  if (!fapEarlyOptions(d, uid).includes(card)) {
    throw new HttpError('failed-precondition', 'Tu peux jouer d\'avance seulement après un 10, avec une carte de la même famille.');
  }
  return { early: { uid, card } };
}

/** « Passe » au 4e pli (2 cartes en main) : on joue la carte qui ne peut pas gagner,
 *  un 3 ou une carte de la famille demandée plus petite que la meilleure du pli. */
function fapPassCard(d, uid) {
  if (!d || d.game !== 'fapfap' || d.status !== 'playing' || d.over === true) return -1;
  if (intOr(d.trickNo, 0) !== 3) return -1;
  if ((Array.isArray(d.passed) ? d.passed : []).some((p) => p.uid === uid)) return -1;
  const trick = Array.isArray(d.trick) ? d.trick : [];
  const hand = (d.hands && d.hands[uid]) || [];
  if (!trick.length || hand.length !== 2) return -1;
  const lead = cardSuit(trick[0].card);
  let top = 0;
  for (const t of trick) if (cardSuit(t.card) === lead) top = Math.max(top, cardVal(t.card));
  const ok = fapLegal(hand, trick).filter((c) => cardVal(c) === 3 || (cardSuit(c) === lead && cardVal(c) < top));
  if (!ok.length) return -1;
  ok.sort((a, b) => cardVal(a) - cardVal(b) || a - b);
  return ok[0];
}

/** « Passe » : le joueur garde ses 2 cartes ; la carte qui ne peut pas gagner est jouée à la fin du pli,
 *  sa dernière carte au pli suivant. Les adversaires voient qu'il est en passe. */
function fapPass(d, uid) {
  const pc = fapPassCard(d, uid);
  if (pc < 0) throw new HttpError('failed-precondition', 'Tu ne peux pas passer : il te faut un 3 ou une carte plus petite que la famille demandée.');
  const d2 = { ...d, passed: [...(Array.isArray(d.passed) ? d.passed : []), { uid, card: pc }] };
  const patch = {
    passed: d2.passed,
    hands: { ...(d.hands || {}) },
    trick: [...(Array.isArray(d.trick) ? d.trick : [])],
    tbl: { ...(d.tbl || {}) },
    turnAt: Date.now(),
  };
  return fapAfter(d2, patch);
}

/** Délai dépassé : on joue la plus faible carte légale. */
function fapAuto(d, uid) {
  const hand = (d.hands && d.hands[uid]) || [];
  const legal = fapLegal(hand, d.trick);
  legal.sort((a, b) => cardVal(a) - cardVal(b) || a - b);
  return fapPlay(d, uid, legal[0]);
}

// ----------------------------------------------------------------------
// KATIKA ANTI-COTE (2 à 5 joueurs, en ligne seulement) : 3 cartes chacun + (joueurs + 1)
// cartes ouvertes au milieu (paquet TIAH). Chacun joue 1 carte de la famille de la 1re carte
// du milieu ; le plus haut ouvre en premier, puis les autres ouvrent leurs 2 cartes restantes
// (les cartes du milieu partent vers lui tant que le total reste <= 21). 2 x M bloqués.
//  Victoires : 777 (CORAT) > brelan (le plus petit) > total 10 > total 11 à la distribution ;
//  3 seul de la famille jouée (CORAT) ; 777 par pioche (CORAT) ; THOUX (2 as restants) ; sinon
//  le plus haut total <= 21. Total < 18 = Koraté. Égalité : tout le monde rejoue, remet M et
//  les Koratés 2 M (cagnotte) ; le vainqueur prend tout.
// ----------------------------------------------------------------------
const AC_KORATE = 18;

function acRoundFields(from, deck) {
  const hands = Object.fromEntries(from.map((u) => [u, []]));
  for (let r = 0; r < 3; r++) for (const u of from) hands[u].push(deck.pop());
  const mid = [];
  for (let k = 0; k < from.length + 1 && deck.length; k++) mid.push(deck.pop());
  const dk = mid.reverse(); // dk[dk.length-1] = carte du dessus (la 1re posée)
  return {
    hands,
    deck: dk,
    fam: cardSuit(dk[dk.length - 1]),
    seq: from,
    act: from,
    turnIdx: 0,
    phase: 'play',
    trick: [],
    prevTrick: { plays: [], winner: '' },
    tbl: Object.fromEntries(from.map((u) => [u, []])),
    opened: [],
    curOpen: false,
    turnAt: Date.now(),
    acDone: false,
  };
}

/** Victoire immédiate à la distribution : 777 > brelan (plus petit) > 10 > 11. */
function acDealCombo(hand) {
  const vals = (hand || []).map(cardVal);
  if (vals.length !== 3) return null;
  const total = vals[0] + vals[1] + vals[2];
  if (vals.every((v) => v === 7)) return { rule: 'three7', rank: 0, corat: true };
  if (vals[0] === vals[1] && vals[1] === vals[2]) return { rule: 'king', rank: 10 + vals[0], corat: false };
  if (total === 10) return { rule: 'ten', rank: 100, corat: false };
  if (total === 11) return { rule: 'eleven', rank: 101, corat: false };
  return null;
}
function acDealWinner(hands, seq) {
  let best = null;
  seq.forEach((u, i) => {
    const c = acDealCombo(hands[u]);
    if (!c) return;
    if (!best || c.rank < best.combo.rank) best = { uid: u, combo: c, i };
  });
  return best;
}

function acLegal(hand, fam) {
  const same = (hand || []).filter((c) => cardSuit(c) === fam);
  return same.length ? same : [...(hand || [])];
}

const acIsThoux = (hand) => (hand || []).length === 2 && hand.every((c) => cardVal(c) === 11);

/** Joue la carte `card` (phase 1). */
function acPlay(d, uid, card) {
  const seq = d.seq || [];
  const hand = [...((d.hands && d.hands[uid]) || [])];
  const idx = hand.indexOf(card);
  if (idx < 0) throw new HttpError('failed-precondition', "Cette carte n'est pas dans ta main.");
  if (!acLegal(hand, intOr(d.fam, 0)).includes(card)) {
    throw new HttpError('failed-precondition', 'Tu dois jouer la famille demandée.');
  }
  hand.splice(idx, 1);
  const trick = [...(Array.isArray(d.trick) ? d.trick : []), { uid, card }];
  const hands = { ...(d.hands || {}), [uid]: hand };
  const tbl = { ...(d.tbl || {}) };
  tbl[uid] = [...(tbl[uid] || []), card];
  const patch = { hands, trick, tbl, turnAt: Date.now() };
  if (trick.length < seq.length) {
    patch.turnIdx = intOr(d.turnIdx, 0) + 1;
    return patch;
  }
  const fam = intOr(d.fam, 0);
  const famPlays = trick.filter((p) => cardSuit(p.card) === fam);
  let first = seq[0];
  if (famPlays.length) {
    let win = famPlays[0];
    for (const p of famPlays) if (cardVal(p.card) > cardVal(win.card)) win = p;
    first = win.uid;
    if (famPlays.length === 1 && cardVal(win.card) === 3) {
      // CORAT classique : un 3 de la famille, personne d'autre n'en joue
      Object.assign(patch, { acDone: true, acOut: { type: 'win', uid: first, rule: 'corat3', corat: true } });
      return patch;
    }
  }
  const i = seq.indexOf(first);
  Object.assign(patch, {
    phase: 'open',
    seq: [...seq.slice(i), ...seq.slice(0, i)],
    turnIdx: 0,
    opened: [],
    prevTrick: { plays: trick, winner: first },
    trick: [],
  });
  return patch;
}

/** Ouvre les 2 cartes restantes de `uid` (phase 2). */
function acOpen(d, uid) {
  const seq = d.seq || [];
  const opened = [...(d.opened || []), uid];
  const deck = [...(d.deck || [])];
  const hand = [...((d.hands && d.hands[uid]) || [])];
  while (deck.length && cardsTotal(hand) + cardVal(deck[deck.length - 1]) <= 21) hand.push(deck.pop());
  const hands = { ...(d.hands || {}), [uid]: hand };
  const patch = { opened, hands, deck, turnIdx: intOr(d.turnIdx, 0) + 1, turnAt: Date.now() };
  if (hand.filter((c) => cardVal(c) === 7).length >= 3) {
    Object.assign(patch, { acDone: true, acOut: { type: 'win', uid, rule: 'three7p', corat: true } });
  } else if (opened.length >= seq.length) {
    const th = seq.filter((u) => acIsThoux(hands[u]));
    if (th.length) {
      Object.assign(patch, { acDone: true, acOut: { type: 'win', uid: th[0], rule: 'thoux', corat: false } });
    } else {
      const tot = (u) => cardsTotal(hands[u]);
      const best = Math.max(...seq.map(tot));
      const tied = seq.filter((u) => tot(u) === best);
      patch.acDone = true;
      patch.acOut =
        tied.length > 1
          ? { type: 'tie', uids: tied, best }
          : { type: 'win', uid: tied[0], rule: best === 21 ? 'thiah' : 'total', corat: false };
    }
  }
  return patch;
}

/** Joueur inactif : on joue / ouvre à sa place. */
function acAuto(d, uid) {
  if (d.phase === 'play') {
    const legal = acLegal((d.hands && d.hands[uid]) || [], intOr(d.fam, 0));
    legal.sort((a, b) => cardVal(a) - cardVal(b) || a - b);
    return acPlay(d, uid, legal[0]);
  }
  return acOpen(d, uid);
}

/** Fin de manche gagnée : qui paie quoi (contributions) et état final. Fonction pure. */
function acSettleWin(dd, out) {
  const act = dd.act || [];
  const M = intOr(dd.stake, 0);
  const rep = intOr(dd.rep, 0);
  const w = out.uid;
  const totals = Object.fromEntries(act.map((u) => [u, cardsTotal((dd.hands && dd.hands[u]) || [])]));
  const contrib = { ...(dd.contrib || {}) };
  const kor = [];
  const totalRule = out.rule === 'total' || out.rule === 'thiah' || out.rule === 'thoux';
  let extras = false;
  if (M > 0 && rep === 0) {
    for (const u of act) {
      if (u === w) continue;
      const pays = out.corat === true || (totalRule && totals[w] >= AC_KORATE && totals[u] < AC_KORATE);
      if (pays) {
        contrib[u] = (contrib[u] || 0) + M;
        extras = true;
        if (out.corat !== true) kor.push(u);
      }
    }
  }
  const pot = Object.values(contrib).reduce((a, b) => a + b, 0);
  return {
    over: true,
    acDone: false,
    finishedMs: Date.now(),
    winnerUids: [w],
    nextDealerUid: w,
    corat: out.corat === true,
    acRule: out.rule,
    acTotals: totals,
    acKorate: kor,
    contrib,
    pot: M > 0 ? pot : intOr(dd.pot, 0),
    acExtras: extras,
  };
}

/** Applique un patch Anti-Cote ; si la manche se termine, règle la victoire ou relance (égalité). */
async function acPost(tx, path, d, patch) {
  const dd = { ...d, ...patch };
  if (patch.acDone !== true) {
    tx.write(path, { set: patch });
    return;
  }
  const out = dd.acOut;
  const clean = { ...patch };
  delete clean.acOut;
  if (out.type === 'win') {
    tx.write(path, { set: { ...clean, ...acSettleWin(dd, out) } });
    return;
  }
  // Égalité : tous rejouent ; chacun remet M, les Koratés 2 M (si le meilleur total >= 18).
  const act = dd.act || [];
  const M = intOr(dd.stake, 0);
  const totals = Object.fromEntries(act.map((u) => [u, cardsTotal((dd.hands && dd.hands[u]) || [])]));
  const doubled = out.best >= AC_KORATE ? act.filter((u) => totals[u] < AC_KORATE) : [];
  const contrib = { ...(dd.contrib || {}) };
  const esc = { ...(dd.esc || {}) };
  const alive = [];
  const out2 = [];
  for (const u of act) {
    if (M > 0) {
      const add = M * (doubled.includes(u) ? 2 : 1);
      const need = (contrib[u] || 0) + add;
      if (need > (esc[u] || 0)) {
        const extra = need - (esc[u] || 0);
        const me = await tx.get(`users/${u}`);
        if (me && balanceOf(me) >= extra) {
          tx.write(`users/${u}`, { incr: { balance: -extra } });
          esc[u] = (esc[u] || 0) + extra;
        } else {
          out2.push(u); // ne peut pas payer : il abandonne, sa mise reste dans la cagnotte
          continue;
        }
      }
      contrib[u] = need;
    }
    alive.push(u);
  }
  const pot = Object.values(contrib).reduce((a, b) => a + b, 0);
  const rep = intOr(dd.rep, 0) + 1;
  const tieNote = { n: rep, uids: out.uids, best: out.best, totals, doubled, quit: out2, hands: dd.hands };
  const base = {
    ...clean,
    contrib,
    esc,
    pot: M > 0 ? pot : intOr(dd.pot, 0),
    rep,
    tieNote,
    tieAt: Date.now(),
    acKorate: [],
  };
  if (alive.length <= 1) {
    const w = alive[0] || out.uids[0];
    tx.write(path, { set: { ...base, ...acSettleWin({ ...dd, ...base, act: alive.length ? alive : act }, { type: 'win', uid: w, rule: 'forfeit', corat: false }) } });
    return;
  }
  const f = acRoundFields(alive, cardsDeck('anticote'));
  const set = { ...base, ...f, turnAt: Date.now() + 2500 }; // + 2,5 s pour lire le message d'égalité
  const dw = acDealWinner(f.hands, alive);
  if (dw) Object.assign(set, acSettleWin({ ...dd, ...set }, { type: 'win', uid: dw.uid, rule: dw.combo.rule, corat: dw.combo.corat }));
  tx.write(path, { set });
}

// ----------------------------------------------------------------------
// KATIKA TCHEK GAMES (2 à 4 joueurs, en ligne seulement) : 54 cartes, 4 cartes chacun.
// Se débarrasser de toutes ses cartes. Carte = rang * 4 + famille (0 ♠, 1 ♥, 2 ♦, 3 ♣),
// rang 1 = As, 11 = J, 12 = Q, 13 = K ; jokers : 0 = rouge, 1 = noir.
//  As : le suivant passe son tour. 7 : +2 cartes. Joker : +4 cartes (cumul, riposte avec
//  un 7 ou un joker). J : choix libre de la famille. Pioche volontaire possible (1 carte,
//  le tour s'arrête). TCHEK : à annoncer en posant l'avant-dernière carte, sinon +1 carte.
// ----------------------------------------------------------------------
const tcRank = (c) => c >> 2;
const tcSuit = (c) => c & 3;
const tcIsJoker = (c) => c === 0 || c === 1;
const tcSuitColor = (s) => (s === 1 || s === 2 ? 'r' : 'b');

function tcDeck() {
  const d = [0, 1];
  for (let r = 1; r <= 13; r++) for (let s = 0; s < 4; s++) d.push(r * 4 + s);
  for (let i = d.length - 1; i > 0; i--) {
    const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [d[i], d[j]] = [d[j], d[i]];
  }
  return d;
}

/** Distribution : 4 cartes chacun, carte de départ ordinaire (ni As, 7, J ni joker). */
function tcDealFields(from, deck) {
  const hands = Object.fromEntries(from.map((u) => [u, []]));
  for (let r = 0; r < 4; r++) for (const u of from) hands[u].push(deck.pop());
  let k = deck.length - 1;
  while (k >= 0 && (tcIsJoker(deck[k]) || [1, 7, 11].includes(tcRank(deck[k])))) k--;
  const start = deck.splice(k < 0 ? deck.length - 1 : k, 1)[0];
  return {
    hands,
    draw: deck,
    disc: [start],
    curSuit: tcSuit(start),
    curRank: tcRank(start),
    curColor: tcSuitColor(tcSuit(start)),
    pen: 0,
    seq: from,
    act: from,
    turnIdx: 0,
    evt: [],
    turnAt: Date.now(),
  };
}

function tcCanPlay(d, c) {
  const pen = intOr(d.pen, 0);
  if (pen > 0) return tcIsJoker(c) || tcRank(c) === 7;
  if (!tcIsJoker(c) && tcRank(c) === 11) return true; // le J passe sur toutes les familles
  if (tcIsJoker(c)) return (c === 0 ? 'r' : 'b') === d.curColor;
  const s = tcSuit(c);
  if (intOr(d.curSuit, -1) >= 0) return s === d.curSuit || tcRank(c) === intOr(d.curRank, 0);
  return tcSuitColor(s) === d.curColor;
}
const tcLegal = (d, hand) => (hand || []).filter((c) => tcCanPlay(d, c));

/** Prend n cartes de la pioche ; pioche vide : on remélange la défausse (sauf la carte du dessus). */
function tcTake(draw, disc, n) {
  const dr = [...draw];
  const dc = [...disc];
  const got = [];
  for (let i = 0; i < n; i++) {
    if (!dr.length && dc.length > 1) {
      const top = dc.pop();
      const rest = dc.splice(0, dc.length);
      for (let a = rest.length - 1; a > 0; a--) {
        const b = crypto.getRandomValues(new Uint32Array(1))[0] % (a + 1);
        [rest[a], rest[b]] = [rest[b], rest[a]];
      }
      dr.push(...rest);
      dc.push(top);
    }
    if (!dr.length) break;
    got.push(dr.pop());
  }
  return { got, draw: dr, disc: dc };
}

const tcEvt = (d, e) => [...(Array.isArray(d.evt) ? d.evt : []), e].slice(-6);

function tcPlay(d, uid, card, suit, announced) {
  const seq = d.seq || [];
  const hand = [...((d.hands && d.hands[uid]) || [])];
  const idx = hand.indexOf(card);
  if (idx < 0) throw new HttpError('failed-precondition', "Cette carte n'est pas dans ta main.");
  if (!tcCanPlay(d, card)) {
    throw new HttpError('failed-precondition', intOr(d.pen, 0) > 0 ? 'Réplique avec un 7 ou un joker, ou prends la pénalité.' : 'Carte refusée : même famille ou même numéro.');
  }
  const rank = tcRank(card);
  if (rank === 11 && !tcIsJoker(card) && !(suit >= 0 && suit <= 3)) throw new HttpError('invalid-argument', 'Choisis une famille.');
  hand.splice(idx, 1);
  const disc = [...(d.disc || []), card];
  let pen = intOr(d.pen, 0);
  let skip = 0;
  let curSuit;
  let curRank;
  let curColor;
  if (tcIsJoker(card)) {
    pen += 4;
    curSuit = -1;
    curRank = 0;
    curColor = card === 0 ? 'r' : 'b';
  } else {
    curSuit = rank === 11 ? suit : tcSuit(card);
    curRank = rank;
    curColor = tcSuitColor(curSuit);
    if (rank === 7) pen += 2;
    if (rank === 1) skip = 1;
  }
  const hands = { ...(d.hands || {}), [uid]: hand };
  let evt = tcEvt(d, { u: uid, k: 'play', c: card, s: curSuit });
  const patch = { hands, disc, pen, curSuit, curRank, curColor, turnAt: Date.now() };
  if (hand.length === 0) {
    Object.assign(patch, { over: true, finishedMs: Date.now(), winnerUids: [uid], nextDealerUid: uid, evt });
    return patch;
  }
  let draw = d.draw || [];
  if (hand.length === 1 && announced !== true) {
    const t = tcTake(draw, disc, 1);
    hand.push(...t.got);
    draw = t.draw;
    patch.disc = t.disc;
    evt = [...evt, { u: uid, k: 'noTchek' }].slice(-6);
  } else if (hand.length === 1) {
    evt = [...evt, { u: uid, k: 'tchek' }].slice(-6);
  }
  patch.draw = draw;
  patch.evt = evt;
  patch.turnIdx = (intOr(d.turnIdx, 0) + 1 + skip) % seq.length;
  if (skip) patch.evt = [...patch.evt, { u: seq[(intOr(d.turnIdx, 0) + 1) % seq.length], k: 'skip' }].slice(-6);
  return patch;
}

/** Pioche : pénalité cumulée si elle existe (le tour est perdu), sinon 1 carte (pioche volontaire). */
function tcDraw(d, uid) {
  const seq = d.seq || [];
  const pen = intOr(d.pen, 0);
  const n = pen > 0 ? pen : 1;
  const hand = [...((d.hands && d.hands[uid]) || [])];
  const t = tcTake(d.draw || [], d.disc || [], n);
  hand.push(...t.got);
  return {
    hands: { ...(d.hands || {}), [uid]: hand },
    draw: t.draw,
    disc: t.disc,
    pen: 0,
    evt: tcEvt(d, { u: uid, k: pen > 0 ? 'pen' : 'draw', n: t.got.length }),
    turnIdx: (intOr(d.turnIdx, 0) + 1) % seq.length,
    turnAt: Date.now(),
  };
}

/** Joueur inactif : il pose une carte jouable (ou pioche). */
function tcAuto(d, uid) {
  const hand = (d.hands && d.hands[uid]) || [];
  if (intOr(d.pen, 0) > 0) return tcDraw(d, uid);
  const legal = tcLegal(d, hand);
  if (!legal.length) return tcDraw(d, uid);
  const plain = legal.filter((c) => !tcIsJoker(c) && ![1, 7, 11].includes(tcRank(c)));
  const c = (plain.length ? plain : legal)[0];
  let suit = -1;
  if (tcRank(c) === 11 && !tcIsJoker(c)) {
    const cnt = [0, 0, 0, 0];
    for (const x of hand) if (!tcIsJoker(x) && x !== c) cnt[tcSuit(x)]++;
    suit = cnt.indexOf(Math.max(...cnt));
  }
  return tcPlay(d, uid, c, suit, true);
}

/** Fin de manche : gagnants et prochain distributeur. */
function cardsFinish(d, opened, hands) {
  const uids = d.seq || [];
  const patch = { over: true, finishedMs: Date.now() };
  let winners;
  if (d.game === 'tiah') {
    const tx = uids.filter((u) => cardsIsToucx(hands[u]));
    let best = -1;
    for (const u of uids) {
      const t = cardsTotal(hands[u]);
      if (t <= 21 && t > best) best = t;
    }
    if (tx.length) {
      winners = [tx[0]];
      patch.toucx = true;
    } else {
      winners = best < 0 ? [...uids] : uids.filter((u) => cardsTotal(hands[u]) === best);
    }
    patch.nextDealerUid = nextAfter(d.order || uids, d.first, uids);
  } else {
    const fom = opened.filter((u) => cardsIsFomekou(d, u)); // dans l'ordre de révélation
    if (fom.length) {
      winners = fom;
      patch.fomekou = true;
      patch.nextDealerUid = fom[0];
    } else {
      let best = 0;
      for (const u of uids) best = Math.max(best, cardsBoubaTotal(d, u));
      winners = opened.filter((u) => cardsBoubaTotal(d, u) === best);
      patch.fomekou = false;
      patch.nextDealerUid = winners[0];
    }
  }
  patch.winnerUids = winners;
  return patch;
}

/** Le joueur `uid` ouvre ses cartes.
 *  BOUBAYAH : ses deux cartes sont révélées.
 *  TIAH : les cartes du milieu, dans l'ordre, partent toutes seules vers lui tant que la
 *  carte du dessus tient dans 21 ; on ne saute jamais une carte. */
function cardsApplyOpen(d, uid) {
  const seq = d.seq || [];
  const opened = [...(d.opened || []), uid];
  const patch = { opened, turnIdx: intOr(d.turnIdx, 0) + 1, turnAt: Date.now() };
  let hands = d.hands;
  if (d.game === 'tiah') {
    const deck = [...(d.deck || [])];
    const hand = [...((d.hands && d.hands[uid]) || [])];
    while (deck.length && cardsTotal(hand) + cardVal(deck[deck.length - 1]) <= 21) hand.push(deck.pop());
    hands = { ...(d.hands || {}), [uid]: hand };
    patch.deck = deck;
    patch.hands = hands;
  }
  if (opened.length >= seq.length) Object.assign(patch, cardsFinish(d, opened, hands));
  return patch;
}

/** Joueur inactif : on ouvre ses cartes à sa place. */
const cardsAutoStep = (d, uid) => (d.game === 'fapfap' ? fapAuto(d, uid) : d.game === 'anticote' ? acAuto(d, uid) : d.game === 'tchek' ? tcAuto(d, uid) : cardsApplyOpen(d, uid));

/** Écrit le patch d'une action (Anti-Cote : fin de manche, égalité et cagnotte gérées ici). */
async function cardsWritePatch(tx, path, d, patch) {
  if (d.game === 'anticote') return acPost(tx, path, d, patch);
  tx.write(path, { set: patch });
}

/** Joueur qui suit `uid` dans l'ordre des sièges. */
function nextAfter(order, uid, present) {
  const list = (order && order.length ? order : present).filter((u) => present.includes(u));
  const i = list.indexOf(uid);
  return list[(i + 1) % list.length] || present[0];
}

async function cardsDrive(env, gid) {
  for (let i = 0; i < 8; i++) {
    const g = await readDoc(env, `cards/${gid}`);
    if (!g || g.status !== 'playing' || g.over === true) return;
    if (Date.now() - intOr(g.turnAt, 0) <= cardsTurnMs(g)) return;
    await runTx(env, async (tx) => {
      const path = `cards/${gid}`;
      const d = await tx.get(path);
      if (!d || d.status !== 'playing' || d.over === true) return;
      if (Date.now() - intOr(d.turnAt, 0) <= cardsTurnMs(d)) return;
      const cur = (d.seq || [])[intOr(d.turnIdx, 0)];
      if (!cur) return;
      await cardsWritePatch(tx, path, d, cardsAutoStep(d, cur));
    });
  }
}

/** Ce que `uid` a le droit de voir de la manche. */
function cardsView(id, g, uid) {
  const over = g.over === true;
  const players = playersOf(g);
  const opened = Array.isArray(g.opened) ? g.opened : [];
  const seq = Array.isArray(g.seq) ? g.seq : [];
  const turnUid = g.status === 'playing' && !over ? seq[intOr(g.turnIdx, 0)] || '' : '';
  const out = players.map((p) => {
    const isOpen = opened.includes(p.uid);
    const row = { uid: p.uid, name: p.name || 'Joueur', opened: isOpen };
    if (g.game === 'fapfap') {
      const hand = (g.hands && g.hands[p.uid]) || [];
      row.count = hand.length - (g.early && g.early.uid === p.uid ? 1 : 0);
      row.table = (g.tbl && g.tbl[p.uid]) || [];
      if (over && hand.length) row.cards = hand; // gain par combinaison : mains dévoilées
      if (over && hand.length === 5) {
        const c = fapCombo(hand);
        if (c) row.combo = c.rule;
      }
    } else if (g.game === 'tchek') {
      const hand = (g.hands && g.hands[p.uid]) || [];
      row.count = hand.length;
      if (over && hand.length) row.cards = hand;
      row.out = false;
    } else if (g.game === 'anticote') {
      const hand = (g.hands && g.hands[p.uid]) || [];
      row.count = hand.length;
      row.table = (g.tbl && g.tbl[p.uid]) || [];
      row.contrib = intOr(g.contrib && g.contrib[p.uid], 0);
      row.out = g.status === 'playing' && !over && Array.isArray(g.act) && !g.act.includes(p.uid);
      if (isOpen || over) {
        row.cards = hand;
        row.total = cardsTotal(hand);
      }
    } else if (g.game === 'tiah') {
      const hand = (g.hands && g.hands[p.uid]) || [];
      row.count = hand.length;
      if (isOpen || over) {
        row.cards = hand;
        row.total = cardsTotal(hand);
        row.toucx = cardsIsToucx(hand);
      }
    } else if (g.game === 'boubayah') {
      const plain = (g.plain && g.plain[p.uid]) || [];
      const bouba = (g.bouba && g.bouba[p.uid]) || [];
      row.count = plain.length;
      if (isOpen || over) {
        row.total = cardsBoubaTotal(g, p.uid);
        row.fomekou = cardsIsFomekou(g, p.uid);
      }
      if (over || p.uid === uid) row.plain = plain;
      // BOUBAYAH masqué pour tout le monde (y compris soi) jusqu'à l'ouverture.
      row.bouba = isOpen || over ? bouba : undefined;
      row.myOnly = !isOpen && !over && p.uid === uid;
    }
    return row;
  });
  const stake = intOr(g.stake, 0);
  const winners = Array.isArray(g.winnerUids) ? g.winnerUids : [];
  const n = (Array.isArray(g.paid) && g.paid.length) || players.length;
  return {
    id,
    game: g.game,
    code: g.code || '',
    isPublic: g.isPublic === true,
    stake,
    pot: intOr(g.pot, 0),
    maxPlayers: intOr(g.maxPlayers, 6),
    status: over ? 'finished' : g.status,
    round: intOr(g.round, 1),
    hostUid: g.hostUid,
    dealerUid: g.dealerUid || g.hostUid,
    players: out,
    pile: Array.isArray(g.deck) ? g.deck.length : 0,
    pileCards: (g.game === 'tiah' || g.game === 'anticote') && Array.isArray(g.deck) ? [...g.deck].reverse() : [], // la 1re est celle du dessus
    chat: cardsChatView(g),
    curOpen: g.curOpen === true,
    seq: Array.isArray(g.seq) ? g.seq : [],
    turnUid,
    turnLeftMs: turnUid ? Math.max(0, cardsTurnMs(g) - (Date.now() - intOr(g.turnAt, 0))) : 0,
    ...(g.game === 'fapfap'
      ? {
          myHand: ((g.hands && g.hands[uid]) || []).filter((c) => !(g.early && g.early.uid === uid && g.early.card === c)),
          early: g.early || null,
          passedUids: (Array.isArray(g.passed) ? g.passed : []).map((p) => p.uid),
          earlyOk: fapEarlyOptions(g, uid),
          canPass: turnUid === uid && fapPassCard(g, uid) >= 0,
          showPass: turnUid === uid && intOr(g.trickNo, 0) === 3 && Array.isArray(g.trick) && g.trick.length > 0 && ((g.hands && g.hands[uid]) || []).length === 2,
          trick: Array.isArray(g.trick) ? g.trick : [],
          prevTrick: g.prevTrick || null,
          trickNo: intOr(g.trickNo, 0),
          legal: turnUid === uid ? fapLegal((g.hands && g.hands[uid]) || [], g.trick) : [],
          corat: g.corat === true,
          fapRule: g.fapRule || '',
          escrow: intOr(g.stake, 0) * 2,
        }
      : {}),
    ...(g.game === 'tchek'
      ? {
          myHand: (g.hands && g.hands[uid]) || [],
          legal: turnUid === uid ? tcLegal(g, (g.hands && g.hands[uid]) || []) : [],
          top: Array.isArray(g.disc) && g.disc.length ? g.disc[g.disc.length - 1] : -1,
          curSuit: intOr(g.curSuit, -1),
          curColor: g.curColor || '',
          pen: intOr(g.pen, 0),
          drawCount: Array.isArray(g.draw) ? g.draw.length : 0,
          evt: Array.isArray(g.evt) ? g.evt : [],
        }
      : {}),
    ...(g.game === 'anticote'
      ? {
          myHand: (g.hands && g.hands[uid]) || [],
          phase: g.phase || 'play',
          fam: intOr(g.fam, 0),
          trick: Array.isArray(g.trick) ? g.trick : [],
          prevTrick: g.prevTrick || null,
          legal: turnUid === uid && g.phase === 'play' ? acLegal((g.hands && g.hands[uid]) || [], intOr(g.fam, 0)) : [],
          corat: g.corat === true,
          acRule: g.acRule || '',
          acKorate: Array.isArray(g.acKorate) ? g.acKorate : [],
          acTotals: over && g.acTotals ? g.acTotals : {},
          rep: intOr(g.rep, 0),
          tieNote: g.tieNote || null,
          tieAt: intOr(g.tieAt, 0),
          escrow: intOr(g.stake, 0) * 2,
        }
      : {}),
    over,
    winnerUids: over ? winners : [],
    fomekou: g.fomekou === true,
    toucx: g.toucx === true,
    nextDealerUid: over ? g.nextDealerUid || '' : '',
    nextId: g.nextId || '',
    settled: g.settled === true,
    refunded: g.refunded === true,
    prize:
      over && stake > 0
        ? g.game === 'anticote'
          ? Math.floor(prizeOf(intOr(g.pot, 0)) / Math.max(1, winners.length))
          : g.game === 'fapfap'
          ? Math.floor(prizeOf(stake * (g.corat === true ? 2 : 1) * n) / Math.max(1, winners.length))
          : winners.length === n
            ? stake
            : Math.floor(prizeOf(stake * n) / Math.max(1, winners.length))
        : 0,
    canStart:
      g.status === 'waiting' &&
      players.length >= 2 &&
      (uid === (g.dealerUid || g.hostUid) ||
        (players.some((p) => p.uid === uid) && Date.now() - intOr(g.createdAtMs, 0) > CARDS_START_AFTER_MS)),
    now: Date.now(),
  };
}

// ----------------------------------------------------------------------
// Paris entre joueurs aux cartes (en ligne) : Duel (TIAH et BOUBAYAH) et Défi Fétiche 13 (BOUBAYAH)
// ----------------------------------------------------------------------
// cards/{roomId}/bets/{betId}, cards/{roomId}/betMeta/index { ids }
// Possible tant que les joueurs concernés n'ont pas ouvert leurs cartes (avant la manche
// ou pendant). Mise débitée à la proposition / l'acceptation, réglée par cardsBetsSync.
//  • Duel : le plus gros score gagne (TIAH : total ≤ 21, plus de 21 = perdu ; BOUBAYAH : MILLION bat tout).
//  • Fétiche : le total BOUBAYAH du parieur est comparé à 13 ; MILLION compte 6 (donc « moins de 13 »).
//  Égalité (ou 13 pile) : mises rendues.

const FETICHE = 13;
/** Défis entre joueurs avant le départ (Anti-Cote, Tchek) : jeux « rapides » avec défi à la création. */
const cardsFlBets = (g) => g === 'anticote' || g === 'tchek';
/** Vainqueur d'un défi : celui qui gagne la manche ; si un tiers gagne, Anti-Cote = meilleur total, Tchek = moins de cartes. */
function flDuelWinner(room, a, b) {
  const win = Array.isArray(room.winnerUids) ? room.winnerUids : [];
  if (win.includes(a) !== win.includes(b)) return win.includes(a) ? a : b;
  const sc = (u) => {
    const h = room.hands && room.hands[u];
    if (!Array.isArray(h)) return -1000;
    if (room.game === 'tchek') return -h.length;
    return cardsTotal(h) <= 21 ? cardsTotal(h) : -1;
  };
  const x = sc(a);
  const y = sc(b);
  return x === y ? null : x > y ? a : b;
}
const cardsBetPath = (rid, id) => `cards/${rid}/bets/${id}`;
const cardsBetIndexPath = (rid) => `cards/${rid}/betMeta/index`;
const cardsPlayed = (g, uid) => g.over === true || (Array.isArray(g.opened) && g.opened.includes(uid));

function cardsDuelScore(g, uid) {
  if (g.game === 'tiah') {
    const h = (g.hands && g.hands[uid]) || [];
    if (cardsIsToucx(h)) return 100;
    const t = cardsTotal(h);
    return t > 21 ? -1 : t;
  }
  return cardsIsFomekou(g, uid) ? 100 : cardsBoubaTotal(g, uid);
}
const cardsFeticheValue = (g, uid) => (cardsIsFomekou(g, uid) ? 6 : cardsBoubaTotal(g, uid));

async function cardsLoadBets(tx, rid) {
  const idx = await tx.get(cardsBetIndexPath(rid));
  const ids = idx && Array.isArray(idx.ids) ? idx.ids.slice(0, BET_MAX_PER_ROOM) : [];
  const out = [];
  for (const id of ids) {
    const b = await tx.get(cardsBetPath(rid, id));
    if (b) out.push({ id, path: cardsBetPath(rid, id), b });
  }
  return out;
}

// ----------------------------------------------------------------------
// Pari « CHAT » (TIAH et ANTI-COTE) : on parie sur le rang d'une carte du milieu.
// 1er CHAT = la 1re carte du milieu (celle du dessus), 2ÈME CHAT = la suivante, etc.
// Chaque joueur de la salle choisit un CHAT (même mise pour tous, fixée par le 1er parieur)
// AVANT le début de la manche, quand les cartes ne sont pas encore connues. Au départ, la carte
// de plus grande valeur gagne la cagnotte (5 % de commission) ; égalité : la cagnotte est partagée.
// Un CHAT qui n'existe pas (ANTI-COTE : joueurs + 1 cartes) est remboursé.
// Données : cards/{id}.chatBet = { amount, status: none|open|settled|void|cancelled, entries: [{uid,name,n,value?}], ... }
// ----------------------------------------------------------------------
const CHAT_COMMISSION_PERCENT = 5;
const cardsChatMax = (g) => (g.game === 'tiah' ? 10 : intOr(g.maxPlayers, 4) + 1);
const cardsChatOf = (g) =>
  g && g.chatBet && Array.isArray(g.chatBet.entries) ? g.chatBet : { amount: 0, entries: [], status: 'none' };

async function cardsChatJoin({ uid, data, env }) {
  const gid = idStr(data.gameId);
  const n = intOr(data.n, 0);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (g.game !== 'tiah' && g.game !== 'anticote') {
      throw new HttpError('invalid-argument', 'Le pari CHAT existe seulement au TIAH et à ANTI-COTE.');
    }
    if (g.status !== 'waiting') {
      throw new HttpError('failed-precondition', 'Le pari CHAT se place avant le début de la manche (les cartes du milieu ne sont pas encore connues).');
    }
    if (intOr(g.stake, 0) <= 0) throw new HttpError('failed-precondition', 'Pas de pari dans une partie gratuite.');
    const me = playersOf(g).find((p) => p.uid === uid);
    if (!me) throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    const cb = cardsChatOf(g);
    if (cb.entries.some((e) => e.uid === uid)) {
      throw new HttpError('failed-precondition', 'Tu as déjà choisi ton CHAT : retire-le d\'abord pour en changer.');
    }
    const max = cardsChatMax(g);
    if (n < 1 || n > max) throw new HttpError('invalid-argument', `CHAT invalide : choisis de 1 à ${max}.`);
    if (cb.entries.some((e) => intOr(e.n, 0) === n)) {
      throw new HttpError('failed-precondition', 'Ce CHAT est déjà pris par un autre joueur : choisis-en un autre.');
    }
    const amount = cb.entries.length ? intOr(cb.amount, 0) : intOr(data.amount, -1);
    if (amount < BET_MIN || amount > BET_MAX) throw new HttpError('invalid-argument', 'Mise invalide.');
    const u = await tx.get(`users/${uid}`);
    if (balanceOf(u) < amount) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(path, {
      set: { chatBet: { amount, status: 'open', entries: [...cb.entries, { uid, name: me.name || 'Joueur', n }] } },
    });
  });
  return cardsFetch(env, gid, uid);
}

async function cardsChatLeave({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (g.status !== 'waiting') throw new HttpError('failed-precondition', 'Le pari CHAT ne peut plus être retiré.');
    const patch = cardsChatDrop(tx, g, uid);
    if (!patch.chatBet) throw new HttpError('failed-precondition', "Tu n'as pas de pari CHAT.");
    tx.write(path, { set: patch });
  });
  return cardsFetch(env, gid, uid);
}

/** Rembourse l'entrée CHAT d'un joueur (salle d'attente) et renvoie le champ à mettre à jour. */
function cardsChatDrop(tx, g, uid) {
  const cb = cardsChatOf(g);
  if (!cb.entries.some((e) => e.uid === uid)) return {};
  tx.write(`users/${uid}`, { incr: { balance: intOr(cb.amount, 0) } });
  const entries = cb.entries.filter((e) => e.uid !== uid);
  return { chatBet: { amount: entries.length ? intOr(cb.amount, 0) : 0, status: entries.length ? 'open' : 'none', entries } };
}

/** Salle annulée : toutes les mises CHAT sont rendues. */
function cardsChatRefundAll(tx, g) {
  const cb = cardsChatOf(g);
  for (const e of cb.entries) tx.write(`users/${e.uid}`, { incr: { balance: intOr(cb.amount, 0) } });
  return { chatBet: { amount: 0, status: 'cancelled', entries: [] } };
}

/** Au départ de la manche : les cartes du milieu sont connues, le pari CHAT est réglé tout de suite. */
async function cardsChatSettle(tx, gid, g, set) {
  const cb = cardsChatOf(g);
  const amount = intOr(cb.amount, 0);
  const cards = [...(Array.isArray(set.deck) ? set.deck : [])].reverse(); // 1er CHAT = carte du dessus
  const vals = cards.map(cardVal);
  const valid = cb.entries.filter((e) => e.n >= 1 && e.n <= cards.length);
  const voided = cb.entries.filter((e) => !(e.n >= 1 && e.n <= cards.length));
  for (const e of voided) tx.write(`users/${e.uid}`, { incr: { balance: amount } });
  if (valid.length < 2) {
    for (const e of valid) tx.write(`users/${e.uid}`, { incr: { balance: amount } });
    set.chatBet = {
      amount, status: 'void', cards, entries: cb.entries.map((e) => ({ ...e, value: vals[e.n - 1] === undefined ? null : vals[e.n - 1] })),
      voidUids: cb.entries.map((e) => e.uid), winners: [], prize: 0, each: 0, commission: 0,
      note: 'Pas assez de CHAT valides : mises rendues.',
    };
    return;
  }
  const best = Math.max(...valid.map((e) => vals[e.n - 1]));
  const winners = valid.filter((e) => vals[e.n - 1] === best);
  const pool = amount * valid.length;
  const prize = prizeOf(pool, CHAT_COMMISSION_PERCENT);
  const each = Math.floor(prize / winners.length);
  const commission = pool - each * winners.length; // commission 5 % + arrondi du partage
  for (const w of winners) tx.write(`users/${w.uid}`, { incr: { balance: each } });
  for (const e of valid) tx.write(`users/${e.uid}`, { incr: { wagered: amount } });
  for (const e of valid) {
    if (winners.some((x) => x.uid === e.uid)) betNote(tx, e.uid, each - amount, 'Pari CHAT', commission > 0 ? `commission ${commission} FCFA déduite` : '');
    else betNote(tx, e.uid, -amount, 'Pari CHAT', '');
  }
  const ref = await referralPayout(tx, valid.map((e) => e.uid), commission, { gameId: gid, mode: 'chat', ref: gid });
  await houseAdd(tx, commission - ref.referral - ref.partner);
  set.betCommission = Math.max(0, intOr(g.betCommission, 0)) + commission;
  set.chatBet = {
    amount, status: 'settled', cards,
    entries: cb.entries.map((e) => ({ ...e, value: vals[e.n - 1] === undefined ? null : vals[e.n - 1] })),
    voidUids: voided.map((e) => e.uid), winners: winners.map((e) => e.uid), best, prize, each, commission,
    note: voided.length ? 'Un CHAT inexistant a été remboursé.' : '',
  };
}

function cardsChatView(g) {
  if (g.game !== 'tiah' && g.game !== 'anticote') return null;
  const cb = cardsChatOf(g);
  if (!cb.entries.length && cb.status !== 'settled' && cb.status !== 'void') return null;
  return {
    amount: intOr(cb.amount, 0),
    status: String(cb.status || 'open'),
    max: cardsChatMax(g),
    percent: CHAT_COMMISSION_PERCENT,
    entries: cb.entries.map((e) => ({ uid: e.uid, name: String(e.name || ''), n: intOr(e.n, 0), value: e.value === undefined || e.value === null ? null : intOr(e.value, 0) })),
    cards: Array.isArray(cb.cards) ? cb.cards.map((c) => intOr(c, 0)) : [],
    voidUids: Array.isArray(cb.voidUids) ? cb.voidUids : [],
    winners: Array.isArray(cb.winners) ? cb.winners : [],
    prize: intOr(cb.prize, 0),
    each: intOr(cb.each, 0),
    commission: intOr(cb.commission, 0),
    note: String(cb.note || ''),
  };
}

async function cardsBetPropose({ uid, data, env }) {
  const gid = idStr(data.gameId);
  const type = data.type;
  const amount = intOr(data.amount, -1);
  const targetUid = typeof data.targetUid === 'string' && data.targetUid ? data.targetUid : null;
  const side = data.side === 'under' ? 'under' : 'over';
  let inviter = '';
  let gameName = '';
  if (!gid || (type !== 'duel' && type !== 'fetiche')) throw new HttpError('invalid-argument', 'Pari invalide.');
  if (amount < BET_MIN || amount > BET_MAX) throw new HttpError('invalid-argument', 'Mise invalide.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const flb = cardsFlBets(g.game);
    if (isFl(g.game) && !flb) throw new HttpError('invalid-argument', 'Pas de paris à ce jeu.');
    if (flb && type !== 'duel') throw new HttpError('invalid-argument', 'Seul le défi entre joueurs existe à ce jeu.');
    if (type === 'fetiche' && g.game !== 'boubayah') {
      throw new HttpError('invalid-argument', 'Le défi Fétiche existe seulement au BOUBAYAH.');
    }
    if (!flb && intOr(g.stake, 0) <= 0) throw new HttpError('failed-precondition', 'Pas de pari dans une partie gratuite.');
    // Paris et défis : à la création (salle d'attente) ET pendant la manche.
    if ((g.status !== 'waiting' && g.status !== 'playing') || g.over === true) {
      throw new HttpError('failed-precondition', "La manche est terminée : plus de pari.");
    }
    const players = playersOf(g);
    const me = players.find((p) => p.uid === uid);
    if (!me) throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    if (!flb && cardsPlayed(g, uid)) throw new HttpError('failed-precondition', 'Tu as déjà ouvert tes cartes.');
    let target = null;
    if (targetUid) {
      target = players.find((p) => p.uid === targetUid);
      if (!target || targetUid === uid) throw new HttpError('invalid-argument', 'Adversaire invalide.');
      if (!flb && cardsPlayed(g, targetUid)) throw new HttpError('failed-precondition', 'Ce joueur a déjà ouvert ses cartes.');
    }
    const bets = await cardsLoadBets(tx, gid);
    if (bets.length >= BET_MAX_PER_ROOM) throw new HttpError('failed-precondition', 'Trop de paris dans cette partie.');
    if (bets.filter((x) => x.b.status === 'open' && x.b.proposerUid === uid).length >= BET_MAX_OPEN_PER_PLAYER) {
      throw new HttpError('failed-precondition', 'Trop de paris en attente.');
    }
    const u = await tx.get(`users/${uid}`);
    if (balanceOf(u) < amount) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    inviter = me.name || 'Un joueur';
    gameName = g.game === 'anticote' ? 'ANTI-COTE' : g.game === 'tchek' ? 'TCHEK GAMES' : g.game === 'boubayah' ? 'BOUBAYAH' : 'TIAH';
    const id = newId();
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(cardsBetPath(gid, id), {
      create: true,
      set: {
        type,
        amount,
        prize: prizeOf(amount * 2),
        side: type === 'fetiche' ? side : null,
        proposerUid: uid,
        proposerName: me.name || 'Joueur',
        targetUid: target ? target.uid : null,
        targetName: target ? target.name || null : null,
        opponentUid: null,
        opponentName: null,
        status: 'open',
      },
      serverTime: ['createdAt'],
    });
    tx.write(cardsBetIndexPath(gid), { set: { n: bets.length + 1 }, union: { ids: [id] } });
    tx.write(path, { set: { betsN: bets.length + 1, betsDone: false } });
  });
  // Invitation : le joueur défié reçoit une notification (il accepte ou refuse dans la table).
  if (type === 'duel' && targetUid) {
    later(env, pushToUser(env, targetUid, '⚔️ Défi reçu', `${inviter} te défie de ${amount} FCFA à ${gameName}. Ouvre la table pour accepter ou refuser.`));
  }
  return cardsFetch(env, gid, uid);
}

async function cardsBetAccept({ uid, data, env }) {
  const gid = idStr(data.gameId);
  const id = idStr(data.betId);
  if (!gid || !id) throw new HttpError('invalid-argument', 'Pari invalide.');
  await runTx(env, async (tx) => {
    const g = await tx.get(`cards/${gid}`);
    const bet = await tx.get(cardsBetPath(gid, id));
    if (!g || !bet) throw new HttpError('not-found', 'Pari introuvable.');
    if (bet.status !== 'open') throw new HttpError('failed-precondition', "Ce pari n'est plus disponible.");
    if (bet.proposerUid === uid) throw new HttpError('failed-precondition', 'Tu ne peux pas relever ton propre pari.');
    if (bet.targetUid && bet.targetUid !== uid) throw new HttpError('permission-denied', "Ce pari ne t'est pas destiné.");
    const flb = cardsFlBets(g.game);
    if ((g.status !== 'waiting' && g.status !== 'playing') || g.over === true) {
      throw new HttpError('failed-precondition', "La manche est terminée : plus de pari.");
    }
    const me = playersOf(g).find((p) => p.uid === uid);
    if (!me) throw new HttpError('permission-denied', 'Tu ne joues pas dans cette partie.');
    if (!flb && cardsPlayed(g, uid)) throw new HttpError('failed-precondition', 'Tu as déjà ouvert tes cartes.');
    if (!flb && cardsPlayed(g, bet.proposerUid)) throw new HttpError('failed-precondition', 'Le parieur a déjà ouvert ses cartes.');
    const u = await tx.get(`users/${uid}`);
    if (balanceOf(u) < bet.amount) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    tx.write(`users/${uid}`, { incr: { balance: -bet.amount } });
    tx.write(cardsBetPath(gid, id), {
      set: { status: 'accepted', opponentUid: uid, opponentName: me.name || 'Joueur' },
      serverTime: ['acceptedAt'],
    });
  });
  return cardsFetch(env, gid, uid);
}

async function cardsBetCancel({ uid, data, env }) {
  const gid = idStr(data.gameId);
  const id = idStr(data.betId);
  if (!gid || !id) throw new HttpError('invalid-argument', 'Pari invalide.');
  await runTx(env, async (tx) => {
    const bet = await tx.get(cardsBetPath(gid, id));
    if (!bet) throw new HttpError('not-found', 'Pari introuvable.');
    if (bet.status !== 'open') throw new HttpError('failed-precondition', "Ce pari n'est plus en attente.");
    const isProposer = bet.proposerUid === uid;
    if (!isProposer && bet.targetUid !== uid) throw new HttpError('permission-denied', "Ce pari n'est pas le tien.");
    tx.write(`users/${bet.proposerUid}`, { incr: { balance: bet.amount } });
    tx.write(cardsBetPath(gid, id), {
      set: { status: isProposer ? 'cancelled' : 'declined' },
      serverTime: ['closedAt'],
    });
  });
  return cardsFetch(env, gid, uid);
}

/** Règle les paris prêts (gains, remboursements, paris expirés). Sans danger si répétée. */
async function cardsBetsSync(env, gid) {
  const g0 = await readDoc(env, `cards/${gid}`);
  if (!g0 || !(intOr(g0.betsN, 0) > 0) || g0.betsDone === true) return;
  await runTx(env, async (tx) => {
    const room = await tx.get(`cards/${gid}`);
    if (!room || room.betsDone === true) return;
    const bets = await cardsLoadBets(tx, gid);
    let house = 0;
    let pending = 0;
    for (const { path, b } of bets) {
      if (b.status === 'open') {
        const expired = cardsFlBets(room.game)
          ? room.status === 'cancelled' || room.over === true
          : room.over === true || cardsPlayed(room, b.proposerUid) || (b.targetUid && cardsPlayed(room, b.targetUid));
        if (expired) {
          tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
          tx.write(path, { set: { status: 'expired' }, serverTime: ['closedAt'] });
        } else {
          pending++;
        }
        continue;
      }
      if (b.status !== 'accepted') continue;
      if (cardsFlBets(room.game) && room.status === 'cancelled') {
        tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
        tx.write(`users/${b.opponentUid}`, { incr: { balance: b.amount } });
        tx.write(path, { set: { status: 'cancelled' }, serverTime: ['closedAt'] });
        continue;
      }
      let winner;
      if (b.type === 'fetiche') {
        if (!cardsPlayed(room, b.proposerUid)) {
          pending++;
          continue;
        }
        const v = cardsFeticheValue(room, b.proposerUid);
        winner = v === FETICHE ? null : v > FETICHE === (b.side !== 'under') ? b.proposerUid : b.opponentUid;
      } else if (cardsFlBets(room.game)) {
        if (room.over !== true) {
          pending++;
          continue;
        }
        winner = flDuelWinner(room, b.proposerUid, b.opponentUid);
      } else {
        if (!cardsPlayed(room, b.proposerUid) || !cardsPlayed(room, b.opponentUid)) {
          pending++;
          continue;
        }
        const a = cardsDuelScore(room, b.proposerUid);
        const c = cardsDuelScore(room, b.opponentUid);
        winner = a === c ? null : a > c ? b.proposerUid : b.opponentUid;
      }
      if (winner === null) {
        tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
        tx.write(`users/${b.opponentUid}`, { incr: { balance: b.amount } });
        tx.write(path, { set: { status: 'settled', result: 'refund' }, serverTime: ['closedAt'] });
      } else {
        tx.write(`users/${winner}`, { incr: { balance: b.prize } });
        betNoteWinLose(tx, b, winner, b.type === 'fetiche' ? 'Fétiche' : b.type === 'seven' ? 'Défi 7' : 'Duel');
        tx.write(`users/${b.proposerUid}`, { incr: { wagered: b.amount } });
        tx.write(`users/${b.opponentUid}`, { incr: { wagered: b.amount } });
        tx.write(`cards/${gid}`, { incr: { betCommission: 2 * b.amount - b.prize } });
        house += 2 * b.amount - b.prize;
        tx.write(path, { set: { status: 'settled', result: 'win', winnerUid: winner }, serverTime: ['closedAt'] });
      }
    }
    if (room.over === true && pending === 0) tx.write(`cards/${gid}`, { set: { betsDone: true } });
    await houseAdd(tx, house);
  });
}

async function cardsReadBets(env, gid) {
  const idx = await readDoc(env, cardsBetIndexPath(gid));
  const ids = idx && Array.isArray(idx.ids) ? idx.ids.slice(0, BET_MAX_PER_ROOM) : [];
  const out = [];
  for (const id of ids) {
    const b = await readDoc(env, cardsBetPath(gid, id));
    if (!b) continue;
    out.push({
      id,
      type: b.type,
      amount: intOr(b.amount, 0),
      prize: intOr(b.prize, 0),
      side: b.side || null,
      proposerUid: b.proposerUid,
      proposerName: b.proposerName || '',
      targetUid: b.targetUid || '',
      targetName: b.targetName || '',
      opponentUid: b.opponentUid || '',
      opponentName: b.opponentName || '',
      status: b.status,
      result: b.result || '',
      winnerUid: b.winnerUid || '',
    });
  }
  return out;
}

async function cardsFetch(env, gid, uid) {
  await accessToken(env);
  let g = await readDoc(env, `cards/${gid}`);
  if (g && isFl(g.game)) {
    // Jeux rapides (pas de paris) : on ne rejoue le temps écoulé que si le délai est dépassé.
    if (g.status === 'playing' && g.over !== true && Date.now() - intOr(g.turnAt, 0) > cardsTurnMs(g)) {
      await cardsDrive(env, gid);
      g = (await readDoc(env, `cards/${gid}`)) || g;
    }
    if (cardsFlBets(g.game) && intOr(g.betsN, 0) > 0 && g.betsDone !== true && (g.status !== 'waiting' || g.over === true)) {
      try {
        await cardsBetsSync(env, gid);
        g = (await readDoc(env, `cards/${gid}`)) || g;
      } catch (e) {
        console.error('cards bets', e);
      }
    }
  } else if (g && g.status === 'waiting' && g.over !== true) {
    // Salle d'attente : rien à faire avancer, on évite 2 lectures (réponse plus rapide).
  } else {
    await cardsDrive(env, gid);
    try {
      await cardsBetsSync(env, gid);
    } catch (e) {
      console.error('cards bets', e);
    }
    g = await readDoc(env, `cards/${gid}`);
  }
  if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
  if (!playersOf(g).some((p) => p.uid === uid)) {
    throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
  }
  if (g.over === true && g.settled !== true) {
    try {
      await settleGame({ uid, data: { gameId: gid }, env });
      g = (await readDoc(env, `cards/${gid}`)) || g;
    } catch (e) {
      console.error('cards settle', e);
    }
  }
  const view = cardsView(gid, g, uid);
  view.bets = intOr(g.betsN, 0) > 0 ? await cardsReadBets(env, gid) : [];
  return view;
}

function cardsNewDoc({ game, stake, maxPlayers, isPublic, uid, name, round = 1, prevId = '', order = [], dealerUid = '' }) {
  return {
    game,
    hostUid: uid,
    dealerUid: dealerUid || uid,
    code: tournCode(),
    isPublic: !!isPublic,
    stake,
    pot: stake,
    maxPlayers,
    status: 'waiting',
    over: false,
    round,
    prevId,
    nextId: '',
    order,
    players: [{ uid, name }],
    uids: [uid],
    paid: stake > 0 ? [uid] : [],
    createdAtMs: Date.now(),
  };
}

const CARDS_PUSH_LABELS = { tiah: 'Tiah', boubayah: 'Boubayah', fapfap: 'Fap-Fap', anticote: 'Anti-Cote', tchek: 'Tchek Games' };
async function pushHostName(env, uid) {
  const u = await readDoc(env, `users/${uid}`);
  return u ? tournName(u) : '';
}

async function cardsCreate({ uid, data, env }) {
  const game = cardsGameOf(data.game);
  const stake = cardsStakeOf(data, game);
  const maxPlayers = Math.min(game === 'fapfap' || game === 'tchek' ? 4 : game === 'anticote' ? 5 : 6, Math.max(2, intOr(data.maxPlayers, 4)));
  const esc = stake * (isEsc2(game) ? 2 : 1); // 2 x M bloqués
  const open = await queryDocs(env, 'cards', eqFilter('hostUid', uid), 100);
  if (open.filter((g) => g.status === 'waiting').length >= CARDS_MAX_OPEN_PER_HOST) {
    throw new HttpError('failed-precondition', `Tu as déjà ${CARDS_MAX_OPEN_PER_HOST} salles ouvertes.`);
  }
  const id = newGameId();
  const fapLoc0 = isFl(game) && maxPlayers >= 3 ? fapLoc(data) : null; // position obligatoire à 3-4 joueurs (pas à 2)
  await runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (stake > 0) {
      if (balanceOf(me) < esc) throw new HttpError('failed-precondition', 'Solde insuffisant.');
      tx.write(`users/${uid}`, { incr: { balance: -esc } });
    }
    tx.write(`cards/${id}`, {
      create: true,
      set: {
        ...cardsNewDoc({ game, stake, maxPlayers, isPublic: data.isPublic !== false, uid, name: tournName(me) }),
        ...(fapLoc0 ? { locs: { [uid]: fapLoc0 } } : {}),
      },
      serverTime: ['createdAt'],
    });
  });
  if (data.isPublic !== false) {
    later(env, (async () => pushNewGame(env, uid, { col: 'cards', label: CARDS_PUSH_LABELS[game] || 'cartes', host: await pushHostName(env, uid), stake }))());
  }
  return cardsFetch(env, id, uid);
}

async function cardsJoin({ uid, data, env }) {
  let gid = idStr(data.gameId);
  if (!gid && typeof data.code === 'string') {
    const code = data.code.trim().toUpperCase();
    const found = (await queryDocs(env, 'cards', eqFilter('code', code), 5)).filter((g) => g.status === 'waiting');
    if (!found.length) throw new HttpError('not-found', 'Code inconnu ou salle fermée.');
    gid = found[0].id;
  }
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const [g, meDoc] = await tx.getMany([path, `users/${uid}`]); // un seul aller-retour
    if (!g || g.status !== 'waiting') throw new HttpError('failed-precondition', "Cette salle n'est plus ouverte.");
    const players = playersOf(g);
    if (players.some((p) => p.uid === uid)) return;
    if (players.length >= intOr(g.maxPlayers, 6)) throw new HttpError('failed-precondition', 'Salle complète.');
    const jLoc = isFl(g.game) && intOr(g.maxPlayers, 4) >= 3 ? fapLoc(data) : null; // position obligatoire à 3-4 joueurs (pas à 2)
    if (jLoc && fapTooClose(g.locs, uid, jLoc)) throw new HttpError('failed-precondition', FAP_CLOSE_MSG);
    const me = meDoc;
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const stake = intOr(g.stake, 0);
    const esc = stake * (isEsc2(g.game) ? 2 : 1);
    if (stake > 0) {
      if (balanceOf(me) < esc) throw new HttpError('failed-precondition', 'Solde insuffisant.');
      tx.write(`users/${uid}`, { incr: { balance: -esc } });
    }
    const np = [...players, { uid, name: tournName(me) }];
    tx.write(path, {
      set: {
        ...(jLoc ? { locs: { ...(g.locs || {}), [uid]: jLoc } } : {}),
        players: np,
        uids: np.map((p) => p.uid),
        paid: stake > 0 ? [...(Array.isArray(g.paid) ? g.paid : []), uid] : [],
        pot: stake * np.length,
      },
    });
  });
  return cardsFetch(env, gid, uid);
}

async function cardsLeave({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g || g.status !== 'waiting') throw new HttpError('failed-precondition', 'On ne peut quitter qu\'avant le départ.');
    const players = playersOf(g);
    if (!players.some((p) => p.uid === uid)) return;
    const stake = intOr(g.stake, 0);
    if (stake > 0) tx.write(`users/${uid}`, { incr: { balance: stake * (isEsc2(g.game) ? 2 : 1) } });
    const chatPatch = cardsChatDrop(tx, g, uid);
    if (intOr(g.betsN, 0) > 0) {
      // Défis en attente ou acceptés qui concernent ce joueur : annulés, mises rendues.
      for (const { path: bp, b } of await cardsLoadBets(tx, gid)) {
        if (b.status === 'open' && (b.proposerUid === uid || b.targetUid === uid)) {
          tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
          tx.write(bp, { set: { status: b.proposerUid === uid ? 'cancelled' : 'declined' }, serverTime: ['closedAt'] });
        } else if (b.status === 'accepted' && (b.proposerUid === uid || b.opponentUid === uid)) {
          tx.write(`users/${b.proposerUid}`, { incr: { balance: b.amount } });
          tx.write(`users/${b.opponentUid}`, { incr: { balance: b.amount } });
          tx.write(bp, { set: { status: 'cancelled' }, serverTime: ['closedAt'] });
        }
      }
    }
    const np = players.filter((p) => p.uid !== uid);
    if (!np.length) {
      tx.write(path, { set: { status: 'cancelled', over: true, settled: true, players: [], uids: [], paid: [], pot: 0, ...chatPatch } });
      return;
    }
    const keepLocs = g.locs ? Object.fromEntries(Object.entries(g.locs).filter(([u]) => u !== uid)) : null;
    tx.write(path, {
      set: {
        ...chatPatch,
        ...(keepLocs ? { locs: keepLocs } : {}),
        players: np,
        uids: np.map((p) => p.uid),
        paid: stake > 0 ? (Array.isArray(g.paid) ? g.paid : []).filter((u) => u !== uid) : [],
        pot: stake * np.length,
        hostUid: g.hostUid === uid ? np[0].uid : g.hostUid,
        dealerUid: (g.dealerUid || g.hostUid) === uid ? np[0].uid : g.dealerUid || g.hostUid,
      },
    });
  });
  return { ok: true };
}

async function cardsStart({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g || g.status !== 'waiting') throw new HttpError('failed-precondition', 'La manche a déjà commencé.');
    let players = playersOf(g);
    if (!players.some((p) => p.uid === uid)) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette salle.');
    if (players.length < 2) throw new HttpError('failed-precondition', 'Il faut au moins 2 joueurs.');
    if (isFl(g.game) && intOr(g.maxPlayers, 4) >= 3 && players.length >= 3) {
      // Chaque joueur doit avoir une position récente et personne ne doit être à moins de 150 m d'un autre.
      const locs = g.locs || {};
      for (const p of players) {
        const o = locs[p.uid];
        if (!o || Date.now() - intOr(o.ms, 0) > FAP_LOC_FRESH_MS) {
          throw new HttpError('failed-precondition', `La position de ${p.name || 'un joueur'} n'est pas à jour. Chacun doit garder la localisation activée et l'appli ouverte.`);
        }
      }
      for (const p of players) {
        if (fapTooClose(locs, p.uid, locs[p.uid])) {
          throw new HttpError('failed-precondition', 'Deux joueurs sont à moins de 150 m l\'un de l\'autre : la manche ne peut pas démarrer. Éloignez-vous ou quittez la table.');
        }
      }
    }
    const dealerOk = uid === (g.dealerUid || g.hostUid);
    if (!dealerOk && Date.now() - intOr(g.createdAtMs, 0) <= CARDS_START_AFTER_MS) {
      throw new HttpError('permission-denied', 'Seul le distributeur peut lancer la manche.');
    }
    // sièges : même ordre que la manche précédente
    const ord = Array.isArray(g.order) ? g.order : [];
    if (ord.length) {
      players = [...players].sort((a, b) => {
        const ia = ord.indexOf(a.uid);
        const ib = ord.indexOf(b.uid);
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
      });
    }
    const uids = players.map((p) => p.uid);
    let dealer = g.dealerUid || g.hostUid;
    if (!uids.includes(dealer)) dealer = uids[0];
    const di = uids.indexOf(dealer);
    const clockwise = (from, n) => Array.from({ length: n }, (_, k) => uids[(from + k) % uids.length]);
    const deck = cardsDeck(g.game);
    const set = {
      players,
      uids,
      order: uids,
      dealerUid: dealer,
      first: dealer,
      maxPlayers: uids.length,
      status: 'playing',
      turnIdx: 0,
      opened: [],
      curOpen: false,
      turnAt: Date.now(),
      startedMs: Date.now(),
    };
    if (g.game === 'fapfap') {
      const hands = Object.fromEntries(uids.map((u) => [u, []]));
      const from = clockwise(di + 1, uids.length); // le 1er après le distributeur entame
      for (let r = 0; r < 3; r++) for (const u of from) hands[u].push(deck.pop()); // phase 1 : 3 cartes
      for (let r = 0; r < 2; r++) for (const u of from) hands[u].push(deck.pop()); // phase 2 : 2 cartes
      set.hands = hands;
      set.deck = [];
      set.seq = from;
      set.turnIdx = 0;
      set.leaderIdx = 0;
      set.trick = [];
      set.trickNo = 0;
      set.tbl = Object.fromEntries(uids.map((u) => [u, []]));
      const w = fapDealWinner(hands, from);
      if (w) {
        // combinaison gagnante dès la distribution : la manche s'arrête
        Object.assign(set, {
          over: true,
          finishedMs: Date.now(),
          winnerUids: [w.uid],
          corat: w.combo.corat,
          fapRule: w.combo.rule,
          nextDealerUid: w.uid,
        });
      }
    } else if (g.game === 'tchek') {
      if (uids.length > 4) throw new HttpError('failed-precondition', '4 joueurs au maximum.');
      const from = clockwise(di + 1, uids.length);
      Object.assign(set, tcDealFields(from, tcDeck()));
    } else if (g.game === 'anticote') {
      if (uids.length > 5) throw new HttpError('failed-precondition', '5 joueurs au maximum.');
      const from = clockwise(di + 1, uids.length); // le 1er après le distributeur joue en premier
      Object.assign(set, acRoundFields(from, deck), { rep: 0, tieNote: { n: 0, uids: [], best: 0, totals: {}, doubled: [], quit: [], hands: {} }, acKorate: [] });
      const M0 = intOr(g.stake, 0);
      if (M0 > 0) {
        const pd = Array.isArray(g.paid) && g.paid.length ? g.paid : uids;
        set.contrib = Object.fromEntries(pd.map((u) => [u, M0]));
        set.esc = Object.fromEntries(pd.map((u) => [u, M0 * 2]));
        set.pot = M0 * pd.length;
      }
      const dw = acDealWinner(set.hands, from);
      if (dw) Object.assign(set, acSettleWin({ ...g, ...set }, { type: 'win', uid: dw.uid, rule: dw.combo.rule, corat: dw.combo.corat }));
    } else if (g.game === 'tiah') {
      const hands = Object.fromEntries(uids.map((u) => [u, []]));
      const from = clockwise(di, uids.length);
      for (let k = 0; k < 2 * uids.length; k++) hands[from[k % uids.length]].push(deck.pop());
      set.hands = hands;
      // 10 cartes ouvertes au milieu, visibles de tous avant la 1re ouverture (la 1re tirée = le dessus).
      const mid = [];
      for (let k = 0; k < 10 && deck.length; k++) mid.push(deck.pop());
      set.deck = mid.reverse();
      set.seq = from; // le 1er joueur ouvre en premier
    } else {
      const plain = Object.fromEntries(uids.map((u) => [u, []]));
      const bouba = Object.fromEntries(uids.map((u) => [u, []]));
      const from = clockwise(di + 1, uids.length); // distribution et révélation après le distributeur
      for (let r = 0; r < 3; r++) for (const u of from) plain[u].push(deck.pop());
      // MILLION plus fréquent : chaque joueur, à égalité, a MILLION_BOOST_PERCENT % de chances de recevoir
      // directement deux 3 (s'il en reste deux dans le paquet) ; sinon distribution normale.
      for (const u of from) {
        if (crypto.getRandomValues(new Uint32Array(1))[0] % 100 < MILLION_BOOST_PERCENT) {
          const idx = [];
          for (let i = 0; i < deck.length && idx.length < 2; i++) if (cardVal(deck[i]) === 3) idx.push(i);
          if (idx.length === 2) {
            bouba[u].push(deck[idx[0]], deck[idx[1]]);
            deck.splice(idx[1], 1);
            deck.splice(idx[0], 1);
          }
        }
      }
      for (let r = 0; r < 2; r++) for (const u of from) if (bouba[u].length < 2) bouba[u].push(deck.pop());
      set.plain = plain;
      set.bouba = bouba;
      set.deck = [];
      set.seq = from;
    }
    if ((g.game === 'tiah' || g.game === 'anticote') && cardsChatOf(g).entries.length) await cardsChatSettle(tx, gid, g, set); // pari CHAT
    set.turnAt = Date.now() + 3000; // + 3 s pour le 1er joueur : le temps de voir la distribution
    tx.write(path, { set, serverTime: ['startedAt'] });
  });
  return cardsFetch(env, gid, uid);
}

async function cardsAct(uid, data, env, act) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  if (act !== 'open') throw new HttpError('invalid-argument', 'Action inconnue.');
  await accessToken(env);
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const d = await tx.get(path);
    if (!d || d.status !== 'playing' || d.over === true) throw new HttpError('failed-precondition', 'La manche est terminée.');
    const cur = (d.seq || [])[intOr(d.turnIdx, 0)];
    if (cur !== uid) throw new HttpError('failed-precondition', "Ce n'est pas encore ton tour.");
    if (d.game === 'tchek') throw new HttpError('invalid-argument', 'Action inconnue.');
    if (d.game === 'anticote' && d.phase !== 'open') throw new HttpError('failed-precondition', 'Joue d\'abord une carte de la famille demandée.');
    await cardsWritePatch(tx, path, d, d.game === 'anticote' ? acOpen(d, uid) : cardsApplyOpen(d, uid));
  });
  return cardsFetch(env, gid, uid);
}

const cardsOpen = ({ uid, data, env }) => cardsAct(uid, data, env, 'open');

/** Fap-Fap, salle d'attente : le joueur actualise sa position (toutes les 30 s). */
async function cardsLoc({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  const loc = fapLoc(data);
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g || !isFl(g.game) || g.over === true || intOr(g.maxPlayers, 4) < 3) return;
    if (g.status !== 'waiting' && g.status !== 'playing') return;
    if (!playersOf(g).some((p) => p.uid === uid)) return;
    const set = { locs: { ...(g.locs || {}), [uid]: loc } };
    // Pendant la manche : deux joueurs à moins de 150 m = partie signalée (à vérifier par l'admin).
    if (g.status === 'playing' && fapTooClose(g.locs, uid, loc)) {
      set.proxFlag = true;
      set.proxAt = Date.now();
    }
    tx.write(path, { set });
  });
  return { ok: true };
}

/** Fap-Fap : jouer une carte (le serveur vérifie le tour, la main et la famille demandée). */
async function cardsPlay({ uid, data, env }) {
  const gid = idStr(data.gameId);
  const card = data.pass === true ? 0 : intOr(data.card, -1);
  if (!gid || card < 0) throw new HttpError('invalid-argument', 'Carte invalide.');
  await accessToken(env);
  // (le temps écoulé est rejoué par cardsFetch)
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const d = await tx.get(path);
    if (!d || (d.game !== 'fapfap' && d.game !== 'anticote' && d.game !== 'tchek')) throw new HttpError('invalid-argument', 'Jeu inconnu.');
    if (d.status !== 'playing' || d.over === true) throw new HttpError('failed-precondition', 'La manche est terminée.');
    const cur = (d.seq || [])[intOr(d.turnIdx, 0)];
    if (data.early === true && d.game === 'fapfap') {
      tx.write(path, { set: fapEarly(d, uid, card) });
      return;
    }
    if (cur !== uid) throw new HttpError('failed-precondition', "Ce n'est pas encore ton tour.");
    if (data.pass === true && d.game === 'fapfap') {
      tx.write(path, { set: fapPass(d, uid) });
      return;
    }
    if (d.game === 'tchek') {
      tx.write(path, { set: tcPlay(d, uid, card, intOr(data.suit, -1), data.tchek === true) });
    } else if (d.game === 'anticote') {
      if (d.phase !== 'play') throw new HttpError('failed-precondition', 'Ouvre tes cartes.');
      await cardsWritePatch(tx, path, d, acPlay(d, uid, card));
    } else tx.write(path, { set: fapPlay(d, uid, card) });
  });
  return cardsFetch(env, gid, uid);
}

/** Tchek Games : piocher (1 carte, ou toute la pénalité en cours). */
async function cardsDraw({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  await accessToken(env);
  await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const d = await tx.get(path);
    if (!d || d.game !== 'tchek') throw new HttpError('invalid-argument', 'Jeu inconnu.');
    if (d.status !== 'playing' || d.over === true) throw new HttpError('failed-precondition', 'La manche est terminée.');
    const cur = (d.seq || [])[intOr(d.turnIdx, 0)];
    if (cur !== uid) throw new HttpError('failed-precondition', "Ce n'est pas encore ton tour.");
    tx.write(path, { set: tcDraw(d, uid) });
  });
  return cardsFetch(env, gid, uid);
}

async function cardsGet({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  return cardsFetch(env, gid, uid);
}

/** Manche suivante : crée la salle (le premier qui clique mise), les autres la rejoignent. */
async function cardsRematch({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  const nid = await runTx(env, async (tx) => {
    const path = `cards/${gid}`;
    const g = await tx.get(path);
    if (!g || g.over !== true) throw new HttpError('failed-precondition', "La manche n'est pas terminée.");
    if (!playersOf(g).some((p) => p.uid === uid)) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    if (g.nextId) return g.nextId;
    const rLoc = isFl(g.game) && intOr(g.maxPlayers, 4) >= 3 ? fapLoc(data) : null; // position obligatoire à 3-4 joueurs (pas à 2)
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const stake = intOr(g.stake, 0);
    const esc = stake * (isEsc2(g.game) ? 2 : 1);
    if (stake > 0) {
      if (balanceOf(me) < esc) throw new HttpError('failed-precondition', 'Solde insuffisant.');
      tx.write(`users/${uid}`, { incr: { balance: -esc } });
    }
    const id = newGameId();
    const doc = cardsNewDoc({
      game: g.game,
      stake,
      maxPlayers: intOr(g.maxPlayers, g.game === 'fapfap' || g.game === 'tchek' ? 4 : g.game === 'anticote' ? 5 : 6),
      isPublic: false,
      uid,
      name: tournName(me),
      round: intOr(g.round, 1) + 1,
      prevId: gid,
      order: Array.isArray(g.order) ? g.order : [],
      dealerUid: g.nextDealerUid || uid,
    });
    if (rLoc) doc.locs = { [uid]: rLoc };
    tx.write(`cards/${id}`, { create: true, set: doc, serverTime: ['createdAt'] });
    tx.write(path, { set: { nextId: id } });
    return id;
  });
  return cardsFetch(env, nid, uid);
}

/** Salles publiques ouvertes + mes salles en cours. */
async function cardsList({ uid, data, env }) {
  await accessToken(env);
  later(env, maybeSweep(env));
  const game = data && (data.game === 'tiah' || data.game === 'boubayah' || data.game === 'fapfap' || data.game === 'anticote' || data.game === 'tchek') ? data.game : '';
  const waiting = await queryDocs(env, 'cards', eqFilter('status', 'waiting'), 30);
  // Actualisation légère (toutes les ~10 s) : on ne relit pas « mes parties » (économie de lectures).
  const light = !!(data && data.light === true);
  const mine = light ? [] : await queryDocs(env, 'cards', arrayContainsFilter('uids', uid), 60);
  const row = (g) => ({
    id: g.id,
    game: g.game,
    hostName: (playersOf(g)[0] && playersOf(g)[0].name) || '',
    stake: intOr(g.stake, 0),
    count: playersOf(g).length,
    maxPlayers: intOr(g.maxPlayers, 6),
    round: intOr(g.round, 1),
    status: g.status,
  });
  const fresh = Date.now() - 30 * 60 * 1000;
  return {
    open: waiting
      .filter((g) => g.isPublic === true && (!game || g.game === game) && intOr(g.createdAtMs, 0) > fresh)
      .filter((g) => !playersOf(g).some((p) => p.uid === uid))
      .map(row),
    mine: light
      ? null
      : mine
          .filter((g) => (g.status === 'waiting' || g.status === 'playing') && g.over !== true && (!game || g.game === game))
          .map(row),
  };
}

// ======================================================================
// PARIS PAR DERRIÈRE — SPORTS (paris P2P : duel à mise égale, 7,5 % de commission)
//   sportEvents/{id} : rencontre créée par l'administrateur
//   sportBets/{id}   : pari d'un joueur (open → matched → settled / refunded / cancelled)
// Les mises sont débitées tout de suite (séquestre) et rendues ou payées au règlement.
// ======================================================================

const SPORT_COMMISSION_PERCENT = 7.5;
const SPORT_MAX_OPEN_PER_PLAYER = 10;
const SPORT_CATEGORIES = ['football', 'combats'];

function sportEventOut(e) {
  return {
    id: e.id,
    category: e.category || 'football',
    subcategory: e.subcategory || '',
    teamA: e.teamA || '',
    teamB: e.teamB || '',
    startsAt: intOr(e.startsAt, 0),
    status: e.status || 'upcoming',
    result: e.result || '',
  };
}

/** Rembourse un pari encore actif (open ou matched). Sans danger si répété. */
async function sportRefundBet(env, betId, newStatus) {
  await runTx(env, async (tx) => {
    const path = `sportBets/${betId}`;
    const b = await tx.get(path);
    if (!b || b.active !== true) return;
    const amt = intOr(b.amount, 0);
    tx.write(`users/${b.proposerUid}`, { incr: { balance: amt } });
    if (b.status === 'matched' && b.opponentUid) tx.write(`users/${b.opponentUid}`, { incr: { balance: amt } });
    tx.write(path, { set: { status: newStatus, active: false }, serverTime: ['closedAt'] });
  });
}

/** Paris ouverts (sans challenger) d'un match dont l'heure limite est passée : remboursés. */
async function sportExpireOpen(env, events, bets) {
  const now = Date.now();
  const late = new Set(
    events.filter((e) => e.status === 'upcoming' && intOr(e.startsAt, 0) <= now).map((e) => e.id),
  );
  if (!late.size) return;
  for (const b of bets) {
    if (b.status === 'open' && b.active === true && late.has(b.eventId)) {
      try {
        await sportRefundBet(env, b.id, 'refunded');
        b.status = 'refunded';
        b.active = false;
      } catch (e) {
        console.error('sport expire', e);
      }
    }
  }
}

async function sportsList({ uid, env }) {
  await accessToken(env);
  const isAdmin = adminIds(env).includes(uid);
  let events = (await queryDocs(env, 'sportEvents', eqFilter('visible', true), 150)).filter(
    (e) => e.status !== 'cancelled' || isAdmin,
  );
  const active = await queryDocs(env, 'sportBets', eqFilter('active', true), 500);
  await sportExpireOpen(env, events, active);
  const mine = await queryDocs(env, 'sportBets', arrayContainsFilter('participants', uid), 80);
  events.sort((a, b) => intOr(a.startsAt, 0) - intOr(b.startsAt, 0));
  const now = Date.now();
  const outEvents = events.map((e) => {
    const o = sportEventOut(e);
    const open = active.filter((b) => b.eventId === e.id && b.status === 'open');
    o.open = open.map((b) => ({
      id: b.id,
      side: b.side,
      amount: intOr(b.amount, 0),
      prize: prizeOf(intOr(b.amount, 0) * 2, SPORT_COMMISSION_PERCENT),
      proposerName: b.proposerName || '',
      mine: b.proposerUid === uid,
    }));
    o.matched = active.filter((b) => b.eventId === e.id && b.status === 'matched').length;
    return o;
  });
  const myBets = mine
    .map((b) => ({
      id: b.id,
      eventId: b.eventId,
      side: b.side,
      amount: intOr(b.amount, 0),
      status: b.status,
      role: b.proposerUid === uid ? 'proposer' : 'challenger',
      opponentName: b.proposerUid === uid ? b.opponentName || '' : b.proposerName || '',
      mySide: b.proposerUid === uid ? b.side : b.side === 'a' ? 'b' : 'a',
      winnerUid: b.winnerUid || '',
      won: b.winnerUid === uid,
      prize: intOr(b.prize, 0),
    }))
    .sort((a, b) => (a.status === 'open' || a.status === 'matched' ? -1 : 1) - (b.status === 'open' || b.status === 'matched' ? -1 : 1));
  return { admin: isAdmin, now, commission: SPORT_COMMISSION_PERCENT, events: outEvents, myBets };
}

async function sportBetCreate({ uid, data, env }) {
  const eventId = idStr(data.eventId);
  const side = data.side === 'b' ? 'b' : data.side === 'a' ? 'a' : '';
  const amount = intOr(data.amount, -1);
  if (!eventId || !side) throw new HttpError('invalid-argument', 'Pari invalide.');
  if (amount < BET_MIN || amount > BET_MAX) {
    throw new HttpError('invalid-argument', `Mise : entre ${BET_MIN} et ${BET_MAX} FCFA.`);
  }
  const betId = newId();
  await runTx(env, async (tx) => {
    const e = await tx.get(`sportEvents/${eventId}`);
    if (!e || e.status !== 'upcoming') throw new HttpError('failed-precondition', 'Ce match n\'accepte plus de paris.');
    if (Date.now() >= intOr(e.startsAt, 0)) throw new HttpError('failed-precondition', 'Les paris sont clos pour ce match.');
    const u = await tx.get(`users/${uid}`);
    if (balanceOf(u) < amount) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    const mine = await queryDocs(env, 'sportBets', arrayContainsFilter('participants', uid), 80);
    if (mine.filter((b) => b.status === 'open' && b.proposerUid === uid).length >= SPORT_MAX_OPEN_PER_PLAYER) {
      throw new HttpError('failed-precondition', 'Trop de paris en attente de challenger.');
    }
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(`sportBets/${betId}`, {
      create: true,
      set: {
        eventId,
        proposerUid: uid,
        proposerName: tournName(u),
        side,
        amount,
        status: 'open',
        active: true,
        participants: [uid],
        opponentUid: '',
        opponentName: '',
      },
      serverTime: ['createdAt'],
    });
  });
  return sportsList({ uid, env });
}

async function sportBetAccept({ uid, data, env }) {
  const betId = idStr(data.betId);
  if (!betId) throw new HttpError('invalid-argument', 'Pari invalide.');
  await runTx(env, async (tx) => {
    const b = await tx.get(`sportBets/${betId}`);
    if (!b || b.status !== 'open' || b.active !== true) throw new HttpError('failed-precondition', "Ce pari n'est plus disponible.");
    if (b.proposerUid === uid) throw new HttpError('failed-precondition', 'Tu ne peux pas relever ton propre pari.');
    const e = await tx.get(`sportEvents/${b.eventId}`);
    if (!e || e.status !== 'upcoming' || Date.now() >= intOr(e.startsAt, 0)) {
      throw new HttpError('failed-precondition', 'Les paris sont clos pour ce match.');
    }
    const u = await tx.get(`users/${uid}`);
    const amount = intOr(b.amount, 0);
    if (balanceOf(u) < amount) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    tx.write(`users/${uid}`, { incr: { balance: -amount } });
    tx.write(`sportBets/${betId}`, {
      set: { status: 'matched', opponentUid: uid, opponentName: tournName(u), pool: amount * 2 },
      union: { participants: [uid] },
      serverTime: ['matchedAt'],
    });
  });
  return sportsList({ uid, env });
}

async function sportBetCancel({ uid, data, env }) {
  const betId = idStr(data.betId);
  if (!betId) throw new HttpError('invalid-argument', 'Pari invalide.');
  await runTx(env, async (tx) => {
    const b = await tx.get(`sportBets/${betId}`);
    if (!b || b.status !== 'open' || b.active !== true) throw new HttpError('failed-precondition', "Ce pari n'est plus en attente.");
    if (b.proposerUid !== uid) throw new HttpError('permission-denied', "Ce pari n'est pas le tien.");
    tx.write(`users/${uid}`, { incr: { balance: intOr(b.amount, 0) } });
    tx.write(`sportBets/${betId}`, { set: { status: 'cancelled', active: false }, serverTime: ['closedAt'] });
  });
  return sportsList({ uid, env });
}

async function adminSportEventSave({ uid, data, env }) {
  requireAdmin(uid, env);
  const category = SPORT_CATEGORIES.includes(data.category) ? data.category : 'football';
  const teamA = String(data.teamA || '').trim().slice(0, 40);
  const teamB = String(data.teamB || '').trim().slice(0, 40);
  const subcategory = String(data.subcategory || '').trim().slice(0, 40);
  const startsAt = intOr(data.startsAt, 0);
  if (!teamA || !teamB || teamA.toLowerCase() === teamB.toLowerCase()) {
    throw new HttpError('invalid-argument', 'Indique deux équipes ou combattants différents.');
  }
  if (startsAt <= Date.now()) throw new HttpError('invalid-argument', "L'heure limite des paris doit être dans le futur.");
  const id = idStr(data.id) || newId();
  await runTx(env, async (tx) => {
    const old = await tx.get(`sportEvents/${id}`);
    if (old && old.status !== 'upcoming') throw new HttpError('failed-precondition', 'Ce match est déjà terminé ou annulé.');
    tx.write(`sportEvents/${id}`, {
      set: { category, subcategory, teamA, teamB, startsAt, status: 'upcoming', visible: true, result: '' },
      ...(old ? {} : { serverTime: ['createdAt'] }),
    });
  });
  return sportsList({ uid, env });
}

async function sportActiveBets(env, eventId) {
  return queryDocs(env, 'sportBets', eqFilter('eventId', eventId), 500).then((l) => l.filter((b) => b.active === true));
}

async function adminSportEventCancel({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  if (!id) throw new HttpError('invalid-argument', 'Match inconnu.');
  await runTx(env, async (tx) => {
    const e = await tx.get(`sportEvents/${id}`);
    if (!e) throw new HttpError('not-found', 'Match introuvable.');
    if (e.status === 'finished') throw new HttpError('failed-precondition', 'Ce match est déjà terminé.');
    tx.write(`sportEvents/${id}`, { set: { status: 'cancelled' } });
  });
  for (const b of await sportActiveBets(env, id)) await sportRefundBet(env, b.id, 'refunded');
  return sportsList({ uid, env });
}

/** Saisie du résultat : a, b ou draw. Nul = remboursement des deux sans commission. */
async function adminSportEventResult({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  const result = data.result;
  if (!id || !['a', 'b', 'draw'].includes(result)) throw new HttpError('invalid-argument', 'Résultat invalide.');
  await runTx(env, async (tx) => {
    const e = await tx.get(`sportEvents/${id}`);
    if (!e) throw new HttpError('not-found', 'Match introuvable.');
    if (e.status === 'finished' || e.status === 'cancelled') {
      throw new HttpError('failed-precondition', 'Ce match est déjà clôturé.');
    }
    tx.write(`sportEvents/${id}`, { set: { status: 'finished', result }, serverTime: ['finishedAt'] });
  });
  for (const b of await sportActiveBets(env, id)) {
    if (b.status !== 'matched' || result === 'draw') {
      await sportRefundBet(env, b.id, 'refunded');
      continue;
    }
    await runTx(env, async (tx) => {
      const path = `sportBets/${b.id}`;
      const cur = await tx.get(path);
      if (!cur || cur.active !== true || cur.status !== 'matched') return;
      const amount = intOr(cur.amount, 0);
      const pool = amount * 2;
      const prize = prizeOf(pool, SPORT_COMMISSION_PERCENT);
      const winner = cur.side === result ? cur.proposerUid : cur.opponentUid;
      tx.write(`users/${winner}`, { incr: { balance: prize } });
      tx.write(path, {
        set: { status: 'settled', active: false, winnerUid: winner, prize, commission: pool - prize },
        serverTime: ['closedAt'],
      });
      // Les parrains et partenaires touchent leur part de la commission, le reste revient à Katika.
      const commission = pool - prize;
      const ref = await referralPayout(tx, [cur.proposerUid, cur.opponentUid], commission, { gameId: id, mode: 'sport', ref: b.id });
      tx.write(`users/${cur.proposerUid}`, { incr: { wagered: amount } });
      tx.write(`users/${cur.opponentUid}`, { incr: { wagered: amount } });
      await houseAdd(tx, commission - ref.referral - ref.partner);
    });
  }
  return sportsList({ uid, env });
}

// ======================================================================
// PARIS PAR DERRIÈRE — COURSES (pari mutuel à coefficient)
//   races/{id}        : course créée par l'administrateur
//   raceBets/{id}     : billet (formule, numéros, coefficient)
//   raceSettle/{id}_{formule} : règlement d'une formule (une seule fois)
//   raceCarry/{formule}       : cagnotte reportée (aucun gagnant)
// Ticket de base 100 FCFA = coefficient 1. Commission 25 % de la masse.
// Gain par unité = (masse × 75 % + report) / total des coefficients gagnants.
// ======================================================================

const RACE_UNIT = 100;
const RACE_COMMISSION_PERCENT = 25;
const RACE_MAX_COEF = 1000;
// formule : nombre de numéros à choisir, et rang dans lequel ils doivent arriver (l'ordre n'importe pas)
const RACE_FORMULAS = {
  couple: { picks: 2, within: 3, exact: false }, // 2 numéros parmi les 3 premiers
  deux4: { picks: 2, within: 4, exact: false }, // 2 numéros parmi les 4 premiers
  tierce: { picks: 3, within: 3, exact: true }, // les 3 premiers, dans le désordre
  quinte: { picks: 5, within: 5, exact: true }, // les 5 premiers, dans le désordre
  super6: { picks: 6, within: 6, exact: true }, // les 6 premiers, dans le désordre
};
const RACE_FORMULA_KEYS = Object.keys(RACE_FORMULAS);

function raceWins(formula, picks, arrival) {
  const f = RACE_FORMULAS[formula];
  if (!f || !Array.isArray(picks) || !Array.isArray(arrival)) return false;
  const top = arrival.slice(0, f.within);
  if (top.length < f.within) return false;
  if (f.exact) return picks.length === f.picks && picks.every((n) => top.includes(n));
  return picks.length === f.picks && picks.every((n) => top.includes(n));
}

function raceOut(r, carry) {
  const pools = {};
  const carries = {};
  for (const k of RACE_FORMULA_KEYS) {
    const gross = intOr(r[`pool_${k}`], 0);
    pools[k] = gross;
    carries[k] = intOr(carry[k], 0);
  }
  return {
    id: r.id,
    name: r.name || '',
    runners: intOr(r.runners, 0),
    startsAt: intOr(r.startsAt, 0),
    status: r.status || 'open',
    arrival: Array.isArray(r.arrival) ? r.arrival : [],
    pools,
    carries,
    nets: Object.fromEntries(RACE_FORMULA_KEYS.map((k) => [k, Math.floor((pools[k] * (100 - RACE_COMMISSION_PERCENT)) / 100) + carries[k]])),
  };
}

async function raceCarryAll(env) {
  const out = {};
  for (const k of RACE_FORMULA_KEYS) {
    const d = await readDoc(env, `raceCarry/${k}`);
    out[k] = d ? intOr(d.amount, 0) : 0;
  }
  return out;
}

async function racesList({ uid, env }) {
  await accessToken(env);
  const isAdmin = adminIds(env).includes(uid);
  const races = (await queryDocs(env, 'races', eqFilter('visible', true), 100)).filter(
    (r) => r.status !== 'cancelled' || isAdmin,
  );
  races.sort((a, b) => intOr(b.startsAt, 0) - intOr(a.startsAt, 0));
  const carry = await raceCarryAll(env);
  const mine = await queryDocs(env, 'raceBets', eqFilter('uid', uid), 100);
  mine.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
  return {
    admin: isAdmin,
    now: Date.now(),
    unit: RACE_UNIT,
    commission: RACE_COMMISSION_PERCENT,
    races: races.map((r) => raceOut(r, carry)),
    carry,
    myBets: mine.slice(0, 60).map((b) => ({
      id: b.id,
      raceId: b.raceId,
      formula: b.formula,
      picks: Array.isArray(b.picks) ? b.picks : [],
      coef: intOr(b.coef, 1),
      stake: intOr(b.stake, 0),
      status: b.status,
      payout: intOr(b.payout, 0),
    })),
  };
}

async function raceBetCreate({ uid, data, env }) {
  const raceId = idStr(data.raceId);
  const formula = String(data.formula || '');
  const f = RACE_FORMULAS[formula];
  const coef = intOr(data.coef, 0);
  if (!raceId || !f) throw new HttpError('invalid-argument', 'Pari invalide.');
  if (coef < 1 || coef > RACE_MAX_COEF) throw new HttpError('invalid-argument', `Coefficient : 1 à ${RACE_MAX_COEF}.`);
  const picks = Array.isArray(data.picks) ? data.picks.map((n) => intOr(n, 0)) : [];
  if (picks.length !== f.picks || new Set(picks).size !== picks.length) {
    throw new HttpError('invalid-argument', `Choisis exactement ${f.picks} numéros différents.`);
  }
  const stake = RACE_UNIT * coef;
  if (stake < BET_MIN || stake > BET_MAX) throw new HttpError('invalid-argument', 'Mise invalide.');
  const betId = newId();
  let ticketName = '';
  let ticketRace = '';
  await runTx(env, async (tx) => {
    const r = await tx.get(`races/${raceId}`);
    if (!r || r.status !== 'open') throw new HttpError('failed-precondition', "Cette course n'accepte plus de paris.");
    ticketRace = String(r.name || '');
    if (Date.now() >= intOr(r.startsAt, 0)) throw new HttpError('failed-precondition', 'Les paris sont clos pour cette course.');
    const runners = intOr(r.runners, 0);
    if (picks.some((n) => n < 1 || n > runners)) throw new HttpError('invalid-argument', `Numéros de 1 à ${runners}.`);
    const u = await tx.get(`users/${uid}`);
    if (balanceOf(u) < stake) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    ticketName = tournName(u);
    tx.write(`users/${uid}`, { incr: { balance: -stake } });
    tx.write(`races/${raceId}`, { incr: { [`pool_${formula}`]: stake } });
    tx.write(`raceBets/${betId}`, {
      create: true,
      set: {
        raceId,
        uid,
        name: tournName(u),
        formula,
        picks: [...picks].sort((a, b) => a - b),
        coef,
        stake,
        status: 'active',
        payout: 0,
        createdAtMs: Date.now(),
      },
      serverTime: ['createdAt'],
    });
  });
  const listed = await racesList({ uid, env });
  return {
    ...listed,
    ticket: {
      id: betId,
      no: String(betId).slice(-8).toUpperCase(),
      raceId,
      race: ticketRace,
      formula,
      picks: [...picks].sort((a, b) => a - b),
      coef,
      stake,
      by: ticketName,
      at: Date.now(),
    },
  };
}

async function adminRaceSave({ uid, data, env }) {
  requireAdmin(uid, env);
  const name = String(data.name || '').trim().slice(0, 60);
  const runners = intOr(data.runners, 0);
  const startsAt = intOr(data.startsAt, 0);
  if (!name) throw new HttpError('invalid-argument', 'Donne un nom à la course.');
  if (runners < 6 || runners > 20) throw new HttpError('invalid-argument', 'Nombre de partants : 6 à 20.');
  if (startsAt <= Date.now()) throw new HttpError('invalid-argument', "L'heure limite des paris doit être dans le futur.");
  const id = newId();
  await runTx(env, async (tx) => {
    const set = { name, runners, startsAt, status: 'open', visible: true, arrival: [] };
    for (const k of RACE_FORMULA_KEYS) set[`pool_${k}`] = 0;
    tx.write(`races/${id}`, { create: true, set, serverTime: ['createdAt'] });
  });
  return racesList({ uid, env });
}

async function raceBetsOf(env, raceId) {
  return queryDocs(env, 'raceBets', eqFilter('raceId', raceId), 2000);
}

async function adminRaceCancel({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  if (!id) throw new HttpError('invalid-argument', 'Course inconnue.');
  await runTx(env, async (tx) => {
    const r = await tx.get(`races/${id}`);
    if (!r) throw new HttpError('not-found', 'Course introuvable.');
    if (r.status === 'finished') throw new HttpError('failed-precondition', 'Cette course est terminée.');
    tx.write(`races/${id}`, { set: { status: 'cancelled' } });
  });
  for (const b of await raceBetsOf(env, id)) {
    if (b.status !== 'active') continue;
    await runTx(env, async (tx) => {
      const cur = await tx.get(`raceBets/${b.id}`);
      if (!cur || cur.status !== 'active') return;
      tx.write(`users/${cur.uid}`, { incr: { balance: intOr(cur.stake, 0) } });
      tx.write(`raceBets/${b.id}`, { set: { status: 'refunded' } });
    });
  }
  return racesList({ uid, env });
}

/** Règle UNE formule d'une course (idempotent : la fiche de règlement n'est créée qu'une fois). */
async function raceSettleFormula(env, race, formula, arrival) {
  const sid = `${race.id}_${formula}`;
  let st = await readDoc(env, `raceSettle/${sid}`);
  const bets = (await raceBetsOf(env, race.id)).filter((b) => b.formula === formula);
  if (!st) {
    const gross = bets.reduce((a, b) => a + intOr(b.stake, 0), 0);
    const winners = bets.filter((b) => raceWins(formula, b.picks, arrival));
    const totalCoef = winners.reduce((a, b) => a + intOr(b.coef, 0), 0);
    const commission = gross - Math.floor((gross * (100 - RACE_COMMISSION_PERCENT)) / 100);
    await runTx(env, async (tx) => {
      const carryDoc = await tx.get(`raceCarry/${formula}`);
      const carry = carryDoc ? intOr(carryDoc.amount, 0) : 0;
      const net = gross - commission + carry;
      let unit = 0;
      let carryAfter = 0;
      if (gross === 0 && carry === 0) {
        carryAfter = 0;
      } else if (totalCoef > 0) {
        unit = Math.floor(net / totalCoef);
        carryAfter = net - unit * totalCoef; // les centimes restent dans le report
      } else {
        carryAfter = net; // aucun gagnant : la cagnotte nette est reportée à la course suivante
      }
      tx.write(`raceCarry/${formula}`, { set: { amount: carryAfter } });
      tx.write(`raceSettle/${sid}`, {
        create: true,
        set: { raceId: race.id, formula, gross, commission, carryIn: carry, net, totalCoef, unit, carryAfter, winners: winners.length },
        serverTime: ['createdAt'],
      });
      // Part de commission de chaque billet : versée aux parrains/partenaires puis à Katika billet par billet.
      // Ici seulement le reste des arrondis revient à Katika.
      let shares = 0;
      if (gross > 0) for (const b of bets) shares += Math.floor((commission * intOr(b.stake, 0)) / gross);
      await houseAdd(tx, commission - shares);
    });
    st = await readDoc(env, `raceSettle/${sid}`);
  }
  const unit = intOr(st && st.unit, 0);
  const gross = intOr(st && st.gross, 0);
  const commission = intOr(st && st.commission, 0);
  for (const b of bets) {
    if (b.status !== 'active') continue;
    const win = raceWins(formula, b.picks, arrival) && unit > 0;
    await runTx(env, async (tx) => {
      const cur = await tx.get(`raceBets/${b.id}`);
      if (!cur || cur.status !== 'active') return;
      const stake = intOr(cur.stake, 0);
      const share = gross > 0 ? Math.floor((commission * stake) / gross) : 0;
      const ref = await referralPayout(tx, [cur.uid], share, { gameId: race.id, mode: 'course', ref: b.id });
      tx.write(`users/${cur.uid}`, { incr: { wagered: stake } });
      await houseAdd(tx, share - ref.referral - ref.partner);
      if (win) {
        const payout = unit * intOr(cur.coef, 0);
        tx.write(`users/${cur.uid}`, { incr: { balance: payout } });
        tx.write(`raceBets/${b.id}`, { set: { status: 'won', payout } });
      } else {
        tx.write(`raceBets/${b.id}`, { set: { status: 'lost' } });
      }
    });
  }
}

/** Saisie de l'arrivée officielle : les numéros dans l'ordre d'arrivée (6 premiers). */
async function adminRaceResult({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  const arrival = Array.isArray(data.arrival) ? data.arrival.map((n) => intOr(n, 0)) : [];
  if (!id) throw new HttpError('invalid-argument', 'Course inconnue.');
  let race;
  await runTx(env, async (tx) => {
    const r = await tx.get(`races/${id}`);
    if (!r) throw new HttpError('not-found', 'Course introuvable.');
    if (r.status === 'finished' || r.status === 'cancelled') throw new HttpError('failed-precondition', 'Cette course est déjà clôturée.');
    const runners = intOr(r.runners, 0);
    const need = Math.min(6, runners);
    const arr = r.status === 'settling' && Array.isArray(r.arrival) && r.arrival.length ? r.arrival : arrival;
    if (arr.length !== need || new Set(arr).size !== arr.length || arr.some((n) => n < 1 || n > runners)) {
      throw new HttpError('invalid-argument', `Indique les ${need} premiers numéros, tous différents, entre 1 et ${runners}.`);
    }
    tx.write(`races/${id}`, { set: { status: 'settling', arrival: arr } });
    race = { id, arrival: arr };
  });
  for (const k of RACE_FORMULA_KEYS) await raceSettleFormula(env, race, k, race.arrival);
  await runTx(env, async (tx) => {
    tx.write(`races/${id}`, { set: { status: 'finished' }, serverTime: ['finishedAt'] });
  });
  return racesList({ uid, env });
}


// ======================================================================
// Parties ouvertes : annulées après 30 min si personne n'a rejoint (mises remboursées)
// ======================================================================
const WAITING_CANCEL_MIN = 60;

async function sweepWaitingGames(env) {
  await accessToken(env);
  const limitMs = Date.now() - WAITING_CANCEL_MIN * 60 * 1000;
  let cancelled = 0;
  for (const col of ONLINE_COLLECTIONS) {
    let docs = [];
    try {
      docs = await queryDocs(env, col, eqFilter('status', 'waiting'), 200);
    } catch (e) {
      console.error('sweep query', col, e);
      continue;
    }
    for (const d of docs) {
      const t = typeof d.createdAt === 'string' ? Date.parse(d.createdAt) : 0;
      if (d.settled === true || d.over === true || !(t > 0 && t < limitMs)) continue;
      if (playersOf(d).length > 1) continue; // quelqu'un a rejoint : la salle reste ouverte
      try {
        const done = await runTx(env, async (tx) => {
          const path = `${col}/${d.id}`;
          const g = await tx.get(path);
          if (!g || g.status !== 'waiting' || g.settled === true || g.over === true) return false;
          if (playersOf(g).length > 1) return false;
          const stake = Math.max(0, intOr(g.stake, 0));
          refund(tx, chargedPaid(g), stake, g);
          tx.write(path, {
            set: {
              ...(col === 'cards' && cardsChatOf(g).entries.length ? cardsChatRefundAll(tx, g) : {}),
              settled: true,
              refunded: true,
              status: col === 'cards' || col === 'pileface' ? 'cancelled' : 'finished',
              over: true,
              commission: 0,
              referralPaid: 0,
              partnerPaid: 0,
            },
          });
          return true;
        });
        if (done) cancelled++;
      } catch (e) {
        console.error('sweep cancel', col, d.id, e);
      }
    }
  }
  return cancelled;
}

/** Lance le balayage au plus une fois par minute (appelé par la tâche planifiée et par quelques écrans). */
async function maybeSweep(env, force = false) {
  try {
    const now = Date.now();
    const st = await readDoc(env, 'app/sweep');
    if (!force && st && now - intOr(st.lastMs, 0) < 60000) return 0;
    await runTx(env, async (tx) => {
      tx.write('app/sweep', { set: { lastMs: now } });
    });
    const n = await sweepWaitingGames(env);
    return n;
  } catch (e) {
    console.error('maybeSweep', e);
    return 0;
  }
}

/** Historique des transactions d'argent : recharges, retraits, transferts.
 *  Le joueur voit le sien ; l'administrateur peut passer data.uid pour voir celui d'un joueur. */
async function txHistory({ uid, data, env }) {
  let target = uid;
  const asked = typeof data.uid === 'string' ? data.uid : '';
  if (asked && asked !== uid) {
    requireAdmin(uid, env);
    if (!ID_RE.test(asked)) throw new HttpError('invalid-argument', 'Joueur invalide.');
    target = asked;
  }
  const lim = 80;
  const q = (col, f, v) => queryDocs(env, col, eqFilter(f, v), lim).catch(() => []);
  const [dep, mdep, sdep, mwit, swit, tout, tin] = await Promise.all([
    q('deposits', 'uid', target),
    q('manualDeposits', 'uid', target),
    q('sebpayDeposits', 'uid', target),
    q('manualWithdrawals', 'uid', target),
    q('sebpayPayouts', 'uid', target),
    q('transfers', 'from', target),
    q('transfers', 'to', target),
  ]);
  const at = (d) => (typeof d.createdAt === 'string' ? d.createdAt : null);
  const st = (d) => (typeof d.status === 'string' ? d.status : 'pending');
  const opName = (d) => (d.operator === 'mtn' ? 'MTN MoMo' : d.operator === 'orange' ? 'Orange Money' : '');
  const items = [
    ...dep.map((d) => ({ id: d.id, kind: 'deposit', label: 'Recharge Mobile Money', amount: intOr(d.amount, 0), status: st(d), at: at(d), other: '' })),
    ...mdep.map((d) => ({ id: d.id, kind: 'deposit', label: `Recharge Local ${opName(d)}`.trim(), amount: intOr(d.amount, 0), status: st(d), at: at(d), other: '' })),
    ...sdep.map((d) => ({ id: d.id, kind: 'deposit', label: `Recharge International ${opName(d)}`.trim(), amount: intOr(d.amount, 0), status: st(d), at: at(d), other: '' })),
    ...mwit.map((d) => ({ id: d.id, kind: 'withdrawal', label: `Retrait Local ${opName(d)}`.trim(), amount: intOr(d.amount, 0), status: st(d), at: at(d), other: typeof d.phone === 'string' ? d.phone : '' })),
    ...swit.map((d) => ({ id: d.id, kind: 'withdrawal', label: `Retrait International ${opName(d)}`.trim(), amount: intOr(d.amount, 0), status: st(d), at: at(d), other: typeof d.phone === 'string' ? d.phone : '' })),
    ...tout.map((d) => ({ id: d.id, kind: 'transfer_out', label: 'Transfert envoyé', amount: intOr(d.amount, 0), status: 'done', at: at(d), other: String(d.toName || '') })),
    ...tin.map((d) => ({ id: d.id, kind: 'transfer_in', label: 'Transfert reçu', amount: intOr(d.amount, 0), status: 'done', at: at(d), other: String(d.fromName || '') })),
  ]
    .sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')))
    .slice(0, 150);
  return { items };
}

// ----------------------------------------------------------------------
// Anti-triche : une partie à mise qui se termine de façon invraisemblable
// (trop courte, trop peu de coups) n'est PAS payée tout de suite : elle passe
// « à vérifier » et l'administrateur décide (payer le gagnant ou rembourser).
// ----------------------------------------------------------------------
const LUDO_MIN_REV = 40; // un camp ne peut pas rentrer ses 4 pions en moins de ~38 lancers
const MIN_PLAY_MS = { games: 60000, deuxdes: 5000, songo: 30000, damier: 30000 };

function suspicion(col, d) {
  if (!(col in MIN_PLAY_MS)) return [];
  const reasons = [];
  const forfeited = Array.isArray(d.forfeited) ? d.forfeited : [];
  const players = playersOf(d).length;
  const byForfeit = col === 'games' && (intOr(d.winner, -1) >= 0 || (players > 1 && forfeited.length >= players - 1));
  const started = typeof d.startedAt === 'string' ? Date.parse(d.startedAt) : 0;
  if (!byForfeit && started > 0 && Date.now() - started < MIN_PLAY_MS[col]) {
    reasons.push(`durée ${Math.round((Date.now() - started) / 1000)} s`);
  }
  if (col === 'games' && !byForfeit && intOr(d.rev, 0) < LUDO_MIN_REV) {
    reasons.push(`seulement ${intOr(d.rev, 0)} coups`);
  }
  return reasons;
}

async function settleGame(args) {
  const { data, env } = args;
  const gameId = idOf(data);
  if (gameId) {
    for (const col of ['games', 'deuxdes', 'songo', 'damier']) {
      const d = await readDoc(env, `${col}/${gameId}`);
      if (!d) continue;
      if (d.settled === true || d.over !== true || !(intOr(d.stake, 0) > 0)) break;
      if (d.review === true) return { review: true, jackpot: 0 };
      if (d.reviewApproved === true) break;
      const reasons = suspicion(col, d);
      if (!reasons.length) break;
      await runTx(env, async (tx) => {
        tx.write(`${col}/${gameId}`, { set: { review: true, reviewReason: reasons.join(', ') } });
      });
      await notifyAdmin(env, `🕵️ Partie à vérifier (${col}) : ${reasons.join(', ')}.\nOuvre Katika > Admin > Parties à vérifier.`).catch(() => {});
      return { review: true, jackpot: 0 };
    }
  }
  const result = await settleGameCore(args);
  if (gameId) await recordTiming(env, gameId).catch(() => {});
  return result;
}

/** Le joueur vient d'inviter un binôme : notification push à l'invité (une seule par invitation). */
async function notifyInvite({ uid, data, env }) {
  const gameId = idOf(data);
  if (!gameId) throw new HttpError('invalid-argument', 'Partie invalide.');
  const g = await readDoc(env, `games/${gameId}`);
  if (!g) throw new HttpError('not-found', 'Partie introuvable.');
  const players = playersOf(g);
  const me = players.findIndex((p) => p && p.uid === uid);
  if (me < 0) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
  const invites = Array.isArray(g.invites) ? g.invites : [];
  const inv = invites.find((i) => i && intOr(i.from, -1) === me);
  if (!inv) return { sent: false };
  const to = players[intOr(inv.to, -1)];
  if (!to || !to.uid || to.uid === uid) return { sent: false };
  const key = `${me}>${intOr(inv.to, -1)}`;
  if (g.inviteNotified === key) return { sent: false }; // déjà prévenu
  await runTx(env, async (tx) => {
    tx.write(`games/${gameId}`, { set: { inviteNotified: key } });
  });
  later(env, pushToUser(env, to.uid, '🤝 Invitation de binôme', `${String(players[me].name || 'Un joueur')} t'invite à jouer en équipe au Ludo.`));
  return { sent: true };
}

/** Administrateur : tranche une partie « à vérifier » : payer le gagnant ou rembourser tout le monde. */
async function adminResolveGame({ uid, data, env }) {
  requireAdmin(uid, env);
  const gameId = idOf(data);
  if (!gameId) throw new HttpError('invalid-argument', 'Partie invalide.');
  const action = data.action === 'refund' ? 'refund' : data.action === 'approve' ? 'approve' : '';
  if (!action) throw new HttpError('invalid-argument', 'Action invalide.');
  const info = await runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const d = g.data;
    if (d.settled === true) throw new HttpError('failed-precondition', 'Cette partie est déjà réglée.');
    if (action === 'approve') {
      tx.write(g.path, { set: { review: false, reviewApproved: true } });
      return { first: String((playersOf(d)[0] || {}).uid || '') };
    }
    const stake = Math.max(0, intOr(d.stake, 0));
    refund(tx, chargedPaid(d), stake, d);
    tx.write(g.path, {
      set: { review: false, settled: true, refunded: true, over: true, status: 'finished', commission: 0, referralPaid: 0, partnerPaid: 0, jackpot: 0 },
    });
    return { first: '' };
  });
  if (action === 'approve') {
    await settleGameCore({ uid: info.first, data: { gameId }, env });
  }
  return { ok: true, action };
}

/** Administrateur : annule une partie en ligne (ouverte OU en cours) et rembourse toutes les mises. */
async function adminCancelGame({ uid, data, env }) {
  requireAdmin(uid, env);
  const gameId = idOf(data);
  if (!gameId) throw new HttpError('invalid-argument', 'Partie invalide.');
  const out = await runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
    if (!g) throw new HttpError('not-found', "Cette partie n'existe plus.");
    const d = g.data;
    if (d.settled === true || d.over === true) {
      throw new HttpError('failed-precondition', 'Cette partie est déjà terminée.');
    }
    const stake = Math.max(0, intOr(d.stake, 0));
    const paid = chargedPaid(d);
    refund(tx, paid, stake, d);
    tx.write(g.path, {
      set: {
        settled: true,
        refunded: true,
        over: true,
        status: g.col === 'cards' || g.col === 'pileface' ? 'cancelled' : 'finished',
        cancelledByAdmin: true,
        commission: 0,
        referralPaid: 0,
        partnerPaid: 0,
        jackpot: 0,
      },
    });
    return { refunded: stake > 0 ? paid.length : 0, stake };
  });
  return { ok: true, ...out };
}

async function sweepWaiting({ env }) {
  return { cancelled: await maybeSweep(env), afterMinutes: WAITING_CANCEL_MIN };
}


// ======================================================================
// Notifications ntfy de TOUTES les transactions d'argent (variable NTFY_TOPIC)
// recharges, retraits, transferts, retraits de gains et de commissions.
// ======================================================================
function fcfaText(n) {
  const s = String(Math.max(0, Math.floor(Number(n) || 0)));
  return s.replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' FCFA';
}

async function ntfyTx(env, uid, tag, line) {
  try {
    if (!env.NTFY_TOPIC) return;
    let who = '';
    if (uid) {
      const u = await readDoc(env, `users/${uid}`);
      who = u ? String(u.pseudo || u.promoCode || '') : '';
    }
    await ntfyPost(env, { Title: 'Katika - transaction', Priority: 'default', Tags: tag }, `${line}${who ? ` · ${who}` : ''}`);
  } catch (_) {
    /* sans effet */
  }
}

async function settleDeposit(env, id) {
  const before = await readDoc(env, `deposits/${id}`);
  const r = await settleDepositCore(env, id);
  if (before && before.status === 'pending' && r.status === 'credited') {
    await ntfyTx(env, before.uid, 'moneybag', `💰 Recharge Campay : +${fcfaText(before.amount)}`);
    await pushToUser(env, before.uid, '💰 Recharge reçue', `+${fcfaText(before.amount)} ajoutés à ton solde.`);
  }
  return r;
}

async function settleSebpayDeposit(env, id) {
  const before = await readDoc(env, `sebpayDeposits/${id}`);
  const r = await settleSebpayDepositCore(env, id);
  if (before && before.status === 'pending' && r.status === 'credited') {
    await ntfyTx(env, before.uid, 'moneybag', `💰 Recharge International (${before.operator === 'mtn' ? 'MTN MoMo' : 'Orange Money'}) : +${fcfaText(before.amount)}`);
    await pushToUser(env, before.uid, '💰 Recharge reçue', `+${fcfaText(before.amount)} ajoutés à ton solde.`);
  }
  return r;
}

async function settleSebpayPayout(env, id) {
  const before = await readDoc(env, `sebpayPayouts/${id}`);
  const r = await settleSebpayPayoutCore(env, id);
  if (before && before.status === 'pending' && (r.status === 'paid' || r.status === 'failed')) {
    const op = before.operator === 'mtn' ? 'MTN MoMo' : 'Orange Money';
    await ntfyTx(
      env,
      before.uid,
      r.status === 'paid' ? 'outbox_tray' : 'warning',
      r.status === 'paid'
        ? `💸 Retrait International envoyé (${op}) : ${fcfaText(before.amount)}`
        : `⚠️ Retrait International échoué, jetons remboursés (${op}) : ${fcfaText(before.amount)}`,
    );
  }
  return r;
}

async function adminManualDecide(args) {
  const { data, env } = args;
  const kind = data.kind === 'withdrawal' ? 'withdrawal' : 'deposit';
  const before = await readDoc(env, `${kind === 'deposit' ? 'manualDeposits' : 'manualWithdrawals'}/${idStr(data.id)}`);
  const r = await adminManualDecideCore(args);
  if (before) {
    const approve = data.action === 'approve';
    const amt = kind === 'deposit' ? intOr(before.amount, 0) : intOr(before.tokens, intOr(before.amount, 0));
    await ntfyTx(
      env,
      before.uid,
      approve ? 'white_check_mark' : 'x',
      kind === 'deposit'
        ? approve
          ? `💰 Recharge Local Cameroun validée : +${fcfaText(amt)}`
          : `❌ Recharge Local Cameroun refusée : ${fcfaText(amt)}`
        : approve
          ? `💸 Retrait Local Cameroun payé : ${fcfaText(amt)}`
          : `❌ Retrait Local Cameroun refusé (remboursé) : ${fcfaText(amt)}`,
    );
    await pushToUser(
      env,
      before.uid,
      kind === 'deposit' ? (approve ? '💰 Recharge validée' : '❌ Recharge refusée') : approve ? '💸 Retrait payé' : '❌ Retrait refusé',
      kind === 'deposit'
        ? approve
          ? `+${fcfaText(amt)} ont été ajoutés à ton solde.`
          : `Ta recharge de ${fcfaText(amt)} a été refusée.`
        : approve
          ? `${fcfaText(amt)} ont été envoyés sur ton Mobile Money.`
          : `Ton retrait de ${fcfaText(amt)} a été refusé, ton solde est remboursé.`,
    );
  }
  return r;
}

/** Transactions notifiées après un appel réussi (les demandes manuelles passent déjà par notifyAdmin). */
async function ntfyAfterHandler(env, name, uid, data, result) {
  const amount = result && typeof result.amount === 'number' ? result.amount : intOr(data && data.amount, 0);
  switch (name) {
    case 'transfer':
      return ntfyTx(env, uid, 'repeat', `🔁 Transfert : ${fcfaText(amount)} vers ${result && result.toName ? result.toName : '?'}`);
    case 'referralWithdraw':
      return ntfyTx(env, uid, 'handshake', `🤝 Retrait des gains de parrainage : ${fcfaText(amount)}`);
    case 'partnerWithdraw':
      return ntfyTx(env, uid, 'handshake', `🤝 Retrait des gains partenaire : ${fcfaText(amount)}`);
    case 'adminHouseWithdraw':
      return ntfyTx(env, uid, 'bank', `🏦 Retrait des commissions Katika : ${fcfaText(amount)}`);
    case 'sebpayWithdrawRequest':
      return ntfyTx(env, uid, 'hourglass', `⏳ Demande de retrait International : ${fcfaText(intOr(data && data.amount, 0))}`);
    default:
      return undefined;
  }
}
const NTFY_HANDLERS = new Set(['transfer', 'referralWithdraw', 'partnerWithdraw', 'adminHouseWithdraw', 'sebpayWithdrawRequest']);

// ======================================================================
// Ludo serveur : règles du jeu (copie fidèle des règles de l'appli) et
// action unique `ludoAct` (roll / move / pass / forfeit).
// ======================================================================
const LUDO_START = [0, 13, 26, 39];
const LUDO_STARS = [8, 21, 34, 47];
const LUDO_DOORS = [0, 13, 26, 39];
const LUDO_MAX_FINISH_THROWS = 5;
const LUDO_STALE_MS = 20000;

function ludoColors(d) {
  return colorsFor(intOr(d.maxPlayers, 4));
}
function ludoPawns(d, c) {
  const p = d['p' + c];
  return Array.isArray(p) ? p : [];
}
function ludoSafeCells(d) {
  const s = new Set();
  if (d.doorSafe !== false) LUDO_DOORS.forEach((x) => s.add(x));
  if (d.starSafe !== false) LUDO_STARS.forEach((x) => s.add(x));
  return s;
}
function ludoIsMate(d, a, b) {
  return d.teamMode === true && Array.isArray(d.partners) && d.partners[a] === b;
}
function ludoMateOf(d, c) {
  return d.teamMode === true && Array.isArray(d.partners) ? intOr(d.partners[c], -1) : -1;
}
/** Deux pions (ou plus) de la même équipe sur la même case : protégés de la capture
 *  (même joueur, ou binôme en 2 contre 2), que la case soit étoilée ou non. */
function ludoIsBlock(d, c, pos) {
  if (pos < 0 || pos >= 51) return ludoPawns(d, c).filter((x) => x === pos).length >= 2;
  const abs = (LUDO_START[c] + pos) % 52;
  let n = 0;
  for (const q of ludoColors(d)) {
    if (q !== c && !ludoIsMate(d, c, q)) continue;
    for (const x of ludoPawns(d, q)) {
      if (x >= 0 && x < 51 && (LUDO_START[q] + x) % 52 === abs) n++;
    }
  }
  return n >= 2;
}
function ludoFinishTarget(d) {
  return Math.max(1, intOr(d.finishTarget, 1));
}
function ludoFinishedAll(d, c) {
  return (d.teamMode === true || ludoFinishTarget(d) > 1) && ludoPawns(d, c).every((x) => x === 56);
}
function ludoActive(d) {
  const f = Array.isArray(d.forfeited) ? d.forfeited : [];
  return ludoColors(d).filter((c) => !f.includes(c));
}
function ludoCanMoveWith(pos, dv) {
  if (pos === -1) return dv === 6;
  return pos + dv <= 56;
}
function ludoProgress(d, c) {
  const p = ludoPawns(d, c);
  let t = 0;
  for (const x of p) if (x > 0) t += x;
  return p.length ? t / (p.length * 56) : 0;
}

/** Le pion i du joueur c capturerait-il avec la face dv ? */
function ludoCaptureWith(d, c, i, dv) {
  const from = ludoPawns(d, c)[i];
  if (!ludoCanMoveWith(from, dv)) return false;
  const target = from === -1 ? 0 : from + dv;
  if (target >= 51) return false;
  const abs = (LUDO_START[c] + target) % 52;
  if (ludoSafeCells(d).has(abs)) return false;
  for (const p of ludoColors(d)) {
    if (p === c || ludoIsMate(d, p, c)) continue;
    for (const pos of ludoPawns(d, p)) {
      if (pos >= 0 && pos < 51 && (LUDO_START[p] + pos) % 52 === abs && !ludoIsBlock(d, p, pos)) {
        return true;
      }
    }
  }
  return false;
}

/** Coups autorisés (la capture est obligatoire quand elle existe). */
function ludoLegal(d, c, dv) {
  const pawns = ludoPawns(d, c);
  const all = [];
  for (let i = 0; i < pawns.length; i++) if (ludoCanMoveWith(pawns[i], dv)) all.push(i);
  const caps = all.filter((i) => ludoCaptureWith(d, c, i, dv));
  return caps.length > 0 ? caps : all;
}

function ludoFaceCaptures(d, c, f) {
  const n = ludoPawns(d, c).length;
  for (let i = 0; i < n; i++) if (ludoCaptureWith(d, c, i, f)) return true;
  return false;
}

function ludoBalancedFace(d, c, rnd) {
  const r6 = () => Math.floor(rnd() * 6) + 1;
  const mine = ludoProgress(d, c);
  let best = 0;
  let any = false;
  for (const p of ludoColors(d)) {
    if (p === c) continue;
    if (ludoPawns(d, p).every((x) => x === 56)) continue;
    any = true;
    best = Math.max(best, ludoProgress(d, p));
  }
  let face = r6();
  if (!any) return face;
  const ahead = mine - best;
  const behind = best - mine;
  if (ahead > 0.2) {
    const tries = ahead > 0.3 ? 3 : ahead > 0.25 ? 2 : 1;
    for (let k = 0; k < tries; k++) face = Math.min(face, r6());
    if (ahead > 0.3 && face > 3) face = 1 + Math.floor(rnd() * 3);
  } else if (behind > 0.2) {
    const tries = behind > 0.3 ? 3 : behind > 0.25 ? 2 : 1;
    for (let k = 0; k < tries; k++) face = Math.max(face, r6());
  }
  return face;
}

/** Chance (sur 1000) qu'un lancer force une face qui capture quand une capture est possible. */
const LUDO_CAPTURE_BOOST = 70; // était 100 (10 %) : captures un peu moins fréquentes

function ludoRandomFace(d, c, rnd) {
  const capFaces = [];
  for (let f = 1; f <= 6; f++) if (ludoFaceCaptures(d, c, f)) capFaces.push(f);
  if (capFaces.length > 0 && Math.floor(rnd() * 1000) < LUDO_CAPTURE_BOOST) {
    return capFaces[Math.floor(rnd() * capFaces.length)];
  }
  return ludoBalancedFace(d, c, rnd);
}

/** Valeur du prochain lancer ; `ft` = compteur de lancers de finition. */
function ludoRollValue(d, c, ft, rnd) {
  const left = ludoPawns(d, c).filter((x) => x !== 56);
  if (left.length === 1 && left[0] >= 0) {
    const remaining = 56 - left[0];
    if (remaining >= 1 && remaining <= 6) {
      if (ft[c] >= LUDO_MAX_FINISH_THROWS - 1) {
        ft[c] = 0;
        return remaining;
      }
      ft[c] += 1;
      return ludoRandomFace(d, c, rnd);
    }
  }
  ft[c] = 0;
  return ludoRandomFace(d, c, rnd);
}

/** Joueur suivant (saute ceux qui ont déjà fini en équipe / tournoi). */
function ludoAdvance(d) {
  const act = ludoActive(d);
  if (act.length === 0) return;
  let next = intOr(d.cur, 0);
  for (let k = 0; k < act.length; k++) {
    const idx = act.indexOf(next);
    next = act[(idx < 0 ? 0 : idx + 1) % act.length];
    if (!ludoFinishedAll(d, next)) break;
  }
  d.cur = next;
  d.hasRolled = false;
}

/** Applique un déplacement (le coup a déjà été reconnu légal). */
function ludoApplyMove(d, i) {
  const c = intOr(d.cur, 0);
  const dv = intOr(d.dice, 1);
  const pawns = ludoPawns(d, c).slice();
  const old = pawns[i];
  const pos = old === -1 ? 0 : old + dv;
  pawns[i] = pos;
  d['p' + c] = pawns;
  const victims = [];
  if (pos < 51) {
    const abs = (LUDO_START[c] + pos) % 52;
    if (!ludoSafeCells(d).has(abs)) {
      for (const p of ludoColors(d)) {
        if (p === c || ludoIsMate(d, p, c)) continue;
        const op = ludoPawns(d, p).slice();
        let hit = false;
        for (let k = 0; k < op.length; k++) {
          if (op[k] >= 0 && op[k] < 51 && (LUDO_START[p] + op[k]) % 52 === abs && !ludoIsBlock(d, p, op[k])) {
            op[k] = -1;
            victims.push(p);
            hit = true;
          }
        }
        if (hit) d['p' + p] = op;
      }
    }
  }
  const fo = Array.isArray(d.finishOrder) ? d.finishOrder.slice() : [];
  const selfDone = pawns.every((x) => x === 56);
  if (selfDone && !fo.includes(c)) fo.push(c);
  d.finishOrder = fo;
  const won = selfDone && (ludoFinishTarget(d) <= 1 || fo.length >= ludoFinishTarget(d));
  if (won) {
    d.over = true;
    d.hasRolled = true;
  } else if (selfDone) {
    ludoAdvance(d);
  } else if (dv === 6 || victims.length > 0 || pos === 56) {
    d.hasRolled = false;
  } else {
    ludoAdvance(d);
  }
  return { victims, pos, won };
}

/** Abandon de la couleur `who` (et de son binôme). */
function ludoApplyForfeit(d, who) {
  const f = Array.isArray(d.forfeited) ? d.forfeited.slice() : [];
  if (f.includes(who)) return false;
  const mate = ludoMateOf(d, who);
  const order = ludoColors(d);
  f.push(who);
  if (mate >= 0 && !f.includes(mate)) f.push(mate);
  d.forfeited = f;
  for (const c of [who, mate]) {
    if (c >= 0) d['p' + c] = ludoPawns(d, c).map(() => -1);
  }
  let next = who;
  for (let k = 1; k <= order.length; k++) {
    const c = order[(order.indexOf(who) + k) % order.length];
    if (!f.includes(c)) {
      next = c;
      break;
    }
  }
  const act = ludoActive(d);
  const oneSide = act.length <= 1 || (d.teamMode === true && act.length === 2 && ludoMateOf(d, act[0]) === act[1]);
  if (oneSide) {
    d.winner = act.length ? act[0] : -1;
    d.over = true;
  } else if (f.includes(intOr(d.cur, 0))) {
    d.cur = next;
    d.hasRolled = false;
  } else if (d.hasRolled === true && ludoLegal(d, intOr(d.cur, 0), intOr(d.dice, 1)).length === 0) {
    ludoAdvance(d);
  }
  return true;
}

/** Action d'un joueur sur une partie Ludo « serveur » (srv === true). */
/** Entrer dans un Ludo déjà lancé à moins de joueurs que de places, tant que
 *  personne n'a joué de 6 (aucun pion n'a bougé). Le joueur paie sa mise tout
 *  de suite ; les couleurs sont redistribuées selon le nouvel effectif. */
async function ludoJoinRunning({ uid, data, env }) {
  const gameId = idOf(data);
  return runTx(env, async (tx) => {
    const path = `games/${gameId}`;
    const [d, me] = await Promise.all([tx.get(path), tx.get(`users/${uid}`)]);
    if (!d) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (d.status !== 'playing' || d.over === true || d.srv !== true || d.lateOpen !== true) {
      throw new HttpError('failed-precondition', 'Cette partie ne peut plus être rejointe.');
    }
    const players = playersOf(d);
    if (players.some((p) => p.uid === uid)) return { ok: true, already: true };
    const cap = intOr(d.lateCap, 0);
    const n = players.length;
    if (n < 2 || n >= cap || n >= 4) throw new HttpError('failed-precondition', 'La partie est complète.');
    const oldColors = colorsFor(n);
    const newColors = colorsFor(n + 1);
    // Personne n'a bougé un pion.
    const pc = Math.max(1, intOr(d.pawnCount, 4));
    const initial = (i) => (d.startOut === true ? 43 + (i % 2) : d.startDoor === true ? 0 : -1);
    for (const c of oldColors) {
      const p = ludoPawns(d, c);
      for (let i = 0; i < pc; i++) {
        if (intOr(p[i], -9) !== initial(i)) throw new HttpError('failed-precondition', 'Un pion a déjà bougé : trop tard.');
      }
    }
    const perSeat = Math.max(0, intOr(d.stake, 0));
    const capNeed = capFeeOf(d);
    if ((perSeat > 0 || capNeed > 0) && balanceOf(me) < perSeat + capNeed) {
      throw new HttpError('failed-precondition', 'Solde insuffisant.');
    }
    if (perSeat > 0) tx.write(`users/${uid}`, { incr: { balance: -perSeat } });
    const name = (typeof data.name === 'string' && data.name.trim() ? data.name.trim().slice(0, 24) : '') || (me && (me.pseudo || me.name)) || 'Joueur';
    // Tour et mémoires de dés : on garde le même joueur, sa couleur change.
    const oldCur = intOr(d.cur, 0);
    const ti = Math.max(0, oldColors.indexOf(oldCur));
    const lr = [1, 1, 1, 1];
    const ft = [0, 0, 0, 0];
    const oldLr = Array.isArray(d.lastRoll) ? d.lastRoll : [];
    const oldFt = Array.isArray(d.ft) ? d.ft : [];
    oldColors.forEach((c, i) => {
      lr[newColors[i]] = intOr(oldLr[c], 1);
      ft[newColors[i]] = intOr(oldFt[c], 0);
    });
    const set = {
      players: [...players, { uid, name }],
      maxPlayers: n + 1,
      cur: newColors[ti],
      lastRoll: lr,
      ft,
      msg: `${name} a rejoint la partie.`,
    };
    if (n + 1 >= cap) set.lateOpen = false;
    tx.write(path, {
      set,
      union: { uids: [uid], paid: [uid] },
      incr: { pot: perSeat, rev: 1 },
    });
    return { ok: true, players: n + 1 };
  });
}

async function ludoAct({ uid, data, env }) {
  const gameId = idOf(data);
  const act = String(data.act || '');
  if (!gameId || !['roll', 'move', 'pass', 'forfeit'].includes(act)) {
    throw new HttpError('invalid-argument', 'Action invalide.');
  }
  const out = await runTx(env, async (tx) => {
    const path = `games/${gameId}`;
    const d = await tx.get(path);
    if (!d) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (d.srv !== true) throw new HttpError('failed-precondition', 'Partie non gérée par le serveur.');
    const uids = Array.isArray(d.uids) ? d.uids : [];
    if (!uids.includes(uid)) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    if (d.status !== 'playing' || d.over === true) {
      throw new HttpError('failed-precondition', "La partie n'est pas en cours.");
    }
    const colors = ludoColors(d);
    const cur = intOr(d.cur, 0);
    const seatUid = (c) => uids[colors.indexOf(c)];

    // Qui agit ? Le propriétaire du siège, ou (proxy) un joueur quand le
    // propriétaire est absent depuis plus de 20 s.
    const target = act === 'forfeit' ? intOr(data.seat, -1) : cur;
    if (!colors.includes(target)) throw new HttpError('invalid-argument', 'Siège invalide.');
    const owner = seatUid(target);
    if (owner !== uid) {
      if (data.proxy !== true) throw new HttpError('permission-denied', "Ce n'est pas ton tour.");
      const pres = await tx.get(`${path}/presence/${owner}`);
      const t = pres ? intOr(pres.t, 0) : 0;
      if (Date.now() - t < LUDO_STALE_MS) {
        throw new HttpError('permission-denied', 'Ce joueur est toujours connecté.');
      }
    }

    const set = {};
    const info = {};
    if (act === 'forfeit') {
      if (!ludoApplyForfeit(d, target)) return { ok: true, noop: true };
      info.forfeit = target;
    } else {
      if (ludoActive(d).indexOf(cur) < 0) throw new HttpError('failed-precondition', 'Joueur éliminé.');
      if (act === 'roll') {
        if (d.hasRolled === true) throw new HttpError('failed-precondition', 'Le dé est déjà lancé.');
        const ft = Array.isArray(d.ft) && d.ft.length === 4 ? d.ft.map((x) => intOr(x, 0)) : [0, 0, 0, 0];
        const dv = ludoRollValue(d, cur, ft, Math.random);
        const lr = Array.isArray(d.lastRoll) && d.lastRoll.length === 4 ? d.lastRoll.slice() : [1, 1, 1, 1];
        lr[cur] = dv;
        d.dice = dv;
        d.hasRolled = true;
        d.lastRoll = lr;
        d.ft = ft;
        if (dv === 6 && d.lateOpen === true) set.lateOpen = false;
        set.roll = { by: uid, n: Date.now() };
        info.dice = dv;
      } else if (act === 'pass') {
        if (d.hasRolled !== true) throw new HttpError('failed-precondition', "Lance d'abord le dé.");
        const dv = intOr(d.dice, 1);
        if (ludoLegal(d, cur, dv).length > 0) throw new HttpError('failed-precondition', 'Un coup est possible.');
        if (dv === 6) d.hasRolled = false;
        else ludoAdvance(d);
      } else {
        if (d.hasRolled !== true) throw new HttpError('failed-precondition', "Lance d'abord le dé.");
        const i = intOr(data.pawn, -1);
        const legal = ludoLegal(d, cur, intOr(d.dice, 1));
        if (!legal.includes(i)) throw new HttpError('failed-precondition', 'Coup interdit.');
        const r = ludoApplyMove(d, i);
        info.victims = r.victims;
        info.pos = r.pos;
        info.won = r.won;
      }
    }

    for (const k of ['p0', 'p1', 'p2', 'p3', 'cur', 'hasRolled', 'dice', 'lastRoll', 'over',
      'forfeited', 'finishOrder', 'winner', 'ft']) {
      if (d[k] !== undefined) set[k] = d[k];
    }
    set.writer = uid;
    if (d.over === true) set.status = 'finished';
    if (act !== 'roll') set.roll = null;
    // Enregistrement de la partie (pour la revoir du début à la fin).
    const rp = (Array.isArray(d.rp) ? d.rp : []).slice(-1500);
    rp.push(
      JSON.stringify([
        Date.now(), intOr(d.cur, 0), intOr(d.dice, 1), d.hasRolled ? 1 : 0, intOr(d.winner, -1),
        d.finishOrder || [], d.forfeited || [], d.p0 || [], d.p1 || [], d.p2 || [], d.p3 || [],
        d.over ? 1 : 0, act === 'roll' ? 1 : 0,
      ]),
    );
    tx.write(path, { set: { ...set, rp }, incr: { rev: 1 } });
    return { ok: true, ...info, state: set };
  });
  return out;
}


// ----------------------------------------------------------------------
// Deux dés « serveur » : le serveur tire les dés et additionne les scores.
// ----------------------------------------------------------------------
const DD_IDLE_MS = 25000;

async function deuxDesAct({ uid, data, env }) {
  const gameId = idOf(data);
  const act = String(data.act || '');
  const seat = intOr(data.seat, -1);
  if (!gameId || !['roll', 'next'].includes(act)) throw new HttpError('invalid-argument', 'Action invalide.');
  return runTx(env, async (tx) => {
    const path = `deuxdes/${gameId}`;
    const d = await tx.get(path);
    if (!d) throw new HttpError('not-found', "Cette partie n'existe plus.");
    if (d.srv !== true) throw new HttpError('failed-precondition', 'Partie non gérée par le serveur.');
    const uids = Array.isArray(d.uids) ? d.uids : [];
    if (!uids.includes(uid)) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
    if (d.status !== 'playing' || d.over === true) throw new HttpError('failed-precondition', "La partie n'est pas en cours.");
    const cur = intOr(d.cur, 0);
    if (seat !== cur) throw new HttpError('failed-precondition', "Ce n'est pas ce tour.");
    const scores = Array.isArray(d.scores) ? d.scores.map((x) => intOr(x, 0)) : [];
    if (cur < 0 || cur >= scores.length || cur >= uids.length) throw new HttpError('invalid-argument', 'Siège invalide.');
    const last = intOr(d.turnAt, 0) || (typeof d.startedAt === 'string' ? Date.parse(d.startedAt) : 0) || 0;
    if (uids[cur] !== uid && Date.now() - last < DD_IDLE_MS) {
      throw new HttpError('permission-denied', "Ce n'est pas ton tour.");
    }
    const spin = () => [
      (Math.random() < 0.5 ? 1 : -1) * (1 + Math.floor(Math.random() * 2)),
      (Math.random() < 0.5 ? 1 : -1) * (2 + Math.floor(Math.random() * 2)),
      (Math.random() < 0.5 ? 1 : -1) * (1 + Math.floor(Math.random() * 2)),
    ];
    if (act === 'roll') {
      if (d.rolled === true) throw new HttpError('failed-precondition', 'Déjà lancé.');
      const a = 1 + Math.floor(Math.random() * 6);
      const b = 1 + Math.floor(Math.random() * 6);
      scores[cur] += a + b;
      const isLast = cur === uids.length - 1;
      const set = { d1: a, d2: b, spin1: spin(), spin2: spin(), scores, rolled: true, turnAt: Date.now() };
      set.mv = [...(Array.isArray(d.mv) ? d.mv : []).slice(-60), `${a},${b}`];
      if (isLast) {
        const best = Math.max(...scores);
        set.over = true;
        set.status = 'finished';
        set.winners = scores.map((s, i) => (s === best ? i : -1)).filter((i) => i >= 0);
      }
      tx.write(path, { set, incr: { rollN: 1 } });
      return { ok: true, d1: a, d2: b };
    }
    if (d.rolled !== true) throw new HttpError('failed-precondition', "Lance d'abord les dés.");
    tx.write(path, { set: { cur: cur + 1, rolled: false, turnAt: Date.now() } });
    return { ok: true };
  });
}


// ======================================================================
// Revoir les parties : liste des parties en ligne d'un joueur + cartes
// ======================================================================

const REPLAY_COLS = [
  ['games', 'ludo'],
  ['deuxdes', 'deuxdes'],
  ['songo', 'songo'],
  ['damier', 'damier'],
  ['cards', 'cards'],
];

function docTimeMs(d) {
  for (const k of ['startedAt', 'createdAt']) {
    if (typeof d[k] === 'string') {
      const t = Date.parse(d[k]);
      if (t > 0) return t;
    }
  }
  return intOr(d.createdAtMs, 0);
}

/** Les parties en ligne (terminées ou en cours) d'un joueur : le sien, ou
 *  n'importe lequel pour un administrateur. data : { uid?, limit? } */
async function playerGames({ uid, data, env }) {
  let target = uid;
  if (typeof data.uid === 'string' && data.uid && data.uid !== uid) {
    requireAdmin(uid, env);
    target = data.uid;
  }
  const lim = Math.min(60, Math.max(5, intOr(data.limit, 40)));
  const rows = [];
  await Promise.all(
    REPLAY_COLS.map(async ([col, kind]) => {
      let docs = [];
      try {
        docs = await queryDocs(env, col, arrayContainsFilter('uids', target), lim);
      } catch (_) {
        return;
      }
      for (const d of docs) {
        if (d.status === 'waiting') continue;
        const players = playersOf(d);
        const uidsL = players.map((p) => p.uid);
        let winners = [];
        try {
          winners = col === 'cards' ? (Array.isArray(d.winnerUids) ? d.winnerUids : []) : winnersFor(col, d, uidsL);
        } catch (_) {}
        const over = d.over === true || d.status === 'finished';
        const stakeN = col === 'damier' ? stakeFor(d, target) : Math.max(0, intOr(d.stake, 0));
        rows.push({
          id: d.id,
          kind: col === 'cards' ? (d.game === 'boubayah' ? 'boubayah' : d.game === 'fapfap' ? 'fapfap' : d.game === 'anticote' ? 'anticote' : d.game === 'tchek' ? 'tchek' : 'tiah') : kind,
          t: docTimeMs(d),
          names: [...new Set(players.map((p) => p.name || 'Joueur'))],
          stake: stakeN,
          over,
          cancelled: d.refunded === true && !(d.winners && d.winners.length) && !winners.length,
          result: !over ? 'live' : d.refunded === true ? 'refunded' : winners.includes(target) ? 'won' : winners.length ? 'lost' : 'draw',
          replay: col === 'cards' ? over && !isFl(d.game) : Array.isArray(d.rp) ? d.rp.length > 0 : Array.isArray(d.mv) ? d.mv.length > 0 : false,
        });
      }
    }),
  );
  rows.sort((a, b) => b.t - a.t);
  return { rows: rows.slice(0, lim * 2) };
}

/** Tiah / Boubayah : tout le déroulé d'une manche terminée (cartes de chacun,
 *  ordre d'ouverture, gagnants). Réservé aux joueurs de la manche et aux admins. */
async function cardsReplay({ uid, data, env }) {
  const gid = idOf(data);
  const g = gid ? await readDoc(env, `cards/${gid}`) : null;
  if (!g) throw new HttpError('not-found', 'Partie introuvable.');
  const uidsL = Array.isArray(g.uids) ? g.uids : [];
  let isAdmin = false;
  try {
    requireAdmin(uid, env);
    isAdmin = true;
  } catch (_) {}
  if (!isAdmin && !uidsL.includes(uid)) throw new HttpError('permission-denied', 'Tu ne fais pas partie de cette partie.');
  if (g.over !== true) throw new HttpError('failed-precondition', 'La manche n\'est pas terminée.');
  const players = playersOf(g).map((p) => {
    const row = { uid: p.uid, name: p.name || 'Joueur' };
    if (g.game === 'tiah') {
      const hand = (g.hands && g.hands[p.uid]) || [];
      row.cards = hand;
      row.total = cardsTotal(hand);
      row.toucx = cardsIsToucx(hand);
    } else {
      row.plain = (g.plain && g.plain[p.uid]) || [];
      row.bouba = (g.bouba && g.bouba[p.uid]) || [];
      row.total = cardsBoubaTotal(g, p.uid);
      row.fomekou = cardsIsFomekou(g, p.uid);
    }
    return row;
  });
  return {
    game: g.game,
    round: intOr(g.round, 1),
    stake: intOr(g.stake, 0),
    players,
    seq: Array.isArray(g.seq) ? g.seq : players.map((p) => p.uid),
    opened: Array.isArray(g.opened) ? g.opened : [],
    winnerUids: Array.isArray(g.winnerUids) ? g.winnerUids : [],
    dealerUid: g.dealerUid || g.hostUid || '',
    refunded: g.refunded === true,
  };
}


/** Administrateur : fiche complète d'un joueur : parrain, filleuls, gains de
 *  parrainage, statut partenaire / hôtesse, parties en cours. data : { uid } */
// ----------------------------------------------------------------------
// Administration des comptes : retirer de l'argent, supprimer un compte.
// Journal : admin_debits/{id} et account_deletions/{id}.
// ----------------------------------------------------------------------

/** L'administrateur retire un montant du solde d'un joueur (jamais en dessous de 0). */
async function adminDebitAccount({ uid, data, env }) {
  requireAdmin(uid, env);
  const target = typeof data.uid === 'string' ? data.uid : '';
  const amount = intOr(data.amount, 0);
  const reason = zoneClean(data.reason, 120);
  if (!target) throw new HttpError('invalid-argument', 'Joueur invalide.');
  if (amount < 1) throw new HttpError('invalid-argument', 'Indique un montant à retirer.');
  return runTx(env, async (tx) => {
    const u = await tx.get(`users/${target}`);
    if (!u) throw new HttpError('not-found', 'Joueur introuvable.');
    const before = balanceOf(u);
    if (amount > before) throw new HttpError('failed-precondition', `Solde insuffisant : ce joueur a ${before} FCFA.`);
    tx.write(`users/${target}`, { incr: { balance: -amount } });
    // L'argent retiré revient dans le compte joueur de l'administrateur.
    const toAdmin = target !== uid;
    if (toAdmin) tx.write(`users/${uid}`, { incr: { balance: amount } });
    tx.write(`admin_debits/${newId()}`, {
      create: true,
      set: { uid: target, pseudo: tournName(u), amount, before, after: before - amount, by: uid, reason, creditedToAdmin: toAdmin },
      serverTime: ['createdAt'],
    });
    return { ok: true, balance: before - amount };
  });
}

/** Supprime un compte joueur (fiche + connexion). Refuse : compte admin, soi-même, partie en cours, partenaire/hôtesse,
 *  ou solde positif sans confirmation explicite (force = true : le solde est perdu, noté dans le journal). */
async function adminDeleteAccount({ uid, data, env }) {
  requireAdmin(uid, env);
  const target = typeof data.uid === 'string' ? data.uid : '';
  if (!target) throw new HttpError('invalid-argument', 'Joueur invalide.');
  if (target === uid || adminIds(env).includes(target)) {
    throw new HttpError('failed-precondition', 'Impossible de supprimer un compte administrateur.');
  }
  const u0 = await readDoc(env, `users/${target}`);
  if (!u0) throw new HttpError('not-found', 'Joueur introuvable.');
  if (u0.partner === true || u0.zonePartner === true || u0.hostess === true || u0.cashier === true) {
    throw new HttpError('failed-precondition', "Ce compte est partenaire, hôtesse ou caissière : retire d'abord ce statut.");
  }
  if (balanceOf(u0) > 0 && data.force !== true) {
    throw new HttpError('failed-precondition', `Ce joueur a encore ${balanceOf(u0)} FCFA : retire d'abord son solde, ou confirme la suppression.`);
  }
  for (const [col] of REPLAY_COLS) {
    let docs = [];
    try {
      docs = await queryDocs(env, col, arrayContainsFilter('uids', target), 30);
    } catch (_) {
      continue;
    }
    if (docs.some((d) => d.over !== true && (d.status === 'playing' || d.status === 'waiting'))) {
      throw new HttpError('failed-precondition', 'Ce joueur est dans une partie en cours : attends la fin.');
    }
  }
  const tokens = await queryDocs(env, 'pushTokens', eqFilter('uid', target), 20);
  await runTx(env, async (tx) => {
    const u = await tx.get(`users/${target}`);
    if (!u) throw new HttpError('not-found', 'Joueur introuvable.');
    tx.write(`account_deletions/${newId()}`, {
      create: true,
      set: {
        uid: target, pseudo: tournName(u), promoCode: String(u.promoCode || ''), balance: balanceOf(u),
        wagered: intOr(u.wagered, 0), by: uid, forced: data.force === true,
      },
      serverTime: ['createdAt'],
    });
    if (typeof u.promoCode === 'string' && u.promoCode) tx.delete(`promoCodes/${u.promoCode}`);
    for (const t of tokens) tx.delete(`pushTokens/${t.id}`);
    tx.delete(`users/${target}`);
  });
  // Suppression de la connexion (sinon le joueur retrouverait un compte vide en se reconnectant).
  let authDeleted = false;
  try {
    const access = await accessToken(env, 'https://www.googleapis.com/auth/cloud-platform');
    const r = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${projectId(env)}/accounts:delete`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${access}` },
      body: JSON.stringify({ localId: target }),
    });
    authDeleted = r.ok;
    if (!r.ok) console.error('auth delete', r.status, await r.text());
  } catch (e) {
    console.error('auth delete', e);
  }
  return { ok: true, authDeleted };
}

/** Historique de connexion : à chaque ouverture de session (ensureWallet) on
 *  garde l'adresse IP, le pays/ville (Cloudflare) et l'appareil. Une même IP vue
 *  dans les 30 dernières minutes ne crée pas de nouvelle ligne (on rafraîchit
 *  l'heure). 60 entrées maximum par joueur. */
const LOGIN_KEEP = 60;
async function logLogin(env, uid, request) {
  const h = request.headers;
  const ip = (h.get('cf-connecting-ip') || (h.get('x-forwarded-for') || '').split(',')[0] || '').trim().slice(0, 64);
  if (!ip) return;
  const cf = request.cf || {};
  const now = Date.now();
  const entry = {
    t: now,
    ip,
    country: String(cf.country || '').slice(0, 8),
    city: String(cf.city || '').slice(0, 60),
    ua: String(h.get('user-agent') || '').slice(0, 160),
  };
  await runTx(env, async (tx) => {
    const cur = await tx.get(`loginLog/${uid}`);
    const list = Array.isArray(cur && cur.list) ? cur.list.slice() : [];
    const last = list[0];
    if (last && last.ip === ip && now - intOr(last.t, 0) < 30 * 60 * 1000) {
      list[0] = Object.assign({}, last, { t: now });
    } else {
      list.unshift(entry);
    }
    tx.write(`loginLog/${uid}`, { set: { list: list.slice(0, LOGIN_KEEP) } });
  });
}

async function adminPlayerInfo({ uid, data, env }) {
  requireAdmin(uid, env);
  const target = typeof data.uid === 'string' ? data.uid : '';
  if (!target) throw new HttpError('invalid-argument', 'Joueur invalide.');
  const u = await readDoc(env, `users/${target}`);
  if (!u) throw new HttpError('not-found', 'Joueur introuvable.');
  const nameOf = (x) => (x && typeof x.pseudo === 'string' && x.pseudo ? x.pseudo : '');

  let referrer = null;
  if (typeof u.referrerUid === 'string' && u.referrerUid) {
    const r = await readDoc(env, `users/${u.referrerUid}`);
    referrer = {
      uid: u.referrerUid,
      pseudo: nameOf(r),
      code: typeof u.referrerCode === 'string' ? u.referrerCode : '',
    };
  }

  const kids = await queryDocs(env, 'users', eqFilter('referrerUid', target), 300);
  const referrals = kids
    .map((k) => ({
      uid: k.id,
      pseudo: nameOf(k),
      createdAt: typeof k.createdAt === 'string' ? k.createdAt : null,
      played: intOr(k.statPlayed, 0),
      wagered: intOr(k.wagered, 0),
      balance: balanceOf(k),
    }))
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

  const live = [];
  await Promise.all(
    REPLAY_COLS.map(async ([col, kind]) => {
      let docs = [];
      try {
        docs = await queryDocs(env, col, arrayContainsFilter('uids', target), 30);
      } catch (_) {
        return;
      }
      for (const d of docs) {
        if (d.over === true || (d.status !== 'playing' && d.status !== 'waiting')) continue;
        live.push({
          id: d.id,
          kind: col === 'cards' ? (d.game === 'boubayah' ? 'boubayah' : d.game === 'fapfap' ? 'fapfap' : d.game === 'anticote' ? 'anticote' : d.game === 'tchek' ? 'tchek' : 'tiah') : kind,
          status: d.status,
          t: docTimeMs(d),
          names: playersOf(d).map((p) => p.name || 'Joueur'),
          stake: col === 'damier' ? stakeFor(d, target) : Math.max(0, intOr(d.stake, 0)),
        });
      }
    }),
  );
  live.sort((a, b) => b.t - a.t);

  let phone = '';
  try {
    const dep = await queryDocs(env, 'deposits', eqFilter('uid', target), 5);
    const withPhone = dep.find((x) => typeof x.phone === 'string' && x.phone);
    if (withPhone) phone = withPhone.phone;
  } catch (_) {}

  let logins = [];
  try {
    const ll = await readDoc(env, `loginLog/${target}`);
    if (ll && Array.isArray(ll.list)) {
      logins = ll.list.map((x) => ({
        t: intOr(x.t, 0),
        ip: String(x.ip || ''),
        country: String(x.country || ''),
        city: String(x.city || ''),
        ua: String(x.ua || ''),
      }));
    }
  } catch (_) {}

  return {
    uid: target,
    pseudo: nameOf(u),
    logins,
    promoCode: typeof u.promoCode === 'string' ? u.promoCode : '',
    referrer,
    referrals,
    referralEarned: intOr(u.referralEarned, 0),
    referralBalance: intOr(u.referralBalance, 0),
    referralWithdrawn: intOr(u.referralWithdrawn, 0),
    partner: u.partner === true,
    partnerEarned: intOr(u.partnerEarned, 0),
    partnerBalance: intOr(u.partnerBalance, 0),
    hostess: u.hostess === true,
    wagered: intOr(u.wagered, 0),
    balance: balanceOf(u),
    isAdminAccount: adminIds(env).includes(target),
    firstDep: intOr(u.firstDep, 0),
    wagerLeft: wagerLeft(u),
    phone,
    live,
  };
}

const HANDLERS = {
  adminPlayerInfo,
  adminDebitAccount,
  adminDeleteAccount,
  playerGames,
  cardsReplay,
  deuxDesAct,
  ludoAct,
  adminRiskClear,
  notifyInvite,
  adminResolveGame,
  myLimits,
  acceptTerms,
  setLimits,
  adminCashierLog,
  txHistory,
  adminCancelGame,
  myRole,
  adminSetCashier,
  adminCashiers,
  sweepWaiting,
  racesList,
  raceBetCreate,
  adminRaceSave,
  adminRaceCancel,
  adminRaceResult,
  sportsList,
  sportBetCreate,
  sportBetAccept,
  sportBetCancel,
  adminSportEventSave,
  adminSportEventCancel,
  adminSportEventResult,
  ensureWallet,
  applyPromo,
  referralInfo,
  payStake,
  ludoJoinRunning,
  startGame,
  captureFee,
  adminPlayers,
  leaveGame,
  settleGame,
  startLocalGame,
  settleLocalGame,
  sideBetPropose,
  sideBetAccept,
  sideBetCancel,
  sideBetSync,
  localBetCreate,
  adminStats,
  adminFindGame,
  cardsChatJoin,
  cardsChatLeave,
  zoneMe,
  playerSetCity,
  cityChangeRequest,
  zoneMy,
  zonePayoutRequest,
  adminZones,
  adminZoneSave,
  adminZoneAssign,
  adminZoneRelease,
  adminZoneStatus,
  adminZoneAttach,
  adminZonePlayers,
  adminZoneCommissions,
  adminCityChangeDecide,
  adminZonePayoutDecide,
  adminRechargeFeed,
  adminHouseWithdraw,
  campayDeposit,
  campayDepositStatus,
  manualInfo,
  manualDepositRequest,
  manualWithdrawRequest,
  manualMine,
  adminManualList,
  adminManualDecide,
  adminResetBalances,
  sebpayInfo,
  sebpayDeposit,
  sebpayDepositStatus,
  sebpayWithdrawRequest,
  sebpayMine,
  setPush,
  referralWithdraw,
  adminSetPartner,
  adminPartners,
  adminSetHostess,
  adminBackfillStats,
  adminHostesses,
  hostessStats,
  partnerStats,
  partnerWithdraw,
  transfer,
  searchPlayers,
  adminTournamentCreate,
  tournamentList,
  tournamentRegister,
  tournamentTeamCreate,
  tournamentTeamJoin,
  tournamentLeave,
  adminTournamentCancel,
  adminTournamentEntries,
  adminTournamentStart,
  cardsCreate,
  cardsJoin,
  cardsLeave,
  cardsStart,
  cardsOpen,
  cardsPlay,
  cardsDraw,
  cardsLoc,
  cardsBetPropose,
  cardsBetAccept,
  cardsBetCancel,
  cardsGet,
  cardsRematch,
  cardsList,
};

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...CORS },
  });
}

// --- Sauvegarde gratuite -----------------------------------------------
// Appelée chaque nuit par GitHub Actions (workflow « Sauvegarde gratuite »).
// Protégée par le secret Cloudflare BACKUP_TOKEN (en-tête x-backup-token).
// Renvoie une page de documents Firestore bruts (sans perte) d'une collection.
const BACKUP_COLLECTIONS = [
  'users', 'app', 'house', 'promoCodes', 'deposits', 'sebpayDeposits', 'sebpayPayouts',
  'manualDeposits', 'manualWithdrawals', 'manualRefs', 'transfers', 'partnerEarnings',
  'cashierLog', 'tournaments', 'tournamentEntries', 'tournamentTeams', 'tournamentMatches',
  'tournamentPayouts', 'races', 'raceBets', 'raceCarry', 'raceSettle', 'sportEvents',
  'sportBets', 'games', 'deuxdes', 'songo', 'damier', 'pileface', 'cards', 'localGames',
];

function sameSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function backupDump(request, env) {
  const token = typeof env.BACKUP_TOKEN === 'string' ? env.BACKUP_TOKEN : '';
  if (request.method !== 'POST' || token.length < 24 || !sameSecret(request.headers.get('x-backup-token') || '', token)) {
    return json({ error: 'Refusé.' }, 403);
  }
  let body = {};
  try {
    body = (await request.json()) || {};
  } catch (_) {}
  if (body.list === true) return json({ collections: BACKUP_COLLECTIONS });
  const col = typeof body.collection === 'string' ? body.collection : '';
  if (!BACKUP_COLLECTIONS.includes(col)) return json({ error: 'Collection inconnue.' }, 400);
  let url = `https://firestore.googleapis.com/v1/projects/${projectId(env)}/databases/(default)/documents/${col}?pageSize=300`;
  if (typeof body.pageToken === 'string' && body.pageToken) url += `&pageToken=${encodeURIComponent(body.pageToken)}`;
  const res = await fetch(url, { headers: { authorization: `Bearer ${await accessToken(env)}` } });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) return json({ error: (j.error && j.error.message) || 'Firestore' }, 502);
  return json({ docs: j.documents || [], next: j.nextPageToken || '' });
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(maybeSweep(env, true));
  },

  async fetch(request, env0, ctx) {
    const env = Object.assign(Object.create(env0), { __ctx: ctx });
    // Webhook Campay : appelé par Campay, sans connexion joueur.
    const p0 = new URL(request.url).pathname.replace(/^\/+|\/+$/g, '');
    if (p0 === 'campay/webhook') return campayWebhook(request, env);
    if (p0 === 'sebpay/webhook') return sebpayWebhook(request, env);
    if (p0 === 'backup/dump') return backupDump(request, env);

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (request.method !== 'POST') {
      return json({ error: 'POST requis.' }, 405);
    }

    const name = new URL(request.url).pathname.replace(/^\/+|\/+$/g, '');
    const handler = HANDLERS[name];
    if (!handler) {
      return json({ error: 'Fonction inconnue.' }, 404);
    }

    let whoAdmin = false;
    try {
      const m = (request.headers.get('authorization') || '').match(/^Bearer (.+)$/i);
      if (!m) throw new HttpError('unauthenticated', 'Connexion requise.');
      const uid = await verifyIdToken(m[1], env);
      try { whoAdmin = adminIds(env).includes(uid); } catch (_) {}

      let data = {};
      try {
        data = (await request.json()) || {};
      } catch (_) {}

      const guard = await guardRequest(env, uid, name, data);
      const result = await handler({ uid, data, env });
      if (name === 'ensureWallet') {
        const p = logLogin(env, uid, request).catch(() => {});
        if (ctx && ctx.waitUntil) ctx.waitUntil(p);
      }
      if (guard && guard.risk && guard.risk.length && MONEY_OUT.has(name)) {
        const p = notifyAdmin(env, `🕵️ Retrait demandé par un compte SUSPECT (${fcfaText(data.amount)}) : ${guard.risk.join(' ; ')}`).catch(() => {});
        if (ctx && ctx.waitUntil) ctx.waitUntil(p);
      }
      if (JOIN_HANDLERS.has(name)) {
        const p = pushJoined(env, uid, data).catch(() => {});
        if (ctx && ctx.waitUntil) ctx.waitUntil(p);
      }
      if (MONEY_OUT.has(name) && intOr(data.amount, 0) >= intOr(env.WITHDRAW_ALERT, 100000)) {
        const p = notifyAdmin(env, `⚠️ Gros retrait demandé : ${fcfaText(data.amount)}`).catch(() => {});
        if (ctx && ctx.waitUntil) ctx.waitUntil(p);
      }
      if (NTFY_HANDLERS.has(name)) {
        const p = ntfyAfterHandler(env, name, uid, data, result).catch(() => {});
        if (ctx && ctx.waitUntil) ctx.waitUntil(p);
      }
      return json({ data: result });
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message }, STATUS[e.code] || 400);
      }
      console.error(e);
      // Pour l'administrateur seulement : on montre la cause pour pouvoir corriger vite.
      const detail = whoAdmin ? ` [${name} : ${String((e && e.message) || e).slice(0, 160)}]` : '';
      return json({ error: 'Erreur serveur.' + detail }, 500);
    }
  },
};




