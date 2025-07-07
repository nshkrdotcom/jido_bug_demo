# 107: Error Handling and Recovery

## Overview

This document provides comprehensive specifications for error handling and recovery mechanisms in the integrated Jido framework, ensuring system resilience, graceful degradation, and clear error reporting throughout the migration and beyond.

## Error Architecture

### 1. Error Hierarchy

```elixir
# lib/jido/core/error.ex
defmodule Jido.Core.Error do
  @moduledoc """
  Unified error structure for the Jido framework.
  """
  
  use TypedStruct
  
  @type error_category :: 
    :validation |      # Input validation failures
    :execution |       # Runtime execution errors
    :system |          # System-level errors
    :integration |     # Integration/communication errors
    :concurrency |     # Concurrency-related errors
    :resource |        # Resource exhaustion/limits
    :security          # Security/permission errors
    
  @type error_severity ::
    :debug |           # Debugging information
    :info |            # Informational
    :warning |         # Warning, system continues
    :error |           # Error, operation failed
    :critical |        # Critical, system stability at risk
    :fatal             # Fatal, system must shutdown
    
  typedstruct do
    field :id, String.t(), enforce: true
    field :type, atom(), enforce: true
    field :category, error_category(), enforce: true
    field :severity, error_severity(), default: :error
    field :message, String.t(), enforce: true
    field :details, map(), default: %{}
    field :context, map(), default: %{}
    field :stacktrace, Exception.stacktrace()
    field :timestamp, DateTime.t(), default: DateTime.utc_now()
    field :parent, t()  # For error chaining
    field :retry_count, non_neg_integer(), default: 0
    field :recoverable?, boolean(), default: true
  end
  
  @doc """
  Create a new error with full context.
  """
  def new(type, message, opts \\ []) do
    %__MODULE__{
      id: Jido.Core.ID.generate(),
      type: type,
      category: categorize(type),
      severity: Keyword.get(opts, :severity, :error),
      message: message,
      details: Keyword.get(opts, :details, %{}),
      context: capture_context(opts),
      stacktrace: Keyword.get(opts, :stacktrace, capture_stacktrace()),
      parent: Keyword.get(opts, :parent),
      recoverable?: Keyword.get(opts, :recoverable?, true)
    }
  end
  
  # Automatic categorization based on error type
  defp categorize(type) do
    cond do
      type in [:invalid_input, :missing_field, :type_mismatch] -> :validation
      type in [:action_failed, :timeout, :process_crashed] -> :execution
      type in [:out_of_memory, :too_many_processes, :disk_full] -> :resource
      type in [:node_down, :network_error, :rpc_failed] -> :integration
      type in [:deadlock, :race_condition, :lock_timeout] -> :concurrency
      type in [:unauthorized, :forbidden, :invalid_token] -> :security
      true -> :system
    end
  end
  
  defp capture_context(opts) do
    base_context = %{
      node: node(),
      pid: self(),
      timestamp: DateTime.utc_now()
    }
    
    # Add caller information if available
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, [{caller, _, _, _} | _]} ->
        Map.put(base_context, :caller, caller)
      _ ->
        base_context
    end
    |> Map.merge(Keyword.get(opts, :context, %{}))
  end
  
  defp capture_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stack} -> stack
      _ -> []
    end
  end
end
```

### 2. Error Context Enrichment

