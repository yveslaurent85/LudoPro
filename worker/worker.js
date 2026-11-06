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
const COMMISSION_PERCENT = 6; // en ligne : part gardée par Katika sur la cagnotte (0-100)
const COMMISSION_LOCAL_PERCENT = 6; // présentiel (Ludo, Deux dés et Songô)
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
const ONLINE_COLLECTIONS = ['games', 'deuxdes', 'songo', 'damier'];
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

/** Gain du gagnant : la cagnotte moins la commission (6 % en ligne et en présentiel). */
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

