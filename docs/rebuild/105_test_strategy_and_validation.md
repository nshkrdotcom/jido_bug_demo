# 105: Test Strategy and Validation

## Overview

This document outlines the comprehensive testing strategy for the Jido-JidoSignal reintegration, including unit tests, integration tests, property-based tests, performance benchmarks, and validation procedures to ensure the migration maintains system integrity.

## Test Architecture

### 1. Test Organization Structure

```
test/
├── unit/
│   ├── core/
│   │   ├── types_test.exs
│   │   ├── error_test.exs
│   │   └── id_test.exs
│   ├── agent/
│   │   ├── instance_test.exs
│   │   ├── behavior_test.exs
│   │   └── directive_test.exs
│   ├── signal/
│   │   ├── signal_test.exs
│   │   ├── router_test.exs
│   │   └── dispatch_test.exs
│   └── action/
│       ├── action_test.exs
│       └── instruction_test.exs
├── integration/
│   ├── agent_signal_test.exs
│   ├── bus_sensor_test.exs
│   └── end_to_end_test.exs
├── property/
│   ├── type_properties_test.exs
│   └── signal_routing_test.exs
├── performance/
│   ├── signal_dispatch_bench.exs
│   └── agent_execution_bench.exs
└── support/
    ├── test_helpers.ex
    └── fixtures/
```

### 2. Test Framework Configuration

```elixir
# test/test_helper.exs
ExUnit.start(
  assert_receive_timeout: 500,
  capture_log: true,
  exclude: [:skip, :distributed],
  formatters: [ExUnit.CLIFormatter, JidoTestFormatter]
)

# Start test applications
{:ok, _} = Application.ensure_all_started(:jido)

# Configure test environment
Application.put_env(:jido, :test_mode, true)
Application.put_env(:jido, :signal_pool_size, 2)

# Load test support modules
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/test_factories.ex", __DIR__)

# Ensure consistent test ordering for CI
ExUnit.configure(seed: 0)
```

## Unit Test Specifications

### 1. Type System Tests

```elixir
# test/unit/core/types_test.exs
defmodule Jido.Core.TypesTest do
  use ExUnit.Case, async: true
  
  alias Jido.Core.Types
  alias Jido.Core.TypeValidator
  
  describe "type validation" do
    test "validates UUID v7 IDs" do
      valid_id = Jido.Core.ID.generate()
      invalid_id = "not-a-uuid"
      
      assert TypeValidator.validate(valid_id, :id) == :ok
      assert {:error, _} = TypeValidator.validate(invalid_id, :id)
    end
    
    test "validates agent_module type" do
      defmodule ValidAgent do
        use Jido.Agent
        def initial_state(_), do: {:ok, %{}}
      end
      
      assert TypeValidator.validate(ValidAgent, :agent_module) == :ok
      assert {:error, _} = TypeValidator.validate(String, :agent_module)
    end
    
    test "validates complex nested types" do
      valid_context = %{
        agent: %Jido.Agent.Instance{
          id: Jido.Core.ID.generate(),
          module: ValidAgent,
          state: %{}
        },
        timeout: 5000,
        correlation_id: Jido.Core.ID.generate()
      }
      
      assert TypeValidator.validate(valid_context, :action_context) == :ok
    end
  end
  
  describe "result types" do
    test "ok/1 creates success tuple" do
      assert Types.ok("value") == {:ok, "value"}
    end
    
    test "error/1 creates error tuple with proper type" do
      error = Jido.Core.Error.new(:validation_error, "Invalid input")
      result = Types.error(error)
      
      assert {:error, %Jido.Core.Error{type: :validation_error}} = result
    end
  end
end
```

### 2. Agent Instance Tests

