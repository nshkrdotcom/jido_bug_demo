# Prompt 9: Move Signal Core Modules

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Move Signal Core Modules (Prompt 9 of ~30)

## References Needed
- Doc 103, Section 1 (File System Migration)
- Doc 110, Lines 79-83 (Phase 2 Signal Integration)

## Current State
The signal system currently exists as a separate library (jido_signal) that needs to be integrated into the main jido library. The modules already use the correct namespace (Jido.Signal.*) but reside in the wrong location.

## Implementation Requirements

1. **Create Directory Structure**
   ```bash
   mkdir -p lib/jido/signal/{bus,dispatch,router,serialization,journal}
   ```

2. **Move Core Modules**
   Move the following files from jido_signal to jido:
   - `jido_signal/lib/jido_signal.ex` → `jido/lib/jido/signal.ex`
   - `jido_signal/lib/jido_signal/dispatch.ex` → `jido/lib/jido/signal/dispatch.ex`
   - `jido_signal/lib/jido_signal/bus.ex` → `jido/lib/jido/signal/bus.ex`
   - `jido_signal/lib/jido_signal/router.ex` → `jido/lib/jido/signal/router.ex`
   - `jido_signal/lib/jido_signal/error.ex` → `jido/lib/jido/signal/error.ex`
   - `jido_signal/lib/jido_signal/id.ex` → `jido/lib/jido/signal/id.ex`
   - `jido_signal/lib/jido_signal/util.ex` → `jido/lib/jido/signal/util.ex`

3. **Move Subdirectories**
   - All files in `jido_signal/lib/jido_signal/dispatch/*` → `jido/lib/jido/signal/dispatch/*`
   - All files in `jido_signal/lib/jido_signal/bus/*` → `jido/lib/jido/signal/bus/*`
   - All files in `jido_signal/lib/jido_signal/router/*` → `jido/lib/jido/signal/router/*`
   - All files in `jido_signal/lib/jido_signal/serialization/*` → `jido/lib/jido/signal/serialization/*`

4. **Update Application References**
   In all moved files, update:
   - `Application.get_env(:jido_signal, ...)` → `Application.get_env(:jido, ...)`
   - `Application.put_env(:jido_signal, ...)` → `Application.put_env(:jido, ...)`

5. **Update Mix Dependencies**
   In `jido/mix.exs`, remove the dependency on `:jido_signal`

## Key Code Locations
- Module namespaces are already correct (no defmodule changes needed)
- Application config references need updating (grep for `:jido_signal`)
- Import/alias statements should remain unchanged

## Success Criteria
- All signal modules exist under `lib/jido/signal/`
- No references to `:jido_signal` application remain
- Module compilation succeeds without errors
- Existing jido modules can alias signal modules without external dependency

## Rollback Strategy
If issues arise:
1. Restore from backup created before migration
2. Re-add `:jido_signal` dependency temporarily
3. Fix any compilation errors incrementally