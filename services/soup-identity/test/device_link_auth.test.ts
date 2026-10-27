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
import {
  normalizeUserCode,
  pollDeviceLink,
  startDeviceLink,
} from "../src/auth/sessions.js";

describe("normalizeUserCode", () => {
  it("accepts lowercase, spaces and missing dash", () => {
    assert.equal(normalizeUserCode("abcd efgh"), "ABCD-EFGH");
    assert.equal(normalizeUserCode(" abcdefgh "), "ABCD-EFGH");
    assert.equal(normalizeUserCode("ABCD-EFGH"), "ABCD-EFGH");
    assert.equal(normalizeUserCode("abc"), "ABC");
  });
});

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

describe("/link page", () => {
  let db: Db;
  let app: ReturnType<typeof createApp>;
  let env: ReturnType<typeof loadEnv>;

  before(async () => {
    env = loadEnv({
      ...process.env,
      ALLOW_DEV_LOGIN: "false",
      GOOGLE_CLIENT_ID: "test-client.apps.googleusercontent.com",
      GOOGLE_CLIENT_SECRET: "test-secret",
      DATABASE_URL:
        process.env.DATABASE_URL ??
        "postgres://soup:soup@localhost:5433/soup_identity",
      PUBLIC_BASE_URL: "http://localhost:8787",
    });
    db = createPool(env.DATABASE_URL);
    await applyMigrations(db);
    const keys = await loadSigningKeys(
      env,
      `/tmp/soup-identity-link-page-test-${randomBytes(4).toString("hex")}`,
    );
    app = createApp({ db, env, keys });
  });

  after(async () => {
    await db.end();
  });

  const post = (fields: Record<string, string>) =>
    app.request("/link", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(fields).toString(),
    });

  it("device link points the TV QR at /link", async () => {
    const started = await startDeviceLink(db, env);
    assert.equal(started.verification_uri, "http://localhost:8787/link");
    assert.match(started.verification_uri_complete, /\/link\?user_code=/);
  });

  it("renders Google with the code prefilled", async () => {
    const started = await startDeviceLink(db, env);
    const res = await app.request(
      `/link?user_code=${encodeURIComponent(started.user_code.toLowerCase())}`,
    );
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.match(html, /Continue with Google/);
    assert.match(html, new RegExp(`value="${started.user_code}"`));
  });

  it("flags an unknown code on GET", async () => {
    const res = await app.request("/link?user_code=ZZZZ-ZZZZ");
    assert.equal(res.status, 400);
    assert.match(await res.text(), /wasn’t found/);
  });

  it("redirects a valid code to the provider start route", async () => {
    const started = await startDeviceLink(db, env);
    const res = await post({
      user_code: started.user_code.replace("-", "").toLowerCase(),
      provider: "google",
    });
    assert.equal(res.status, 303);
    assert.equal(
      res.headers.get("location"),
      `/auth/google/start?user_code=${encodeURIComponent(started.user_code)}`,
    );
  });

  it("rejects expired codes without leaving the page", async () => {
    const started = await startDeviceLink(db, env);
    await db.query(
      `UPDATE device_links SET expires_at = now() - interval '1 minute' WHERE device_code = $1`,
      [started.device_code],
    );
    const res = await post({ user_code: started.user_code, provider: "google" });
    assert.equal(res.status, 400);
    assert.match(await res.text(), /expired or was already used/);
  });

  it("rejects providers that aren't enabled", async () => {
    const started = await startDeviceLink(db, env);
    const res = await post({ user_code: started.user_code, provider: "dev" });
    assert.equal(res.status, 400);
    assert.match(await res.text(), /Choose a sign-in method/);
  });
});