```elixir
# test/unit/agent/instance_test.exs
defmodule Jido.Agent.InstanceTest do
  use ExUnit.Case, async: true
  
  alias Jido.Agent.Instance
  
  defmodule TestAgent do
    use Jido.Agent
    
    def initial_state(config) do
      {:ok, %{initialized: true, config: config}}
    end
    
    def vsn, do: "1.2.3"
  end
  
  describe "Instance creation" do
    test "creates instance with all required fields" do
      config = %{name: "test"}
      
      assert {:ok, instance} = Instance.new(TestAgent, config)
      assert %Instance{
        id: id,
        module: TestAgent,
        state: %{initialized: true, config: ^config},
        config: ^config,
        metadata: %{created_at: _},
        __vsn__: "1.2.3",
        __dirty__: false
      } = instance
      
      assert is_binary(id)
      assert byte_size(id) == 36  # UUID format
    end
    
    test "validates agent module" do
      assert {:error, "Module Elixir.String is not a Jido Agent"} = 
        Instance.new(String, %{})
    end
    
    test "handles initial_state errors" do
      defmodule FailingAgent do
        use Jido.Agent
        def initial_state(_), do: {:error, "Initialization failed"}
      end
      
      assert {:error, "Initialization failed"} = Instance.new(FailingAgent, %{})
    end
  end
  
  describe "Instance pattern matching" do
    test "works with pattern matching" do
      {:ok, instance} = Instance.new(TestAgent, %{})
      
      assert %Instance{module: TestAgent} = instance
      
      # Function head pattern matching
      assert module_name(instance) == TestAgent
    end
    
    defp module_name(%Instance{module: mod}), do: mod
  end
end
```

### 3. Signal Integration Tests

```elixir
# test/unit/signal/signal_test.exs
defmodule Jido.SignalTest do
  use ExUnit.Case, async: true
  
  alias Jido.Signal
  alias Jido.Agent.Instance
  
  setup do
    {:ok, agent} = Instance.new(TestAgent, %{name: "test"})
    {:ok, agent: agent}
  end
  
  describe "agent signal creation" do
    test "from_agent/3 creates properly formatted signal", %{agent: agent} do
      signal = Signal.from_agent(agent, "test.event", %{value: 42})
      
      assert %Signal{
        type: "jido.agent.test.event",
        source: source,
        data: %{value: 42},
        meta: meta
      } = signal
      
      assert source =~ ~r{jido://agent/.+/#{agent.id}}
      assert meta.agent_id == agent.id
      assert meta.agent_module == "Jido.Agent.InstanceTest.TestAgent"
    end
    
    test "command/3 creates command signal" do
      signal = Signal.command("agent-123", :run, %{timeout: 5000})
      
      assert %Signal{
        type: "jido.agent.cmd.run",
        source: "jido://system",
        subject: "agent-123",
        data: %{timeout: 5000},
        dispatch: {:named, _}
      } = signal
    end
    
    test "field migration from legacy format" do
      legacy = %{
        "id" => "123",
        "type" => "test",
        "source" => "test",
        "jido_dispatch" => {:pid, self()},
        "jido_meta" => %{foo: "bar"}
      }
      
      {:ok, signal} = Signal.from_map(legacy)
      
      assert signal.dispatch == {:pid, self()}
      assert signal.meta == %{foo: "bar"}
      refute Map.has_key?(signal, :jido_dispatch)
      refute Map.has_key?(signal, :jido_meta)
    end
  end
end
```

## Integration Test Specifications

### 1. Agent-Signal Integration

