# 108: Distributed System Considerations

## Overview

This document addresses the distributed system aspects of the Jido framework reintegration, covering node communication, distributed state management, network partitions, consensus mechanisms, and ensuring the framework works seamlessly across multiple nodes.

## Distributed Architecture

### 1. Node Topology Management

```elixir
# lib/jido/distributed/topology.ex
defmodule Jido.Distributed.Topology do
  @moduledoc """
  Manages distributed node topology and membership.
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :cluster_name,
    :nodes,
    :node_states,
    :partitions,
    :view_number,
    :leader,
    :config
  ]
  
  @type node_state :: :active | :suspected | :failed | :leaving
  @type node_info :: %{
    id: node(),
    state: node_state(),
    last_seen: DateTime.t(),
    metadata: map()
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      node_id: node(),
      cluster_name: Keyword.get(opts, :cluster_name, "jido_cluster"),
      nodes: MapSet.new([node()]),
      node_states: %{node() => build_node_info(:active)},
      partitions: %{},
      view_number: 0,
      leader: nil,
      config: build_config(opts)
    }
    
    # Start topology management
    schedule_heartbeat()
    schedule_failure_detection()
    
    # Join cluster
    join_cluster(state)
    
    {:ok, state}
  end
  
  @doc """
  Get current cluster view.
  """
  def get_view do
    GenServer.call(__MODULE__, :get_view)
  end
  
  @doc """
  Check if node is reachable.
  """
  def reachable?(target_node) do
    GenServer.call(__MODULE__, {:reachable?, target_node})
  end
  
  @impl GenServer
  def handle_info(:heartbeat, state) do
    # Send heartbeats to all known nodes
    active_nodes = get_active_nodes(state)
    
    Enum.each(active_nodes -- [node()], fn target ->
      send_heartbeat(target, state)
    end)
    
    schedule_heartbeat()
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(:failure_detection, state) do
    # Check for failed nodes
    now = DateTime.utc_now()
    timeout = state.config.failure_timeout
    
    suspected_nodes = Enum.filter(state.node_states, fn {node, info} ->
      node != node() and
      info.state == :active and
      DateTime.diff(now, info.last_seen, :millisecond) > timeout
    end)
    
    new_state = Enum.reduce(suspected_nodes, state, fn {node, _}, acc ->
      mark_node_suspected(acc, node)
    end)
    
    # Check for nodes to mark as failed
    failed_nodes = Enum.filter(new_state.node_states, fn {node, info} ->
      info.state == :suspected and
      DateTime.diff(now, info.last_seen, :millisecond) > timeout * 3
    end)
    
    final_state = Enum.reduce(failed_nodes, new_state, fn {node, _}, acc ->
      mark_node_failed(acc, node)
    end)
    
    schedule_failure_detection()
    {:noreply, maybe_elect_leader(final_state)}
  end
  
  @impl GenServer
  def handle_cast({:heartbeat, from_node, view_number}, state) do
    if view_number >= state.view_number do
      new_state = update_node_seen(state, from_node, :active)
      {:noreply, new_state}
    else
      # Outdated view, send our view
      send_view_update(from_node, state)
      {:noreply, state}
    end
  end
  
  defp build_config(opts) do
    %{
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, 1000),
      failure_timeout: Keyword.get(opts, :failure_timeout, 5000),
      gossip_fanout: Keyword.get(opts, :gossip_fanout, 3),
      partition_strategy: Keyword.get(opts, :partition_strategy, :optimistic)
    }
  end
  
  defp maybe_elect_leader(state) do
    active_nodes = get_active_nodes(state)
    
    cond do
      state.leader in active_nodes ->
        state
        
      active_nodes == [] ->
        %{state | leader: nil}
        
      true ->
        # Simple leader election: lowest node ID
        new_leader = Enum.min(active_nodes)
        broadcast_leader_change(state, new_leader)
        %{state | leader: new_leader, view_number: state.view_number + 1}
    end
  end
  
  defp join_cluster(state) do
    # Discover other nodes via various strategies
    discovered = discover_nodes(state.cluster_name)
    
    Enum.each(discovered, fn node ->
      :net_kernel.connect_node(node)
      send({__MODULE__, node}, {:join, node(), state.view_number})
    end)
  end
  
  defp discover_nodes(cluster_name) do
    # Multiple discovery strategies
    strategies = [
      &discover_via_epmd/1,
      &discover_via_dns/1,
      &discover_via_kubernetes/1
    ]
    
    strategies
    |> Enum.flat_map(& &1.(cluster_name))
    |> Enum.uniq()
    |> Enum.reject(&(&1 == node()))
  end
end
```

