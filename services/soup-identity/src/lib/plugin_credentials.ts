import type { Db } from "../db/client.js";
import { randomToken, sha256 } from "./crypto.js";

const PLUGIN_ID = /^[a-z0-9][a-z0-9-]{1,38}$/;

export class PluginCredentialError extends Error {}

export type PluginCredentialRow = {
  plugin_id: string;
  label: string | null;
  created_at: Date;
  revoked_at: Date | null;
  servers: string[];
};

/** Creates a credential and returns its secret, which is only stored hashed. */
export async function issuePluginCredential(
  db: Db,
  pluginId: string,
  label?: string,
): Promise<string> {
  if (!PLUGIN_ID.test(pluginId)) {
    throw new PluginCredentialError(
      "Plugin id must be 2-39 lowercase letters, digits or hyphens.",
    );
  }
  const secret = randomToken(32);
  const { rowCount } = await db.query(
    `INSERT INTO plugin_credentials (plugin_id, secret_hash, label)
     VALUES ($1, $2, $3)
     ON CONFLICT (plugin_id) DO NOTHING`,
    [pluginId, sha256(secret), label ?? null],
  );
  if (!rowCount) {
    throw new PluginCredentialError(
      `${pluginId} already exists. Use rotate to replace its secret.`,
    );
  }
  return secret;
}

/** Replaces the secret, which also restores a revoked credential. */
export async function rotatePluginCredential(
  db: Db,
  pluginId: string,
): Promise<string> {
  const secret = randomToken(32);
  const { rowCount } = await db.query(
    `UPDATE plugin_credentials SET secret_hash = $2, revoked_at = NULL
     WHERE plugin_id = $1`,
    [pluginId, sha256(secret)],
  );
  if (!rowCount) throw new PluginCredentialError(`No credential named ${pluginId}.`);
  return secret;
}

/** Stops the plugin calling Soup. Its servers stay listed for their guests. */
export async function revokePluginCredential(
  db: Db,
  pluginId: string,
): Promise<void> {
  const { rowCount } = await db.query(
    `UPDATE plugin_credentials SET revoked_at = COALESCE(revoked_at, now())
     WHERE plugin_id = $1`,
    [pluginId],
  );
  if (!rowCount) throw new PluginCredentialError(`No credential named ${pluginId}.`);
}

export async function listPluginCredentials(
  db: Db,
): Promise<PluginCredentialRow[]> {
  const { rows } = await db.query<PluginCredentialRow>(
    `SELECT c.plugin_id, c.label, c.created_at, c.revoked_at,
            COALESCE(array_agg(s.server_id ORDER BY s.server_id)
              FILTER (WHERE s.server_id IS NOT NULL), '{}') AS servers
     FROM plugin_credentials c
     LEFT JOIN servers s ON s.plugin_id = c.plugin_id
     GROUP BY c.plugin_id
     ORDER BY c.created_at`,
  );
  return rows;
}
