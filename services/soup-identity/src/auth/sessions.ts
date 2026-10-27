import type { Env } from "../env.js";
import type { Db } from "../db/client.js";
import {
  randomToken,
  randomUserCode,
  sha256,
  signAccessToken,
  type SigningKeys,
} from "../lib/crypto.js";

const DEVICE_LINK_TTL_SECONDS = 600;
const DEVICE_FIELD_MAX = 64;
const PLATFORMS = new Set(["webos", "android", "android_tv", "web", "ios"]);

/** What a client says about itself when it starts a device link. */
export type DeviceInfo = {
  deviceName: string | null;
  platform: string | null;
  clientVersion: string | null;
};

function cleanField(value: unknown): string | null {
  if (typeof value !== "string") return null;
  // Control characters never belong in a label shown back to the user.
  const trimmed = value.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return trimmed ? trimmed.slice(0, DEVICE_FIELD_MAX) : null;
}

/** Normalize client-supplied device fields; anything unexpected becomes null. */
export function parseDeviceInfo(raw: unknown): DeviceInfo {
  const body = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const platform = cleanField(body.platform)?.toLowerCase() ?? null;
  return {
    deviceName: cleanField(body.device_name),
    platform: platform && PLATFORMS.has(platform) ? platform : null,
    clientVersion: cleanField(body.client_version),
  };
}

export function normalizeDeviceName(raw: unknown): string | null {
  return cleanField(raw);
}

/** Normalize Google email for join keys (lowercase trimmed). */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function isValidEmail(email: string): boolean {
  const e = normalizeEmail(email);
  // Practical check — Google emails are well-formed; reject empty / no-at.
  return e.length > 3 && e.includes("@") && !e.includes(" ");
}

/**
 * Normalize a typed TV code: uppercase, ignore spaces/dashes, re-insert the
 * XXXX-XXXX dash. Anything that isn't 8 characters is returned uppercased as-is
 * so lookups simply miss.
 */
export function normalizeUserCode(raw: string): string {
  const compact = raw.toUpperCase().replace(/[\s-]/g, "");
  if (compact.length !== 8) return raw.trim().toUpperCase();
  return `${compact.slice(0, 4)}-${compact.slice(4)}`;
}

export async function upsertSubject(
  db: Db,
  subject: {
    email: string;
    googleSub?: string | null;
    name?: string | null;
    pictureUrl?: string | null;
  },
) {
  const email = normalizeEmail(subject.email);
  if (!isValidEmail(email)) {
    throw new Error("A verified Google email is required");
  }
  await db.query(
    `INSERT INTO subjects (email, google_sub, name, picture_url)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (email) DO UPDATE SET
       google_sub = COALESCE(EXCLUDED.google_sub, subjects.google_sub),
       name = COALESCE(EXCLUDED.name, subjects.name),
       picture_url = COALESCE(EXCLUDED.picture_url, subjects.picture_url),
       updated_at = now()`,
    [
      email,
      subject.googleSub ?? null,
      subject.name ?? null,
      subject.pictureUrl ?? null,
    ],
  );
  return email;
}

export async function createSession(
  db: Db,
  keys: SigningKeys,
  env: Env,
  input: { email: string; device?: DeviceInfo },
) {
  const email = normalizeEmail(input.email);
  const refreshToken = randomToken(48);
  const expiresAt = new Date(
    Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
  );
  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO sessions
      (email, refresh_token_hash, device_name, platform, client_version, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [
      email,
      sha256(refreshToken),
      input.device?.deviceName ?? null,
      input.device?.platform ?? null,
      input.device?.clientVersion ?? null,
      expiresAt,
    ],
  );
  const access = await signAccessToken(keys, env, {
    email,
    sessionId: rows[0]!.id,
  });
  return {
    access_token: access.token,
    refresh_token: refreshToken,
    expires_in: access.expiresIn,
    token_type: "Bearer" as const,
    email,
  };
}

export async function refreshSession(
  db: Db,
  keys: SigningKeys,
  env: Env,
  refreshToken: string,
) {
  const hash = sha256(refreshToken);
  const { rows } = await db.query<{
    id: string;
    email: string;
    expires_at: Date;
    revoked_at: Date | null;
  }>(
    `SELECT s.id, s.email, s.expires_at, s.revoked_at
     FROM sessions s
     WHERE s.refresh_token_hash = $1`,
    [hash],
  );
  const row = rows[0];
  if (!row || row.revoked_at || row.expires_at.getTime() < Date.now()) {
    return null;
  }

  const newRefresh = randomToken(48);
  const expiresAt = new Date(
    Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
  );
  await db.query(
    `UPDATE sessions
     SET refresh_token_hash = $1, expires_at = $2, last_used_at = now()
     WHERE id = $3`,
    [sha256(newRefresh), expiresAt, row.id],
  );

  const access = await signAccessToken(keys, env, {
    email: row.email,
    sessionId: row.id,
  });
  return {
    access_token: access.token,
    refresh_token: newRefresh,
    expires_in: access.expiresIn,
    token_type: "Bearer" as const,
    email: row.email,
  };
}

