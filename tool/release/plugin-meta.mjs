// Prints the meta.json that goes inside a plugin zip: <version> <target-abi>
import { plugin } from './plugin-info.mjs';

const [version, targetAbi] = process.argv.slice(2);
console.log(JSON.stringify({
  ...plugin,
  version,
  targetAbi,
  changelog: 'See the GitHub release.',
  timestamp: new Date().toISOString(),
}, null, 2));
