# What a draft may change

Every change made from inside Euclid is a Git draft that a person reviews and
commits. This page lists what a draft can reach, how each area is checked, and
when a committed change takes effect.

| Area | F4 editor | Agent drafts | Checked by | Takes effect |
| --- | --- | --- | --- | --- |
| Godot scripts, shaders, data, `main.tscn` | Yes | Yes | Core tests and smoke test | Live swap, reload, or **Restart Euclid** |
| Godot diagnostics and `world/scenes` | No | Yes | Core tests and smoke test | **Restart Euclid** |
| Gateway source, tests and schemas in `gateway/` | No | Yes | Gateway tests | Gateway reload on commit |
| `README.md` and `docs/*.md` | No | Yes | None | At once |

Agent drafts are the F2 source agent and drafts submitted over the
[development MCP endpoint](agents.md#development-tools-for-connected-agents).
The draft reports `activation` as `restart`, `gateway_restart` or `none`. The
Workbench status line still reads **Restart Euclid** for the last two.

## The kernel

Four gateway files cannot be changed by any draft:

| File | Why it is fixed |
| --- | --- |
| `gateway/workbench-source.mjs` | Defines what a draft may change, including this list |
| `gateway/workbench-git.mjs` | Verifies the reviewed diff and makes the commit |
| `gateway/workbench-runner.mjs` | Isolates checks and previews and removes their credentials |
| `gateway/handoff.mjs` | Replaces the running gateway and resumes it on failure |

Everything under `scripts/` and every file in the project root other than
`README.md` is outside every draft as well. That covers the launcher, the
check script, recovery, `package.json` and `AGENTS.md`. `world/project.godot`
stays outside too. Agents can read all of these.

The rule behind the list: a change made from inside must never be able to
remove the means of reviewing, checking, or undoing the next change. Edit the
kernel from a normal checkout, outside Euclid.

## Gateway reload

Godot restarts never restarted the gateway, so committed gateway code used to
wait for the next launcher start. A commit or revert that touches `gateway/`
now replaces the gateway process in place:

1. The running gateway starts the new code with `--preflight`. That builds a
   gateway on throwaway data and a free port and checks that it answers.
2. If the preflight fails, nothing else happens. The running gateway keeps
   serving and reports the failure.
3. Otherwise it stops listening and starts the replacement with the same port
   and the same three credentials.
4. Once the replacement answers an authenticated request, the old process
   exits. If it does not answer in time, the old process stops it and listens
   again.

The world keeps its credentials, so it reconnects by itself. Requests in
flight during the swap fail, and the world re-registers its MCP session on
its next sync. The replacement writes `.local/gateway.json` and
`.local/gateway.pid`, and logs to `.local/gateway-reload.log` and
`.local/gateway-reload-error.log`.

A failed reload leaves the committed code on disk with the previous code
still running. The Workbench state carries the reason in `gateway_notice`.
Revert the commit, or fix it with another draft.

`POST /v1/workbench/reload`, with the Workbench capability, runs the same
replacement by hand. Use it after gateway code changes outside Euclid, for
example after a merge. `EUCLID_DATA_DIR` moves the gateway's data directory
away from `.local/`; the tests use it.

## Verification

`gateway/scope.test.mjs` checks the path rules, the reload request on commit
and revert, and three real-process cases from a copy of the gateway: adopting
handed credentials, a successful replacement, and both failure paths. These
have run on Linux. They have not yet run on Windows.
