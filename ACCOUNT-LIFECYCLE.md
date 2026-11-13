# Stato autorevole — 13 novembre 2026

Questa sezione prevale sui checkpoint storici sottostanti.

- Pubblico aggiornato: **1.0.0-rc.1**, anteprima interattiva, https://trovato.diegolucentedesign.workers.dev/ . Versione Cloudflare `959a4c70-a070-4ee8-aa21-b306260b3165`, pubblicata l’11 novembre. Non è ancora V1.0 cloud.
- Nuova verifica HTTPS del 13 novembre: **17/17 asset identici**, intestazioni corrette, **5/5 percorsi riservati negati**. Ricevuta: `output/audit/2026-11-13/live-verification.json`.
- Supabase corretto `nrixslotansgrtrosaof`: **15 migrazioni**. Ciclo account applicato e **enabled=false, purge_enabled=false**. Nessun job installato, nessuna cancellazione attiva. Utenti/eventi reali ancora zero.
- Nuovo modulo `supabase/session-security.sql` applicato: sessione Auth esatta e viva, account valido, **10 policy RLS restrittive** con USING/WITH CHECK. Non annulla richieste già in corso o snapshot MVCC precedenti.
- Test locale aggiornato: **14 moduli SQL / 13 regressioni** con rollback, compresa session-security. Due controlli negativi rilevano un bypass intenzionale dei gate/RLS. Auth e JWT sono fixture, non login reali. Ultima esecuzione Node: **22/22**.
- Il tentativo Google del 13 novembre, dopo la conferma «Impostazione modificata», è ancora negato dalla regola salvata/gestita del browser. Nessun aggiramento. Provider Google non completato; frontend mantiene tutti i Ready=false.
- Master aggiornato: `output/handoff/OBIETTIVO-MASTER-R3.md`, **25 criteri V1 e 11 scenari reali** A–I,L,M. Nessuno scenario integralmente collaudato online: **0/11**. V2=PUBLIC BETA; V3=STABLE; V4=COMPLETE PLATFORM. Le vecchie barre 0/7 descrivono il precedente obiettivo.
- Cancellazione volontaria ancora mancante: audit `output/audit/2026-11-11/erasure-readiness-review.md`. Non equiparare scadenza Free a diritto di cancellazione. Conservazione Billing/dipendenze da risolvere prima del purge.
- Prossime priorità: Google–Supabase sul progetto corretto; Admin reale TOTP; due identità Host/Sportivo e persistenza; export/erasure/supporto e retention server; ripristino; poi collaudo V1. Push e apertura beta V2 successive. Premium/Stripe predisposti ma pagamenti spenti, tutti iniziano Free.
- Nessun nuovo costo, SMS, acquisto o account Admin creato. Il dominio acquistato resta futuro.

---

## Documento e checkpoint precedenti

# Durata degli account Free

Decisione del titolare dell’11 novembre 2026: il periodo Free parte dalla **creazione del primo match**, dura sette giorni ed esclude gli account con Premium verificato attivo. Non coincide con lo storico dei match, che ha un termine distinto dalla conclusione o dall’annullamento.

## Stato effettivo

Il codice è in `supabase/account-lifecycle.sql`, con interfaccia dietro `accountLifecycleReady: false`. Le impostazioni server iniziano con `enabled=false` e `purge_enabled=false`. **Non è attivo online.** Il tentativo di applicare la migrazione con il connettore l’11 novembre ha richiesto una conferma operativa poi scaduta: una lettura successiva ha verificato che la tabella non esiste e le migrazioni remote restano tredici. Non riprovare automaticamente per ottenere approvazioni ripetute.

La funzione Admin aggiornata a versione 2 è stata invece distribuita, senza attivare questo modulo, Google o pagamenti. Nessun account reale è stato cancellato e nessun nuovo costo è stato autorizzato.

## Regole implementate

- Un trigger sul primo inserimento effettivo di un evento registra l’ora reale del server dopo aver acquisito il blocco sulla conferma delle condizioni, non l’ora di inizio della transazione. L’orario del match, l’orologio del dispositivo e i dati modificabili del profilo non possono scegliere questa data. Se la creazione viene annullata dalla transazione, anche il conteggio viene annullato.
- Partecipazione, cambio ruolo, annullamento e rimozione di un match non fanno ripartire il periodo. Uno Sportivo che non ha mai creato un evento non avvia il conteggio.
- Prima di creare un evento, quando la regola è attiva, viene presentata una conferma non preselezionata con il collegamento alle condizioni. La conferma viene registrata per il solo account chiamante con una sessione ancora valida; non è un consenso pubblicitario e non può attribuire Premium.
- Alla scadenza, il server impedisce nuove creazioni e nuove richieste. Gestione dei match già esistenti e ritiro della partecipazione restano possibili. L’account resta consultabile fino alla cancellazione fisica, così può chiedere assistenza o esportare i dati.
- Un avviso nell’account all’inizio spiega la regola. Alla scadenza il worker registra un altro avviso: la cancellazione fisica non avviene prima di ulteriori 48 ore. Gli avvisi di servizio non dipendono dalle preferenze sugli aggiornamenti di attività; non è promessa un’email o una push consegnata se il relativo servizio non è attivo.
- Premium attivo e amministratori presenti nell’allowlist sono protetti. Un token o un metadata fornito dal browser non conferma un pagamento. Dopo la cessazione del Premium vengono rivalutati il termine originario e un nuovo avviso, se il worker aveva osservato e azzerato il precedente.

