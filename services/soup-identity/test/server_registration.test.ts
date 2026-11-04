import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { createApp } from "../src/app.js";
import { createPool, type Db } from "../src/db/client.js";
import { applyMigrations } from "../src/db/migrations.js";
import { loadEnv } from "../src/env.js";
import { loadSigningKeys, sha256 } from "../src/lib/crypto.js";

const OWNER = { id: "test-plugin-owner", secret: "owner-secret" };
const OTHER = { id: "test-plugin-other", secret: "other-secret" };
const SERVER_ID = "test-jf-registration";

describe("server registration", () => {
  let db: Db;
  let app: ReturnType<typeof createApp>;

  before(async () => {
    const env = loadEnv({ ...process.env });
    db = createPool(env.DATABASE_URL);
    await applyMigrations(db);
    for (const p of [OWNER, OTHER]) {
      await db.query(
        `INSERT INTO plugin_credentials (plugin_id, secret_hash, label)
         VALUES ($1, $2, $3)
         ON CONFLICT (plugin_id) DO UPDATE
           SET secret_hash = EXCLUDED.secret_hash, revoked_at = NULL`,
        [p.id, sha256(p.secret), "test"],
      );
    }
    await db.query(`DELETE FROM servers WHERE server_id = $1`, [SERVER_ID]);
    const keys = await loadSigningKeys(env, `/tmp/soup-identity-test-keys-${randomBytes(4).toString("hex")}`);
    app = createApp({ db, env, keys });
  });

  after(async () => {
    await db.query(`DELETE FROM servers WHERE server_id = $1`, [SERVER_ID]);
    await db.query(`DELETE FROM plugin_credentials WHERE plugin_id = ANY($1)`, [
      [OWNER.id, OTHER.id],
    ]);
    await db.end();
  });

  function put(plugin: typeof OWNER, body: Record<string, unknown>) {
    return app.request(`/v1/servers/${SERVER_ID}`, {
      method: "PUT",
      headers: {
        authorization: `Basic ${Buffer.from(`${plugin.id}:${plugin.secret}`).toString("base64")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
  }

  it("lets the registering plugin update its server", async () => {
    let res = await put(OWNER, { name: "Home", audience: "jellyfin:home", base_url: "https://home.example" });
    assert.equal(res.status, 200);
    res = await put(OWNER, { name: "Home 2", audience: "jellyfin:home", base_url: "https://home2.example" });
    assert.equal(res.status, 200);
    const { rows } = await db.query<{ name: string }>(
      `SELECT name FROM servers WHERE server_id = $1`,
      [SERVER_ID],
    );
    assert.equal(rows[0]?.name, "Home 2");
  });

  it("rejects another plugin taking over the server id", async () => {
    const res = await put(OTHER, { name: "Evil", audience: "jellyfin:home", base_url: "https://evil.example" });
    assert.equal(res.status, 409);
    const { rows } = await db.query<{ plugin_id: string; base_url: string }>(
      `SELECT plugin_id, base_url FROM servers WHERE server_id = $1`,
      [SERVER_ID],
    );
    assert.equal(rows[0]?.plugin_id, OWNER.id);
    assert.equal(rows[0]?.base_url, "https://home2.example");
  });
});
