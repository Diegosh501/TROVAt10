# TROVAT1O — iterazione UX 2

## Obiettivo

Ridurre i passaggi tra trovare una partita e chiedere un posto; distinguere il percorso di chi gioca da quello di chi organizza; mantenere la gestione essenziale fino alla chiusura dell’evento. Questa nota documenta l’iterazione che ha portato alla versione mobile first ora integrata nel file canonico `index.html`. `index-v2.html` è mantenuto solo come reindirizzamento compatibile.

## Problemi di flusso affrontati

- **Troppi campi in vista:** ricerca e filtri occupavano la prima schermata mobile. Ora la ricerca zona/campo resta visibile e i filtri formato, tipo e data si aprono solo su richiesta.
- **Join nascosto nei dettagli:** dalla scheda elenco si potevano aprire i dettagli e solo lì trovare l’iscrizione. Ora ogni card presenta l’azione coerente con lo stato: Partecipa, Chiedi un posto, Richiesta inviata, Posti esauriti o Apri la tua partita.
- **Scelta Host/Sportivo troppo presto:** il nuovo benvenuto propone prima due intenzioni concrete: cercare eventi da ospite oppure registrarsi come Host per organizzarne uno. Per chiedere di partecipare si richiede l’account nel momento dell’azione.
- **Troppe azioni contemporanee nei dettagli:** la scheda introduce lo stato della partita e separa “Condividi invito”, “Contatta Host”, “Correggi luogo” e “Segnala”. Il contatto non sostituisce la condivisione.
- **Evento senza chiusura chiara:** lo stato esplicito guida da iscrizioni aperte a partita in corso e conclusa; l’Host mantiene avvio e chiusura manuali.
- **Reminder invasivo:** se dopo 10 secondi l’utente non ha iniziato una creazione o un’iscrizione, compare un suggerimento non bloccante con “Trova una partita” e “Organizza”. Aspetta che un dialogo si chiuda, sparisce dopo una scelta e non torna nella stessa sessione dopo la chiusura.

## Contatto Host

Il Host può inserire un recapito WhatsApp per evento e deve selezionare una casella esplicita per condividerlo. Nell’interfaccia il numero è mostrato solo a chi risulta ammesso, mai nella card pubblica o nel link d’invito. Condivisione invito e contatto diretto restano due azioni separate. Lo schema aggiunge `event_host_contacts` con regole RLS dedicate; l’integrazione completa con il database non è ancora attiva, quindi non inserire numeri reali nella demo locale.

## Funzioni mantenute

Ricerca lista/mappa, filtri 5/8/11, eventi pubblici/privati, approvazione Host, gestione partecipanti, avvisi per richieste e ammissioni, promemoria prima dell’evento, condivisione via link/WhatsApp, pin suggerito, segnalazioni riservate, cronologia e proposta Premium. Non vengono aggiunti feed, amicizie, classifiche, profili social o notifiche di popolarità.

## Iterazione mobile e brand · 9 novembre 2026

La promessa di brand è **“Non perderti più una partita”**. La visione futura è più ampia, ma questa versione dichiara con chiarezza il suo perimetro: partite amatoriali di calcio a 5, 8 e 11. La scheda mantiene l’ordine data/ora, luogo, tipo e titolo. Su mobile il claim è breve, i filtri sono richiudibili, la CTA flottante è una sola e scompare in “I miei match”, dove resta il pulsante dedicato “Organizza”. Desktop conserva la vista più distesa.

Il riepilogo storico mostra prima data/ora e luogo; i limiti Free/Premium sono raccolti in un dettaglio richiudibile su mobile. I campi facoltativi di creazione restano dentro sezioni espandibili. La navigazione mobile lascia visibili Eventi, Mappa, I miei match e Profilo.

Gli avvisi locali sono in-app e operano solo mentre la pagina è aperta. La push in background è subordinata a HTTPS, consenso esplicito dal pulsante, VAPID e un dispatcher backend con Cron; non è dichiarata attiva in questa anteprima. La scelta di archiviazione offre “Solo questa sessione” o “Salva sul dispositivo” e si può modificare nelle preferenze.

## Privacy e documenti

`privacy.html`, `cookie.html` e `termini.html` descrivono la demo locale, il titolare e i contatti forniti, i contenuti conservati nel browser, i servizi esterni condizionali, i diritti e lo stato non attivo di Supabase, OTP e pagamenti. Le informative non fingono che il backend sia già configurato. Prima di attivare account online vanno aggiunti i dati effettivi di hosting/backend, regione, trasferimenti, retention, procedure di cancellazione e basi giuridiche del trattamento che il titolare decide di adottare.

I documenti Fubles sono citati soltanto come riferimento di struttura; il loro testo non è stato copiato e non descrive il servizio TROVAT1O. Per i requisiti informativi sono linkati il [Garante Privacy](https://www.garanteprivacy.it/home/docweb/-/docweb-display/docweb/8981258) e il [Regolamento GDPR, articolo 13](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng/).

## Prossimo passaggio

Il client è ancora offline e Supabase è soltanto uno scaffold. I test automatici già presenti vanno rieseguiti dopo questa iterazione; l’interfaccia va inoltre rivista visivamente su Safari iOS e Chrome Android. Solo dopo l’implementazione del collegamento dati vanno provate le policy cloud con utenti separati.

## Riferimenti e confronto

- [Garante Privacy — guida applicazione GDPR](https://www.garanteprivacy.it/documents/10160/0/Guida%2Ball%2Bapplicazione%2Bdel%2BRegolamento%2BUE%2B2016%2B679.pdf)
- [Fubles — termini](https://www.fubles.com/it/pages/terms)
- [Fubles — privacy](https://fubles.com/en/pages/privacy)
