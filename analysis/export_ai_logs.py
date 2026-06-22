#!/usr/bin/env python3
"""Export + analiza colectiei `ai_logs` (experimentul cu 2 brate) pentru lucrare.

Citeste toate rularile din Firestore si, pe fiecare brat / suprafata, calculeaza:
  - alinierea cu profilul (media scorului de potrivire al locurilor returnate),
  - rata de schimbare A->B (cate din cele N locuri ale lui B nu apar in A),
  - latenta,
  - tokenii (doar pe 'assistant' — Home nu cheama LLM),
si ruleaza testul Wilcoxon pereche pe scoruri (A=none vs B=full), grupat dupa pairId.

Scrie totul intr-un fisier SQLite (anexa lucrarii) cu tabelele `runs`, `pairs` si
`summary_by_arm`, si afiseaza un sumar in consola. Cifrele intra in sectiunea 6.4.

Rulare: vezi README.md (ai nevoie de o cheie de service account).
"""

import argparse
import math
import os
import sqlite3
import sys
from collections import defaultdict
from statistics import mean, stdev

try:
    from google.cloud import firestore
except ImportError:
    sys.exit(
        "Lipseste google-cloud-firestore. Ruleaza: pip install -r requirements.txt"
    )

try:
    from scipy.stats import wilcoxon
except ImportError:
    wilcoxon = None  # raportam, dar nu blocam exportul restului cifrelor


def item_key(it):
    """Identitatea unui loc pentru turnover: placeId daca exista, altfel numele.
    (Pe 'assistant' id-ul e gol, asa ca ne bazam pe nume.)"""
    if not isinstance(it, dict):
        return None
    pid = str(it.get("id") or "").strip()
    if pid:
        return f"id:{pid}"
    name = str(it.get("name") or "").strip().lower()
    return f"name:{name}" if name else None


def mean_score(items):
    scores = [
        float(it["score"])
        for it in items
        if isinstance(it, dict) and isinstance(it.get("score"), (int, float))
    ]
    return mean(scores) if scores else 0.0


def change_rate(items_a, items_b):
    """Fractia din cele N locuri ale lui B care nu apar in A (turnover A->B)."""
    keys_a = {item_key(it) for it in items_a if item_key(it)}
    keys_b = [item_key(it) for it in items_b if item_key(it)]
    if not keys_b:
        return None
    changed = sum(1 for k in keys_b if k not in keys_a)
    return changed / len(keys_b)


def avg(values):
    vals = [v for v in values if v is not None]
    return mean(vals) if vals else None


def rnd(x, n=4):
    return round(x, n) if isinstance(x, (int, float)) and math.isfinite(x) else None


def connect(service_account, project):
    if service_account:
        return firestore.Client.from_service_account_json(
            service_account, project=project
        )
    # altfel foloseste GOOGLE_APPLICATION_CREDENTIALS / ADC
    return firestore.Client(project=project) if project else firestore.Client()


def fetch_runs(db):
    runs = []
    for doc in db.collection("ai_logs").stream():
        d = doc.to_dict()
        items = d.get("items") if isinstance(d.get("items"), list) else []
        ts = d.get("timestamp")
        runs.append(
            {
                "surface": d.get("surface", "?"),
                "arm": d.get("arm", "?"),
                "uid": d.get("uid", ""),
                "pairId": d.get("pairId", ""),
                "items": items,
                "itemCount": d.get("itemCount", len(items)),
                "meanScore": mean_score(items),
                "latencyMs": d.get("latencyMs"),
                "promptTokens": d.get("promptTokens"),
                "responseTokens": d.get("responseTokens"),
                "query": d.get("query", ""),
                "timestamp": ts.isoformat() if hasattr(ts, "isoformat") else None,
            }
        )
    return runs


def summarize_by_arm(runs):
    groups = defaultdict(list)
    for r in runs:
        groups[(r["surface"], r["arm"])].append(r)
    rows = []
    for (surface, arm), g in sorted(groups.items()):
        rows.append(
            {
                "surface": surface,
                "arm": arm,
                "n": len(g),
                "meanScore": avg([r["meanScore"] for r in g]),
                "meanLatencyMs": avg([r["latencyMs"] for r in g]),
                "meanItems": avg([r["itemCount"] for r in g]),
                "meanPromptTokens": avg([r["promptTokens"] for r in g]),
                "meanResponseTokens": avg([r["responseTokens"] for r in g]),
            }
        )
    return rows


