# Jido Action Extraction Plan with Type Contracts

## Overview

This document outlines the plan to extract `jido_action` as a separate, independent library from the `jido` core, with a strong focus on type contracts and boundary enforcement.

## Current State Analysis

### Duplicated Modules
- `Jido.Action` (in both jido and jido_action)
- `Jido.Exec` (in both jido and jido_action)  
- `Jido.Error` (in both jido and jido_action)
- `Jido.Instruction` (in both jido and jido_action)

### Dependencies
- `jido_action` currently depends on `jido` core
- Circular dependency risk if not properly separated
- Shared type definitions create coupling

## Extraction Strategy

### Phase 1: Define Clear Boundaries

```
┌─────────────────┐         ┌─────────────────┐
│   jido_action   │         │      jido       │
├─────────────────┤         ├─────────────────┤
│ - Action        │ ──────> │ - Agent         │
│ - Exec          │  uses   │ - Runner        │
│ - Instruction   │         │ - Sensor        │
│ - Error         │         │ - Scheduler     │
└─────────────────┘         └─────────────────┘
```

### Phase 2: Type Contract Definition

#### Action Contract Interface

```elixir
defmodule Jido.Action.Contract do
  @moduledoc """
  Defines the type contract between jido_action and jido.
  This module serves as the boundary interface.
  """
  
  @type action_module :: module()
  @type action_params :: map()
  @type action_context :: map()
  @type action_result :: 
    {:ok, map()} | 
    {:ok, map(), directive() | [directive()]} |
    {:error, error()} |
    {:error, error(), directive() | [directive()]}
  
  @type directive :: %{
    type: :set | :update | :delete | :spawn | :kill | :register | :deregister,
    target: atom(),
    value: any()
  }
  
  @type error :: %{
    type: error_type(),
    message: String.t(),
    details: map(),
    stacktrace: list()
  }
  
  @type error_type :: 
    :validation_error |
    :execution_error |
    :timeout |
    :config_error
    
  @callback validate_params(action_params()) :: {:ok, action_params()} | {:error, String.t()}
  @callback run(action_params(), action_context()) :: action_result()
  @callback validate_output(map()) :: {:ok, map()} | {:error, String.t()}
end
```

#### Instruction Contract Interface

```elixir
defmodule Jido.Instruction.Contract do
  @moduledoc """
  Defines the contract for instruction normalization and validation.
  """
  
  @type t :: %{
    id: String.t(),
    action: module(),
    params: map(),
    context: map(),
    opts: keyword()
  }
  
  @type instruction_input :: 
    module() |
    {module(), map()} |
    t()
    
  @spec normalize(instruction_input(), map(), keyword()) :: 
    {:ok, [t()]} | {:error, term()}
    
  @spec validate_allowed_actions([t()], [module()]) :: 
    :ok | {:error, term()}
end
```

### Phase 3: Boundary Enforcement Implementation

#### 1. Action Boundary Guards

```elixir
defmodule Jido.Action do
  use Jido.TypeContract
  
  defcontract :action_config do
    required :name, :string, format: ~r/^[a-z_]+$/
    optional :description, :string
    optional :category, :string
    optional :tags, {:list, :string}
    optional :vsn, :string
    required :schema, :keyword_list
    optional :output_schema, :keyword_list
  end
  
  defcontract :run_params do
    # Dynamic - validated against action's schema
    type :map
    validate :validate_against_schema
  end
  
  defcontract :run_context do
    type :map
    optional :action_metadata, :map
    optional :__task_group__, :pid
  end
  
  defcontract :run_result do
    one_of [
      {:ok, :map},
      {:ok, :map, :any},
      {:error, :any},
      {:error, :any, :any}
    ]
  end
end
```

#### 2. Exec Boundary Guards

```elixir
defmodule Jido.Exec do
  use Jido.TypeContract
  
  defcontract :exec_opts do
    optional :timeout, :integer, min: 0
    optional :max_retries, :integer, min: 0
    optional :backoff, :integer, min: 0
    optional :log_level, :atom, in: [:debug, :info, :warn, :error]
    optional :telemetry, :atom, in: [:full, :minimal, :silent]
  end
  
  @guard input: :exec_input, output: :exec_output
  def run(action, params, context, opts) do
    # Implementation with boundary validation
  end
end
```

### Phase 4: Migration Steps

