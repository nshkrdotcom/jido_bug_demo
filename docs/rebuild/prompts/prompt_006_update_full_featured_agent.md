# Prompt 6: Update FullFeaturedAgent to Instance Pattern

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update FullFeaturedAgent with callbacks to Instance pattern (Prompt 6 of ~30)

## References needed:
- Prompts 1-5 (Instance pattern foundation)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 101, Week 1, Task 4 (Update existing agents)

## Current code issue:
FullFeaturedAgent uses callbacks that expect the polymorphic struct pattern:
```elixir
@impl true
def on_before_validate_state(agent) do
  new_state = Map.put(agent.state, :last_validated_at, DateTime.utc_now())
  {:ok, %{agent | state: new_state}}
end
```

The `%{agent | state: new_state}` syntax assumes `agent` is a struct with a `:state` field.

## Implementation requirements:

### 1. Update FullFeaturedAgent callbacks for Instance pattern

```elixir
defmodule FullFeaturedAgent do
  @moduledoc "Agent with all features enabled - uses Instance pattern"
  use Jido.Agent,
    name: "full_featured_agent",
    description: "Tests all agent features with Instance pattern",
    category: "test",
    tags: ["test", "full", "features"],
    vsn: "2.0.0",
    actions: [
      JidoTest.TestActions.Add,
      JidoTest.TestActions.Multiply,
      JidoTest.TestActions.DelayAction,
      JidoTest.TestActions.ContextAction,
      Jido.Actions.StateManager.Get,
      Jido.Actions.StateManager.Set,
      Jido.Actions.StateManager.Update,
      Jido.Actions.StateManager.Delete
    ],
    schema: [
      value: [type: :integer, default: 0, doc: "Current value"],
      location: [type: :atom, default: :home, doc: "Current location"],
      battery_level: [type: :pos_integer, default: 100, doc: "Battery percentage"],
      status: [type: :atom, default: :idle, doc: "Current status"],
      config: [type: :map, doc: "Configuration map", default: %{}],
      metadata: [type: {:map, :atom, :any}, default: %{}, doc: "Metadata storage"],
      # Callback tracking fields
      last_validated_at: [type: {:nullable, :datetime}, default: nil],
      planned_actions: [type: {:list, :tuple}, default: []],
      last_result_at: [type: {:nullable, :datetime}, default: nil],
      last_result_summary: [type: :any, default: nil]
    ]
  
  @impl true
  def init(config) do
    initial_state = %{
      value: config[:value] || 0,
      location: config[:location] || :home,
      battery_level: config[:battery_level] || 100,
      status: config[:status] || :idle,
      config: config[:config] || %{},
      metadata: config[:metadata] || %{},
      last_validated_at: nil,
      planned_actions: [],
      last_result_at: nil,
      last_result_summary: nil
    }
    
    {:ok, initial_state}
  end
  
  @impl true
  def on_before_validate_state(%Instance{state: state} = agent) do
    # Update state with validation timestamp
    new_state = Map.put(state, :last_validated_at, DateTime.utc_now())
    {:ok, Instance.update_state(agent, new_state)}
  end
  
  @impl true
  def on_before_plan(%Instance{state: state} = agent, action, params) do
    # Track planned actions
    planned_action = {action, params}
    new_state = Map.update(state, :planned_actions, [planned_action], fn actions ->
      [planned_action | actions]
    end)
    {:ok, Instance.update_state(agent, new_state)}
  end
  
  @impl true
  def on_before_run(%Instance{state: state} = agent) do
    # Set status to busy
    new_state = Map.put(state, :status, :busy)
    {:ok, Instance.update_state(agent, new_state)}
  end
  
  @impl true
  def on_after_run(%Instance{state: state} = agent, result, _directives) do
    # Update status and store result summary
    new_state =
      state
      |> Map.put(:status, :idle)
      |> Map.put(:last_result_at, DateTime.utc_now())
      |> Map.put(:last_result_summary, result)
    
    {:ok, Instance.update_state(agent, new_state)}
  end
end
```

### 2. Update callback signatures