```elixir
# lib/jido/core/error_context.ex
defmodule Jido.Core.ErrorContext do
  @moduledoc """
  Enriches errors with contextual information.
  """
  
  alias Jido.Core.Error
  
  @doc """
  Wrap an error with agent context.
  """
  def with_agent(%Error{} = error, %Jido.Agent.Instance{} = agent) do
    agent_context = %{
      agent_id: agent.id,
      agent_module: inspect(agent.module),
      agent_state_keys: Map.keys(agent.state),
      agent_version: agent.__vsn__
    }
    
    %{error | 
      context: Map.merge(error.context, agent_context),
      details: Map.put(error.details, :agent_info, agent_context)
    }
  end
  
  @doc """
  Wrap an error with signal context.
  """
  def with_signal(%Error{} = error, %Jido.Signal{} = signal) do
    signal_context = %{
      signal_id: signal.id,
      signal_type: signal.type,
      signal_source: signal.source,
      signal_time: signal.time
    }
    
    %{error | 
      context: Map.merge(error.context, signal_context),
      details: Map.put(error.details, :signal_info, signal_context)
    }
  end
  
  @doc """
  Wrap an error with instruction context.
  """
  def with_instruction(%Error{} = error, %Jido.Instruction{} = instruction) do
    instruction_context = %{
      instruction_id: instruction.id,
      action: inspect(instruction.action),
      params_keys: Map.keys(instruction.params)
    }
    
    %{error | 
      context: Map.merge(error.context, instruction_context),
      details: Map.put(error.details, :instruction_info, instruction_context)
    }
  end
  
  @doc """
  Chain errors together for full error trace.
  """
  def chain(%Error{} = parent, %Error{} = child) do
    %{child | parent: parent}
  end
  
  @doc """
  Convert exception to Error.
  """
  def from_exception(exception, opts \\ []) do
    Error.new(
      :exception,
      Exception.message(exception),
      Keyword.merge([
        severity: :error,
        details: %{
          exception_type: exception.__struct__,
          exception_fields: Map.from_struct(exception)
        },
        stacktrace: __STACKTRACE__,
        recoverable?: recoverable_exception?(exception)
      ], opts)
    )
  end
  
  defp recoverable_exception?(exception) do
    case exception do
      %ArgumentError{} -> false
      %ArithmeticError{} -> false
      %SystemLimitError{} -> false
      _ -> true
    end
  end
end
```

## Error Recovery Strategies

### 1. Automatic Recovery

```elixir
# lib/jido/core/recovery.ex
defmodule Jido.Core.Recovery do
  @moduledoc """
  Automatic error recovery strategies.
  """
  
  alias Jido.Core.Error
  
  @type recovery_strategy :: 
    :retry |           # Retry with backoff
    :circuit_breaker | # Circuit breaker pattern
    :fallback |        # Use fallback value/behavior
    :compensate |      # Run compensation logic
    :escalate |        # Escalate to supervisor
    :ignore            # Log and continue
    
  @type recovery_config :: %{
    strategy: recovery_strategy(),
    max_retries: non_neg_integer(),
    backoff: backoff_config(),
    fallback: term() | fun(),
    circuit_breaker: circuit_breaker_config()
  }
  
  @type backoff_config :: %{
    type: :exponential | :linear | :constant,
    initial: non_neg_integer(),
    max: non_neg_integer(),
    jitter: boolean()
  }
  
  @doc """
  Execute function with automatic recovery.
  """
  def with_recovery(fun, config \\ default_config()) do
    execute_with_recovery(fun, config, 0, [])
  end
  
  defp execute_with_recovery(fun, config, attempt, errors) do
    try do
      {:ok, fun.()}
    rescue
      exception ->
        error = ErrorContext.from_exception(exception, retry_count: attempt)
        handle_error(error, fun, config, attempt, [error | errors])
    catch
      kind, reason ->
        error = Error.new(:caught, "Caught #{kind}: #{inspect(reason)}", 
          details: %{kind: kind, reason: reason},
          retry_count: attempt
        )
        handle_error(error, fun, config, attempt, [error | errors])
    end
  end
  
  defp handle_error(error, fun, config, attempt, errors) do
    cond do
      not error.recoverable? ->
        {:error, finalize_error(error, errors)}
        
      attempt >= config.max_retries ->
        {:error, finalize_error(
          %{error | type: :max_retries_exceeded},
          errors
        )}
        
      true ->
        apply_recovery_strategy(error, fun, config, attempt, errors)
    end
  end
  
  defp apply_recovery_strategy(error, fun, config, attempt, errors) do
    case config.strategy do
      :retry ->
        delay = calculate_backoff(attempt, config.backoff)
        Process.sleep(delay)
        execute_with_recovery(fun, config, attempt + 1, errors)
        
      :circuit_breaker ->
        handle_circuit_breaker(error, fun, config, attempt, errors)
        
      :fallback ->
        apply_fallback(config.fallback)
        
      :compensate ->
        run_compensation(error, config)
        
      :escalate ->
        escalate_error(error, errors)
        
      :ignore ->
        log_and_continue(error)
    end
  end
  
  defp calculate_backoff(attempt, backoff_config) do
    base_delay = case backoff_config.type do
      :exponential ->
        backoff_config.initial * :math.pow(2, attempt)
      :linear ->
        backoff_config.initial * (attempt + 1)
      :constant ->
        backoff_config.initial
    end
    
    delay = min(base_delay, backoff_config.max) |> round()
    
    if backoff_config.jitter do
      add_jitter(delay)
    else
      delay
    end
  end
  
  defp add_jitter(delay) do
    jitter = :rand.uniform(div(delay, 4))
    delay + jitter - div(delay, 8)
  end
  
  defp default_config do
    %{
      strategy: :retry,
      max_retries: 3,
      backoff: %{
        type: :exponential,
        initial: 100,
        max: 5000,
        jitter: true
      }
    }
  end
end
```