```elixir
# test/integration/agent_signal_test.exs
defmodule Jido.Integration.AgentSignalTest do
  use ExUnit.Case
  
  alias Jido.Agent.{Instance, Server}
  alias Jido.Signal
  alias Jido.Signal.Bus
  
  defmodule EchoAgent do
    use Jido.Agent
    
    def initial_state(_), do: {:ok, %{messages: []}}
    
    def handle_signal(%Signal{type: "echo.request"} = signal, state) do
      response = Signal.from_agent(state.agent, "echo.response", signal.data)
      {:ok, response, %{state | messages: [signal | state.messages]}}
    end
  end
  
  setup do
    {:ok, bus} = Bus.start_link(name: :test_bus)
    {:ok, agent} = EchoAgent.new()
    {:ok, server} = Server.start_link(agent: agent)
    
    {:ok, bus: bus, agent: agent, server: server}
  end
  
  test "agent receives and responds to signals", %{server: server, bus: bus} do
    # Subscribe to responses
    Bus.subscribe(bus, ["jido.agent.echo.response"], self())
    
    # Send echo request
    request = Signal.new!(%{
      type: "echo.request",
      source: "test",
      data: %{message: "Hello, Agent!"}
    })
    
    Server.call(server, request)
    
    # Verify response
    assert_receive %Signal{
      type: "jido.agent.echo.response",
      data: %{message: "Hello, Agent!"}
    }, 1000
  end
  
  test "direct local execution optimization", %{server: server} do
    # Create instruction signal with local source
    agent_id = GenServer.call(server, :get_agent_id)
    
    signal = %Signal{
      id: Jido.Core.ID.generate(),
      type: "jido.agent.instruction",
      source: "jido://agent/#{agent_id}",
      data: %{
        instruction: %Jido.Instruction{
          id: "test",
          action: TestAction,
          params: %{value: 42}
        }
      },
      meta: %{node: node()}
    }
    
    # Measure execution time
    {time, result} = :timer.tc(fn ->
      Server.call(server, signal)
    end)
    
    # Should be very fast (< 1ms) due to optimization
    assert time < 1000  # microseconds
    assert {:ok, %{value: 43}} = result
  end
end
```

### 2. Bus Sensor Integration

```elixir
# test/integration/bus_sensor_test.exs
defmodule Jido.Integration.BusSensorTest do
  use ExUnit.Case
  
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Sensors.Bus, as: BusSensor
  
  test "bus sensor works without circular dependency" do
    # Start a bus
    {:ok, bus} = Bus.start_link(name: :sensor_test_bus)
    
    # Start bus sensor
    {:ok, sensor} = BusSensor.start_link(
      bus_name: :sensor_test_bus,
      patterns: ["orders.#", "payments.#"],
      target: self()
    )
    
    # Publish signals
    signals = [
      %Signal{
        id: Jido.Core.ID.generate(),
        type: "orders.created",
        source: "shop",
        data: %{order_id: "123"}
      },
      %Signal{
        id: Jido.Core.ID.generate(),
        type: "payments.processed",
        source: "payment-gateway",
        data: %{order_id: "123", amount: 99.99}
      },
      %Signal{
        id: Jido.Core.ID.generate(),
        type: "inventory.updated",
        source: "warehouse",
        data: %{sku: "ABC123"}
      }
    ]
    
    Enum.each(signals, &Bus.publish(bus, &1))
    
    # Should receive only matching signals
    assert_receive %Signal{type: "orders.created"}
    assert_receive %Signal{type: "payments.processed"}
    refute_receive %Signal{type: "inventory.updated"}, 100
  end
  
  test "sensor handles high-volume signals" do
    {:ok, bus} = Bus.start_link(name: :volume_test_bus)
    
    {:ok, sensor} = BusSensor.start_link(
      bus_name: :volume_test_bus,
      patterns: ["#"],  # Subscribe to all
      target: self()
    )
    
    # Send 1000 signals rapidly
    signal_count = 1000
    
    Task.async_stream(1..signal_count, fn i ->
      signal = %Signal{
        id: Jido.Core.ID.generate(),
        type: "stress.test",
        source: "generator",
        data: %{index: i}
      }
      Bus.publish(bus, signal)
    end, max_concurrency: 10)
    |> Stream.run()
    
    # Verify all signals received
    received = receive_signals(signal_count, [])
    assert length(received) == signal_count
    
    # Verify order preservation per source
    indexed = Enum.map(received, & &1.data.index)
    assert length(Enum.uniq(indexed)) == signal_count
  end
  
  defp receive_signals(0, acc), do: Enum.reverse(acc)
  defp receive_signals(n, acc) do
    receive do
      %Signal{} = signal ->
        receive_signals(n - 1, [signal | acc])
    after
      1000 ->
        Enum.reverse(acc)
    end
  end
end
```

