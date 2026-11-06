import { loadDotEnv, loadEnv } from "../env.js";
import { sha256 } from "../lib/crypto.js";
import { createPool } from "./client.js";
import { applyMigrations } from "./migrations.js";

async function main() {
  loadDotEnv();
  const env = loadEnv();
  const pool = createPool(env.DATABASE_URL);
  const applied = await applyMigrations(pool);

  if (env.BOOTSTRAP_PLUGIN_ID && env.BOOTSTRAP_PLUGIN_SECRET) {
    await pool.query(
      `INSERT INTO plugin_credentials (plugin_id, secret_hash, label)
       VALUES ($1, $2, $3)
       ON CONFLICT (plugin_id) DO UPDATE
         SET secret_hash = EXCLUDED.secret_hash,
             label = COALESCE(EXCLUDED.label, plugin_credentials.label),
             revoked_at = NULL`,
      [
        env.BOOTSTRAP_PLUGIN_ID,
        sha256(env.BOOTSTRAP_PLUGIN_SECRET),
        "bootstrap",
      ],
    );
    console.log(`Bootstrapped plugin credential: ${env.BOOTSTRAP_PLUGIN_ID}`);
  }

  await pool.end();
  console.log(`Migrations applied: ${applied.join(", ")}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
