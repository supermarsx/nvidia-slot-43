# nvidia-slot-43 CLI Specification (v1.0)

**Last updated:** 2026-07-16  
**Objective:** Fix and stabilize NVIDIA Error 43 / equivalent device failure scenarios on multi-GPU systems with deterministic, low-risk automation.

## 1) Product Overview

`nvidia-slot-43` is a Rust CLI utility for:

- inventorying NVIDIA devices and related platform state,
- detecting likely causes for Code 43 and GPU initialization failures,
- generating ranked remediation plans with explicit risk levels,
- applying selected fixes in a safe sequence,
- and verifying recovery with a clear audit trail.

Primary audience: workstation and compute-admin users managing systems with multiple NVIDIA adapters.

## 2) Non-goals

- No BIOS flashing or firmware modifications.
- No unsigned driver installation bypasses.
- No implicit data-center orchestrator replacement (Slurm/Kubernetes integration is out of scope for v1).
- No automatic invasive actions without explicit `apply` confirmation.

---

## 3) Requirements and Acceptance Criteria

### 3.1 Problem Statement and Success Targets

- The tool must identify and help resolve one or more GPUs entering a failed/blocked initialization state on systems with 2+ adapters.
- It must return:
  - prioritized root-cause candidates,
  - confidence scores,
  - targeted actions per GPU/BDF,
  - expected side effects and risk level.
- It should minimize disruption: prefer reversible operations first, then controlled repairs.

Exit behavior:

- `0`: healthy / no action required
- `1`: healthy with warnings
- `2`: actionable issue detected
- `3`: manual intervention required
- `4`: internal/runtime failure

### 3.2 Supported Platforms

- Windows 11, Windows Server 2022/2025 (where supported)
- Linux x86_64 with proprietary NVIDIA driver stack (kernel modules + `nvidia-smi`)
- PowerShell/Bash shells for shell integration

### 3.3 Environment Inputs

- OS identity, secure-boot policy, driver branch signatures
- NVIDIA hardware inventory and bus topology
- Driver package metadata and version consistency
- Event and kernel logs
- NVML / adapter status / MIG mode details (if available)
- Current runtime usage (render/compute processes)
- Virtualization context (VM passthrough/host passthrough flags)

### 3.4 Detection & Rule Engine

Every rule MUST emit:

- `rule_id`
- `severity`: `high|medium|low`
- `confidence`: `0.0..1.0`
- `affected_gpus`: list of BDF/UUID/Index references
- `evidence`: normalized evidence references
- `remediation_recommended`: one or more action IDs
- `prerequisites` and `risk`

Recommended baseline rules:

1. explicit device status indicates Code 43 or init fault,
2. partial GPU enumeration mismatch (`nvidia-smi` differs from PCI enumeration),
3. user-kernel driver version divergence,
4. stale or stale-appearing PCIe topology/link instability,
5. virtualization passthrough inconsistencies,
6. service/module state conflict,
7. lock-contention or active usage blocking remediation,
8. duplicate/conflicting NVIDIA components and driver source mix,
9. repeated XID/NVRM patterns correlated with link or memory errors.

Each match must include a ranked action path:

- quick fix (non-disruptive),
- controlled fix (likely disruptive),
- manual escalation path.

### 3.5 Remediation and Safety

- **Read-only by default.** `scan`, `analyze`, and `report` cannot mutate.
- `--apply` is required for write actions.
- Mutating actions are executed with:
  - pre-flight validation,
  - state snapshot,
  - optional confirmation by risk class,
  - explicit rollback metadata.
- Actions that affect all GPUs require explicit `--global` flag and separate confirmation.
- Headless systems that would lose GPU output should fail safe unless `--allow-headless-risk` is set.

### 3.6 Failure and Recovery

- Every command returns structured errors with machine-code categories:
  - `NS43_ERR_USAGE`, `NS43_ERR_VALIDATION`, `NS43_ERR_PERMISSION`,
    `NS43_ERR_DEPENDENCY`, `NS43_ERR_CONFLICT`, `NS43_ERR_DRIVER`,
    `NS43_ERR_RECOVERABLE`, `NS43_ERR_INTERNAL`.
