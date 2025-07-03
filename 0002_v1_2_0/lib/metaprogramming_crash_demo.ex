defmodule JidoBugDemo.MetaprogrammingCrashDemo do
  @moduledoc """
  Demonstrates how Jido's type system crashes when using advanced metaprogramming
  patterns recommended in docs20250702/type_safe_metaprogramming_patterns.md
  
  This shows real-world scenarios where:
  1. Compile-time contract validation meets runtime type mismatches
  2. Dynamic module generation exposes framework type inconsistencies
  3. Complex state transformations break dialyzer analysis
  """

  # First, let's define a macro that generates type-safe actions
  defmacro define_typed_action(name, contract, implementation) do
    quote do
      defmodule unquote(name) do
        use Jido.Action
        
        # Define compile-time contract
        @contract unquote(contract)
        
        # Generate run function with boundary protection
        def run(params, context) do
          # This pattern from the docs should work but triggers dialyzer errors
          case validate_input(@contract, params) do
            {:ok, validated} ->
              # Interior: trusted zone
              result = unquote(implementation).(validated, context)
              validate_output(result)
            
            {:error, violations} ->
              {:error, %Jido.Error{
                type: :validation_error,
                message: "Input validation failed",
                details: violations
              }}
          end
        end
        
        defp validate_input(contract, params) do
          # Simplified validation for demo
          required = Keyword.get(contract, :required, [])
          
          missing = Enum.reject(required, fn field ->
            Map.has_key?(params, field)
          end)
          
          if missing == [] do
            {:ok, params}
          else
            {:error, %{missing_fields: missing}}
          end
        end
        
        defp validate_output({:ok, _} = result), do: result
        defp validate_output({:error, _} = result), do: result
        defp validate_output(other), do: {:error, {:invalid_output, other}}
      end
    end
  end
end

