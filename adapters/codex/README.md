# Adapter — OpenAI Codex

> Last verified with Codex CLI 0.146.0 on 2026-08-03.

Install the portable pack and native lifecycle wiring:

```bash
git clone https://github.com/aiosbrain/aios-engineering-harness .harness && rm -rf .harness/.git
mkdir -p .agents/skills .codex
cp -R .harness/skills/. .agents/skills/
cp .harness/agents/*.md .agents/
cp .harness/adapters/codex/hooks.json .codex/hooks.json
chmod +x .harness/hooks/*.sh .harness/adapters/run-hook.sh \
  .harness/adapters/codex/normalize.sh
cp .harness/AGENTS.md ./AGENTS.md
cp .harness/CONSTITUTION.md ./CONSTITUTION.md
printf 'make lint && make test\n' > .harness/check   # your repo's real check command
```

Codex project hooks require a trusted project and explicit review of changed hook
definitions. Inspect them with `/hooks`. Requirements: POSIX shell and `jq`.

The adapter owns Codex payload interpretation. It parses all `apply_patch` file
headers, rename destinations, and added lines, then sends protocol `1.0` JSON to the
portable policies. Secret scanning sees added lines only, so removing leaked material
is allowed. Safety normalization failure maps to exit 2; formatter failure maps to
allow. `HARNESS_TRACE_FILE` is available only as an opt-in eval artifact.

Codex's sandbox and approval policy remain the outer capability boundary. Hooks give
specific repository-policy feedback but are not a replacement for OS isolation,
managed requirements, or CI. Project hooks can also be skipped until trust is granted.

## Context injection (SessionStart / SubagentStart)

`hooks.json` wires `SessionStart` and `SubagentStart` to `inject-context.sh` (digest +
skill index, protocol `1.1` `context` action), translated to the documented
`{"hookSpecificOutput":{"hookEventName":...,"additionalContext":...}}` envelope. The
contract parse was live-verified on 0.145.0 (Codex injects the text as a developer
message). Two honest limitations, measured 2026-07-25:

- **Headless hook loading changed between 0.145.0 and 0.146.0.** Version 0.145.0 did
  not load project-level `.codex/hooks.json` `SessionStart` hooks (0/13 deliveries),
  while 0.146.0 does. Automation must still inject reviewed hooks explicitly rather
  than depend on ambient project discovery. The eval driver temporarily hides the
  equivalent project file during the subprocess so each policy fires exactly once,
  then restores it. Duplicate hook decisions fail observation completeness.
- Model-visible hook output is capped at ~2,500 tokens per entry (overflow spills to a
  file with a head/tail preview). `inject-context.sh` caps its output at 8,000 bytes
  and typical digest+index payloads are well under the limit.

`UserPromptSubmit` additionally runs `route-skills.sh` (literal trigger→skill routing,
one nested-envelope pointer max, marker dedupe — see the Claude adapter README for the
exact semantics; they are identical). The `codex exec` project-hook limitation above
applies to this event too.

Run before rollout:

```bash
bash .harness/evals/guards.test.sh
bash .harness/evals/conformance.test.sh
```

Primary sources: [hooks](https://developers.openai.com/codex/hooks),
[sandboxing and approvals](https://developers.openai.com/codex/security),
[skills](https://developers.openai.com/codex/skills), and
[`AGENTS.md`](https://developers.openai.com/codex/guides/agents-md).