## Cancellazione prudente

`run_account_retention(25)` usa una transazione, batch limitati e blocchi sugli account, sui profili e sui piani. Non effettua una verifica SQL seguita da una cancellazione HTTP separata, che potrebbe correre contro un pagamento. Quando tutte le condizioni sono soddisfatte, elimina la riga Auth: profilo e sessioni vengono rimossi dalle relazioni a cascata. Le operazioni sensibili continuano a controllare l’esistenza dell’utente/sessione anche con un vecchio JWT.

La cancellazione viene rinviata se esistono match ancora intestati all’utente, partecipazioni approvate/in attesa a eventi non conclusi, contributi di posizione ancora collegati, segnalazioni, assistenza aperta, audit di assistenza o una sospensione di conservazione. Sono protetti anche piano mancante, oggetti Storage dell’utente e qualsiasi collegamento Billing, incluse operazioni pendenti. La riduzione dei dati finanziari dopo la loro conservazione obbligatoria è una procedura distinta: questo worker non la indovina né cancella il cliente Stripe.

La presenza di una nuova dipendenza sconosciuta, anche a cascata e anche transitiva, ferma il purge fisico. Non vengono eliminati report per liberare forzatamente un account. Il rinnovo di una sospensione di conservazione acquisisce gli stessi blocchi sul record Auth e sul profilo del worker, prima di aggiornare la sospensione; non può dichiararsi riuscito per un account già eliminato. Un vincolo o un conflitto di blocchi trattiene la riga e permette una riprova. Le righe trattenute passano a una verifica successiva: non occupano indefinitamente i primi posti del batch bloccando gli altri account.

Il ciclo di conservazione degli eventi deve terminare prima di liberare un Host che conserva eventi. Un match necessario a un altro partecipante non è cancellato per espellere più rapidamente l’Host. Questa salvaguardia significa che non si può promettere spazio recuperato per ogni account esattamente al settimo giorno.

I record precedenti alla comunicazione della regola o non riconciliati sono esclusi dalla cancellazione automatica. Non anticipare la data della conferma per farli rientrare nel job.

## Attivazione e disattivazione

Prima dell’attivazione servono: migrazione approvata nel progetto corretto, revisione delle dipendenze reali/Storage, informative aggiornate, percorso di esportazione e assistenza funzionante, disponibilità effettiva del Premium proposto e prove reali di Auth/pagamento in ambiente separato. La beta gratuita iniziale può mantenere disattivata questa durata finché gli acquisti non sono operativi: non presentarla come già applicata.

Le RPC `set_account_lifecycle_enabled(enabled,purge_enabled,policy_version)`, `set_account_retention_hold(...)` e `configure_account_retention_cron(...)` sono riservate al server. La configurazione rifiuta il purge se l’enforcement è spento. Il job usa l’estensione inclusa `pg_cron`, al minuto 37 di ogni ora; il modulo non installa l’estensione e non lo attiva automaticamente. Va controllata una vera esecuzione sul servizio prima di chiamarlo operativo. I conteggi privati del worker sono conservati per 30 giorni, senza una lista di persone eliminate.

Per fermare la pulizia, disabilitare il solo job e impostare entrambe le opzioni server su false. Disattivare un job non ripristina account già cancellati. Occorrono una procedura di backup/ripristino provata e istruzioni che non reintroducano dati di account eliminati.

## Prove e limiti

`tests/account-lifecycle-runtime.cjs` esegue dieci scenari delle funzioni reali del client con trasporti controllati: conferma, ordine delle chiamate, errore server, doppio tap, scadenza, risposta tardiva e cambio account. `tests/sql/account-lifecycle.sql` esegue dodici gruppi in PostgreSQL locale e termina con rollback verificato dei conteggi.

Le prove coprono periodo esatto, mancato reset, join senza timer, sessione revocata, blocco delle nuove operazioni, preavviso/grazia, Premium, Admin, acquisti, match attivi, segnalazioni, vincoli nuovi, Storage, cancellazione Auth/sessione/profilo e rotazione del batch. Sono prove sintetiche PGlite, non un accesso Google reale, un webhook reale o un’esecuzione Cron. La concorrenza a connessioni separate e la gestione delle tabelle Auth/Storage del servizio reale restano da verificare in un ambiente approvato.

Riferimenti primari: [gestione e cancellazione utenti Supabase](https://supabase.com/docs/guides/auth/managing-user-data), [Cron Supabase](https://supabase.com/docs/guides/cron). I JWT già emessi possono sopravvivere fino alla loro scadenza; la cancellazione non sostituisce i controlli applicativi su utente e sessione.
