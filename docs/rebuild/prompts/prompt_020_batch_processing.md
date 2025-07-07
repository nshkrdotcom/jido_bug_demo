# Prompt 20: Implement Batch Processing for Throughput Optimization

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement batch processing to optimize throughput by grouping multiple operations (Prompt 20 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 4.2 (lines 579-683) - Batch Processing
- Current: `jido/lib/jido/agent/server_runtime.ex` (lines 21-71) - Single signal processing
- Current: `jido/lib/jido/runner/simple.ex` (line 109) - Single instruction dequeue
- Current: `jido/lib/jido/agent/server.ex` (line 241) - Individual queue triggers

Current code issue:
```elixir
# In server_runtime.ex, lines 24-29 - processes one signal at a time:
case dequeue_signal(state) do
  {nil, state} ->
    %{state | processing?: false}
  
  {signal, state} ->
    # Processes single signal, losing batching opportunity
    state = execute_signal(signal, state)
end

# In simple.ex, line 109 - dequeues one instruction:
{instruction, agent} = Jido.Agent.dequeue_instruction(agent)
```

Implementation requirements:
1. Create `lib/jido/core/batch_processor.ex` module for batch coordination:
   ```elixir
   defmodule Jido.Core.BatchProcessor do
     @batch_size 100
     @batch_timeout_ms 10
     
     defstruct [
       :batch_size,
       :timeout_ms,
       :accumulator,
       :timer_ref,
       :processor_fn
     ]
     
     def process_batch(items, group_by_fn, execute_fn) do
       items
       |> Enum.group_by(group_by_fn)
       |> Enum.map(fn {key, grouped_items} ->
         Task.async(fn -> execute_fn.(key, grouped_items) end)
       end)
       |> Task.await_many()
     end
   end
   ```
2. Modify signal processing to batch similar signals:
   ```elixir
   defmodule Jido.Agent.Server.Runtime do
     def process_signals_in_batch(state, batch_size \\ 100) do
       {signals, state} = dequeue_signals(state, batch_size)
       
       case signals do
         [] -> %{state | processing?: false}
         signals ->
           # Group by action type for efficient processing
           grouped = Enum.group_by(signals, & &1.action)
           
           state = Enum.reduce(grouped, state, fn {action, action_signals}, acc_state ->
             execute_signal_batch(action, action_signals, acc_state)
           end)
       end
     end
   end
   ```
3. Implement batch instruction execution:
   - Dequeue multiple instructions at once
   - Group by action type and similar parameters
   - Execute groups in parallel when safe
   - Preserve execution order within groups
4. Add smart batching heuristics:
   ```elixir
   def should_batch?(queue_size, current_load) do
     cond do
       queue_size > 1000 -> {true, 200}      # Large batch for high load
       queue_size > 100 -> {true, 50}        # Medium batch
       queue_size > 10 -> {true, 10}         # Small batch
       true -> {false, 1}                    # No batching for low load
     end
   end
   ```
5. Implement batch-aware operations:
   - State updates that merge multiple changes
   - Bulk signal routing for same destination
   - Combined telemetry events for batches
   - Batch error handling with partial success
6. Add flow control for batch processing:
   ```elixir
   def flow_controlled_batch(items, max_concurrent \\ System.schedulers_online()) do
     items
     |> Stream.chunk_every(@batch_size)
     |> Stream.map(&process_chunk/1)
     |> Stream.take(max_concurrent)
     |> Enum.to_list()
   end
   ```
7. Optimize database and I/O operations:
   - Batch database queries for related data
   - Combine multiple file operations
   - Group network requests by destination
8. Add batch monitoring and metrics:
   - Track batch sizes and processing times
   - Monitor batching effectiveness
   - Auto-tune batch parameters based on throughput

Success criteria:
- 3-5x throughput improvement for high-load scenarios
- Batch processing reduces overhead by 60%
- Automatic batch sizing based on queue depth
- Latency remains < 50ms for 99th percentile
- CPU utilization improves by 40% under load
- Memory efficiency through shared batch processing
- All single-operation tests still pass

Performance targets from Doc 106 (lines 641-647):
- Batch size: 10-200 items based on load
- Batch formation: < 1ms overhead
- Throughput: 10,000+ operations/second
- Latency impact: < 10ms additional for batching
- CPU efficiency: 40% reduction in per-operation cost