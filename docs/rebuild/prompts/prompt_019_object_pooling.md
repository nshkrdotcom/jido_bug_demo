# Prompt 19: Implement Object Pooling for Instructions and Signals

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement object pooling to reduce garbage collection pressure and improve memory efficiency (Prompt 19 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 3.1 (lines 221-326) - Object Pooling
- Current: `jido/lib/jido/instruction.ex` (line 146) - UUID generation overhead
- Current: `jido/lib/jido/agent.ex` (line 169) - Queue operations
- Current: `jido/lib/jido/exec.ex` (lines 812-827) - Task spawning

Current code issue:
```elixir
# In instruction.ex, line 146 - generates new UUID for every instruction:
defstruct [
  id: Jido.Util.generate_id(),  # New UUID every time
  action: nil,
  params: %{},
  context: %{},
  opts: []
]

# In exec.ex, lines 812-827 - spawns new Task for every execution:
task = Task.async(fn ->
  receive do
    :start ->
      do_execute(action, params, context, opts)
  end
end)
```

Implementation requirements:
1. Create `lib/jido/core/pool.ex` module with generic pooling infrastructure:
   ```elixir
   defmodule Jido.Core.Pool do
     use GenServer
     
     defstruct [:type, :size, :available, :in_use, :factory, :reset_fn]
     
     # Pool configuration
     @pools %{
       instruction: {1000, &Instruction.new/0, &Instruction.reset/1},
       signal: {5000, &Signal.new/0, &Signal.reset/1},
       task: {500, &Task.Supervisor.async_nolink/2, &Task.shutdown/2},
       error: {500, &Error.new/0, &Error.reset/1}
     }
   end
   ```
2. Implement pool lifecycle management:
   - `checkout/1` - Get object from pool or create new if empty
   - `checkin/2` - Return object to pool after reset
   - `expand/2` - Dynamically grow pool under pressure
   - `shrink/1` - Reduce pool size during idle periods
3. Add instruction pooling to reduce allocations:
   ```elixir
   defmodule Jido.Instruction do
     def from_pool(action, params \\ %{}, context \\ %{}, opts \\ []) do
       case Pool.checkout(:instruction) do
         {:ok, instruction} ->
           %{instruction | 
             action: action,
             params: params,
             context: context,
             opts: opts,
             id: lazy_generate_id()
           }
         :empty ->
           new(action, params, context, opts)
       end
     end
     
     defp lazy_generate_id do
       # Only generate ID when actually needed
       fn -> Jido.Util.generate_id() end
     end
   end
   ```
4. Implement signal pooling with zero-reset overhead:
   - Pre-allocate signals in pool
   - Use efficient reset that only clears necessary fields
   - Maintain pool statistics for monitoring
5. Add execution process pooling:
   ```elixir
   defmodule Jido.Exec.ProcessPool do
     # Pool of pre-started processes for execution
     def execute_in_pool(action, params, context, opts) do
       case checkout_process() do
         {:ok, pid} ->
           ref = make_ref()
           send(pid, {:execute, ref, action, params, context, opts, self()})
           receive do
             {^ref, result} -> 
               checkin_process(pid)
               result
           end
         :empty ->
           # Fallback to regular execution
           Jido.Exec.run(action, params, context, opts)
       end
     end
   end
   ```
6. Add pool warming and statistics:
   - Pre-warm pools on application start
   - Track pool utilization metrics
   - Auto-tune pool sizes based on usage patterns
7. Implement efficient object reset:
   - Clear only mutable fields
   - Preserve pre-allocated internal structures
   - Avoid deep cleaning when not necessary
8. Add pooling for common temporary objects:
   - Queue nodes for instruction queuing
   - Map structures for context merging
   - Binary buffers for serialization

Success criteria:
- 70% reduction in object allocations for pooled types
- GC pressure reduced by 50% under load
- Pool hit rate > 85% during normal operation
- No memory leaks from pooled objects
- Pool overhead < 5% of memory savings
- Auto-scaling pools based on load patterns
- All existing tests pass with pooling enabled

Performance targets from Doc 106 (lines 262-266):
- Object checkout: < 100ns
- Object reset: < 500ns
- Pool management overhead: < 1% CPU
- Memory reduction: 50-70% for short-lived objects
- GC pause reduction: 40% under heavy load