### 2. Distributed Agent Registry

```elixir
# lib/jido/distributed/agent_registry.ex
defmodule Jido.Distributed.AgentRegistry do
  @moduledoc """
  Distributed registry for agents across nodes.
  """
  
  use GenServer
  
  defstruct [
    :registry,
    :replicas,
    :partitions,
    :ring,
    :config
  ]
  
  @hash_ring_size 1024
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      registry: %{},
      replicas: Keyword.get(opts, :replicas, 3),
      partitions: initialize_partitions(),
      ring: build_hash_ring([node()]),
      config: opts
    }
    
    # Subscribe to topology changes
    Jido.Distributed.Topology.subscribe(self())
    
    {:ok, state}
  end
  
  @doc """
  Register an agent globally.
  """
  def register(agent_id, agent_pid, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, agent_id, agent_pid, metadata})
  end
  
  @doc """
  Lookup agent by ID.
  """
  def lookup(agent_id) do
    primary_node = get_primary_node(agent_id)
    
    if primary_node == node() do
      # Local lookup
      GenServer.call(__MODULE__, {:lookup_local, agent_id})
    else
      # Remote lookup with fallback
      case remote_lookup(primary_node, agent_id) do
        {:ok, result} -> {:ok, result}
        {:error, :node_down} -> lookup_from_replicas(agent_id)
      end
    end
  end
  
  @doc """
  Get all agents on a specific node.
  """
  def agents_on_node(target_node \\ node()) do
    if target_node == node() do
      GenServer.call(__MODULE__, :list_local)
    else
      remote_call(target_node, :list_local)
    end
  end
  
  @impl GenServer
  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    # Determine nodes for replication
    nodes = get_replica_nodes(agent_id, state)
    
    if node() in nodes do
      # Register locally
      new_registry = Map.put(state.registry, agent_id, %{
        pid: pid,
        metadata: metadata,
        registered_at: DateTime.utc_now(),
        node: node(pid)
      })
      
      # Replicate to other nodes
      other_nodes = nodes -- [node()]
      replicate_registration(agent_id, pid, metadata, other_nodes)
      
      {:reply, :ok, %{state | registry: new_registry}}
    else
      # Forward to primary node
      primary = hd(nodes)
      result = remote_register(primary, agent_id, pid, metadata)
      {:reply, result, state}
    end
  end
  
  @impl GenServer
  def handle_call({:lookup_local, agent_id}, _from, state) do
    case Map.get(state.registry, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end
  
  @impl GenServer
  def handle_info({:topology_change, change}, state) do
    new_state = handle_topology_change(change, state)
    {:noreply, new_state}
  end
  
  defp get_primary_node(agent_id) do
    hash = :erlang.phash2(agent_id, @hash_ring_size)
    get_node_for_hash(hash)
  end
  
  defp get_replica_nodes(agent_id, state) do
    primary = get_primary_node(agent_id)
    all_nodes = Jido.Distributed.Topology.get_active_nodes()
    
    # Get N replicas including primary
    if length(all_nodes) <= state.replicas do
      all_nodes
    else
      # Consistent hashing for replica selection
      start_index = Enum.find_index(all_nodes, &(&1 == primary))
      
      Enum.take(
        Stream.cycle(all_nodes),
        state.replicas
      )
      |> Enum.drop(start_index)
      |> Enum.take(state.replicas)
    end
  end
  
  defp handle_topology_change(%{type: :node_added, node: new_node}, state) do
    # Rebuild hash ring
    new_ring = build_hash_ring(Jido.Distributed.Topology.get_active_nodes())
    
    # Rebalance agents
    agents_to_move = calculate_rebalance(state.registry, state.ring, new_ring)
    
    Enum.each(agents_to_move, fn {agent_id, _info} ->
      maybe_transfer_agent(agent_id, new_ring)
    end)
    
    %{state | ring: new_ring}
  end
  
  defp handle_topology_change(%{type: :node_removed, node: failed_node}, state) do
    # Remove failed node from ring
    new_ring = build_hash_ring(
      Jido.Distributed.Topology.get_active_nodes() -- [failed_node]
    )
    
    # Re-register agents that were on failed node
    failed_agents = Enum.filter(state.registry, fn {_id, info} ->
      info.node == failed_node
    end)
    
    Enum.each(failed_agents, fn {agent_id, info} ->
      # Try to recover agent on new primary
      recover_agent(agent_id, info, new_ring)
    end)
    
    %{state | ring: new_ring}
  end
  
  defp recover_agent(agent_id, info, ring) do
    new_primary = get_node_for_agent(agent_id, ring)
    
    if new_primary == node() do
      # We're the new primary, try to recover
      case Jido.Agent.Supervisor.recover_agent(agent_id, info.metadata) do
        {:ok, new_pid} ->
          Logger.info("Recovered agent #{agent_id} on #{node()}")
          
        {:error, reason} ->
          Logger.error("Failed to recover agent #{agent_id}: #{inspect(reason)}")
      end
    end
  end
end
```

