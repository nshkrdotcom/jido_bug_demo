# Prompt 5: Update BasicAgent to Instance Pattern

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update BasicAgent with schema and actions to Instance pattern (Prompt 5 of ~30)

## References needed:
- Prompts 1-4 (Previous work on Instance pattern)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 101, Week 1, Task 4 (Update existing agents)

## Current code issue:
From `test/support/test_agent.ex`, BasicAgent has schema and actions:
```elixir
defmodule BasicAgent do
  use Jido.Agent,
    name: "basic_agent",
    actions: [
      JidoTest.TestActions.BasicAction,
      JidoTest.TestActions.NoSchema,
      # ...
    ],
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]
end
```

The schema creates struct fields on the polymorphic struct, which we need to move to the state map.

## Implementation requirements:

### 1. Update BasicAgent to use state map

```elixir
defmodule BasicAgent do
  @moduledoc "Basic agent with simple schema and actions - uses Instance pattern"
  use Jido.Agent,
    name: "basic_agent",
    version: "2.0.0",
    actions: [
      JidoTest.TestActions.BasicAction,
      JidoTest.TestActions.NoSchema,
      JidoTest.TestActions.EnqueueAction,
      JidoTest.TestActions.RegisterAction,
      JidoTest.TestActions.DeregisterAction
    ],
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]
  
  @impl true
  def init(config) do
    # Initialize state from schema defaults and config
    initial_state = %{
      location: config[:location] || :home,
      battery_level: config[:battery_level] || 100
    }
    
    {:ok, initial_state}
  end
  
  @impl true
  def validate_config(config) do
    # Validate battery level if provided
    case config[:battery_level] do
      nil -> {:ok, config}
      level when is_integer(level) and level >= 0 and level <= 100 ->
        {:ok, config}
      _ ->
        {:error, Jido.Core.Error.validation_error("battery_level must be 0-100")}
    end
  end
end
```

### 2. Update state access patterns

Change from struct field access to map access:
```elixir
# OLD - Direct field access
agent.state.location
agent.state.battery_level

# NEW - Map access in state
agent.state[:location]
agent.state[:battery_level]

# Or with pattern matching
%{state: %{location: location, battery_level: battery}} = agent
```

### 3. Update action handlers

Actions that access agent state need updates:
```elixir
# In action implementations that use BasicAgent

# OLD
def run(%{location: :home} = agent, params) do
  # ...
end

# NEW  
def run(%Jido.Agent.Instance{state: %{location: :home}} = agent, params) do
  # ...
end

# Or extract state first
def run(%Jido.Agent.Instance{state: state} = agent, params) do
  if state[:location] == :home do
    # ...
  end
end
```

### 4. Schema validation integration

Ensure schema validation works with the state map:
```elixir
@impl true
def on_before_validate_state(%Instance{state: state} = agent) do
  # Schema validation will validate the state map
  # The framework should handle this, but we can add custom validation
  cond do
    not is_atom(state[:location]) ->
      {:error, "location must be an atom"}
    
    state[:battery_level] < 0 or state[:battery_level] > 100 ->
      {:error, "battery_level must be 0-100"}
    
    true ->
      {:ok, agent}
  end
end
```

### 5. Migration tests

```elixir
test "BasicAgent uses Instance pattern with schema" do
  # Create with defaults
  assert {:ok, agent} = BasicAgent.new()
  assert %Instance{
    module: BasicAgent,
    state: %{location: :home, battery_level: 100}
  } = agent
  
  # Create with custom config
  assert {:ok, agent2} = BasicAgent.new(%{
    location: :work,
    battery_level: 75
  })
  assert agent2.state[:location] == :work
  assert agent2.state[:battery_level] == 75
end

test "BasicAgent validates config" do
  # Invalid battery level
  assert {:error, error} = BasicAgent.new(%{battery_level: 150})
  assert error.kind == :validation_error
  
  # Valid config
  assert {:ok, _} = BasicAgent.new(%{battery_level: 50})
end

test "BasicAgent actions work with Instance" do
  {:ok, agent} = BasicAgent.new()
  
  # Test an action
  instruction = %Jido.Instruction{
    action: JidoTest.TestActions.BasicAction,
    params: %{}
  }
  
  # Actions should work with Instance
  assert {:ok, _result} = Jido.Runner.run(agent, instruction)
end
```

## Success criteria:
- [ ] BasicAgent uses state map instead of struct fields
- [ ] Schema defaults populate the state map
- [ ] Config validation works properly
- [ ] Actions can access state through the map
- [ ] All existing tests pass with Instance pattern
- [ ] Schema validation integrates with state map
- [ ] No dialyzer warnings

## Testing requirements:
- Test schema defaults apply to state map
- Test config overrides defaults
- Test validation rejects invalid configs
- Test actions work with new state structure
- Test state updates maintain schema compliance

## Notes:
- Schema moves from struct definition to state validation
- This pattern will be used for all agents with schemas
- Actions need to be aware of Instance structure
- State is now a plain map, not a struct with fields