# 103: Signal Integration Technical Details

## Overview

This document provides comprehensive technical details for integrating the signal system directly into Jido, including module reorganization, API changes, optimization strategies, and handling of complex integration scenarios.

## Module Reorganization Plan

### 1. File System Migration

```bash
#!/bin/bash
# migrate_signals.sh - Complete migration script

set -e  # Exit on error

echo "Starting Jido Signal Integration..."

# Backup existing code
echo "Creating backup..."
cp -r lib lib.backup.$(date +%Y%m%d_%H%M%S)

# Create new directory structure
echo "Creating directory structure..."
mkdir -p lib/jido/signal/{bus,dispatch,router,serialization,journal}

# Module mapping (old -> new)
declare -A MODULE_MAP=(
  ["jido_signal"]="jido/signal"
  ["jido_signal/application"]="jido/signal/application"
  ["jido_signal/bus"]="jido/signal/bus"
  ["jido_signal/dispatch"]="jido/signal/dispatch"
  ["jido_signal/error"]="jido/signal/error"
  ["jido_signal/id"]="jido/signal/id"
  ["jido_signal/router"]="jido/signal/router"
  ["jido_signal/util"]="jido/signal/util"
)

# Copy and update files
for old_path in "${!MODULE_MAP[@]}"; do
  new_path="${MODULE_MAP[$old_path]}"
  echo "Migrating $old_path -> $new_path"
  
  # Copy file
  cp "../jido_signal/lib/${old_path}.ex" "lib/${new_path}.ex"
  
  # Update module names - handled by separate script
done

# Run module name updates
echo "Updating module references..."
elixir scripts/update_signal_modules.exs

echo "Migration complete!"
```

### 2. Module Namespace Updates

```elixir
# scripts/update_signal_modules.exs
defmodule SignalModuleUpdater do
  @moduledoc """
  Updates module namespaces during signal integration.
  """
  
  @namespace_changes [
    # No changes needed - already using Jido.Signal namespace!
    # This is a key insight - the namespaces are already correct
  ]
  
  @import_updates [
    # Update imports that reference jido_signal app
    {~r/Application\.get_env\(:jido_signal/, 
     "Application.get_env(:jido"},
    {~r/Application\.put_env\(:jido_signal/, 
     "Application.put_env(:jido"}
  ]
  
  def run do
    Path.wildcard("lib/jido/signal/**/*.ex")
    |> Enum.each(&update_file/1)
  end
  
  defp update_file(path) do
    content = File.read!(path)
    
    updated = Enum.reduce(@import_updates, content, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
    
    if content != updated do
      File.write!(path, updated)
      IO.puts("Updated: #{path}")
    end
  end
end

SignalModuleUpdater.run()
```

## Signal-Agent Integration Points

### 1. Agent-Aware Signal Creation

```elixir
# lib/jido/signal.ex (enhanced)
defmodule Jido.Signal do
  alias Jido.Agent.Instance
  alias Jido.Instruction
  
  # Agent-specific signal builders
  @agent_signal_prefix "jido.agent"
  
  @doc """
  Creates a signal from an agent context.
  """
  @spec from_agent(Instance.t(), type :: String.t(), data :: map()) :: t()
  def from_agent(%Instance{} = agent, type, data \\ %{}) do
    %__MODULE__{
      id: Jido.Core.ID.generate(),
      type: build_agent_type(type),
      source: build_agent_source(agent),
      time: DateTime.utc_now(),
      data: data,
      meta: %{
        agent_id: agent.id,
        agent_module: inspect(agent.module),
        agent_vsn: agent.__vsn__
      }
    }
  end
  
  @doc """
  Creates a signal from an instruction execution.
  """
  @spec from_instruction(Instruction.t(), Instance.t(), result :: any()) :: t()
  def from_instruction(%Instruction{} = instruction, %Instance{} = agent, result) do
    %__MODULE__{
      id: Jido.Core.ID.generate(),
      type: "#{@agent_signal_prefix}.instruction.completed",
      source: build_agent_source(agent),
      subject: instruction.id,
      time: DateTime.utc_now(),
      data: %{
        instruction_id: instruction.id,
        action: inspect(instruction.action),
        result: result
      },
      meta: %{
        agent_id: agent.id,
        correlation_id: instruction.id
      }
    }
  end
  
  @doc """
  Creates a command signal for an agent.
  """
  @spec command(Instance.t() | String.t(), command :: atom(), params :: map()) :: t()
  def command(agent_or_id, command, params \\ %{})
  
  def command(%Instance{id: agent_id}, command, params) do
    command(agent_id, command, params)
  end
  
  def command(agent_id, command, params) when is_binary(agent_id) do
    %__MODULE__{
      id: Jido.Core.ID.generate(),
      type: "#{@agent_signal_prefix}.cmd.#{command}",
      source: "jido://system",
      subject: agent_id,
      time: DateTime.utc_now(),
      data: params,
      dispatch: {:named, {:via, Registry, {Jido.Registry, agent_id}}}
    }
  end
  
  # Private helpers
  defp build_agent_type(type) when is_binary(type) do
    if String.starts_with?(type, @agent_signal_prefix) do
      type
    else
      "#{@agent_signal_prefix}.#{type}"
    end
  end
  
  defp build_agent_source(%Instance{id: id, module: module}) do
    "jido://agent/#{inspect(module)}/#{id}"
  end
end
```

