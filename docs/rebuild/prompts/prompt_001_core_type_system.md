# Prompt 1: Create Core Type System

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Create the foundational type system modules (Prompt 1 of ~30)

## References needed:
- Doc 102, sections 1-3 (Core Type Hierarchy, Unified Error Types, Agent Type Specifications)
- Doc 100, section 2 (Unified Type System goals)
- Doc 107, section 1 (Unified Error Structure)

## Current code issue:
The current error module at `jido/lib/jido/error.ex` has well-defined error types but needs to be moved to the new core types location and enhanced with the unified error structure from Doc 107.

## Implementation requirements:

### 1. Create `lib/jido/core/types.ex`
Define the base types for the entire system:
```elixir
defmodule Jido.Core.Types do
  @moduledoc """
  Core type definitions for the Jido framework.
  """

  # Base types
  @type id :: String.t()  # UUID v7
  @type timestamp :: DateTime.t()
  @type metadata :: map()
  @type config :: map()
  
  # Result types
  @type result :: result(any())
  @type result(value) :: {:ok, value} | {:error, error_reason()}
  @type error_reason :: Jido.Core.Error.t() | atom() | String.t()
  
  # Agent types
  @type agent_module :: module()
  @type agent_state :: map()
  @type agent_id :: id()
  
  # Signal types
  @type signal_type :: :event | :command | :query | :document
  @type signal_source :: String.t()
  @type signal_id :: id()
  
  # Action types
  @type action_module :: module()
  @type action_params :: map()
  @type action_context :: map()
end
```

### 2. Create `lib/jido/core/error.ex`
Migrate and enhance the existing error module:
```elixir
defmodule Jido.Core.Error do
  @moduledoc """
  Unified error handling for the Jido framework.
  """
  
  defstruct [
    :kind,
    :reason,
    :message,
    :stacktrace,
    :timestamp,
    :id,
    :parent_error,
    :context,
    :category,
    :severity,
    :metadata
  ]
  
  @type category :: :validation | :execution | :system | :integration | 
                    :concurrency | :resource | :security
  @type severity :: :debug | :info | :warning | :error | :critical | :fatal
  
  @type t :: %__MODULE__{
    kind: atom(),
    reason: any(),
    message: String.t() | nil,
    stacktrace: list() | nil,
    timestamp: DateTime.t(),
    id: String.t(),
    parent_error: t() | nil,
    context: map(),
    category: category(),
    severity: severity(),
    metadata: map()
  }
  
  # Migrate existing error kinds from current error.ex
  @error_kinds ~w[
    invalid_action invalid_sensor validation_error config_error
    execution_error planning_error dispatch_error routing_error
    compensation_error missing_pid invalid_directive no_registered_name
    not_allowed invalid_state resource_exhausted resource_not_found
    agent_not_found sensor_not_found process_not_found invalid_template
    chain_halted unsupported_feature internal_error initialization_error
    workflow_error
  ]a
  
  # Create constructor functions for each error kind
  for kind <- @error_kinds do
    def unquote(kind)(reason, opts \\ []) do
      new(unquote(kind), reason, opts)
    end
  end
  
  def new(kind, reason, opts \\ []) do
    %__MODULE__{
      kind: kind,
      reason: reason,
      message: Keyword.get(opts, :message),
      stacktrace: Keyword.get(opts, :stacktrace),
      timestamp: DateTime.utc_now(),
      id: generate_error_id(),
      parent_error: Keyword.get(opts, :parent_error),
      context: Keyword.get(opts, :context, %{}),
      category: categorize_error(kind),
      severity: Keyword.get(opts, :severity, :error),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  defp generate_error_id do
    # Will use Jido.Util.generate_id() once available
    # For now, use a simple timestamp-based ID
    "err_" <> to_string(System.system_time(:microsecond))
  end
  
  defp categorize_error(kind) do
    # Map error kinds to categories
    case kind do
      k when k in [:invalid_action, :invalid_sensor, :validation_error] -> :validation
      k when k in [:execution_error, :planning_error] -> :execution
      k when k in [:dispatch_error, :routing_error] -> :integration
      k when k in [:resource_exhausted, :resource_not_found] -> :resource
      k when k in [:not_allowed, :invalid_state] -> :security
      _ -> :system
    end
  end
end
```

### 3. Create type validation module
Create `lib/jido/core/validation.ex`:
```elixir
defmodule Jido.Core.Validation do
  @moduledoc """
  Runtime type validation for critical paths.
  """
  
  import Jido.Core.Types
  alias Jido.Core.Error
  
  @spec validate_id(any()) :: result(id())
  def validate_id(id) when is_binary(id) do
    # Validate UUID v7 format
    case UUID.info(id) do
      {:ok, info} when info.version == 7 -> {:ok, id}
      _ -> {:error, Error.validation_error("Invalid UUID v7", context: %{id: id})}
    end
  end
  def validate_id(_), do: {:error, Error.validation_error("ID must be a string")}
  
  @spec validate_agent_module(any()) :: result(agent_module())
  def validate_agent_module(module) when is_atom(module) do
    if function_exported?(module, :__jido_agent__, 0) do
      {:ok, module}
    else
      {:error, Error.validation_error("Not a valid agent module", context: %{module: module})}
    end
  end
  def validate_agent_module(_), do: {:error, Error.validation_error("Agent module must be an atom")}
end
```

## Success criteria:
- [ ] `Jido.Core.Types` module created with all base type definitions
- [ ] `Jido.Core.Error` module created with unified error structure
- [ ] All existing error kinds from `jido/lib/jido/error.ex` preserved
- [ ] Type validation functions for critical types
- [ ] Dialyzer clean with no warnings
- [ ] Module documentation complete
- [ ] All type specs properly defined

## Testing requirements:
Create `test/jido/core/types_test.exs` and `test/jido/core/error_test.exs` with:
- Tests for error creation and categorization
- Tests for type validation functions
- Tests for error context enrichment
- Property-based tests for ID validation

## Notes:
- This foundational type system will be used by all subsequent prompts
- The error structure supports the recovery mechanisms detailed in Doc 107
- UUID v7 validation will be properly implemented once `Jido.Util` is available