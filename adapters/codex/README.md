# Adapter — OpenAI Codex

> Last verified with Codex CLI 0.144.5 on 2026-07-17.

Install the portable pack and native lifecycle wiring:

```bash
git clone <this-repo> .harness && rm -rf .harness/.git
mkdir -p .agents/skills .codex
cp -R .harness/skills/. .agents/skills/
cp .harness/adapters/codex/hooks.json .codex/hooks.json
cp .harness/AGENTS.md ./AGENTS.md
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

Run before rollout:

```bash
bash .harness/evals/guards.test.sh
bash .harness/evals/conformance.test.sh
```

Primary sources: [hooks](https://developers.openai.com/codex/hooks),
[sandboxing and approvals](https://developers.openai.com/codex/security),
[skills](https://developers.openai.com/codex/skills), and
[`AGENTS.md`](https://developers.openai.com/codex/guides/agents-md).
