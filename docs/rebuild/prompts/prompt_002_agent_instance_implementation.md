# Prompt 2: Agent Instance Implementation

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Implement Agent Instance struct (Prompt 2 of ~30)

## References needed:
- Doc 102, section 3 (Agent Type Specifications)
- Doc 100, section 2 (Unified Type System - Instance pattern)
- Doc 101, Week 1, Task 2 (Create Agent Instance struct)

## Current code issue:
From `jido/lib/jido/agent.ex` line 528:
```elixir
# ANTIPATTERN - creates polymorphic structs
base_agent = struct(__MODULE__, %{
  id: generated_id,
  state: state_defaults,
  dirty_state?: false,
  pending_instructions: :queue.new(),
  actions: @validated_opts[:actions] || [],
  result: nil
})
```

This creates a different struct type for each agent module (e.g., `%MyAgent{}`), causing type system issues and making it impossible to have a unified agent type.

## Implementation requirements:

### 1. Create `lib/jido/agent/instance.ex`
```elixir
defmodule Jido.Agent.Instance do
  @moduledoc """
  Unified agent instance struct that replaces polymorphic agent structs.
  
  All agents in the system are represented as instances of this struct,
  with their specific behavior module referenced in the :module field.
  """
  
  alias Jido.Core.Types
  alias Jido.Core.Error
  alias Jido.Core.Validation
  
  @enforce_keys [:id, :module]
  defstruct [
    :id,
    :module,
    :state,
    :config,
    :metadata,
    :__vsn__,
    :__dirty__,
    # Fields from original agent struct
    :pending_instructions,
    :actions,
    :result
  ]
  
  @type t :: %__MODULE__{
    id: Types.agent_id(),
    module: Types.agent_module(),
    state: Types.agent_state(),
    config: Types.config(),
    metadata: Types.metadata(),
    __vsn__: String.t() | nil,
    __dirty__: boolean(),
    pending_instructions: :queue.queue(),
    actions: [Types.action_module()],
    result: any()
  }
  
  @doc """
  Creates a new agent instance for the given module with optional config.
  """
  @spec new(Types.agent_module(), Types.config()) :: Types.result(t())
  def new(module, config \\ %{}) do
    with {:ok, module} <- Validation.validate_agent_module(module),
         {:ok, validated_config} <- validate_config(module, config),
         {:ok, initial_state} <- initialize_state(module, validated_config) do
      
      instance = %__MODULE__{
        id: generate_agent_id(module),
        module: module,
        state: initial_state,
        config: validated_config,
        metadata: %{
          created_at: DateTime.utc_now(),
          node: node()
        },
        __vsn__: get_module_version(module),
        __dirty__: false,
        pending_instructions: :queue.new(),
        actions: get_module_actions(module),
        result: nil
      }
      
      {:ok, instance}
    end
  end
  
  @doc """
  Updates the state of an agent instance, marking it as dirty.
  """
  @spec update_state(t(), Types.agent_state()) :: t()
  def update_state(%__MODULE__{} = instance, new_state) do
    %{instance | state: new_state, __dirty__: true}
  end
  
  @doc """
  Converts a legacy polymorphic agent struct to an Instance.
  Used for migration compatibility.
  """
  @spec from_legacy(struct()) :: Types.result(t())
  def from_legacy(%module{} = legacy_agent) do
    if legacy_agent?(legacy_agent) do
      # Extract fields from the legacy struct
      instance = %__MODULE__{
        id: Map.get(legacy_agent, :id),
        module: module,
        state: Map.get(legacy_agent, :state, %{}),
        config: Map.get(legacy_agent, :config, %{}),
        metadata: Map.get(legacy_agent, :metadata, %{}),
        __vsn__: Map.get(legacy_agent, :__vsn__),
        __dirty__: Map.get(legacy_agent, :dirty_state?, false),
        pending_instructions: Map.get(legacy_agent, :pending_instructions, :queue.new()),
        actions: Map.get(legacy_agent, :actions, []),
        result: Map.get(legacy_agent, :result)
      }
      
      {:ok, instance}
    else
      {:error, Error.validation_error("Not a legacy agent struct", context: %{struct: legacy_agent})}
    end
  end
  
  @doc """
  Checks if a struct is a legacy agent struct.
  """
  @spec legacy_agent?(any()) :: boolean()
  def legacy_agent?(%module{} = struct) do
    module != __MODULE__ &&
    Map.has_key?(struct, :id) &&
    Map.has_key?(struct, :state) &&
    function_exported?(module, :__jido_agent__, 0)
  end
  def legacy_agent?(_), do: false
  
  # Private functions
  
  defp validate_config(module, config) do
    if function_exported?(module, :validate_config, 1) do
      module.validate_config(config)
    else
      {:ok, config}
    end
  end
  
  defp initialize_state(module, config) do
    cond do
      function_exported?(module, :init, 1) ->
        module.init(config)
      
      function_exported?(module, :initial_state, 1) ->
        {:ok, module.initial_state(config)}
      
      true ->
        {:ok, %{}}
    end
  end
  
  defp generate_agent_id(module) do
    # Will use Jido.Util.generate_id() once available
    # For now, use module name + timestamp
    module_name = module |> Module.split() |> List.last() |> String.downcase()
    "agent_#{module_name}_#{System.system_time(:microsecond)}"
  end
  
  defp get_module_version(module) do
    if function_exported?(module, :__version__, 0) do
      module.__version__()
    else
      "1.0.0"
    end
  end
  
  defp get_module_actions(module) do
    if function_exported?(module, :__actions__, 0) do
      module.__actions__()
    else
      []
    end
  end
end
```

