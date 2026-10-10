# Deploying Soup Identity on a Ploi-managed droplet

Runs the service as a plain Node daemon behind Ploi's nginx with Let's Encrypt TLS.
See `deploy.sh` (Ploi deploy script) and `nginx-location.conf` (proxy block).

Process manager: PM2 as the `ploi` user, via the app Ploi creates (`soup-idmbestiestudioscom`, runs `npm start`;
Ploi restarts it after each deploy; `pm2-ploi.service` restores it on boot),
started from `{SITE_DIRECTORY}/services/soup-identity`. The service reads `.env`
from its working directory and persists signing keys under `data/`; back that
folder up, since losing it invalidates every issued token.
