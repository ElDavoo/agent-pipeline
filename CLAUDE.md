# CLAUDE.md

This repository is a template. It holds the agent pipeline itself, not a project the pipeline
builds — so the workflows here describe how agents work rather than being run by them.

`README.md` is the setup guide and is accurate; read it before changing anything under
`.github/`.

## What must not drift

- **`.github/actions/project-setup/` and `.github/scripts/agent-gates.sh` are stubs on purpose.**
  They ship as working no-ops so a fresh copy runs end to end before anything is configured.
  Keep them succeeding, keep the examples current, and never make either one project-specific.
- **The gates are a script, not a composite action.** The agent runs them mid-turn from inside a
  prompt, where a composite action cannot be reached. Changing this splits CI's definition of
  "passing" from the agent's.
- **`workflow_run.workflows` takes a literal.** It cannot be a variable, and a wrong name fails
  silently rather than erroring.
- **The push token deliberately has no `workflow` scope.** Do not add it; an agent could then
  rewrite the gates that judge it and merge the rewrite. The plan stage is told to leave workflow
  changes out of scope for this reason, and that exclusion is load-bearing rather than
  conservative — but it excludes the *files*, not the issue. The plan stage has no refusal verdict
  at all: every issue that reaches it is planned, because an issue quietly declined and relabelled
  has no path back into the pipeline, and that is how work goes missing here.
- **Trust is write access, checked through the collaborator API**, never a login in a workflow
  file. Both the approval gate and the plan-provenance check use the same predicate.
- **One agent runs at a time**, through a shared `agent-pipeline` concurrency group. Two things
  about it are easy to break: `agent-fix.yml` must stay out of the group, because a reusable
  workflow asking for the group its own caller holds deadlocks; and the workflow-name list in
  `agent-retry.yml`'s second sweep has to name every stage that *is* in the group, since the API
  will not report which group a run holds.

## Style

Comments explain *why* — a platform quirk, a race actually observed, a failure seen in
production — not what the code does. Most of the comments in the workflows record something that
went wrong once; keep that habit, because it is the only reason the traps are not repeated.

Commit messages follow the same rule: a plain-language lowercase subject, and a body explaining
the reasoning and the evidence.