## Property-Based Testing

### 1. Type System Properties

```elixir
# test/property/type_properties_test.exs
defmodule Jido.Property.TypePropertiesTest do
  use ExUnit.Case
  use ExUnitProperties
  
  alias Jido.Agent.Instance
  alias Jido.Core.TypeValidator
  
  property "all generated IDs are valid UUID v7" do
    check all count <- integer(1..100) do
      ids = for _ <- 1..count, do: Jido.Core.ID.generate()
      
      assert Enum.all?(ids, fn id ->
        TypeValidator.validate(id, :id) == :ok
      end)
      
      # IDs should be unique
      assert length(Enum.uniq(ids)) == count
      
      # IDs should be chronologically sortable
      sorted = Enum.sort(ids)
      timestamps = Enum.map(sorted, &Jido.Core.ID.extract_timestamp/1)
      assert timestamps == Enum.sort(timestamps)
    end
  end
  
  property "Instance struct maintains invariants" do
    check all module <- constant(TestAgent),
              config <- map_of(atom(:alphanumeric), term()),
              state_updates <- list_of(map_of(atom(:alphanumeric), term())) do
      
      {:ok, instance} = Instance.new(module, config)
      
      # Apply random state updates
      final_instance = Enum.reduce(state_updates, instance, fn update, inst ->
        %{inst | state: Map.merge(inst.state, update), __dirty__: true}
      end)
      
      # Invariants that must hold
      assert final_instance.module == module
      assert final_instance.id == instance.id
      assert is_map(final_instance.state)
      assert final_instance.__vsn__ == module.vsn()
    end
  end
  
  property "signal type hierarchy is consistent" do
    check all base <- string(:alphanumeric, min_length: 1),
              segments <- list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 5) do
      
      type = Enum.join([base | segments], ".")
      signal = %Jido.Signal{
        id: Jido.Core.ID.generate(),
        type: type,
        source: "test"
      }
      
      # Type should be preserved
      assert signal.type == type
      
      # Routing should handle wildcards correctly
      patterns = [
        type,  # Exact match
        base <> ".#",  # Wildcard match
        Enum.join([base | Enum.take(segments, 1)], ".") <> ".#"  # Partial match
      ]
      
      router = Jido.Signal.Router.new!(
        Enum.map(patterns, &{&1, &1})
      )
      
      {:ok, matches} = Jido.Signal.Router.route(router, signal)
      assert length(matches) >= 1
    end
  end
end
```

### 2. Signal Routing Properties

```elixir
# test/property/signal_routing_test.exs
defmodule Jido.Property.SignalRoutingTest do
  use ExUnit.Case
  use ExUnitProperties
  
  alias Jido.Signal.Router
  
  property "wildcard patterns match correctly" do
    check all segments <- list_of(
                string(:alphanumeric, min_length: 1),
                min_length: 2,
                max_length: 5
              ) do
      
      signal_type = Enum.join(segments, ".")
      
      # Generate all valid wildcard patterns
      patterns = for i <- 0..(length(segments) - 1) do
        prefix = Enum.take(segments, i)
        if i == 0 do
          "#"
        else
          Enum.join(prefix, ".") <> ".#"
        end
      end
      
      router = Router.new!(Enum.map(patterns, &{&1, &1}))
      {:ok, matches} = Router.route(router, %{type: signal_type})
      
      # Should match at least one pattern
      assert length(matches) >= 1
      
      # Most specific pattern should have highest priority
      sorted_matches = Enum.sort_by(matches, &String.length(&1), :desc)
      assert hd(sorted_matches) == List.last(patterns)
    end
  end
  
  property "routing is deterministic" do
    check all routes <- list_of(
                {string(:alphanumeric, min_length: 1), term()},
                min_length: 1,
                max_length: 20
              ),
              signal_type <- string(:alphanumeric, min_length: 1) do
      
      router = Router.new!(routes)
      
      # Multiple routes should give same result
      results = for _ <- 1..10 do
        Router.route(router, %{type: signal_type})
      end
      
      # All results should be identical
      assert Enum.all?(results, &(&1 == hd(results)))
    end
  end
end
```

