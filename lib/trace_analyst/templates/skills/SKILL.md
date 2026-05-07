---
name: trace-analyst
description: Run a scoped production debug investigation loop. Use when the user describes a bug hitting one specific subject (e.g. tenant, shop) in production and you need temporary instrumentation, ship it, and analyze captured NDJSON logs. Required inputs are the configured subject id (see repo TraceAnalyst config) and a short bug description; the human merges PRs, enables capture, downloads logs from object storage, and drops the NDJSON under {{LOCAL_DROP_DIR}}/<slug>/round-N.ndjson for the agent to index.
---

<!-- trace-analyst-skill-version: {{GEM_VERSION}} -->

# Trace analyst investigations

This skill drives a multi-round production debug loop for **one subject id** at a time. The agent runs locally and never touches production directly. The human is the courier for log downloads and the gate for deploys.

Human-side guide: [`{{INVESTIGATIONS_DIR}}/README.md`](../../../{{INVESTIGATIONS_DIR}}/README.md).

## When to invoke

The user describes a bug that:

- Hits one identifiable **`{{SUBJECT_KEY}}`** in production (or can be scoped to one).
- Is not reproducible locally with confidence.
- Needs runtime evidence best captured via structured `TraceAnalyst.for(...).log(...)` probes.

## Recovery — fresh agent session

1. List `{{INVESTIGATIONS_DIR}}/*.md` for `Status: open` in front matter (if present in header bullets).
2. Read the **Hand-off log** table at the bottom — last row is current state.
3. Read **Instrumentation rounds** — **Files touched** is source of truth for probe locations.
4. Append a Hand-off row on every state change (`When | Action | By`).

## The loop

```
[describe bug + {{SUBJECT_KEY}}]
  ↓
agent: trace-analyst open <slug> --subject <id> --topic "..."
  ↓
agent: insert TraceAnalyst.for({{SUBJECT_KEY}}:, investigation:).log(...)
agent: update MD Instrumentation rounds table
agent: open PR on {{BRANCH_PREFIX}}/<slug>
  ↓
human: merge PR → deploy
human: enable capture for subject (CLI `trace-analyst enable`, Redis TTL adapter, or custom activation)
human: reproduce; sync object storage → bundle round NDJSON
human: gives agent path to round NDJSON
  ↓
agent: trace-analyst index <path>
agent: write Observations prose; update Hypotheses
  ↓
loop (more probes / fix PR / cleanup)
  ↓
agent: trace-analyst close <slug>
  ↓
human: merge cleanup PR; disable capture for subject
```

## Call-site API

```ruby
TraceAnalyst
  .for({{SUBJECT_KEY}}: SUBJECT, investigation: 'inv_YYYY_MM_DD_topic')
  .log(label: 'scope.input', data: { sku: 'AB-12', qty: 3 })
```

- `investigation`, `label`, and configured **`{{SUBJECT_KEY}}`** are required at the callsite (via `TraceAnalyst.for`).
- `data` must satisfy the redactor type allowlist (scalars / nested hashes / arrays of scalars only).
- Calls **no-op** when activation says capture is off for that subject.

### Probe safety

Wrap probes in sensitive transactions / callbacks / Sidekiq jobs:

```ruby
begin
  TraceAnalyst.for({{SUBJECT_KEY}}:, investigation:).log(label: '...', data: { ... })
rescue StandardError
  nil
end
```

### PII

Regex redaction applies by field name; optional `allow_pii: [:key]` per call (recorded in payload).

## CLI (repo root)

All local-only (no direct prod/AWS from CLI except `flush`/`enable`/`disable` loading your Rails app).

- `trace-analyst open <slug> --subject <id> --topic "..."` (`--shop` alias)
- `trace-analyst index <path-to-ndjson>`
- `trace-analyst bundle <slug> --round N`
- `trace-analyst timeline <slug> --round N [--where path=value] [--label L]`
- `trace-analyst grep <slug> --round N [--group-by path]`
- `trace-analyst close <slug>`
- `flush` / `enable` / `disable` — run via `bundle exec` from Rails root after configuring `config/initializers/trace_analyst.rb`.

Set `TRACE_ANALYST_REPO_ROOT` if not cwd.

## Cross-references

- Templates: `{{INVESTIGATIONS_DIR}}/TEMPLATE.md`
- Gem: `trace_analyst` {{GEM_VERSION}}
