import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { agentFor, agentId } from './agents/index.mjs';
import { createClaudeAgent, resolveClaudeBinary } from './agents/claude.mjs';
import { createCodexAgent } from './agents/codex.mjs';
import { authorSource } from './workbench-source-agent.mjs';
import { planWorld } from './world-planner.mjs';

const schema = { type: 'object', properties: { action: { type: 'string' } }, required: ['action'], additionalProperties: false };
const secrets = { CONSTRUCT_GATEWAY_TOKEN: 'gateway', CONSTRUCT_GATEWAY_URL: 'http://127.0.0.1:1', EUCLID_WORKBENCH_TOKEN: 'workbench',
  SKETCHFAB_API_TOKEN: 'sketchfab', OPENAI_API_KEY: 'openai' };

// A stand-in CLI that records how it was called, then answers in the documented output format.
const recorder = `
import { appendFileSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
let input = '';
for await (const chunk of process.stdin) input += chunk;
const leaked = [...${JSON.stringify(Object.keys(secrets))}, ...(process.env.FAKE_FORBID ?? '').split(',').filter(Boolean)].filter(key => key in process.env);
appendFileSync(process.env.FAKE_LOG, JSON.stringify({ args, input, cwd: process.cwd(), leaked }) + '\\n');
const mode = process.env.FAKE_MODE ?? 'ok';
const print = value => process.stdout.write(JSON.stringify(value) + '\\n');
`;
const fakeClaude = recorder + `
if (args[0] === 'auth') process.exit(mode === 'signed-out' ? 1 : 0);
if (args.includes('--json-schema')) {
  if (mode === 'failed') { print({ type: 'result', subtype: 'error_during_execution', is_error: true, result: 'Not logged in' }); process.exit(1); }
  print({ type: 'result', subtype: 'success', is_error: false, result: '', session_id: 'fixture',
    ...(mode === 'declined' ? {} : { structured_output: { action: 'spawn_cone' } }) });
} else {
  print({ type: 'system', subtype: 'init', tools: ['Read', 'Edit'] });
  if (mode === 'hang') await new Promise(() => setInterval(() => {}, 1000));
  print({ type: 'assistant', parent_tool_use_id: null, message: { content: [{ type: 'text', text: 'Editing.' }, { type: 'tool_use', name: 'Write' }] } });
  writeFileSync('edited.gd', 'extends Node\\n');
  print({ type: 'assistant', parent_tool_use_id: null, message: { content: [{ type: 'tool_use', name: 'Edit' }] } });
  if (mode === 'failed') { print({ type: 'result', subtype: 'error_max_turns', is_error: true }); process.exit(1); }
  print({ type: 'result', subtype: 'success', is_error: false, result: 'Added [edited.gd](edited.gd)   to the\\nworkspace.' });
}
`;
const fakeCodex = recorder + `
import { readFileSync } from 'node:fs';
if (args[0] === 'login') { console.log(mode === 'api-key' ? 'Logged in using an API key' : 'Logged in using ChatGPT'); process.exit(0); }
if (args.includes('--output-schema')) {
  JSON.parse(readFileSync(args[args.indexOf('--output-schema') + 1], 'utf8'));
  print({ action: 'spawn_cone' });
} else {
  print({ type: 'item.completed', item: { type: 'command_execution' } });
  writeFileSync('edited.gd', 'extends Node\\n');
  print({ type: 'item.completed', item: { type: 'agent_message', text: 'Added edited.gd.' } });
  if (mode !== 'failed') print({ type: 'turn.completed' });
}
`;

async function fixture(t, source, env = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'euclid-agent-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const script = path.join(directory, 'cli.mjs');
  const log = path.join(directory, 'calls.jsonl');
  await writeFile(script, source);
  return {
    options: { env: { ...process.env, ...secrets, FAKE_LOG: log, ...env }, launcher: async () => ({ file: process.execPath, args: [script] }) },
    workspace: (await mkdtemp(path.join(directory, 'workspace-'))),
    calls: async () => (await readFile(log, 'utf8')).trim().split('\n').map(line => JSON.parse(line)),
  };
}
const live = () => new AbortController().signal;
const option = (args, name) => args[args.indexOf(name) + 1];