### 2. Circuit Breaker

```elixir
# lib/jido/core/circuit_breaker.ex
defmodule Jido.Core.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for fault tolerance.
  """
  
  use GenServer
  
  @states [:closed, :open, :half_open]
  
  defstruct [
    :name,
    :state,
    :failure_count,
    :success_count,
    :last_failure_time,
    :config,
    :stats
  ]
  
  @default_config %{
    failure_threshold: 5,
    success_threshold: 2,
    timeout: 60_000,  # 1 minute
    reset_timeout: 30_000  # 30 seconds
  }
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Keyword.get(opts, :config, %{}))
    
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      state: :closed,
      failure_count: 0,
      success_count: 0,
      config: config,
      stats: %{
        total_calls: 0,
        total_failures: 0,
        total_successes: 0,
        state_changes: []
      }
    }
    
    {:ok, state}
  end
  
  @doc """
  Execute function through circuit breaker.
  """
  def call(breaker, fun) do
    GenServer.call(breaker, {:call, fun}, 10_000)
  end
  
  @impl GenServer
  def handle_call({:call, fun}, _from, state) do
    case state.state do
      :open ->
        if should_attempt_reset?(state) do
          transition_to_half_open(state, fun)
        else
          {:reply, {:error, :circuit_open}, update_stats(state, :rejected)}
        end
        
      :half_open ->
        execute_half_open(state, fun)
        
      :closed ->
        execute_closed(state, fun)
    end
  end
  
  defp execute_closed(state, fun) do
    case safe_execute(fun) do
      {:ok, result} ->
        new_state = %{state | 
          failure_count: 0,
          success_count: state.success_count + 1
        }
        {:reply, {:ok, result}, update_stats(new_state, :success)}
        
      {:error, error} ->
        new_failure_count = state.failure_count + 1
        
        new_state = if new_failure_count >= state.config.failure_threshold do
          transition_to_open(%{state | 
            failure_count: new_failure_count,
            last_failure_time: System.monotonic_time(:millisecond)
          })
        else
          %{state | failure_count: new_failure_count}
        end
        
        {:reply, {:error, error}, update_stats(new_state, :failure)}
    end
  end
  
  defp execute_half_open(state, fun) do
    case safe_execute(fun) do
      {:ok, result} ->
        new_success_count = state.success_count + 1
        
        new_state = if new_success_count >= state.config.success_threshold do
          transition_to_closed(%{state | success_count: new_success_count})
        else
          %{state | success_count: new_success_count}
        end
        
        {:reply, {:ok, result}, update_stats(new_state, :success)}
        
      {:error, error} ->
        new_state = transition_to_open(%{state | 
          last_failure_time: System.monotonic_time(:millisecond)
        })
        {:reply, {:error, error}, update_stats(new_state, :failure)}
    end
  end
  
  defp safe_execute(fun) do
    try do
      {:ok, fun.()}
    rescue
      exception ->
        {:error, Exception.message(exception)}
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end
  
  defp should_attempt_reset?(state) do
    current_time = System.monotonic_time(:millisecond)
    current_time - state.last_failure_time >= state.config.reset_timeout
  end
  
  defp transition_to_open(state) do
    record_state_change(state, :open)
    %{state | state: :open, failure_count: 0, success_count: 0}
  end
  
  defp transition_to_half_open(state, fun) do
    new_state = %{state | state: :half_open, failure_count: 0, success_count: 0}
    record_state_change(state, :half_open)
    execute_half_open(new_state, fun)
  end
  
  defp transition_to_closed(state) do
    record_state_change(state, :closed)
    %{state | state: :closed, failure_count: 0, success_count: 0}
  end
  
  defp record_state_change(state, new_state) do
    change = %{
      from: state.state,
      to: new_state,
      timestamp: DateTime.utc_now()
    }
    
    updated_stats = %{state.stats | 
      state_changes: [change | state.stats.state_changes]
    }
    
    %{state | stats: updated_stats}
  end
end
```