#### Step 1: Create Clean Interfaces
```elixir
# In jido_action
defmodule Jido.Action.Interface do
  @moduledoc """
  Public interface for jido to interact with actions.
  """
  
  defdelegate run(action, params, context, opts), to: Jido.Exec
  defdelegate normalize(instruction, context, opts), to: Jido.Instruction
  defdelegate validate_action(module), to: Jido.Action.Validator
end
```

#### Step 2: Update jido Core Dependencies
```elixir
# In jido's mix.exs
defp deps do
  [
    {:jido_action, "~> 2.0"},
    # Remove internal Action/Exec modules
  ]
end
```

#### Step 3: Adapter Pattern for Compatibility
```elixir
defmodule Jido.ActionAdapter do
  @moduledoc """
  Provides compatibility layer during migration.
  """
  
  @behaviour Jido.Action.Contract
  
  def adapt(old_action_module) do
    # Convert old action format to new contract
  end
end
```

## Type Safety Guarantees

### Compile-Time Guarantees

1. **Action Definition**
   - Schema validation at compile time
   - Callback implementation verification
   - Contract completeness checking

2. **Usage Validation**
   - Allowed actions list verification
   - Parameter type checking against schema
   - Context structure validation

### Runtime Guarantees

1. **Boundary Validation**
   - Input parameter validation
   - Context validation
   - Output validation

2. **Error Propagation**
   - Typed error returns
   - Contract-compliant error structures
   - Traceable error paths

## API Compatibility Matrix

| Operation | Old API | New API | Contract Enforcement |
|-----------|---------|---------|---------------------|
| Define Action | `use Jido.Action` | `use Jido.Action` | Compile-time validation |
| Run Action | `Jido.Exec.run/4` | `Jido.Exec.run/4` | Runtime boundary guard |
| Normalize Instruction | `Jido.Instruction.normalize/3` | `Jido.Instruction.normalize/3` | Input validation |
| Validate Params | `Action.validate_params/1` | `Action.validate_params/1` | Schema-based validation |

## Breaking Changes

### Required Changes

1. **Error Structure**
   - Standardized error format across boundaries
   - Removal of framework-specific error types
   - Introduction of error contracts

2. **Directive Format**
   - Explicit directive type definitions
   - Validated directive structures
   - Contract-based directive passing

3. **Context Structure**
   - Reserved keys for framework use
   - Explicit context contracts
   - Validation at boundaries

### Migration Helpers

```elixir
defmodule Jido.Action.Migration do
  @moduledoc """
  Helpers for migrating from embedded to extracted jido_action.
  """
  
  def migrate_action(module) do
    # Analyze and report required changes
  end
  
  def validate_migration(app) do
    # Verify all actions comply with new contracts
  end
end
```

## Testing Strategy

### Contract Testing

```elixir
defmodule Jido.Action.ContractTest do
  use ExUnit.Case
  use Jido.TypeContract.Testing
  
  describe "action contracts" do
    contract_test MyAction do
      valid_input %{name: "test", value: 42}
      invalid_input %{name: nil}
      
      valid_output %{result: "success"}
      invalid_output %{result: nil}
    end
  end
end
```

### Boundary Testing

```elixir
defmodule Jido.Action.BoundaryTest do
  use ExUnit.Case
  
  test "validates input at boundary" do
    assert {:error, violations} = 
      Jido.Exec.run(MyAction, %{invalid: "input"}, %{})
      
    assert [%{field: :name, error: "is required"}] = violations
  end
end
```

## Performance Considerations

1. **Zero-Cost Abstractions**
   - Compile-time contract resolution
   - Inline boundary guards in production
   - Optional runtime validation

2. **Caching Strategy**
   - Contract validation caching
   - Compiled validator functions
   - Fast-path for validated inputs

## Documentation Requirements

1. **Contract Documentation**
   - Auto-generated from contracts
   - Examples for each contract
   - Migration guides

2. **API Documentation**
   - Clear boundary definitions
   - Type specifications
   - Usage examples

## Success Metrics

1. **Type Safety**
   - 100% of public APIs have contracts
   - Zero runtime type errors at boundaries
   - Dialyzer compliance

2. **Performance**
   - < 1% overhead from boundary validation
   - No performance regression
   - Improved error reporting

3. **Developer Experience**
   - Clear error messages
   - Smooth migration path
   - Better IDE support