## Performance Testing

### 1. Signal Dispatch Benchmarks

```elixir
# test/performance/signal_dispatch_bench.exs
defmodule Jido.Performance.SignalDispatchBench do
  use Benchfella
  
  @signal_count 10_000
  
  setup_all do
    # Start test infrastructure
    {:ok, _} = Application.ensure_all_started(:jido)
    
    # Create test agents
    agents = for i <- 1..10 do
      {:ok, agent} = TestAgent.new(%{id: i})
      {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)
      {agent, pid}
    end
    
    # Create signals
    signals = for i <- 1..@signal_count do
      {agent, _} = Enum.random(agents)
      Jido.Signal.from_agent(agent, "bench.event", %{index: i})
    end
    
    {:ok, %{agents: agents, signals: signals}}
  end
  
  bench "local signal dispatch (optimized)" do
    {:ok, %{agents: agents, signals: signals}} = bench_context
    
    signal = Enum.random(signals)
    {_, pid} = Enum.random(agents)
    
    Jido.Agent.Server.handle_signal(pid, signal)
  end
  
  bench "remote signal dispatch (serialized)" do
    {:ok, %{signals: signals}} = bench_context
    
    signal = Enum.random(signals)
    
    # Force serialization path
    Jido.Signal.Dispatch.dispatch(signal, signal.dispatch)
  end
  
  bench "batch signal dispatch" do
    {:ok, %{signals: signals}} = bench_context
    
    batch = Enum.take_random(signals, 100)
    
    Jido.Signal.Dispatch.dispatch_batch(batch)
  end
  
  bench "signal routing (trie-based)" do
    router = build_test_router()
    signal = %Jido.Signal{type: "orders.created.premium.us-east-1"}
    
    Jido.Signal.Router.route(router, signal)
  end
  
  defp build_test_router do
    patterns = [
      {"#", :all},
      {"orders.#", :orders},
      {"orders.created.#", :created},
      {"orders.*.premium.#", :premium},
      {"*.*.*.us-east-1", :region}
    ]
    
    Jido.Signal.Router.new!(patterns)
  end
end
```

### 2. Type System Performance

```elixir
# test/performance/type_system_bench.exs
defmodule Jido.Performance.TypeSystemBench do
  use Benchfella
  
  setup_all do
    # Create instances
    instances = for i <- 1..1000 do
      {:ok, instance} = Jido.Agent.Instance.new(TestAgent, %{id: i})
      instance
    end
    
    {:ok, %{instances: instances}}
  end
  
  bench "Instance creation" do
    Jido.Agent.Instance.new(TestAgent, %{test: true})
  end
  
  bench "Instance pattern matching" do
    {:ok, %{instances: instances}} = bench_context
    instance = Enum.random(instances)
    
    case instance do
      %Jido.Agent.Instance{module: TestAgent, state: state} ->
        Map.get(state, :counter, 0)
      _ ->
        nil
    end
  end
  
  bench "Type validation" do
    {:ok, %{instances: instances}} = bench_context
    instance = Enum.random(instances)
    
    Jido.Core.TypeValidator.validate(instance, :agent_instance)
  end
  
  bench "Legacy struct detection" do
    {:ok, %{instances: instances}} = bench_context
    value = Enum.random([
      Enum.random(instances),
      %{__struct__: TestAgent, id: "123", state: %{}},
      %{id: "123", state: %{}},
      "not a struct"
    ])
    
    Jido.Agent.InstanceConverter.legacy_agent?(value)
  end
end
```

## Validation Procedures