### 2. Direct Agent Server Integration

```elixir
# lib/jido/agent/server/signal_handler.ex
defmodule Jido.Agent.Server.SignalHandler do
  @moduledoc """
  Optimized signal handling for agent servers.
  """
  
  alias Jido.Agent.{Instance, Server.State}
  alias Jido.Signal
  
  @doc """
  Handles incoming signals with optimized local path.
  """
  @spec handle_signal(Signal.t(), State.t()) :: 
    {:reply, term(), State.t()} | 
    {:noreply, State.t()} |
    {:stop, term(), State.t()}
    
  def handle_signal(%Signal{} = signal, %State{} = state) do
    cond do
      local_signal?(signal, state) ->
        handle_local_signal(signal, state)
        
      command_signal?(signal) ->
        handle_command_signal(signal, state)
        
      event_signal?(signal) ->
        handle_event_signal(signal, state)
        
      true ->
        handle_generic_signal(signal, state)
    end
  end
  
  # Optimized local signal handling - no serialization
  defp handle_local_signal(%Signal{data: %{instruction: instruction}}, state) 
       when is_struct(instruction, Jido.Instruction) do
    # Direct execution without serialization
    case execute_instruction(instruction, state) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}
        
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end
  
  defp handle_local_signal(signal, state) do
    # Fall back to normal handling
    handle_generic_signal(signal, state)
  end
  
  # Command signals modify agent state
  defp handle_command_signal(%Signal{type: type} = signal, state) do
    command = extract_command(type)
    
    case command do
      :run ->
        handle_run_command(signal, state)
        
      :plan ->
        handle_plan_command(signal, state)
        
      :set_state ->
        handle_set_state_command(signal, state)
        
      _ ->
        {:reply, {:error, "Unknown command: #{command}"}, state}
    end
  end
  
  # Event signals are routed to skills/handlers
  defp handle_event_signal(signal, state) do
    results = Enum.map(state.skills, fn {skill_name, skill_state} ->
      skill_module = skill_state.module
      
      if skill_handles_signal?(skill_module, signal) do
        skill_module.handle_signal(signal, state)
      else
        :skip
      end
    end)
    
    # Aggregate results and determine state changes
    process_skill_results(results, signal, state)
  end
  
  # Check if signal originated locally
  defp local_signal?(%Signal{meta: %{node: node}}, _state) do
    node == node()
  end
  
  defp local_signal?(%Signal{source: source}, %State{agent: agent}) do
    source == "jido://agent/#{agent.id}"
  end
  
  defp local_signal?(_, _), do: false
  
  # Extract command from signal type
  defp extract_command(type) do
    case Regex.run(~r/jido\.agent\.cmd\.(\w+)/, type) do
      [_, command] -> String.to_atom(command)
      _ -> nil
    end
  end
end
```

### 3. Signal Bus Integration