- Missing privileges, unsupported stacks, and parse ambiguity must stop with actionable guidance.
- Every failed mutable step records failed command, stdout/stderr hash, and rollback hint.

---

## 4) Command-Line Contract

### 4.1 Global Flags

| Flag | Type | Required | Purpose |
|---|---|---|---|
| `--config <path>` | path | no | Config file path (`toml|yaml`) |
| `--state-dir <path>` | path | no | Persistent state/log directory |
| `--format <table|json|yaml|ndjson|csv>` | enum | no | Output format |
| `--color <auto|always|never>` | enum | no | Color policy |
| `--log-level <error|warn|info|debug|trace>` | enum | no | Log verbosity |
| `--timeout <duration>` | duration | no | Global command timeout |
| `--yes` | bool | no | Auto-confirm prompts |
| `--dry-run` | bool | no | Simulate changes; no writes |
| `--json` | bool | no | Shortcut for `--format json` |
| `--profile <name>` | string | no | Select runtime policy profile |
| `--verbose` / `--quiet` | count/bool | no | Output density |

Environment fallback variables:
`NS43_CONFIG`, `NS43_STATE_DIR`, `NS43_FORMAT`, `NS43_LOG_LEVEL`.

### 4.2 Core Commands

#### `doctor`

Runs preflight checks and optional minor self-healing.

```bash
nvidia-slot-43 doctor [--quick|--full] [--fix] [--scope windows|linux|all]
```

- `--quick`: driver/tool presence, permissions, config validity, state dir writeability.
- `--full`: include PCIe/log/driver/package consistency checks.
- `--fix`: repair only safe defaults (permissions, stale lock cleanup, schema migration).

#### `scan`

Collect a signed evidence bundle.

```bash
nvidia-slot-43 scan [--scope all|adapter|system] [--target <gpu-id|uuid|index>] [--out <file>]
```

- Produces one run snapshot with:
  - device inventory,
  - driver metadata,
  - event log extract,
  - runtime modules/services state,
  - platform constraints.
- Automatically redacts sensitive fields unless `--raw`.

#### `analyze`

Run inference rules on a scan bundle.

```bash
nvidia-slot-43 analyze [--input <file>] [--from-cache] [--rule-set <name>] [--min-confidence 0.0..1.0]
```

Output includes ranked issue list and action mapping.

#### `plan`

Generate ordered remediation plan.

```bash
nvidia-slot-43 plan [--from <scan|analysis> ] [--risk-threshold low|medium|high] [--max-steps N] [--out <file>] [--policy safe|aggressive]
```

- Produces dependency-ordered steps.
- Includes per-step:
  - preconditions,
  - revert command(s),
  - expected success signal,
  - fallback if fails.

#### `apply`

Apply one or more planned actions.

```bash
nvidia-slot-43 apply [--plan <file>|--action <id>] [--safe|--aggressive] [--target <gpu-id>] [--parallel] [--force]
```

Rules:

- Never apply `global` actions by default when multiple GPUs are affected.
- `--parallel` only applies to read-only or isolated adapter-safe operations.
- Writes to state/logs include run ID and action IDs.

#### `verify`

Post-change verification.

```bash
nvidia-slot-43 verify [--last-run|--run-id <id>] [--target <gpu-id>] [--baseline <scan.json>]
```

- Re-runs diagnostics and compares against baseline.
- Classifies result as `recovered`, `partially recovered`, or `not recovered`.

#### `rollback`

Undo applied change where supported by action class.

```bash
nvidia-slot-43 rollback --run-id <id> [--action <id>] [--target <gpu-id>] [--force]
```

- Uses captured pre-apply state and generated rollback metadata.
- If full automatic rollback is not available, prints manual recovery script.

#### `report`

Generate human or machine-readable report for support workflows.

```bash
nvidia-slot-43 report --run-id <id> [--format markdown|json|yaml] [--include-remediation-log]
```

#### `config`

