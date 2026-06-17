'use strict';

// Export + analiza colectiei `ai_logs` (experimentul cu 2 brate) pentru lucrare.
//
// Citeste toate rularile, agrega scorul de potrivire si latenta pe brat/suprafata
// si face comparatia pereche A(none) vs B(full) dupa pairId. Scrie doua CSV-uri:
//   ai_logs_runs.csv  — un rand per rulare
//   ai_logs_pairs.csv — un rand per pereche (acelasi pairId+suprafata)
//
// Rulare: vezi README.md (ai nevoie de o cheie de service account).

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();

const mean = (a) => (a.length ? a.reduce((s, v) => s + v, 0) / a.length : 0);
const sd = (a) => {
  if (a.length < 2) return 0;
  const m = mean(a);
  return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1));
};
const round = (x, n = 4) => (Number.isFinite(x) ? Number(x.toFixed(n)) : null);

// scorul unei rulari = media scorurilor de potrivire ale locurilor returnate
function docMeanScore(d) {
  const items = Array.isArray(d.items) ? d.items : [];
  return mean(items.map((i) => (i && typeof i.score === 'number' ? i.score : 0)));
}

function csvField(v) {
  if (v === null || v === undefined) return '';
  return `"${String(v).replace(/"/g, '""')}"`;
}
const csvRow = (arr) => arr.map(csvField).join(',') + '\n';

async function main() {
  const snap = await db.collection('ai_logs').get();
  if (snap.empty) {
    console.log('ai_logs e gol — rulează experimentul mai întâi.');
    return;
  }

  const runs = snap.docs.map((doc) => {
    const d = doc.data();
    const ts = d.timestamp && d.timestamp.toDate ? d.timestamp.toDate() : null;
    return {
      surface: d.surface || '?',
      arm: d.arm || '?',
      uid: d.uid || '',
      pairId: d.pairId || '',
      itemCount:
        typeof d.itemCount === 'number'
          ? d.itemCount
          : Array.isArray(d.items)
            ? d.items.length
            : 0,
      meanScore: docMeanScore(d),
      latencyMs: typeof d.latencyMs === 'number' ? d.latencyMs : null,
      query: d.query || '',
      timestamp: ts,
    };
  });

  // ---- agregat pe (suprafata, brat) -------------------------------------
  const groups = {};
  for (const r of runs) (groups[`${r.surface}|${r.arm}`] ||= []).push(r);

  console.log(`\n# ai_logs: ${runs.length} rulări\n`);
  console.log('## Pe suprafață și braț');
  console.log('surface    arm    n      meanScore   meanLatency   meanItems');
  for (const k of Object.keys(groups).sort()) {
    const g = groups[k];
    const [surface, arm] = k.split('|');
    const lat = g.filter((r) => r.latencyMs != null).map((r) => r.latencyMs);
    console.log(
      `${surface.padEnd(10)} ${arm.padEnd(6)} ${String(g.length).padEnd(6)} ` +
        `${String(round(mean(g.map((r) => r.meanScore)))).padEnd(11)} ` +
        `${String(round(mean(lat), 0)).padEnd(13)} ` +
        `${round(mean(g.map((r) => r.itemCount)), 2)}`,
    );
  }

  // ---- comparatie pereche pe (suprafata, pairId) ------------------------
  const byPair = {};
  for (const r of runs) {
    const k = `${r.surface}|${r.pairId}`;
    (byPair[k] ||= { none: [], full: [] })[r.arm]?.push(r);
  }
  const pairs = [];
  for (const k of Object.keys(byPair)) {
    const p = byPair[k];
    if (!p.none.length || !p.full.length) continue;
    const [surface, pairId] = k.split('|');
    const latOf = (rs) =>
      mean(rs.filter((r) => r.latencyMs != null).map((r) => r.latencyMs));
    const scoreNone = mean(p.none.map((r) => r.meanScore));
    const scoreFull = mean(p.full.map((r) => r.meanScore));
    pairs.push({
      surface,
      pairId,
      uid: (p.full[0] || p.none[0]).uid,
      scoreNone,
      scoreFull,
      delta: scoreFull - scoreNone,
      latNone: latOf(p.none),
      latFull: latOf(p.full),
    });
  }

  console.log('\n## Comparație pereche (Δ = B[full] − A[none])');
  for (const s of [...new Set(pairs.map((p) => p.surface))].sort()) {
    const ps = pairs.filter((p) => p.surface === s);
    const deltas = ps.map((p) => p.delta);
    const m = mean(deltas);
    const se = ps.length ? sd(deltas) / Math.sqrt(ps.length) : 0;
    const wins = ps.filter((p) => p.delta > 0).length;
    console.log(`\nsurface = ${s}`);
    console.log(`  perechi:      ${ps.length}`);
    console.log(`  Δscor mediu:  ${round(m)}`);
    console.log(`  sd(Δ):        ${round(sd(deltas))}`);
    console.log(`  95% CI (≈):   [${round(m - 1.96 * se)}, ${round(m + 1.96 * se)}]`);
    console.log(`  t:            ${round(se ? m / se : 0, 3)} (df=${ps.length - 1})`);
    console.log(`  B > A:        ${wins}/${ps.length} (${round((100 * wins) / ps.length, 1)}%)`);
  }

  // ---- CSV --------------------------------------------------------------
  let runsCsv = csvRow([
    'timestamp', 'surface', 'arm', 'uid', 'pairId',
    'itemCount', 'meanScore', 'latencyMs', 'query',
  ]);
  for (const r of runs.sort(
    (a, b) => (a.timestamp?.getTime() || 0) - (b.timestamp?.getTime() || 0),
  )) {
    runsCsv += csvRow([
      r.timestamp ? r.timestamp.toISOString() : '',
      r.surface, r.arm, r.uid, r.pairId,
      r.itemCount, round(r.meanScore), r.latencyMs, r.query,
    ]);
  }
  fs.writeFileSync(path.join(__dirname, 'ai_logs_runs.csv'), runsCsv);

  let pairsCsv = csvRow([
    'surface', 'pairId', 'uid',
    'scoreNone', 'scoreFull', 'delta', 'latencyNone', 'latencyFull',
  ]);
  for (const p of pairs) {
    pairsCsv += csvRow([
      p.surface, p.pairId, p.uid,
      round(p.scoreNone), round(p.scoreFull), round(p.delta),
      round(p.latNone, 0), round(p.latFull, 0),
    ]);
  }
  fs.writeFileSync(path.join(__dirname, 'ai_logs_pairs.csv'), pairsCsv);

  console.log(
    `\nCSV scrise: analysis/ai_logs_runs.csv (${runs.length} rânduri), ` +
      `analysis/ai_logs_pairs.csv (${pairs.length} perechi)\n`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