```elixir
# lib/jido/signal/bus/agent_integration.ex
defmodule Jido.Signal.Bus.AgentIntegration do
  @moduledoc """
  Agent-specific enhancements to the signal bus.
  """
  
  alias Jido.Signal.Bus
  alias Jido.Agent.Instance
  
  @doc """
  Subscribe an agent to signals matching patterns.
  """
  @spec subscribe_agent(GenServer.server(), Instance.t(), [String.t()]) :: 
    {:ok, subscription_id :: String.t()} | {:error, term()}
    
  def subscribe_agent(bus, %Instance{} = agent, patterns) do
    # Build agent-specific dispatch config
    dispatch_config = {:named, {:via, Registry, {Jido.Registry, agent.id}}}
    
    # Subscribe with agent metadata
    Bus.subscribe(bus, patterns, dispatch_config, %{
      subscriber_type: :agent,
      agent_id: agent.id,
      agent_module: inspect(agent.module)
    })
  end
  
  @doc """
  Publish a signal from an agent with routing hints.
  """
  @spec publish_from_agent(GenServer.server(), Instance.t(), Signal.t()) :: 
    :ok | {:error, term()}
    
  def publish_from_agent(bus, %Instance{} = agent, signal) do
    # Enhance signal with agent context
    enhanced_signal = %{signal | 
      source: "jido://agent/#{agent.id}",
      meta: Map.merge(signal.meta || %{}, %{
        publisher_type: :agent,
        agent_id: agent.id,
        published_at: DateTime.utc_now()
      })
    }
    
    Bus.publish(bus, enhanced_signal)
  end
  
  @doc """
  Create agent-specific routing rules.
  """
  @spec agent_routes(Instance.t()) :: [Bus.route_spec()]
  def agent_routes(%Instance{} = agent) do
    [
      # Route commands to this agent
      {"jido.agent.cmd.#", {:agent, agent.id}, priority: 100},
      
      # Route agent-specific events
      {"jido.agent.#{agent.id}.#", {:agent, agent.id}, priority: 90},
      
      # Route by agent type
      {"jido.agent.type.#{agent.module}.#", {:agent, agent.id}, priority: 80}
    ]
  end
end
```

## Optimization Strategies

### 1. Local Signal Fast Path

```elixir
# lib/jido/signal/dispatch/local_optimizer.ex
defmodule Jido.Signal.Dispatch.LocalOptimizer do
  @moduledoc """
  Optimizes local signal dispatch to avoid serialization.
  """
  
  @behaviour Jido.Signal.Dispatch.Adapter
  
  @impl true
  def validate_opts(opts) do
    with {:ok, target} <- Keyword.fetch(opts, :target),
         true <- local_target?(target) do
      :ok
    else
      :error -> {:error, "Missing :target option"}
      false -> {:error, "Target is not local"}
    end
  end
  
  @impl true
  def deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    
    case local_deliver(signal, target) do
      :ok -> :ok
      {:error, :not_local} -> fallback_deliver(signal, opts)
      error -> error
    end
  end
  
  # Direct in-memory delivery for local targets
  defp local_deliver(signal, {:pid, pid}) when node(pid) == node() do
    # Skip serialization completely
    send(pid, {:signal_direct, signal})
    :ok
  end
  
  defp local_deliver(signal, {:via, Registry, {Jido.Registry, name}}) do
    case Registry.lookup(Jido.Registry, name) do
      [{pid, _}] when node(pid) == node() ->
        send(pid, {:signal_direct, signal})
        :ok
        
      _ ->
        {:error, :not_local}
    end
  end
  
  defp local_deliver(_, _), do: {:error, :not_local}
  
  # Fallback to normal dispatch for remote targets
  defp fallback_deliver(signal, opts) do
    adapter = Keyword.get(opts, :fallback_adapter, :pid)
    adapter_module = Jido.Signal.Dispatch.adapter_for(adapter)
    adapter_module.deliver(signal, opts)
  end
end
```

### 2. Signal Pooling and Batching