export async function revokeSession(db: Db, refreshToken: string) {
  await db.query(
    `UPDATE sessions SET revoked_at = now()
     WHERE refresh_token_hash = $1 AND revoked_at IS NULL`,
    [sha256(refreshToken)],
  );
}

export async function startDeviceLink(db: Db, env: Env, device?: DeviceInfo) {
  const deviceCode = randomToken(32);
  const userCode = randomUserCode();
  const expiresAt = new Date(Date.now() + DEVICE_LINK_TTL_SECONDS * 1000);
  const verificationUri = `${env.PUBLIC_BASE_URL}/link`;
  await db.query(
    `INSERT INTO device_links
      (device_code, user_code, verification_uri, interval_seconds, expires_at, status,
       device_name, platform, client_version)
     VALUES ($1, $2, $3, 5, $4, 'pending', $5, $6, $7)`,
    [
      deviceCode,
      userCode,
      verificationUri,
      expiresAt,
      device?.deviceName ?? null,
      device?.platform ?? null,
      device?.clientVersion ?? null,
    ],
  );
  return {
    device_code: deviceCode,
    user_code: userCode,
    verification_uri: verificationUri,
    verification_uri_complete: `${verificationUri}?user_code=${encodeURIComponent(userCode)}`,
    expires_in: DEVICE_LINK_TTL_SECONDS,
    interval: 5,
  };
}

export async function pollDeviceLink(
  db: Db,
  keys: SigningKeys,
  env: Env,
  deviceCode: string,
) {
  const { rows } = await db.query<{
    status: string;
    expires_at: Date;
    email: string | null;
  }>(
    `SELECT d.status, d.expires_at, d.email
     FROM device_links d
     WHERE d.device_code = $1`,
    [deviceCode],
  );
  const row = rows[0];
  if (!row) return { kind: "missing" as const };
  if (row.status === "consumed") return { kind: "missing" as const };

  if (row.expires_at.getTime() < Date.now() && row.status === "pending") {
    await db.query(
      `UPDATE device_links SET status = 'expired' WHERE device_code = $1`,
      [deviceCode],
    );
    return { kind: "expired" as const };
  }

  if (row.status === "expired") return { kind: "expired" as const };
  if (row.status === "pending") return { kind: "pending" as const };

  if (row.status === "approved" && row.email) {
    // Claim first so concurrent polls cannot mint two sessions.
    const claimed = await db.query<{
      email: string;
      device_name: string | null;
      platform: string | null;
      client_version: string | null;
    }>(
      `UPDATE device_links
       SET status = 'consumed'
       WHERE device_code = $1 AND status = 'approved' AND email IS NOT NULL
       RETURNING email, device_name, platform, client_version`,
      [deviceCode],
    );
    const link = claimed.rows[0];
    if (!link) return { kind: "missing" as const };

    const tokens = await createSession(db, keys, env, {
      email: link.email,
      device: {
        deviceName: link.device_name,
        platform: link.platform,
        clientVersion: link.client_version,
      },
    });
    return { kind: "approved" as const, tokens };
  }

  return { kind: "pending" as const };
}

/** Check a TV code before sending the browser off to a sign-in provider. */
export async function checkDeviceLinkCode(db: Db, userCode: string) {
  const { rows } = await db.query<{
    status: string;
    expires_at: Date;
    device_name: string | null;
    platform: string | null;
  }>(
    `SELECT status, expires_at, device_name, platform
     FROM device_links WHERE user_code = $1`,
    [normalizeUserCode(userCode)],
  );
  const row = rows[0];
  if (!row) return { ok: false as const, reason: "not_found" as const };
  if (row.expires_at.getTime() < Date.now() || row.status !== "pending") {
    return { ok: false as const, reason: "invalid" as const };
  }
  return {
    ok: true as const,
    deviceName: row.device_name,
    platform: row.platform,
  };
}

export async function approveDeviceLink(
  db: Db,
  input: {
    userCode: string;
    email: string;
    googleSub?: string | null;
    name?: string | null;
  },
) {
  const email = await upsertSubject(db, {
    email: input.email,
    googleSub: input.googleSub,
    name: input.name,
  });

  const { rows } = await db.query<{
    device_code: string;
    status: string;
    expires_at: Date;
  }>(`SELECT device_code, status, expires_at FROM device_links WHERE user_code = $1`, [
    normalizeUserCode(input.userCode),
  ]);
  const row = rows[0];
  if (!row) return { ok: false as const, reason: "not_found" };
  if (row.expires_at.getTime() < Date.now() || row.status !== "pending") {
    return { ok: false as const, reason: "invalid" };
  }

  await db.query(
    `UPDATE device_links
     SET status = 'approved', email = $1
     WHERE device_code = $2`,
    [email, row.device_code],
  );
  return { ok: true as const, email };
}

