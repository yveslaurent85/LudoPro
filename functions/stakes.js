const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const REGION = 'europe-west1';
const WELCOME = 10000; // jetons offerts à chaque compte
const MIN_STAKE = 100; // mise minimale
const COMMISSION_PERCENT = 5; // part gardée par Katika sur la cagnotte (0-100)
const JACKPOT_PERCENT = 10; // part de la commission versée au jackpot
const JACKPOT_MIN = 550; // le jackpot se déclenche entre ces deux montants
const JACKPOT_MAX = 650;
const opts = { region: REGION };

function needAuth(request) {
if (!request.auth) {
throw new HttpsError('unauthenticated', 'Connexion requise.');
}
return request.auth.uid;
}

function balanceOf(snap) {
const d = snap.exists ? snap.data() : null;
return d && typeof d.balance === 'number' ? d.balance : 0;
}

// --- Jackpot ----------------------------------------------------------
// app/jackpot       : { pool }   (lisible par les joueurs, pour l'afficher)
// app/jackpotTarget : { target } (secret : tirage au sort entre 550 et 650)
// Quand la cagnotte du jackpot a atteint le seuil tiré au sort, le gagnant de
// la partie suivante remporte tout le jackpot, puis un nouveau seuil est tiré.

function newTarget() {
return JACKPOT_MIN + Math.floor(Math.random() * (JACKPOT_MAX - JACKPOT_MIN + 1));
}

// À appeler AVANT toute écriture de la transaction.
async function readJackpot(tx) {
const poolRef = db.collection('app').doc('jackpot');
const targetRef = db.collection('app').doc('jackpotTarget');
const [ps, ts] = await Promise.all([tx.get(poolRef), tx.get(targetRef)]);
const pool = ps.exists && typeof ps.data().pool === 'number' ? ps.data().pool : 0;
const target = ts.exists && typeof ts.data().target === 'number' ? ts.data().target : newTarget();
return { poolRef, targetRef, pool, target, hadTarget: ts.exists };
}