```elixir
# lib/jido/signal/pool.ex
defmodule Jido.Signal.Pool do
  @moduledoc """
  Pools and batches signals for efficient processing.
  """
  
  use GenServer
  
  defstruct [
    :buffer,
    :buffer_size,
    :flush_interval,
    :flush_timer,
    :dispatcher
  ]
  
  @default_buffer_size 100
  @default_flush_interval 50  # ms
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      buffer: [],
      buffer_size: Keyword.get(opts, :buffer_size, @default_buffer_size),
      flush_interval: Keyword.get(opts, :flush_interval, @default_flush_interval),
      dispatcher: Keyword.fetch!(opts, :dispatcher)
    }
    
    {:ok, schedule_flush(state)}
  end
  
  def add(signal) do
    GenServer.cast(__MODULE__, {:add, signal})
  end
  
  @impl GenServer
  def handle_cast({:add, signal}, state) do
    new_buffer = [signal | state.buffer]
    
    if length(new_buffer) >= state.buffer_size do
      flush_buffer(new_buffer, state.dispatcher)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end
  
  @impl GenServer
  def handle_info(:flush, state) do
    if state.buffer != [] do
      flush_buffer(state.buffer, state.dispatcher)
    end
    
    {:noreply, schedule_flush(%{state | buffer: []})}
  end
  
  defp flush_buffer(buffer, dispatcher) do
    # Group signals by destination for efficient dispatch
    buffer
    |> Enum.reverse()  # Maintain order
    |> Enum.group_by(&get_dispatch_key/1)
    |> Enum.each(fn {key, signals} ->
      dispatcher.dispatch_batch(signals, key)
    end)
  end
  
  defp get_dispatch_key(%{dispatch: dispatch}), do: dispatch
  defp get_dispatch_key(%{meta: %{agent_id: id}}), do: {:agent, id}
  defp get_dispatch_key(_), do: :default
  
  defp schedule_flush(state) do
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)
    timer = Process.send_after(self(), :flush, state.flush_interval)
    %{state | flush_timer: timer}
  end
end
```

### 3. Zero-Copy Signal Routing

```elixir
# lib/jido/signal/router/zero_copy.ex
defmodule Jido.Signal.Router.ZeroCopy do
  @moduledoc """
  Implements zero-copy routing for signals.
  """
  
  use GenServer
  
  # Use ETS for zero-copy reads
  @table_name :jido_signal_routes
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(_opts) do
    # Create ETS table with read concurrency
    table = :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    {:ok, %{table: table}}
  end
  
  @doc """
  Add a route without copying data.
  """
  def add_route(pattern, handler, opts \\ []) do
    key = pattern_to_key(pattern)
    value = {handler, opts}
    
    # Direct ETS write - no copying
    :ets.insert(@table_name, {key, value})
    :ok
  end
  
  @doc """
  Route a signal without copying.
  Returns handlers as references.
  """
  def route(signal_type) when is_binary(signal_type) do
    # Build lookup keys from most to least specific
    keys = build_lookup_keys(signal_type)
    
    # Direct ETS lookups - no GenServer call
    handlers = keys
    |> Enum.flat_map(&:ets.lookup(@table_name, &1))
    |> Enum.map(fn {_key, value} -> value end)
    |> Enum.sort_by(fn {_handler, opts} -> 
      Keyword.get(opts, :priority, 0) 
    end, :desc)
    
    {:ok, handlers}
  end
  
  defp pattern_to_key(pattern) do
    pattern
    |> String.split(".")
    |> Enum.map(fn
      "#" -> :wildcard
      "*" -> :single
      segment -> segment
    end)
  end
  
  defp build_lookup_keys(signal_type) do
    segments = String.split(signal_type, ".")
    
    # Generate all matching patterns
    length = length(segments)
    
    for i <- 0..length,
        j <- i..length do
      prefix = Enum.take(segments, i)
      suffix_length = j - i
      
      if suffix_length == 0 do
        prefix
      else
        wildcards = List.duplicate(:wildcard, suffix_length)
        prefix ++ wildcards
      end
    end
    |> Enum.uniq()
  end
end
```

## Complex Integration Scenarios

### 1. Distributed Signal Routing

