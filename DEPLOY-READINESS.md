# Preparare il rilascio V1.0

Stato dell’11 novembre 2026. Il sito pubblico è ancora l’anteprima 2.0.2. La cartella pubblica locale e i pacchetti sono candidati successivi e non attestano un nuovo deploy.

## Gate ancora aperti

1. Google OAuth sul progetto Supabase corretto e login/logout reali. Il client non richiede SMTP/SMS/Turnstile per il percorso Google; configurare solo i percorsi opzionali realmente offerti.
2. Allowlist dell’Admin verificato, enrollment TOTP e controllo della sessione e della scadenza di 15 minuti. L’Edge Admin v2 è distribuita ma non sostituisce questo test.
3. Distribuzione delle funzioni necessarie, segreti nelle impostazioni dei provider, limiti e origini corrette. Non impostare valori segreti nel frontend o nel repository.
4. Prove con account Host/Sportivo separati: persistenza, invito privato, capienza concorrente, richieste, ammissioni, espulsione/riammissione, modifiche e conclusione.
5. Cron e vere esecuzioni di storico, promemoria e push. Esportazione e cancellazione su richiesta devono funzionare; la durata automatica degli account ha una migrazione separata da approvare ed è disattivata.
6. Prima degli acquisti: ambiente Stripe test autorizzato, prezzo annuale previsto e stato pagato verificato, webhook, portale, rinnovo/annullamento, dati fiscali/contrattuali pertinenti. Non usare un acquisto live per provare l’integrazione.
7. Verifica finale delle informative aggiornate, accordi con i responsabili, trasferimenti e conservazione delle pratiche. I testi non sono una certificazione legale. Backup dati e ripristino completo ancora da provare.
8. Solo dopo i controlli necessari abilitare i flag appropriati, distribuire una versione coordinata e provare online i flussi A-G. Le funzioni opzionali non disponibili restano spente e non devono mostrare falsi successi.

## Pacchetto e controlli

Da una copia completa dei sorgenti:

```sh
cp config.example.js config.js
bash scripts/package-release.sh
```

La configurazione reale va predisposta prima del rilascio e non va sostituita alla cieca se esiste già. Il workflow CI crea solo una configurazione di preview e non pubblica. I test Node, il driver PostgreSQL locale obbligatorio e i controlli Deno sono descritti nel README e nel workflow.

Gli archivi escludono `.env`, `.dev.vars`, `.npmrc`, `node_modules`, `.wrangler` e Git. Prima di usarli confrontare sorgenti, copie ed entrypoint, non soltanto l’integrità dello ZIP. Il pacchetto locale include la documentazione, le prove e la guida PDF; quello statico contiene i file del sito.

## Pubblicazione e verifica

Il progetto Cloudflare già autorizzato usa asset statici da `TROVAT1O-Cloudflare-Deploy/public/` e il dominio gratuito esistente. Dopo aver superato i gate:

```sh
cd TROVAT1O-Cloudflare-Deploy
npm ci --ignore-scripts --no-audit --no-fund
npx wrangler deploy
```

Non confondere `deploy --dry-run` con pubblicazione e un deploy riuscito con accesso Google o sincronizzazione funzionanti. Registrare versione Cloudflare, commit, configurazione senza segreti, data ed esito. Controllare asset, console, sessioni, autorizzazioni e prove reali sullo stesso URL pubblico.

## Recupero e costi

Conservare la versione hosting precedente e un backup dati verificato. Disattivare i job di eliminazione prima di interventi di rollback; una cancellazione fisica non si annulla cambiando configurazione o ritirando una migrazione. Le tredici migrazioni registrate non sono un backup dei dati e non sono state riprodotte da zero.

Non acquistare servizi o aumentare piani automaticamente. Verificare le quote e la continuità dei servizi Free correnti; in caso di crescita il titolare decide un eventuale incremento. Il dominio comprato non è necessario per il primo collaudo pubblico; collegarlo successivamente richiede aggiornare origine, redirect, link, metadata, CORS e informative.
