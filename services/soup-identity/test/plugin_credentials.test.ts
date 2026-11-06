import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { decodeJwt } from "jose";
import { createApp } from "../src/app.js";
import { createPool, type Db } from "../src/db/client.js";
import { applyMigrations } from "../src/db/migrations.js";
import { loadEnv } from "../src/env.js";
import { loadSigningKeys, signAssertion } from "../src/lib/crypto.js";
import {
  issuePluginCredential,
  listPluginCredentials,
  PluginCredentialError,
  revokePluginCredential,
  rotatePluginCredential,
} from "../src/lib/plugin_credentials.js";

const FRIEND = "test-friend-cred";
const SERVER_ID = "test-friend-cred-jf";

describe("plugin credentials", () => {
  let db: Db;
  let app: ReturnType<typeof createApp>;
  let env: ReturnType<typeof loadEnv>;
  let keys: Awaited<ReturnType<typeof loadSigningKeys>>;

  const register = (pluginId: string, secret: string) =>
    app.request(`/v1/servers/${SERVER_ID}`, {
      method: "PUT",
      headers: {
        authorization: `Basic ${Buffer.from(`${pluginId}:${secret}`).toString("base64")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "Friend", audience: `jellyfin:${pluginId}` }),
    });

  const cleanUp = async () => {
    await db.query(`DELETE FROM servers WHERE server_id = $1`, [SERVER_ID]);
    await db.query(`DELETE FROM plugin_credentials WHERE plugin_id = $1`, [FRIEND]);
  };

  before(async () => {
    env = loadEnv({ ...process.env });
    db = createPool(env.DATABASE_URL);
    await applyMigrations(db);
    await cleanUp();
    keys = await loadSigningKeys(env, `/tmp/soup-identity-test-keys-${randomBytes(4).toString("hex")}`);
    app = createApp({ db, env, keys });
  });

  after(async () => {
    await cleanUp();
    await db.end();
  });

  it("an issued secret lets the plugin register its server", async () => {
    const secret = await issuePluginCredential(db, FRIEND, "Friend");
    assert.equal((await register(FRIEND, secret)).status, 200);
    assert.equal((await register(FRIEND, "wrong")).status, 401);

    const row = (await listPluginCredentials(db)).find((r) => r.plugin_id === FRIEND);
    assert.deepEqual(row?.servers, [SERVER_ID]);
    assert.equal(row?.label, "Friend");
  });

  it("won't overwrite an existing credential", async () => {
    await assert.rejects(issuePluginCredential(db, FRIEND), PluginCredentialError);
  });

  it("rejects ids that wouldn't work as a server id", async () => {
    await assert.rejects(issuePluginCredential(db, "Not Valid!"), PluginCredentialError);
  });

  it("revoking blocks the plugin and rotating restores it with a new secret", async () => {
    const old = await rotatePluginCredential(db, FRIEND);
    assert.equal((await register(FRIEND, old)).status, 200);

    await revokePluginCredential(db, FRIEND);
    assert.equal((await register(FRIEND, old)).status, 401);

    const fresh = await rotatePluginCredential(db, FRIEND);
    assert.equal((await register(FRIEND, old)).status, 401);
    assert.equal((await register(FRIEND, fresh)).status, 200);
  });

  it("reports unknown credentials", async () => {
    await assert.rejects(rotatePluginCredential(db, "test-nobody"), PluginCredentialError);
    await assert.rejects(revokePluginCredential(db, "test-nobody"), PluginCredentialError);
  });

  // Plugins reject a server_id that isn't theirs, which is what stops one
  // server replaying a guest's assertion on another that shares its audience.
  it("assertions always name their server", async () => {
    const { assertion } = await signAssertion(keys, env, {
      email: "guest@example.com",
      audience: "jellyfin:shared",
      serverId: SERVER_ID,
    });
    assert.equal(decodeJwt(assertion).server_id, SERVER_ID);
  });
});
