// Manages the credentials that let a Jellyfin plugin use this Soup Identity.
// Run from services/soup-identity, on the server that hosts it:
//   node dist/db/plugin_credentials.js issue <plugin-id> [label]
import { loadDotEnv, loadEnv, type Env } from "../env.js";
import {
  issuePluginCredential,
  listPluginCredentials,
  PluginCredentialError,
  revokePluginCredential,
  rotatePluginCredential,
} from "../lib/plugin_credentials.js";
import { createPool } from "./client.js";

const USAGE = `Usage: plugin_credentials <command>

  issue <plugin-id> [label]  Create a credential and print the plugin settings
  rotate <plugin-id>         Replace a secret; the old one stops working
  revoke <plugin-id>         Stop this plugin calling Soup Identity
  list                       Show credentials and their servers`;

function printSettings(env: Env, pluginId: string, secret: string) {
  console.log(`Enter these in Jellyfin under Dashboard → Soup Invites → Settings.
Send them privately: the secret can't be shown again.

  Soup base URL:              ${env.PUBLIC_BASE_URL}
  Plugin credential id:       ${pluginId}
  Plugin credential secret:   ${secret}
  Soup server id:             ${pluginId}
  Assertion audience:         jellyfin:${pluginId}
  Assertion issuer:           ${env.ASSERTION_ISSUER}`);
}

/** Startup resets the bootstrap credential from .env, undoing any change here. */
function refuseBootstrap(env: Env, pluginId: string) {
  if (pluginId === env.BOOTSTRAP_PLUGIN_ID) {
    throw new PluginCredentialError(
      `${pluginId} comes from BOOTSTRAP_PLUGIN_* in .env and is reset on every restart. Change it there.`,
    );
  }
}

async function main() {
  loadDotEnv();
  const env = loadEnv();
  const [command, pluginId, label] = process.argv.slice(2);
  if (command !== "list" && !pluginId) {
    console.error(USAGE);
    process.exitCode = 1;
    return;
  }

  const db = createPool(env.DATABASE_URL);
  try {
    switch (command) {
      case "issue":
        printSettings(env, pluginId, await issuePluginCredential(db, pluginId, label));
        break;
      case "rotate":
        refuseBootstrap(env, pluginId);
        printSettings(env, pluginId, await rotatePluginCredential(db, pluginId));
        break;
      case "revoke":
        refuseBootstrap(env, pluginId);
        await revokePluginCredential(db, pluginId);
        console.log(`Revoked ${pluginId}.`);
        break;
      case "list":
        for (const row of await listPluginCredentials(db)) {
          const status = row.revoked_at ? "revoked" : "active";
          const servers = row.servers.join(", ") || "no servers";
          console.log(`${row.plugin_id}  ${status}  ${row.label ?? "-"}  ${servers}`);
        }
        break;
      default:
        console.error(USAGE);
        process.exitCode = 1;
    }
  } finally {
    await db.end();
  }
}

main().catch((error) => {
  console.error(error instanceof PluginCredentialError ? error.message : error);
  process.exitCode = 1;
});