### 2. Update `lib/jido/agent.ex` to use Instance
Add helper functions to the Agent module to work with instances:

```elixir
# Add to Jido.Agent module

@doc """
Creates a new agent instance for this module.
"""
def new(config \\ %{}) do
  Jido.Agent.Instance.new(__MODULE__, config)
end

@doc """
Ensures the given value is an agent instance.
Converts legacy agent structs if needed.
"""
@spec ensure_instance(Instance.t() | struct()) :: Types.result(Instance.t())
def ensure_instance(%Instance{} = instance), do: {:ok, instance}
def ensure_instance(%_{} = legacy_agent) do
  Instance.from_legacy(legacy_agent)
end
def ensure_instance(_), do: {:error, Error.invalid_agent("Not an agent instance or struct")}
```

### 3. Create migration helper module
Create `lib/jido/agent/migration.ex`:
```elixir
defmodule Jido.Agent.Migration do
  @moduledoc """
  Helpers for migrating from polymorphic agent structs to Instance pattern.
  """
  
  alias Jido.Agent.Instance
  
  @doc """
  Wraps agent callbacks to automatically convert between legacy and instance formats.
  """
  defmacro wrap_callback(name, arity, fun) do
    # Implementation to wrap callbacks and handle conversion
    # This will be used in the agent behavior macro
  end
end
```

## Success criteria:
- [ ] `Jido.Agent.Instance` module created with all required fields
- [ ] Instance struct properly typed with `@type t()`
- [ ] `new/2` function creates instances with proper validation
- [ ] `from_legacy/1` converts polymorphic structs to instances
- [ ] State update functions maintain dirty flag
- [ ] Helper functions added to Agent module
- [ ] All functions have proper `@spec` annotations
- [ ] Dialyzer clean with no warnings

## Testing requirements:
Create `test/jido/agent/instance_test.exs` with:
- Tests for instance creation with various configs
- Tests for legacy struct conversion
- Tests for state updates and dirty flag
- Tests for validation failures
- Property-based tests for instance creation

## Notes:
- This instance struct will be used by all agents going forward
- The `from_legacy/1` function enables gradual migration
- ID generation will be improved once Jido.Util is available
- The next prompt will fix the agent behavior macro to use this Instance struct