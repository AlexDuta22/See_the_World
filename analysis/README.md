# Analiză `ai_logs` — experiment 2 brațe

Script de export + analiză pentru colecția Firestore `ai_logs` (scrisă de Home și
de AI Assistant). Calculează scorul de potrivire cu profilul și latența pe fiecare
braț/suprafață și face comparația pereche **A (none)** vs **B (full)** după `pairId`.

Sunt două variante echivalente la bază; cea Python e cea din protocol (secțiunea 8).

## `export_ai_logs.py` (Python — varianta din protocol)

Produce cifrele pentru secțiunea 6.4: alinierea per braț, **rata de schimbare** A→B
(câte din cele N locuri ale lui B nu apar în A), latența, **tokenii** (doar pe
`assistant`) și **testul Wilcoxon** pereche pe scoruri. Exportă un fișier **SQLite**
(`ai_logs_export.sqlite`, anexa lucrării) cu tabelele `runs`, `pairs` și
`summary_by_arm`, plus un sumar în consolă.

```powershell
cd analysis
pip install -r requirements.txt
$env:GOOGLE_APPLICATION_CREDENTIALS = "$PWD\serviceAccount.json"
python export_ai_logs.py
# sau, fără variabilă de mediu:
python export_ai_logs.py --service-account serviceAccount.json --project <PROJECT_ID>
```

## `analyze_ai_logs.js` (Node.js — variantă rapidă, doar CSV)

- Sumar în consolă: agregat pe `(surface, arm)` + comparație pereche (Δ scor, sd,
  95% CI aproximativ, statistica `t`, procent de perechi cu B > A).
- `ai_logs_runs.csv` — un rând per rulare (inclusiv `itemCount`, ca să verifici
  empiric invariantul „același N").
- `ai_logs_pairs.csv` — un rând per pereche: `scoreNone`, `scoreFull`, `delta`,
  latențe.

## Cum rulezi (Node.js)

1. **Cheie de service account** (acces de citire la Firestore, ocolește regulile):
   Firebase Console → ⚙️ Project settings → *Service accounts* →
   *Generate new private key*. Salveaz-o ca `analysis/serviceAccount.json`
   (e deja în `.gitignore`, nu ajunge în repo).

2. **Instalează dependențele:**
   ```powershell
   cd analysis
   npm install
   ```

3. **Indică cheia și rulează** (PowerShell):
   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "$PWD\serviceAccount.json"
   npm run analyze
   ```

## Note

- `meanScore` per rulare = media `score`-urilor locurilor returnate (cât de bine se
  potrivește setul cu profilul de gusturi al userului). Așteptarea H1: mai mare pe
  brațul `full`.
- O pereche există doar dacă același `pairId` (+ aceeași suprafață) are și `none`, și
  `full`. Cel mai curat le obții cu butonul **„Rulează ambele brațe"** din Home
  (același pool, același `pairId`).
- `p`-ul: caută `t` cu `df = nperechi − 1` în tabelul distribuției t. Pentru `n`
  mare, CI-ul normal afișat e suficient.
