# Agent adapters

Euclid supplies the tools, isolation, review, and activation. The model that
plans or writes is a local CLI behind an adapter in `gateway/agents/`. Codex is
the default. Claude Code is the second adapter.

## Choosing an agent

Set these in the environment that starts the gateway:

| Variable | Effect |
| --- | --- |
| `EUCLID_AGENT` | `codex` (default) or `claude`, for every role |
| `EUCLID_AGENT_PLAN` | Overrides the agent for one-shot structured proposals |
| `EUCLID_AGENT_AUTHOR` | Overrides the agent that edits a source workspace |
| `EUCLID_CODEX_BIN`, `EUCLID_CLAUDE_BIN` | Full path to that CLI when discovery fails |
| `EUCLID_CLAUDE_MODEL` | Optional model alias or name passed to Claude Code |

The gateway reads the selection on each request. A gateway that is already
running keeps the environment it started with, so run
`powershell -File scripts/stop-gateway.ps1` and relaunch Euclid after a change.

## Roles

`plan` covers every one-shot proposal that must match a JSON schema: the F2
command planner, model selection, F4 **Ask**, behavior plugins, workshop
actions, and the shoreline and Grid appearance drafts. The agent gets the
request and catalog as text and has no tools.

`author` edits files in the temporary source workspace of an F2 source draft
or revision. The gateway still compares the workspace afterwards, enforces the
draft path allowlist, and builds the reviewed Git diff itself.

An adapter is an object with `id`, `label`, `structured(input, schema, signal)`
and `author(input, { workspace, onProgress, signal, timeout })`. Prompts,
validation, and limits stay in the callers and are the same for every agent.
Add an adapter by implementing those two functions and registering it in
`gateway/agents/index.mjs`.

## What each adapter runs

| | Codex | Claude Code |
| --- | --- | --- |
| Sign-in | ChatGPT sign-in only; API keys are removed | Whatever `claude auth status` reports as signed in |
| `plan` | `codex exec`, read-only sandbox, shell tool disabled | `claude -p --json-schema`, `--tools ""`, `dontAsk` |
| `author` | `codex exec`, workspace-write sandbox, network off | `claude -p --restricted` with Read, Edit, Write, Glob and Grep, `acceptEdits` |
| User configuration | Ignored | Ignored (`--safe-mode`, `--strict-mcp-config`) |

No agent process inherits the gateway credential, the Workbench capability, or
the Sketchfab token. Each adapter also drops the other vendor's API keys.

The Claude adapter has no command execution, so it creates and edits files but
cannot delete one. `--restricted` needs Claude Code v2.1.248 or later. Schemas
travel on the command line and are limited to 24,000 characters.

## Development tools for connected agents

An agent that connects over MCP can do source work itself. The gateway serves
a second MCP endpoint beside the world tools:

`POST http://127.0.0.1:4317/mcp/dev/<development capability>/<agent name>`

It needs the gateway bearer credential and the development capability, which
the gateway writes to `.local/gateway.json` as `development_token` at each
start. The agent name is 1 to 32 lowercase letters, digits, `_` or `-`. It
labels the agent's drafts and defaults to `agent`. The Codex terminal opened
from F2 connects as `codex`.

| Tool | Effect |
| --- | --- |
| `list_source`, `read_source` | Read draft-eligible source plus `README.md`, `AGENTS.md` and `docs/*.md`. While the agent has a draft, reads return its draft's version |
| `draft_status` | Owner, version, files, diff, check status, scope and output of the active draft, its `base` commit, the extension `kinds` it changes, and `behind_main` when the main branch has moved past it |
| `submit_draft` | Create a draft from complete file contents and deletions, or revise the agent's own draft on top of its current version |
| `run_checks` | Start the isolated project checks for the agent's own draft |
| `rebase_draft` | Replay the agent's own draft onto the tip of the main branch. It keeps its id and needs fresh checks. A conflict names the files and changes nothing |
| `discard_draft` | Discard the agent's own draft |
| `list_extensions` | The kinds of extension Euclid takes, whether each previews live, and every installed extension with its kind, id, files and version |
| `task_history` | Recent Workbench events, newest first, or one draft's events: drafts, revisions, checks, commits, discards and reverts |

A submission is written into the same temporary workspace a local source
agent edits, so the same path allowlist, 24-file and 256 KiB limits and
reviewed Git diff apply. The draft appears in F2 and F4 like any other source
draft. An agent can check, revise or discard only a draft it owns. Commit,
preview, live activation and revert are not exposed. A person does those in
the Workbench.

Checks run the draft's code in the disposable preview project with the local
account's permissions and without the gateway credentials. An agent can now
start them for its own draft without a person reviewing the diff first.

### Cloud agents

An agent that runs elsewhere, such as a cloud agent, reaches Euclid in one of two ways. Both lead
to the same handler, accept only credentials issued for remote use, and are managed from
**F4 → Agents**.

**Through a relay (recommended).** Euclid dials out to a small Cloudflare Worker on your own
account, so nothing on this machine listens for the outside and nothing runs beside Euclid. Deploy
it once from `relay/` ([setup](../relay/README.md)), paste its address in **F4 → Agents**, and give
the relay the key Euclid shows. Euclid reconnects by itself, stops retrying if the relay refuses
its key, and steps aside if another Euclid connects to the same relay. The settings live in
`.local/relay.json`.

**Through your own tunnel.** Set `EUCLID_REMOTE_PORT`, for example `setx EUCLID_REMOTE_PORT 4318`,
restart Euclid, and point a tunnel such as `cloudflared tunnel --url http://127.0.0.1:4318` at that
port only. It is a separate server with one route, `POST /mcp`, so the tunnel exposes nothing else.

