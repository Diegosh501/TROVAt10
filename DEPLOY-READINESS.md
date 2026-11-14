# Preparare il rilascio V1.0

Versioni, criteri e scenari autorevoli: [V1-STATUS.md](V1-STATUS.md). Storico: [RELEASES.md](RELEASES.md). Distinguere frontend distribuito, sorgenti e funzioni server: un merge non aggiorna il sito automaticamente.

## Punto di partenza del 14 novembre 2026

Collaudo cloud-test.11 da rc.8; principale rc.1, anteprima con dati locali. PR #1 e sorgenti rc.10 sono integrati nel ramo principale, senza deploy frontend. Supabase `nrixslotansgrtrosaof` conserva 17 migrazioni, due account Google e quattro eventi. Funzioni: admin-console v4, host-contact v1, push-dispatch v1 con blocco false nel codice. Invio, pianificazione e purge sono spenti.

Auth del collaudo è ora allineato: solo Google abilitato, Email e altri provider non offerti disabilitati; nuove registrazioni Google consentite. Scelta salvata dopo la delega del titolare, preflight reale riuscito e nuovo accesso Google con profilo/storico persistenti verificato. Il percorso email del Master rimane da completare.

## Gate ancora aperti

1. Completare email/password, SMTP personalizzato, conferma, recupero e antiabuso previsti dal Master R3. Nel frattempo mantenere chiusi sul server i percorsi non offerti nel collaudo. La disattivazione temporanea non completa il requisito email V1.
2. Completare personalmente TOTP dell’Admin già assegnato e collaudare metriche e operazioni reali. Il titolare ha rinviato il passaggio; non creare o simulare un suo fattore.
3. Applicare le sole migrazioni pendenti con conferma tecnica valida. Assistenza richiede anche Turnstile reale e prova pratica. Non ripetere il ciclo di conferme scadute o aggirarlo.
4. Chiudere gli scenari su altro dispositivo, contesa dell’ultimo posto fra due Sportivi Google distinti, errori dei servizi, automatismi e recupero gestito.
5. Verificare job reali di storico e comunicazioni, consenso, revoca e pulizia. Il dispatcher spento non prova consegna. Account lifecycle, purge e cancellazione revisionata rimangono disattivati.
6. Verificare backup/ripristino del progetto gestito: Auth, Storage e configurazione hanno prove distinte dal recupero PostgreSQL sintetico.
7. Adeguare informative, conservazione e accordi ai servizi effettivi. Premium e pagamenti reali restano spenti.
8. Superare i criteri V1, rilasciare sul principale e collaudarlo sullo stesso URL. Porting gratuito e indicizzabilità pubblica vanno coordinati con questa fase; il collaudo mantiene noindex.

## Configurazione e preflight

Creare una preview solo se manca la configurazione locale:

```sh
if [ ! -f config.js ]; then
  cp config.example.js config.js
fi
```

Per la release cloud predisporre e revisionare la configurazione pubblica pertinente; il default dei sorgenti è preview.

```sh
bash scripts/package-release.sh
node scripts/verify-auth-settings.mjs TROVAT1O-Cloudflare-Deploy/public/config.js output/audit/auth-provider-preflight.json
```

Il preflight esegue solo GET alle impostazioni pubbliche del progetto corretto con chiave publishable/anon. Rifiuta chiavi server, altri progetti, redirect e provider non offerti; non crea utenti, non accede e non invia email. Discrepanza: exit 1. Preview: exit 2, esito non verificato. Non dimostra SMTP, CAPTCHA, consegna email, login Google o MFA.

La CI esegue test sorgenti, PostgreSQL locale/nativo, Deno con lock e packaging. Wrangler in CI è solo dry-run. Consultare il run del commit effettivo; un verde precedente non verifica nuovi cambi.

## Pubblicazione e controllo HTTPS

Solo dopo i gate:

```sh
cd TROVAT1O-Cloudflare-Deploy
npm ci --ignore-scripts --no-audit --no-fund
npx wrangler deploy
```

Esporre esclusivamente `public/`. Root, checkpoint, dump, test e pacchetti restano privati. Tornati alla root:

```sh
node scripts/verify-live.mjs https://trovato.diegolucentedesign.workers.dev/ output/audit/live-verification.json TROVAT1O-Cloudflare-Deploy/public
```

Per un’anteprima usare la sua URL e directory effettivamente caricata. Il verificatore asset confronta hash, intestazioni e percorsi riservati; Auth e flussi reali restano prove separate. Registrare Version ID, release, commit, origini, migrazioni e risultati post-deploy.

## Recupero e costi

Conservare versione hosting precedente e backup verificato. Fermare i job che modificano dati prima del recupero. Un rollback frontend non ripristina righe cancellate. [Procedura backup](BACKUP-RESTORE-SETUP.md).

Nessun acquisto o aumento di piano automatico. Il vincolo è costo zero entro le quote effettive. Un dominio comprato è facoltativo: richiederà aggiornare origine, redirect, link, metadata, CORS e informative.
