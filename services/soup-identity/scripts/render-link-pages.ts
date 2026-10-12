/**
 * Writes the device-link browser pages as static HTML for README screenshots.
 * Usage: npx tsx scripts/render-link-pages.ts <out-dir>
 * Codes and emails are fixtures; no server or database is involved.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  deviceLinkEnterCode,
  deviceLinkStart,
  deviceLinkSuccess,
} from "../src/lib/device_link_html.js";

const outDir = process.argv[2] ?? "link-pages";
mkdirSync(outDir, { recursive: true });

const google = [{ id: "google", label: "Continue with Google" }];
const pages: Record<string, string> = {
  "link-code": deviceLinkStart({ userCode: "VEWR-37AY", providers: google }),
  "link-expired": deviceLinkStart({
    userCode: "VEWR-37AY",
    providers: google,
    errorHtml: "That code has expired or was already used. Get a new code on the TV.",
  }),
  "enter-code": deviceLinkEnterCode({
    identity: "guest@example.com",
    linkToken: "fixture",
  }),
  linked: deviceLinkSuccess({
    heading: "Device linked",
    messageHtml: "Linked <strong>guest@example.com</strong> to the Soup device.",
  }),
};

for (const [name, html] of Object.entries(pages)) {
  writeFileSync(join(outDir, `${name}.html`), html);
}
console.log(Object.keys(pages).map((n) => join(outDir, `${n}.html`)).join("\n"));
