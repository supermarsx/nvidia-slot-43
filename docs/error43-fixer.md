# error 43 fixer reference

## What this fixer does

This repository includes `scripts/nvidia_error43_fixer.ps1`, adapted from the community `nvidia-error43-fixer` logic.

The workflow is:

1. Detect NVIDIA display adapter entries under:
   - `HKLM\System\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`
2. Check adapter status for error code 43.
3. For affected adapters, set:
   - `RM1774520 = 1` (REG_DWORD)
4. Attempt adapter restart through available PnP methods.
5. Re-check status and report if the adapter becomes active.

## Why this key matters

`RM1774520=1` is a registry override used by the script family to bypass the default NVIDIA driver refusal path on certain hotplug/non-hotplug bridge and interface combinations.

## Risk profile (tool integration notes)

- This is a **targeted write** to display adapter keys.
- It is lower risk than driver uninstallation but still changes runtime initialization behavior.
- You should treat it as a constrained remediation:
  - require `--target` when possible,
  - capture pre-state,
  - include rollback guidance,
  - verify by `verify` immediately after apply.

## Suggested Rust action mapping

Action id (example): `ns43.fix.error43.reg_patch_legacy`

Preconditions:

- Platform: Windows
- Admin privileges required
- NVIDIA adapters present
- Candidate evidence indicates `code_43` / `init_blocked`

Execution steps:

- export pre-state snapshot (`reg query` + `pnputil`/`nvidia-smi` if present),
- set `RM1774520` only on matched adapter instance,
- attempt controlled disable/enable restart,
- verify status returns healthy,
- write action result + rollback hint.

Rollback hint:

- remove adapter, scan, and reinstall driver stack
- or clean reboot path after uninstall of the adapter device node.

## Related references

- Community source page: `https://egpu.io/nvidia-error43-fixer`
- Powershell refactor used in this repo: `scripts/nvidia_error43_fixer.ps1`
