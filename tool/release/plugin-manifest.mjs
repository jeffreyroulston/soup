// Prints the Jellyfin plugin repository manifest: <repo> <tag> <plugins-file>,
// where each line of the file is: <version> <target-abi> <zip-name> <md5>
import { readFileSync } from 'node:fs';
import { plugin } from './plugin-info.mjs';

const [repo, tag, plugins] = process.argv.slice(2);
const timestamp = new Date().toISOString();
const versions = readFileSync(plugins, 'utf8')
  .trim()
  .split('\n')
  .map((line) => line.split(' '))
  .map(([version, targetAbi, zip, checksum]) => ({
    version,
    targetAbi,
    checksum,
    timestamp,
    changelog: `https://github.com/${repo}/releases/tag/${tag}`,
    sourceUrl: `https://github.com/${repo}/releases/download/${tag}/${zip}`,
  }))
  .reverse(); // Newest build first.
console.log(JSON.stringify([{ ...plugin, versions }], null, 2));