### 1. Type Safety Validation

```elixir
# lib/jido/validation/type_safety.ex
defmodule Jido.Validation.TypeSafety do
  @moduledoc """
  Validates type safety across the system.
  """
  
  def validate_all do
    validators = [
      &validate_no_struct_confusion/0,
      &validate_consistent_types/0,
      &validate_dialyzer_clean/0,
      &validate_pattern_matches/0
    ]
    
    results = Enum.map(validators, & &1.())
    
    if Enum.all?(results, &match?(:ok, &1)) do
      {:ok, "All type validations passed"}
    else
      errors = Enum.filter(results, &match?({:error, _}, &1))
      {:error, "Type validation failed", errors}
    end
  end
  
  defp validate_no_struct_confusion do
    # Ensure no polymorphic struct usage
    case find_polymorphic_usage() do
      [] -> :ok
      issues -> {:error, "Found polymorphic struct usage", issues}
    end
  end
  
  defp validate_consistent_types do
    # Check all public APIs return consistent types
    modules = [Jido.Agent, Jido.Action, Jido.Signal]
    
    issues = Enum.flat_map(modules, fn module ->
      module.__info__(:functions)
      |> Enum.filter(fn {name, _arity} ->
        name in [:new, :create, :build]
      end)
      |> Enum.flat_map(fn {name, arity} ->
        validate_return_type(module, name, arity)
      end)
    end)
    
    if issues == [] do
      :ok
    else
      {:error, "Inconsistent return types", issues}
    end
  end
end
```

### 2. Integration Validation

```elixir
# lib/jido/validation/integration.ex
defmodule Jido.Validation.Integration do
  @moduledoc """
  Validates integration points work correctly.
  """
  
  def validate_signal_integration do
    # Test agent can send and receive signals
    with {:ok, agent} <- create_test_agent(),
         {:ok, signal} <- create_test_signal(agent),
         {:ok, result} <- send_signal_to_agent(agent, signal),
         :ok <- verify_signal_received(result) do
      :ok
    else
      error -> {:error, "Signal integration failed", error}
    end
  end
  
  def validate_bus_sensor do
    # Test bus sensor works without circular deps
    with {:ok, bus} <- start_test_bus(),
         {:ok, sensor} <- start_bus_sensor(bus),
         :ok <- publish_test_signals(bus),
         :ok <- verify_sensor_forwarding(sensor) do
      :ok
    else
      error -> {:error, "Bus sensor validation failed", error}
    end
  end
  
  def validate_performance_targets do
    benchmarks = [
      {:local_dispatch, 100},  # microseconds
      {:signal_routing, 50},
      {:instance_creation, 200}
    ]
    
    results = Enum.map(benchmarks, fn {bench, target} ->
      time = measure_benchmark(bench)
      if time <= target do
        {:ok, bench, time}
      else
        {:error, bench, "Expected <= #{target}μs, got #{time}μs"}
      end
    end)
    
    failures = Enum.filter(results, &match?({:error, _, _}, &1))
    
    if failures == [] do
      :ok
    else
      {:error, "Performance targets not met", failures}
    end
  end
end
```

### 3. Continuous Validation

```yaml
# .github/workflows/validation.yml
name: Continuous Validation

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  type-safety:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Run dialyzer
      run: mix dialyzer
    
    - name: Run type validation
      run: mix jido.validate.types

  integration:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: erlef/setup-beam@v1
    
    - name: Run integration tests
      run: mix test --only integration
    
    - name: Validate signal integration
      run: mix jido.validate.integration

  performance:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: erlef/setup-beam@v1
    
    - name: Run benchmarks
      run: mix bench
    
    - name: Validate performance targets
      run: mix jido.validate.performance
    
    - name: Upload results
      uses: actions/upload-artifact@v3
      with:
        name: benchmark-results
        path: bench/snapshots/
```

This comprehensive test strategy ensures the reintegration maintains correctness, performance, and reliability throughout the migration process.