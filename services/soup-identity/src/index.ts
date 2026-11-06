import { readFileSync, existsSync } from "node:fs";
import { serve } from "@hono/node-server";
import { loadDotEnv, loadEnv } from "./env.js";
import { createPool } from "./db/client.js";
import { applyMigrations } from "./db/migrations.js";
import { loadSigningKeys, sha256 } from "./lib/crypto.js";
import { createApp } from "./app.js";

/** Minimal .env loader (no dotenv dependency). Does not override existing env. */
async function ensureBootstrapPlugin(
  db: ReturnType<typeof createPool>,
  env: ReturnType<typeof loadEnv>,
) {
  if (!env.BOOTSTRAP_PLUGIN_ID || !env.BOOTSTRAP_PLUGIN_SECRET) return;
  await db.query(
    `INSERT INTO plugin_credentials (plugin_id, secret_hash, label)
     VALUES ($1, $2, $3)
     ON CONFLICT (plugin_id) DO UPDATE
       SET secret_hash = EXCLUDED.secret_hash,
           revoked_at = NULL`,
    [env.BOOTSTRAP_PLUGIN_ID, sha256(env.BOOTSTRAP_PLUGIN_SECRET), "bootstrap"],
  );
}

async function main() {
  loadDotEnv();
  const env = loadEnv();
  const db = createPool(env.DATABASE_URL);
  const keys = await loadSigningKeys(env);

  for (let attempt = 1; attempt <= 10; attempt++) {
    try {
      await applyMigrations(db);
      await ensureBootstrapPlugin(db, env);
      break;
    } catch (err) {
      if (attempt === 10) throw err;
      console.warn(`Migrate attempt ${attempt}/10 failed; retrying…`, err);
      await new Promise((r) => setTimeout(r, 500 * attempt));
    }
  }

  const app = createApp({ db, env, keys });

  console.log(
    `soup-identity listening on :${env.PORT} (alg=${keys.alg} kid=${keys.kid} google=${env.googleConfigured ? "on" : "dev"})`,
  );
  serve({ fetch: app.fetch, port: env.PORT });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