### 3. Compensation and Rollback

```elixir
# lib/jido/core/compensation.ex
defmodule Jido.Core.Compensation do
  @moduledoc """
  Compensation and rollback mechanisms.
  """
  
  alias Jido.Core.Error
  
  defstruct [
    :id,
    :operations,
    :completed,
    :compensations,
    :state
  ]
  
  @type operation :: {
    id :: term(),
    execute :: fun(),
    compensate :: fun()
  }
  
  @doc """
  Execute operations with automatic compensation on failure.
  """
  def with_compensation(operations) do
    saga = %__MODULE__{
      id: Jido.Core.ID.generate(),
      operations: operations,
      completed: [],
      compensations: [],
      state: :running
    }
    
    execute_saga(saga)
  end
  
  defp execute_saga(%__MODULE__{operations: []} = saga) do
    {:ok, %{saga | state: :completed}}
  end
  
  defp execute_saga(%__MODULE__{operations: [{id, execute, compensate} | rest]} = saga) do
    case safe_execute(execute) do
      {:ok, result} ->
        updated_saga = %{saga | 
          operations: rest,
          completed: [{id, result} | saga.completed],
          compensations: [{id, compensate, result} | saga.compensations]
        }
        execute_saga(updated_saga)
        
      {:error, error} ->
        compensated_saga = run_compensations(%{saga | state: :compensating}, error)
        {:error, error, compensated_saga}
    end
  end
  
  defp run_compensations(%__MODULE__{compensations: []} = saga, original_error) do
    %{saga | state: :compensated}
  end
  
  defp run_compensations(%__MODULE__{compensations: [{id, compensate, result} | rest]} = saga, original_error) do
    case safe_execute(fn -> compensate.(result) end) do
      {:ok, _} ->
        Logger.info("Compensated operation #{id}")
        run_compensations(%{saga | compensations: rest}, original_error)
        
      {:error, comp_error} ->
        Logger.error("Failed to compensate operation #{id}: #{inspect(comp_error)}")
        # Continue compensating even if one fails
        run_compensations(%{saga | compensations: rest}, original_error)
    end
  end
  
  defp safe_execute(fun) do
    try do
      {:ok, fun.()}
    rescue
      exception ->
        {:error, ErrorContext.from_exception(exception)}
    end
  end
  
  @doc """
  Define compensatable action.
  """
  defmacro compensatable(id, do: execute_block, compensate: compensate_block) do
    quote do
      {unquote(id), 
       fn -> unquote(execute_block) end,
       fn result -> unquote(compensate_block) end}
    end
  end
end
```

