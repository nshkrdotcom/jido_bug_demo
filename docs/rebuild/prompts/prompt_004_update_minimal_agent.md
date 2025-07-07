# Prompt 4: Update MinimalAgent to Instance Pattern

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update MinimalAgent to use Instance pattern (Prompt 4 of ~30)

## References needed:
- Prompts 1-3 (Core types, Instance implementation, Fixed agent macro)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 101, Week 1, Task 4 (Update existing agents)

## Current code issue:
From `test/support/test_agent.ex`, MinimalAgent uses the old pattern:
```elixir
defmodule MinimalAgent do
  @moduledoc "Minimal agent with no schema or actions"
  use Jido.Agent,
    name: "minimal_agent"
end
```

This creates a polymorphic struct `%MinimalAgent{}` which we need to eliminate.

## Implementation requirements:

### 1. Update MinimalAgent definition

Update the agent to work with the new Instance pattern:

```elixir
defmodule MinimalAgent do
  @moduledoc "Minimal agent with no schema or actions - uses Instance pattern"
  use Jido.Agent,
    name: "minimal_agent",
    version: "2.0.0"  # Bump version to indicate Instance pattern
  
  @doc """
  Initialize minimal agent with empty state.
  """
  @impl true
  def init(_config) do
    {:ok, %{}}
  end
end
```

### 2. Update any code that creates MinimalAgent instances

Replace direct struct creation:
```elixir
# OLD - Don't use this anymore
agent = %MinimalAgent{id: "test", state: %{}}

# NEW - Use the new/0 or new/1 functions
{:ok, agent} = MinimalAgent.new()
{:ok, agent} = MinimalAgent.new(%{custom: "config"})
```

### 3. Update pattern matching in tests

Update pattern matching to work with Instance:
```elixir
# OLD
assert %MinimalAgent{state: state} = agent

# NEW
assert %Jido.Agent.Instance{module: MinimalAgent, state: state} = agent
```

### 4. Add migration test

Add a test to verify the migration works:
```elixir
test "MinimalAgent uses Instance pattern" do
  # Create agent
  assert {:ok, agent} = MinimalAgent.new()
  
  # Verify it's an Instance
  assert %Jido.Agent.Instance{
    module: MinimalAgent,
    state: %{},
    id: id,
    __dirty__: false
  } = agent
  
  # Verify ID format
  assert is_binary(id)
  assert String.starts_with?(id, "agent_")
  
  # Verify no polymorphic struct
  refute match?(%MinimalAgent{}, agent)
end

test "MinimalAgent init callback works" do
  # Test with config
  assert {:ok, agent} = MinimalAgent.new(%{test: true})
  assert %Jido.Agent.Instance{state: %{}} = agent
end
```

### 5. Documentation updates

Update module docs to show Instance pattern usage:
```elixir
@moduledoc """
Minimal agent with no schema or actions - uses Instance pattern.

## Examples

    # Create a new minimal agent
    {:ok, agent} = MinimalAgent.new()
    
    # Agent is now an Instance struct
    %Jido.Agent.Instance{module: MinimalAgent} = agent
    
    # Can be used with Agent.Server
    {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)

"""
```

## Success criteria:
- [ ] MinimalAgent no longer creates `%MinimalAgent{}` structs
- [ ] `MinimalAgent.new/0` returns `{:ok, %Jido.Agent.Instance{}}`
- [ ] All tests pass with Instance pattern
- [ ] No dialyzer warnings
- [ ] Pattern matching updated to use Instance
- [ ] Documentation shows Instance usage

## Testing requirements:
- Test that `MinimalAgent.new/0` creates Instance struct
- Test that old struct creation fails or is converted
- Test that agent works with Agent.Server
- Verify no polymorphic struct leakage

## Notes:
- This is the simplest agent, making it a good first migration
- Pattern established here will be used for other agents
- Focus on showing the migration is straightforward
- Next prompts will handle more complex agents with schemas and actions