describe("device sessions", () => {
  let db: Db;
  let app: ReturnType<typeof createApp>;
  let keys: SigningKeys;
  let env: ReturnType<typeof loadEnv>;
  const EMAIL = "device-sessions@example.com";
  const OTHER = "device-sessions-other@example.com";

  before(async () => {
    env = loadEnv({
      ...process.env,
      ALLOW_DEV_LOGIN: "false",
      GOOGLE_CLIENT_ID: "test-client.apps.googleusercontent.com",
      GOOGLE_CLIENT_SECRET: "test-secret",
      DATABASE_URL:
        process.env.DATABASE_URL ??
        "postgres://soup:soup@localhost:5433/soup_identity",
      PUBLIC_BASE_URL: "http://localhost:8787",
    });
    db = createPool(env.DATABASE_URL);
    await applyMigrations(db);
    keys = await loadSigningKeys(
      env,
      `/tmp/soup-identity-sessions-test-${randomBytes(4).toString("hex")}`,
    );
    app = createApp({ db, env, keys });
  });

  after(async () => {
    for (const email of [EMAIL, OTHER]) {
      await db.query(`DELETE FROM sessions WHERE email = $1`, [email]);
      await db.query(`DELETE FROM device_links WHERE email = $1`, [email]);
      await db.query(`DELETE FROM subjects WHERE email = $1`, [email]);
    }
    await db.end();
  });

  type Tokens = { access_token: string; refresh_token: string };

  /** Run the whole TV flow: start with device info, approve, poll for tokens. */
  async function linkDevice(email: string, device?: Record<string, unknown>) {
    const startRes = await app.request("/auth/device/link", {
      method: "POST",
      ...(device
        ? {
            headers: { "content-type": "application/json" },
            body: JSON.stringify(device),
          }
        : {}),
    });
    assert.equal(startRes.status, 200);
    const started = (await startRes.json()) as {
      device_code: string;
      user_code: string;
    };
    const linkToken = await signDeviceLinkProof(keys, env, {
      email,
      googleSub: null,
      name: null,
    });
    const approve = await app.request("/auth/device/approve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ user_code: started.user_code, link_token: linkToken }),
    });
    assert.equal(approve.status, 200);
    const poll = await app.request(`/auth/device/link/${started.device_code}`);
    return (await poll.json()) as Tokens;
  }

  const authed = (tokens: Tokens, path: string, init: RequestInit = {}) =>
    app.request(path, {
      ...init,
      headers: {
        ...(init.headers as Record<string, string> | undefined),
        authorization: `Bearer ${tokens.access_token}`,
      },
    });

  type Listed = {
    sessions: {
      id: string;
      device_name: string | null;
      platform: string | null;
      client_version: string | null;
      current: boolean;
    }[];
  };

  const list = async (tokens: Tokens) => {
    const res = await authed(tokens, "/v1/me/sessions");
    assert.equal(res.status, 200);
    return ((await res.json()) as Listed).sessions;
  };

  it("carries device info from the link into the session", async () => {
    const tv = await linkDevice(EMAIL, {
      device_name: "  Living room\u0007 TV ",
      platform: "webOS",
      client_version: "2.4.0",
    });
    const sessions = await list(tv);
    const me = sessions.find((s) => s.current);
    assert.ok(me);
    assert.equal(me.device_name, "Living room TV");
    assert.equal(me.platform, "webos");
    assert.equal(me.client_version, "2.4.0");
  });

  it("still links clients that send no device info", async () => {
    const tokens = await linkDevice(EMAIL);
    const me = (await list(tokens)).find((s) => s.current);
    assert.ok(me);
    assert.equal(me.device_name, null);
    assert.equal(me.platform, null);
  });

  it("drops unknown platforms", async () => {
    const tokens = await linkDevice(EMAIL, { platform: "toaster" });
    const me = (await list(tokens)).find((s) => s.current);
    assert.equal(me?.platform, null);
  });

  it("names the device on the /link approval page", async () => {
    const res = await app.request("/auth/device/link", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ device_name: "<b>Den</b>", platform: "android_tv" }),
    });
    const started = (await res.json()) as { user_code: string };
    const page = await app.request(
      `/link?user_code=${encodeURIComponent(started.user_code)}`,
    );
    const html = await page.text();
    assert.match(html, /Linking <strong>&lt;b&gt;Den&lt;\/b&gt; \(Android TV\)<\/strong>/);
  });

  it("only lists the caller's own active sessions", async () => {
    const mine = await linkDevice(EMAIL, { device_name: "Mine" });
    const theirs = await linkDevice(OTHER, { device_name: "Theirs" });
    const ids = new Set((await list(mine)).map((s) => s.id));
    const otherIds = (await list(theirs)).map((s) => s.id);
    assert.ok(otherIds.every((id) => !ids.has(id)));
    assert.equal((await list(mine)).filter((s) => s.current).length, 1);
  });

  it("keeps the session id when a token is refreshed", async () => {
    const tokens = await linkDevice(EMAIL, { device_name: "Refresher" });
    const before = (await list(tokens)).find((s) => s.current)!.id;
    const res = await app.request("/v1/sessions/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: tokens.refresh_token }),
    });
    const refreshed = (await res.json()) as Tokens;
    const after = (await list(refreshed)).find((s) => s.current)!.id;
    assert.equal(after, before);
  });

  it("renames a device", async () => {
    const tokens = await linkDevice(EMAIL, { device_name: "Old name" });
    const id = (await list(tokens)).find((s) => s.current)!.id;
    const res = await authed(tokens, `/v1/me/sessions/${id}`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ device_name: "Bedroom TV" }),
    });
    assert.equal(res.status, 204);
    const me = (await list(tokens)).find((s) => s.id === id);
    assert.equal(me?.device_name, "Bedroom TV");
  });

  it("404s on another user's session and on malformed ids", async () => {
    const mine = await linkDevice(EMAIL);
    const theirs = await linkDevice(OTHER);
    const theirId = (await list(theirs)).find((s) => s.current)!.id;
    for (const id of [theirId, "not-a-uuid"]) {
      const del = await authed(mine, `/v1/me/sessions/${id}`, { method: "DELETE" });
      assert.equal(del.status, 404);
      const patch = await authed(mine, `/v1/me/sessions/${id}`, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ device_name: "Hijacked" }),
      });
      assert.equal(patch.status, 404);
    }
    assert.ok((await list(theirs)).some((s) => s.id === theirId));
  });

  it("revoking a device blocks its refresh and its device management", async () => {
    const phone = await linkDevice(EMAIL, { device_name: "Phone" });
    const tv = await linkDevice(EMAIL, { device_name: "TV" });
    const tvId = (await list(tv)).find((s) => s.current)!.id;

    const del = await authed(phone, `/v1/me/sessions/${tvId}`, { method: "DELETE" });
    assert.equal(del.status, 204);
    assert.ok(!(await list(phone)).some((s) => s.id === tvId));

    const refresh = await app.request("/v1/sessions/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: tv.refresh_token }),
    });
    assert.equal(refresh.status, 401);
    // Its access token is still valid for a few minutes, but not for this.
    const stale = await authed(tv, "/v1/me/sessions");
    assert.equal(stale.status, 401);
  });

  it("revoke-others keeps only the current device", async () => {
    await linkDevice(EMAIL, { device_name: "A" });
    await linkDevice(EMAIL, { device_name: "B" });
    const keeper = await linkDevice(EMAIL, { device_name: "Keeper" });
    const res = await authed(keeper, "/v1/me/sessions/revoke-others", {
      method: "POST",
    });
    assert.equal(res.status, 200);
    assert.ok(((await res.json()) as { revoked: number }).revoked >= 2);
    const left = await list(keeper);
    assert.equal(left.length, 1);
    assert.equal(left[0]!.device_name, "Keeper");
    assert.equal(left[0]!.current, true);
  });
});