## Error Reporting and Monitoring

### 1. Error Reporter

```elixir
# lib/jido/error/reporter.ex
defmodule Jido.Error.Reporter do
  @moduledoc """
  Centralized error reporting and monitoring.
  """
  
  use GenServer
  
  alias Jido.Core.Error
  
  defstruct [
    :buffer,
    :config,
    :stats,
    :handlers
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      buffer: [],
      config: Keyword.get(opts, :config, default_config()),
      stats: init_stats(),
      handlers: Keyword.get(opts, :handlers, default_handlers())
    }
    
    # Schedule periodic flush
    schedule_flush(state.config.flush_interval)
    
    {:ok, state}
  end
  
  @doc """
  Report an error.
  """
  def report(%Error{} = error) do
    GenServer.cast(__MODULE__, {:report, error})
  end
  
  @doc """
  Report with additional context.
  """
  def report_with_context(%Error{} = error, context) do
    enriched = %{error | context: Map.merge(error.context, context)}
    report(enriched)
  end
  
  @impl GenServer
  def handle_cast({:report, error}, state) do
    # Update statistics
    new_stats = update_stats(state.stats, error)
    
    # Check if we should handle immediately
    if should_handle_immediately?(error, state.config) do
      handle_error(error, state.handlers)
      {:noreply, %{state | stats: new_stats}}
    else
      # Buffer for batch processing
      new_buffer = [error | state.buffer]
      
      if length(new_buffer) >= state.config.buffer_size do
        flush_buffer(new_buffer, state.handlers)
        {:noreply, %{state | buffer: [], stats: new_stats}}
      else
        {:noreply, %{state | buffer: new_buffer, stats: new_stats}}
      end
    end
  end
  
  @impl GenServer
  def handle_info(:flush, state) do
    if state.buffer != [] do
      flush_buffer(state.buffer, state.handlers)
    end
    
    schedule_flush(state.config.flush_interval)
    {:noreply, %{state | buffer: []}}
  end
  
  defp should_handle_immediately?(error, config) do
    error.severity in [:critical, :fatal] or
    error.type in config.immediate_types
  end
  
  defp handle_error(error, handlers) do
    Enum.each(handlers, fn handler ->
      safe_handle(handler, error)
    end)
  end
  
  defp flush_buffer(errors, handlers) do
    # Group by severity
    grouped = Enum.group_by(errors, & &1.severity)
    
    Enum.each(handlers, fn handler ->
      safe_handle_batch(handler, grouped)
    end)
  end
  
  defp safe_handle(handler, error) do
    try do
      handler.handle(error)
    rescue
      exception ->
        Logger.error("Error handler failed: #{Exception.message(exception)}")
    end
  end
  
  defp default_handlers do
    [
      Jido.Error.LogHandler,
      Jido.Error.TelemetryHandler,
      Jido.Error.AlertHandler
    ]
  end
  
  defp default_config do
    %{
      buffer_size: 100,
      flush_interval: 5_000,
      immediate_types: [:security_breach, :data_corruption, :system_failure]
    }
  end
end
```

### 2. Error Analytics

