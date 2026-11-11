# Notifiche: consegna e promemoria

Il codice è pronto per la configurazione; **nessuna push reale è stata inviata e nessun job è stato attivato**. `pushReady` e `PUSH_ENABLED` restano disabilitati finché le prove di integrazione non sono completate.

## Componenti

- `notifications.sql`: avvisi nell'app, preferenze, sottoscrizioni del dispositivo e coda; la coda da sola non invia messaggi.
- `push-dispatch.sql`: nuova API di consegna con lease di tre minuti, massimo cinque tentativi, attese crescenti e controllo aggiornato del consenso. Sostituisce i callback precedenti senza token di consegna.
- `functions/push-dispatch/index.ts` e `_shared/push-core.ts`: Web Push reale con `web-push@4.0.0`, crittografia/VAPID e invio HTTPS controllato.
- Client: registrazione serializzata della sottoscrizione, revoca sul dispositivo al logout/cambio account, protezione dalle risposte tardive. Un indicatore tecnico dell'account del dispositivo evita di riutilizzare involontariamente la sottoscrizione di un altro account; non concede autorizzazioni.

## Protezioni

La funzione è riservata al job tramite un segreto distinto da qualsiasi token utente. Accetta solo un piccolo oggetto JSON vuoto, una richiesta POST senza origine browser e un lotto massimo di dieci elementi su due canali di invio. Non accetta destinatari, endpoint, payload o URL passati dal chiamante.

Gli endpoint di sottoscrizione sono dati non attendibili. La consegna permette esclusivamente gli host ufficiali FCM, Firefox e Apple definiti nel codice; rifiuta indirizzi locali, porte personalizzate, credenziali nell'URL, query e host somiglianti. L'invio usa `redirect: 'error'` e timeout di otto secondi. Altri provider di browser richiedono una verifica e un'estensione esplicita dell'elenco, senza accettare URL arbitrari.

Consenso, proprietario, età dell'avviso, stato dell'evento e lease vengono ricontrollati prima dell'invio e dopo la preparazione crittografica. Avvisi più vecchi di 24 ore, promemoria di partite già iniziate e dati non più accessibili non vengono inviati. Il messaggio sullo schermo bloccato contiene solo un testo generico e il collegamento alle notifiche; nessun numero, nome di partecipante, luogo privato o token d'invito.

Ogni callback deve corrispondere al lease corrente. Un errore HTTP 404/410 invalida solo la stessa sottoscrizione e lo stesso contenuto crittografico presi in carico: una sottoscrizione rinnovata durante l'invio non viene cancellata. Errori temporanei sono ritentati; i messaggi di errore conservati sono codici generici. Il codice non registra endpoint, chiavi del dispositivo, payload privati o segreti.

## Attivazione da completare

1. Applicare e verificare schema notifiche, retention e `push-dispatch.sql` nel progetto corretto.
2. Generare una coppia VAPID e un segreto del job; conservare i valori privati solo nei secrets Supabase. `VAPID_PUBLIC_KEY` è la sola chiave da pubblicare nel frontend.
3. Configurare `PUSH_ENABLED`, `PUSH_CRON_SECRET`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` e `APP_ORIGIN`. Il contatto VAPID può essere l'indirizzo di assistenza dell'app. La funzione usa le chiavi Supabase server standard; nessuna nel frontend.
4. Distribuire `push-dispatch` senza controllo JWT del gateway: autentica il job con il proprio segreto, non con un utente finale. Il client non può invocarla per inviare notifiche.
5. Rendere disponibili `pg_cron`, `pg_net` e Vault sul piano gratuito effettivamente in uso. Salvare in Vault il segreto `trovat1o_push_cron_secret`, corrispondente a quello della funzione. Non scrivere il valore in migrazioni, query condivise o comandi Cron.
6. Configurare il job tramite `configure_push_dispatch_cron(true, project_ref)`. Crea i promemoria e chiama il dispatcher ogni cinque minuti. Il comando Cron contiene soltanto il riferimento a Vault; non il segreto. La variante `false` disattiva solo il job dell'app. Questa guida non implica che il job sia stato creato.
7. Provare sul dispositivo HTTPS: consenso, avviso, promemoria, rinuncia, account diversi, sottoscrizione scaduta e browser supportati. Su iPhone verificare il contesto di installazione e le capacità del browser effettivo.
8. Solo dopo queste prove attivare `pushReady` e distribuire la configurazione pubblica. I permessi di posizione sono separati dalle notifiche; non sono necessari per cercare manualmente una partita.

## Evidenze e limiti

Sono presenti 17 scenari del gestore effettivo con trasporti controllati, 10 scenari del ciclo client e una regressione SQL su PostgreSQL locale. Il controllo TypeScript con dipendenze fissate è separato. Verificano struttura, firme di consegna, consenso e protezioni; non dimostrano una consegna reale, la programmazione Cron in cloud o il comportamento su tutti i dispositivi. I risultati del checkpoint corrente sono registrati in `V1-STATUS.md`.

I servizi restano soggetti alle quote del piano Free: gratuità iniziale non equivale a capacità illimitata. L'abilitazione di estensioni, chiavi, funzioni e job viene verificata prima del rilascio; nessun acquisto automatico.