### 3. Distributed Signal Routing

```elixir
# lib/jido/distributed/signal_router.ex
defmodule Jido.Distributed.SignalRouter do
  @moduledoc """
  Routes signals across distributed nodes.
  """
  
  alias Jido.Signal
  alias Jido.Distributed.{Topology, AgentRegistry}
  
  @doc """
  Route signal to appropriate node(s).
  """
  def route(%Signal{} = signal) do
    case determine_routing(signal) do
      {:local, target} ->
        route_local(signal, target)
        
      {:remote, node, target} ->
        route_remote(signal, node, target)
        
      {:broadcast, nodes} ->
        route_broadcast(signal, nodes)
        
      {:partition, strategy} ->
        handle_partition(signal, strategy)
    end
  end
  
  defp determine_routing(%Signal{dispatch: dispatch} = signal) do
    case dispatch do
      {:agent, agent_id} ->
        route_to_agent(agent_id)
        
      {:broadcast, pattern} ->
        nodes = find_nodes_with_pattern(pattern)
        {:broadcast, nodes}
        
      {:node, target_node, target} ->
        {:remote, target_node, target}
        
      local_target ->
        {:local, local_target}
    end
  end
  
  defp route_to_agent(agent_id) do
    case AgentRegistry.lookup(agent_id) do
      {:ok, %{node: agent_node, pid: pid}} when agent_node == node() ->
        {:local, pid}
        
      {:ok, %{node: agent_node, pid: pid}} ->
        {:remote, agent_node, pid}
        
      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end
  
  defp route_local(signal, target) do
    case target do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          send(pid, {:signal, signal})
          :ok
        else
          {:error, :process_dead}
        end
        
      name when is_atom(name) ->
        case Process.whereis(name) do
          nil -> {:error, :process_not_found}
          pid -> route_local(signal, pid)
        end
    end
  end
  
  defp route_remote(signal, target_node, target) do
    if Topology.reachable?(target_node) do
      # Use Erlang distribution
      :rpc.cast(target_node, __MODULE__, :deliver_local, [signal, target])
      :ok
    else
      # Node unreachable - use fallback
      handle_unreachable_node(signal, target_node, target)
    end
  end
  
  defp route_broadcast(signal, nodes) do
    # Efficient broadcast using tree topology
    broadcast_tree(signal, nodes, [])
  end
  
  defp broadcast_tree(signal, nodes, visited) do
    # Calculate fanout for this node
    remaining = nodes -- visited -- [node()]
    fanout = min(3, length(remaining))  # Max 3 children
    
    if fanout > 0 do
      children = Enum.take(remaining, fanout)
      rest = remaining -- children
      
      # Send to children with rest of nodes
      Enum.each(children, fn child_node ->
        child_targets = Enum.filter(rest, fn n ->
          closer_to?(n, child_node, node())
        end)
        
        :rpc.cast(
          child_node,
          __MODULE__,
          :continue_broadcast,
          [signal, child_targets, [node() | visited]]
        )
      end)
    end
    
    # Deliver locally
    deliver_broadcast_local(signal)
  end
  
  defp handle_unreachable_node(signal, target_node, target) do
    # Store for later delivery
    Jido.Distributed.SignalBuffer.buffer(signal, target_node, target)
    
    # Try alternate routes
    case find_alternate_route(target_node) do
      {:ok, alt_node} ->
        route_remote(signal, alt_node, target)
        
      :error ->
        {:error, :no_route}
    end
  end
  
  def deliver_local(signal, target) do
    route_local(signal, target)
  end
  
  def continue_broadcast(signal, nodes, visited) do
    broadcast_tree(signal, nodes, visited)
  end
end
```

