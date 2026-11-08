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
const PARTNER_WITHDRAW_MIN = 100; // gains de partenaire minimum pour les transférer vers le solde
const REVIVE_AFTER_MIN = 180; // parties bloquées depuis plus de 3 h
const REFERRAL_PERCENT = 20; // part de la commission reversée au parrain (affilié)
const JACKPOT_MIN = 550; // le jackpot se déclenche entre ces deux montants
const JACKPOT_MAX = 650;
const HOUSE_WITHDRAW_MIN = 2500; // commissions de Katika : seuil pour pouvoir les retirer (FCFA)
const REFERRAL_WITHDRAW_MIN = 100; // gains de parrainage minimum pour pouvoir les retirer vers le solde

// Parties en ligne gérées : le Ludo (« games »), Deux dés (« deuxdes »), Songô et Damier.
const ONLINE_COLLECTIONS = ['games', 'deuxdes', 'songo', 'damier', 'pileface'];
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

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

  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
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
  const j = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error((j.error && j.error.message) || 'Firestore');
    err.fsStatus = j.error && j.error.status;
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
      async get(path) {
        const r = await fsCall(env, 'batchGet', {
          documents: [docName(env, path)],
          transaction,
        });
        const first = Array.isArray(r) ? r[0] : r;
        return first && first.found ? fieldsToObj(first.found.fields || {}) : null;
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
  for (const col of ONLINE_COLLECTIONS) {
    const path = `${col}/${gameId}`;
    const data = await tx.get(path);
    if (data) return { path, data, col };
  }
  return null;
}

function refund(tx, uids, stake) {
  if (!(stake > 0)) return;
  for (const uid of uids) tx.write(`users/${uid}`, { incr: { balance: stake } });
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
  const bonus = Math.floor((share * REFERRAL_PERCENT) / 100);
  const partnerBonus = Math.floor(((share - bonus) * PARTNER_PERCENT) / 100);

  const gains = new Map();
  const pGains = new Map();
  for (const u of list) {
    const d = await tx.get(`users/${u}`);
    const r = d && typeof d.referrerUid === 'string' ? d.referrerUid : '';
    if (!r || r === u) continue;
    // Hôtesse : son code sert seulement à compter les inscrits, sans commission.
    const rh = await tx.get(`users/${r}`);
    if (rh && rh.hostess === true) continue;
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
  return { referral, partner };
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
  { stake, pot, winners, percent = COMMISSION_PERCENT, participants = [], gameId = '', mode = '' },
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
        ...(toCount.delete(uid) ? { wagered: stake } : {}),
      },
    });
  }
  for (const uid of toCount) tx.write(`users/${uid}`, { incr: { wagered: stake } });
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

// Partage des commissions : 50 % pour le 1er compte de ADMIN_UIDS, 50 % pour le
// 2e (si la somme est impaire, le franc en trop va au 1er). Chacun retire sa
// part vers son propre compte. Champs supplémentaires de house/ledger :
//   bal0 / bal1             = part disponible du 1er / du 2e administrateur
//   withdrawn0 / withdrawn1 = total déjà retiré par chacun
//   balance                 = bal0 + bal1 (total disponible)

/** Parts disponibles { b0, b1 }. Ancien format (sans bal0/bal1) : le solde
 *  actuel est partagé 50/50 la première fois. */
function houseShares(h) {
  if (h && h.bal0 !== undefined && h.bal0 !== null && h.bal1 !== undefined && h.bal1 !== null) {
    return { b0: Math.max(0, intOr(h.bal0, 0)), b1: Math.max(0, intOr(h.bal1, 0)) };
  }
  const total = Math.max(0, intOr(h ? h.balance : 0, 0));
  const b0 = Math.ceil(total / 2);
  return { b0, b1: total - b0 };
}

/** Ce que l'administrateur d'index `idx` peut retirer (`count` = nombre
 *  d'identifiants dans ADMIN_UIDS). Avec un seul administrateur, il garde tout. */
function houseMyAmount(count, idx, b0, b1) {
  if (idx === 0) return b0 + (count < 2 ? b1 : 0);
  if (idx === 1) return b1;
  return 0;
}

/** Ajoute `amount` aux commissions de Katika, réparties 50/50 entre les deux
 *  administrateurs (à appeler UNE fois par transaction). */
