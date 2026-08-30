# agent-pipeline

File an issue; get a merged pull request. Claude plans the work, implements it on a branch,
reviews its own diff as a separate identity, and loops against CI until both are green — then
squash-merges without a human clicking anything.

Issues from anyone who could not push the change themselves stop at an approval gate, twice,
before any of their text reaches a prompt.

This is a **template repository**. Copy it into a project, fill in two files, and it runs.

```
issue opened
     |
     +-- [approval gate if the author cannot write here]
     |
  Agent · plan          reads the code, rewrites the issue body to BE the plan
     |
     +-- [approval gate if the author cannot write here]
     |
  Agent · implement     builds it on agent/issue-N, opens a PR, arms auto-merge
     |
     +---------------------------+
     |                           |
  CI (yours)              Agent · review     inline findings, then a verdict
     |                           |
     +----------> Agent · fix <--+           up to 10 rounds, 9 is an escalation
     |
   squash merge
```

## Setting it up

### 1. Copy the files

```sh
gh repo create my-project --template ElDavoo/agent-pipeline
# or, into a repository you already have:
cp -r agent-pipeline/.github/workflows/agent-*.yml   my-project/.github/workflows/
cp -r agent-pipeline/.github/actions/agent-stall     my-project/.github/actions/
cp -r agent-pipeline/.github/actions/project-setup   my-project/.github/actions/
cp    agent-pipeline/.github/scripts/agent-gates.sh  my-project/.github/scripts/
cp -r agent-pipeline/.github/ISSUE_TEMPLATE          my-project/.github/
cp    agent-pipeline/.github/workflows/lint-workflows.yml my-project/.github/workflows/
```

That last one is optional and recommended. It runs actionlint and zizmor over
`.github/workflows/`, which is the only test these files have; without it a mistake in one is
found when a release quietly does nothing. It is a file of its own rather than a job in `ci.yml`
precisely so that replacing `ci.yml` with your own does not take it with you.

### 2. Fill in the two hooks

Everything project-specific lives in exactly two files. Nothing else needs editing to get a
working pipeline.

| File | What it is |
|---|---|
| `.github/actions/project-setup/action.yml` | What a runner needs before your code will build. Ships as a working no-op with examples for Node, Python, Go, JVM and Rust. |
| `.github/scripts/agent-gates.sh` | The checks that must pass before a push is worth making. Ships as a working no-op with examples. |

The gates are a **script**, not a composite action, and that is not an accident. The agent is
told to run them itself before it finishes; a composite action cannot be called from inside a
prompt. A script is the only form both the workflow and the agent can reach — which is what
stops CI and the agent developing two different definitions of "passing", a disagreement that
otherwise costs a full fix round each time it is discovered.

Put the fast gates there. Slow legs — an emulator matrix, a release build — belong in CI, where
the fix loop reads their failures out of the logs.

### 3. Name your CI workflow

`agent-fix-ci.yml` watches one workflow by name:

```yaml
on:
  workflow_run:
    workflows: ["CI"]        # <- must match your CI workflow's `name:` exactly
```

**This is the one setting that cannot be a variable.** `workflow_run.workflows` is matched
before any expression is evaluated, so it takes a literal. Get it wrong and there is no error
message: the trigger simply never fires, and red CI on an agent branch is met with silence.

A `ci.yml` ships with the template that runs `agent-gates.sh`, so a fresh copy has a closed loop
immediately. If your repository already has CI, delete it and put your workflow's name here
instead.

### 4. Create the approval environment

Settings → Environments → **New environment** → name it `agent-approval`, tick **Required
reviewers**, add yourself, save.

This is what holds an outside issue. The queue happens *before* the gated job's first step, so
at the moment you are asked, no runner has checked anything out and no issue text has reached a
prompt.

### 5. Add the secrets

Both are **repository** secrets (Settings → Secrets and variables → Actions).