test('agent selection defaults to Codex and can differ by role', () => {
  assert.equal(agentId('plan', {}), 'codex');
  assert.equal(agentId('author', { EUCLID_AGENT: ' Claude ' }), 'claude');
  assert.equal(agentId('plan', { EUCLID_AGENT: 'claude', EUCLID_AGENT_PLAN: 'codex' }), 'codex');
  assert.equal(agentId('author', { EUCLID_AGENT_AUTHOR: 'claude' }), 'claude');
  assert.throws(() => agentId('plan', { EUCLID_AGENT: 'other' }), /Set EUCLID_AGENT to codex or claude/);
  assert.throws(() => agentId('chat', {}), /Unknown agent role/);
  const agent = agentFor('author', { EUCLID_AGENT: 'claude' });
  assert.deepEqual([agent.id, agent.label, typeof agent.structured, typeof agent.author], ['claude', 'Claude', 'function', 'function']);
});

test('Claude returns schema-validated output with every tool removed', async t => {
  const { options, calls } = await fixture(t, fakeClaude, { EUCLID_CLAUDE_MODEL: 'haiku' });
  const agent = createClaudeAgent(options);
  assert.deepEqual(await agent.structured('Plan: a cone', schema, live()), { action: 'spawn_cone' });
  const [status, plan] = await calls();
  assert.deepEqual(status.args.slice(-2), ['auth', 'status']);
  assert.deepEqual(plan.leaked, []);
  assert.equal(plan.input, 'Plan: a cone');
  assert.notEqual(path.resolve(plan.cwd), process.cwd());
  assert.ok(plan.args.includes('-p') && plan.args.includes('--safe-mode') && plan.args.includes('--strict-mcp-config'));
  assert.ok(plan.args.includes('--no-session-persistence'));
  assert.deepEqual(JSON.parse(option(plan.args, '--json-schema')), schema);
  assert.equal(option(plan.args, '--output-format'), 'json');
  assert.equal(option(plan.args, '--tools'), '');
  assert.equal(option(plan.args, '--disallowedTools'), 'mcp__*');
  assert.equal(option(plan.args, '--permission-mode'), 'dontAsk');
  assert.equal(option(plan.args, '--model'), 'haiku');
});

test('Claude reads a schema file and rejects missing output, failures and sign-out', async t => {
  const { options, calls } = await fixture(t, fakeClaude);
  const file = path.join(path.dirname(options.env.FAKE_LOG), 'schema.json');
  await writeFile(file, JSON.stringify(schema, null, 2));
  assert.deepEqual(await createClaudeAgent(options).structured('x', file, live()), { action: 'spawn_cone' });
  assert.deepEqual(JSON.parse(option((await calls())[1].args, '--json-schema')), schema);
  assert.ok(!(await calls())[1].args.includes('--model'));
  const withMode = FAKE_MODE => createClaudeAgent({ ...options, env: { ...options.env, FAKE_MODE } });
  await assert.rejects(withMode('declined').structured('x', schema, live()), /Claude Code could not complete the request/);
  await assert.rejects(withMode('failed').structured('x', schema, live()), /Claude Code could not complete the request/);
  await assert.rejects(withMode('signed-out').structured('x', schema, live()), /claude auth login/);
  const large = { type: 'object', properties: { text: { type: 'string', description: 'x'.repeat(25000) } } };
  await assert.rejects(createClaudeAgent(options).structured('x', large, live()), /too large for the Claude Code adapter/);
  await assert.rejects(createClaudeAgent({ ...options, launcher: async () => ({ file: path.join(path.dirname(file), 'missing-claude'), args: [] }) })
    .structured('x', schema, live()), /Install Claude Code/);
});

test('Claude authors inside the workspace with file tools only', async t => {
  const { options, workspace, calls } = await fixture(t, fakeClaude);
  const progress = [];
  const summary = await authorSource({ workspace, request: 'Add a file', onProgress: line => progress.push(line), signal: live() },
    createClaudeAgent(options));
  assert.equal(summary, 'Added edited.gd to the workspace.');
  assert.deepEqual(progress, ['Claude started workspace step 1.\n', 'Claude started workspace step 2.\n']);
  assert.equal(await readFile(path.join(workspace, 'edited.gd'), 'utf8'), 'extends Node\n');
  const job = (await calls())[1];
  assert.equal(path.resolve(job.cwd), path.resolve(workspace));
  assert.deepEqual(job.leaked, []);
  assert.match(job.input, /"request":"Add a file"/);
  assert.equal(option(job.args, '--tools'), 'Read,Edit,Write,Glob,Grep');
  assert.equal(option(job.args, '--output-format'), 'stream-json');
  assert.equal(option(job.args, '--permission-mode'), 'acceptEdits');
  for (const flag of ['--verbose', '--restricted', '--safe-mode', '--strict-mcp-config']) assert.ok(job.args.includes(flag), flag);
  assert.ok(!job.args.includes('Bash') && !job.args.includes('--dangerously-skip-permissions'));
});

