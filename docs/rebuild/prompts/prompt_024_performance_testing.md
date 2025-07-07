# Prompt 24: Implement Comprehensive Performance Testing

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Create comprehensive performance test suite to verify all optimizations meet the 50% improvement target (Prompt 24 of ~30)

References needed:
- Doc 106: Performance Optimization Details, section 5 (lines 762-942) - Benchmarking
- Doc 105: Test Strategy (performance testing section)
- Doc 101: Implementation Plan, Week 3 targets (line 694) - 50% improvement goal
- All Phase 3 optimizations from prompts 17-23

Current code issue:
```elixir
# No comprehensive performance benchmarks exist
# No baseline measurements for comparison
# No automated performance regression detection
# Missing performance profiles for different workloads
```

Implementation requirements:
1. Create `test/performance/benchmark_suite.exs` with comprehensive benchmarks:
   ```elixir
   defmodule Jido.Performance.BenchmarkSuite do
     use Benchfella
     
     @baseline_results "test/performance/baseline_v1.json"
     @warmup_iterations 1000
     
     # Baseline measurements before optimizations
     setup_all do
       # Disable optimizations to get baseline
       Application.put_env(:jido, :fast_path_enabled, false)
       Application.put_env(:jido, :zero_copy_enabled, false)
       Application.put_env(:jido, :pooling_enabled, false)
       
       capture_baseline_metrics()
     end
     
     bench "signal creation - baseline" do
       Signal.new(:test_action, %{data: :crypto.strong_rand_bytes(1024)})
     end
     
     bench "local signal dispatch - baseline" do
       agent = start_test_agent()
       Signal.dispatch(build_signal(), agent)
     end
   end
   ```
2. Implement optimization-specific benchmarks:
   ```elixir
   defmodule Jido.Performance.OptimizationBenchmarks do
     # Fast path benchmarks
     bench "fast path - state query", [agent: setup_agent()] do
       Agent.Server.FastPath.execute(%Signal{action: :state}, agent)
     end
     
     bench "fast path vs regular path comparison" do
       compare_execution_paths(:state_query, fast_path: true, regular_path: true)
     end
     
     # Zero-copy benchmarks  
     bench "zero-copy signal passing", [size: [64, 1024, 65536]] do
       signal = build_signal_with_size(size)
       ZeroCopy.send_local_signal(signal, self())
     end
     
     # Pooling benchmarks
     bench "object pool allocation vs new" do
       pooled = Pool.checkout(:instruction)
       regular = %Instruction{}
       Pool.checkin(:instruction, pooled)
     end
   end
   ```
3. Add load testing scenarios:
   ```elixir
   defmodule Jido.Performance.LoadTest do
     @scenarios %{
       burst: {10_000, :instant},      # 10k signals at once
       sustained: {1_000, :per_second}, # 1k signals/sec for 60 sec
       mixed: {:realistic_workload}     # Mix of operations
     }
     
     def run_load_test(scenario, duration_sec) do
       {:ok, agent} = start_load_test_agent()
       
       stats = generate_load(agent, @scenarios[scenario], duration_sec)
       
       analyze_results(stats, expected_targets())
     end
     
     defp expected_targets do
       %{
         p50_latency: 10,    # μs
         p99_latency: 100,   # μs  
         throughput: 10_000, # ops/sec
         error_rate: 0.001   # 0.1%
       }
     end
   end
   ```
4. Implement performance profiling:
   ```elixir
   defmodule Jido.Performance.Profiler do
     def profile_optimization(optimization, workload) do
       :fprof.start()
       
       # Run workload with optimization disabled
       baseline = run_with_config([{optimization, false}], workload)
       
       # Run workload with optimization enabled
       optimized = run_with_config([{optimization, true}], workload)
       
       analysis = :fprof.analyse([
         :totals,
         {:dest, "profiles/#{optimization}_profile.txt"}
       ])
       
       calculate_improvement(baseline, optimized)
     end
   end
   ```
5. Add memory usage benchmarks:
   ```elixir
   bench "memory usage - signal creation" do
     before_memory = :erlang.memory(:total)
     
     # Create 1000 signals
     signals = for _ <- 1..1000, do: Signal.new(:test, %{})
     
     after_memory = :erlang.memory(:total)
     memory_per_signal = (after_memory - before_memory) / 1000
     
     assert memory_per_signal < 1024  # Less than 1KB per signal
   end
   ```
6. Create performance regression detection:
   ```elixir
   defmodule Jido.Performance.RegressionTest do
     @tolerance 0.10  # Allow 10% variance
     
     def check_regression(current_results) do
       baseline = load_baseline_results()
       
       Enum.each(current_results, fn {metric, value} ->
         baseline_value = baseline[metric]
         
         if regression?(value, baseline_value, @tolerance) do
           raise "Performance regression in #{metric}: " <>
                 "#{value} vs baseline #{baseline_value}"
         end
       end)
     end
   end
   ```
7. Implement distributed performance tests:
   ```elixir
   defmodule Jido.Performance.DistributedTest do
     def test_cross_node_performance(node_count) do
       nodes = start_cluster(node_count)
       
       # Measure cross-node signal latency
       latencies = measure_cross_node_latencies(nodes)
       
       # Test tree broadcast efficiency  
       broadcast_time = measure_tree_broadcast(nodes, 1000)
       
       # Verify batching effectiveness
       batch_improvement = measure_batch_improvement(nodes)
       
       assert Enum.mean(latencies) < 5  # ms
       assert broadcast_time < node_count * 10  # Linear bound
       assert batch_improvement > 0.5  # 50% improvement
     end
   end
   ```
8. Add continuous performance monitoring:
   ```elixir
   defmodule Jido.Performance.Monitor do
     use GenServer
     
     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: __MODULE__)
     end
     
     def init(_) do
       schedule_performance_check()
       {:ok, %{metrics: [], thresholds: load_thresholds()}}
     end
     
     def handle_info(:check_performance, state) do
       metrics = collect_current_metrics()
       
       if degradation_detected?(metrics, state.thresholds) do
         alert_performance_degradation(metrics)
       end
       
       schedule_performance_check()
       {:noreply, %{state | metrics: [metrics | state.metrics]}}
     end
   end
   ```

Success criteria:
- All optimization benchmarks show 50%+ improvement over baseline
- Fast path achieves < 10μs for simple operations
- Zero-copy reduces memory allocation by 80%
- Pooling reduces GC pressure by 50%
- Batch processing improves throughput 3-5x
- JIT optimizations show 30%+ CPU improvement
- Caching achieves 80%+ hit rate
- Distributed optimizations reduce network traffic 60%
- No performance regressions in existing functionality
- All performance tests run in < 5 minutes

Performance verification checklist:
- [ ] Baseline measurements captured and stored
- [ ] Each optimization validated independently  
- [ ] Combined optimizations show cumulative improvement
- [ ] Load tests pass at 10x expected traffic
- [ ] Memory usage remains stable under load
- [ ] Distributed tests verify network optimizations
- [ ] Performance regression detection automated
- [ ] Continuous monitoring in place