# Apna Society website

Product landing page plus Play Store compliance pages.

Routes: `/` (landing), `/privacy-policy`, `/account-deletion`, `/support`. Vite + React + React Router, pre-rendered to static HTML.

    npm install
    SITE_URL=https://your-domain npm run build   # typecheck, build, prerender; lists every unconfirmed item
    npm run preview

- Landing and legal text: `src/content.ts`. Layout: `src/App.tsx`. Styles: `src/styles.css`.
- Set `PLAY_STORE_URL` in `src/content.ts` when the listing is live; the landing page then shows a store button.
- Deploy `dist/` anywhere. SPA fallback is included for Netlify (`_redirects`), Vercel (`vercel.json`) and nginx (`nginx.conf.sample`).
- Account deletion requests go to `info@skylinetv.in` (the public SkyLine Tech Ventures address). Change `SUPPORT_EMAIL` in `src/content.ts` if that mailbox changes.
- Every `[TO CONFIRM: ...]` shows as a yellow highlight on the page and in the build log. Replace or delete each before submitting.

Known gap: Google Play requires an in-app account deletion path. This site only covers the web part.