def build_pairs(runs):
    """Imperecheaza A(none) cu B(full) pe (surface, pairId). pairId e unic per
    rulare pereche, deci e cate cel mult un none si un full per cheie."""
    by_pair = defaultdict(lambda: {"none": [], "full": []})
    for r in runs:
        if r["arm"] in ("none", "full"):
            by_pair[(r["surface"], r["pairId"])][r["arm"]].append(r)

    pairs = []
    for (surface, pair_id), arms in by_pair.items():
        if not arms["none"] or not arms["full"]:
            continue
        a = arms["none"][0]
        b = arms["full"][0]
        pairs.append(
            {
                "surface": surface,
                "pairId": pair_id,
                "uid": b["uid"] or a["uid"],
                "query": b["query"] or a["query"],
                "scoreNone": a["meanScore"],
                "scoreFull": b["meanScore"],
                "delta": b["meanScore"] - a["meanScore"],
                "changeRate": change_rate(a["items"], b["items"]),
                "latencyNone": a["latencyMs"],
                "latencyFull": b["latencyMs"],
                "promptTokensFull": b["promptTokens"],
                "responseTokensFull": b["responseTokens"],
            }
        )
    return pairs


def paired_stats(pairs):
    """Pe fiecare suprafata: Δscor mediu, sd, 95% CI, %B>A, rata de schimbare
    medie si testul Wilcoxon pereche."""
    out = {}
    surfaces = sorted({p["surface"] for p in pairs})
    for s in surfaces:
        ps = [p for p in pairs if p["surface"] == s]
        deltas = [p["delta"] for p in ps]
        none_scores = [p["scoreNone"] for p in ps]
        full_scores = [p["scoreFull"] for p in ps]
        n = len(ps)
        m = mean(deltas) if deltas else 0.0
        sd = stdev(deltas) if n > 1 else 0.0
        se = sd / math.sqrt(n) if n else 0.0
        wins = sum(1 for d in deltas if d > 0)
        crs = [p["changeRate"] for p in ps if p["changeRate"] is not None]

        w_stat = w_p = None
        if wilcoxon is not None and n >= 1 and any(d != 0 for d in deltas):
            try:
                res = wilcoxon(full_scores, none_scores)
                w_stat, w_p = float(res.statistic), float(res.pvalue)
            except ValueError:
                pass  # toate diferentele nule sau prea putine perechi

        out[s] = {
            "nPairs": n,
            "deltaMean": m,
            "deltaSd": sd,
            "ci95Low": m - 1.96 * se,
            "ci95High": m + 1.96 * se,
            "winsBoverA": wins,
            "changeRateMean": mean(crs) if crs else None,
            "wilcoxonStat": w_stat,
            "wilcoxonP": w_p,
        }
    return out