| Secret | What it is |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token` in the Claude Code CLI. |
| `AGENT_PUSH_TOKEN` | A fine-grained PAT with **Contents: write**, **Pull requests: write**, **Issues: write**, **Actions: write** on this repository. |

Two things about that PAT, both of which will bite otherwise:

- **It must not be `GITHUB_TOKEN`.** A branch pushed with `GITHUB_TOKEN` triggers no workflow
  runs at all, so CI would never run on the agent's pull request and the auto-merge armed on it
  would wait forever for a check that cannot arrive. The same is true of `gh workflow run`.
- **Do not give it `workflow` scope.** That would let an agent rewrite the review and CI gates
  that judge it, and then merge the rewrite. The cost is that the pipeline structurally cannot
  implement an issue asking for a workflow change — the plan stage is told to decline those.

Put them in **repository** secrets, not environment secrets. An environment secret is readable
only by a job that declares that environment, and the gate job is the only one that does — the
jobs that actually need the token would fail at checkout.

### 6. Labels

```sh
gh label create 'no-agent'       -c ededed -d 'Do not let the agent pipeline touch this'
gh label create 'agent:stop'     -c b60205 -d 'Halt the pipeline for this issue or PR'
gh label create 'agent:planned'  -c 0e8a16 -d 'Planned, waiting to be implemented'
gh label create 'agent:working'  -c fbca04 -d 'Being implemented'
gh label create 'agent:stalled'  -c d4c5f9 -d 'A stage stopped before finishing — will be re-run'
gh label create 'agent:stuck'    -c d93f0b -d 'Gave up — needs a human'
gh label create 'agent:declined' -c c5def5 -d 'Not work an agent should take unattended'
```

### 7. Let Actions approve pull requests

Settings → Actions → General → tick **Allow GitHub Actions to create and approve pull
requests**.

The review stage approves as `github-actions[bot]`, a different identity from the PAT that
opened the pull request — GitHub blocks an identity from approving its own. Verified in
production: a `github-actions[bot]` approval does satisfy a ruleset's required-approval rule.

### 8. Protect `main`

A ruleset on `main` with:

- **Require a pull request before merging**, 1 approving review, dismiss stale approvals on push
- **Require status checks to pass** — list your CI jobs by their *job* names
- Yourself as a bypass actor, so you can still push directly

Without the approval rule, auto-merge fires the moment CI is green and the reviewer is never
consulted. Without the status checks, the reverse.

## Customising

Everything below is a deliberate default, not a constant. All of it is in the workflow files.

| Setting | Where | Default |
|---|---|---|
| Fix rounds before giving up | `agent-fix.yml` | 10, with round 9 as an escalation |
| Concurrent agent pull requests | `agent-plan.yml`, `MAX_OPEN_AGENT_PRS` | 3 |
| Stall retries per stage | `agent-retry.yml`, `MAX_RETRIES` | 3, five hours apart |
| What the plan stage refuses | `agent-plan.yml` prompt | questions, policy calls, releases, migrations, workflow changes, anything too vague to test |
| House rules for the implementer | `agent-implement.yml` prompt | tests with the change; comments explain why; match the surrounding code |
| Model | every `claude_args` | `claude-opus-5` on review, default elsewhere |

**Write a `CLAUDE.md`.** Every stage is told to read it and treats it as authoritative. It is
where the invariants that lint and tests will not catch belong — the reasoning a reviewer needs
and a diff does not show. A repository without one gets a pipeline running on generic
instincts; the quality difference is larger than any prompt tuning here.

## Who is trusted

The pipeline asks one question about the person who filed an issue: **could they have pushed
this change themselves?** That is write access, checked through the collaborator permission API.

- A maintainer's issue runs unattended, end to end.
- Anyone else's queues at the `agent-approval` gate — once before planning, once before
  implementing.

No login is written into a workflow file. A solo repository trusts its owner; an organisation
trusts its committers; neither needs configuring.

The same predicate guards the plan itself. The issue body *becomes* the plan and is fed to an
agent holding a push token — and an issue author can edit their own issue at any time, including
after you approve. So the implement stage checks who **last wrote** the body and builds it only
if that was the plan stage or someone with write access.

That is deliberately not a hash pinned at approval. The gate exists so you can read the plan and
change it; a pin taken before your edit would refuse your own work. A body is a full
replacement, so the last writer owns all of it — which makes "who wrote it last" both the
simpler question and the right one. Edit the plan freely; what is refused is a body last touched
by someone who could not have pushed the change themselves.

## Controls

| Label | Applied by | Meaning |
|---|---|---|
| `agent:stop` | you | **The kill switch, and the one that always works.** Blocks every stage *and* cancels what is running. Issue or pull request, any time. |
| `no-agent` | you | Never touch this issue. **Only works applied at creation** — the *Note to self* issue template applies it for you. |
| `agent:planned` | pipeline | Planned, waiting to be implemented. |
| `agent:working` | pipeline | Being implemented. |
| `agent:stalled` | pipeline | A stage stopped before finishing; the sweeper will re-run it. |
| `agent:stuck` | pipeline | Gave up. The pull request is drafted, which disarms auto-merge. |
| `agent:declined` | pipeline | Not work an agent should take unattended. |

`no-agent` cannot work after the fact: the plan stage fires on `issues: opened`, and a label
added a second later loses the race. That is what the issue template is for, and why
`agent:stop` exists as the escape hatch that always works.

## Restarting a stage

Only two of these can be dispatched by hand. For the rest, restarting means re-triggering the
event they listen for.

| Stage | How | Caveat |
|---|---|---|
| plan | Re-run the run from the Actions tab | Cannot be dispatched — it fires on `issues: opened`, and reopening an issue is not that event |
| implement | `gh workflow run agent-implement.yml -f issue=N -f author=…` | Resets the branch and force-pushes |
| review | Close and reopen the pull request | Not a re-run: a re-run replays the workflow file as it was, so it cannot pick up a fix to that file |
| CI | Re-run failed jobs, or push | A push counts as a fix round; a re-run does not |
| fix | Cannot be started directly | Reusable workflow, no trigger of its own |
| retry sweep | `gh workflow run agent-retry.yml` | Runs itself every 5 hours |

### When a stage stops before it finishes

It labels `agent:stalled` and comments with the run link. `agent-retry.yml` sweeps every five
hours and re-runs it, up to three times *for that stage*, then hands over with `agent:stuck`.

That recovers a usage limit and nothing else. A permission denial or a bad prompt fails
identically every time and burns fifteen hours before saying so — so if the run shows a
`permission_denials_count` above zero, read it now rather than waiting for the sweep.

The retry markers are read only from comments posted by `github-actions[bot]`, and must name a
run of this pipeline's own workflows. An issue comment is world-writable; without both checks, a
commenter chooses which run gets re-run under a token with `actions: write`.

## Traps

Five things that behave differently from how they read. All of them have bitten this pipeline
in production.

1. **A workflow fix does not reach an in-flight pull request.** Workflows triggered by
   `pull_request` run from the *branch's* copy of the file. Fixing `agent-review.yml` on `main`
   leaves every open agent branch running the old one. Rebase the branch to pick it up.

2. **Re-running a run replays the old workflow file.** Same cause. To pick up a fix, re-trigger
   the event — close and reopen the pull request, or push.

3. **`--allowedTools` is an allowlist, not an addition to a default.** Anything absent is
   denied. The review stage's plugin dispatches subagents and shells out to `gh`; omitting
   `Task` or denying `gh` leaves it reviewing with no tools, and it will report findings it had
   no way to file. This is also what makes the allowlist safe — a verb nobody predicted is
   refused without having to be enumerated.

4. **Pushing to `main` during a run can break that run's push.** GitHub compares the pushed
   branch's workflow files against the default branch, and a `main` that moved is enough to make
   *unchanged* files "differ" — rejecting the push while naming a file the agent never opened.
   The implement and fix stages rebase onto `main` immediately before pushing, which handles it.

5. **`workflow_run.workflows` takes a literal.** No expressions, no variables. A typo is
   silence, not an error.

6. **A shellcheck suppression behaves differently inside a workflow.** actionlint only runs
   shellcheck when shellcheck is on `PATH`, so a local run without it is quieter than CI. And of
   the three ways to write a suppression, only one works here: it must sit immediately above the
   command it applies to, because a file-level `# shellcheck disable=` at the top of a `run:`
   block is silently ignored; nothing may follow it on its line, or the directive fails to parse
   and that failure is reported instead; and a prose comment beginning with the word
   `shellcheck` is itself read as a malformed directive. A literal backtick inside single quotes
   also reads as an expression, which is why the workflows pass one through a `tick` variable.

## What it costs

A planned-and-implemented issue is roughly two Claude runs plus one per fix round, and the
review stage is two more per push — one inline pass, one verdict. The concurrency cap exists
because of this: three open agent pull requests is already more diff than one person reviews in
an evening.

## Licence

MIT. See `LICENSE`.
