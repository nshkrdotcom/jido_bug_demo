# Action Migration Plan: Removing Action from Jido

## Executive Summary

This document outlines the step-by-step plan to remove action functionality from the jido library and replace it with jido_action. This is a breaking change that will require careful coordination and comprehensive migration support.

## Current State Analysis

### Dependencies to Address
- **50+ source files** in jido reference Action modules
- **40+ test action implementations** use `Jido.Action`
- **Agent system** deeply integrated with actions
- **Runner system** executes action instructions
- **Exec engine** handles action execution

### Key Incompatibilities
1. Module namespace changes (`Jido.Action` → `JidoAction.Action`)
2. Error type mismatches (`Jido.Error` → `JidoAction.Error`)
3. Missing agent-specific actions in jido_action
4. Different ID generation strategies
5. Configuration approach differences

## Migration Phases

### Phase 1: Preparation (Week 1)
**Goal**: Set up infrastructure for migration without breaking existing code

#### Tasks:
1. **Create Compatibility Layer**
   ```elixir
   # jido/lib/jido/action_compat.ex
   defmodule Jido.ActionCompat do
     @moduledoc "Temporary compatibility layer for action migration"
     
     def normalize_error(%JidoAction.Error{} = error) do
       %Jido.Error{
         type: error.type,
         message: error.message,
         details: error.details,
         stacktrace: error.stacktrace
       }
     end
     
     def normalize_error(%Jido.Error{} = error), do: error
   end
   ```

2. **Add jido_action dependency**
   ```elixir
   # jido/mix.exs
   defp deps do
     [
       {:jido_action, "~> 1.0"},
       {:jido_signal, "~> 1.0"},
       # ... other deps
     ]
   end
   ```

3. **Create Migration Helpers**
   ```elixir
   # jido/lib/jido/migration/action_migrator.ex
   defmodule Jido.Migration.ActionMigrator do
     def migrate_action_module(module) do
       # Generates new module using JidoAction.Action
     end
   end
   ```

### Phase 2: Port Missing Actions (Week 1-2)
**Goal**: Ensure jido_action has all required functionality

#### Actions to Port:
1. **StateManager Actions**
   - `Jido.Actions.StateManager.Get`
   - `Jido.Actions.StateManager.Set`
   - `Jido.Actions.StateManager.Update`
   - `Jido.Actions.StateManager.Delete`

2. **Directive Actions**
   - `Jido.Actions.Directives.Emit`
   - `Jido.Actions.Directives.Spawn`
   - `Jido.Actions.Directives.SetState`

3. **Task Actions**
   - `Jido.Actions.Tasks.*`

#### Implementation:
```elixir
# jido_action/lib/jido_tools/agent/state_manager.ex
defmodule JidoTools.Agent.StateManager do
  defmodule Get do
    use JidoAction.Action,
      name: "agent.state.get",
      description: "Get value from agent state",
      category: "agent",
      tags: ["state", "read"]
      
    param :path, :string, required: true
    param :default, :any, required: false
    
    @impl true
    def run(params, context) do
      path = String.split(params.path, ".")
      value = get_in(context.agent_state, path) || params[:default]
      {:ok, %{value: value}}
    end
  end
end
```

### Phase 3: Update Core Modules (Week 2)
**Goal**: Switch jido core to use jido_action

#### Step 1: Update Imports
```elixir
# Before
alias Jido.Action
alias Jido.Error

# After  
alias JidoAction.Action
alias JidoAction.Error, as: ActionError
alias Jido.ActionCompat
```

#### Step 2: Update Agent Module
```elixir
defmodule Jido.Agent do
  # Remove action behavior definition
  # Update to use JidoAction modules
  
  def register_action(agent, action_module) do
    # Validate using JidoAction.Action behaviour
    if JidoAction.Action.action?(action_module) do
      # ... existing logic
    end
  end
end
```

#### Step 3: Update Instruction Module
```elixir
defmodule Jido.Instruction do
  # Change to wrap JidoAction.Instruction
  defdelegate new(action), to: JidoAction.Instruction
  defdelegate normalize(input, allowed, opts), to: JidoAction.Instruction
end
```

#### Step 4: Update Exec Module
```elixir
defmodule Jido.Exec do
  # Delegate to JidoAction.Exec with compatibility
  def run(instruction, params, context, opts) do
    case JidoAction.Exec.run(instruction, params, context, opts) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, ActionCompat.normalize_error(error)}
    end
  end
end
```

