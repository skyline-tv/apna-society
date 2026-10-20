# MongoDB replica-set setup (single VPS)

Transactions require a replica set (even with one member). The Docker Compose stack in this project starts a single-node replica set named `rs0` and keeps MongoDB on an internal Docker network only.

## Why a replica set?

- Mongoose multi-document transactions need `replicaSet` (or mongos).
- A one-member replica set is enough for a single VPS.

## Docker Compose (recommended)

```bash
cd backend-v2
cp .env.example .env
# edit secrets
docker compose up -d
```

MongoDB is **not** published on the host. Only the API port is exposed.

Connection string used by the API container:

```text
mongodb://mongo:27017/apna_society?replicaSet=rs0&directConnection=true
```

## Manual single-VPS replica set

1. Install MongoDB 7 on the VPS.
2. Bind MongoDB to localhost / private interface only (never `0.0.0.0` publicly without auth + firewall).
3. Start with `--replSet rs0`.
4. Initiate:

```js
rs.initiate({
  _id: 'rs0',
  members: [{ _id: 0, host: '127.0.0.1:27017' }],
});
```

5. Create an application user and use:

```text
mongodb://appuser:SECRET@127.0.0.1:27017/apna_society?replicaSet=rs0&authSource=admin
```

## Security checklist

- Do not publish `27017` to the public internet.
- Use strong credentials; never commit them.
- Prefer Docker internal networking or a private VPC.
- Enable authentication before exposing any network path.
- Back up the volume (`mongo_data`) regularly.