**F4 → Agents** adds agents (a cloud agent may connect from outside; a local one only from this
machine), shows each agent's credential and address once, when it was last seen and through which
door, the recent outside calls, and disconnects an agent by revoking its credential.
`node scripts/agent-credential.mjs issue <name> --remote [--checks]` does the same from a terminal.

Remote agents get the development tools. `run_checks` is left out unless the agent may run checks,
because checks run the draft's code on this machine before anyone reviews it. Without that, a
person runs the checks in the Workbench. Each remote agent has its own budget of 120 requests a
minute. Every outside call is written to `.local/remote-audit.jsonl` with the agent, address,
route, method, tool and result, never the arguments. Revoking a credential stops the agent at once.
Browser origins are refused.

Whoever runs the relay or the tunnel can read the traffic that passes through it, including source
code and agent credentials. Run either on an account you control.

### Several agents at once

Euclid holds up to four drafts at once: one for each connected agent, plus one
shared by the person and the local F2 agent. Each draft has its own Git
worktree. An agent sees and reads only its own draft, and `draft_status` lists
the others under `other_drafts` so agents can avoid overlapping files. An agent
cannot check, revise, rebase or discard another agent's draft.

Long jobs still run one at a time: authoring, revising and checks. A second
agent that starts one meanwhile is told the Workbench is busy and tries again.
Discarding a draft does not cancel another draft's checks.

The Workbench panel shows one draft, the one in focus. A draft the person
starts takes focus. An agent's draft takes it only when nothing else is open,
so the person's work is never switched out from under them. When the focused
draft is committed or discarded, the next open draft comes into view.
`POST /v1/workbench/focus` with a draft `id` changes it. An empty `id` shows
the person's own files, and agents' new drafts then stay out of view until the
person picks one. `state` lists every draft under `drafts`, each with
`behind_main`. Committing one draft moves the main branch past the
others, and each is rebased before it commits.

### Agent credentials

On the shared route above, the agent name is only a label. Any local process
with the development capability can use any name. To give an agent an
identity of its own, issue it a credential:

```
node scripts/agent-credential.mjs issue grok
```

The credential is printed once. Issuing again replaces it, `revoke grok`
removes it, and `list` shows the names. The gateway keeps only a hash, in
`.local/agents.json`. The script calls `POST /v1/agents/issue`, `revoke` or
`list`, which need the Workbench capability, so only the person can issue a
credential.

The agent connects to `POST http://127.0.0.1:4317/mcp/agent` with the gateway
bearer credential and an `X-Euclid-Agent` header carrying its own credential.
The gateway takes the agent's name from the credential. It offers the same
tools. Once a name has a credential, the shared route refuses it, so no other
agent can submit, check, rebase or discard drafts as that name.

This separates agents that cooperate and keeps attribution honest. It does not
contain a hostile local process. Anything that can read `.local/gateway.json`
holds the Workbench capability and can issue itself a credential.

### Seeing what agents do

Every agent's work shows in the world, above and around its projection.

- **The feed.** The gateway turns what agents do into events
  (`gateway/agent-activity.mjs`). It reads them from the Claude Code and Codex
  event streams of local tasks and source drafts, and from the development
  tool calls of connected agents. Event kinds are `read`, `search`, `edit`,
  `write`, `delete`, `run`, `tool`, `think`, `say`, `start`, `done` and
  `error`. A read carries the lines read and an edit carries a diff. The world
  long-polls `POST /v1/activity/feed` (`{since, wait}`), which needs the
  Workbench capability. The feed keeps the last 400 events in memory and
  writes nothing to disk.
- **What is hidden.** Files that look like secrets (`.env`, keys,
  credentials, `.git`, `.local`) show only their kind and no path or text.
  Token-like strings are redacted everywhere.
- **The card.** A panel above the agent plays each event as it arrives:
  - a read sweeps down the lines;
  - an edit strikes out removed lines and types in new ones;
  - a command types out, then shows its output.

  A backlog plays faster. Far away, the card shrinks to its header.
- **Motions and props.** The agent acts out each event. It holds a book while
  reading, types on a keyboard while editing, holds a terminal while running
  a command, searches with a lens and turns an orb while using a tool.
  - The motions and prop specs are in `world/data/agents/activity_motions.json`.
  - They are solved from limb directions in `activity_poses.json` by
    `scripts/diagnostics/solve_activity_poses.gd`.
  - Agents can revise a motion in the world with the animation tools, using
    target `activity:<kind>`. A preview plays on the companion, and a saved
    motion goes to `user://activity-motions.json`.
- **Settings.** The wrist computer's System page has two rows. **Agent
  activity** sets `full`, `icons` (header only) or `off`; `off` also stops
  the motions. **Show code** draws bars in place of text, for screen sharing.
  Both are saved in `user://graphics.cfg`.
- **Previewing.** `scripts/diagnostics/activity_preview.gd` renders the card
  and pose for sample events. Its views are `card`, `side`, `close`, `front`
  and `back`.

## Verification

`gateway/workbench-mcp.test.mjs` runs the endpoint against a fixture
repository: both credentials, the tool list, reads, rejected submissions, a
failed check, a revision, a passing check, a second agent, and discard.


`gateway/agents.test.mjs` drives both adapters through a stand-in CLI that
records its arguments, input, working directory and environment, and answers
in each CLI's documented output format. It covers selection, credential
removal, schema delivery, progress, failure, cancellation and timeout. The
Claude adapter has not yet been run against an installed Claude Code.

The F2 plan response keeps `agent_id: "local-codex"` and the interface still
says Codex. Both are protocol and display names in the Godot project.
