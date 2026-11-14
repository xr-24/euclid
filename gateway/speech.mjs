import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { parseEnv, promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { agentEnvironment } from './agents/process.mjs';

const exec = promisify(execFile);
const require = createRequire(import.meta.url);
const voiceId = /^[a-zA-Z0-9_-]{1,80}$/;
export const maxSpeechLength = 4000;
export const maxSpeechBytes = 4 * 1024 * 1024;
const approvalTimeout = 30 * 60_000;

export class SpeechError extends Error {
  constructor(status, message, connect = false) {
    super(message);
    this.status = status;
    this.connect = connect;
  }
}

async function elevenLabs(apiKey) {
  const { ElevenLabsClient } = await import('@elevenlabs/elevenlabs-js');
  return new ElevenLabsClient({ apiKey, timeoutInSeconds: 20, maxRetries: 0 });
}

async function runOnboarding(directory, envFile, args, signal) {
  const platform = `@elevenlabs/cli-${process.platform}-${process.arch}`;
  const cli = path.join(path.dirname(require.resolve(platform + '/package.json')),
    process.platform === 'win32' ? 'elevenlabs.exe' : 'elevenlabs');
  const env = agentEnvironment(process.env);
  const { stdout } = await exec(cli, ['onboard', 'connect', '--env-path', envFile, ...args],
    { cwd: directory, env, signal, timeout: 28_000, windowsHide: true });
  return JSON.parse(stdout);
}

function providerError(error) {
  const status = error?.statusCode;
  if (status === 401) return new SpeechError(401, 'Authorize ElevenLabs in your browser to reconnect.', true);
  if (status === 403) return new SpeechError(403, 'The ElevenLabs key needs Voices and Text to Speech access.', true);
  if (status === 402) return new SpeechError(402, 'Your ElevenLabs plan does not support this voice or has no credits left.');
  if (status === 404) return new SpeechError(404, 'That voice is no longer available in your ElevenLabs account.');
  if (status === 429) return new SpeechError(429, 'ElevenLabs is limiting requests. Try again in a moment.');
  return new SpeechError(502, 'ElevenLabs is unavailable right now. Try again in a moment.');
}

export function createSpeechService(directory, { clientFor = elevenLabs, onboard = runOnboarding,
  env = process.env, envFile = path.join(directory, '.env.local') } = {}) {
  const shutdown = new AbortController();
  let connection = null;
  let connectionError = '';
  let catalog = null;

  async function apiKey() {
    const content = await readFile(envFile, 'utf8').catch(error => {
      if (error.code !== 'ENOENT') throw error;
      return '';
    });
    return parseEnv(content).ELEVENLABS_API_KEY?.trim() || env.ELEVENLABS_API_KEY?.trim();
  }

  async function clientWithKey() {
    const key = await apiKey();
    if (!key) throw new SpeechError(409, 'Authorize ElevenLabs in your browser to turn on voice.', true);
    return { client: await clientFor(key), key };
  }

  async function voices({ refresh = false } = {}, signal) {
    if (connection) return { connecting: true };
    if (connectionError) {
      const message = connectionError;
      connectionError = '';
      throw new SpeechError(409, message, true);
    }
    const { client, key } = await clientWithKey();
    if (!refresh && catalog?.key === key && Date.now() < catalog.expires) return { voices: catalog.voices };
    const found = new Map();
    const tokens = new Set();
    let nextPageToken;
    try {
      do {
        const page = await client.voices.search({ pageSize: 100, nextPageToken }, { abortSignal: signal });
        for (const voice of page.voices) {
          if (typeof voice.voiceId === 'string' && voiceId.test(voice.voiceId) && typeof voice.name === 'string' && voice.name.trim()) {
            found.set(voice.voiceId, { id: voice.voiceId, name: voice.name.trim().slice(0, 120) });
          }
        }
        nextPageToken = page.hasMore ? page.nextPageToken : undefined;
        if (page.hasMore && (!nextPageToken || tokens.has(nextPageToken))) throw new Error('Invalid voice page token');
        tokens.add(nextPageToken);
      } while (nextPageToken);
    } catch (error) {
      throw providerError(error);
    }
    const voices = [...found.values()].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
    catalog = { key, voices, expires: Date.now() + 5 * 60_000 };
    return { voices };
  }

  async function authorize() {
    if (connection) return await connection;
    connectionError = '';
    // The app opens the URL in the user's default browser only after an explicit voice action.
    connection = (async () => {
      try {
        const response = await onboard(directory, envFile, ['--no-browser', '--replace'], shutdown.signal);
        if (response.next !== 'wait') throw new Error('No browser approval');
        const match = response.say?.match(/https:\/\/elevenlabs\.io\/app\/oauth\/authorize\?[^\s]+/);
        if (!match) throw new Error('No approval URL');
        void waitForApproval().then(() => {
          catalog = null;
        }).catch(() => {
          connectionError = 'ElevenLabs approval did not finish. Choose Connect to try again.';
        }).finally(() => { connection = null; });
        return { authorization_url: match[0] };
      } catch {
        throw new SpeechError(503, 'Could not open ElevenLabs approval. Check the connection and try again.', true);
      }
    })();
    try { return await connection; }
    catch (error) {
      connection = null;
      throw error;
    }
  }

  async function waitForApproval() {
    const signal = AbortSignal.any([shutdown.signal, AbortSignal.timeout(approvalTimeout)]);
    while (true) {
      const result = await onboard(directory, envFile, ['--wait'], signal);
      if (result.details?.key_status === 'created' && await apiKey()) return;
      if (result.next !== 'wait') throw new Error('No account key');
      await delay(250, undefined, { signal });
    }
  }

  async function synthesize({ voice, text }, signal) {
    if (typeof voice !== 'string' || !voiceId.test(voice) ||
        typeof text !== 'string' || !text.trim() || text.length > maxSpeechLength || text.includes('\0')) {
      throw new SpeechError(400, 'Choose a voice and enter up to 4000 characters of speech.');
    }
    const { client } = await clientWithKey();
    try {
      const stream = await client.textToSpeech.convert(voice, { text, modelId: 'eleven_flash_v2_5', outputFormat: 'mp3_44100_64' },
        { abortSignal: signal });
      const chunks = [];
      let bytes = 0;
      const reader = stream.getReader();
      const abort = () => { void reader.cancel().catch(() => {}); };
      signal?.addEventListener('abort', abort, { once: true });
      try {
        while (true) {
          signal?.throwIfAborted();
          const { done, value } = await reader.read();
          if (done) break;
          bytes += value.length;
          if (bytes > maxSpeechBytes) throw new Error('Audio over size limit');
          chunks.push(value);
        }
        signal?.throwIfAborted();
      } finally {
        signal?.removeEventListener('abort', abort);
        abort();
      }
      if (!bytes) throw new Error('Empty audio');
      return Buffer.concat(chunks, bytes);
    } catch (error) {
      throw providerError(error);
    }
  }

  return { voices, authorize, synthesize, close: () => shutdown.abort() };
}