### 4. Distributed State Synchronization

```elixir
# lib/jido/distributed/state_sync.ex
defmodule Jido.Distributed.StateSync do
  @moduledoc """
  Synchronizes agent state across distributed nodes.
  """
  
  use GenServer
  
  defstruct [
    :sync_strategy,
    :vector_clocks,
    :pending_syncs,
    :conflict_resolver,
    :config
  ]
  
  @type sync_strategy :: :eventual | :causal | :strong
  @type vector_clock :: %{node() => non_neg_integer()}
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      sync_strategy: Keyword.get(opts, :strategy, :causal),
      vector_clocks: %{},
      pending_syncs: %{},
      conflict_resolver: Keyword.get(opts, :conflict_resolver, &default_resolver/2),
      config: build_config(opts)
    }
    
    schedule_sync()
    {:ok, state}
  end
  
  @doc """
  Update agent state with synchronization.
  """
  def update_state(agent_id, state_update, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update, agent_id, state_update, metadata})
  end
  
  @doc """
  Get synchronized state for agent.
  """
  def get_state(agent_id) do
    GenServer.call(__MODULE__, {:get_state, agent_id})
  end
  
  @impl GenServer
  def handle_call({:update, agent_id, update, metadata}, _from, state) do
    # Update vector clock
    clock = increment_clock(get_clock(state, agent_id))
    
    # Create update record
    update_record = %{
      agent_id: agent_id,
      update: update,
      clock: clock,
      node: node(),
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
    
    # Apply locally
    new_state = apply_update(state, update_record)
    
    # Schedule replication based on strategy
    schedule_replication(update_record, state.sync_strategy)
    
    {:reply, {:ok, clock}, new_state}
  end
  
  @impl GenServer
  def handle_info(:sync, state) do
    # Perform periodic synchronization
    active_nodes = Jido.Distributed.Topology.get_active_nodes() -- [node()]
    
    # Anti-entropy: exchange state with random nodes
    sync_nodes = Enum.take_random(active_nodes, state.config.sync_fanout)
    
    Enum.each(sync_nodes, fn target_node ->
      sync_with_node(target_node, state)
    end)
    
    schedule_sync()
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_cast({:sync_request, from_node, their_clocks}, state) do
    # Compare vector clocks and send missing updates
    missing_updates = find_missing_updates(state, their_clocks)
    
    if missing_updates != [] do
      send({__MODULE__, from_node}, {:sync_response, node(), missing_updates})
    end
    
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info({:sync_response, from_node, updates}, state) do
    # Apply received updates
    new_state = Enum.reduce(updates, state, fn update, acc ->
      maybe_apply_remote_update(acc, update)
    end)
    
    {:noreply, new_state}
  end
  
  defp increment_clock(clock) do
    Map.update(clock, node(), 1, &(&1 + 1))
  end
  
  defp apply_update(state, update_record) do
    agent_id = update_record.agent_id
    
    # Update vector clock
    new_clocks = Map.put(state.vector_clocks, agent_id, update_record.clock)
    
    # Store update
    updates = Map.get(state.pending_syncs, agent_id, [])
    new_updates = [update_record | updates] |> Enum.take(state.config.max_history)
    
    %{state |
      vector_clocks: new_clocks,
      pending_syncs: Map.put(state.pending_syncs, agent_id, new_updates)
    }
  end
  
  defp maybe_apply_remote_update(state, update) do
    agent_id = update.agent_id
    current_clock = get_clock(state, agent_id)
    
    case compare_clocks(update.clock, current_clock) do
      :newer ->
        # Update is newer, apply it
        apply_update(state, update)
        
      :older ->
        # Our state is newer, ignore
        state
        
      :concurrent ->
        # Concurrent updates - resolve conflict
        resolve_conflict(state, agent_id, update)
    end
  end
  
  defp compare_clocks(clock1, clock2) do
    cond do
      clock_less_than?(clock1, clock2) -> :older
      clock_less_than?(clock2, clock1) -> :newer
      true -> :concurrent
    end
  end
  
  defp clock_less_than?(clock1, clock2) do
    Enum.all?(clock1, fn {node, value} ->
      Map.get(clock2, node, 0) >= value
    end) and clock1 != clock2
  end
  
  defp resolve_conflict(state, agent_id, remote_update) do
    local_updates = Map.get(state.pending_syncs, agent_id, [])
    
    # Find concurrent local update
    local_update = Enum.find(local_updates, fn update ->
      compare_clocks(update.clock, remote_update.clock) == :concurrent
    end)
    
    if local_update do
      # Use conflict resolver
      resolved = state.conflict_resolver.(local_update, remote_update)
      apply_update(state, resolved)
    else
      apply_update(state, remote_update)
    end
  end
  
  defp default_resolver(update1, update2) do
    # Last-write-wins with node ID as tiebreaker
    if update1.timestamp > update2.timestamp do
      update1
    elsif update2.timestamp > update1.timestamp do
      update2
    elsif update1.node > update2.node do
      update1
    else
      update2
    end
  end
  
  defp schedule_replication(update, :strong) do
    # Synchronous replication to all nodes
    nodes = Jido.Distributed.Topology.get_active_nodes() -- [node()]
    
    tasks = Enum.map(nodes, fn target ->
      Task.async(fn ->
        replicate_to_node(target, update)
      end)
    end)
    
    Task.await_many(tasks, 5000)
  end
  
  defp schedule_replication(update, :causal) do
    # Asynchronous causal replication
    Task.start(fn ->
      replicate_causally(update)
    end)
  end
  
  defp schedule_replication(_update, :eventual) do
    # Will be handled by periodic sync
    :ok
  end
end
```

