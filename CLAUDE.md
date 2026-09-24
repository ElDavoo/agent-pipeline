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
- **One concurrency group per issue**, `agent-pipeline/agent/issue-N`, which every stage for
  that issue names, and a cap on how many run at once that only `agent-retry.yml` enforces. Four
  things about it are easy to break. First, `agent-fix.yml` must stay out of the group, because a
  reusable workflow asking for the group its own caller holds deadlocks. Second, the group
  belongs on the **job** unless the workflow calls a reusable one, because a run joins a
  workflow-level group before any job `if:` is evaluated and so takes the group's single pending
  slot even when it has nothing to do. Third, the retry sweep is the only thing that hands out
  slots, and it can only count what it can name: the workflow-name list in its idle check, and
  its `workflow_run` trigger, have to name every stage, since the API will not report which group
  a run holds. Fourth, `agent-conflicts.yml` is dispatched one pull request per run for the same
  reason. A batch run counts as one busy run however many agents it starts, and a stage that
  sizes its own batch from the free slots races the sweep for them. `MAX_PARALLEL_AGENTS` and
  `MAX_OPEN_AGENT_PRS` each have two copies, which must be kept equal.
- **Every stage in the group leaves a trace a displacement cannot erase**, because a run cancelled
  out of the queue never reaches its first step. The implement stage's is `agent:planned` with no
  pull request; the plan stage's is `agent:queued`, applied by triage outside the group; the
  review's is an agent pull request with no bot review on its head commit; the follow-up stage's
  is its run history or its queued/done markers. A conflicting pull request needs no marker,
  because GitHub's own mergeable state is the trace. `agent-retry.yml` restarts each from its
  trace.
  A new stage in the group needs one too, written before the job that asks for the group, or its
  runs can be lost without anything noticing.
- **The review is one pass, and its findings are data.** The verdict schema returns each finding
  as file, line, problem and fix, and the workflow renders them as the review's markdown body.
  That body is also the fix stage's whole payload, so a finding the schema cannot express is one
  the fix stage never sees. A second reviewing pass (the old inline one, posting as `claude[bot]`)
  doubles the reviews on every pull request. A free-text summary field brings back the
  one-paragraph blob.
- **The review has three verdicts, and reject is not a big request for changes.** `rejected`
  closes the pull request, deletes its branch, writes the review and the rejected plan on top
  of the issue body, and requeues the issue for a fresh plan; the second rejection of an issue
  hands it to a human. It is for work that would have to start over, so its findings are
  guidance for the next plan rather than patches for the fix stage. Without it the only exits
  are ten fix rounds ending in a draft, or a human's `agent:stop`. A verdict with both
  `approved` and `rejected` set is read as a rejection, never as a merge.
- **A schedule is a fallback, not a clock.** GitHub drops `schedule:` events under load without
  saying so, which is why `agent-retry.yml` also runs on `workflow_run` and `push`. Anything that
  has to happen soon after an event should be triggered by that event.

## Style

Comments explain *why* — a platform quirk, a race actually observed, a failure seen in
production — not what the code does. Most of the comments in the workflows record something that
went wrong once; keep that habit, because it is the only reason the traps are not repeated.

Commit messages follow the same rule: a plain-language lowercase subject, and a body explaining
the reasoning and the evidence.
