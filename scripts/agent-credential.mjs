// Issue, revoke or list agent credentials for the running Euclid gateway.
//   node scripts/agent-credential.mjs issue grok
//   node scripts/agent-credential.mjs issue cloud-claude --remote [--checks]
//   node scripts/agent-credential.mjs revoke grok
//   node scripts/agent-credential.mjs list
// --remote lets the agent connect through the outside endpoint (EUCLID_REMOTE_PORT).
// --checks also lets that remote agent run checks, which execute its draft's code on this machine.
import { readFile } from 'node:fs/promises';

const args = process.argv.slice(2);
const flags = new Set(args.filter(arg => arg.startsWith('--')));
const [action, name] = args.filter(arg => !arg.startsWith('--'));
const unknown = [...flags].filter(flag => !['--remote', '--checks'].includes(flag));
if (!['issue', 'revoke', 'list'].includes(action) || (action !== 'list' && !name) || unknown.length ||
    (flags.size && action !== 'issue')) {
  console.error('Usage: node scripts/agent-credential.mjs issue <name> [--remote [--checks]], revoke <name>, or list');
  process.exit(2);
}
const config = JSON.parse(await readFile(new URL('../.local/gateway.json', import.meta.url), 'utf8'));
const response = await fetch(`${config.url}/v1/agents/${action}`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${config.token}`, 'X-Euclid-Workbench': config.workbench_token, 'Content-Type': 'application/json' },
  body: JSON.stringify(action === 'list' ? {} : { name, remote: flags.has('--remote'), checks: flags.has('--checks') }),
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
  if (result.remote) {
    console.log(`\nRemote agent. Start Euclid with EUCLID_REMOTE_PORT set, point a tunnel at that port, and give the`);
    console.log('agent the tunnel URL with /mcp and this header:');
    console.log('  Authorization: Bearer <the credential above>');
    console.log(result.checks ? 'It may run checks, which execute its draft on this machine.' : 'It cannot run checks. A person runs them in the Workbench.');
  } else {
    console.log(`\nConnect the agent's MCP client to ${config.url}/mcp/agent with these headers:`);
    console.log('  Authorization: Bearer <the token field in .local/gateway.json>');
    console.log('  X-Euclid-Agent: <the credential above>');
  }
} else if (action === 'revoke') {
  console.log(result.revoked ? `Revoked ${result.name}.` : `${result.name} had no credential.`);
} else if (!result.agents.length) {
  console.log('No agent credentials have been issued.');
} else {
  for (const agent of result.agents) {
    const scope = agent.remote ? (agent.checks ? 'remote, runs checks' : 'remote') : 'local';
    console.log(`${agent.name}\t${scope}\tissued ${agent.created_at}`);
  }
}