def write_sqlite(path, runs, by_arm, pairs):
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    cur = con.cursor()
    cur.execute(
        "CREATE TABLE runs (timestamp TEXT, surface TEXT, arm TEXT, uid TEXT, "
        "pairId TEXT, itemCount INTEGER, meanScore REAL, latencyMs INTEGER, "
        "promptTokens INTEGER, responseTokens INTEGER, query TEXT)"
    )
    cur.execute(
        "CREATE TABLE pairs (surface TEXT, pairId TEXT, uid TEXT, query TEXT, "
        "scoreNone REAL, scoreFull REAL, delta REAL, changeRate REAL, "
        "latencyNone INTEGER, latencyFull INTEGER, promptTokensFull INTEGER, "
        "responseTokensFull INTEGER)"
    )
    cur.execute(
        "CREATE TABLE summary_by_arm (surface TEXT, arm TEXT, n INTEGER, "
        "meanScore REAL, meanLatencyMs REAL, meanItems REAL, "
        "meanPromptTokens REAL, meanResponseTokens REAL)"
    )
    cur.executemany(
        "INSERT INTO runs VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        [
            (
                r["timestamp"], r["surface"], r["arm"], r["uid"], r["pairId"],
                r["itemCount"], rnd(r["meanScore"]), r["latencyMs"],
                r["promptTokens"], r["responseTokens"], r["query"],
            )
            for r in sorted(runs, key=lambda r: r["timestamp"] or "")
        ],
    )
    cur.executemany(
        "INSERT INTO pairs VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        [
            (
                p["surface"], p["pairId"], p["uid"], p["query"],
                rnd(p["scoreNone"]), rnd(p["scoreFull"]), rnd(p["delta"]),
                rnd(p["changeRate"]), p["latencyNone"], p["latencyFull"],
                p["promptTokensFull"], p["responseTokensFull"],
            )
            for p in pairs
        ],
    )
    cur.executemany(
        "INSERT INTO summary_by_arm VALUES (?,?,?,?,?,?,?,?)",
        [
            (
                row["surface"], row["arm"], row["n"], rnd(row["meanScore"]),
                rnd(row["meanLatencyMs"], 0), rnd(row["meanItems"], 2),
                rnd(row["meanPromptTokens"], 1), rnd(row["meanResponseTokens"], 1),
            )
            for row in by_arm
        ],
    )
    con.commit()
    con.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--service-account",
        help="cale catre cheia JSON de service account (altfel GOOGLE_APPLICATION_CREDENTIALS / ADC)",
    )
    parser.add_argument("--project", help="ID-ul proiectului Firebase (optional)")
    parser.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "ai_logs_export.sqlite"),
        help="fisierul SQLite de iesire",
    )
    args = parser.parse_args()

    db = connect(args.service_account, args.project)
    runs = fetch_runs(db)
    if not runs:
        print("ai_logs e gol — rulează experimentul mai întâi.")
        return

    by_arm = summarize_by_arm(runs)
    pairs = build_pairs(runs)
    stats = paired_stats(pairs)

    print(f"\n# ai_logs: {len(runs)} rulări\n")
    print("## Pe suprafață și braț")
    print(
        f"{'surface':<10} {'arm':<6} {'n':<5} {'score':<8} {'latency':<9} "
        f"{'items':<6} {'tokIn':<7} {'tokOut':<7}"
    )
    for row in by_arm:
        print(
            f"{row['surface']:<10} {row['arm']:<6} {row['n']:<5} "
            f"{str(rnd(row['meanScore'])):<8} {str(rnd(row['meanLatencyMs'], 0)):<9} "
            f"{str(rnd(row['meanItems'], 2)):<6} "
            f"{str(rnd(row['meanPromptTokens'], 1)):<7} "
            f"{str(rnd(row['meanResponseTokens'], 1)):<7}"
        )

    print("\n## Comparație pereche (Δ = B[full] − A[none])")
    if wilcoxon is None:
        print("  (scipy lipsește — testul Wilcoxon a fost sărit; pip install scipy)")
    for s, st in sorted(stats.items()):
        n = st["nPairs"]
        print(f"\nsurface = {s}")
        print(f"  perechi:         {n}")
        print(f"  Δscor mediu:     {rnd(st['deltaMean'])}")
        print(f"  sd(Δ):           {rnd(st['deltaSd'])}")
        print(f"  95% CI (≈):      [{rnd(st['ci95Low'])}, {rnd(st['ci95High'])}]")
        win_pct = rnd(100 * st["winsBoverA"] / n, 1) if n else None
        print(f"  B > A:           {st['winsBoverA']}/{n} ({win_pct}%)")
        cr = st["changeRateMean"]
        print(
            f"  rată schimbare:  {rnd(cr)}"
            + (f" (~{rnd(100 * cr, 1)}% din N)" if cr is not None else "")
        )
        if st["wilcoxonStat"] is not None:
            print(
                f"  Wilcoxon:        W={rnd(st['wilcoxonStat'], 3)}, "
                f"p={rnd(st['wilcoxonP'], 4)}"
            )
        else:
            print("  Wilcoxon:        n/a (diferențe nule sau prea puține perechi)")

    write_sqlite(args.out, runs, by_arm, pairs)
    print(
        f"\nSQLite scris: {args.out} "
        f"(runs={len(runs)}, pairs={len(pairs)}, summary_by_arm={len(by_arm)})\n"
    )


if __name__ == "__main__":
    main()
