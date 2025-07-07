# Prompt 23: Implement Distributed System Optimizations

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Optimize cross-node communication and implement network-aware routing for distributed deployments (Prompt 23 of ~30)

References needed:
- Doc 108: Distributed System Considerations (lines 386-526) - Network optimizations
- Doc 106: Performance Optimization Details, section 2 (lines 190-195) - Local node detection
- Current: `jido/lib/jido/router.ex` - Current routing logic
- Current: `jido/lib/jido/signal/dispatcher.ex` - Signal dispatch

Current code issue:
```elixir
# Current routing doesn't optimize for network topology
# No batching for cross-node signals
# No fallback for network partitions
# Missing local-first routing optimization

# In dispatcher, each signal sent individually:
Enum.each(signals, fn signal ->
  send(target_pid, {:signal, signal})  # Individual network calls
end)
```

Implementation requirements:
1. Create `lib/jido/distributed/optimizer.ex` for network-aware operations:
   ```elixir
   defmodule Jido.Distributed.Optimizer do
     @local_node_cache :persistent_term.get(:jido_local_node, node())
     
     def optimize_routing(signals, targets) do
       signals
       |> group_by_node(targets)
       |> Enum.map(fn {node, node_signals} ->
         if node == @local_node_cache do
           {:local, node_signals}
         else
           {:remote, node, batch_for_network(node_signals)}
         end
       end)
     end
     
     defp batch_for_network(signals) do
       # Compress and batch signals for network efficiency
       signals
       |> :erlang.term_to_binary([:compressed])
       |> Base.encode64()
     end
   end
   ```
2. Implement local-first routing with fallback:
   ```elixir
   defmodule Jido.Router do
     def route_with_locality(signal, agents) do
       local_agents = Enum.filter(agents, &on_local_node?/1)
       
       case find_capable_agent(signal, local_agents) do
         {:ok, agent} -> 
           {:local, agent}
           
         :not_found ->
           # Fall back to remote agents
           remote_agents = agents -- local_agents
           route_to_remote(signal, remote_agents)
       end
     end
     
     defp on_local_node?(%{node: agent_node}) do
       agent_node == node()
     end
   end
   ```
3. Add tree-based broadcast optimization:
   ```elixir
   defmodule Jido.Distributed.TreeBroadcast do
     @fanout 4  # Each node forwards to 4 others
     
     def broadcast(signal, all_nodes) do
       tree = build_broadcast_tree(all_nodes, node())
       initiate_tree_broadcast(signal, tree)
     end
     
     defp build_broadcast_tree(nodes, root) do
       # Build optimal broadcast tree based on network topology
       %{
         root: root,
         children: partition_nodes(nodes -- [root], @fanout),
         depth: calculate_depth(length(nodes), @fanout)
       }
     end
   end
   ```
4. Implement signal buffering for unreachable nodes:
   ```elixir
   defmodule Jido.Distributed.Buffer do
     use GenServer
     
     @buffer_size 10_000
     @retry_interval :timer.seconds(5)
     
     def buffer_for_node(node, signal) do
       case :ets.lookup(:node_buffers, node) do
         [{^node, buffer}] when length(buffer) < @buffer_size ->
           :ets.update_element(:node_buffers, node, {2, [signal | buffer]})
           
         _ ->
           {:error, :buffer_full}
       end
     end
     
     def flush_when_available(node) do
       Process.send_after(self(), {:retry_flush, node}, @retry_interval)
     end
   end
   ```
5. Add network-aware batching:
   ```elixir
   def batch_by_network_cost(signals) do
     signals
     |> Enum.group_by(&network_distance(&1.target_node))
     |> Enum.map(fn {distance, signals} ->
       batch_size = optimal_batch_size(distance)
       {distance, Enum.chunk_every(signals, batch_size)}
     end)
   end
   
   defp network_distance(target_node) do
     # Calculate network distance (same rack, datacenter, region)
     case {node(), target_node} do
       {n, n} -> :local
       _ -> measure_latency(target_node)
     end
   end
   ```
6. Implement distributed caching coordination:
   ```elixir
   defmodule Jido.Distributed.Cache do
     def coordinate_cache_invalidation(key, nodes) do
       # Use gossip protocol for eventual consistency
       gossip_invalidation(key, nodes, ttl: :timer.seconds(5))
     end
     
     def distributed_cache_get(key) do
       case local_cache_get(key) do
         :miss -> 
           # Query nearby nodes before remote ones
           query_nodes_by_distance(key)
         hit -> 
           hit
       end
     end
   end
   ```
7. Add partition tolerance:
   ```elixir
   def handle_network_partition(unreachable_nodes, signals) do
     # Store signals for later delivery
     buffer_signals(unreachable_nodes, signals)
     
     # Find alternative routes through reachable nodes
     find_relay_nodes(unreachable_nodes, reachable_nodes())
     
     # Update routing tables to avoid unreachable nodes
     update_routing_weights(unreachable_nodes, :infinity)
   end
   ```
8. Implement monitoring and adaptation:
   - Track network latencies between nodes
   - Adjust batch sizes based on network conditions
   - Automatically detect and adapt to topology changes
   - Monitor cross-node traffic patterns

Success criteria:
- 70% reduction in cross-node message count through batching
- Local-first routing achieves 90% local execution
- Network partition recovery < 10 seconds
- Tree broadcast reduces message complexity from O(n) to O(log n)
- Adaptive batching reduces network overhead by 50%
- No message loss during network disruptions
- Distributed cache coordination < 100ms

Performance targets from Doc 108 (lines 516-521):
- Cross-node latency: < 5ms for same datacenter
- Batch formation: < 1ms overhead
- Network utilization: 60% reduction through batching
- Partition detection: < 2 seconds
- Message delivery guarantee: 99.99% within 30 seconds