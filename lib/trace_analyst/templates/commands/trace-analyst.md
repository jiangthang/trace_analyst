---
description: Start or resume a TraceAnalyst production investigation — follow the trace-analyst skill end-to-end.
---

<!-- trace-analyst-command-version: {{GEM_VERSION}} -->

You are helping debug production using **TraceAnalyst** (gem `trace_analyst`).

1. Open and follow the workspace skill at `.cursor/skills/trace-analyst/SKILL.md` (recovery steps, loop, probe safety, CLI).
2. Insist on explicit **`{{SUBJECT_KEY}}`** from the user plus a short bug description and any anchor record ids / request ids.
3. Use `trace-analyst open …`, add `TraceAnalyst.for({{SUBJECT_KEY}}:, investigation: …).log(…)` probes only (no behavior fixes in probe PRs), drive rounds with `index` / `timeline` / `grep`, and finish with `trace-analyst close …` + cleanup PR.

If templates are missing, run `bundle exec trace-analyst install --subject-key {{SUBJECT_KEY}}`.
