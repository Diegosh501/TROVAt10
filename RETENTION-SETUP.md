# Ciclo di vita e conservazione dei match

Il codice è in `supabase/retention.sql`, da applicare dopo schema, notifiche, sicurezza Admin, profilo Google, accesso gratuito e Billing. **Questo documento non attesta un'applicazione remota o un job già attivo.** L'account non viene eliminato, sospeso o fatto scadere quando termina lo storico Free.

## Regola del piano

La chiusura è manuale: l'Host avvia, conclude o annulla l'evento mediante la RPC esistente. Il server scrive `closed_at` quando lo stato passa a `completed` o `cancelled`. Non viene dedotta la fine dalla creazione, dall'orario previsto o dall'orologio del telefono. Una partita ancora in corso resta tale finché l'Host non la conclude; nessun automatismo inventa una fine.

Il piano è valutato per l'utente che consulta lo storico. Free conserva la visibilità per sette giorni esatti da `closed_at`; un Premium attivo con scadenza futura conserva il proprio storico come creatore o partecipante ammesso. Un utente rifiutato/rimosso non prolunga la conservazione semplicemente pagando. Premium non rende pubblico un evento privato. Ruolo Host/Sportivo e abbonamento restano distinti.

Se un Host Free organizza una partita con un partecipante Premium ammesso, il record condiviso viene conservato per quel partecipante. L'Host e gli altri utenti Free, dopo sette giorni, non lo vedono più. La politica non cancella dati che spettano ancora a un partecipante Premium. La scadenza di un abbonamento riapplica la regola Free al termine effettivo originario: non sposta artificialmente `closed_at`.

La firma e le colonne di `event_feed()` restano compatibili. La scadenza è verificata nel feed e nelle policy delle tabelle collegate, non soltanto nell'interfaccia. Roster, contatto Host, inviti, pin e notifiche dell'evento non restano consultabili da un Free attraverso richieste dirette dopo la scadenza. I report inviati al supporto fanno eccezione: il segnalante e l'assistenza autorizzata mantengono il contesto necessario alla pratica.

## Archiviazione e cancellazione

Il worker esegue tre fasi, con batch limitati:

1. Ripristina l'archivio se un creatore o membro ammesso dispone di Premium attivo.
2. Archivia gli eventi conclusi/annullati da almeno sette giorni che non hanno più titolari Premium ammessi. L'archiviazione non modifica `closed_at` né il numero degli eventi attivi.
3. Dopo almeno altre 24 ore dall'archiviazione, elimina fisicamente soltanto eventi ancora senza Premium, senza segnalazioni e senza sospensioni di conservazione valide.

Nella finestra di archiviazione, un nuovo Premium ammesso può ritrovare subito lo storico conservato; il worker rimuove poi la marcatura d'archivio. Un record già eliminato non può essere ricostruito da un nuovo abbonamento: non va promesso un recupero retroattivo di dati cancellati.

Sono controllate le dipendenze reali: partecipanti, contatti Host, inviti, pin, notifiche e consegne hanno cancellazione a cascata. Qualsiasi `player_reports` collegato impedisce la cancellazione dell'evento, anche se la pratica risulta risolta: la definizione del periodo di conservazione delle pratiche di sicurezza è separata e richiede una politica esplicita. Non viene scelta implicitamente una scadenza legale. Eventuali nuove chiavi esterne sconosciute, anche a cascata, bloccano il purge fino a revisione. Una sottoscrizione legacy mancante impedisce il purge fisico anziché indovinare il piano.

Le sospensioni esplicite sono gestite esclusivamente da `set_event_retention_hold(event_id,reason,until)`, riservata al server. I motivi ammessi sono revisione sicurezza, obbligo di conservazione o assistenza. Ogni sospensione ha una scadenza futura di massimo 366 giorni, rinnovabile mediante una decisione autorizzata; passare `null` rimuove soltanto la sospensione di quel motivo. Questi controlli non concedono accesso utente ai match scaduti.

I vecchi eventi già conclusi prima della migrazione, privi di una data attendibile, ricevono una finestra prudenziale piena a partire dall'applicazione. È un fallback documentato per dati legacy, non una dichiarazione sulla loro vera conclusione. Il database remoto osservato durante la preparazione era vuoto.

## Pianificazione senza nuovo servizio

Il worker è `run_event_retention(limit)`; `anon` e `authenticated` non possono eseguirlo. Usa un blocco transazionale per evitare esecuzioni sovrapposte e piccoli batch con `SKIP LOCKED`. Le statistiche sono conteggi privati, senza nomi, email o contenuti dei match. Il registro del worker e la storia del suo solo job Cron vengono conservati per 30 giorni.

La funzione `configure_event_retention_cron(true)` crea/aggiorna il job nominato `trovat1o-event-retention-v1`, al minuto 17 di ogni ora. È riservata al server e funziona solo dopo aver abilitato l'estensione inclusa `pg_cron` nel progetto esistente. Non installa l'estensione e non dichiara successo se essa manca. `configure_event_retention_cron(false)` disattiva quel solo job.

La pianificazione usa il database esistente; il codice non apre account di terzi né attiva un canone esterno. Va verificata insieme ai limiti e allo stato del piano Supabase effettivo. Un progetto sospeso o un job disattivato non esegue pulizie: al ritorno il feed continua a negare lo storico Free scaduto, ma la cancellazione fisica richiede che il database e il job siano operativi. Non è una garanzia di cancellazione al secondo. Riferimenti ufficiali: [Supabase Cron](https://supabase.com/docs/guides/cron), [pianificazione e storia dei job](https://supabase.com/docs/guides/cron/quickstart).

Prima dell'attivazione remota: eseguire le regressioni su un database di prova, verificare le dipendenze, applicare come nuova migrazione, abilitare/configurare Cron e controllare almeno un'esecuzione reale e i conteggi. Il codice da solo non completa questi passaggi. Disattivare il job prima di un rollback; una cancellazione fisica richiede un backup dati per essere recuperata e non viene annullata togliendo la migrazione.

## Prove

`tests/sql/retention.sql` esegue 14 gruppi di controlli effettivi in PostgreSQL e conclude con `ROLLBACK`. Rifiuta un database con utenti o eventi esistenti. Comprende chiusura server e immutabilità, Free/Premium per partecipante, canali RLS laterali, link privato, dipendenza FK sconosciuta, grazia prima del purge, report e sospensioni, piano legacy mancante, account preservati, ripetizione idempotente, scadenza/rinnovo Premium e configurazioni invalide, blocco di vecchi JWT di account sospesi e ricerca pubblica anonima preservata.

Le date storiche dei fixture vengono preparate con il solo trigger di questa migrazione temporaneamente disabilitato, esclusivamente nella transazione di prova; viene riabilitato prima di verificare i comportamenti. Non è una funzione disponibile al client e non è una prova d'identità Google o di pagamento Stripe.
