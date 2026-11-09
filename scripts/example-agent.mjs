import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const config = JSON.parse(await readFile(new URL('../.local/gateway.json', import.meta.url), 'utf8'));
const task_id = `manifest-check-${Date.now()}`;
async function report(event, summary) {
  const response = await fetch(`${config.url}/v1/events`, { method: 'POST', headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ event_id: randomUUID(), agent_id: 'example-worker', task_id, event, summary }) });
  if (!response.ok) throw new Error(`Gateway rejected event (${response.status})`);
}
await report('task.started', 'Checking world anchor identities in a real local Node process.');
try {
  const world = JSON.parse(await readFile(new URL('../world/data/world.json', import.meta.url), 'utf8'));
  const ids = world.anchors.map(anchor => anchor.id);
  if (new Set(ids).size !== ids.length) throw new Error('Duplicate anchor IDs found');
  if (world.anchors.some(anchor => !world.zones.some(zone => zone.id === anchor.zone))) throw new Error('Unknown anchor zone');
  await report('task.completed', `Validated ${ids.length} unique anchors across ${world.zones.length} zones. This is a Node adapter example, not a connected AI assistant.`);
  console.log('Real manifest check completed; result sent to the avatar in the villa.');
} catch (error) { await report('task.failed', error.message); throw error; }