### 5. Network Partition Handling

```elixir
# lib/jido/distributed/partition_handler.ex
defmodule Jido.Distributed.PartitionHandler do
  @moduledoc """
  Handles network partitions and split-brain scenarios.
  """
  
  use GenServer
  
  defstruct [
    :partition_strategy,
    :quorum_size,
    :current_partition,
    :partition_history,
    :merge_strategy
  ]
  
  @type partition_strategy :: 
    :static_quorum |      # Require fixed quorum
    :dynamic_quorum |     # Adjust quorum based on cluster size
    :primary_partition |  # Designate primary partition
    :optimistic           # Allow all partitions to operate
    
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      partition_strategy: Keyword.get(opts, :strategy, :dynamic_quorum),
      quorum_size: calculate_initial_quorum(opts),
      current_partition: nil,
      partition_history: [],
      merge_strategy: Keyword.get(opts, :merge_strategy, &default_merge/2)
    }
    
    # Monitor topology
    Jido.Distributed.Topology.subscribe(self())
    
    {:ok, state}
  end
  
  @doc """
  Check if we can perform operation requiring quorum.
  """
  def has_quorum? do
    GenServer.call(__MODULE__, :check_quorum)
  end
  
  @doc """
  Handle operation in partition.
  """
  def handle_partitioned_operation(operation, opts \\ []) do
    GenServer.call(__MODULE__, {:handle_operation, operation, opts})
  end
  
  @impl GenServer
  def handle_call(:check_quorum, _from, state) do
    active_nodes = Jido.Distributed.Topology.get_active_nodes()
    has_quorum = check_quorum(length(active_nodes), state)
    
    {:reply, has_quorum, state}
  end
  
  @impl GenServer
  def handle_call({:handle_operation, operation, opts}, _from, state) do
    active_nodes = Jido.Distributed.Topology.get_active_nodes()
    
    result = case state.partition_strategy do
      :static_quorum ->
        if length(active_nodes) >= state.quorum_size do
          {:ok, :proceed}
        else
          {:error, :no_quorum}
        end
        
      :dynamic_quorum ->
        if length(active_nodes) >= dynamic_quorum_size(state) do
          {:ok, :proceed}
        else
          {:error, :no_quorum}
        end
        
      :primary_partition ->
        if in_primary_partition?(active_nodes, state) do
          {:ok, :proceed}
        else
          {:error, :not_primary_partition}
        end
        
      :optimistic ->
        # Always allow, track for later reconciliation
        track_partitioned_operation(operation, state)
        {:ok, :proceed_with_tracking}
    end
    
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_info({:topology_change, %{type: :partition_detected} = event}, state) do
    new_partition = %{
      id: Jido.Core.ID.generate(),
      members: event.partition_members,
      detected_at: DateTime.utc_now(),
      active: true
    }
    
    new_state = %{state |
      current_partition: new_partition,
      partition_history: [new_partition | state.partition_history]
    }
    
    # Notify applications of partition
    broadcast_partition_event(new_partition)
    
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_info({:topology_change, %{type: :partition_healed} = event}, state) do
    if state.current_partition do
      # Merge partition data
      handle_partition_merge(event, state)
    else
      {:noreply, state}
    end
  end
  
  defp handle_partition_merge(event, state) do
    # Get data from all partitions
    partition_data = collect_partition_data(event.reunited_nodes)
    
    # Apply merge strategy
    merged_data = state.merge_strategy.(partition_data, state.current_partition)
    
    # Update state
    healed_partition = %{state.current_partition | 
      active: false,
      healed_at: DateTime.utc_now(),
      merge_result: merged_data
    }
    
    new_state = %{state |
      current_partition: nil,
      partition_history: [healed_partition | state.partition_history]
    }
    
    # Apply merged data
    apply_merged_data(merged_data)
    
    {:noreply, new_state}
  end
  
  defp collect_partition_data(nodes) do
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        case :rpc.call(node, __MODULE__, :get_partition_data, [], 5000) do
          {:badrpc, _} -> {:error, node}
          data -> {:ok, node, data}
        end
      end)
    end)
    
    Task.await_many(tasks, 10000)
    |> Enum.filter(&match?({:ok, _, _}, &1))
    |> Map.new(fn {:ok, node, data} -> {node, data} end)
  end
  
  defp default_merge(partition_data, _current_partition) do
    # Vector clock based merge
    all_updates = partition_data
    |> Enum.flat_map(fn {_node, data} -> data.updates end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.vector_clock)
    
    %{
      strategy: :vector_clock_merge,
      updates: all_updates,
      conflicts: detect_conflicts(all_updates)
    }
  end
  
  defp in_primary_partition?(active_nodes, state) do
    # Use node with lowest ID as primary
    primary_node = determine_primary_node()
    primary_node in active_nodes
  end
  
  defp determine_primary_node do
    all_nodes = Node.list() ++ [node()]
    Enum.min(all_nodes)
  end
  
  defp dynamic_quorum_size(state) do
    total_nodes = length(Node.list()) + 1
    div(total_nodes, 2) + 1
  end
end
```

