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
| `draft_status` | Owner, version, files, diff, check status, scope and output of the active draft, its `base` commit, and `behind_main` when the main branch has moved past it |
| `submit_draft` | Create a draft from complete file contents and deletions, or revise the agent's own draft on top of its current version |
| `run_checks` | Start the isolated project checks for the agent's own draft |
| `rebase_draft` | Replay the agent's own draft onto the tip of the main branch. It keeps its id and needs fresh checks. A conflict names the files and changes nothing |
| `discard_draft` | Discard the agent's own draft |
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
`POST /v1/workbench/focus` with a draft `id` changes it, and `state` lists
every draft under `drafts`. Committing one draft moves the main branch past the
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
