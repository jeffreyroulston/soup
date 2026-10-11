import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { createApp } from "../src/app.js";
import { createPool, type Db } from "../src/db/client.js";
import { applyMigrations } from "../src/db/migrations.js";
import { loadEnv } from "../src/env.js";
import {
  loadSigningKeys,
  signDeviceLinkProof,
  signOAuthState,
  verifyOAuthState,
  type SigningKeys,
} from "../src/lib/crypto.js";
import { pollDeviceLink, startDeviceLink } from "../src/auth/sessions.js";

describe("ALLOW_DEV_LOGIN default", () => {
  it("defaults to false when unset", () => {
    const env = loadEnv({
      DATABASE_URL: "postgres://soup:soup@localhost:5433/soup_identity",
      PUBLIC_BASE_URL: "http://localhost:8787",
    });
    assert.equal(env.ALLOW_DEV_LOGIN, false);
  });
});

describe("OAuth state JWT", () => {
  let keys: SigningKeys;
  let env: ReturnType<typeof loadEnv>;

  before(async () => {
    env = loadEnv({
      DATABASE_URL: "postgres://soup:soup@localhost:5433/soup_identity",
      PUBLIC_BASE_URL: "http://localhost:8787",
      ALLOW_DEV_LOGIN: "false",
    });
    keys = await loadSigningKeys(
      env,
      `/tmp/soup-identity-oauth-test-${randomBytes(4).toString("hex")}`,
    );
  });

  it("round-trips user_code", async () => {
    const state = await signOAuthState(keys, env, "ABCD-EFGH");
    const decoded = await verifyOAuthState(keys, env, state);
    assert.equal(decoded.user_code, "ABCD-EFGH");
  });

  it("rejects forged base64 JSON state", async () => {
    const forged = Buffer.from(
      JSON.stringify({ user_code: "HACK-CODE", n: "x" }),
    ).toString("base64url");
    await assert.rejects(() => verifyOAuthState(keys, env, forged));
  });
});

describe("device-link auth hardening", () => {
  let db: Db;
  let app: ReturnType<typeof createApp>;
  let keys: SigningKeys;
  let env: ReturnType<typeof loadEnv>;
  const EMAIL = "device-link-auth@example.com";

  before(async () => {
    env = loadEnv({
      ...process.env,
      ALLOW_DEV_LOGIN: "false",
      DATABASE_URL:
        process.env.DATABASE_URL ??
        "postgres://soup:soup@localhost:5433/soup_identity",
      PUBLIC_BASE_URL: "http://localhost:8787",
    });
    db = createPool(env.DATABASE_URL);
    await applyMigrations(db);
    keys = await loadSigningKeys(
      env,
      `/tmp/soup-identity-device-link-test-${randomBytes(4).toString("hex")}`,
    );
    app = createApp({ db, env, keys });
  });

  after(async () => {
    await db.query(`DELETE FROM sessions WHERE email = $1`, [EMAIL]);
    await db.query(`DELETE FROM device_links WHERE email = $1`, [EMAIL]);
    await db.query(`DELETE FROM subjects WHERE email = $1`, [EMAIL]);
    await db.end();
  });

  it("rejects approve without link_token", async () => {
    const started = await startDeviceLink(db, env);
    const res = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        email: EMAIL,
      }),
    });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: string };
    assert.equal(body.error, "bad_request");
  });

  it("rejects approve with only a caller-supplied email (no proof)", async () => {
    const started = await startDeviceLink(db, env);
    const res = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        email: EMAIL,
        name: "Attacker",
      }),
    });
    assert.equal(res.status, 400);
  });

  it("approves with a valid link_token proof", async () => {
    const started = await startDeviceLink(db, env);
    const linkToken = await signDeviceLinkProof(keys, env, {
      email: EMAIL,
      googleSub: "google-sub-1",
      name: "Tester",
    });
    const res = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        link_token: linkToken,
      }),
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as { status: string; email: string };
    assert.equal(body.status, "approved");
    assert.equal(body.email, EMAIL);
  });

  it("rejects invalid link_token", async () => {
    const started = await startDeviceLink(db, env);
    const res = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        link_token: "not.a.jwt",
      }),
    });
    assert.equal(res.status, 401);
  });

  it("blocks /auth/dev/complete when ALLOW_DEV_LOGIN is false", async () => {
    const started = await startDeviceLink(db, env);
    const res = await app.request("/auth/dev/complete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        email: EMAIL,
      }),
    });
    assert.equal(res.status, 403);
  });

  it("only one concurrent poll receives tokens after approve", async () => {
    const started = await startDeviceLink(db, env);
    const linkToken = await signDeviceLinkProof(keys, env, {
      email: EMAIL,
      googleSub: "google-sub-2",
      name: "Tester",
    });
    const approve = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user_code: started.user_code,
        link_token: linkToken,
      }),
    });
    assert.equal(approve.status, 200);

    const [a, b] = await Promise.all([
      pollDeviceLink(db, keys, env, started.device_code),
      pollDeviceLink(db, keys, env, started.device_code),
    ]);
    const approved = [a, b].filter((r) => r.kind === "approved");
    const missing = [a, b].filter((r) => r.kind === "missing");
    assert.equal(approved.length, 1);
    assert.equal(missing.length, 1);
    assert.ok(approved[0] && "tokens" in approved[0]);
  });

  it("rejects forged OAuth state on Google callback", async () => {
    const forged = Buffer.from(
      JSON.stringify({ user_code: "FAKE-CODE", n: "x" }),
    ).toString("base64url");
    const res = await app.request(
      `/auth/google/callback?code=fake&state=${encodeURIComponent(forged)}`,
    );
    assert.equal(res.status, 400);
    const html = await res.text();
    assert.match(html, /Invalid sign-in state/i);
  });
});