/** A signed-in device as the user sees it in their device list. */
export type SessionSummary = {
  id: string;
  device_name: string | null;
  platform: string | null;
  client_version: string | null;
  created_at: Date;
  last_used_at: Date;
  current: boolean;
};

const ACTIVE_SESSION = `revoked_at IS NULL AND expires_at > now()`;

/** Is this session still live? Revoked devices keep a valid access token briefly. */
export async function isSessionActive(db: Db, email: string, sessionId: string) {
  const { rows } = await db.query(
    `SELECT 1 FROM sessions WHERE id = $1 AND email = $2 AND ${ACTIVE_SESSION}`,
    [sessionId, email],
  );
  return rows.length > 0;
}

export async function listSessions(
  db: Db,
  email: string,
  currentSessionId: string | null,
): Promise<SessionSummary[]> {
  const { rows } = await db.query<Omit<SessionSummary, "current">>(
    `SELECT id, device_name, platform, client_version, created_at, last_used_at
     FROM sessions
     WHERE email = $1 AND ${ACTIVE_SESSION}
     ORDER BY last_used_at DESC`,
    [email],
  );
  return rows.map((r) => ({ ...r, current: r.id === currentSessionId }));
}

/** Rename one of the user's devices; false when it isn't theirs or is gone. */
export async function renameSession(
  db: Db,
  email: string,
  sessionId: string,
  deviceName: string | null,
) {
  const { rowCount } = await db.query(
    `UPDATE sessions SET device_name = $3
     WHERE id = $1 AND email = $2 AND ${ACTIVE_SESSION}`,
    [sessionId, email, deviceName],
  );
  return (rowCount ?? 0) > 0;
}

/** Sign one of the user's devices out; false when it isn't theirs or is gone. */
export async function revokeSessionById(db: Db, email: string, sessionId: string) {
  const { rowCount } = await db.query(
    `UPDATE sessions SET revoked_at = now()
     WHERE id = $1 AND email = $2 AND ${ACTIVE_SESSION}`,
    [sessionId, email],
  );
  return (rowCount ?? 0) > 0;
}

/** Sign out every device except the one making the request. */
export async function revokeOtherSessions(
  db: Db,
  email: string,
  keepSessionId: string,
) {
  const { rowCount } = await db.query(
    `UPDATE sessions SET revoked_at = now()
     WHERE email = $1 AND id <> $2 AND ${ACTIVE_SESSION}`,
    [email, keepSessionId],
  );
  return rowCount ?? 0;
}

export function googleAuthUrl(env: Env, state: string): string {
  const params = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: env.GOOGLE_REDIRECT_URI,
    response_type: "code",
    scope: "openid email profile",
    access_type: "online",
    include_granted_scopes: "true",
    state,
    prompt: "select_account",
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

export type GoogleProfile = {
  sub: string;
  email: string;
  email_verified?: boolean;
  name?: string;
  picture?: string;
};

export async function exchangeGoogleCode(
  env: Env,
  code: string,
): Promise<GoogleProfile> {
  const body = new URLSearchParams({
    code,
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    redirect_uri: env.GOOGLE_REDIRECT_URI,
    grant_type: "authorization_code",
  });
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!tokenRes.ok) {
    const text = await tokenRes.text();
    throw new Error(`Google token exchange failed: ${tokenRes.status} ${text}`);
  }
  const tokens = (await tokenRes.json()) as {
    access_token: string;
    id_token?: string;
  };
  const userRes = await fetch(
    "https://openidconnect.googleapis.com/v1/userinfo",
    {
      headers: { authorization: `Bearer ${tokens.access_token}` },
    },
  );
  if (!userRes.ok) {
    throw new Error(`Google userinfo failed: ${userRes.status}`);
  }
  const profile = (await userRes.json()) as {
    sub: string;
    email?: string;
    email_verified?: boolean;
    name?: string;
    picture?: string;
  };
  if (!profile.email || !isValidEmail(profile.email)) {
    throw new Error("Google account has no usable email");
  }
  if (profile.email_verified === false) {
    throw new Error("Google email is not verified");
  }
  return {
    sub: profile.sub,
    email: normalizeEmail(profile.email),
    email_verified: profile.email_verified,
    name: profile.name,
    picture: profile.picture,
  };
}

