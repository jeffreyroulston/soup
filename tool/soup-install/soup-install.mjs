#!/usr/bin/env node
// Installs or updates Soup on an LG webOS TV in Developer Mode, using LG's own
// `ares` tools for pairing and installing. See README.md.
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { connect } from 'node:net';
import { networkInterfaces, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { parseArgs } from 'node:util';

const RELEASES = 'https://github.com/jeffreyroulston/soup/releases/latest/download';
const IPK_NAME = 'soup-webos-arm.ipk';
const APP_ID = 'com.bestiestudios.soup'; // apps/android-v2/webos/meta/appinfo.json
const DEVICE = 'soup-tv';
const DEV_MODE_PORT = 9922;
// The only webOS SDK version Soup has actually been run on.
const TESTED_SDK_MAJOR = 11;

const USAGE = `Usage: soup-install [install|uninstall] [options]

  install      Install or update Soup on the TV (default)
  uninstall    Remove Soup from the TV

Options:
  --host <ip>  Use this TV instead of searching the network
  --ipk <path> Install this file instead of downloading the latest release
  -h, --help   Show this help
`;

const aresRoot = dirname(
  createRequire(import.meta.url).resolve('@webos-tools/cli/package.json'),
);

class UserError extends Error {}

/** Runs an ares tool and returns its output, without throwing on failure. */
function ares(tool, args, { timeoutMs = 120_000, inherit = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [join(aresRoot, 'bin', `${tool}.js`), ...args],
      { stdio: inherit ? 'inherit' : ['ignore', 'pipe', 'pipe'], timeout: timeoutMs },
    );
    let output = '';
    child.stdout?.on('data', (d) => (output += d));
    child.stderr?.on('data', (d) => (output += d));
    child.on('error', reject);
    child.on('close', (code) => resolve({ ok: code === 0, output }));
  });
}

function portOpen(host, timeoutMs) {
  return new Promise((resolve) => {
    const socket = connect({ host, port: DEV_MODE_PORT, timeout: timeoutMs });
    const finish = (open) => {
      socket.destroy();
      resolve(open);
    };
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
  });
}

function isPrivateLan(address) {
  const [a, b] = address.split('.').map(Number);
  return a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31);
}

/** Every host in the /24 of each private network this computer is on. */
function lanHosts() {
  const hosts = new Set();
  for (const [name, addresses] of Object.entries(networkInterfaces())) {
    if (/^(docker|br-|veth|virbr|tailscale|utun)/.test(name)) continue;
    for (const { family, internal, address } of addresses ?? []) {
      if (family !== 'IPv4' || internal || !isPrivateLan(address)) continue;
      const prefix = address.split('.').slice(0, 3).join('.');
      for (let i = 1; i < 255; i++) hosts.add(`${prefix}.${i}`);
    }
  }
  return [...hosts];
}

async function scanForTvs() {
  const queue = lanHosts();
  const found = [];
  const worker = async () => {
    for (let host = queue.pop(); host; host = queue.pop()) {
      if (await portOpen(host, 600)) found.push(host);
    }
  };
  await Promise.all(Array.from({ length: 64 }, worker));
  return found.sort();
}

async function savedHost() {
  const { ok, output } = await ares('ares-setup-device', ['--listfull']);
  if (!ok) return null;
  const match = output.match(/\[[\s\S]*\]/);
  if (!match) return null;
  try {
    return JSON.parse(match[0]).find((d) => d.name === DEVICE)?.deviceinfo?.ip ?? null;
  } catch {
    return null;
  }
}

async function chooseTv(rl, requested) {
  if (requested) {
    if (await portOpen(requested, 3000)) return requested;
    throw new UserError(
      `Nothing is answering on ${requested}:${DEV_MODE_PORT}. Is Dev Mode Status on?`,
    );
  }
  const saved = await savedHost();
  if (saved && (await portOpen(saved, 1500))) return saved;

  console.log('Looking for a TV in Developer Mode on your network...');
  const found = await scanForTvs();
  if (found.length === 1) return found[0];
  if (found.length > 1) {
    found.forEach((host, i) => console.log(`  ${i + 1}) ${host}`));
    const answer = await rl.question('Which one is your TV? ');
    const picked = found[Number(answer) - 1];
    if (!picked) throw new UserError('That is not one of the listed TVs.');
    return picked;
  }
  throw new UserError(
    `No TV found. Check that it is on the same network as this computer and that\n` +
      `Dev Mode Status is ON in the Developer Mode app, or pass --host <tv-ip>.`,
  );
}

async function register(host, passphrase) {
  const settings = ['-i', `host=${host}`, '-i', `port=${DEV_MODE_PORT}`, '-i', 'username=prisoner'];
  if (passphrase) settings.push('-i', `passphrase=${passphrase}`);
  const saved = await savedHost();
  const { ok, output } = await ares('ares-setup-device', [
    saved ? '-m' : '-a',
    DEVICE,
    ...settings,
  ]);
  if (!ok) throw new Error(`Could not save the TV:\n${output}`);
}

