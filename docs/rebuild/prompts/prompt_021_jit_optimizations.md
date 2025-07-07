# Prompt 21: Implement JIT-Friendly Code Patterns

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement JIT-friendly code patterns to leverage BEAM VM's JIT compiler for maximum performance (Prompt 21 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 4.1 (lines 495-577) - JIT-Friendly Patterns
- Current: `jido/lib/jido/exec.ex` (lines 382-424) - Complex validation flow
- Current: `jido/lib/jido/agent/server_runtime.ex` (lines 104-111) - Pipeline with multiple calls
- Current: `jido/lib/jido/instruction.ex` (lines 342-363) - Recursive normalization

Current code issue:
```elixir
# In exec.ex, lines 382-424 - complex conditional flow hurts JIT:
defp validate_params(action, params, context) do
  cond do
    not function_exported?(action, :validate_params, 2) -> {:ok, params}
    # Multiple conditional branches
    is_function(validator, 1) -> validator.(params)
    is_function(validator, 2) -> validator.(params, context)
    # More conditions...
  end
end

# In server_runtime.ex, lines 104-111 - indirect calls prevent inlining:
signal
|> validate_signal()
|> check_permissions(state)
|> log_signal()
|> do_execute_signal(state)
```

Implementation requirements:
1. Create `lib/jido/core/jit_optimizer.ex` with JIT-friendly patterns:
   ```elixir
   defmodule Jido.Core.JitOptimizer do
     # Pattern matching instead of conditionals
     def optimize_execution_path(action, params, context) do
       execute_optimized(action.__info__(:functions), action, params, context)
     end
     
     # Direct pattern match on function exports
     defp execute_optimized([{:validate_params, 2} | _], action, params, context) do
       action.validate_params(params, context)
     end
     
     defp execute_optimized([{:validate_params, 1} | _], action, params, _context) do
       action.validate_params(params)
     end
     
     defp execute_optimized([_ | rest], action, params, context) do
       execute_optimized(rest, action, params, context)
     end
     
     defp execute_optimized([], _action, params, _context) do
       {:ok, params}
     end
   end
   ```
2. Replace conditional logic with pattern matching:
   - Convert cond/if chains to function heads
   - Use guards for fast path selection
   - Eliminate dynamic dispatch where possible
3. Implement monomorphic function calls:
   ```elixir
   # Instead of polymorphic pipeline
   def execute_signal(signal, state) do
     # Inline critical path
     case signal do
       %{action: :state} -> 
         {:ok, state.agent.state, state}
       
       %{action: :status} ->
         {:ok, %{status: :running, queue_size: queue_size(state)}, state}
       
       %{action: action} when is_atom(action) ->
         execute_known_action(action, signal, state)
       
       _ ->
         execute_generic_signal(signal, state)
     end
   end
   ```
4. Add compile-time optimizations:
   ```elixir
   defmodule Jido.Core.FastDispatch do
     @compile {:inline, [dispatch: 2]}
     @compile {:inline_size, 100}
     
     # Generate specialized dispatchers at compile time
     for {action, module} <- known_actions() do
       def dispatch(unquote(action), params) do
         unquote(module).execute(params)
       end
     end
     
     def dispatch(action, params) do
       GenericDispatch.execute(action, params)
     end
   end
   ```
5. Optimize hot loops with tail recursion:
   ```elixir
   # Convert queue processing to tail-recursive form
   defp process_queue_optimized([], state, acc), do: {Enum.reverse(acc), state}
   
   defp process_queue_optimized([signal | rest], state, acc) do
     case fast_execute(signal, state) do
       {:ok, result, new_state} ->
         process_queue_optimized(rest, new_state, [{signal.id, result} | acc])
       
       {:error, reason} ->
         process_queue_optimized(rest, state, [{signal.id, {:error, reason}} | acc])
     end
   end
   ```
6. Implement type-stable operations:
   - Avoid changing struct shapes dynamically
   - Use fixed-size tuples instead of variable lists
   - Pre-allocate maps with known keys
7. Add guard-based fast paths:
   ```elixir
   def handle_signal(signal, state) 
       when signal.action in [:state, :status, :ping] do
     # Fast path for read-only operations
     FastPath.execute_readonly(signal, state)
   end
   
   def handle_signal(signal, state) do
     # Regular path for complex operations
     execute_signal(signal, state)
   end
   ```
8. Remove abstractions from hot paths:
   - Inline small functions manually
   - Unroll simple loops
   - Avoid protocol dispatch in performance-critical code

Success criteria:
- 30-50% performance improvement from JIT optimization
- Monomorphic call sites for 90% of executions
- Reduced instruction count in hot paths
- Better CPU branch prediction (< 5% misprediction rate)
- Consistent performance across runs
- JIT compilation time < 100ms for hot modules
- Profiler shows improved inlining rates

Performance targets from Doc 106 (lines 540-545):
- Function dispatch: < 10ns for monomorphic calls
- Pattern matching: 2-3x faster than conditional chains
- Hot loop execution: 50% fewer CPU instructions
- Memory access: Better cache locality from type stability
- JIT effectiveness: 90%+ of hot code paths optimized