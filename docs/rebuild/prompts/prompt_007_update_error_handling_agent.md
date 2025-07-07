# Prompt 7: Update ErrorHandlingAgent to Instance Pattern

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update ErrorHandlingAgent with error callbacks to Instance pattern (Prompt 7 of ~30)

## References needed:
- Prompts 1-6 (Instance pattern work)
- Doc 102, section 3 (Agent Type Specifications)
- Doc 107, section 2 (Recovery Mechanisms)

## Current code issue:
ErrorHandlingAgent has error handling callbacks that use the polymorphic pattern:
```elixir
@impl true
def on_error(%{state: %{should_recover?: true}} = agent, result) do
  new_state =
    agent.state
    |> Map.update!(:error_count, &(&1 + 1))
    |> Map.put(:last_error, result)
  
  {:ok, %{agent | state: new_state}, []}
end
```

## Implementation requirements:

### 1. Update ErrorHandlingAgent for Instance pattern

```elixir
defmodule ErrorHandlingAgent do
  @moduledoc "Agent for testing error scenarios and recovery - uses Instance pattern"
  use Jido.Agent,
    name: "error_handling_agent",
    version: "2.0.0",
    actions: [
      JidoTest.TestActions.Add,
      JidoTest.TestActions.ErrorAction,
      JidoTest.TestActions.CompensateAction
    ],
    schema: [
      should_recover?: [type: :boolean, default: true],
      error_count: [type: :integer, default: 0],
      last_error: [type: :map, default: %{}],
      error_history: [type: {:list, :map}, default: []]
    ]
  
  alias Jido.Agent.Instance
  alias Jido.Core.Error
  
  @impl true
  def init(config) do
    initial_state = %{
      should_recover?: config[:should_recover?] || true,
      error_count: 0,
      last_error: %{},
      error_history: []
    }
    
    {:ok, initial_state}
  end
  
  @impl true
  def on_error(%Instance{state: %{should_recover?: true} = state} = agent, error) do
    # Create error record with timestamp
    error_record = %{
      error: error,
      timestamp: DateTime.utc_now(),
      count: state.error_count + 1
    }
    
    # Update state with error information
    new_state =
      state
      |> Map.update!(:error_count, &(&1 + 1))
      |> Map.put(:last_error, error_record)
      |> Map.update!(:error_history, &[error_record | &1])
    
    # Return updated agent with potential directives
    updated_agent = Instance.update_state(agent, new_state)
    
    # Could emit directives for error handling
    directives = maybe_emit_error_directives(error, state.error_count + 1)
    
    {:ok, updated_agent, directives}
  end
  
  @impl true
  def on_error(%Instance{state: %{should_recover?: false}} = _agent, error) do
    # Don't recover - propagate the error
    enhanced_error = enhance_error(error)
    {:error, enhanced_error}
  end
  
  # Private helpers
  
  defp maybe_emit_error_directives(error, error_count) do
    cond do
      error_count >= 5 ->
        # Too many errors - emit alert
        [{:publish, %{type: "error.threshold.exceeded", data: %{count: error_count}}}]
      
      error_count >= 3 ->
        # Multiple errors - slow down
        [{:delay, 1000}]
      
      true ->
        []
    end
  end
  
  defp enhance_error(error) when is_struct(error, Error) do
    Error.add_context(error, %{
      agent: __MODULE__,
      recovery_attempted: false
    })
  end
  
  defp enhance_error(other) do
    Error.new(:execution_error, other, 
      context: %{
        agent: __MODULE__,
        recovery_attempted: false
      }
    )
  end
end
```

### 2. Add error recovery strategies

