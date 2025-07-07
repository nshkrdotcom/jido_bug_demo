# Prompt 17: Implement Fast Path for Local Signal Execution

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement fast path execution for local signals that bypasses serialization and queue processing (Prompt 17 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 1 (lines 39-136) - Direct Function Call Path
- Doc 101: Implementation Plan, Week 3 targets (line 694) - 50% performance improvement requirement
- Current: `jido/lib/jido/agent/server.ex` (lines 208-252) - handle_call implementation
- Current: `jido/lib/jido/agent/server_runtime.ex` (lines 99-123) - execute_signal pipeline

Current code issue:
```elixir
# In server.ex, line 233-246:
def handle_call({:signal, signal}, from, state) do
  # Always stores reply reference and enqueues, even for simple queries
  state = Map.put(state, {:reply, signal.id}, from)
  
  state =
    case enqueue_signal(signal, state) do
      {:ok, state} -> state
      {:error, reason} -> state
    end
  
  if state.processing? do
    {:noreply, state}
  else
    Process.send_after(self(), :process_queue, 0)
    {:noreply, %{state | processing?: true}}
  end
end
```

Implementation requirements:
1. Create `lib/jido/agent/server/fast_path.ex` module with fast path detection logic
2. Implement `FastPath.can_execute_directly?/2` to identify signals that bypass queuing:
   - Simple queries (`:state`, `:status`, `:pending_instructions`)
   - Stateless operations with no side effects
   - Local node signals without distributed concerns
3. Add `FastPath.execute/2` for direct execution without serialization:
   - Skip queue operations entirely
   - Execute synchronously in the calling process
   - Return result immediately via `{:reply, result, state}`
4. Modify `handle_call/3` in server.ex to check fast path first:
   ```elixir
   def handle_call({:signal, signal}, from, state) do
     if FastPath.can_execute_directly?(signal, state) do
       case FastPath.execute(signal, state) do
         {:ok, result, new_state} -> {:reply, {:ok, result}, new_state}
         {:error, reason} -> {:reply, {:error, reason}, state}
       end
     else
       # Existing queue-based implementation
     end
   end
   ```
5. Optimize common query patterns:
   - State queries should read directly without Agent.cmd overhead
   - Status checks should bypass instruction creation
   - Pending instruction counts should use queue size directly
6. Add compile-time optimization flags:
   - `@compile {:inline, [can_execute_directly?: 2, execute: 2]}`
   - Pattern match on signal.action for known fast operations
7. Ensure compatibility with existing signal processing:
   - Fast path results must match format of queue-processed results
   - Maintain telemetry and logging for audit trails
   - Preserve error handling semantics

Success criteria:
- Simple state queries execute in < 10 microseconds (vs current ~100μs)
- No queue operations or process messages for fast path signals
- Zero serialization overhead for local read operations
- All existing tests pass without modification
- Benchmark shows 50%+ improvement for targeted operations
- Fast path handles at least 30% of typical signal traffic

Performance targets from Doc 106 (lines 55-57):
- Local dispatch: < 100μs → < 10μs for fast path
- State queries: Direct memory access, no serialization
- Skip validation for trusted local operations