```elixir
# lib/jido/signal/distributed.ex
defmodule Jido.Signal.Distributed do
  @moduledoc """
  Handles distributed signal routing across nodes.
  """
  
  alias Jido.Signal
  alias Jido.Signal.Dispatch
  
  @doc """
  Routes signals across distributed nodes.
  """
  def route_to_node(signal, target_node, target_id) do
    cond do
      node() == target_node ->
        # Local delivery
        local_deliver(signal, target_id)
        
      Node.ping(target_node) == :pong ->
        # Remote node is alive
        remote_deliver(signal, target_node, target_id)
        
      true ->
        # Node unreachable - use fallback
        fallback_deliver(signal, target_node, target_id)
    end
  end
  
  defp local_deliver(signal, target_id) do
    case Jido.Agent.Server.whereis(target_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:signal, signal})
        
      {:error, :not_found} ->
        {:error, "Agent #{target_id} not found locally"}
    end
  end
  
  defp remote_deliver(signal, target_node, target_id) do
    # Use Erlang distribution for efficiency
    :rpc.cast(target_node, Jido.Agent.Server, :deliver_signal, [target_id, signal])
  end
  
  defp fallback_deliver(signal, target_node, target_id) do
    # Store for later delivery when node comes back
    Jido.Signal.Journal.append(%{
      signal: signal,
      target_node: target_node,
      target_id: target_id,
      attempted_at: DateTime.utc_now(),
      status: :pending_delivery
    })
  end
end
```

### 2. Signal Transaction Support

```elixir
# lib/jido/signal/transaction.ex
defmodule Jido.Signal.Transaction do
  @moduledoc """
  Provides transactional guarantees for signal operations.
  """
  
  use GenServer
  
  defstruct [:id, :signals, :status, :participants, :timeout]
  
  @doc """
  Begins a distributed signal transaction.
  """
  def begin(opts \\ []) do
    transaction = %__MODULE__{
      id: Jido.Core.ID.generate(),
      signals: [],
      status: :active,
      participants: [],
      timeout: Keyword.get(opts, :timeout, 5000)
    }
    
    {:ok, pid} = GenServer.start(__MODULE__, transaction)
    {:ok, transaction.id, pid}
  end
  
  @doc """
  Adds a signal to the transaction.
  """
  def add_signal(tx_pid, signal) do
    GenServer.call(tx_pid, {:add_signal, signal})
  end
  
  @doc """
  Commits all signals atomically.
  """
  def commit(tx_pid) do
    GenServer.call(tx_pid, :commit, 10_000)
  end
  
  @doc """
  Rolls back the transaction.
  """
  def rollback(tx_pid) do
    GenServer.call(tx_pid, :rollback)
  end
  
  @impl GenServer
  def handle_call({:add_signal, signal}, _from, state) do
    if state.status == :active do
      new_state = %{state | signals: [signal | state.signals]}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :transaction_not_active}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:commit, _from, state) do
    case two_phase_commit(state) do
      :ok ->
        {:reply, :ok, %{state | status: :committed}}
        
      {:error, reason} ->
        # Rollback on failure
        rollback_all(state)
        {:reply, {:error, reason}, %{state | status: :aborted}}
    end
  end
  
  # Two-phase commit protocol
  defp two_phase_commit(state) do
    # Phase 1: Prepare
    prepare_results = Enum.map(state.participants, fn participant ->
      GenServer.call(participant, {:prepare, state.id}, state.timeout)
    end)
    
    if Enum.all?(prepare_results, &(&1 == :prepared)) do
      # Phase 2: Commit
      Enum.each(state.participants, fn participant ->
        GenServer.cast(participant, {:commit, state.id})
      end)
      
      # Dispatch all signals
      Enum.each(state.signals, &Jido.Signal.Dispatch.dispatch/1)
      :ok
    else
      {:error, :prepare_failed}
    end
  end
  
  defp rollback_all(state) do
    Enum.each(state.participants, fn participant ->
      GenServer.cast(participant, {:rollback, state.id})
    end)
  end
end
```

### 3. Signal Priority and QoS