```elixir
# lib/jido/error/analytics.ex
defmodule Jido.Error.Analytics do
  @moduledoc """
  Error analytics and pattern detection.
  """
  
  use GenServer
  
  defstruct [
    :window_size,
    :errors,
    :patterns,
    :alerts
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      window_size: Keyword.get(opts, :window_size, 300_000),  # 5 minutes
      errors: :queue.new(),
      patterns: %{},
      alerts: []
    }
    
    # Schedule analysis
    schedule_analysis()
    
    {:ok, state}
  end
  
  def track(error) do
    GenServer.cast(__MODULE__, {:track, error})
  end
  
  @impl GenServer
  def handle_cast({:track, error}, state) do
    timestamped = {System.monotonic_time(:millisecond), error}
    new_queue = :queue.in(timestamped, state.errors)
    
    # Remove old errors outside window
    pruned_queue = prune_old_errors(new_queue, state.window_size)
    
    {:noreply, %{state | errors: pruned_queue}}
  end
  
  @impl GenServer
  def handle_info(:analyze, state) do
    patterns = detect_patterns(queue_to_list(state.errors))
    alerts = generate_alerts(patterns, state.patterns)
    
    if alerts != [] do
      send_alerts(alerts)
    end
    
    schedule_analysis()
    {:noreply, %{state | patterns: patterns, alerts: alerts}}
  end
  
  defp detect_patterns(errors) do
    %{
      error_rate: calculate_error_rate(errors),
      top_errors: find_top_errors(errors),
      error_chains: find_error_chains(errors),
      time_patterns: find_time_patterns(errors),
      correlation: find_correlations(errors)
    }
  end
  
  defp find_error_chains(errors) do
    # Detect cascading failures
    errors
    |> Enum.filter(& &1.parent)
    |> Enum.group_by(& &1.parent.type)
    |> Enum.map(fn {parent_type, children} ->
      %{
        parent_type: parent_type,
        child_count: length(children),
        child_types: Enum.frequencies_by(children, & &1.type)
      }
    end)
    |> Enum.sort_by(& &1.child_count, :desc)
  end
  
  defp find_correlations(errors) do
    # Find errors that occur together
    time_windows = chunk_by_time(errors, 1000)  # 1 second windows
    
    time_windows
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.flat_map(&find_pairs/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
  end
  
  defp generate_alerts(current_patterns, previous_patterns) do
    alerts = []
    
    # Spike detection
    if spike_detected?(current_patterns.error_rate, previous_patterns[:error_rate]) do
      alerts = [{:error_spike, current_patterns.error_rate} | alerts]
    end
    
    # New error types
    new_types = MapSet.difference(
      MapSet.new(Map.keys(current_patterns.top_errors)),
      MapSet.new(Map.keys(previous_patterns[:top_errors] || %{}))
    )
    
    if MapSet.size(new_types) > 0 do
      alerts = [{:new_error_types, MapSet.to_list(new_types)} | alerts]
    end
    
    alerts
  end
end
```

## Integration Error Handling

### 1. Agent Error Handling

```elixir
# lib/jido/agent/error_handler.ex
defmodule Jido.Agent.ErrorHandler do
  @moduledoc """
  Agent-specific error handling.
  """
  
  alias Jido.Core.{Error, Recovery}
  alias Jido.Agent.Instance
  
  @doc """
  Handle errors in agent execution with recovery.
  """
  def handle_agent_error(%Instance{} = agent, error, opts \\ []) do
    enriched_error = ErrorContext.with_agent(error, agent)
    
    recovery_strategy = determine_recovery_strategy(enriched_error, agent)
    
    case apply_recovery(agent, enriched_error, recovery_strategy) do
      {:ok, recovered_agent} ->
        log_recovery(enriched_error, recovery_strategy)
        {:ok, recovered_agent}
        
      {:error, recovery_failed} ->
        final_error = Error.chain(enriched_error, recovery_failed)
        Error.Reporter.report(final_error)
        
        if should_terminate?(final_error) do
          {:stop, final_error}
        else
          {:error, final_error, maybe_degraded_agent(agent, final_error)}
        end
    end
  end
  
  defp determine_recovery_strategy(error, agent) do
    cond do
      error.type == :timeout ->
        %{strategy: :retry, max_retries: 1}
        
      error.category == :resource ->
        %{strategy: :circuit_breaker}
        
      error.category == :validation ->
        %{strategy: :fallback, fallback: &validation_fallback/1}
        
      agent_has_error_handler?(agent) ->
        %{strategy: :custom, handler: agent.module}
        
      true ->
        %{strategy: :escalate}
    end
  end
  
  defp apply_recovery(agent, error, %{strategy: :custom, handler: module}) do
    case module.handle_error(agent, error) do
      {:ok, new_agent} -> {:ok, new_agent}
      {:error, _} = err -> err
      other -> {:error, "Invalid error handler response: #{inspect(other)}"}
    end
  end
  
  defp apply_recovery(agent, error, strategy) do
    Recovery.with_recovery(
      fn -> recover_agent(agent, error) end,
      strategy
    )
  end
  
  defp agent_has_error_handler?(agent) do
    function_exported?(agent.module, :handle_error, 2)
  end
  
  defp maybe_degraded_agent(agent, error) do
    if error.severity in [:critical, :fatal] do
      %{agent | 
        state: Map.put(agent.state, :__degraded__, true),
        metadata: Map.put(agent.metadata, :last_error, error)
      }
    else
      agent
    end
  end
end
```

