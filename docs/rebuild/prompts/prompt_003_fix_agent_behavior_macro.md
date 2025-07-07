# Prompt 3: Fix Agent Behavior Macro

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Fix Agent Behavior Macro to use Instance pattern (Prompt 3 of ~30)

## References needed:
- Doc 101, Week 1, Task 3 (Remove polymorphic struct from Agent behavior)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 100, section 2 (Unified Type System)

## Current code issue:
From `jido/lib/jido/agent.ex` lines 518-535, the `__using__` macro creates polymorphic structs:

```elixir
# Line 528 - THE PROBLEM
base_agent = struct(__MODULE__, %{
  id: generated_id,
  state: state_defaults,
  dirty_state?: false,
  pending_instructions: :queue.new(),
  actions: @validated_opts[:actions] || [],
  result: nil
})
```

When `MyAgent` does `use Jido.Agent`, the `__MODULE__` in the macro refers to `Jido.Agent`, not `MyAgent`, creating incorrect structs. Additionally, this creates a different struct type for each agent, preventing unified typing.

## Implementation requirements:

### 1. Fix the `__using__` macro in `lib/jido/agent.ex`

Replace the problematic section (lines 518-535) with:

```elixir
quote location: :keep do
  @behaviour Jido.Agent
  
  # Import types and Instance module
  alias Jido.Agent.Instance
  alias Jido.Core.Types
  
  # Store validated options for later use
  @__jido_agent_opts__ unquote(opts)
  
  # Define marker function
  def __jido_agent__, do: true
  
  # Define version function
  def __version__, do: unquote(opts[:version] || "1.0.0")
  
  # Define actions function
  def __actions__, do: unquote(opts[:actions] || [])
  
  @doc """
  Creates a new agent instance of this module.
  
  ## Examples
  
      {:ok, agent} = MyAgent.new()
      {:ok, agent} = MyAgent.new(%{initial_value: 42})
  
  """
  @spec new(Types.config()) :: Types.result(Instance.t())
  def new(config \\ %{}) do
    # Merge default config with provided config
    default_config = unquote(Macro.escape(config_defaults))
    merged_config = Map.merge(default_config, config)
    
    # Create instance using the Instance module
    Instance.new(__MODULE__, merged_config)
  end
  
  @doc """
  Validates configuration for this agent.
  
  Can be overridden by the implementing module for custom validation.
  """
  @spec validate_config(Types.config()) :: Types.result(Types.config())
  def validate_config(config) do
    {:ok, config}
  end
  
  @doc """
  Returns the initial state for this agent.
  
  Can be overridden by the implementing module.
  """
  @spec initial_state(Types.config()) :: Types.agent_state()
  def initial_state(config) do
    unquote(Macro.escape(state_defaults))
  end
  
  # Allow modules to override these functions
  defoverridable [
    new: 0,
    new: 1,
    validate_config: 1,
    initial_state: 1
  ]
end
```

### 2. Update the `init` callback handling

Ensure the behavior properly defines the init callback that returns state, not a struct:

```elixir
@doc """
Initializes the agent's state based on the provided configuration.

The return value should be `{:ok, state}` where state is a map,
not an agent struct. The Instance wrapper will be handled by the framework.

## Examples

    def init(config) do
      {:ok, %{counter: config[:initial_value] || 0}}
    end

"""
@callback init(config :: Types.config()) :: {:ok, Types.agent_state()} | {:error, Types.error_reason()}
```

### 3. Add migration support to existing agents

Add a temporary compatibility layer in the macro:

```elixir
# Add this to the __using__ macro to support gradual migration
if Module.get_attribute(__CALLER__.module, :jido_legacy_struct, false) do
  # For agents that still expect struct behavior during migration
  defstruct unquote(
    Keyword.merge(
      [
        id: nil,
        state: state_defaults,
        dirty_state?: false,
        pending_instructions: :queue.new(),
        actions: opts[:actions] || [],
        result: nil
      ],
      Module.get_attribute(__CALLER__.module, :jido_struct_fields, [])
    )
  )
  
  @doc false
  def __legacy_struct__, do: true
end
```

### 4. Update agent creation helpers

Add module-level functions to help with agent instantiation:

```elixir
defmodule Jido.Agent do
  # ... existing code ...
  
  @doc """
  Creates a new agent instance for the given module.
  """
  @spec create(Types.agent_module(), Types.config()) :: Types.result(Instance.t())
  def create(module, config \\ %{}) do
    Instance.new(module, config)
  end
  
  @doc """
  Ensures the given value is an agent instance.
  Handles legacy structs for backward compatibility.
  """
  @spec ensure_instance(Instance.t() | struct()) :: Types.result(Instance.t())
  def ensure_instance(%Instance{} = instance), do: {:ok, instance}
  def ensure_instance(%module{} = legacy_struct) do
    if Instance.legacy_agent?(legacy_struct) do
      Instance.from_legacy(legacy_struct)
    else
      {:error, Error.validation_error("Not a valid agent", context: %{value: legacy_struct})}
    end
  end
  def ensure_instance(other) do
    {:error, Error.validation_error("Not a valid agent", context: %{value: other})}
  end
end
```

### 5. Document the migration path

Add to the module documentation:

```elixir
@moduledoc """
Defines the behavior for Jido agents.

## Migration from Legacy Structs

If you have existing agents that use the old polymorphic struct pattern,
you can gradually migrate by:

1. Adding `@jido_legacy_struct true` to maintain struct definition
2. Updating your code to use `MyAgent.new/1` instead of `%MyAgent{}`
3. Once fully migrated, remove the `@jido_legacy_struct` attribute

## Example

    defmodule MyAgent do
      use Jido.Agent,
        name: "my_agent",
        version: "2.0.0",
        actions: [MyAction]
      
      def init(config) do
        {:ok, %{value: config[:initial_value] || 0}}
      end
      
      def handle_action(:increment, _params, state) do
        {:ok, %{state | value: state.value + 1}}
      end
    end
    
    # Create an agent instance
    {:ok, agent} = MyAgent.new(%{initial_value: 42})

"""
```

## Success criteria:
- [ ] `__using__` macro no longer creates polymorphic structs
- [ ] `new/0` and `new/1` functions return `Instance.t()`
- [ ] Legacy struct support via `@jido_legacy_struct` attribute
- [ ] All agent callbacks work with state maps, not structs
- [ ] Proper type specs for all generated functions
- [ ] Migration path documented
- [ ] Dialyzer clean with no warnings
- [ ] Existing tests pass with Instance pattern

## Testing requirements:
Create tests to verify:
- New agents created with the updated macro use Instance pattern
- Legacy agents with `@jido_legacy_struct` still work
- Agent callbacks receive and return proper state maps
- Instance creation through `MyAgent.new/1` works correctly
- Type checking with Dialyzer passes

## Notes:
- This fix is critical as it blocks all other agent-related work
- The legacy support allows gradual migration of existing code
- After this, we'll update individual agents in prompts 4-8
- The Instance pattern enables proper typing and serialization