import type { Env } from "../env.js";

/**
 * Sign-in methods offered on the /link page. Each provider owns a browser start
 * route that takes `user_code` and ends by approving the device link. Add new
 * social logins here (plus their start/callback routes).
 */
export type LinkProvider = {
  id: string;
  label: string;
  /** Path (relative to PUBLIC_BASE_URL) that begins sign-in for `userCode`. */
  startPath(userCode: string): string;
};

export function linkProviders(env: Env): LinkProvider[] {
  const providers: LinkProvider[] = [];
  if (env.googleConfigured) {
    providers.push({
      id: "google",
      label: "Continue with Google",
      startPath: (code) => `/auth/google/start?user_code=${encodeURIComponent(code)}`,
    });
  }
  if (env.ALLOW_DEV_LOGIN) {
    providers.push({
      id: "dev",
      label: "Dev sign-in",
      startPath: (code) => `/auth/dev/start?user_code=${encodeURIComponent(code)}`,
    });
  }
  return providers;
}
