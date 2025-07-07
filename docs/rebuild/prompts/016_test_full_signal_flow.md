# Prompt 16: Test Full Signal Flow

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Test Full Signal Flow End-to-End (Prompt 16 of ~30)

## References Needed
- Doc 105 (Test Strategy and Validation)
- Doc 101, Lines 335-357 (Bus sensor integration test)
- All previous prompts 9-15 implementations

## Current State
All signal modules have been moved and integrated. Now we need comprehensive tests to verify the full signal flow works correctly.

## Implementation Requirements

1. **Create Integration Test Suite**
   Create `test/jido/signal_integration_test.exs`:

   ```elixir
   defmodule Jido.SignalIntegrationTest do
     use ExUnit.Case, async: false
     
     alias Jido.Agent.{Instance, Server}
     alias Jido.Signal
     alias Jido.Signal.{Bus, Dispatch}
     alias Jido.Sensors.Bus, as: BusSensor
     
     setup do
       # Start a test bus
       {:ok, bus} = Bus.start_link(
         name: :test_bus,
         agent_aware: true
       )
       
       # Start registry for agents
       {:ok, _} = Registry.start_link(
         keys: :unique, 
         name: Jido.Test.Registry
       )
       
       {:ok, bus: bus}
     end
     
     test "full signal flow: agent -> bus -> sensor -> agent", %{bus: bus} do
       # Create source agent
       source_agent = %Instance{
         id: "source_agent",
         module: TestAgent,
         state: %{name: "source"},
         __vsn__: 1
       }
       
       # Create target agent
       target_agent = %Instance{
         id: "target_agent", 
         module: TestAgent,
         state: %{name: "target"},
         __vsn__: 1
       }
       
       # Start target agent server
       {:ok, target_pid} = Server.start_link(
         agent: target_agent,
         name: {:via, Registry, {Jido.Test.Registry, "target_agent"}}
       )
       
       # Start bus sensor
       {:ok, sensor} = BusSensor.start_link(
         id: "test_sensor",
         bus_name: :test_bus,
         stream_id: "test_stream",
         target: {:named, {:via, Registry, {Jido.Test.Registry, "target_agent"}}}
       )
       
       # Subscribe target to bus via sensor patterns
       :ok = Bus.subscribe_agent(bus, target_agent, ["jido.agent.cmd.#"])
       
       # Create and publish signal from source
       signal = Signal.from_agent(source_agent, "cmd.ping", %{
         timestamp: DateTime.utc_now()
       })
       
       :ok = Bus.publish_from_agent(bus, source_agent, signal)
       
       # Wait for signal propagation
       Process.sleep(100)
       
       # Verify target received signal
       assert Server.call(target_pid, :get_last_signal) == signal
     end
     
     test "local optimization for same-node signals" do
       # Create two agents on same node
       agent1 = %Instance{id: "agent1", module: TestAgent, state: %{}, __vsn__: 1}
       agent2 = %Instance{id: "agent2", module: TestAgent, state: %{}, __vsn__: 1}
       
       # Track dispatch path
       test_pid = self()
       
       # Create signal with local dispatch
       signal = Signal.command(agent2, :run, %{test_pid: test_pid})
       
       # Dispatch should use local optimization
       assert signal.dispatch == [
         {:local, target: {:via, Registry, {Jido.Registry, "agent2"}}},
         {:named, {:via, Registry, {Jido.Registry, "agent2"}}}
       ]
       
       # Measure dispatch time
       start = System.monotonic_time(:microsecond)
       :ok = Dispatch.dispatch(signal, signal.dispatch)
       elapsed = System.monotonic_time(:microsecond) - start
       
       # Should be very fast (< 1ms)
       assert elapsed < 1000
     end
     
     test "bus sensor without circular dependency" do
       # This is the critical test from Doc 101
       {:ok, bus} = Bus.start_link(name: :test_bus_2)
       
       # Start bus sensor - should not cause circular dependency
       {:ok, sensor} = BusSensor.start_link(
         id: "circular_test_sensor",
         bus_name: :test_bus_2,
         stream_id: "test_stream",
         target: self()
       )
       
       # Publish signal to bus
       signal = Signal.new!(%{
         id: Jido.Core.ID.generate(),
         type: "test.event",
         source: "test",
         data: %{message: "Hello from test"}
       })
       
       :ok = Bus.publish(bus, signal)
       
       # Should receive signal through sensor
       assert_receive {:signal, {:ok, received_signal}}, 5000
       assert received_signal.data == signal.data
       assert received_signal.source =~ "bus_sensor"
     end
     
     test "router pattern matching for agents" do
       alias Jido.Signal.Router
       
       router = Router.new()
       agent_id = "test_agent_123"
       
       # Add agent routes
       router = Router.add_agent_routes(router, agent_id, :test_handler)
       
       # Test various signal types
       test_cases = [
         {"jido.agent.cmd.run", true},
         {"jido.agent.test_agent_123.status", true},
         {"jido.agent.event.started", false},  # Not specific to this agent
         {"other.signal.type", false}
       ]
       
       for {signal_type, should_match} <- test_cases do
         signal = %Signal{type: signal_type, source: "test"}
         {:ok, handlers} = Router.route_agent_signal(router, signal)
         
         if should_match do
           assert :test_handler in handlers,
             "Expected #{signal_type} to match agent routes"
         else
           refute :test_handler in handlers,
             "Expected #{signal_type} NOT to match agent routes"
         end
       end
     end
     
     test "performance: 50% improvement for local signals" do
       # Benchmark local vs remote dispatch
       large_payload = :crypto.strong_rand_bytes(10_000)
       
       local_signal = Signal.new!(%{
         type: "benchmark.local",
         source: "bench",
         data: large_payload,
         meta: %{node: node()}
       })
       
       remote_signal = %{local_signal | meta: %{node: :remote@node}}
       
       # Measure local dispatch
       local_times = for _ <- 1..100 do
         start = System.monotonic_time(:microsecond)
         Dispatch.dispatch(local_signal, [
           {:local, target: self()},
           {:pid, target: self()}
         ])
         System.monotonic_time(:microsecond) - start
       end
       
       # Measure normal dispatch  
       normal_times = for _ <- 1..100 do
         start = System.monotonic_time(:microsecond)
         Dispatch.dispatch(remote_signal, {:pid, target: self()})
         System.monotonic_time(:microsecond) - start
       end
       
       avg_local = Enum.sum(local_times) / length(local_times)
       avg_normal = Enum.sum(normal_times) / length(normal_times)
       
       improvement = (avg_normal - avg_local) / avg_normal * 100
       
       IO.puts("Local dispatch: #{avg_local}μs")
       IO.puts("Normal dispatch: #{avg_normal}μs") 
       IO.puts("Improvement: #{improvement}%")
       
       # Should see at least 50% improvement
       assert improvement >= 50
     end
   end
   ```

