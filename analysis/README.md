# Analiză `ai_logs` — experiment 2 brațe

Script de export + analiză pentru colecția Firestore `ai_logs` (scrisă de Home și
de AI Assistant). Calculează scorul de potrivire cu profilul și latența pe fiecare
braț/suprafață și face comparația pereche **A (none)** vs **B (full)** după `pairId`.

## Ce produce

- Sumar în consolă: agregat pe `(surface, arm)` + comparație pereche (Δ scor, sd,
  95% CI aproximativ, statistica `t`, procent de perechi cu B > A).
- `ai_logs_runs.csv` — un rând per rulare (inclusiv `itemCount`, ca să verifici
  empiric invariantul „același N").
- `ai_logs_pairs.csv` — un rând per pereche: `scoreNone`, `scoreFull`, `delta`,
  latențe.

## Cum rulezi

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