Implement recovery patterns from Doc 107:
```elixir
defmodule ErrorHandlingAgent do
  # ... previous code ...
  
  @doc """
  Implements various recovery strategies based on error type.
  """
  def recovery_strategy(%Instance{state: state} = agent, error) do
    case categorize_error(error) do
      :transient ->
        {:retry, %{max_attempts: 3, backoff: :exponential}}
      
      :resource ->
        {:circuit_breaker, %{threshold: 5, timeout: 30_000}}
      
      :validation ->
        {:fallback, &validation_fallback/2}
      
      :critical ->
        {:escalate, %{to: :supervisor}}
      
      _ ->
        if state.error_count < 3 do
          {:retry, %{max_attempts: 1}}
        else
          {:ignore, %{log: true}}
        end
    end
  end
  
  defp categorize_error(%Error{category: category}), do: category
  defp categorize_error(_), do: :unknown
  
  defp validation_fallback(_error, _agent) do
    # Return safe default state
    {:ok, %{safe_mode: true}}
  end
end
```

### 3. Test error handling with Instance

```elixir
test "ErrorHandlingAgent handles errors with recovery" do
  {:ok, agent} = ErrorHandlingAgent.new()
  
  # Simulate an error
  error = Error.execution_error("Something went wrong")
  
  # Test recovery path
  assert {:ok, updated, directives} = ErrorHandlingAgent.on_error(agent, error)
  assert %Instance{state: state} = updated
  assert state.error_count == 1
  assert state.last_error.error == error
  assert length(state.error_history) == 1
  assert updated.__dirty__ == true
  
  # Test multiple errors
  {:ok, updated2, _} = ErrorHandlingAgent.on_error(updated, error)
  assert updated2.state.error_count == 2
  
  # Test error threshold directives
  agent_with_errors = %{updated2 | state: %{updated2.state | error_count: 4}}
  {:ok, _, directives} = ErrorHandlingAgent.on_error(agent_with_errors, error)
  assert {:publish, %{type: "error.threshold.exceeded"}} in directives
end

test "ErrorHandlingAgent propagates errors when recovery disabled" do
  {:ok, agent} = ErrorHandlingAgent.new(%{should_recover?: false})
  error = Error.validation_error("Invalid input")
  
  # Should propagate error
  assert {:error, enhanced_error} = ErrorHandlingAgent.on_error(agent, error)
  assert %Error{} = enhanced_error
  assert enhanced_error.context.recovery_attempted == false
end

test "Recovery strategies based on error type" do
  {:ok, agent} = ErrorHandlingAgent.new()
  
  # Transient error - should retry
  transient_error = Error.new(:execution_error, "Network timeout", 
    category: :transient
  )
  assert {:retry, %{max_attempts: 3}} = 
    ErrorHandlingAgent.recovery_strategy(agent, transient_error)
  
  # Validation error - should use fallback
  validation_error = Error.validation_error("Invalid field")
  assert {:fallback, fallback_fn} = 
    ErrorHandlingAgent.recovery_strategy(agent, validation_error)
  assert is_function(fallback_fn, 2)
end
```

### 4. Integration with unified error system

```elixir
test "ErrorHandlingAgent integrates with unified error system" do
  {:ok, agent} = ErrorHandlingAgent.new()
  
  # Create error with full context
  error = Error.new(:execution_error, "Action failed",
    context: %{
      action: TestAction,
      params: %{value: -1}
    },
    parent_error: Error.validation_error("Negative value")
  )
  
  {:ok, updated, _} = ErrorHandlingAgent.on_error(agent, error)
  
  # Verify error chain is preserved
  last_error = updated.state.last_error.error
  assert last_error.parent_error != nil
  assert last_error.context.action == TestAction
end
```

## Success criteria:
- [ ] Error callbacks work with Instance pattern
- [ ] State updates use Instance.update_state/2
- [ ] Error history tracking works properly
- [ ] Recovery strategies implemented
- [ ] Integration with unified error system
- [ ] Directives emitted based on error patterns
- [ ] All tests pass with Instance
- [ ] Dialyzer clean

## Testing requirements:
- Test error recovery with Instance
- Test error propagation when recovery disabled
- Test error history accumulation
- Test recovery strategy selection
- Test directive emission on error thresholds
- Test integration with Error struct

## Notes:
- Error handling is critical for robustness
- This shows Instance pattern works with complex callbacks
- Recovery strategies align with Doc 107
- Error context is preserved through Instance updates