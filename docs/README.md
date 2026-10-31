# Docs

Architecture documentation, ADRs (Architecture Decision Records), and guides
for the Kuvera DFIR platform.

## Contents

- `PROJECT-MANAGEMENT.md` — project management process
- `TOOLCHAIN.md` — which tools the project uses, where each version is pinned,
  and how to add a new one
- `DEVELOPMENT-SETUP.md` — clean-machine setup: mise, uv, Docker, first
  dev cluster, troubleshooting
- `TESTING.md` — what each check covers, where it runs, what blocks a merge,
  and what is by hand only

## Planned additions

- `architecture/` — component interaction diagrams and data flow
- `adr/` — Architecture Decision Records
- `guides/` — operator and investigator guides
- `api-reference/` — generated from proto definitions via buf
