# Kuvera Project Management

This document describes how the Kuvera project is run on GitHub: the Project board schema, label taxonomy, sprint cadence, Definition of Done, and issue template index. It is the authoritative reference for project management conventions.

For the roadmap itself (sprint dates, goals, Gantt), see `docs/roadmap.md`.  
For coding conventions, see `CLAUDE.md`.  
For product spec, see `PROJECT.md`.

## Source of truth

- **Live ticket state, sprint membership, status, dates:** the [Kuvera GitHub Project](https://github.com/users/Jacklevi02/projects) (Project items are canonical).
- **Roadmap, sprint goals, acceptance criteria, Gantt:** `docs/roadmap.md` in this repo.
- **Coding conventions, architecture rules:** `CLAUDE.md` in this repo.
- **Definition of Done, project conventions:** this file.

If the Project and `docs/roadmap.md` disagree on a ticket, the Project wins. If they disagree on a sprint goal or acceptance criterion, the roadmap wins.

## Repository

`Jacklevi02/Kuvera-DFIR` — monorepo containing sensor, operator, api, analyzer, console, deploy, and docs.

## Sprint cadence

- Sprint length: 2 weeks.
- Sprint week: Monday to Sunday.
- The next sprint starts the Monday immediately following the previous sprint's Sunday.
- MVP runs Sprint 1 through Sprint 6 (25 May – 16 Aug 2026).
- Sprint dates and goals: see `docs/roadmap.md`.

## GitHub Project schema

The project uses a single GitHub Project of type "Team" to support iterations and the Roadmap view.

### Custom fields

| Field | Type | Values |
|---|---|---|
| Status | Single-select (built-in) | Backlog, Todo, In Progress, In Review, Done, Blocked |
| Sprint | Iteration | Sprint 1 (25 May 2026, 2w), Sprint 2 (8 Jun 2026, 2w), Sprint 3 (22 Jun 2026, 2w), Sprint 4 (6 Jul 2026, 2w), Sprint 5 (20 Jul 2026, 2w), Sprint 6 (3 Aug 2026, 2w) |
| Component | Single-select | sensor, operator, api, analyzer, console, deploy, docs, infra |
| Type | Single-select | epic, feature, task, spike, chore, bug |
| Estimate | Single-select | 0.5d, 1d, 2d, 3d, 5d |
| Start date | Date | — |
| Target date | Date | — |
| Priority | Single-select | P0, P1, P2 |
| Chain-of-custody touched | Boolean | true / false |

### Field usage rules

- **Sprint** is an iteration field (not single-select) so the Roadmap view treats it natively and `@current` filters work.
- **Component** and **Type** are duplicated as labels on the issue itself. This is intentional: labels are visible everywhere (issue lists, PRs, `gh issue list`); Project fields are only visible inside the Project. Claude Code filters from the CLI using labels.
- **Estimate** uses fixed buckets to avoid spurious precision. If a ticket is bigger than 5d, split it.
- **Start date** and **Target date** are required for the Roadmap view to render a Gantt-equivalent.
- **Chain-of-custody touched** is duplicated as the `chain-of-custody` label and triggers extra review per `CLAUDE.md` rule 4.

### Views

| View | Layout | Grouping | Filter | Sort |
|---|---|---|---|---|
| Current Sprint | Board | Status | Sprint = @current | Priority asc |
| Roadmap | Roadmap | Component | — | Start date asc |
| All Epics | Table | Sprint | Type = epic | Sprint asc |
| By Component | Board | Component | Sprint = @current | — |
| Backlog | Table | Component | Sprint is empty | Priority asc |
| Chain-of-Custody Watch | Table | Sprint | Chain-of-custody touched = true | Sprint asc |

## Label taxonomy

Labels mirror the Project's `Component` and `Type` fields so they are visible on the issue outside the Project context, and so CLI tools (including Claude Code) can filter without querying the Project API.

### Component labels

| Label | Colour | Used for |
|---|---|---|
| `component:sensor` | `#1d76db` | eBPF DaemonSet work |
| `component:operator` | `#0e8a16` | Kubernetes operator and CRDs |
| `component:api` | `#5319e7` | gRPC + REST API gateway |
| `component:analyzer` | `#fbca04` | Python analyzer workers |
| `component:console` | `#e99695` | TypeScript + React frontend |
| `component:deploy` | `#c5def5` | Helm charts, manifests, dev cluster |
| `component:docs` | `#bfd4f2` | Markdown docs, ADRs, READMEs |
| `component:infra` | `#d4c5f9` | CI, Makefile, tooling, lint config |

### Type labels

| Label | Colour | Used for |
|---|---|---|
| `type:epic` | `#3e4b9e` | Sprint-sized parent issues with sub-issues |
| `type:feature` | `#a2eeef` | New user-facing capability |
| `type:task` | `#cccccc` | Default. A concrete unit of work, 0.5d–2d |
| `type:spike` | `#f9d0c4` | Timeboxed investigation, output is a written finding |
| `type:chore` | `#ededed` | Cleanup, refactor, dependency bumps |
| `type:bug` | `#d73a4a` | Something is broken |

### Priority labels

| Label | Colour | Meaning |
|---|---|---|
| `priority:p0` | `#b60205` | Blocks the MVP. Drop everything. |
| `priority:p1` | `#d93f0b` | Blocks the current sprint. |
| `priority:p2` | `#fbca04` | Should fix when convenient. |

### Special labels

| Label | Colour | Used for |
|---|---|---|
| `chain-of-custody` | `#000000` | Touches capture, sealing, hashing, signing, or transparency log. Requires extra review per `CLAUDE.md` rule 4. |
| `good-first-issue` | `#7057ff` | Reserved for post-MVP when the repo opens to contributors. |

## Issue templates

Templates live in `.github/ISSUE_TEMPLATE/`. Blank issues are disabled to enforce structure.

| Template | File | Use for |
|---|---|---|
| Epic | `epic.yml` | Sprint-sized work with multiple sub-issues. One epic = one sprint goal area. |
| Task | `task.yml` | Default. A concrete unit of work, 0.5d–2d, linked to a parent epic. |
| Spike | `spike.yml` | Timeboxed investigation. Output is a written finding (comment or ADR). |
| Bug | `bug.yml` | Something is broken. |

All templates require:

- Acceptance criteria (objectively verifiable).
- Component (mirrors the Project field).
- Chain-of-custody flag (mirrors the Project field).

Tasks additionally require a parent epic and an estimate. Epics additionally require a sprint assignment.

## Definition of Done

### Ticket level

A ticket can move to `Done` when:

1. Acceptance criteria are all met.
2. Tests added or updated (where applicable; spikes are exempt).
3. `make lint` passes.
4. `make test` passes.
5. Code reviewed (self-review acceptable while solo; required PR review once team grows).
6. Merged to `main` via PR (no direct commits to `main`).
7. If `chain-of-custody` labelled: change explicitly called out in the PR description and reviewed against `CLAUDE.md` rule 4.

### Sprint level

A sprint is closed when:

1. All tickets in the sprint are either `Done` or explicitly moved to a later sprint with a written reason.
2. `make lint` and `make test` pass on `main`.
3. `docs/sprint-demos/sprint-N.md` is written, containing:
   - **What was built** — short prose summary.
   - **What works end-to-end** — bullet list of demoable flows, or "infrastructure-only sprint, no user-visible output" if applicable.
   - **What was punted** — tickets moved to a later sprint and why.
   - **Screencast or terminal recording** — link, where it makes sense.
4. The Roadmap view is reviewed for dependency drift into the next sprint.
5. Any new `chain-of-custody`-labelled tickets are reviewed against `CLAUDE.md` rule 4.

Infrastructure-only sprints are allowed; the demo writeup still has to exist and explain what was done.

## Sprint demo writeups

- Path: `docs/sprint-demos/sprint-N.md`.
- Written before closing the sprint.
- Durable, version-controlled record of what shipped each sprint.
- This is the only sprint-related markdown in the repo beyond `docs/roadmap.md`; everything else lives in the GitHub Project.

## Workflow conventions

1. No commits to `main` directly. Feature branches and PRs only.
2. Branch naming: `<type>/<short-description>` — e.g. `feature/sensor-execve`, `fix/operator-rbac`, `chore/bump-go-version`.
3. PR descriptions reference the issue: `Closes #42`.
4. Chain-of-custody-touching PRs must state so explicitly in the description.
5. DCO sign-off required on every commit. No CLA.
6. Tickets stay in `In Progress` for at most one sprint. If a ticket spans sprints, it gets split.

## Roles (for when the team grows)

While solo, all roles are the maintainer. Documenting now for forward compatibility:

- **Maintainer:** approves PRs, owns the Project, owns the roadmap.
- **Reviewer:** any contributor with merge rights, required for non-trivial PRs.
- **Chain-of-custody reviewer:** the maintainer for now; will be a named role with separate sign-off once the team grows beyond one.

## Tooling assumptions

- `gh` CLI for issue and Project manipulation.
- `make` targets defined in `CLAUDE.md`: `dev-cluster`, `build`, `deploy-dev`, `tes
