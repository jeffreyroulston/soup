#!/usr/bin/env bash
# Ploi deploy script for Soup Identity.
# Paste into Ploi → Site → Deployment → Deploy script. Ploi runs it from the
# site root ({SITE_DIRECTORY}); this repo keeps the service under services/soup-identity.
set -euo pipefail

cd {SITE_DIRECTORY}
git pull origin main

cd services/soup-identity
# devDependencies are needed for tsc; prune after the build.
npm ci
npm run build
npm prune --omit=dev

# Applies pending SQL migrations and upserts the plugin credential from .env.
# Uses the compiled script: `npm run migrate` needs tsx, which was just pruned.
node dist/db/migrate.js

# The service runs under PM2 as the ploi user (`pm2 start dist/index.js --name soup-identity`).
pm2 restart soup-identity --update-env

echo "Soup Identity deployed"