defmodule JidoBugDemo.StateManagerAgent do
  @moduledoc """
  Complex agent demonstrating state management with type-safe metaprogramming.
  Shows how the framework's type issues cascade through realistic usage.
  """
  
  use Jido.Agent,
    name: "state_manager",
    description: "Manages complex application state with type safety",
    schema: [
      # State machine configuration
      states: [type: :map, default: %{}],
      current_state: [type: :atom, default: :initial],
      transitions: [type: :list, default: []],
      
      # Generated modules registry
      generated_modules: [type: :map, default: %{}],
      
      # Event log for audit
      event_log: [type: :list, default: []]
    ]

  require JidoBugDemo.MetaprogrammingCrashDemo

  # Define a state with compile-time validation
  def define_state(agent, state_name, config) when is_atom(state_name) do
    # Generate a module for this state dynamically
    module_name = Module.concat([__MODULE__, States, state_name])
    
    # This pattern should provide type safety but doesn't due to Jido's issues
    module_ast = quote do
      defmodule unquote(module_name) do
        @state_config unquote(Macro.escape(config))
        
        def enter(context) do
          # Validate context matches expected shape
          required_keys = Keyword.get(@state_config, :required_context, [])
          
          if Enum.all?(required_keys, &Map.has_key?(context, &1)) do
            {:ok, apply_enter_actions(context)}
          else
            {:error, :invalid_context}
          end
        end
        
        def exit(context) do
          apply_exit_actions(context)
        end
        
        defp apply_enter_actions(context) do
          Enum.reduce(@state_config[:on_enter] || [], context, fn action, ctx ->
            action.(ctx)
          end)
        end
        
        defp apply_exit_actions(context) do
          Enum.reduce(@state_config[:on_exit] || [], context, fn action, ctx ->
            action.(ctx)
          end)
        end
      end
    end
    
    # Compile the module
    Code.compile_quoted(module_ast)
    
    # Register it in the agent - type mismatch here
    updated_states = Map.put(agent.state.states, state_name, module_name)
    updated_modules = Map.put(agent.state.generated_modules, state_name, module_name)
    
    # Multiple set calls demonstrate cascading type errors
    with {:ok, agent} <- set(agent, %{states: updated_states}),
         {:ok, agent} <- set(agent, %{generated_modules: updated_modules}) do
      {:ok, agent}
    end
  end

  # Define a transition with type checking
  def define_transition(agent, from, to, guard_fn) 
      when is_atom(from) and is_atom(to) and is_function(guard_fn, 1) do
    
    transition = %{
      from: from,
      to: to,
      guard: guard_fn,
      defined_at: DateTime.utc_now()
    }
    
    # Validate states exist
    case {Map.has_key?(agent.state.states, from), Map.has_key?(agent.state.states, to)} do
      {true, true} ->
        # Add transition - another type mismatch point
        transitions = [transition | agent.state.transitions]
        set(agent, %{transitions: transitions})
      
      {false, _} ->
        {:error, {:unknown_state, from}}
      
      {_, false} ->
        {:error, {:unknown_state, to}}
    end
  end

  # Execute state transition with full type checking
  def transition_to(agent, new_state, context \\ %{}) do
    current = agent.state.current_state
    
    # Find valid transition
    transition = Enum.find(agent.state.transitions, fn t ->
      t.from == current && t.to == new_state && t.guard.(context)
    end)
    
    case transition do
      nil ->
        {:error, {:invalid_transition, current, new_state}}
      
      %{to: target} ->
        # Get state modules
        with {:ok, current_module} <- get_state_module(agent, current),
             {:ok, target_module} <- get_state_module(agent, target),
             {:ok, context} <- current_module.exit(context),
             {:ok, context} <- target_module.enter(context) do
          
          # Log the transition
          event = %{
            type: :transition,
            from: current,
            to: target,
            timestamp: DateTime.utc_now(),
            context: context
          }
          
          # Update agent state - multiple type mismatches
          updates = %{
            current_state: target,
            event_log: [event | agent.state.event_log]
          }
          
          set(agent, updates)
        end
    end
  end

  # Generate typed actions using our macro
  def generate_typed_actions(agent) do
    # Example of generating actions with contracts
    JidoBugDemo.MetaprogrammingCrashDemo.define_typed_action(
      ProcessDataAction,
      [required: [:data, :format], optional: [:options]],
      fn params, _context ->
        # Process data based on format
        case params.format do
          :json -> {:ok, Jason.decode!(params.data)}
          :csv -> {:ok, String.split(params.data, ",")}
          _ -> {:error, :unsupported_format}
        end
      end
    )
    
    # Register the action - type mismatch in dynamic registration
    register_action(agent, :process_data, ProcessDataAction)
  end

  # Private helper functions
  
  defp get_state_module(agent, state_name) do
    case Map.fetch(agent.state.generated_modules, state_name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:state_not_defined, state_name}}
    end
  end

  defp register_action(agent, name, module) do
    # This pattern breaks due to Jido's type specifications
    current_modules = agent.state.generated_modules
    updated = Map.put(current_modules, name, module)
    
    set(agent, %{generated_modules: updated})
  end


  # Complex nested state update that triggers multiple type errors
  def bulk_update_states(agent, state_updates) do
    # Validate all updates first
    validated_updates = Enum.map(state_updates, fn {state, config} ->
      case validate_state_config(config) do
        {:ok, valid_config} -> {:ok, {state, valid_config}}
        error -> error
      end
    end)
    
    # Check for any errors
    errors = Enum.filter(validated_updates, &match?({:error, _}, &1))
    
    if errors == [] do
      # Apply all updates - this creates a cascade of type mismatches
      Enum.reduce_while(validated_updates, {:ok, agent}, fn {:ok, {state, config}}, {:ok, acc_agent} ->
        case define_state(acc_agent, state, config) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, {:validation_errors, errors}}
    end
  end

  defp validate_state_config(config) do
    required = [:on_enter, :on_exit, :required_context]
    
    missing = Enum.reject(required, &Keyword.has_key?(config, &1))
    
    if missing == [] do
      {:ok, config}
    else
      {:error, {:missing_config_keys, missing}}
    end
  end

  # This function demonstrates the ultimate type system crash scenario
  def execute_complex_workflow(agent, workflow_definition) do
    # Parse workflow definition
    with {:ok, parsed} <- parse_workflow(workflow_definition),
         {:ok, agent} <- setup_workflow_states(agent, parsed.states),
         {:ok, agent} <- setup_workflow_transitions(agent, parsed.transitions),
         {:ok, agent} <- generate_workflow_actions(agent, parsed.actions) do
      
      # Start workflow execution
      transition_to(agent, parsed.initial_state, %{workflow: parsed})
    end
  end

  defp parse_workflow(definition) do
    # Simplified workflow parsing
    {:ok, %{
      states: definition[:states] || [],
      transitions: definition[:transitions] || [],
      actions: definition[:actions] || [],
      initial_state: definition[:initial_state] || :start
    }}
  end

  defp setup_workflow_states(agent, states) do
    bulk_update_states(agent, states)
  end

  defp setup_workflow_transitions(agent, transitions) do
    Enum.reduce_while(transitions, {:ok, agent}, fn trans, {:ok, acc} ->
      case define_transition(acc, trans.from, trans.to, trans.guard || fn _ -> true end) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end

  defp generate_workflow_actions(agent, actions) do
    Enum.reduce_while(actions, {:ok, agent}, fn _action_def, {:ok, acc} ->
      # Generate and register each action
      case generate_typed_actions(acc) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end
end