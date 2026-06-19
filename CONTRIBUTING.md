# Contributing to Kuvera

## Status: pre-alpha, not yet open to external contributions

Kuvera is under active early development. The APIs, CRDs, and internal
architecture are changing rapidly. We are **not accepting pull requests from
outside the core team** at this stage.

When the project reaches a state where external contributions are welcome,
this document will be updated with full guidelines covering the review
process, release cadence, and coding standards.

---

## Developer Certificate of Origin (DCO)

Every commit to this repository must carry a **Signed-off-by** trailer. This
is a lightweight way of confirming that you wrote the code and have the right
to contribute it under the project's licence, as described in the
[Developer Certificate of Origin](https://developercertificate.org/).

### Adding sign-off automatically

Pass `-s` (or `--signoff`) to `git commit`:

```
git commit -s -m "your commit message"
```

Git will append a line to the commit body:

```
Signed-off-by: Your Name <you@example.com>
```

The name and email are taken from your `user.name` and `user.email` git
config values. Set them if they are not already:

```
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### Fixing commits that are missing sign-off

Amend the most recent commit:

```
git commit --amend -s
```

Sign off every commit in the current branch in one step:

```
git rebase --signoff origin/main
```

### Enforcement

DCO sign-off is enforced automatically on every pull request by
`.github/workflows/dco.yml`. A PR that contains any unsigned commit will
fail the DCO check and cannot be merged until the commits are amended.

---

## Branch naming

Branches are named after the GitHub issue they implement:

```
<issue-number>-<ticket-id>-<component>-<slug>
```

Examples:

```
4-t11-infra-scaffold-monorepo-directory-structure
10-t17-infra-github-actions-ci-lint-test-on-every-pr
```

Where:
- `<issue-number>` is the GitHub issue number
- `<ticket-id>` is the sprint ticket identifier in lowercase (e.g. `t11`, `t17`)
- `<component>` is the component label (infra, sensor, operator, api, analyzer, console, deploy, docs)
- `<slug>` is a kebab-case description of the change

No commits directly to `main` or `dev`. Every change goes through a branch and a pull request.

See [docs/PROJECT-MANAGEMENT.md](./docs/PROJECT-MANAGEMENT.md) for the full label taxonomy and workflow conventions.
