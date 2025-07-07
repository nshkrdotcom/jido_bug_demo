# Unified Type System Design for Jido Framework

## Overview

This document outlines the design for a unified type system across jido, jido_action, and jido_signal libraries. The goal is to eliminate type mismatches, resolve the polymorphic struct antipattern, and create a cohesive type foundation for all three libraries.

## Core Design Principles

1. **Single Source of Truth**: Each type should be defined in exactly one place
2. **No Circular Dependencies**: Clear hierarchy with shared types at the base
3. **Explicit Over Implicit**: All types should be explicitly defined and documented
4. **Composition Over Inheritance**: Use behaviors and protocols, not struct polymorphism
5. **Runtime Safety**: Types should guide correct usage and prevent runtime errors

## Proposed Package Structure

```
jido_core/          # New shared types package
├── lib/
│   ├── jido_core.ex
│   ├── jido_core/
│   │   ├── types.ex        # Common type definitions
│   │   ├── error.ex        # Unified error types
│   │   ├── result.ex       # Result type definitions
│   │   └── id.ex           # ID generation

jido_action/        # Action execution framework
├── lib/
│   ├── jido_action.ex
│   └── jido_action/
│       ├── behavior.ex     # Action behavior
│       ├── instruction.ex  # Instruction types
│       └── exec.ex         # Execution engine

jido_signal/        # Event routing system
├── lib/
│   └── jido_signal/
│       └── (unchanged)

jido/               # Agent framework
├── lib/
│   └── jido/
│       ├── agent.ex        # Agent behavior (fixed)
│       └── (other modules)
```

## Type Definitions

### 1. Core Types (jido_core)

```elixir
defmodule JidoCore.Types do
  @type id :: String.t()
  @type timestamp :: DateTime.t()
  @type metadata :: map()
  
  @type result(success, error) :: 
    {:ok, success} | 
    {:error, error}
    
  @type result(success) :: result(success, JidoCore.Error.t())
end

defmodule JidoCore.Error do
  @type error_type :: 
    :validation_error |
    :execution_error |
    :timeout_error |
    :not_found |
    :permission_denied |
    :configuration_error |
    :type_mismatch |
    atom()
    
  @type t :: %__MODULE__{
    type: error_type(),
    message: String.t(),
    details: map(),
    stacktrace: Exception.stacktrace() | nil,
    timestamp: DateTime.t()
  }
  
  defstruct [:type, :message, :details, :stacktrace, :timestamp]
end

defmodule JidoCore.Result do
  @type ok(value) :: {:ok, value}
  @type error :: {:error, JidoCore.Error.t()}
  @type t(value) :: ok(value) | error()
  
  # Result with directives for agent actions
  @type with_directives(value, directive) :: 
    {:ok, value} |
    {:ok, value, directive | [directive]} |
    error()
end
```

### 2. Action Types (jido_action)

```elixir
defmodule JidoAction.Types do
  alias JidoCore.Types
  
  @type action_module :: module()
  @type params :: map()
  @type context :: map()
  @type options :: keyword()
  
  @type run_result :: Types.result(map())
  @type run_result_with_directives(directive) :: 
    JidoCore.Result.with_directives(map(), directive)
    
  @type compensation_result :: 
    {:ok, :compensated} |
    {:ok, :compensation_not_needed} |
    {:error, JidoCore.Error.t()}
end

defmodule JidoAction.Behavior do
  @callback run(params :: map(), context :: map()) :: 
    JidoAction.Types.run_result()
    
  @callback on_error(
    error :: JidoCore.Error.t(),
    params :: map(),
    context :: map(),
    opts :: keyword()
  ) :: JidoAction.Types.compensation_result()
  
  # Other callbacks with proper types...
end

defmodule JidoAction.Instruction do
  alias JidoCore.Types
  
  @type t :: %__MODULE__{
    id: Types.id(),
    action: module(),
    params: map(),
    context: map(),
    opts: keyword()
  }
  
  defstruct [:id, :action, :params, :context, :opts]
end
```

### 3. Agent Types (jido)

