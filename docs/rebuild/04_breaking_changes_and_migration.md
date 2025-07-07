# Breaking Changes and Migration Guide

## Overview

This document provides a comprehensive list of breaking changes introduced by the Jido framework refactor and detailed migration instructions for each change.

## Breaking Changes Summary

### 1. Agent Struct Types (CRITICAL)
**Impact**: All agent implementations and pattern matching
**Severity**: High
**Migration Effort**: Medium

### 2. Action Module Namespace
**Impact**: All action references and imports
**Severity**: High  
**Migration Effort**: Low (mostly automated)

### 3. Error Type Changes
**Impact**: Error handling and pattern matching
**Severity**: Medium
**Migration Effort**: Medium

### 4. ID Generation Methods
**Impact**: ID formatting and validation
**Severity**: Low
**Migration Effort**: Low

### 5. Configuration Approach
**Impact**: Runtime configuration loading
**Severity**: Low
**Migration Effort**: Low

## Detailed Breaking Changes

### 1. Agent Struct Types

#### What Changed
Agents no longer create their own struct types. All agents now use `Jido.Agent.Instance`.

#### Before
```elixir
defmodule MyAgent do
  use Jido.Agent
  # Creates %MyAgent{} struct automatically
  
  def handle_message(%MyAgent{state: state} = agent, message) do
    # Direct pattern match on agent module struct
  end
end

# Usage
{:ok, agent} = MyAgent.new()
%MyAgent{state: state} = agent
```

#### After
```elixir
defmodule MyAgent do
  use Jido.Agent
  # No struct created
  
  def handle_message(%Jido.Agent.Instance{state: state, module: __MODULE__} = agent, message) do
    # Pattern match on Instance with module guard
  end
end

# Usage  
{:ok, agent} = MyAgent.new()
%Jido.Agent.Instance{state: state, module: MyAgent} = agent
```

#### Migration Steps
1. Update all pattern matches from `%YourAgent{}` to `%Jido.Agent.Instance{module: YourAgent}`
2. Remove any direct struct field access - use Instance fields
3. Update type specs from `@type t :: %__MODULE__{}` to `@type t :: Jido.Agent.Instance.t()`

#### Migration Script
```elixir
# mix run scripts/migrate_agent_structs.exs
defmodule MigrateAgentStructs do
  def run do
    files = Path.wildcard("lib/**/*.ex")
    
    Enum.each(files, fn file ->
      content = File.read!(file)
      module_name = extract_module_name(content)
      
      if module_name && uses_jido_agent?(content) do
        updated = content
        |> String.replace(
          ~r/%#{module_name}\{/,
          "%Jido.Agent.Instance{module: #{module_name}, "
        )
        |> String.replace(
          ~r/@type t :: %__MODULE__\{/,
          "@type t :: Jido.Agent.Instance.t()"
        )
        
        File.write!(file, updated)
      end
    end)
  end
end
```

### 2. Action Module Namespace Changes

#### What Changed
All action modules moved from `Jido.Actions.*` to `JidoTools.*` and use `JidoAction.Action` behavior.

#### Before
```elixir
alias Jido.Action
alias Jido.Actions.Basic
alias Jido.Actions.Workflow

use Jido.Action, name: "my_action"
```

#### After
```elixir
alias JidoAction.Action  
alias JidoTools.Basic
alias JidoTools.Workflow

use JidoAction.Action, name: "my_action"
```

#### Migration Steps
1. Update mix.exs to include `{:jido_action, "~> 1.0"}`
2. Replace all `Jido.Actions.` with `JidoTools.`
3. Replace `use Jido.Action` with `use JidoAction.Action`
4. Update any direct references to `Jido.Action` module

#### Automated Migration
```bash
# Run in your project root
mix jido.migrate_actions

# Or manually with sed
find . -name "*.ex" -o -name "*.exs" | xargs sed -i 's/Jido\.Actions\./JidoTools\./g'
find . -name "*.ex" -o -name "*.exs" | xargs sed -i 's/use Jido\.Action/use JidoAction\.Action/g'
```

### 3. Error Type Changes

#### What Changed
Error types are now namespaced under their respective packages with a unified base in `JidoCore.Error`.

#### Before
```elixir
{:error, %Jido.Error{type: :validation_error, message: "Invalid"}}

case result do
  {:error, %Jido.Error{type: :timeout}} -> handle_timeout()
  {:error, %Jido.Error{}} -> handle_other_error()
end
```

#### After
```elixir
{:error, %JidoCore.Error{type: :validation_error, message: "Invalid"}}

case result do
  {:error, %JidoCore.Error{type: :timeout}} -> handle_timeout()
  {:error, %JidoCore.Error{}} -> handle_other_error()
end
```

#### Migration Steps
1. Replace `Jido.Error` with `JidoCore.Error`
2. Update error creation functions
3. Check for any package-specific error types

#### Compatibility Shim
```elixir
# Add to your application temporarily
defmodule Jido.Error do
  @moduledoc "Compatibility shim - remove in next major version"
  
  defdelegate new(type, message, details \\ %{}), to: JidoCore.Error
  defdelegate format(error), to: JidoCore.Error
  
  def wrap(%JidoCore.Error{} = error) do
    IO.warn("Jido.Error is deprecated, use JidoCore.Error")
    error
  end
end
```

