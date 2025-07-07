# Completing Jido Action Separation - Technical Implementation

## Overview

The jido_action extraction is 70% complete but has code duplication and unclear boundaries. This document provides the implementation plan to complete the separation properly.

## Current State Analysis

### What's Already Separated ✅

#### 1. Package Structure
```
agentjido/
├── jido_action/
│   ├── lib/jido_action/
│   │   ├── action.ex           # Main action implementation
│   │   ├── instruction.ex      # Instruction handling
│   │   └── exec.ex            # Execution engine
│   ├── mix.exs                # Independent package
│   └── test/
├── jido/
│   └── lib/jido/
│       ├── action.ex          # ❌ DUPLICATE - needs removal
│       ├── instruction.ex     # ❌ DUPLICATE - needs removal
│       └── exec.ex           # ❌ DUPLICATE - needs removal
```

#### 2. Working Dependencies
- `jido_action` has its own mix.exs and version
- Core functionality extracted to jido_action package
- Test suites separated

### What Needs Completion ❌

#### 1. Code Duplication Removal
Four files exist in both packages:
- `Jido.Action` (duplicated)
- `Jido.Instruction` (duplicated)  
- `Jido.Exec` (duplicated)
- `Jido.Error` (duplicated)

#### 2. Dependency Clarity
- jido currently doesn't depend on jido_action
- Unclear which implementation is authoritative
- No boundary contracts defined

## Implementation Plan

### Step 1: Establish Dependency Relationship

#### Update jido/mix.exs
```elixir
defmodule Jido.MixProject do
  def project do
    [
      app: :jido,
      version: "1.3.0",  # Bump for breaking change
      # ...
    ]
  end

  defp deps do
    [
      {:jido_action, "~> 1.0"},
      {:jido_signal, "~> 1.0"},
      # ... other deps
    ]
  end
end
```

### Step 2: Remove Duplicate Files from Jido Core

#### Files to Delete from jido/lib/jido/:
```bash
# Remove these files - they now live in jido_action
rm lib/jido/action.ex
rm lib/jido/instruction.ex  
rm lib/jido/exec.ex
rm lib/jido/error.ex  # If duplicated
```

#### Update Imports in Jido Core
```elixir
# In jido/lib/jido/agent.ex
defmodule Jido.Agent do
  # Change from:
  # alias Jido.Action
  
  # To:
  alias JidoAction.Action
  alias JidoAction.Instruction
  alias JidoAction.Exec
  
  # Rest of implementation unchanged
end
```

### Step 3: Define Clean Boundary Contracts

#### Create jido/lib/jido/action_boundary.ex
```elixir
defmodule Jido.ActionBoundary do
  @moduledoc """
  Clean boundary between jido core and jido_action package.
  This module defines the contract and delegates to jido_action.
  """
  
  alias JidoAction.{Action, Instruction, Exec}
  
  @type action_result :: 
    {:ok, result :: any()} |
    {:ok, result :: any(), directives :: [map()]} |
    {:error, reason :: term()}
  
  @spec execute_action(Jido.Agent.t(), atom(), map()) :: action_result()
  def execute_action(%Jido.Agent{} = agent, action_name, params) do
    case Action.get_action(agent, action_name) do
      {:ok, action} ->
        Exec.run(action, params, agent.state)
        
      {:error, reason} ->
        {:error, {:action_not_found, action_name, reason}}
    end
  end
  
  @spec execute_instruction(Jido.Agent.t(), map()) :: action_result()
  def execute_instruction(%Jido.Agent{} = agent, instruction) do
    case Instruction.validate(instruction) do
      {:ok, validated} ->
        Instruction.execute(validated, agent)
        
      {:error, reason} ->
        {:error, {:invalid_instruction, reason}}
    end
  end
  
  @spec register_action(Jido.Agent.t(), atom(), function()) :: {:ok, Jido.Agent.t()}
  def register_action(%Jido.Agent{} = agent, name, handler) do
    action = Action.new(name, handler)
    updated_agent = Action.register(agent, action)
    {:ok, updated_agent}
  end
end
```

### Step 4: Update Agent Implementation

#### Modify jido/lib/jido/agent.ex
```elixir
defmodule Jido.Agent do
  # Remove direct action imports
  # Use boundary module instead
  alias Jido.ActionBoundary
  
  # Keep existing struct definition
  defstruct [
    :id, :type, :actions, :state, :config, 
    :pid, :status, :metadata
  ]
  
  # Delegate action operations to boundary
  def execute_action(agent, action_name, params) do
    ActionBoundary.execute_action(agent, action_name, params)
  end
  
  def execute_instruction(agent, instruction) do
    ActionBoundary.execute_instruction(agent, instruction)
  end
  
  def register_action(agent, name, handler) do
    ActionBoundary.register_action(agent, name, handler)
  end
  
  # Keep other agent functionality unchanged
end
```