```elixir
defmodule Jido.Agent.Types do
  alias JidoCore.Types
  alias JidoAction.Instruction
  
  @type agent_module :: module()
  @type agent_id :: Types.id()
  @type agent_state :: map()
  
  # Single struct type for all agents
  @type t :: %Jido.Agent.Instance{
    id: agent_id(),
    module: agent_module(),
    state: agent_state(),
    config: map(),
    metadata: Types.metadata()
  }
  
  @type directive :: 
    {:set_state, agent_state()} |
    {:update_state, (agent_state() -> agent_state())} |
    {:emit, Jido.Signal.t()} |
    {:spawn, agent_module(), map()} |
    {:stop, reason :: term()}
    
  @type instruction_result :: 
    JidoCore.Result.with_directives(map(), directive())
end

defmodule Jido.Agent.Instance do
  @moduledoc """
  Runtime representation of any agent instance.
  This replaces the polymorphic struct pattern.
  """
  
  defstruct [:id, :module, :state, :config, :metadata]
  
  @type t :: %__MODULE__{
    id: String.t(),
    module: module(),
    state: map(),
    config: map(),
    metadata: map()
  }
end

defmodule Jido.Agent.Behavior do
  alias Jido.Agent.Types
  
  @callback initial_state(config :: map()) :: 
    {:ok, Types.agent_state()} | 
    {:error, JidoCore.Error.t()}
    
  @callback handle_action(
    agent :: Types.t(),
    instruction :: Instruction.t()
  ) :: Types.instruction_result()
  
  # Define the agent without creating a new struct type
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Agent.Behavior
      
      # No defstruct here! Use Jido.Agent.Instance instead
      
      def new(config \\ %{}) do
        with {:ok, state} <- initial_state(config) do
          {:ok, %Jido.Agent.Instance{
            id: JidoCore.ID.generate(),
            module: __MODULE__,
            state: state,
            config: config,
            metadata: %{}
          }}
        end
      end
    end
  end
end
```

### 4. Signal Types (jido_signal)

```elixir
defmodule Jido.Signal.Types do
  alias JidoCore.Types
  
  @type signal_type :: String.t()
  @type signal_source :: String.t()
  
  @type t :: %Jido.Signal{
    id: Types.id(),
    type: signal_type(),
    source: signal_source(),
    data: map(),
    metadata: Types.metadata(),
    timestamp: Types.timestamp()
  }
  
  @type dispatch_result :: Types.result(dispatch_info())
  @type dispatch_info :: %{
    delivered: non_neg_integer(),
    failed: non_neg_integer(),
    handlers: [module()]
  }
end
```

## Migration Strategy

### Phase 1: Create jido_core package
1. Extract common types from all three libraries
2. Define unified error handling
3. Standardize ID generation
4. Create result types with directive support

### Phase 2: Update jido_action
1. Remove internal error definitions
2. Import types from jido_core
3. Update all type references
4. Ensure backward compatibility with adapters

### Phase 3: Update jido_signal
1. Import shared types from jido_core
2. Remove duplicate error definitions
3. Update signal type definitions

### Phase 4: Fix jido agent system
1. Replace polymorphic struct with Jido.Agent.Instance
2. Update all agent modules to use the new pattern
3. Fix all callback signatures
4. Update tests

### Phase 5: Integration testing
1. Verify cross-library type compatibility
2. Run dialyzer on all packages
3. Fix any remaining type issues

## Benefits

1. **Type Safety**: Dialyzer can properly analyze the entire system
2. **Maintainability**: Single source of truth for each type
3. **Flexibility**: Agents can evolve without breaking type contracts
4. **Interoperability**: Clear contracts between libraries
5. **Developer Experience**: Better error messages and IDE support

## Example Usage

```elixir
defmodule MyAgent do
  use Jido.Agent.Behavior
  
  @impl true
  def initial_state(config) do
    {:ok, %{count: 0, config: config}}
  end
  
  @impl true
  def handle_action(agent, instruction) do
    case instruction.action do
      Counter.Increment ->
        new_count = agent.state.count + 1
        {:ok, %{count: new_count}, {:set_state, %{agent.state | count: new_count}}}
        
      _ ->
        {:error, JidoCore.Error.new(:unknown_action, "Unsupported action")}
    end
  end
end

# Usage
{:ok, agent} = MyAgent.new(%{name: "counter"})
# agent is %Jido.Agent.Instance{module: MyAgent, state: %{count: 0}, ...}
```

This design eliminates the polymorphic struct antipattern while maintaining the flexibility and power of the original system.