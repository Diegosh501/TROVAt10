# TROVAT1O · Cloudflare preview

[Apri la preview pubblica](https://trovato.diegolucentedesign.workers.dev/)

Il Worker serve solo gli asset statici in `public/`. La configurazione mantiene `onlineReady: false`; profili demo, eventi, richieste e promemoria restano locali al browser. Non inserire dati reali. Il backend Supabase ha lo schema V2 applicato ma non ha ancora utenti, Edge Functions o provider Auth configurati.

Per aggiornare la preview, sincronizzare `public/` dalla versione locale, creare di nuovo l’archivio statico e pubblicare:

```sh
cd "/Users/claudia/.codex/.chatgpt-projects/g-p-6ad372b660b0819189c0e8409c915b87/TROVAT1O-Cloudflare-Deploy"
tar -xzf trovato-static-assets.tar.gz -C .
npm ci
npx wrangler deploy
```

`workers.dev` è gratuito e non richiede l’acquisto di `trovat10.app`. Il dominio personalizzato potrà essere collegato più avanti. Non mettere file Supabase o segreti dentro `public/`.