### Step 5: Update jido_action for Clean API

#### Enhance jido_action/lib/jido_action/action.ex
```elixir
defmodule JidoAction.Action do
  @moduledoc """
  Action implementation designed for external use by jido core.
  """
  
  defstruct [
    :name, :handler, :params_schema, :metadata
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    handler: function(),
    params_schema: map() | nil,
    metadata: map()
  }
  
  # Clean API for jido core
  @spec new(atom(), function(), keyword()) :: t()
  def new(name, handler, opts \\ []) do
    %__MODULE__{
      name: name,
      handler: handler,
      params_schema: Keyword.get(opts, :params_schema),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @spec get_action(struct(), atom()) :: {:ok, t()} | {:error, term()}
  def get_action(agent, action_name) do
    case Map.get(agent.actions || %{}, action_name) do
      nil -> {:error, :not_found}
      action -> {:ok, action}
    end
  end
  
  @spec register(struct(), t()) :: struct()
  def register(agent, %__MODULE__{} = action) do
    actions = Map.put(agent.actions || %{}, action.name, action)
    Map.put(agent, :actions, actions)
  end
end
```

### Step 6: Fix Type Definitions

#### Create jido_action/lib/jido_action/types.ex
```elixir
defmodule JidoAction.Types do
  @moduledoc """
  Shared type definitions for action system.
  """
  
  @type action_result :: 
    {:ok, result :: any()} |
    {:ok, result :: any(), directives :: [directive()]} |
    {:error, reason :: term()}
  
  @type directive :: %{
    type: atom(),
    target: String.t(),
    params: map()
  }
  
  @type instruction :: %{
    action: atom(),
    params: map(),
    metadata: map()
  }
  
  @type execution_context :: %{
    agent_id: String.t(),
    timestamp: DateTime.t(),
    correlation_id: String.t(),
    metadata: map()
  }
end
```

### Step 7: Update Tests

#### Modify jido tests to use boundary
```elixir
defmodule Jido.AgentTest do
  use ExUnit.Case
  
  alias Jido.{Agent, ActionBoundary}
  
  test "executes actions through boundary" do
    agent = %Agent{
      id: "test",
      actions: %{},
      state: %{}
    }
    
    # Register action through boundary
    {:ok, agent} = ActionBoundary.register_action(agent, :test_action, fn params, _state ->
      {:ok, "result: #{params.input}"}
    end)
    
    # Execute through boundary
    result = ActionBoundary.execute_action(agent, :test_action, %{input: "hello"})
    
    assert {:ok, "result: hello"} = result
  end
end
```

## Migration Strategy

### Phase 1: Prepare (Week 1)
1. ✅ Create boundary module
2. ✅ Update jido_action API
3. ✅ Add type definitions
4. ✅ Update dependency in mix.exs

### Phase 2: Migrate (Week 2)  
1. 🔄 Remove duplicate files
2. 🔄 Update all imports
3. 🔄 Update tests
4. 🔄 Update documentation

### Phase 3: Validate (Week 3)
1. ⏳ Run full test suite
2. ⏳ Check dialyzer warnings
3. ⏳ Performance benchmarks
4. ⏳ Integration tests

## Verification Checklist

### Code Structure ✓
- [ ] No duplicate modules between packages
- [ ] Clean dependency relationship established
- [ ] Boundary contracts defined and documented
- [ ] Type definitions complete

### Functionality ✓
- [ ] All existing tests pass
- [ ] Action execution works through boundary
- [ ] Instruction processing functional
- [ ] Error handling preserved

### Type Safety ✓
- [ ] Dialyzer warnings reduced
- [ ] Type contracts properly defined
- [ ] Boundary types match implementations
- [ ] No circular type references

### Performance ✓
- [ ] No significant overhead from boundary layer
- [ ] Memory usage similar to before
- [ ] Execution time within acceptable range

## Benefits of Completion

### 1. Clear Architecture
- Defined boundaries between concerns
- Explicit dependency relationships
- Documented interfaces

### 2. Reduced Complexity
- Single source of truth for action logic
- No more duplicate code maintenance
- Clear responsibility separation

### 3. Better Testing
- Can test packages independently
- Easier to mock boundaries for testing
- Focused test suites

### 4. Improved Type Safety
- Boundary contracts catch type mismatches
- Cleaner dialyzer analysis
- Better IDE support

## Timeline

**Week 1**: Preparation and boundary creation
**Week 2**: Migration and duplicate removal  
**Week 3**: Validation and testing

**Total**: 3 weeks to complete jido_action separation

**Outcome**: Clean, maintainable package separation with clear boundaries and no code duplication.