// fee = commission totale de la partie. Renvoie la part du jackpot pour chaque
// gagnant et ce que l'application garde (fee - part du jackpot).
function applyJackpot(tx, jp, fee, nWinners) {
let pool = jp.pool;
let target = jp.target;
let perWinner = 0;
let newTargetDrawn = !jp.hadTarget;

if (pool >= target && nWinners > 0) {
perWinner = Math.floor(pool / nWinners);
pool -= perWinner * nWinners; // reste éventuel : conservé pour la suite
target = newTarget();
newTargetDrawn = true;
}
const cut = Math.floor((fee * JACKPOT_PERCENT) / 100);
pool += cut;

tx.set(jp.poolRef, { pool, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
if (newTargetDrawn) tx.set(jp.targetRef, { target });
return { perWinner, kept: fee - cut };
}

function colorsFor(max) {
return max === 2 ? [0, 2] : max === 3 ? [0, 1, 2] : [0, 1, 2, 3];
}

// ---------------------------------------------------------------------
// Compte : 10 000 jetons offerts (une seule fois par compte)
// ---------------------------------------------------------------------
exports.ensureWallet = onCall(opts, async (request) => {
const uid = needAuth(request);
const ref = db.collection('users').doc(uid);
const pseudo = String((request.data && request.data.pseudo) || '').slice(0, 40);
const email = (request.auth.token && request.auth.token.email) || '';

const balance = await db.runTransaction(async (tx) => {
const snap = await tx.get(ref);
if (!snap.exists) {
tx.set(ref, {
name: pseudo,
email,
balance: WELCOME,
welcome: true,
createdAt: FieldValue.serverTimestamp(),
});
return WELCOME;
}
let b = balanceOf(snap);
if (!snap.data().welcome) {
b += WELCOME;
tx.update(ref, { balance: b, welcome: true });
}
return b;
});
return { balance };
});

// ---------------------------------------------------------------------
// Partie en ligne : paiement de la mise (idempotent)
// ---------------------------------------------------------------------
exports.payStake = onCall(opts, async (request) => {
const uid = needAuth(request);
const gameId = String((request.data && request.data.gameId) || '');
if (!gameId) throw new HttpsError('invalid-argument', 'Partie inconnue.');

const gref = db.collection('games').doc(gameId);
const uref = db.collection('users').doc(uid);

return db.runTransaction(async (tx) => {
const [gs, us] = await Promise.all([tx.get(gref), tx.get(uref)]);
if (!gs.exists) {
throw new HttpsError('not-found', "Cette partie n'existe plus.");
}
const g = gs.data();
const players = g.players || [];
if (!players.some((p) => p.uid === uid)) {
throw new HttpsError('permission-denied', 'Tu ne fais pas partie de cette partie.');
}
const stake = Number(g.stake) || 0;
if (stake < MIN_STAKE) {
throw new HttpsError('failed-precondition', Mise minimale : ${MIN_STAKE}.);
}
const paid = g.paid || [];
if (paid.includes(uid)) return { ok: true };
if (g.status !== 'waiting') {
throw new HttpsError('failed-precondition', 'La partie a déjà commencé.');
}
const bal = balanceOf(us);
if (bal < stake) {
throw new HttpsError('failed-precondition', 'Solde insuffisant pour cette mise.');
}

const newPaid = [...paid, uid];  
const max = Number(g.maxPlayers) || 2;  
const teamsOk =  
  g.teamMode !== true ||  
  (Array.isArray(g.partners) && g.partners.length === 4 && g.partners.every((p) => p !== -1));  
const start = players.length >= max && newPaid.length >= max && teamsOk;  

tx.set(uref, { balance: bal - stake }, { merge: true });  
tx.update(gref, {  
  paid: newPaid,  
  pot: (Number(g.pot) || 0) + stake,  
  ...(start ? { status: 'playing' } : {}),  
});  
return { ok: true };

});
});

// ---------------------------------------------------------------------
// Partie en ligne pas commencée : quitter / annuler, mise remboursée
// ---------------------------------------------------------------------
exports.leaveGame = onCall(opts, async (request) => {
const uid = needAuth(request);
const gameId = String((request.data && request.data.gameId) || '');
if (!gameId) throw new HttpsError('invalid-argument', 'Partie inconnue.');
const gref = db.collection('games').doc(gameId);

await db.runTransaction(async (tx) => {
const gs = await tx.get(gref);
if (!gs.exists) return;
const g = gs.data();
if (g.status !== 'waiting') {
throw new HttpsError('failed-precondition', 'La partie a déjà commencé.');
}
const players = g.players || [];
if (!players.some((p) => p.uid === uid)) return;

const stake = Number(g.stake) || 0;  
const paid = g.paid || [];  
const isHost = g.hostUid === uid;  
const refundUids = isHost ? paid : paid.filter((u) => u === uid);  

const refs = refundUids.map((u) => db.collection('users').doc(u));  
const snaps = await Promise.all(refs.map((r) => tx.get(r)));  
snaps.forEach((s, i) => {  
  tx.set(refs[i], { balance: balanceOf(s) + stake }, { merge: true });  
});  

if (isHost) {  
  tx.delete(gref);  
} else {  
  const wasPaid = paid.includes(uid);  
  tx.update(gref, {  
    players: players.filter((p) => p.uid !== uid),  
    uids: FieldValue.arrayRemove(uid),  
    paid: paid.filter((u) => u !== uid),  
    pot: Math.max(0, (Number(g.pot) || 0) - (wasPaid ? stake : 0)),  
    ...(g.teamMode === true ? { partners: [-1, -1, -1, -1], invites: [] } : {}),  
  });  
}

});
return { ok: true };
});

// ---------------------------------------------------------------------
// Fin de partie en ligne : la cagnotte va au gagnant (ou à l'équipe)
// ---------------------------------------------------------------------
exports.settleGame = onCall(opts, async (request) => {
const uid = needAuth(request);
const gameId = String((request.data && request.data.gameId) || '');
if (!gameId) throw new HttpsError('invalid-argument', 'Partie inconnue.');
const gref = db.collection('games').doc(gameId);

return db.runTransaction(async (tx) => {
const gs = await tx.get(gref);
if (!gs.exists) return { ok: false };
const g = gs.data();
if (g.settled === true) return { ok: true, already: true };
if (!(g.uids || []).includes(uid)) {
throw new HttpsError('permission-denied', 'Tu ne fais pas partie de cette partie.');
}
if (g.over !== true) {
throw new HttpsError('failed-precondition', "La partie n'est pas terminée.");
}

const max = Number(g.maxPlayers) || 2;  
const colors = colorsFor(max);  
const players = g.players || [];  

// Couleur gagnante : désignée (abandon) ou celle dont tous les pions sont arrivés.  
let wc = Number.isInteger(g.winner) && g.winner >= 0 ? g.winner : -1;  
if (wc < 0) {  
  for (const c of colors) {  
    const l = g['p' + c];  
    if (Array.isArray(l) && l.length > 0 && l.every((x) => x === 56)) {  
      wc = c;  
      break;  
    }  
  }  
}  
if (wc < 0) {  
  throw new HttpsError('failed-precondition', 'Gagnant introuvable.');  
}  

const winColors = [wc];  
if (g.teamMode === true && Array.isArray(g.partners) && g.partners[wc] >= 0) {  
  winColors.push(g.partners[wc]);  
}  
const winUids = [  
  ...new Set(  
    winColors  
      .map((c) => (players[colors.indexOf(c)] || {}).uid)  
      .filter(Boolean)  
  ),  
];  
if (winUids.length === 0) {  
  throw new HttpsError('failed-precondition', 'Gagnant introuvable.');  
}  

const pot = Number(g.pot) || 0;  
const prize = Math.floor((pot * (100 - COMMISSION_PERCENT)) / 100);  
const share = Math.floor(prize / winUids.length);  

const jp = await readJackpot(tx);  
const refs = winUids.map((u) => db.collection('users').doc(u));  
const snaps = await Promise.all(refs.map((r) => tx.get(r)));  

const fee = pot - share * winUids.length; // commission totale  
const { perWinner, kept } = applyJackpot(tx, jp, fee, winUids.length);  

snaps.forEach((s, i) => {  
  tx.set(refs[i], { balance: balanceOf(s) + share + perWinner }, { merge: true });  
});  
// Commission gardée par l'application (après la part du jackpot)  
tx.set(  
  db.collection('app').doc('stats'),  
  { commissions: FieldValue.increment(kept) },  
  { merge: true }  
);  
tx.update(gref, {  
  settled: true,  
  status: 'finished',  
  prize: share,  
  winners: winUids,  
  jackpot: perWinner * winUids.length,  
});  
return { ok: true, share, jackpot: perWinner * winUids.length };

});
});

// ---------------------------------------------------------------------
// Présentiel (plusieurs comptes sur le même téléphone)
// ---------------------------------------------------------------------
exports.startLocalGame = onCall(opts, async (request) => {
const hostUid = needAuth(request);
const stake = Number(request.data && request.data.stake);
const tokens = request.data && request.data.tokens;

if (!Number.isInteger(stake) || stake < MIN_STAKE) {
throw new HttpsError('invalid-argument', Mise minimale : ${MIN_STAKE}.);
}
if (!Array.isArray(tokens) || tokens.length < 2 || tokens.length > 4) {
throw new HttpsError('invalid-argument', 'Il faut 2 à 4 joueurs.');
}

const uids = [];
for (const t of tokens) {
try {
const decoded = await admin.auth().verifyIdToken(String(t));
uids.push(decoded.uid);
} catch (e) {
throw new HttpsError(
'unauthenticated',
'Une connexion de joueur a expiré. Reconnecte ce joueur.'
);
}
}
if (new Set(uids).size !== uids.length) {
throw new HttpsError('invalid-argument', 'Le même compte ne peut jouer qu'une fois.');
}
if (!uids.includes(hostUid)) {
throw new HttpsError('permission-denied', 'Joueur principal absent.');
}

const gref = db.collection('localGames').doc();
await db.runTransaction(async (tx) => {
const refs = uids.map((u) => db.collection('users').doc(u));
const snaps = await Promise.all(refs.map((r) => tx.get(r)));
snaps.forEach((s) => {
if (balanceOf(s) < stake) {
throw new HttpsError(
'failed-precondition',
Solde insuffisant pour la mise de ${stake}.
);
}
});
snaps.forEach((s, i) => {
tx.set(refs[i], { balance: balanceOf(s) - stake }, { merge: true });
});
tx.set(gref, {
hostUid,
uids,
stake,
pot: stake * uids.length,
settled: false,
createdAt: FieldValue.serverTimestamp(),
});
});
return { id: gref.id, pot: stake * uids.length };
});

exports.settleLocalGame = onCall(opts, async (request) => {
const uid = needAuth(request);
const id = String((request.data && request.data.id) || '');
const winnerUids = (request.data && request.data.winnerUids) || [];
if (!id || !Array.isArray(winnerUids) || winnerUids.length === 0) {
throw new HttpsError('invalid-argument', 'Données invalides.');
}
const gref = db.collection('localGames').doc(id);

return db.runTransaction(async (tx) => {
const gs = await tx.get(gref);
if (!gs.exists) throw new HttpsError('not-found', 'Partie introuvable.');
const g = gs.data();
if (g.hostUid !== uid) {
throw new HttpsError('permission-denied', 'Seul le joueur principal peut conclure.');
}
if (g.settled === true) return { ok: true, already: true };

const winners = [...new Set(winnerUids.map(String))].filter((u) => g.uids.includes(u));  
if (winners.length === 0) {  
  throw new HttpsError('invalid-argument', 'Gagnant invalide.');  
}  
const prize = Math.floor((g.pot * (100 - COMMISSION_PERCENT)) / 100);  
const share = Math.floor(prize / winners.length);  

const jp = await readJackpot(tx);  
const refs = winners.map((u) => db.collection('users').doc(u));  
const snaps = await Promise.all(refs.map((r) => tx.get(r)));  

const fee = g.pot - share * winners.length; // commission totale  
const { perWinner, kept } = applyJackpot(tx, jp, fee, winners.length);  

snaps.forEach((s, i) => {  
  tx.set(refs[i], { balance: balanceOf(s) + share + perWinner }, { merge: true });  
});  
// Commission gardée par l'application (après la part du jackpot)  
tx.set(  
  db.collection('app').doc('stats'),  
  { commissions: FieldValue.increment(kept) },  
  { merge: true }  
);  
tx.update(gref, {  
  settled: true,  
  winners,  
  prize: share,  
  jackpot: perWinner * winners.length,  
});  
return { ok: true, share, jackpot: perWinner * winners.length };

});
});
