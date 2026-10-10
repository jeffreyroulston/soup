# Deploying Soup Identity on a Ploi-managed droplet

Runs the service as a plain Node daemon behind Ploi's nginx with Let's Encrypt TLS.
See `deploy.sh` (Ploi deploy script) and `nginx-location.conf` (proxy block).

Process manager: PM2 as the `ploi` user (`pm2 start dist/index.js --name soup-identity`, then `pm2 save` and `pm2 startup`),
started from `{SITE_DIRECTORY}/services/soup-identity`. The service reads `.env`
from its working directory and persists signing keys under `data/`; back that
folder up, since losing it invalidates every issued token.