```elixir
# lib/jido/signal/qos.ex
defmodule Jido.Signal.QoS do
  @moduledoc """
  Quality of Service for signal delivery.
  """
  
  use GenServer
  
  @priorities [:low, :normal, :high, :critical]
  @default_priority :normal
  
  defstruct [
    queues: %{},
    workers: %{},
    config: %{}
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    # Initialize priority queues
    queues = Map.new(@priorities, fn priority ->
      {priority, :queue.new()}
    end)
    
    # Start workers for each priority
    workers = start_priority_workers(opts)
    
    state = %__MODULE__{
      queues: queues,
      workers: workers,
      config: opts
    }
    
    {:ok, state}
  end
  
  @doc """
  Enqueues a signal with priority.
  """
  def enqueue(signal, priority \\ @default_priority) do
    GenServer.cast(__MODULE__, {:enqueue, signal, priority})
  end
  
  @impl GenServer
  def handle_cast({:enqueue, signal, priority}, state) do
    queue = Map.get(state.queues, priority)
    new_queue = :queue.in(signal, queue)
    new_queues = Map.put(state.queues, priority, new_queue)
    
    # Notify worker
    notify_worker(state.workers[priority])
    
    {:noreply, %{state | queues: new_queues}}
  end
  
  @impl GenServer
  def handle_call({:dequeue, priority}, _from, state) do
    queue = Map.get(state.queues, priority)
    
    case :queue.out(queue) do
      {{:value, signal}, new_queue} ->
        new_queues = Map.put(state.queues, priority, new_queue)
        {:reply, {:ok, signal}, %{state | queues: new_queues}}
        
      {:empty, _} ->
        {:reply, :empty, state}
    end
  end
  
  defp start_priority_workers(config) do
    Map.new(@priorities, fn priority ->
      worker_count = get_worker_count(priority, config)
      workers = for i <- 1..worker_count do
        {:ok, pid} = QoSWorker.start_link(priority: priority, qos: self())
        pid
      end
      {priority, workers}
    end)
  end
  
  defp get_worker_count(:critical, _), do: 4
  defp get_worker_count(:high, _), do: 2
  defp get_worker_count(:normal, _), do: 1
  defp get_worker_count(:low, _), do: 1
  
  defp notify_worker(workers) do
    # Round-robin notification
    worker = Enum.random(workers)
    send(worker, :process_signal)
  end
end
```

## Performance Considerations

### 1. Memory Management

```elixir
# lib/jido/signal/memory.ex
defmodule Jido.Signal.Memory do
  @moduledoc """
  Memory-efficient signal handling.
  """
  
  # Use binary references for large payloads
  def optimize_signal(%Signal{data: data} = signal) when is_binary(data) and byte_size(data) > 64_000 do
    # Store large data externally
    ref = store_large_data(data)
    %{signal | data: {:binary_ref, ref}}
  end
  
  def optimize_signal(signal), do: signal
  
  # Implement copy-on-write for signal data
  def cow_update(signal, path, value) do
    new_data = put_in(signal.data, path, value)
    
    if identical?(signal.data, new_data) do
      signal
    else
      %{signal | data: new_data}
    end
  end
  
  defp identical?(a, b), do: :erts_debug.same(a, b)
end
```

### 2. CPU Optimization

```elixir
# lib/jido/signal/cpu_optimizer.ex
defmodule Jido.Signal.CPUOptimizer do
  @moduledoc """
  CPU-efficient signal processing.
  """
  
  # Compile patterns at module load time
  @type_patterns %{
    command: ~r/^jido\.agent\.cmd\.(.+)$/,
    event: ~r/^jido\.agent\.event\.(.+)$/,
    system: ~r/^jido\.system\.(.+)$/
  }
  
  for {type, pattern} <- @type_patterns do
    def match_type(unquote(to_string(type)), signal_type) do
      Regex.match?(unquote(Macro.escape(pattern)), signal_type)
    end
  end
  
  def match_type(_, _), do: false
  
  # Use NIFs for hot paths
  def fast_route(signal_type) do
    :jido_signal_nif.route(signal_type)
  rescue
    UndefinedFunctionError ->
      # Fallback to Elixir implementation
      Jido.Signal.Router.route(signal_type)
  end
end
```

This comprehensive technical specification provides all the details needed for integrating the signal system into Jido while maintaining performance and functionality.