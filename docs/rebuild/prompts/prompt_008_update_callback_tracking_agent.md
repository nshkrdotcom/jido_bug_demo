# Prompt 8: Update CallbackTrackingAgent to Instance Pattern

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update CallbackTrackingAgent to Instance pattern (Prompt 8 of ~30)

## References needed:
- Prompts 1-7 (Instance pattern foundation)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 101, Week 1, Task 4 (Complete agent updates)

## Current code issue:
CallbackTrackingAgent extensively manipulates agent state and needs careful Instance migration:
```elixir
def track_callback(agent, callback_name) do
  # ... state updates ...
  %{agent | state: new_state}  # This pattern must change
end
```

## Implementation requirements:

### 1. Update CallbackTrackingAgent with Instance pattern

```elixir
defmodule CallbackTrackingAgent do
  @moduledoc """
  Agent that tracks all callback executions - uses Instance pattern.
  Useful for testing callback order and state transitions.
  """
  use Jido.Agent,
    name: "callback_tracking_agent",
    version: "2.0.0",
    actions: [
      JidoTest.TestActions.Add,
      JidoTest.TestActions.Multiply
    ],
    schema: [
      callback_log: [type: {:list, :map}, default: []],
      callback_count: [type: :map, default: %{}]
    ]
  
  alias Jido.Agent.Instance
  alias Jido.Signal
  
  @impl true
  def init(config) do
    initial_state = %{
      callback_log: [],
      callback_count: %{},
      # Optional tracking configuration
      track_timestamps: config[:track_timestamps] || true,
      track_state_snapshots: config[:track_state_snapshots] || false,
      max_log_entries: config[:max_log_entries] || 100
    }
    
    {:ok, initial_state}
  end
  
  @doc """
  Tracks a callback execution with Instance pattern.
  """
  def track_callback(%Instance{state: state} = agent, callback_name) do
    entry = build_log_entry(callback_name, state, agent)
    
    new_state =
      state
      |> update_callback_log(entry)
      |> update_callback_count(callback_name)
      |> maybe_trim_log()
    
    Instance.update_state(agent, new_state)
  end
  
  # Private helpers
  
  defp build_log_entry(callback_name, state, agent) do
    entry = %{
      callback: callback_name,
      agent_id: agent.id
    }
    
    entry = if state[:track_timestamps] do
      Map.put(entry, :timestamp, DateTime.utc_now())
    else
      entry
    end
    
    if state[:track_state_snapshots] do
      # Only track essential state, not full state to avoid bloat
      Map.put(entry, :state_snapshot, %{
        callback_count: state[:callback_count],
        log_size: length(state[:callback_log])
      })
    else
      entry
    end
  end
  
  defp update_callback_log(state, entry) do
    Map.update!(state, :callback_log, &[entry | &1])
  end
  
  defp update_callback_count(state, callback_name) do
    Map.update(state, :callback_count, %{callback_name => 1}, fn counts ->
      Map.update(counts, callback_name, 1, &(&1 + 1))
    end)
  end
  
  defp maybe_trim_log(%{callback_log: log, max_log_entries: max} = state) 
       when length(log) > max do
    trimmed_log = Enum.take(log, max)
    Map.put(state, :callback_log, trimmed_log)
  end
  defp maybe_trim_log(state), do: state
  
  # Callback implementations
  
  @impl true
  def mount(%{agent: agent} = state, _opts) do
    updated_agent = track_callback(agent, :mount)
    {:ok, %{state | agent: updated_agent}}
  end
  
  @impl true
  def code_change(%{agent: agent} = state, _old_vsn, _extra) do
    updated_agent = track_callback(agent, :code_change)
    {:ok, %{state | agent: updated_agent}}
  end
  
  @impl true
  def shutdown(%{agent: agent} = state, _reason) do
    updated_agent = track_callback(agent, :shutdown)
    {:ok, %{state | agent: updated_agent}}
  end
  
  @impl true
  def handle_signal(signal, agent) do
    # Track signal handling
    updated_agent = track_callback(agent, {:handle_signal, signal.type})
    
    # Process signal
    processed_signal = %{signal | data: Map.put(signal.data, :agent_handled, true)}
    
    {:ok, processed_signal, updated_agent}
  end
  
  @impl true
  def transform_result(signal, result, agent) do
    # Track result transformation
    updated_agent = track_callback(agent, {:transform_result, signal.type})
    
    # Transform result
    transformed = Map.put(result, :agent_processed, true)
    
    {:ok, transformed, updated_agent}
  end
  
  @impl true
  def on_before_validate_state(%Instance{} = agent) do
    {:ok, track_callback(agent, :on_before_validate_state)}
  end
  
  @impl true
  def on_after_validate_state(%Instance{} = agent) do
    {:ok, track_callback(agent, :on_after_validate_state)}
  end
  
  @impl true
  def on_before_plan(%Instance{} = agent, action, params) do
    updated = track_callback(agent, {:on_before_plan, action})
    {:ok, updated}
  end
  
  @impl true
  def on_before_run(%Instance{} = agent) do
    {:ok, track_callback(agent, :on_before_run)}
  end
  
  @impl true
  def on_after_run(%Instance{} = agent, _result, _directives) do
    {:ok, track_callback(agent, :on_after_run)}
  end
  
  @impl true
  def on_error(%Instance{} = agent, _error) do
    {:ok, track_callback(agent, :on_error), []}
  end
end
```

### 2. Add query functions for tracked data