```bash
nvidia-slot-43 config view|set|get <key> [value] | reset
```

#### `completion`

```bash
nvidia-slot-43 completion [bash|zsh|fish|powershell]
```

### 4.3 Auxiliary Commands (v1.1+)

- `collect`: extract raw command outputs for support bundles.
- `export`/`import`: backup and migrate diagnostic policy + historical plans.
- `audit`: list action history and approval records.

---

## 5) Data Models

### 5.1 Evidence

Top-level fields:

- `run_id`
- `timestamp`
- `os`
- `host`
- `collector_version`
- `snapshot`
- `events`
- `gpus`
- `warnings`
- `unsupported_features`

### 5.2 Candidate

- `candidate_id`, `name`, `severity`, `confidence`, `category`
- `evidence_refs[]`
- `affected_gpus[]`
- `proposed_actions[]`
- `estimated_recovery_time`

### 5.3 Action

- `action_id`, `name`, `risk`, `scope`, `dry_run_supported`
- `preconditions[]`
- `commands[]`
- `expected_observations[]`
- `rollback`
- `owner` (platform: windows/linux/auto)

---

## 6) Rule & Remediation Libraries

Rules are loaded from embedded registry and optionally JSON/TOML overrides:

- core rules (bundled),
- enterprise override pack,
- environment-specific overrides.

All rules must be deterministic, include schema version, and expose:
- id, title, category, matcher inputs, score weights, recommended actions.

---

## 7) Logging and Evidence Handling

- Action logs include command, input hash, user, host, and pre/post snapshots.
- Redaction policy is mandatory for process command lines and user IDs by default.
- Full raw mode only via `--raw` and warning banner.
- NDJSON stream for long-running commands is line-delimited and resumable.

---

## 8) Adapter Design

Use a platform adapter abstraction:

- `platform/windows`:
  - `nvidia-smi`, PnP, event logs, services.
- `platform/linux`:
  - `nvidia-smi`, `lspci`, kernel logs, module info.
- Collectors emit standardized internal models, not raw text.

---

## 9) Test Strategy

### Unit

- Rule matching correctness.
- Parser strictness for varied command outputs.
- Confidence and ranking algorithm stability.

### Integration

- Golden snapshots for clean systems.
- Synthetic multi-GPU failure scenarios:
  - one-bad GPU,
  - all GPUs degraded,
  - virtualization passthrough edge cases,
  - permission-blocked repair paths.

### Safety

- Ensure `--dry-run` never mutates.
- Ensure all dangerous commands require confirmation unless `--yes`.
- Verify rollback artifacts are always generated for reversible actions.

### CI

- Windows and Linux runner matrix,
- command-contract tests for all output formats,
- artifact generation for reports.

---

## 10) Milestone Plan

### Phase 1 (Weeks 1–2): Core
- evidence collectors,
- scan/analyze,
- baseline command scaffolding.

### Phase 2 (Weeks 3–4): Intelligence
- rule registry,
- confidence scoring,
- plan generation.

### Phase 3 (Weeks 5–6): Remediation
- safe apply/verify/rollback engine,
- platform adapters.

### Phase 4 (Weeks 7–8): Hardening
- audit/report,
- docs,
- tests and packaging.

---

## 11) Risks and Mitigations

- Output parser drift across driver versions → resilient parsing + parser tests + raw evidence capture.
- Misclassification risk → confidence threshold and explicit user confirmation for risky remediation.
- Unsupported hardware/driver combinations → explicit unsupported state and manual guidance.
- Multi-process contention → lock model + conflict-aware queueing.

---

## 12) Terminology

- **Scope:** adapter subset (`all`, `single`, `system`) included in an operation.
- **Evidence run:** immutable snapshot produced by `scan`.
- **Candidate:** ranked cause hypothesis.
- **Action plan:** ordered list of remediation steps.
- **Run ID:** immutable execution identifier shared across scan/analyze/plan/apply/verify.

---

## 13) Change Control

All command behavior changes must be versioned and reflected in:

- this specification,
- `CHANGELOG.md`,
- and tests for contract behavior.

