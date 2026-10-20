# Apna Society

Monorepo layout:

| Folder | Contents |
| --- | --- |
| `app/` | Flutter client (Android & iOS), still local-first with SQLite / Drift |
| `backend-v2/` | Active backend foundation (Express, MongoDB, Mongoose) |

## Flutter app

```bash
cd app
flutter pub get
flutter run
```

See `app/README.md`.

## Backend API (v2)

```bash
cd backend-v2
cp .env.example .env
npm install
npm run seed
npm run dev
```

See `backend-v2/README.md`.