### 6. Distributed Consensus

```elixir
# lib/jido/distributed/consensus.ex
defmodule Jido.Distributed.Consensus do
  @moduledoc """
  Consensus mechanisms for distributed operations.
  """
  
  use GenServer
  
  defstruct [
    :algorithm,
    :current_term,
    :voted_for,
    :log,
    :commit_index,
    :state,  # :follower, :candidate, :leader
    :leader_id,
    :config
  ]
  
  @type consensus_algorithm :: :raft | :paxos | :simple_majority
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Propose a value for consensus.
  """
  def propose(value, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:propose, value}, timeout)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      algorithm: Keyword.get(opts, :algorithm, :simple_majority),
      current_term: 0,
      voted_for: nil,
      log: [],
      commit_index: 0,
      state: :follower,
      leader_id: nil,
      config: build_config(opts)
    }
    
    schedule_election_timeout()
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:propose, value}, from, %{state: :leader} = state) do
    # Leader can directly append to log
    entry = %{
      term: state.current_term,
      value: value,
      id: Jido.Core.ID.generate(),
      timestamp: DateTime.utc_now()
    }
    
    new_log = [entry | state.log]
    new_state = %{state | log: new_log}
    
    # Replicate to followers
    replicate_entry(entry, new_state)
    
    {:reply, {:ok, entry.id}, new_state}
  end
  
  def handle_call({:propose, value}, from, %{state: :follower} = state) do
    if state.leader_id do
      # Forward to leader
      forward_to_leader(state.leader_id, {:propose, value}, from)
      {:noreply, state}
    else
      {:reply, {:error, :no_leader}, state}
    end
  end
  
  @impl GenServer
  def handle_info(:election_timeout, %{state: :follower} = state) do
    # Start election
    new_state = start_election(state)
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_cast({:request_vote, candidate_id, term, last_log}, state) do
    new_state = handle_vote_request(candidate_id, term, last_log, state)
    {:noreply, new_state}
  end
  
  defp start_election(state) do
    new_term = state.current_term + 1
    
    Logger.info("Starting election for term #{new_term}")
    
    # Vote for self
    votes = MapSet.new([node()])
    
    # Request votes from others
    active_nodes = Jido.Distributed.Topology.get_active_nodes() -- [node()]
    
    Enum.each(active_nodes, fn node ->
      GenServer.cast(
        {__MODULE__, node},
        {:request_vote, node(), new_term, List.first(state.log)}
      )
    end)
    
    %{state |
      state: :candidate,
      current_term: new_term,
      voted_for: node()
    }
  end
  
  defp handle_vote_request(candidate_id, term, last_log, state) do
    cond do
      term < state.current_term ->
        # Reject old term
        send_vote_response(candidate_id, false, state.current_term)
        state
        
      term > state.current_term ->
        # Update term and consider voting
        new_state = %{state | current_term: term, voted_for: nil}
        maybe_grant_vote(candidate_id, last_log, new_state)
        
      state.voted_for == nil or state.voted_for == candidate_id ->
        # Can vote
        maybe_grant_vote(candidate_id, last_log, state)
        
      true ->
        # Already voted for someone else
        send_vote_response(candidate_id, false, state.current_term)
        state
    end
  end
  
  defp maybe_grant_vote(candidate_id, last_log, state) do
    if log_up_to_date?(last_log, state.log) do
      send_vote_response(candidate_id, true, state.current_term)
      %{state | voted_for: candidate_id}
    else
      send_vote_response(candidate_id, false, state.current_term)
      state
    end
  end
  
  defp replicate_entry(entry, state) do
    followers = Jido.Distributed.Topology.get_active_nodes() -- [node()]
    
    Enum.each(followers, fn follower ->
      Task.start(fn ->
        GenServer.cast(
          {__MODULE__, follower},
          {:append_entries, node(), state.current_term, entry}
        )
      end)
    end)
  end
end
```