```elixir
defmodule CallbackTrackingAgent do
  # ... previous code ...
  
  @doc """
  Gets the callback execution history.
  """
  def get_callback_history(%Instance{state: state}) do
    Enum.reverse(state.callback_log)
  end
  
  @doc """
  Gets callback execution counts.
  """
  def get_callback_counts(%Instance{state: state}) do
    state.callback_count
  end
  
  @doc """
  Checks if a callback was executed.
  """
  def callback_executed?(%Instance{state: state}, callback_name) do
    Map.has_key?(state.callback_count, callback_name)
  end
  
  @doc """
  Gets the execution order of callbacks.
  """
  def get_execution_order(%Instance{state: state}) do
    state.callback_log
    |> Enum.reverse()
    |> Enum.map(& &1.callback)
  end
end
```

### 3. Comprehensive tests

```elixir
test "CallbackTrackingAgent tracks all callbacks with Instance" do
  {:ok, agent} = CallbackTrackingAgent.new()
  
  # Simulate lifecycle callbacks
  {:ok, agent} = CallbackTrackingAgent.on_before_validate_state(agent)
  {:ok, agent} = CallbackTrackingAgent.on_after_validate_state(agent)
  {:ok, agent} = CallbackTrackingAgent.on_before_run(agent)
  {:ok, agent} = CallbackTrackingAgent.on_after_run(agent, {:ok, "result"}, [])
  
  # Verify tracking
  assert CallbackTrackingAgent.callback_executed?(agent, :on_before_validate_state)
  assert CallbackTrackingAgent.callback_executed?(agent, :on_after_run)
  
  # Check execution order
  order = CallbackTrackingAgent.get_execution_order(agent)
  assert order == [
    :on_before_validate_state,
    :on_after_validate_state,
    :on_before_run,
    :on_after_run
  ]
  
  # Check counts
  counts = CallbackTrackingAgent.get_callback_counts(agent)
  assert counts[:on_before_run] == 1
end

test "CallbackTrackingAgent handles signal callbacks" do
  {:ok, agent} = CallbackTrackingAgent.new()
  
  signal = %Signal{
    id: "test-signal",
    type: "test.event",
    data: %{value: 42}
  }
  
  # Test handle_signal
  {:ok, processed_signal, updated_agent} = 
    CallbackTrackingAgent.handle_signal(signal, agent)
  
  assert processed_signal.data.agent_handled == true
  assert CallbackTrackingAgent.callback_executed?(
    updated_agent, 
    {:handle_signal, "test.event"}
  )
  
  # Test transform_result
  {:ok, result, final_agent} = 
    CallbackTrackingAgent.transform_result(signal, %{data: "test"}, updated_agent)
  
  assert result.agent_processed == true
  assert CallbackTrackingAgent.get_callback_counts(final_agent) == %{
    {:handle_signal, "test.event"} => 1,
    {:transform_result, "test.event"} => 1
  }
end

test "CallbackTrackingAgent respects max log entries" do
  {:ok, agent} = CallbackTrackingAgent.new(%{max_log_entries: 5})
  
  # Generate more than max entries
  agent = Enum.reduce(1..10, agent, fn i, acc ->
    track_callback(acc, :"callback_#{i}")
  end)
  
  # Should only keep last 5
  history = CallbackTrackingAgent.get_callback_history(agent)
  assert length(history) == 5
  assert hd(history).callback == :callback_6  # First kept entry
end

test "CallbackTrackingAgent marks as dirty on updates" do
  {:ok, agent} = CallbackTrackingAgent.new()
  assert agent.__dirty__ == false
  
  {:ok, updated} = CallbackTrackingAgent.on_before_run(agent)
  assert updated.__dirty__ == true
end
```

### 4. Server integration test

```elixir
test "CallbackTrackingAgent works in Agent.Server" do
  {:ok, agent} = CallbackTrackingAgent.new()
  {:ok, pid} = Jido.Agent.Server.start_link(
    agent: agent,
    mount_callback: true
  )
  
  # Mount callback should have been tracked
  state = Jido.Agent.Server.get_state(pid)
  assert CallbackTrackingAgent.callback_executed?(state.agent, :mount)
  
  # Run an instruction to trigger more callbacks
  instruction = Jido.Instruction.new!(
    action: JidoTest.TestActions.Add,
    params: %{value: 5}
  )
  
  {:ok, _result} = Jido.Agent.Server.run(pid, instruction)
  
  # Get final state
  final_state = Jido.Agent.Server.get_state(pid)
  history = CallbackTrackingAgent.get_callback_history(final_state.agent)
  
  # Verify callback sequence
  callback_names = Enum.map(history, & &1.callback)
  assert :mount in callback_names
  assert :on_before_run in callback_names
  assert :on_after_run in callback_names
end
```

## Success criteria:
- [ ] All tracking uses Instance.update_state/2
- [ ] No struct update syntax remains
- [ ] Callback tracking maintains correct order
- [ ] Signal callbacks properly tracked
- [ ] Query functions work with Instance
- [ ] Log trimming works correctly
- [ ] Server integration maintains tracking
- [ ] All tests pass
- [ ] Dialyzer clean

## Testing requirements:
- Test all callback types are tracked
- Test execution order is preserved
- Test callback counts are accurate
- Test log size limits are respected
- Test signal-specific callbacks
- Test dirty flag behavior
- Test server integration

## Notes:
- This completes the Phase 1 foundation agents
- Pattern established can be applied to any agent
- Tracking functionality preserved through migration
- Instance pattern proven to work with complex state manipulation