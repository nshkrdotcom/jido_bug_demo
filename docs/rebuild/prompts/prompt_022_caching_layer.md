# Prompt 22: Implement Strategic Caching Layer

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Add strategic caching layer to reduce redundant computations and improve response times (Prompt 22 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 3.3 (lines 403-491) - ETS-Based Caching
- Current: `jido/lib/jido/instruction.ex` (lines 423-445) - Repeated validation
- Current: `jido/lib/jido/router.ex` - Route computation
- Current: `jido/lib/jido/exec.ex` (lines 404-423) - Parameter validation

Current code issue:
```elixir
# In instruction.ex, lines 423-445 - validates same actions repeatedly:
defp validate_allowed_actions(instructions, allowed_actions) do
  # This validation happens for every instruction, even duplicates
  Enum.reduce_while(instructions, {:ok, []}, fn instruction, {:ok, acc} ->
    if instruction.action in allowed_actions do
      {:cont, {:ok, [instruction | acc]}}
    else
      {:halt, {:error, :action_not_allowed}}
    end
  end)
end

# Route computation happens for every signal without caching
# Parameter validation repeats for same action/params combinations
```

Implementation requirements:
1. Create `lib/jido/core/cache.ex` module with multi-tier caching:
   ```elixir
   defmodule Jido.Core.Cache do
     use GenServer
     
     @tables %{
       validation: {:validation_cache, [:set, :public, :named_table, read_concurrency: true]},
       routes: {:route_cache, [:set, :public, :named_table, read_concurrency: true]},
       results: {:result_cache, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]},
       templates: {:template_cache, [:set, :public, :named_table, compressed: true]}
     }
     
     def init(_) do
       tables = for {name, {table_name, opts}} <- @tables, into: %{} do
         :ets.new(table_name, opts)
         {name, table_name}
       end
       
       {:ok, %{tables: tables, stats: init_stats()}}
     end
   end
   ```
2. Implement validation caching with TTL:
   ```elixir
   defmodule Jido.Core.Cache.Validation do
     @ttl_ms :timer.minutes(5)
     
     def cached_validate(action, params, validator_fn) do
       key = {:validate, action, hash_params(params)}
       
       case lookup_with_ttl(:validation_cache, key) do
         {:ok, result} -> 
           bump_stats(:validation, :hit)
           result
           
         :miss ->
           bump_stats(:validation, :miss)
           result = validator_fn.(action, params)
           cache_with_ttl(:validation_cache, key, result, @ttl_ms)
           result
       end
     end
     
     defp hash_params(params) when map_size(params) < 10 do
       # For small params, use the map directly as key
       params
     end
     
     defp hash_params(params) do
       # For large params, use hash
       :erlang.phash2(params)
     end
   end
   ```
3. Add route caching for signal dispatch:
   ```elixir
   defmodule Jido.Router do
     def cached_route(signal, registered_agents) do
       key = {signal.action, signal.target, hash_agents(registered_agents)}
       
       case Cache.lookup(:routes, key) do
         {:ok, route} -> route
         :miss ->
           route = compute_route(signal, registered_agents)
           Cache.insert(:routes, key, route, ttl: :timer.minutes(1))
           route
       end
     end
   end
   ```
4. Implement result caching for idempotent operations:
   ```elixir
   def cache_idempotent_result(action, params, result) when action in @idempotent_actions do
     key = {action, params, node()}
     Cache.insert(:results, key, result, ttl: :timer.seconds(30))
   end
   ```
5. Add smart cache invalidation:
   - Track dependencies between cached items
   - Invalidate related caches on state changes
   - Use generation counters for bulk invalidation
   - Monitor cache effectiveness and auto-tune TTLs
6. Implement cache warming strategies:
   ```elixir
   def warm_caches(agent) do
     # Pre-compute common validations
     for action <- agent.allowed_actions do
       validator = Cache.Validation.get_validator(action)
       Cache.Validation.warm_validator(action, validator)
     end
     
     # Pre-compute frequent routes
     warm_frequent_routes(agent)
   end
   ```
7. Add cache statistics and monitoring:
   ```elixir
   defmodule Jido.Core.Cache.Stats do
     def report_stats do
       %{
         validation: get_cache_stats(:validation_cache),
         routes: get_cache_stats(:route_cache),
         results: get_cache_stats(:result_cache),
         memory: total_cache_memory(),
         effectiveness: calculate_hit_ratio()
       }
     end
   end
   ```
8. Implement adaptive caching policies:
   - LRU eviction for memory-constrained caches
   - Frequency-based caching for hot items
   - Size-aware caching for large objects
   - Cost-based caching for expensive computations

Success criteria:
- Cache hit ratio > 80% for validation operations
- Route cache reduces computation by 90%
- Memory usage < 100MB for typical workloads
- Cache lookup time < 1μs
- Automatic cache size management
- No stale data from inadequate invalidation
- 40% overall latency reduction for cached operations

Performance targets from Doc 106 (lines 466-471):
- Cache lookup: < 1μs for in-process cache
- Validation caching: 95% hit rate for common actions
- Route caching: 90% hit rate after warm-up
- Memory overhead: < 5% of total application memory
- Cache warming: < 100ms on startup