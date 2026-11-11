// Issue, revoke or list agent credentials for the running Euclid gateway.
//   node scripts/agent-credential.mjs issue grok
//   node scripts/agent-credential.mjs revoke grok
//   node scripts/agent-credential.mjs list
import { readFile } from 'node:fs/promises';

const [action, name] = process.argv.slice(2);
if (!['issue', 'revoke', 'list'].includes(action) || (action !== 'list' && !name)) {
  console.error('Usage: node scripts/agent-credential.mjs issue|revoke <name>, or list');
  process.exit(2);
}
const config = JSON.parse(await readFile(new URL('../.local/gateway.json', import.meta.url), 'utf8'));
const response = await fetch(`${config.url}/v1/agents/${action}`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${config.token}`, 'X-Euclid-Workbench': config.workbench_token, 'Content-Type': 'application/json' },
  body: JSON.stringify(action === 'list' ? {} : { name }),
}).catch(() => null);
if (!response) {
  console.error('The Euclid gateway is not running. Start Euclid first.');
  process.exit(1);
}
const result = await response.json();
if (!response.ok) {
  console.error(result.error ?? `The gateway answered ${response.status}.`);
  process.exit(1);
}
if (action === 'issue') {
  console.log(`Agent credential for ${result.name}. It is shown once; issuing again replaces it.\n`);
  console.log(result.token);
  console.log(`\nConnect the agent's MCP client to ${config.url}/mcp/agent with these headers:`);
  console.log('  Authorization: Bearer <the token field in .local/gateway.json>');
  console.log('  X-Euclid-Agent: <the credential above>');
} else if (action === 'revoke') {
  console.log(result.revoked ? `Revoked ${result.name}.` : `${result.name} had no credential.`);
} else if (!result.agents.length) {
  console.log('No agent credentials have been issued.');
} else {
  for (const agent of result.agents) console.log(`${agent.name}\tissued ${agent.created_at}`);
}
