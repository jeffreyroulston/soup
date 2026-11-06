import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { z } from "zod";

const bool = z
  .string()
  .optional()
  .transform((v) => v === "1" || v?.toLowerCase() === "true");

const schema = z.object({
  PORT: z.coerce.number().default(8787),
  PUBLIC_BASE_URL: z.string().url().default("http://localhost:8787"),
  DATABASE_URL: z
    .string()
    .default("postgres://soup:soup@localhost:5433/soup_identity"),
  GOOGLE_CLIENT_ID: z.string().optional().default(""),
  GOOGLE_CLIENT_SECRET: z.string().optional().default(""),
  GOOGLE_REDIRECT_URI: z
    .string()
    .optional()
    .default("http://localhost:8787/auth/google/callback"),
  DEV_GOOGLE_EMAIL: z.string().email().default("dev@example.com"),
  ALLOW_DEV_LOGIN: bool.default("false"),
  JWT_ALG: z.enum(["EdDSA", "RS256"]).default("RS256"),
  JWT_PRIVATE_KEY_PEM: z.string().optional().default(""),
  JWT_PUBLIC_KEY_PEM: z.string().optional().default(""),
  ASSERTION_TTL_SECONDS: z.coerce.number().min(120).max(300).default(180),
  ASSERTION_ISSUER: z.string().default("https://soup.local/identity"),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().default(90),
  BOOTSTRAP_PLUGIN_ID: z.string().optional().default(""),
  BOOTSTRAP_PLUGIN_SECRET: z.string().optional().default(""),
  /** 32-byte AES key as 64 hex chars or base64; required to seal transport grants */
  TRANSPORT_GRANT_ENCRYPTION_KEY: z
    .string()
    .optional()
    .default(
      // Dev-only default (not for production). Override via env.
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ),
});

export type Env = z.infer<typeof schema> & {
  googleConfigured: boolean;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.parse(source);
  return {
    ...parsed,
    googleConfigured: Boolean(
      parsed.GOOGLE_CLIENT_ID && parsed.GOOGLE_CLIENT_SECRET,
    ),
  };
}

export function loadDotEnv(file = path.join(process.cwd(), ".env")) {
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq < 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}