### 4. ID Generation Changes

#### What Changed
ID generation moved from `Jido.Util.generate_id()` to `JidoCore.ID.generate()`.

#### Before
```elixir
id = Jido.Util.generate_id()  # UUID v7 from jido_signal
```

#### After
```elixir
id = JidoCore.ID.generate()  # Standardized UUID v7
```

#### Migration Steps
1. Replace all calls to `Jido.Util.generate_id()`
2. Add `{:jido_core, "~> 1.0"}` to dependencies
3. Update any ID validation logic

### 5. Configuration Changes

#### What Changed
Configuration moved from compile-time to runtime with different application names.

#### Before
```elixir
# Compile-time
@default_timeout Application.compile_env(:jido, :default_timeout, 30_000)
```

#### After
```elixir
# Runtime
def default_timeout do
  Application.get_env(:jido_action, :default_timeout, 5_000)
end
```

#### Migration Steps
1. Update config files to use new application names
2. Change compile_env to get_env for runtime configuration
3. Update default values to match new defaults

## Test Migration

### Test Action Updates

#### Before
```elixir
defmodule TestAction do
  use Jido.Action, name: "test_action"
  
  param :value, :integer, required: true
  
  def run(params, _context) do
    {:ok, %{result: params.value * 2}}
  end
end
```

#### After
```elixir
defmodule TestAction do
  use JidoAction.Action, name: "test_action"
  
  param :value, :integer, required: true
  
  def run(params, _context) do
    {:ok, %{result: params.value * 2}}
  end
end
```

### Test Assertion Updates

#### Before
```elixir
assert {:error, %Jido.Error{type: :validation_error}} = result
assert %MyAgent{state: %{count: 5}} = agent
```

#### After
```elixir
assert {:error, %JidoCore.Error{type: :validation_error}} = result
assert %Jido.Agent.Instance{module: MyAgent, state: %{count: 5}} = agent
```

## Gradual Migration Strategy

### Phase 1: Add Dependencies (Non-breaking)
```elixir
# mix.exs
def deps do
  [
    {:jido, "~> 1.0"},
    {:jido_core, "~> 1.0"},    # Add this
    {:jido_action, "~> 1.0"},  # Add this
    {:jido_signal, "~> 1.0"}
  ]
end
```

### Phase 2: Add Compatibility Shims
Create `lib/my_app/jido_compat.ex`:
```elixir
defmodule MyApp.JidoCompat do
  # Temporary compatibility layer
  defmacro __using__(_) do
    quote do
      alias JidoCore.Error, as: JidoError
      alias JidoTools, as: JidoActions
      
      # Helper for agent struct migration
      def migrate_agent_struct(%module{} = old_struct) do
        %Jido.Agent.Instance{
          module: module,
          state: Map.from_struct(old_struct),
          id: Map.get(old_struct, :id, JidoCore.ID.generate()),
          config: %{},
          metadata: %{}
        }
      end
    end
  end
end
```

### Phase 3: Incremental Updates
1. Start with leaf modules (no dependencies)
2. Update tests alongside production code
3. Use feature flags for critical paths
4. Monitor error rates during rollout

### Phase 4: Cleanup
1. Remove compatibility shims
2. Delete deprecated modules
3. Update documentation
4. Tag stable release

## Common Migration Issues

### Issue 1: Pattern Match Failures
**Symptom**: `** (MatchError) no match of right hand side value: %Jido.Agent.Instance{...}`

**Solution**: Update pattern matches to use Instance struct

### Issue 2: Undefined Function
**Symptom**: `** (UndefinedFunctionError) function Jido.Actions.Basic.log/0 is undefined`

**Solution**: Update to `JidoTools.Basic.log/0`

### Issue 3: Type Spec Violations
**Symptom**: Dialyzer warnings about mismatched types

**Solution**: Update type specs to use new types from jido_core

### Issue 4: Configuration Not Loaded
**Symptom**: Default values used instead of configured values

**Solution**: Update configuration keys and runtime loading

## Verification Checklist

After migration, verify:

- [ ] All tests pass
- [ ] Dialyzer runs without warnings
- [ ] Application starts without errors
- [ ] Agent creation works
- [ ] Action execution works
- [ ] Signal routing works
- [ ] Error handling works
- [ ] Performance is acceptable

## Rollback Plan

If migration fails:

1. **Git tags** at each phase enable quick rollback
2. **Feature flags** can disable new code paths
3. **Compatibility mode** keeps old modules available
4. **Database migrations** are backward compatible
5. **Monitoring** alerts on error rate increases

## Getting Help

- **Documentation**: https://hexdocs.pm/jido/migration.html
- **Examples**: https://github.com/agentjido/jido-examples
- **Support**: Open issue at https://github.com/agentjido/jido/issues
- **Community**: Join #jido on Elixir Slack

## Timeline

- **Week 1-2**: Early adopters test migration
- **Week 3-4**: General availability with compatibility layer
- **Week 5-6**: Deprecation warnings added
- **Week 7-8**: Compatibility layer removed in 2.0

Plan your migration according to your deployment schedule and testing requirements.