async function houseAdd(tx, amount) {
  amount = Math.floor(amount);
  if (!(amount > 0)) return;
  const h = await tx.get(HOUSE_PATH);
  const { b0, b1 } = houseShares(h);
  const first = Math.ceil(amount / 2);
  const n0 = b0 + first;
  const n1 = b1 + (amount - first);
  tx.write(HOUSE_PATH, {
    set: {
      bal0: n0,
      bal1: n1,
      balance: n0 + n1,
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

  return { ...info, referrals, percent: REFERRAL_PERCENT };
}

/** Paie la mise. Salle pleine + tout le monde a payé (+ binômes formés en
 *  équipe) : la partie démarre. */
async function payStake({ uid, data, env }) {
  const gameId = idOf(data);
  const announce = await runTx(env, async (tx) => {
    const g = await locate(tx, gameId);
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

    const stake = Math.max(0, intOr(d.stake, 0));
    if (stake > 0 && (stake < MIN_STAKE || stake > MAX_STAKE)) {
      throw new HttpError('failed-precondition', 'Mise invalide.');
    }
    const me = await tx.get(`users/${uid}`);
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

    if (stake > 0) tx.write(`users/${uid}`, { incr: { balance: -stake } });
    tx.write(g.path, {
      union: { paid: [uid] },
      incr: { pot: stake },
      // La partie ne démarre plus toute seule : le créateur la lance (startGame).
      set: {},
    });
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
  if (announce) await pushNewGame(env, uid, announce);
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

/** Envoie « Nouvelle partie » à tous les appareils inscrits, sauf au créateur. */
async function pushNewGame(env, hostUid, info) {
  try {
    const docs = await queryDocs(env, 'pushTokens', undefined, 300);
    const targets = docs.filter((x) => x.uid !== hostUid && typeof x.token === 'string');
    if (!targets.length) return;
    const access = await accessToken(env, 'https://www.googleapis.com/auth/firebase.messaging');
    const label = GAME_LABELS[info.col] || 'Katika';
    const who = info.host || 'Un joueur';
    const title = `🎲 Nouvelle partie de ${label}`;
    const body = info.stake > 0
      ? `${who} mise ${info.stake} FCFA 🔥 Rejoins-le !`
      : `${who} a créé une partie 🔥 Rejoins-le !`;
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
              webpush: { headers: { Urgency: 'high', TTL: '3600' } },
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
    /* une notification ratée ne doit jamais bloquer la création de la partie */
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

    tx.write(evPath, {
      create: true,
      set: { amount, capturer, victim, eliminated },
      serverTime: ['createdAt'],
    });
    tx.write(metaPath, { incr: { count: 1 } });
    if (amount > 0) {
      tx.write(`users/${victim}`, { incr: { balance: -amount } });
      tx.write(`users/${capturer}`, { incr: { balance: amount } });
    }
    return { amount, eliminated };
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
    if (g.col === 'games' && d.teamMode === true) {
      const partners = Array.isArray(d.partners) ? d.partners : [];
      const ready = players.length === 4 && partners.length === 4 && partners.every((p) => p !== -1);
      if (!ready) {
        if (players.length < 4) set.teamMode = false;
        else throw new HttpError('failed-precondition', 'Forme les binômes avant de lancer la partie.');
      }
    }
    tx.write(g.path, { set, serverTime: ['startedAt'] });
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
    const stake = Math.max(0, intOr(d.stake, 0));
    const isHost = d.hostUid === uid;
    if (!isHost && !players.some((p) => p.uid === uid)) return;

    if (isHost) {
      refund(tx, paid, stake);
      tx.delete(g.path);
      return;
    }

    const o = {
      set: { players: players.filter((p) => p.uid !== uid) },
      remove: { uids: [uid] },
    };
    if (paid.includes(uid)) {
      refund(tx, [uid], stake);
      o.remove.paid = [uid];
      o.incr = { pot: -stake };
    }
    // Les places changent quand quelqu'un part : on refait les binômes.
    if (d.teamMode === true) {
      o.set.partners = [-1, -1, -1, -1];
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
function recordStats(tx, participants, winners, stake, pot, percent, jackpot) {
  const all = [...new Set((participants || []).filter((u) => typeof u === 'string'))];
  const win = new Set(winners || []);
  const n = Math.max(1, win.size);
  const prizeShare =
    stake > 0 && pot > 0
      ? Math.floor(prizeOf(pot, percent) / n) + Math.floor(intOr(jackpot, 0) / n)
      : 0;
  for (const u of all) {
    const isWin = win.has(u);
    tx.write(`users/${u}`, {
      incr: {
        statPlayed: 1,
        statStaked: stake > 0 ? stake : 0,
        ...(isWin
          ? { statWon: 1, statWonAmt: prizeShare }
          : { statLost: 1, statLostAmt: stake > 0 ? stake : 0 }),
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
          recordStats(tx, paid.length ? paid : uids, winners, stake, pot, COMMISSION_PERCENT, intOr(g.jackpot, 0));
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
      };
    })
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
  return { players, total: players.length };
}

async function settleGame({ uid, data, env }) {
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

    // Aucun gagnant, ou égalité entre tous les joueurs : chacun récupère sa
    // mise en entier, sans aucune commission.
    const allTie = stake > 0 && paid.length >= 2 && winners.length === paid.length;
    if (winners.length === 0 || allTie) {
      refund(tx, paid, stake);
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

    const { jackpot, referral, partner, house } = await payOut(tx, {
      stake,
      pot,
      winners,
      participants: paid,
      gameId,
      mode: 'online',
    });
    recordStats(tx, paid.length ? paid : uids, winners, stake, pot, COMMISSION_PERCENT, jackpot);
    await houseAdd(tx, house);
    const commission = stake > 0 && pot > 0 ? pot - prizeOf(pot) : 0;
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
  const maxLocal = game === 'deuxdes' ? 8 : game === 'songo' || game === 'damier' || game === 'pileface' ? 2 : game === 'tiah' || game === 'boubayah' ? 6 : 4; // Deux dés : jusqu'à 8 joueurs
  const tokens = Array.isArray(data.tokens) ? data.tokens : [];
  if (tokens.length < 2 || tokens.length > maxLocal) {
    throw new HttpError('invalid-argument', 'Nombre de joueurs invalide.');
  }
  const names = Array.isArray(data.names) ? data.names.map(String) : [];
  const capAsked = intOr(data.capturePay, 0);
  const capturePay = capAsked >= MIN_CAPTURE ? Math.min(capAsked, MAX_CAPTURE) : 0;

  const uids = [];
  for (const t of tokens) uids.push(await verifyIdToken(t, env));
  if (new Set(uids).size !== uids.length) {
    throw new HttpError('invalid-argument', 'Un compte joue deux fois.');
  }
  const id = newId();
  await runTx(env, async (tx) => {
    if (stake > 0) {
      for (let i = 0; i < uids.length; i++) {
        const u = await tx.get(`users/${uids[i]}`);
        if (balanceOf(u) < stake + capturePay) {
          throw new HttpError(
            'failed-precondition',
            `Solde insuffisant : ${names[i] || 'un joueur'}`,
          );
        }
      }
      for (const u of uids) tx.write(`users/${u}`, { incr: { balance: -stake } });
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

    const players = Array.isArray(d.uids) ? d.uids : [];
    const winners = [...new Set(asked)].filter((u) => players.includes(u));
    if (winners.length === 0) {
      throw new HttpError('invalid-argument', 'Aucun gagnant valide.');
    }

    const stake = Math.max(0, intOr(d.stake, 0));
    const pot = Math.max(0, intOr(d.pot, 0));
    const bets = await loadLocalBets(tx, gameId);
    // Égalité entre tous les joueurs : les mises sont rendues, sans commission.
    const allTie = stake > 0 && players.length >= 2 && winners.length === players.length;
    let jackpot = 0;
    let referral = 0;
    let partner = 0;
    let house = 0;
    if (allTie) {
      refund(tx, players, stake);
    } else {
      const r = await payOut(tx, {
        stake,
        pot,
        winners,
        percent: COMMISSION_LOCAL_PERCENT,
        participants: players,
        gameId,
        mode: 'local',
      });
      jackpot = r.jackpot;
      referral = r.referral;
      partner = r.partner;
      house = r.house;
      recordStats(tx, players, winners, stake, pot, COMMISSION_LOCAL_PERCENT, jackpot);
    }
    const betsSummary = settleLocalBets(
      tx,
      bets,
      players,
      scores,
      Array.isArray(d.names) ? d.names : [],
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
  if (!id || (type !== 'duel' && type !== 'seven')) {
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
        side: type === 'seven' ? side : null,
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
function settleLocalBets(tx, bets, players, scores, names) {
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
async function recentDocs(env, collectionId, limit) {
  const fields = [
    'createdAt', 'status', 'stake', 'pot', 'settled', 'jackpot', 'commission',
    'betCommission', 'referralPaid', 'partnerPaid', 'refunded', 'maxPlayers', 'players', 'names',
    'uids', 'game',
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
    commission: refunded ? 0 : commission,
    prize: settled && !refunded ? Math.max(0, pot - commission) : 0,
    betCommission: Math.max(0, intOr(d.betCommission, 0)),
    referralPaid: Math.max(0, intOr(d.referralPaid, 0)),
    partnerPaid: Math.max(0, intOr(d.partnerPaid, 0)),
    jackpot: Math.max(0, intOr(d.jackpot, 0)),
  };
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

  const [ludo, deux, songo, damier, local] = await Promise.all([
    recentDocs(env, 'games', limit),
    recentDocs(env, 'deuxdes', limit),
    recentDocs(env, 'songo', limit),
    recentDocs(env, 'damier', limit),
    recentDocs(env, 'localGames', limit),
  ]);

  const rows = [
    ...ludo.map((d) => adminRow('ludo', 'online', d)),
    ...deux.map((d) => adminRow('deuxdes', 'online', d)),
    ...songo.map((d) => adminRow('songo', 'online', d)),
    ...damier.map((d) => adminRow('damier', 'online', d)),
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

  // Commissions de Katika : MA moitié (disponible / retirée). Le 1er compte de
  // ADMIN_UIDS touche 50 %, le 2e touche 50 %.
  const adminList = adminIds(env);
  const myIdx = adminList.indexOf(uid);
  let house = { available: 0, earned: 0, withdrawn: 0, totalEarned: 0 };
  try {
    const hr = await fsCall(env, 'batchGet', { documents: [docName(env, HOUSE_PATH)] });
    const hf = Array.isArray(hr) && hr[0] && hr[0].found;
    if (hf) {
      const h = fieldsToObj(hf.fields || {});
      const { b0, b1 } = houseShares(h);
      const mine = houseMyAmount(adminList.length, myIdx, b0, b1);
      const wd = Math.max(0, intOr(myIdx === 1 ? h.withdrawn1 : myIdx === 0 ? h.withdrawn0 : 0, 0));
      house = {
        available: mine,
        earned: mine + wd,
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
    fetched: { ludo: ludo.length, deuxdes: deux.length, songo: songo.length, damier: damier.length, local: local.length },
    jackpotPercent: JACKPOT_PERCENT,
    referralPercent: REFERRAL_PERCENT,
    house: {
      ...house,
      sharePercent: adminList.length < 2 ? 100 : 50,
      min: HOUSE_WITHDRAW_MIN,
      canWithdraw: myIdx >= 0 && myIdx <= 1 && house.available >= HOUSE_WITHDRAW_MIN,
    },
  };
}

/** Administrateur : transfère SA part des commissions de Katika (50 %) vers son
 *  compte principal (jetons). Possible quand elle atteint HOUSE_WITHDRAW_MIN.
 *  Seuls les 2 premiers comptes de ADMIN_UIDS reçoivent des commissions. */
async function adminHouseWithdraw({ uid, env }) {
  const ids = adminIds(env);
  if (!ids.includes(uid)) {
    throw new HttpError('permission-denied', "Accès réservé à l'administrateur.");
  }
  const idx = ids.indexOf(uid);
  if (idx > 1) {
    throw new HttpError(
      'permission-denied',
      'Les commissions sont partagées entre les 2 premiers comptes administrateurs.',
    );
  }
  return runTx(env, async (tx) => {
    const h = await tx.get(HOUSE_PATH);
    const { b0, b1 } = houseShares(h);
    const amount = houseMyAmount(ids.length, idx, b0, b1);
    if (amount < HOUSE_WITHDRAW_MIN) {
      throw new HttpError(
        'failed-precondition',
        `Retrait possible à partir de ${HOUSE_WITHDRAW_MIN} FCFA de commissions.`,
      );
    }
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    // Il ne reste que la part de l'autre administrateur (rien si un seul admin).
    const takesAll = idx === 0 && ids.length < 2;
    const n0 = idx === 0 ? 0 : b0;
    const n1 = idx === 1 || takesAll ? 0 : b1;
    tx.write(`users/${uid}`, { incr: { balance: amount } });
    tx.write(HOUSE_PATH, {
      set: {
        bal0: n0,
        bal1: n1,
        balance: n0 + n1,
        withdrawn: Math.max(0, intOr(h.withdrawn, 0)) + amount,
        ...(idx === 0
          ? { withdrawn0: Math.max(0, intOr(h.withdrawn0, 0)) + amount }
          : { withdrawn1: Math.max(0, intOr(h.withdrawn1, 0)) + amount }),
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
async function settleDeposit(env, id) {
  const dep = await readDoc(env, `deposits/${id}`);
  if (!dep) return { status: 'unknown' };
  if (dep.status !== 'pending' || !dep.campayRef) return { status: dep.status };

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
  for (const col of ['games', 'deuxdes', 'songo', 'damier', 'pileface', 'localGames']) {
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
            : (Array.isArray(d.paid) ? d.paid : []);
        refund(tx, who, stake);
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
async function notifyAdmin(env, text) {
  // WhatsApp (service CallMeBot) : variables WHATSAPP_PHONE et WHATSAPP_APIKEY.
  try {
    if (env.WHATSAPP_PHONE && env.WHATSAPP_APIKEY) {
      const phone = String(env.WHATSAPP_PHONE).replace(/\D/g, '');
      const url =
        `https://api.callmebot.com/whatsapp.php?phone=${phone}` +
        `&text=${encodeURIComponent(text)}&apikey=${encodeURIComponent(env.WHATSAPP_APIKEY)}`;
      await fetch(url);
    }
  } catch (_) {
    /* sans effet */
  }
  // ntfy (notification gratuite, sans compte) : variable NTFY_TOPIC.
  try {
    if (env.NTFY_TOPIC) {
      await fetch(`https://ntfy.sh/${encodeURIComponent(env.NTFY_TOPIC)}`, {
        method: 'POST',
        headers: { Title: 'Katika', Priority: 'high', Tags: 'moneybag' },
        body: text,
      });
    }
  } catch (_) {
    /* sans effet */
  }
  // Telegram (facultatif) : TELEGRAM_BOT_TOKEN et TELEGRAM_CHAT_ID.
  try {
    if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
      });
    }
  } catch (_) {
    /* sans effet */
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
  await notifyAdmin(
    env,
    `⬇️ Recharge à confirmer (${operator === 'mtn' ? 'MTN MoMo' : 'Orange Money'})\n${amount} FCFA · ${phone}\nTransaction : ${txRef}\nOuvre Katika > Admin > Recharges et retraits.`
  );
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
    tx.write(`users/${uid}`, { incr: { balance: -tokens } });
    tx.write(`manualWithdrawals/${id}`, {
      create: true,
      set: { uid, name: typeof me.pseudo === 'string' ? me.pseudo : '', amount, tokens, phone, status: 'pending' },
      serverTime: ['createdAt'],
    });
    return balanceOf(me) - tokens;
  });
  await notifyAdmin(
    env,
    `⬆️ Retrait à payer\n${amount} FCFA vers ${phone}\nOuvre Katika > Admin > Recharges et retraits.`
  );
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
  requireAdmin(uid, env);
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
  return {
    deposits: dp.map(row('deposit')).sort(byDateDesc('createdAt')),
    withdrawals: wp.map(row('withdrawal')).sort(byDateDesc('createdAt')),
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

async function adminManualDecide({ uid, data, env }) {
  requireAdmin(uid, env);
  const id = idStr(data.id);
  const kind = data.kind === 'withdrawal' ? 'withdrawal' : data.kind === 'deposit' ? 'deposit' : '';
  const approve = data.action === 'approve';
  if (!id || !kind || (!approve && data.action !== 'reject')) {
    throw new HttpError('invalid-argument', 'Demande invalide.');
  }
  const path = kind === 'deposit' ? `manualDeposits/${id}` : `manualWithdrawals/${id}`;
  return runTx(env, async (tx) => {
    const d = await tx.get(path);
    if (!d) throw new HttpError('not-found', 'Demande introuvable.');
    if (d.status !== 'pending') throw new HttpError('failed-precondition', 'Cette demande est déjà traitée.');
    const tokens = kind === 'deposit' ? intOr(d.amount, 0) * TOKENS_PER_XAF : intOr(d.tokens, 0);
    let status;
    if (kind === 'deposit') {
      status = approve ? 'credited' : 'rejected';
      if (approve) tx.write(`users/${d.uid}`, { incr: { balance: tokens } });
    } else {
      status = approve ? 'paid' : 'rejected';
      if (!approve) tx.write(`users/${d.uid}`, { incr: { balance: tokens } }); // remboursé
    }
    tx.write(path, { set: { status, closedBy: uid }, serverTime: ['closedAt'] });
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
  return { id, status: 'pending', providerLink: link };
}

/** Lit la collecte chez SebPay et crédite le solde (une seule fois). */
async function settleSebpayDeposit(env, id) {
  const dep = await readDoc(env, `sebpayDeposits/${id}`);
  if (!dep) return { status: 'unknown' };
  if (dep.status !== 'pending') return { status: dep.status };

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
    tx.write(`users/${d.uid}`, { incr: { balance: tokens } });
    tx.write(`sebpayDeposits/${id}`, {
      set: { status: 'credited', tokens, sebpayTx: String(r.data.transaction_id || d.sebpayTx || '') },
      serverTime: ['closedAt'],
    });
    return { status: 'credited', amount: d.amount };
  });
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
async function settleSebpayPayout(env, id) {
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
  const gid = newId();
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

// ======================================================================
// Damier « DEUX BUTS SORT » : salle ouverte à tous, file d'attente, matchs misés
// ======================================================================
// Règles : un joueur sort s'il perd 2 matchs, ou s'il perd 1 match et fait 1 nul.
// Deux joueurs qui s'affrontent rejouent ensemble tant qu'aucun ne sort ; si
// après 2 matchs aucun n'est sorti : match de barrage (le perdant sort ; nul =
// les deux sortent). Le gagnant reste et affronte le suivant de la file
// (ordre d'arrivée). Chaque match est misé (gagnant : 2 mises − 5 %, nul :
// mises rendues, via settleGame).
//   dbRooms/{id}          : la salle + l'état de la table
//   dbPlayers/{rid}_{uid} : un joueur dans la salle (fautes, rang d'arrivée)

const DB_LOCK_MS = 25000;

function dbInitialBoard() {
  const b = new Array(100).fill(0);
  for (let r = 0; r < 10; r++) {
    for (let c = 0; c < 10; c++) {
      if ((r + c) % 2 !== 1) continue;
      if (r < 4) b[r * 10 + c] = -1;
      else if (r >= 6) b[r * 10 + c] = 1;
    }
  }
  return b;
}

function dbHash(board, cur) {
  let h = 7;
  for (const p of board) h = (h * 31 + p + 2) & 0x7fffffff;
  return (h * 2 + cur) & 0x7fffffff;
}

function dbRid(data) {
  const rid = idStr(data.rid);
  if (!rid) throw new HttpError('invalid-argument', 'Salle inconnue.');
  return rid;
}

function dbOut(p) {
  return intOr(p.losses, 0) >= 2 || (intOr(p.losses, 0) >= 1 && intOr(p.draws, 0) >= 1);
}

/** Crée une salle (n'importe quel joueur connecté). */
async function dbCreate({ uid, data, env }) {
  const stake = intOr(data.stake, 0);
  if (stake < MIN_STAKE || stake > MAX_STAKE) {
    throw new HttpError('invalid-argument', `Mise entre ${MIN_STAKE} et ${MAX_STAKE} FCFA.`);
  }
  const timeMin = Math.min(30, Math.max(2, intOr(data.timeMin, 10)));
  const id = newId();
  const me = await readDoc(env, `users/${uid}`);
  if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
  await runTx(env, async (tx) => {
    tx.write(`dbRooms/${id}`, {
      create: true,
      set: {
        title: String(data.title || 'DEUX BUTS SORT').slice(0, 40),
        hostUid: uid,
        hostName: tournName(me),
        stake,
        timeMin,
        status: 'open',
        seq: 0,
        pair: [],
        matchNo: 0,
        gameId: '',
        lockMs: 0,
      },
      serverTime: ['createdAt'],
    });
  });
  return { id };
}

/** Rejoindre la salle (ou y revenir après être sorti). */
async function dbJoin({ uid, data, env }) {
  const rid = dbRid(data);
  const res = await runTx(env, async (tx) => {
    const r = await tx.get(`dbRooms/${rid}`);
    if (!r || r.status !== 'open') throw new HttpError('failed-precondition', 'Cette salle est fermée.');
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const old = await tx.get(`dbPlayers/${rid}_${uid}`);
    if (old && (old.state === 'waiting' || old.state === 'table' || old.state === 'playing')) {
      throw new HttpError('failed-precondition', 'Tu es déjà dans la salle.');
    }
    if (balanceOf(me) < intOr(r.stake, 0)) {
      throw new HttpError('failed-precondition', `Il faut au moins ${r.stake} FCFA pour jouer un match.`);
    }
    const seq = intOr(r.seq, 0) + 1;
    tx.write(`dbRooms/${rid}`, { set: { seq } });
    tx.write(`dbPlayers/${rid}_${uid}`, {
      set: {
        rid,
        uid,
        name: tournName(me),
        seq,
        state: 'waiting',
        losses: 0,
        draws: 0,
        wins: 0,
      },
    });
    return { seq };
  });
  await dbDrive(env, rid);
  return res;
}

/** Quitter la salle (impossible pendant un match). */
async function dbLeave({ uid, data, env }) {
  const rid = dbRid(data);
  await runTx(env, async (tx) => {
    const p = await tx.get(`dbPlayers/${rid}_${uid}`);
    if (!p || p.state === 'out' || p.state === 'left') return;
    if (p.state === 'playing') {
      throw new HttpError('failed-precondition', 'Termine ton match en cours avant de quitter.');
    }
    tx.write(`dbPlayers/${rid}_${uid}`, { set: { state: 'left' } });
    if (p.state === 'table') {
      const r = await tx.get(`dbRooms/${rid}`);
      if (r) {
        const pair = (Array.isArray(r.pair) ? r.pair : []).filter((u) => u !== uid);
        tx.write(`dbRooms/${rid}`, { set: { pair, matchNo: 0 } });
      }
    }
  });
  await dbDrive(env, rid);
  return { left: true };
}

/** Le créateur (ou l'admin) ferme la salle : plus de nouveau match. */
async function dbClose({ uid, data, env }) {
  const rid = dbRid(data);
  await runTx(env, async (tx) => {
    const r = await tx.get(`dbRooms/${rid}`);
    if (!r) throw new HttpError('not-found', 'Salle introuvable.');
    if (r.hostUid !== uid && !adminIds(env).includes(uid)) {
      throw new HttpError('permission-denied', 'Seul le créateur peut fermer la salle.');
    }
    tx.write(`dbRooms/${rid}`, { set: { status: 'closed' } });
  });
  return { closed: true };
}

/** Prend le verrou de la salle (un seul « moteur » à la fois). */
async function dbLock(env, rid) {
  return runTx(env, async (tx) => {
    const r = await tx.get(`dbRooms/${rid}`);
    if (!r) return null;
    if (Date.now() - intOr(r.lockMs, 0) < DB_LOCK_MS) return null;
    tx.write(`dbRooms/${rid}`, { set: { lockMs: Date.now() } });
    return r;
  });
}

async function dbUnlock(env, rid, set) {
  await runTx(env, async (tx) => {
    tx.write(`dbRooms/${rid}`, { set: { ...(set || {}), lockMs: 0 } });
  });
}

/** Fait avancer la salle : règle le match fini, désigne les sortants, lance le suivant. */
async function dbDrive(env, rid) {
  const room = await dbLock(env, rid);
  if (!room) return;
  let set = {};
  try {
    const players = await queryDocs(env, 'dbPlayers', eqFilter('rid', rid), 300);
    const byUid = new Map(players.map((p) => [p.uid, p]));
    let pair = Array.isArray(room.pair) ? room.pair.slice() : [];
    let matchNo = intOr(room.matchNo, 0);
    let gameId = room.gameId || '';
    const patch = new Map(); // uid -> champs à écrire

    const upd = (uid, f) => {
      patch.set(uid, { ...(patch.get(uid) || {}), ...f });
      Object.assign(byUid.get(uid), f);
    };

    // 1) Un match est en cours : est-il fini ?
    if (gameId) {
      const g = await readDoc(env, `damier/${gameId}`);
      if (g && g.over === true) {
        const uids = (Array.isArray(g.players) ? g.players : []).map((p) => p.uid);
        if (g.settled !== true && uids.length === 2) {
          try {
            await settleGame({ uid: uids[0], data: { gameId }, env });
          } catch (e) {
            console.error('db settle', e);
          }
        }
        const w = damierWinners(g, uids);
        const [a, b] = uids;
        const forcedOut = new Set();
        if (w.length === 1) {
          const win = w[0];
          const lose = win === a ? b : a;
          upd(win, { wins: intOr(byUid.get(win).wins, 0) + 1 });
          upd(lose, { losses: intOr(byUid.get(lose).losses, 0) + 1 });
          if (matchNo >= 3) forcedOut.add(lose);
        } else {
          for (const u of uids) upd(u, { draws: intOr(byUid.get(u).draws, 0) + 1 });
          if (matchNo >= 3) uids.forEach((u) => forcedOut.add(u));
        }
        const outs = uids.filter((u) => forcedOut.has(u) || dbOut(byUid.get(u)));
        for (const u of outs) upd(u, { state: 'out' });
        for (const u of uids) if (!outs.includes(u)) upd(u, { state: 'table' });
        gameId = '';
        if (outs.length === 0) {
          pair = [b, a]; // même duo, on inverse les couleurs
          matchNo += 1;
        } else {
          pair = uids.filter((u) => !outs.includes(u));
          matchNo = 0;
        }
      } else if (!g) {
        gameId = '';
        matchNo = 0;
        pair = [];
      } else {
        // Match toujours en cours. S'il traîne bien au-delà des horloges
        // (joueurs absents), on le déclare nul : mises rendues au prochain passage.
        const limit = (intOr(room.timeMin, 10) * 2 + 8) * 60000;
        if (intOr(g.startedMs, 0) > 0 && Date.now() - intOr(g.startedMs, 0) > limit) {
          await runTx(env, async (tx) => {
            tx.write(`damier/${gameId}`, {
              set: { over: true, winners: [0, 1], status: 'finished', reason: 'timeout' },
            });
          });
        }
        await dbUnlock(env, rid, {});
        await dbFlush(env, rid, patch);
        return;
      }
    }

    // 2) Pas de match : compléter la table avec la file d'attente.
    if (!gameId && room.status === 'open') {
      pair = pair.filter((u) => byUid.has(u) && byUid.get(u).state === 'table');
      const queue = players
        .filter((p) => p.state === 'waiting')
        .sort((x, y) => intOr(x.seq, 0) - intOr(y.seq, 0));
      const stake = intOr(room.stake, 0);
      let guard = 0;
      while (pair.length < 2 && queue.length > 0 && guard++ < 300) {
        const nx = queue.shift();
        const u = await readDoc(env, `users/${nx.uid}`);
        if (!u || balanceOf(u) < stake) {
          upd(nx.uid, { state: 'out', note: 'solde' });
          continue;
        }
        upd(nx.uid, { state: 'table' });
        pair.push(nx.uid);
      }
      // Le joueur resté à table doit aussi pouvoir payer.
      if (pair.length === 2) {
        const bal = await Promise.all(pair.map((u) => readDoc(env, `users/${u}`)));
        const lowIdx = bal.findIndex((x) => !x || balanceOf(x) < stake);
        if (lowIdx >= 0) {
          upd(pair[lowIdx], { state: 'out', note: 'solde' });
          pair.splice(lowIdx, 1);
          matchNo = 0;
        }
      }
      if (pair.length === 2) {
        const start = await dbStartMatch(env, rid, room, pair, byUid, matchNo === 0 ? 1 : matchNo);
        if (start) {
          gameId = start;
          if (matchNo === 0) matchNo = 1;
          for (const u of pair) upd(u, { state: 'playing' });
        } else {
          for (const u of pair) upd(u, { state: 'out', note: 'solde' });
          pair = [];
          matchNo = 0;
        }
      } else {
        matchNo = 0;
      }
    }
    set = { pair, matchNo, gameId };
    await dbFlush(env, rid, patch);
  } catch (e) {
    console.error('dbDrive', e);
  }
  await dbUnlock(env, rid, set);
}

async function dbFlush(env, rid, patch) {
  for (const [uid, f] of patch) {
    await runTx(env, async (tx) => {
      tx.write(`dbPlayers/${rid}_${uid}`, { set: f });
    });
  }
}

/** Débite les 2 mises et crée la partie de Damier. Renvoie l'identifiant, ou '' si un solde manque. */
async function dbStartMatch(env, rid, room, pair, byUid, matchNo) {
  const stake = intOr(room.stake, 0);
  const gid = newId();
  const timeMs = intOr(room.timeMin, 10) * 60000;
  const names = pair.map((u) => byUid.get(u).name || 'Joueur');
  const board = dbInitialBoard();
  try {
    await runTx(env, async (tx) => {
      const us = [];
      for (const u of pair) {
        const d = await tx.get(`users/${u}`);
        if (!d || balanceOf(d) < stake) throw new HttpError('failed-precondition', 'Solde insuffisant.');
        us.push(d);
      }
      for (const u of pair) tx.write(`users/${u}`, { incr: { balance: -stake } });
      tx.write(`damier/${gid}`, {
        create: true,
        set: {
          hostUid: pair[0],
          hostName: names[0],
          maxPlayers: 2,
          private: true,
          stake,
          paid: [pair[0], pair[1]],
          pot: stake * 2,
          code: tournCode(),
          status: 'playing',
          players: pair.map((u, i) => ({ uid: u, name: names[i] })),
          uids: pair.slice(),
          miss: [0, 0],
          timeMin: intOr(room.timeMin, 10),
          timeMinOpp: intOr(room.timeMin, 10),
          incSec: 0,
          clockMs: [timeMs, timeMs],
          hSeat: -1,
          hN: 0,
          drawSeat: -1,
          drawNum: 1,
          drawDen: 2,
          board,
          cur: 0,
          moveN: 0,
          over: false,
          winners: [],
          lastFrom: -1,
          lastPath: [],
          lastCaps: [],
          quiet: 0,
          hist: [dbHash(board, 0)],
          reason: '',
          dbRoomId: rid,
          barrage: matchNo >= 3,
          startedMs: Date.now(),
        },
        serverTime: ['createdAt', 'startedAt'],
      });
    });
  } catch (e) {
    if (e instanceof HttpError) return '';
    throw e;
  }
  return gid;
}

/** Liste des salles ouvertes (et la mienne) ; fait avancer chaque salle au passage. */
async function dbList({ uid, data, env }) {
  await accessToken(env);
  const rid = data && data.rid ? idStr(data.rid) : '';
  let rooms = await queryDocs(env, 'dbRooms', eqFilter('status', 'open'), 20);
  if (rid && !rooms.find((r) => r.id === rid)) {
    const one = await readDoc(env, `dbRooms/${rid}`);
    if (one) rooms.push({ id: rid, ...one });
  }
  const out = [];
  for (const r of rooms) {
    if (r.status === 'open' && (rid ? r.id === rid : true)) await dbDrive(env, r.id);
    const room = (await readDoc(env, `dbRooms/${r.id}`)) || r;
    const players = await queryDocs(env, 'dbPlayers', eqFilter('rid', r.id), 300);
    const act = players.filter((p) => p.state === 'waiting' || p.state === 'table' || p.state === 'playing');
    const pub = (p) => ({
      uid: p.uid,
      name: p.name || '',
      seq: intOr(p.seq, 0),
      state: p.state,
      losses: intOr(p.losses, 0),
      draws: intOr(p.draws, 0),
      wins: intOr(p.wins, 0),
    });
    const me = players.find((p) => p.uid === uid);
    out.push({
      id: r.id,
      title: room.title || 'DEUX BUTS SORT',
      hostUid: room.hostUid,
      hostName: room.hostName || '',
      stake: intOr(room.stake, 0),
      timeMin: intOr(room.timeMin, 10),
      status: room.status,
      matchNo: intOr(room.matchNo, 0),
      gameId: room.gameId || '',
      pair: Array.isArray(room.pair) ? room.pair : [],
      players: act.sort((a, b) => intOr(a.seq, 0) - intOr(b.seq, 0)).map(pub),
      me: me ? pub(me) : null,
    });
  }
  return { rooms: out, now: Date.now() };
}

// ======================================================================
// Pile ou Face : duel en ligne à deux, tirage fait ici (côté serveur)
// ======================================================================
// pileface/{id} : { hostUid, hostName, hostSide ('pile'|'face'), stake, paid, pot,
//   players, uids, status ('waiting'|'playing'|'finished'|'cancelled'),
//   result, winnerUid, over, settled }
// Le créateur mise et choisit son côté ; celui qui relève le défi mise la même
// somme et prend l'autre côté. La pièce est tirée au hasard au moment où le 2e
// joueur relève le défi ; le règlement (5 % de commission) passe par settleGame.

const PF_MAX_OPEN_PER_HOST = 3;

function pfSide(v) {
  return v === 'face' ? 'face' : 'pile';
}

function pfLockedStake(data) {
  const stake = intOr(data.stake, 0);
  if (stake < MIN_STAKE || stake > MAX_STAKE) {
    throw new HttpError('invalid-argument', `Mise entre ${MIN_STAKE} et ${MAX_STAKE} FCFA.`);
  }
  return stake;
}

/** Crée un défi : la mise du créateur est débitée tout de suite. */
async function pfCreate({ uid, data, env }) {
  const stake = pfLockedStake(data);
  const side = pfSide(data.side);
  const open = await queryDocs(env, 'pileface', eqFilter('hostUid', uid), 100);
  if (open.filter((g) => g.status === 'waiting').length >= PF_MAX_OPEN_PER_HOST) {
    throw new HttpError('failed-precondition', `Tu as déjà ${PF_MAX_OPEN_PER_HOST} défis ouverts. Annule-en un d'abord.`);
  }
  const id = newId();
  return runTx(env, async (tx) => {
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    if (balanceOf(me) < stake) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    tx.write(`users/${uid}`, { incr: { balance: -stake } });
    tx.write(`pileface/${id}`, {
      create: true,
      set: {
        hostUid: uid,
        hostName: tournName(me),
        hostSide: side,
        stake,
        paid: [uid],
        pot: stake,
        players: [{ uid, name: tournName(me) }],
        uids: [uid],
        maxPlayers: 2,
        status: 'waiting',
        over: false,
      },
      serverTime: ['createdAt'],
    });
    return { id, balance: balanceOf(me) - stake };
  });
}

/** Relève un défi : mise identique, côté opposé, tirage immédiat, règlement automatique. */
async function pfJoin({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Défi inconnu.');
  const roll = crypto.getRandomValues(new Uint8Array(1))[0] % 2 === 0 ? 'pile' : 'face';
  const out = await runTx(env, async (tx) => {
    const g = await tx.get(`pileface/${gid}`);
    if (!g || g.status !== 'waiting') {
      throw new HttpError('failed-precondition', "Ce défi n'est plus disponible.");
    }
    if (g.hostUid === uid) throw new HttpError('invalid-argument', 'Tu ne peux pas relever ton propre défi.');
    const me = await tx.get(`users/${uid}`);
    if (!me) throw new HttpError('failed-precondition', 'Compte introuvable.');
    const stake = intOr(g.stake, 0);
    if (balanceOf(me) < stake) throw new HttpError('failed-precondition', 'Solde insuffisant.');
    const hostWins = roll === g.hostSide;
    const winnerUid = hostWins ? g.hostUid : uid;
    tx.write(`users/${uid}`, { incr: { balance: -stake } });
    tx.write(`pileface/${gid}`, {
      set: {
        joinerUid: uid,
        joinerName: tournName(me),
        paid: [g.hostUid, uid],
        pot: stake * 2,
        players: [
          { uid: g.hostUid, name: g.hostName || 'Joueur' },
          { uid, name: tournName(me) },
        ],
        uids: [g.hostUid, uid],
        status: 'playing',
        result: roll,
        winnerUid,
        over: true,
      },
      serverTime: ['playedAt'],
    });
    return { stake, hostSide: g.hostSide, hostUid: g.hostUid, winnerUid, hostName: g.hostName || '' };
  });
  let gain = 0;
  try {
    await settleGame({ uid, data: { gameId: gid }, env });
    gain = prizeOf(out.stake * 2);
  } catch (e) {
    console.error('pf settle', e);
  }
  const me2 = await readDoc(env, `users/${uid}`);
  return {
    gameId: gid,
    result: roll,
    mySide: out.hostSide === 'pile' ? 'face' : 'pile',
    won: out.winnerUid === uid,
    gain,
    stake: out.stake,
    opponentName: out.hostName,
    balance: balanceOf(me2),
  };
}

/** Le créateur annule son défi tant que personne ne l'a relevé : mise rendue. */
async function pfCancel({ uid, data, env }) {
  const gid = idStr(data.gameId);
  if (!gid) throw new HttpError('invalid-argument', 'Défi inconnu.');
  return runTx(env, async (tx) => {
    const g = await tx.get(`pileface/${gid}`);
    if (!g || g.status !== 'waiting') throw new HttpError('failed-precondition', "Ce défi n'est plus ouvert.");
    if (g.hostUid !== uid) throw new HttpError('permission-denied', 'Ce défi ne t\'appartient pas.');
    tx.write(`users/${uid}`, { incr: { balance: intOr(g.stake, 0) } });
    tx.write(`pileface/${gid}`, { set: { status: 'cancelled', over: true, settled: true } });
    return { refunded: intOr(g.stake, 0) };
  });
}

/** Défis ouverts + mes derniers tirages + mon solde. Règle au passage un tirage resté en suspens. */
async function pfList({ uid, env }) {
  await accessToken(env);
  const open = await queryDocs(env, 'pileface', eqFilter('status', 'waiting'), 60);
  const mineAll = await queryDocs(env, 'pileface', arrayContainsFilter('uids', uid), 60);
  for (const g of mineAll) {
    if (g.over === true && g.settled !== true && g.status === 'playing') {
      try {
        await settleGame({ uid, data: { gameId: g.id }, env });
        g.status = 'finished';
        g.settled = true;
      } catch (e) {
        console.error('pf resettle', e);
      }
    }
  }
  const me = await readDoc(env, `users/${uid}`);
  const toOpen = (g) => ({
    id: g.id,
    hostUid: g.hostUid,
    hostName: g.hostName || '',
    hostSide: g.hostSide,
    stake: intOr(g.stake, 0),
  });
  const toDone = (g) => {
    const mine = g.hostUid === uid;
    const mySide = mine ? g.hostSide : g.hostSide === 'pile' ? 'face' : 'pile';
    return {
      id: g.id,
      stake: intOr(g.stake, 0),
      result: g.result,
      mySide,
      won: g.winnerUid === uid,
      opponentName: mine ? g.joinerName || '' : g.hostName || '',
      gain: prizeOf(intOr(g.stake, 0) * 2),
      at: typeof g.playedAt === 'string' ? g.playedAt : '',
    };
  };
  return {
    balance: balanceOf(me),
    open: open.sort(byDateDesc('createdAt')).map(toOpen),
    done: mineAll
      .filter((g) => g.status === 'finished' && g.result)
      .sort(byDateDesc('playedAt'))
      .slice(0, 12)
      .map(toDone),
  };
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

const HANDLERS = {
  ensureWallet,
  applyPromo,
  referralInfo,
  payStake,
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
  adminTournamentCreate,
  tournamentList,
  tournamentRegister,
  tournamentTeamCreate,
  tournamentTeamJoin,
  tournamentLeave,
  adminTournamentCancel,
  adminTournamentEntries,
  adminTournamentStart,
  dbCreate,
  dbJoin,
  dbLeave,
  dbClose,
  dbList,
  pfCreate,
  pfJoin,
  pfCancel,
  pfList,
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

export default {
  async fetch(request, env) {
    // Webhook Campay : appelé par Campay, sans connexion joueur.
    const p0 = new URL(request.url).pathname.replace(/^\/+|\/+$/g, '');
    if (p0 === 'campay/webhook') return campayWebhook(request, env);
    if (p0 === 'sebpay/webhook') return sebpayWebhook(request, env);

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (request.method !== 'POST') {
      return json({ error: 'POST requis.' }, 405);
    }

    const name = new URL(request.url).pathname.replace(/^\/+|\/+$/g, '');
    const handler = HANDLERS[name];
    if (!handler) {
      return json({ error: 'Fonction inconnue.' }, 404);
    }

    try {
      const m = (request.headers.get('authorization') || '').match(/^Bearer (.+)$/i);
      if (!m) throw new HttpError('unauthenticated', 'Connexion requise.');
      const uid = await verifyIdToken(m[1], env);

      let data = {};
      try {
        data = (await request.json()) || {};
      } catch (_) {}

      const result = await handler({ uid, data, env });
      return json({ data: result });
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message }, STATUS[e.code] || 400);
      }
      console.error(e);
      return json({ error: 'Erreur serveur.' }, 500);
    }
  },
};