Ensure all callbacks work with Instance:
```elixir
# Callback type signatures should expect Instance
@callback on_before_validate_state(Instance.t()) :: 
  {:ok, Instance.t()} | {:error, term()}

@callback on_before_plan(Instance.t(), module(), map()) :: 
  {:ok, Instance.t()} | {:error, term()}

@callback on_before_run(Instance.t()) :: 
  {:ok, Instance.t()} | {:error, term()}

@callback on_after_run(Instance.t(), term(), list()) :: 
  {:ok, Instance.t()} | {:error, term()}
```

### 3. State update helper pattern

Create a consistent pattern for state updates in callbacks:
```elixir
# Helper function for cleaner state updates
defp update_agent_state(agent, updates) when is_map(updates) do
  new_state = Map.merge(agent.state, updates)
  Instance.update_state(agent, new_state)
end

defp update_agent_state(agent, fun) when is_function(fun, 1) do
  new_state = fun.(agent.state)
  Instance.update_state(agent, new_state)
end

# Usage in callbacks
@impl true
def on_after_run(agent, result, _directives) do
  updated = update_agent_state(agent, %{
    status: :idle,
    last_result_at: DateTime.utc_now(),
    last_result_summary: result
  })
  {:ok, updated}
end
```

### 4. Test callback behavior with Instance

```elixir
test "FullFeaturedAgent callbacks work with Instance pattern" do
  {:ok, agent} = FullFeaturedAgent.new()
  
  # Test on_before_validate_state
  {:ok, validated} = FullFeaturedAgent.on_before_validate_state(agent)
  assert validated.state[:last_validated_at] != nil
  assert validated.__dirty__ == true
  
  # Test on_before_plan
  {:ok, planned} = FullFeaturedAgent.on_before_plan(
    agent, 
    TestAction, 
    %{param: "value"}
  )
  assert [{TestAction, %{param: "value"}}] = planned.state[:planned_actions]
  
  # Test on_before_run
  {:ok, running} = FullFeaturedAgent.on_before_run(agent)
  assert running.state[:status] == :busy
  
  # Test on_after_run
  {:ok, completed} = FullFeaturedAgent.on_after_run(
    running, 
    {:ok, "result"}, 
    []
  )
  assert completed.state[:status] == :idle
  assert completed.state[:last_result_summary] == {:ok, "result"}
end

test "State updates mark agent as dirty" do
  {:ok, agent} = FullFeaturedAgent.new()
  assert agent.__dirty__ == false
  
  # Any state update should mark as dirty
  {:ok, updated} = FullFeaturedAgent.on_before_run(agent)
  assert updated.__dirty__ == true
end
```

### 5. Integration with Agent.Server

Ensure callbacks work when agent runs in server:
```elixir
test "FullFeaturedAgent works in Agent.Server" do
  {:ok, agent} = FullFeaturedAgent.new()
  {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)
  
  # Server should handle Instance-based callbacks
  state = Jido.Agent.Server.get_state(pid)
  assert %Instance{module: FullFeaturedAgent} = state.agent
  
  # Run an action to trigger callbacks
  instruction = Jido.Instruction.new!(
    action: JidoTest.TestActions.Add,
    params: %{value: 5}
  )
  
  {:ok, result} = Jido.Agent.Server.run(pid, instruction)
  
  # Check callbacks were triggered
  updated_state = Jido.Agent.Server.get_state(pid)
  assert updated_state.agent.state[:last_result_at] != nil
  assert updated_state.agent.state[:status] == :idle
end
```

## Success criteria:
- [ ] All callbacks updated to work with Instance pattern
- [ ] State updates use `Instance.update_state/2`
- [ ] No more struct update syntax (`%{agent | ...}`)
- [ ] Callbacks properly mark agent as dirty
- [ ] All callback tests pass
- [ ] Integration with Agent.Server works
- [ ] Dialyzer clean

## Testing requirements:
- Test each callback with Instance struct
- Test state updates mark agent as dirty
- Test callbacks in Agent.Server context
- Test callback error handling
- Verify no polymorphic struct usage

## Notes:
- Callbacks are a key integration point
- The `__dirty__` flag is important for state tracking
- This pattern will be used for all agents with callbacks
- State updates must go through Instance.update_state/2