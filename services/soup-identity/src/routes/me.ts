import { Hono, type Context, type Next } from "hono";
import type { Db } from "../db/client.js";
import type { Env } from "../env.js";
import { signAssertion, type SigningKeys } from "../lib/crypto.js";
import { createSoupAuth, type AppEnv } from "../middleware/auth.js";
import { claimTransportGrant } from "../lib/transport_grants.js";
import { parseEncryptionKey } from "../lib/secret_box.js";
import {
  isSessionActive,
  listSessions,
  normalizeDeviceName,
  renameSession,
  revokeOtherSessions,
  revokeSessionById,
} from "../auth/sessions.js";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function buildMeRoutes(deps: {
  db: Db;
  env: Env;
  keys: SigningKeys;
}) {
  const app = new Hono<AppEnv>();
  const requireSoup = createSoupAuth(deps);
  const encryptionKey = parseEncryptionKey(deps.env.TRANSPORT_GRANT_ENCRYPTION_KEY);

  app.get("/v1/me", requireSoup, async (c) => {
    const email = c.get("email");
    const { rows } = await deps.db.query<{
      email: string;
      name: string | null;
      picture_url: string | null;
    }>(
      `SELECT email, name, picture_url FROM subjects WHERE email = $1`,
      [email],
    );
    const row = rows[0];
    if (!row) {
      return c.json({ email });
    }
    return c.json({
      email: row.email,
      name: row.name,
      picture_url: row.picture_url,
    });
  });

  app.get("/v1/me/servers", requireSoup, async (c) => {
    const email = c.get("email");
    const { rows } = await deps.db.query<{
      server_id: string;
      name: string;
      base_url: string | null;
      magic_dns: string | null;
      audience: string;
      display_name: string | null;
      jellyfin_user_hint: string | null;
      metadata: Record<string, unknown>;
    }>(
      `SELECT s.server_id, s.name, s.base_url, s.magic_dns, s.audience,
              e.display_name, e.jellyfin_user_hint, e.metadata
       FROM entitlements e
       JOIN servers s ON s.server_id = e.server_id
       WHERE e.email = $1
       ORDER BY s.name ASC`,
      [email],
    );

    const servers = [];
    for (const r of rows) {
      const transportGrant = await claimTransportGrant(
        deps.db,
        encryptionKey,
        r.server_id,
        email,
      );
      servers.push({
        id: r.server_id,
        name: r.name,
        base_url: r.base_url,
        magic_dns: r.magic_dns,
        audience: r.audience,
        entitlement: {
          display_name: r.display_name,
          jellyfin_user_hint: r.jellyfin_user_hint,
          metadata: r.metadata,
        },
        transport_grant: transportGrant,
      });
    }

    return c.json({ servers });
  });

  app.post(
    "/v1/me/servers/:serverId/transport-grant/claim",
    requireSoup,
    async (c) => {
      const email = c.get("email");
      const serverId = c.req.param("serverId")!;

      const { rows: entRows } = await deps.db.query(
        `SELECT 1 FROM entitlements WHERE server_id = $1 AND email = $2`,
        [serverId, email],
      );
      if (!entRows[0]) {
        return c.json(
          { error: "forbidden", message: "Not entitled to this server" },
          403,
        );
      }

      const grant = await claimTransportGrant(
        deps.db,
        encryptionKey,
        serverId,
        email,
      );
      if (!grant) {
        return c.json(
          {
            error: "gone",
            message: "No claimable transport grant (expired, claimed, or missing)",
          },
          410,
        );
      }
      return c.json({ transport_grant: grant });
    },
  );

  // Device management needs to know which session is asking, and a device that
  // was just signed out mustn't keep managing the others until its token expires.
  const requireLiveSession = async (
    c: Context<AppEnv>,
    next: Next,
  ) => {
    const sessionId = c.get("sessionId");
    if (!sessionId || !(await isSessionActive(deps.db, c.get("email"), sessionId))) {
      return c.json(
        { error: "unauthorized", message: "Session is no longer active" },
        401,
      );
    }
    await next();
  };

  app.get("/v1/me/sessions", requireSoup, requireLiveSession, async (c) => {
    const sessions = await listSessions(
      deps.db,
      c.get("email"),
      c.get("sessionId"),
    );
    return c.json({ sessions });
  });

  app.patch("/v1/me/sessions/:id", requireSoup, requireLiveSession, async (c) => {
    const id = c.req.param("id")!;
    const body = await c.req.json<{ device_name?: unknown }>().catch(() => null);
    if (!body || !("device_name" in body)) {
      return c.json({ error: "bad_request", message: "device_name required" }, 400);
    }
    const renamed =
      UUID_RE.test(id) &&
      (await renameSession(
        deps.db,
        c.get("email"),
        id,
        normalizeDeviceName(body.device_name),
      ));
    if (!renamed) {
      return c.json({ error: "not_found", message: "Unknown session" }, 404);
    }
    return c.body(null, 204);
  });

  app.delete("/v1/me/sessions/:id", requireSoup, requireLiveSession, async (c) => {
    const id = c.req.param("id")!;
    const revoked =
      UUID_RE.test(id) && (await revokeSessionById(deps.db, c.get("email"), id));
    if (!revoked) {
      return c.json({ error: "not_found", message: "Unknown session" }, 404);
    }
    return c.body(null, 204);
  });

  app.post(
    "/v1/me/sessions/revoke-others",
    requireSoup,
    requireLiveSession,
    async (c) => {
      const revoked = await revokeOtherSessions(
        deps.db,
        c.get("email"),
        c.get("sessionId")!,
      );
      return c.json({ revoked });
    },
  );

  app.post("/v1/assertions", requireSoup, async (c) => {
    const email = c.get("email");
    const body = await c.req.json<{ server_id: string }>();
    if (!body.server_id) {
      return c.json({ error: "bad_request", message: "server_id required" }, 400);
    }

    const { rows: serverRows } = await deps.db.query<{
      server_id: string;
      audience: string;
    }>(`SELECT server_id, audience FROM servers WHERE server_id = $1`, [
      body.server_id,
    ]);
    const server = serverRows[0];
    if (!server) {
      return c.json({ error: "not_found", message: "Unknown server" }, 404);
    }

    const { rows: entRows } = await deps.db.query(
      `SELECT 1 FROM entitlements WHERE server_id = $1 AND email = $2`,
      [body.server_id, email],
    );
    if (!entRows[0]) {
      return c.json(
        { error: "forbidden", message: "Not entitled to this server" },
        403,
      );
    }

    const minted = await signAssertion(deps.keys, deps.env, {
      email,
      audience: server.audience,
      serverId: server.server_id,
    });

    return c.json({
      assertion: minted.assertion,
      expires_in: minted.expiresIn,
      server_id: server.server_id,
      audience: server.audience,
    });
  });

  return app;
}