### Phase 4: Migrate Tests (Week 2-3)
**Goal**: Update all tests to work with new action system

#### Automated Migration Script:
```elixir
# scripts/migrate_tests.exs
defmodule MigrateTests do
  def run do
    test_files = Path.wildcard("test/**/*_test.exs")
    
    Enum.each(test_files, fn file ->
      content = File.read!(file)
      
      updated = content
      |> String.replace("use Jido.Action", "use JidoAction.Action")
      |> String.replace("alias Jido.Action", "alias JidoAction.Action")
      |> String.replace("Jido.Actions.", "JidoTools.")
      
      File.write!(file, updated)
    end)
  end
end
```

#### Manual Test Updates:
1. Fix compilation errors
2. Update error assertions
3. Verify action behavior
4. Add integration tests

### Phase 5: Remove Duplicate Code (Week 3)
**Goal**: Clean up jido codebase

#### Files to Remove:
```
jido/lib/jido/action.ex
jido/lib/jido/actions/
jido/lib/jido/exec.ex (after delegation setup)
jido/lib/jido/exec/
```

#### Update Mix.exs:
```elixir
defmodule Jido.MixProject do
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Application, []},
      # Remove action-related modules from supervision tree
    ]
  end
end
```

### Phase 6: Documentation & Tooling (Week 3-4)
**Goal**: Help users migrate their code

#### 1. Migration Guide
```markdown
# Migrating from Jido.Action to JidoAction

## Quick Start
1. Add `{:jido_action, "~> 1.0"}` to your dependencies
2. Run the migration script: `mix jido.migrate_actions`
3. Update your imports and aliases
4. Test your application

## Manual Migration Steps
...
```

#### 2. Mix Task for Migration
```elixir
# lib/mix/tasks/jido.migrate_actions.ex
defmodule Mix.Tasks.Jido.MigrateActions do
  use Mix.Task
  
  @shortdoc "Migrates action modules to use jido_action"
  
  def run(_args) do
    # Find all files using Jido.Action
    # Offer to update them
    # Generate report
  end
end
```

#### 3. Deprecation Warnings
```elixir
defmodule Jido.Action do
  @deprecated "Use JidoAction.Action instead"
  defmacro __using__(opts) do
    IO.warn("Jido.Action is deprecated. Please use JidoAction.Action", Macro.Env.stacktrace(__ENV__))
    quote do
      use JidoAction.Action, unquote(opts)
    end
  end
end
```

## Migration Timeline

### Week 1: Preparation
- [ ] Set up compatibility layer
- [ ] Add jido_action dependency
- [ ] Create migration tooling
- [ ] Port StateManager actions

### Week 2: Core Updates  
- [ ] Port remaining actions
- [ ] Update Agent module
- [ ] Update Instruction module
- [ ] Update Exec module
- [ ] Begin test migration

### Week 3: Cleanup
- [ ] Complete test migration
- [ ] Remove duplicate code
- [ ] Update documentation
- [ ] Release beta version

### Week 4: Finalization
- [ ] User testing and feedback
- [ ] Fix migration issues
- [ ] Update examples
- [ ] Release stable version

## Rollback Plan

If issues arise during migration:

1. **Revert Commits**: Git tags at each phase
2. **Feature Flags**: Can disable new code paths
3. **Compatibility Mode**: Keep old modules available
4. **Gradual Rollout**: Test with subset of users first

## Success Criteria

1. All tests pass with jido_action
2. No runtime errors in production
3. Dialyzer runs clean
4. Performance remains stable
5. Migration tools work for user code

## Risk Mitigation

### High Risk Areas:
1. **Agent State Management**: Test thoroughly
2. **Error Handling**: Ensure compatibility
3. **Performance**: Benchmark before/after
4. **User Code**: Provide migration tools

### Mitigation Strategies:
1. Extensive testing at each phase
2. Beta testing with key users
3. Compatibility layer for transition
4. Clear communication and documentation
5. Support channel for migration issues

## Post-Migration

After successful migration:
1. Remove compatibility layers (v2.0)
2. Optimize integration points
3. Add new features enabled by separation
4. Document best practices
5. Plan next architectural improvements