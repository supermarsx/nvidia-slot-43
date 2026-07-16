# nvidia-slot-43

`nvidia-slot-43` is a Rust CLI for diagnosing and recovering NVIDIA Code 43 (and related GPU fault states) on multi-GPU Windows and Linux systems.

The tool focuses on **safe, explainable repair workflows**:

- discover GPU topology and driver state,
- identify likely causes with confidence scoring,
- propose deterministic remediation plans,
- apply changes only when explicitly allowed,
- verify recovery and produce rollback instructions.

It is designed for technical operators managing 2+ NVIDIA adapters on workstations, render nodes, and compute boxes.

---

## What it does

- Detects Code 43-like conditions across NVIDIA adapters.
- Correlates hardware state, driver stack state, logs, and running workload context.
- Recommends actions ranked by safety and confidence.
- Supports read-only triage (`scan`), guided repair (`plan` + `apply`), and recovery verification (`verify`).
- Produces structured JSON/NDJSON for scripting and automation.

---

## Requirements

- NVIDIA GPUs present (single or multiple).
- Recommended:
  - `nvidia-smi`
  - NVIDIA driver stack installed and functional.
- Admin/root privileges when running mutation workflows:
  - Windows: elevated terminal.
  - Linux: sudo/root for driver/module-related tasks.

---

## Installation

> Rust 1.80+ recommended.

```bash
cargo install nvidia-slot-43
# or
git clone https://example.com/your-org/nvidia-slot-43.git
cd nvidia-slot-43
cargo build --release
```

Generate shell completions:

```bash
nvidia-slot-43 completion bash > /etc/bash_completion.d/nvidia-slot-43
nvidia-slot-43 completion zsh > ~/.zsh/completions/_nvidia-slot-43
```

---

## Quick start

```bash
# 1) Read-only discovery and evidence collection
nvidia-slot-43 scan --scope all --format json > evidence.json

# 2) Build a ranked fix plan
# Optional: inspect candidates first
nvidia-slot-43 analyze --input evidence.json --format json > analysis.json

# Generate ranked plan from analysis
nvidia-slot-43 plan --from analysis.json --out plan.json

# 3) Review, then apply only with explicit approval
nvidia-slot-43 apply --plan plan.json --yes

# 4) Verify results
nvidia-slot-43 verify --last-run
```

Dry-run is default-safe:

```bash
nvidia-slot-43 apply --plan plan.json --dry-run
```

---

## Core command surface

- `scan`: collect and normalize evidence from hardware, drivers, and logs.
- `analyze`: detect failure candidates from one or more scans.
- `plan`: generate repair plan(s) with priorities and risk levels.
- `apply`: execute selected remediation steps with rollback metadata.
- `verify`: confirm recovery and compare against baseline state.
- `report`: emit markdown/JSON/NDJSON for sharing.
- `rollback`: revert supported in-tool actions when possible.
- `doctor`: preflight checks and dependency validation.
- `completion`: shell completion support.
- `config`: view/update runtime behavior.

For complete command-level spec and schemas, see [docs/cli-spec.md](docs/cli-spec.md:1).

---

## Output formats

All non-interactive commands support:

- `table` (default for humans)
- `json`
- `yaml`
- `ndjson`
- `csv` (where flattened structures apply)

JSON envelope shape:

```json
{
  "status": "ok|warning|error",
  "code": 0,
  "message": "short summary",
  "run_id": "uuid",
  "data": {},
  "meta": { "version": "x.y.z", "command": "scan", "timestamp": "..." }
}
```

---

## Safety model

- No mutation without explicit `apply`.
- `--dry-run` and `plan` modes never perform writes.
- High-risk actions require explicit confirmation unless `--yes` is set.
- Critical paths produce rollback instructions automatically.
- Headless GPU-output risk is detected and blocked unless explicitly overridden.

---

## Typical workflow

```text
1. scan --scope all --out ./runs/2026-07-16T0000-scan.json
2. analyze ./runs/2026-07-16T0000-scan.json
3. plan --from ./runs/2026-07-16T0000-scan.json --risk-threshold medium
4. apply --plan ./runs/.../plan.json --safe
5. verify --from ./runs/.../baseline.json --to ./runs/.../post.json
6. report --run-id <run-id> --format markdown
```

---

## Development status

This repository currently contains the design and specification first. The initial implementation plan is complete and should be used as the implementation contract.

If you are implementing next:
- Start with `docs/cli-spec.md`
- Build parser + data model first, then collector adapters, then remediation engine.

---

## Contributing

When adding a new collector/remediation rule:

1. Add rule metadata to the registry.
2. Add evidence parser tests.
3. Add command integration tests.
4. Add rollback and failure-path coverage.

---

## Support and reporting issues

When sharing failures, include:

- `nvidia-slot-43 scan --scope all --format json --out ...`
- `nvidia-slot-43 analyze --input ...`
- `nvidia-slot-43 plan --input ... --format json`
- OS, driver version, and GPU model list.