### 2. Signal Error Handling

```elixir
# lib/jido/signal/error_handler.ex
defmodule Jido.Signal.ErrorHandler do
  @moduledoc """
  Signal-specific error handling.
  """
  
  alias Jido.Core.Error
  alias Jido.Signal
  
  @doc """
  Handle signal dispatch errors.
  """
  def handle_dispatch_error(%Signal{} = signal, error, opts \\ []) do
    enriched_error = ErrorContext.with_signal(error, signal)
    
    case determine_fallback(signal, enriched_error) do
      {:retry, config} ->
        retry_dispatch(signal, config)
        
      {:dead_letter, queue} ->
        send_to_dead_letter(signal, enriched_error, queue)
        
      {:compensate, action} ->
        run_compensation(signal, action)
        
      :drop ->
        log_dropped_signal(signal, enriched_error)
        {:error, enriched_error}
    end
  end
  
  defp determine_fallback(signal, error) do
    cond do
      transient_error?(error) ->
        {:retry, %{max_attempts: 3, backoff: :exponential}}
        
      signal.meta[:priority] == :critical ->
        {:dead_letter, :critical_failed_signals}
        
      signal.dispatch[:fallback] ->
        {:compensate, signal.dispatch.fallback}
        
      true ->
        :drop
    end
  end
  
  defp transient_error?(error) do
    error.type in [:network_timeout, :node_down, :process_busy]
  end
  
  defp send_to_dead_letter(signal, error, queue) do
    dead_letter_signal = %{signal | 
      meta: Map.merge(signal.meta || %{}, %{
        dead_letter_queue: queue,
        original_error: Error.to_map(error),
        failed_at: DateTime.utc_now()
      })
    }
    
    Jido.Signal.DeadLetter.enqueue(queue, dead_letter_signal)
  end
end
```

## Testing Error Scenarios

### 1. Error Injection

```elixir
# lib/jido/test/error_injection.ex
defmodule Jido.Test.ErrorInjection do
  @moduledoc """
  Error injection for testing error handling.
  """
  
  def inject(type, opts \\ []) do
    case type do
      :random ->
        inject_random_error(opts)
        
      :cascading ->
        inject_cascading_failure(opts)
        
      :resource_exhaustion ->
        inject_resource_exhaustion(opts)
        
      :network_partition ->
        inject_network_partition(opts)
    end
  end
  
  defp inject_random_error(opts) do
    errors = [
      fn -> raise "Random error" end,
      fn -> {:error, :injected_error} end,
      fn -> exit(:injected_exit) end,
      fn -> throw(:injected_throw) end
    ]
    
    probability = Keyword.get(opts, :probability, 0.1)
    
    if :rand.uniform() < probability do
      Enum.random(errors).()
    end
  end
  
  defp inject_cascading_failure(opts) do
    # Start with one error that triggers others
    initial_error = Error.new(:injection, "Initial injected error")
    
    # Simulate cascade
    Task.start(fn ->
      Process.sleep(Keyword.get(opts, :delay, 100))
      raise "Cascading failure from error injection"
    end)
    
    {:error, initial_error}
  end
end
```

This comprehensive error handling and recovery system ensures the Jido framework can gracefully handle failures, provide clear error reporting, and maintain system stability throughout the migration and beyond.