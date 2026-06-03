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
├── package.json    # npm dependencies (managed via npm/pnpm)
└── vite.config.ts  # Vite build configuration
```

## Stack

- TypeScript 6.0+, strict mode, `noUncheckedIndexedAccess`
- React 19+, functional components and hooks
- TanStack Query for server state, TanStack Router for routing
- Tailwind CSS + shadcn/ui components
- react-hook-form + zod for forms
- vitest + testing-library for tests
- Generated API client from gRPC proto via `buf generate`

## Setup

```bash
npm install
npm run dev
```

## Testing

```bash
npm test
npm run lint
npm run typecheck
```

## Architecture note

All API calls go through the generated client (`src/generated/`). Hand-written
API clients are not permitted.