test('Claude authoring reports failures and stops when cancelled', async t => {
  const { options, workspace } = await fixture(t, fakeClaude);
  const author = (FAKE_MODE, signal) => createClaudeAgent({ ...options, env: { ...options.env, FAKE_MODE } })
    .author('brief', { workspace, onProgress() {}, signal, timeout: 30000 });
  await assert.rejects(author('failed', live()), /did not finish editing the workspace/);
  const controller = new AbortController();
  const running = author('hang', controller.signal);
  setTimeout(() => controller.abort(new Error('Source authoring cancelled.')), 300);
  await assert.rejects(running, /Source authoring cancelled/);
  await assert.rejects(createClaudeAgent({ ...options, env: { ...options.env, FAKE_MODE: 'hang' } })
    .author('brief', { workspace, onProgress() {}, signal: live(), timeout: 300 }), /timed out/);
});

test('Codex keeps its ChatGPT sign-in, schema file and workspace sandbox', async t => {
  const { options, workspace, calls } = await fixture(t, fakeCodex, { ANTHROPIC_API_KEY: 'anthropic', FAKE_FORBID: 'ANTHROPIC_API_KEY' });
  const agent = createCodexAgent(options);
  assert.deepEqual(await agent.structured('Plan: a cone', schema, live()), { action: 'spawn_cone' });
  const progress = [];
  assert.equal(await agent.author('brief', { workspace, onProgress: line => progress.push(line), signal: live(), timeout: 30000 }), 'Added edited.gd.');
  assert.deepEqual(progress, ['Codex completed workspace command 1.\n']);
  const [login, plan, , job] = await calls();
  assert.deepEqual(login.args.slice(-2), ['login', 'status']);
  assert.deepEqual([plan.leaked, job.leaked], [[], []]);
  assert.equal(plan.input, 'Plan: a cone');
  assert.equal(option(plan.args, '--sandbox'), 'read-only');
  assert.ok(plan.args.includes('shell_tool') && plan.args.includes('forced_login_method="chatgpt"'));
  assert.equal(option(job.args, '--sandbox'), 'workspace-write');
  assert.ok(job.args.includes('sandbox_workspace_write.network_access=false') && job.args.includes('--json'));
  assert.equal(path.resolve(job.cwd), path.resolve(workspace));
  const withMode = FAKE_MODE => createCodexAgent({ ...options, env: { ...options.env, FAKE_MODE } });
  await assert.rejects(withMode('api-key').structured('x', schema, live()), /uses ChatGPT sign-in/);
  await assert.rejects(withMode('failed').author('brief', { workspace, onProgress() {}, signal: live(), timeout: 30000 }),
    /Codex did not finish editing the workspace/);
});

test('the world planner validates whichever agent answers', async () => {
  const seen = [];
  const structured = plan => async (input, definition) => { seen.push([input, definition]); return plan; };
  const plan = { action: 'spawn_cone', color: 'ff681d', scale: 1 };
  assert.deepEqual(await planWorld('Make a cone', live(), null, structured(plan)), plan);
  assert.match(seen[0][0], /User request: "Make a cone"/);
  assert.match(seen[0][1], /grid-plan\.schema\.json$/);
  await assert.rejects(planWorld('Make a cone', live(), null, structured({ ...plan, scale: 9 })), /The agent returned an invalid world plan/);
});

test('Claude discovery honors an explicit executable', async () => {
  assert.equal(await resolveClaudeBinary({ EUCLID_CLAUDE_BIN: 'C:/tools/claude.exe' }), 'C:/tools/claude.exe');
  if (process.platform !== 'win32') assert.equal(await resolveClaudeBinary({}), 'claude');
});