## Distributed Testing

```elixir
# test/distributed/cluster_test.exs
defmodule Jido.Distributed.ClusterTest do
  use ExUnit.Case
  
  @cluster_size 5
  
  setup do
    # Start local cluster
    nodes = LocalCluster.start_nodes("jido", @cluster_size)
    
    # Start Jido on all nodes
    Enum.each(nodes, fn node ->
      :rpc.call(node, Application, :ensure_all_started, [:jido])
    end)
    
    # Wait for cluster formation
    :timer.sleep(2000)
    
    {:ok, nodes: nodes}
  end
  
  test "agents can communicate across nodes", %{nodes: nodes} do
    # Create agent on first node
    [node1, node2 | _] = nodes
    
    {:ok, agent_id} = :rpc.call(node1, fn ->
      {:ok, agent} = TestAgent.new()
      {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)
      Jido.Distributed.AgentRegistry.register(agent.id, pid)
      agent.id
    end)
    
    # Send signal from second node
    result = :rpc.call(node2, fn ->
      signal = Jido.Signal.command(agent_id, :ping, %{})
      Jido.Distributed.SignalRouter.route(signal)
    end)
    
    assert result == :ok
  end
  
  test "handles network partition", %{nodes: nodes} do
    # Partition cluster
    [partition1, partition2] = Enum.chunk_every(nodes, 3)
    
    # Block communication between partitions
    LocalCluster.partition_cluster([partition1, partition2])
    
    # Operations should handle partition
    result = :rpc.call(hd(partition1), fn ->
      Jido.Distributed.PartitionHandler.has_quorum?()
    end)
    
    assert result == false
    
    # Heal partition
    LocalCluster.heal_cluster(nodes)
    
    # Should recover
    :timer.sleep(5000)
    
    result = :rpc.call(hd(nodes), fn ->
      Jido.Distributed.PartitionHandler.has_quorum?()
    end)
    
    assert result == true
  end
end
```

This comprehensive distributed system specification ensures the Jido framework can operate reliably across multiple nodes, handle network partitions, and maintain consistency in distributed deployments.