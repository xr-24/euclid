import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

// One credential per connected agent. The person issues it with the Workbench
// capability and hands it to that agent. Only a hash is kept on disk. A name that has
// a credential is reserved: the shared development route can no longer act as it.
export const agentName = /^[a-z0-9_-]{1,32}$/;
const tokenPattern = /^eua_[a-f0-9]{64}$/;
const digest = token => createHash('sha256').update(token).digest();

export async function createAgentCredentials(file, { now = () => new Date() } = {}) {
  let agents = {};
  try {
    const saved = JSON.parse(await readFile(file, 'utf8'));
    for (const [name, entry] of Object.entries(saved?.agents ?? {})) {
      if (agentName.test(name) && /^[a-f0-9]{64}$/.test(entry?.hash ?? '') && typeof entry.created_at === 'string') {
        agents[name] = { hash: entry.hash, created_at: entry.created_at, remote: entry.remote === true, checks: entry.checks === true };
      }
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error(`The agent credential file could not be read: ${error.message}`);
  }
  let turn = Promise.resolve();

  function persist() {
    const snapshot = JSON.stringify({ version: 1, agents }, null, 2);
    const next = turn.then(async () => {
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(`${file}.next`, snapshot, { mode: 0o600 });
      await rename(`${file}.next`, file);
    });
    turn = next.catch(() => {});
    return next;
  }

  function requireName(name) {
    if (typeof name !== 'string' || !agentName.test(name)) throw new Error('An agent name is 1 to 32 lowercase letters, digits, _ or -.');
  }

  return {
    // Issuing again replaces the agent's previous credential and its permissions.
    // remote: the agent may connect through the outside endpoint. checks: it may run checks there.
    async issue(name, { remote = false, checks = false } = {}) {
      requireName(name);
      if (checks && !remote) throw new Error('Only a remote credential needs the checks permission; local agents always have it.');
      const token = `eua_${randomBytes(32).toString('hex')}`;
      const created_at = now().toISOString();
      const previous = agents;
      agents = { ...agents, [name]: { hash: digest(token).toString('hex'), created_at, remote: remote === true, checks: checks === true } };
      try { await persist(); } catch (error) { agents = previous; throw error; }
      return { name, token, created_at, remote: remote === true, checks: checks === true };
    },
    async revoke(name) {
      requireName(name);
      if (!Object.hasOwn(agents, name)) return false;
      const previous = agents;
      agents = Object.fromEntries(Object.entries(agents).filter(([key]) => key !== name));
      try { await persist(); } catch (error) { agents = previous; throw error; }
      return true;
    },
    list: () => Object.entries(agents).map(([name, { created_at, remote, checks }]) => ({ name, created_at, remote, checks }))
      .sort((a, b) => a.name.localeCompare(b.name)),
    permissions: name => Object.hasOwn(agents, name) ? { remote: agents[name].remote, checks: agents[name].checks } : null,
    reserved: name => Object.hasOwn(agents, name),
    // The name a credential belongs to, or null. Every stored hash is compared.
    identify(token) {
      if (typeof token !== 'string' || !tokenPattern.test(token)) return null;
      const supplied = digest(token);
      let found = null;
      for (const [name, { hash }] of Object.entries(agents)) {
        if (timingSafeEqual(supplied, Buffer.from(hash, 'hex')) && found === null) found = name;
      }
      return found;
    },
  };
}
