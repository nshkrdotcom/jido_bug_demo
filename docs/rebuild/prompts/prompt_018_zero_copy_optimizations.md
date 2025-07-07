# Prompt 18: Implement Zero-Copy Signal Optimizations

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement zero-copy optimizations for signal passing to reduce memory allocation and copying overhead (Prompt 18 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 2 (lines 138-217) - Zero-Copy Optimizations
- Doc 108: Distributed System Considerations (lines 386-526) - Network-aware routing
- Current: `jido/lib/jido/signal.ex` - Signal struct and creation
- Current: `jido/lib/jido/agent.ex` (line 129) - Instruction to Signal conversion

Current code issue:
```elixir
# In agent.ex, line 129 - creates new Signal for every instruction:
signal = %Signal{
  id: Jido.Util.generate_id(),
  source: agent.id,
  action: instruction.action,
  params: instruction.params,
  context: instruction.context
}

# In signal routing, signals are copied multiple times:
# 1. When creating from instruction
# 2. When enqueuing in server
# 3. When passing between processes
```

Implementation requirements:
1. Create `lib/jido/signal/zero_copy.ex` module for zero-copy signal handling
2. Implement signal template caching using `:persistent_term`:
   ```elixir
   defmodule Jido.Signal.ZeroCopy do
     @template_cache_prefix :jido_signal_template_
     
     def cache_template(action, template) do
       :persistent_term.put({@template_cache_prefix, action}, template)
     end
     
     def get_cached_template(action) do
       :persistent_term.get({@template_cache_prefix, action}, nil)
     end
   end
   ```
3. Modify Signal creation to use templates for common patterns:
   - Pre-create templates for frequently used actions
   - Only store differences from template in signal instance
   - Use reference counting for shared data structures
4. Implement direct message passing for local nodes:
   ```elixir
   def send_local_signal(signal, target_pid) when node(target_pid) == node() do
     # Send signal reference directly without copying
     send(target_pid, {:signal_ref, make_ref(), signal})
   end
   ```
5. Add binary optimization for large payloads:
   - Store binaries > 64KB externally
   - Pass only references in signals
   - Use sub-binary references without copying
6. Optimize instruction-to-signal conversion:
   - Reuse instruction data structures when possible
   - Avoid deep copying of params and context
   - Use ETS for temporary signal storage with write_concurrency
7. Add zero-copy batch operations:
   ```elixir
   def batch_signals(signals) do
     # Group signals by action type
     # Share common data between grouped signals
     # Return list of signal references, not copies
   end
   ```
8. Implement memory pooling for signal structs:
   - Pre-allocate pool of signal structs
   - Reuse cleared structs instead of allocating new ones
   - Track pool statistics for tuning

Success criteria:
- Signal creation allocates 80% less memory for common operations
- Zero copying for local node signal passing
- Template cache hit rate > 90% for common actions
- Large binary handling without duplication
- Memory usage reduced by 50% under load
- No performance regression for distributed signals
- All existing signal tests pass

Performance targets from Doc 106 (lines 151-156):
- Signal creation: < 1μs for templated actions
- Local signal passing: Zero-copy via reference
- Memory allocation: < 100 bytes per signal for common cases
- Binary handling: Sub-binary optimization for payloads > 1KB