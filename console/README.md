# Console

The Kuvera **console** is a TypeScript + React single-page application (SPA)
built with Vite. It provides investigators with a timeline view, evidence bundle
browser, and chain-of-custody log.

## MVP scope

- List forensic captures
- Capture detail view
- Simple timeline (table, not visualization)

## Layout

```
console/
├── src/            # React application source
├── package.json    # console dependencies (managed with pnpm)
├── pnpm-lock.yaml  # committed lockfile — CI installs with --frozen-lockfile
└── vite.config.ts  # Vite build configuration
```

## Stack

- TypeScript, strict mode, `noUncheckedIndexedAccess`
- React, functional components and hooks
- TanStack Query for server state, TanStack Router for routing
- Tailwind CSS + shadcn/ui components
- react-hook-form + zod for forms
- vitest + testing-library for tests
- Generated API client from gRPC proto via `buf generate`

## Setup

**pnpm only** — no npm, no yarn.

```bash
pnpm install
pnpm run dev
```

## Testing

```bash
pnpm test
pnpm run lint
pnpm run format:check
pnpm run typecheck
```

`pnpm run typecheck` fails with `TS18003` while `src/` is empty scaffolding, so it
is not wired into `make lint` yet — add it there once the first `.tsx` file lands.

Node.js and pnpm versions come from `mise.toml`; everything else from
`package.json`. See [docs/TOOLCHAIN.md](../docs/TOOLCHAIN.md).

## Architecture note

All API calls go through the generated client (`src/generated/`). Hand-written
API clients are not permitted.
