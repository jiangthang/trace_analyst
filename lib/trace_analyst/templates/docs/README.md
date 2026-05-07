# Trace investigations — human guide

<!-- trace-analyst-readme-version: {{GEM_VERSION}} -->

Trace investigations pair with `.cursor/skills/trace-analyst/SKILL.md`. **Production capture is explicit `TraceAnalyst.log` calls**, not ambient Rails logs.

## Your checklist

1. Merge instrument PRs; deploy.
2. **Enable capture** for the subject (`bundle exec trace-analyst enable <id>` when using Redis TTL activation, or your feature-flag UI).
3. Reproduce if needed.
4. Download batches from object storage into `{{LOCAL_DROP_DIR}}/<slug>/raw/`.
5. `bundle exec trace-analyst bundle <slug> --round <N>`
6. Paste the resulting `round-N.ndjson` path to the agent.
7. After cleanup PR merges, **disable capture** for the subject.

## Example S3 sync

```bash
SLUG=inv_2026_05_07_example
SUBJECT=1138
BUCKET=your-bucket
DEST="{{LOCAL_DROP_DIR}}/${SLUG}/raw"
mkdir -p "$DEST"
aws s3 sync "s3://${BUCKET}/{{BRANCH_PREFIX}}/${SUBJECT}/${SLUG}/" "$DEST"
ROUND=$(($(ls {{LOCAL_DROP_DIR}}/${SLUG}/round-*.ndjson 2>/dev/null | wc -l | tr -d ' ') + 1))
bundle exec trace-analyst bundle "${SLUG}" --round "${ROUND}"
```

## IAM sketch

Scope read-only principals to `{{BRANCH_PREFIX}}/*` on your bucket.

## Closing

Optionally delete `{{BRANCH_PREFIX}}/<subject>/<slug>/` in staging/prod buckets after investigation.
