# Analyzer

The Kuvera **analyzer** is a pool of Python workers that ingest sealed evidence
bundles and produce a normalized, queryable timeline. Workers run as Kubernetes
Jobs, fed by a NATS JetStream queue.

> **Architecture rule:** evidence is immutable. A worker never mutates a
> bundle. Re-analysis produces *new* artifacts that reference the original
> bundle's SHA-256.

## MVP scope

A single worker that reads a bundle and emits a JSON timeline. Memory
(Volatility3), filesystem diffing, and YARA/IOC matching come post-MVP.

## Layout

```
analyzer/
├── kuvera_analyzer/    # package source
├── tests/              # pytest suite
└── pyproject.toml      # canonical dependency + tooling config (uv)
```

## Tooling

- Python 3.12+, `uv` for dependency management (`pyproject.toml` is canonical).
- `ruff` for lint + format, `mypy --strict` for typing. Type hints are
  mandatory; no `Any` without justification.
- Logging via `structlog`.

## Setup

```bash
uv sync --extra dev
```

## Testing

```bash
uv run pytest
uv run ruff check .
uv run ruff format --check .
uv run mypy kuvera_analyzer
```

## References

- [volatilityfoundation/volatility3](https://github.com/volatilityfoundation/volatility3)
- [Velocidex/velociraptor](https://github.com/Velocidex/velociraptor) — closest non-K8s DFIR analog
