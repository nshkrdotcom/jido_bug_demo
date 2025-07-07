# Prompt 15: Update Imports and Dependencies

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update All Imports and Dependencies (Prompt 15 of ~30)

## References Needed
- Doc 103, Section 1 (Module Namespace Updates)
- Doc 110, Lines 100-103 (Update imports requirement)
- All moved signal modules from prompts 9-14

## Current State
After moving signal modules into jido, many files still reference the old module locations or use the external jido_signal dependency.

## Implementation Requirements

1. **Update Core Jido Files**
   Search and update imports in the following files:

   ```elixir
   # In lib/jido/agent/server.ex
   # Change:
   alias Jido.Signal  # This may need updating if it was external
   
   # In lib/jido/agent/server_signal.ex (line 4)
   # Verify:
   alias Jido.Signal  # Should now resolve to internal module
   alias Jido.Signal.Dispatch  # Add if needed
   
   # In lib/jido/sensors/bus_sensor.ex (after uncommenting)
   # Add:
   alias Jido.Signal
   alias Jido.Signal.Bus
   alias Jido.Signal.Dispatch
   ```

2. **Update Mix Dependencies**
   In `mix.exs`:

   ```elixir
   # Remove from deps():
   {:jido_signal, path: "../jido_signal"}  # or github: "xxx"
   
   # Ensure jido application starts signal components:
   def application do
     [
       extra_applications: [:logger],
       mod: {Jido.Application, []},
       # Add signal components to application env
       env: [
         signal: [
           bus: [agent_aware: true],
           dispatch: [default_adapter: :local],
           router: [zero_copy: true]
         ]
       ]
     ]
   end
   ```

3. **Update Application Supervisor**
   In `lib/jido/application.ex`, add signal components:

   ```elixir
   def start(_type, _args) do
     children = [
       # Existing children...
       
       # Add signal system components
       {Registry, keys: :unique, name: Jido.Signal.Registry},
       {Jido.Signal.Router.ZeroCopy, []},
       
       # Start default signal bus if configured
       signal_bus_spec()
     ]
     |> Enum.filter(& &1)  # Remove nils
     
     opts = [strategy: :one_for_one, name: Jido.Supervisor]
     Supervisor.start_link(children, opts)
   end
   
   defp signal_bus_spec do
     if Application.get_env(:jido, [:signal, :bus, :start_default], true) do
       {Jido.Signal.Bus, 
        name: Jido.Signal.DefaultBus,
        agent_aware: true}
     end
   end
   ```

4. **Update Error Module References**
   Since both jido and jido_signal have error modules:

   ```elixir
   # In moved signal files, update error references:
   # Search for: Jido.Signal.Error
   # Consider: alias Jido.Error (use main error module)
   
   # Or create compatibility alias in lib/jido/signal/error.ex:
   defmodule Jido.Signal.Error do
     @moduledoc "Compatibility alias for Jido.Error"
     defdelegate new(type, message, opts \\ []), to: Jido.Error
     defdelegate wrap(error, type, message), to: Jido.Error
     # ... other delegated functions
   end
   ```

5. **Update ID Generation**
   Both systems have ID generation. Consolidate:

   ```elixir
   # In lib/jido/signal/id.ex, delegate to core:
   defmodule Jido.Signal.ID do
     @moduledoc "Signal-specific ID generation"
     
     # Delegate to core ID module
     defdelegate generate(), to: Jido.Core.ID
     defdelegate generate!(), to: Jido.Core.ID
     
     # Signal-specific ID functions if needed
     def signal_id(prefix \\ "sig") do
       "#{prefix}_#{Jido.Core.ID.generate()}"
     end
   end
   ```

6. **Global Search and Replace**
   Run these searches across the codebase:

   ```bash
   # Find remaining references to jido_signal
   grep -r "jido_signal" lib/ test/
   
   # Find Application.get_env calls
   grep -r "Application.get_env(:jido_signal" lib/
   
   # Find old imports
   grep -r "JidoSignal" lib/
   ```

7. **Update Test Files**
   Update test helper and test files:

   ```elixir
   # In test/test_helper.exs
   # Remove any jido_signal application start
   
   # In signal-related tests
   # Update module references to internal paths
   ```

## Key Files to Check
- `lib/jido/agent/server.ex` - Signal handling
- `lib/jido/agent/server_signal.ex` - Signal creation
- `lib/jido/sensors/bus_sensor.ex` - Bus integration
- `lib/jido/application.ex` - Application startup
- `mix.exs` - Dependencies
- Any custom agents that might use signals

## Success Criteria
- No remaining references to `:jido_signal` application
- All imports resolve to internal modules
- Application starts without missing dependencies
- Signal system initializes properly
- Tests pass without import errors
- No dialyzer warnings about unknown modules

## Verification Steps
```elixir
# After updates, verify:

# 1. Clean compile
mix clean
mix compile --warnings-as-errors

# 2. Check dependencies
mix deps.tree | grep jido_signal  # Should return nothing

# 3. Start application
iex -S mix
# Should start without errors

# 4. Test signal system
alias Jido.Signal
signal = Signal.new!(%{type: "test", source: "test"})
# Should create signal successfully

# 5. Run tests
mix test

# 6. Run dialyzer
mix dialyzer
```