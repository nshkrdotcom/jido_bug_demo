defmodule JidoBugDemo.BoundaryEnforcementDemo do
  @moduledoc """
  Demonstrates how implementing the "Defensive Boundary / Offensive Interior" pattern
  from docs20250702 exposes type system crashes in Jido.
  
  This module shows:
  1. Type contract validation at boundaries
  2. How Jido's internal type mismatches break defensive patterns
  3. Cascading type errors through metaprogramming layers
  """
  
  use Jido.Agent,
    name: "boundary_enforcer",
    description: "Agent implementing strict type boundaries",
    schema: [
      # Contract registry for runtime type checking
      contracts: [type: :map, default: %{}],
      
      # Validation results cache
      validation_cache: [type: :map, default: %{}],
      
      # Enforcement configuration
      enforcement_level: [type: :atom, default: :strict, in: [:strict, :warn, :log]]
    ]

  # Type definitions matching the defensive boundary pattern
  @type contract_name :: atom()
  @type contract_spec :: %{
    required: %{atom() => contract_field()},
    optional: %{atom() => contract_field()},
    validators: [validation_fn()]
  }
  @type contract_field :: %{
    type: atom(),
    constraints: keyword()
  }
  @type validation_fn :: (map() -> {:ok, map()} | {:error, term()})
  @type enforcement_level :: :strict | :warn | :log

  # Define contracts following the pattern from type_contract_best_practices.md
  def define_contract(agent, name, spec) when is_atom(name) do
    # Validate contract specification structure
    case validate_contract_spec(spec) do
      {:ok, validated_spec} ->
        # This demonstrates the type mismatch:
        # We're following best practices but Jido's set/3 breaks it
        contracts = Map.put(agent.state.contracts, name, validated_spec)
        
        # Type error here: set/3 expects keyword() but gets map()
        case set(agent, %{contracts: contracts}) do
          {:ok, updated_agent} ->
            # Clear validation cache when contracts change
            clear_validation_cache(updated_agent, name)
          error ->
            error
        end
      
      {:error, reason} ->
        {:error, {:invalid_contract_spec, name, reason}}
    end
  end

  # Boundary guard implementation
  def guard_boundary(agent, contract_name, data, opts \\ []) do
    enforcement = Keyword.get(opts, :enforcement, agent.state.enforcement_level)
    
    case get_contract(agent, contract_name) do
      {:ok, contract} ->
        # Check cache first (performance optimization from docs)
        cache_key = {contract_name, :erlang.phash2(data)}
        
        case get_cached_validation(agent, cache_key) do
          {:ok, cached_result} ->
            handle_validation_result(agent, cached_result, enforcement)
          
          :miss ->
            # Perform validation
            result = validate_against_contract(contract, data)
            
            # Cache result - another type mismatch point
            with {:ok, agent_with_cache} <- cache_validation_result(agent, cache_key, result) do
              handle_validation_result(agent_with_cache, result, enforcement)
            end
        end
      
      {:error, :not_found} ->
        {:error, {:unknown_contract, contract_name}}
    end
  end

  # Metaprogramming with type boundaries
  def generate_guarded_function(agent, function_name, contract_name, implementation) do
    # This shows how metaprogramming + type safety = dialyzer errors
    case get_contract(agent, contract_name) do
      {:ok, contract} ->
        # Generate function with boundary protection
        ast = quote do
          def unquote(function_name)(data) do
            # Boundary enforcement
            case unquote(__MODULE__).validate_against_contract(
              unquote(Macro.escape(contract)), 
              data
            ) do
              {:ok, validated_data} ->
                # Interior - trust validated data
                unquote(implementation).(validated_data)
              
              {:error, violations} ->
                {:error, {:validation_failed, violations}}
            end
          end
        end
        
        {:ok, ast}
      
      {:error, _} = error ->
        error
    end
  end

  # Private implementation functions

  defp validate_contract_spec(spec) do
    required_keys = [:required, :optional]
    
    if Enum.all?(required_keys, &Map.has_key?(spec, &1)) do
      {:ok, spec}
    else
      {:error, :incomplete_contract_spec}
    end
  end

  defp get_contract(agent, name) do
    case Map.fetch(agent.state.contracts, name) do
      {:ok, contract} -> {:ok, contract}
      :error -> {:error, :not_found}
    end
  end

  defp get_cached_validation(agent, cache_key) do
    case Map.fetch(agent.state.validation_cache, cache_key) do
      {:ok, result} -> {:ok, result}
      :error -> :miss
    end
  end

  defp cache_validation_result(agent, cache_key, result) do
    # Another type mismatch: updating nested maps
    updated_cache = Map.put(agent.state.validation_cache, cache_key, result)
    set(agent, %{validation_cache: updated_cache})
  end

  defp clear_validation_cache(agent, contract_name) do
    # Clear all cached validations for this contract
    filtered_cache = agent.state.validation_cache
    |> Enum.reject(fn {{name, _}, _} -> name == contract_name end)
    |> Map.new()
    
    set(agent, %{validation_cache: filtered_cache})
  end

  def validate_against_contract(contract, data) do
    # Implement the validation pipeline from the docs
    with {:ok, data} <- validate_required_fields(contract.required, data),
         {:ok, data} <- validate_optional_fields(contract.optional, data),
         {:ok, data} <- run_custom_validators(contract[:validators] || [], data) do
      {:ok, data}
    end
  end

  defp validate_required_fields(required, data) do
    violations = Enum.reduce(required, [], fn {field, spec}, acc ->
      case Map.fetch(data, field) do
        {:ok, value} ->
          case validate_field_value(field, value, spec) do
            :ok -> acc
            {:error, reason} -> [{field, reason} | acc]
          end
        :error ->
          [{field, "is required"} | acc]
      end
    end)
    
    if violations == [] do
      {:ok, data}
    else
      {:error, violations}
    end
  end

  defp validate_optional_fields(optional, data) do
    violations = Enum.reduce(optional, [], fn {field, spec}, acc ->
      case Map.fetch(data, field) do
        {:ok, value} ->
          case validate_field_value(field, value, spec) do
            :ok -> acc
            {:error, reason} -> [{field, reason} | acc]
          end
        :error ->
          acc  # Optional fields can be missing
      end
    end)
    
    if violations == [] do
      {:ok, data}
    else
      {:error, violations}
    end
  end

  defp validate_field_value(_field, value, %{type: type, constraints: constraints}) do
    # Type checking with constraints
    if check_type(value, type) do
      check_constraints(value, constraints)
    else
      {:error, "invalid type, expected #{type}"}
    end
  end

  defp check_type(value, :string), do: is_binary(value)
  defp check_type(value, :integer), do: is_integer(value)
  defp check_type(value, :atom), do: is_atom(value)
  defp check_type(value, :map), do: is_map(value)
  defp check_type(value, :list), do: is_list(value)
  defp check_type(_value, _type), do: false

  defp check_constraints(value, constraints) do
    Enum.reduce_while(constraints, :ok, fn
      {:min, min}, :ok when is_integer(value) ->
        if value >= min, do: {:cont, :ok}, else: {:halt, {:error, "must be at least #{min}"}}
      
      {:max, max}, :ok when is_integer(value) ->
        if value <= max, do: {:cont, :ok}, else: {:halt, {:error, "must be at most #{max}"}}
      
      {:min_length, min}, :ok when is_binary(value) ->
        if String.length(value) >= min, do: {:cont, :ok}, else: {:halt, {:error, "must be at least #{min} characters"}}
      
      {:in, allowed}, :ok ->
        if value in allowed, do: {:cont, :ok}, else: {:halt, {:error, "must be one of: #{inspect(allowed)}"}}
      
      _, :ok ->
        {:cont, :ok}
    end)
  end

  defp run_custom_validators(validators, data) do
    Enum.reduce_while(validators, {:ok, data}, fn validator, {:ok, acc_data} ->
      case validator.(acc_data) do
        {:ok, new_data} -> {:cont, {:ok, new_data}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp handle_validation_result(agent, result, enforcement_level) do
    case {result, enforcement_level} do
      {{:ok, _}, _} ->
        {:ok, agent}
      
      {{:error, violations}, :strict} ->
        {:error, {:validation_failed, violations}}
      
      {{:error, violations}, :warn} ->
        IO.warn("Boundary validation failed: #{inspect(violations)}")
        {:ok, agent}
      
      {{:error, violations}, :log} ->
        require Logger
        Logger.info("Boundary validation failed: #{inspect(violations)}")
        {:ok, agent}
    end
  end
end