2. **Create Test Agent**
   Create `test/support/test_agent.ex`:

   ```elixir
   defmodule TestAgent do
     @moduledoc false
     use Jido.Agent,
       name: "test_agent",
       description: "Agent for testing signal integration"
     
     defstruct [:name, :last_signal]
     
     @impl true
     def new(opts) do
       {:ok, struct(__MODULE__, opts)}
     end
     
     def handle_signal(signal, state) do
       {:ok, %{state | last_signal: signal}}
     end
     
     def get_last_signal(state) do
       {:ok, state.last_signal}
     end
   end
   ```

3. **Add Performance Benchmark**
   Create `test/jido/signal_benchmark.exs`:

   ```elixir
   defmodule Jido.SignalBenchmark do
     alias Jido.Signal
     alias Jido.Signal.Dispatch
     
     def run do
       Benchee.run(%{
         "local_dispatch" => fn input ->
           Dispatch.dispatch(input, [
             {:local, target: self()},
             {:pid, target: self()}
           ])
         end,
         "normal_dispatch" => fn input ->
           Dispatch.dispatch(input, {:pid, target: self()})
         end,
         "bus_publish" => fn input ->
           {:ok, bus} = Bus.start_link()
           Bus.publish(bus, input)
           Bus.stop(bus)
         end
       }, inputs: %{
         "small_signal" => create_signal(100),
         "medium_signal" => create_signal(10_000),
         "large_signal" => create_signal(100_000)
       })
     end
     
     defp create_signal(size) do
       Signal.new!(%{
         type: "benchmark.test",
         source: "benchmark",
         data: :crypto.strong_rand_bytes(size)
       })
     end
   end
   ```

## Key Test Scenarios
1. **End-to-end signal flow**: Agent → Bus → Sensor → Agent
2. **Local optimization**: Same-node signals use fast path
3. **Circular dependency**: Bus sensor works without issues
4. **Router patterns**: Agent-specific routing works
5. **Performance**: 50% improvement achieved
6. **Error handling**: Proper error propagation
7. **Concurrency**: Multiple agents communicating

## Success Criteria
- All integration tests pass
- No circular dependency errors
- Performance improvement ≥ 50% for local signals
- Bus sensor successfully receives and forwards signals
- Agent routing patterns work correctly
- No race conditions or deadlocks
- Memory usage remains stable

## Running the Tests
```bash
# Run all tests
mix test

# Run only integration tests
mix test test/jido/signal_integration_test.exs

# Run with coverage
mix test --cover

# Run benchmarks
mix run test/jido/signal_benchmark.exs
```