# Esportazione della cronologia effettiva

Questa cartella conserva, nell'ordine delle versioni registrate, le nove migrazioni presenti su Supabase al 10 novembre 2026. Non sono nuove migrazioni inventate e non sono file generati con `migration new`: sono l'esportazione della cronologia applicata tramite connettore.

Gli otto file iniziali (88.812 byte complessivi) hanno conteggi e MD5 confrontati con i metadati calcolati dal database. Il nono file, `20261110164243_trovat1o_platform_admin_security.sql`, ha 12.242 byte e MD5 `a0c8bac492bc42747e3452ae5f85d751`, identici al contenuto registrato. `admin-security.sql` è il blueprint leggibile di questa ultima modifica.

Le due migrazioni `event_read_privacy` hanno SQL identico e sono entrambe conservate perché entrambe registrate.

**Questi file non sono un backup dei dati e il replay non è stato provato.** Richiedono una base Supabase: la prima migrazione si riferisce alla funzione preesistente `public.rls_auto_enable()`, e le successive a oggetti Auth e ruoli di piattaforma. Non sono un bootstrap per PostgreSQL vuoto. Non copiare automaticamente la cartella nel percorso CLI `migrations/` e non avviare `db push` senza riconciliazione e prova su ambiente separato.
