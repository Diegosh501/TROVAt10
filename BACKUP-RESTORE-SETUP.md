# Recupero dati, cifratura e prove PostgreSQL

## Stato operativo

Il progetto Supabase reale non ha ancora un backup completo ripristinato e verificato in un secondo ambiente gestito. Il nuovo percorso descritto qui aggiunge una prova ripetibile del database applicativo in un ambiente PostgreSQL isolato: non sostituisce il recupero di Auth gestita, oggetti Storage, configurazioni e segreti dei provider.

Supabase raccomanda per il piano Free esportazioni regolari mediante CLI e copie esterne. I backup del database non includono i file Storage; le credenziali dei ruoli personalizzati richiedono gestione distinta. Riferimenti ufficiali: [backup Supabase](https://supabase.com/docs/guides/platform/backups), [trasferimento e ripristino](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore), [dump PostgreSQL](https://www.postgresql.org/docs/17/backup-dump.html). Non è stato acquistato un piano backup o PITR.

## Controllo nativo nel repository

Il job `Native PostgreSQL concurrency and restore` in GitHub Actions usa l’immagine ufficiale PostgreSQL 17.11 bloccata al digest e `pg` 8.23.1 con lockfile. Il servizio ascolta soltanto sulla loopback del runner. Password e identità nel job sono fixture sintetiche pubbliche, non credenziali del prodotto.

Il driver `tests/integration/native-postgres.cjs`:

1. Rifiuta endpoint remoti, database di controllo diversi da `trovat1o_ci_control`, cluster con altri database, ruoli applicativi preesistenti, controllo o database postgres non vuoti. Richiede un’opzione esplicita di test isolato.
2. Crea due database casuali nuovi e controlla PostgreSQL 17. Il fixture Auth è separato da quello PGlite; il vecchio blocco PGlite-only non viene rimosso.
3. Riproduce le 17 migrazioni realmente registrate nell’ordine. Il solo helper gestito `rls_auto_enable` ha una firma inerte di test per la revoca storica: tutte le tabelle applicative devono attivare esplicitamente la propria RLS.
4. Esegue le regressioni SQL con verifica del rollback. Applica la migrazione supporto pendente esclusivamente al database sintetico e ne verifica la regressione: questo non ne prova l’applicazione remota.
5. Usa connessioni PostgreSQL distinte, avvia richieste concorrenti e osserva tutte le operazioni effettivamente bloccate dietro un lock prima di rilasciarlo. Controlla doppie richieste, ultimo posto, ammissioni, transizioni, limite Free, idempotenza, quota assistenza e riuso del CAPTCHA verificato.
6. Genera un dump custom con `pg_dump` dell’istanza isolata, lo cifra, rifiuta chiave errata o alterazione e lo ripristina con `pg_restore` transazionale in un database nuovo. Confronta dati, ACL, RLS, policy, funzioni, vincoli e sequenze e riprova il confine della sessione sintetica.
7. Rimuove soltanto i database casuali creati da quel test. Non contatta Supabase o legge segreti di produzione. Il risultato, privo di dump o chiavi, viene scritto in `tmp/native-postgres/report.json` e nei log del job.

L’esito effettivo va letto nel run corrispondente al commit corrente, non dedotto dalla presenza del driver. Un errore o una parte non eseguita non chiudono lo scenario I o L. Restano necessarie concorrenza HTTP nel servizio, copia dei dati reali e recupero dell’intero ambiente gestito.

## Cifrare un’esportazione privata

`scripts/backup-envelope.cjs` usa AES-256-GCM con nonce casuale e intestazione autenticata. La cifratura/decifratura dei file è in streaming; il file finale viene pubblicato soltanto a operazione riuscita. Un errore di autenticazione elimina il temporaneo senza lasciare un output parziale. File esistenti e chiavi esistenti non vengono sovrascritti. Cartella di destinazione privata 700 e chiave privata 600 sono obbligatorie.

Esempio, dalla cartella dei sorgenti, su un’esportazione già ottenuta con strumenti ufficiali:

```sh
mkdir -m 700 -p output/private-backup output/private-key
node scripts/backup-envelope.cjs keygen output/private-key/backup.key
node scripts/backup-envelope.cjs encrypt output/private-backup/database.dump output/private-backup/database.dump.enc output/private-key/backup.key
node scripts/backup-envelope.cjs decrypt output/private-backup/database.dump.enc output/private-backup/database.restored.dump output/private-key/backup.key
```

La generazione della chiave va eseguita una volta sola. Custodire la chiave separatamente dal backup, fuori dal versionamento, dal sito e dalle cartelle condivise e allegati di consegna. La perdita della chiave rende irrecuperabile la copia cifrata. La chiave non va inviata in chat o inserita nella riga di comando. L’esempio non produce da solo un dump Supabase e non autorizza cancellazioni: non eliminare gli originali senza una verifica di recupero.

Conservare la copia cifrata e la chiave su supporti separati dopo la verifica di recupero. La cartella output è esclusa da Git; non copiare la sua sottocartella privata nel sito.

Otto prove ripetibili: `node tests/integration/backup-envelope.test.cjs`. La prova non crea una chiave reale del proprietario.

## Procedura ancora necessaria per il servizio reale

- Ottenere una connessione ufficiale con privilegi di lettura/backup appropriati, mantenendo la credenziale fuori da sorgenti, argomenti pubblici, log e cronologia. Non estrarre password da chat, browser o vecchi callback OAuth.
- Con CLI Supabase verificata, esportare ruoli, schema e dati secondo le istruzioni ufficiali correnti. Verificare esplicitamente inclusione di Auth e metadati Storage: i filtri predefiniti non equivalgono automaticamente a un backup completo.
- Conservare configurazione senza segreti e inventario delle Edge Functions; custodire separatamente segreti e oggetti Storage eventualmente presenti. Non pubblicare nessuna di queste copie tramite public/.
- Cifrare le copie e conservarne una separata dal Mac; definire frequenza, durata, responsabilità e scadenza. Non caricare dati di utenti su un nuovo fornitore senza la configurazione e le autorizzazioni pertinenti.
- Ripristinare in un secondo progetto/ambiente approvato, con SMTP, pagamenti, callback e job spenti per evitare invii o addebiti. Verificare policy, identità/riaccesso, dati, oggetti, quote, notifiche e configurazione.
- Riesaminare i diritti di cancellazione: non usare un backup per riattivare un account eliminato. Solo dopo esito documentato attivare eventuali pulizie automatiche.

Il rollback frontend riguarda la versione Cloudflare, non ripristina i dati. Migrazioni, rollback SQL, ZIP integro e copia cifrata non costituiscono da soli un recupero completo del servizio.
