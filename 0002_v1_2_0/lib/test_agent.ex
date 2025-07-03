defmodule JidoBugDemo.TestAgent do
  @moduledoc """
  Demonstrates type system crashes in realistic Jido application scenarios.
  
  This agent simulates a real-world pipeline management system that:
  - Manages workflow states with strict type contracts
  - Implements defensive boundaries per docs20250702 patterns
  - Uses metaprogramming for dynamic action dispatch
  - Shows how type mismatches cascade through the system
  """
  
  use Jido.Agent,
    name: "pipeline_manager",
    description: "Pipeline workflow orchestration agent demonstrating type safety issues",
    schema: [
      # Workflow state management
      status: [type: :atom, default: :idle, in: [:idle, :processing, :complete, :error]],
      current_step: [type: :integer, default: 0],
      total_steps: [type: :integer, default: 0],
      
      # Dynamic action registry following defensive boundary pattern
      registered_actions: [type: :map, default: %{}],
      
      # Execution context with strict typing
      context: [type: :map, default: %{user_id: nil, session_id: nil}],
      
      # Metrics tracking
      metrics: [type: :map, default: %{
        actions_executed: 0,
        errors_count: 0,
        last_error: nil
      }]
    ]

  @type workflow_state :: :idle | :processing | :complete | :error
  @type action_result :: {:ok, map()} | {:error, term()}
  
  # Implement mount with realistic initialization
  @spec mount(t(), keyword()) :: {:ok, map()} | {:error, any()}
  def mount(agent, opts) do
    # Simulate real-world initialization with type boundary validation
    initial_actions = Keyword.get(opts, :actions, [])
    
    case validate_and_register_actions(agent, initial_actions) do
      {:ok, _updated_agent} ->
        {:ok, %{initialized_at: DateTime.utc_now()}}
      {:error, reason} ->
        {:error, {:initialization_failed, reason}}
    end
  end

  @spec shutdown(t(), any()) :: {:ok, map()} | {:error, any()}
  def shutdown(agent, reason) do
    # Cleanup with state validation
    final_metrics = %{
      shutdown_reason: reason,
      final_status: agent.state.status,
      total_actions: agent.state.metrics.actions_executed
    }
    {:ok, final_metrics}
  end

  # This is where type system issues manifest in real usage
  # The set/3 function in Jido.Agent has mismatched type specs
  def update_workflow_state(agent, new_state, opts \\ []) do
    # According to docs, we should use defensive boundaries
    validated_state = validate_workflow_transition(agent.state, new_state)
    
    # This call will trigger dialyzer errors because:
    # 1. Jido.Agent.set/3 expects keyword() for opts
    # 2. But internally passes opts as any() 
    # 3. Creating a contract violation
    case agent |> set(validated_state, opts) do
      {:ok, updated_agent} ->
        # Post-update validation per defensive boundary pattern
        validate_state_integrity(updated_agent)
      error ->
        error
    end
  end

  # Dynamic action dispatch following metaprogramming patterns from docs
  def execute_action(agent, action_name, params) when is_binary(action_name) do
    # Defensive boundary: validate action exists
    case Map.get(agent.state.registered_actions, action_name) do
      nil ->
        {:error, {:unknown_action, action_name}}
      
      action_module ->
        # This demonstrates the "Assertive Dynamic Dispatch" pattern
        # But dialyzer can't verify the module implements the expected behavior
        dispatch_with_boundary_protection(agent, action_module, params)
    end
  end

  # Private functions demonstrating type safety patterns

  defp validate_and_register_actions(agent, actions) do
    # Implements "Contract-Based Module Generation" pattern
    Enum.reduce_while(actions, {:ok, agent}, fn {name, module}, {:ok, acc_agent} ->
      case validate_action_module(module) do
        :ok ->
          updated_actions = Map.put(acc_agent.state.registered_actions, name, module)
          # This will cause dialyzer issues due to type specification mismatch
          case set(acc_agent, %{registered_actions: updated_actions}) do
            {:ok, new_agent} -> {:cont, {:ok, new_agent}}
            error -> {:halt, error}
          end
        {:error, reason} ->
          {:halt, {:error, {:invalid_action, name, reason}}}
      end
    end)
  end

  defp validate_action_module(module) do
    # Type-safe validation of dynamic modules
    if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
      :ok
    else
      {:error, :invalid_action_module}
    end
  end

  defp validate_workflow_transition(current_state, new_state) do
    # Implements state machine transition validation
    valid_transitions = %{
      idle: [:processing],
      processing: [:complete, :error, :processing],
      complete: [:idle],
      error: [:idle, :processing]
    }
    
    current_status = current_state.status
    new_status = new_state[:status] || current_status
    
    allowed = Map.get(valid_transitions, current_status, [])
    
    if new_status in allowed do
      new_state
    else
      # This demonstrates how runtime validation doesn't help with compile-time type issues
      raise "Invalid state transition from #{current_status} to #{new_status}"
    end
  end

  defp dispatch_with_boundary_protection(agent, action_module, params) do
    # Update metrics before execution
    updated_metrics = Map.update(agent.state.metrics, :actions_executed, 1, &(&1 + 1))
    
    # Another type specification issue: set/3 with complex nested updates
    with {:ok, agent_before} <- set(agent, %{metrics: updated_metrics}),
         {:ok, result} <- apply(action_module, :run, [params, agent.state.context]),
         {:ok, agent_after} <- update_agent_after_action(agent_before, result) do
      {:ok, agent_after, result}
    else
      {:error, reason} = error ->
        # Error handling that triggers more type issues
        handle_action_error(agent, action_module, reason)
        error
    end
  end

  defp update_agent_after_action(agent, result) do
    updates = %{
      current_step: agent.state.current_step + 1,
      last_action_result: result
    }
    
    # Recursive type issues when updating nested structures
    set(agent, updates)
  end

  defp handle_action_error(agent, action_module, error) do
    error_metrics = agent.state.metrics
    |> Map.update(:errors_count, 1, &(&1 + 1))
    |> Map.put(:last_error, {action_module, error, DateTime.utc_now()})
    
    # Final type mismatch in error handling path
    set(agent, %{status: :error, metrics: error_metrics})
  end

  defp validate_state_integrity(agent) do
    # Post-update validation following defensive boundary principles
    state = agent.state
    
    cond do
      state.current_step > state.total_steps ->
        {:error, :invalid_step_count}
      
      state.status == :complete and state.current_step < state.total_steps ->
        {:error, :incomplete_workflow}
      
      true ->
        {:ok, agent}
    end
  end

  # Override generated typespecs to show the mismatch
  @spec do_validate(t(), map(), keyword()) :: {:ok, map()} | {:error, Jido.Error.t()}
  @spec pending?(t()) :: non_neg_integer()
  @spec reset(t()) :: {:ok, t()} | {:error, Jido.Error.t()}
  
  # Additional specs that demonstrate the cascading type issues
  @spec update_workflow_state(t(), map(), keyword() | any()) :: action_result()
  @spec execute_action(t(), binary(), map()) :: {:ok, t(), any()} | {:error, term()}
end