async function deviceInfo() {
  const { ok, output } = await ares('ares-device', ['-i', '-d', DEVICE], { timeoutMs: 30_000 });
  return ok && /sdkVersion/.test(output) ? output : null;
}

/** Returns the TV's info, pairing with it first if this computer isn't yet. */
async function connectToTv(rl, host) {
  await register(host);
  const known = await deviceInfo();
  if (known) return known;

  console.log(
    `\nOn the TV, open the Developer Mode app and turn Key Server ON.\n` +
      `The passphrase is the 6 characters shown in that app.`,
  );
  const passphrase = (await rl.question('Passphrase: ')).trim();
  if (!passphrase) throw new UserError('A passphrase is needed to pair with the TV.');
  await register(host, passphrase);
  const { ok, output } = await ares('ares-novacom', [
    '--device', DEVICE, '--getkey', '--passphrase', passphrase,
  ]);
  if (!ok) {
    throw new UserError(`Could not get the key from the TV. Is Key Server ON?\n${output}`);
  }
  const info = await deviceInfo();
  if (!info) throw new UserError('Paired, but the TV did not respond. Check the passphrase.');
  return info;
}

async function confirmSupported(rl, info) {
  const model = info.match(/modelName\s*:\s*(\S+)/)?.[1] ?? 'unknown model';
  const sdk = info.match(/sdkVersion\s*:\s*(\S+)/)?.[1] ?? 'unknown';
  console.log(`Found ${model} (webOS SDK ${sdk})`);
  if (Number.parseInt(sdk, 10) >= TESTED_SDK_MAJOR) return;
  console.log(`Soup has only been tested on webOS SDK ${TESTED_SDK_MAJOR} and newer, so it may not run here.`);
  const answer = await rl.question('Try anyway? [y/N] ');
  if (!/^y/i.test(answer)) throw new UserError('Cancelled.');
}

async function fetchOk(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
  return response;
}

async function downloadIpk(dir) {
  console.log('Downloading the latest Soup release...');
  const sums = await (await fetchOk(`${RELEASES}/SHA256SUMS`)).text();
  const expected = sums
    .split('\n')
    .map((line) => line.trim().split(/\s+/))
    .find(([, name]) => name === IPK_NAME)?.[0];
  if (!expected) throw new Error(`${IPK_NAME} is missing from SHA256SUMS.`);

  const bytes = Buffer.from(await (await fetchOk(`${RELEASES}/${IPK_NAME}`)).arrayBuffer());
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) throw new Error('The download is corrupt (checksum mismatch). Try again.');

  const path = join(dir, IPK_NAME);
  await writeFile(path, bytes);
  return path;
}

async function install(rl, values) {
  const host = await chooseTv(rl, values.host);
  const info = await connectToTv(rl, host);
  await confirmSupported(rl, info);

  const dir = await mkdtemp(join(tmpdir(), 'soup-install-'));
  try {
    // Fail early on a bad --ipk path rather than inside ares.
    if (values.ipk) await readFile(values.ipk);
    const ipk = values.ipk ?? (await downloadIpk(dir));
    console.log('Installing on the TV...');
    const installed = await ares('ares-install', ['-d', DEVICE, ipk], { timeoutMs: 300_000 });
    if (!installed.ok) throw new Error(`Install failed:\n${installed.output}`);
    const launched = await ares('ares-launch', ['-d', DEVICE, APP_ID], { timeoutMs: 30_000 });
    console.log(
      launched.ok
        ? '\nDone. Soup is open on your TV.'
        : '\nInstalled. Open Soup from the TV\'s app list.',
    );
    console.log(
      'Developer Mode expires periodically: open the Developer Mode app and press\n' +
        'Extend before it runs out, or the TV will remove Soup.',
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function uninstall(rl, values) {
  const host = await chooseTv(rl, values.host);
  await connectToTv(rl, host);
  const removed = await ares('ares-install', ['-d', DEVICE, '-r', APP_ID]);
  if (!removed.ok) throw new Error(`Could not remove Soup:\n${removed.output}`);
  console.log('Soup was removed from the TV.');
}

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      host: { type: 'string' },
      ipk: { type: 'string' },
      help: { type: 'boolean', short: 'h' },
    },
  });
  const command = positionals[0] ?? 'install';
  if (values.help || !['install', 'uninstall'].includes(command)) {
    console.log(USAGE);
    process.exitCode = values.help ? 0 : 1;
    return;
  }
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    await (command === 'install' ? install : uninstall)(rl, values);
  } finally {
    rl.close();
  }
}

main().catch((error) => {
  console.error(`\n${error instanceof UserError ? error.message : `Error: ${error.message}`}`);
  process.exitCode = 1;
});
