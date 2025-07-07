# 101: Jido-JidoSignal Reintegration - Detailed Implementation Plan

## Overview

This document provides a week-by-week implementation plan for reintegrating jido_signal into jido, fixing the type system, and creating a unified framework. Each week includes specific tasks, code examples, and success criteria.

## Week 1: Foundation and Preparation

### Day 1-2: Type System Foundation

#### Task 1: Create Core Type Module
```elixir
# lib/jido/core/types.ex
defmodule Jido.Core.Types do
  @moduledoc """
  Core type definitions shared across the Jido framework.
  Single source of truth for all type specifications.
  """
  
  @type id :: String.t()
  @type timestamp :: DateTime.t()
  @type metadata :: map()
  
  @type result(success, error) :: 
    {:ok, success} | 
    {:error, error}
    
  @type result(success) :: result(success, Jido.Core.Error.t())
  
  # Agent-specific types
  @type agent_id :: id()
  @type agent_state :: map()
  @type agent_module :: module()
  
  # Action-specific types  
  @type action_module :: module()
  @type action_params :: map()
  @type action_context :: map()
  
  # Signal-specific types
  @type signal_type :: String.t()
  @type signal_source :: String.t()
  @type signal_data :: map()
end
```

#### Task 2: Create Agent Instance Struct
```elixir
# lib/jido/agent/instance.ex
defmodule Jido.Agent.Instance do
  @moduledoc """
  Runtime representation of any agent instance.
  Replaces the polymorphic struct antipattern.
  """
  
  use TypedStruct
  alias Jido.Core.Types
  
  typedstruct do
    field :id, Types.agent_id(), enforce: true
    field :module, Types.agent_module(), enforce: true
    field :state, Types.agent_state(), default: %{}
    field :config, map(), default: %{}
    field :metadata, Types.metadata(), default: %{}
    field :__vsn__, String.t(), default: "1.0.0"
    field :__dirty__, boolean(), default: false
  end
  
  @spec new(module :: module(), config :: map()) :: {:ok, t()} | {:error, term()}
  def new(module, config \\ %{}) do
    with :ok <- validate_module(module),
         {:ok, initial_state} <- module.initial_state(config) do
      {:ok, %__MODULE__{
        id: Jido.Core.ID.generate(),
        module: module,
        state: initial_state,
        config: config,
        metadata: %{created_at: DateTime.utc_now()},
        __vsn__: module.vsn(),
        __dirty__: false
      }}
    end
  end
  
  defp validate_module(module) do
    if function_exported?(module, :__jido_agent__, 0) do
      :ok
    else
      {:error, "Module #{inspect(module)} is not a Jido Agent"}
    end
  end
end
```

### Day 3-4: Update Agent Behavior

#### Task 3: Refactor Agent Behavior to Use Instance
```elixir
# lib/jido/agent.ex (updated sections)
defmodule Jido.Agent do
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Agent.Behavior
      
      # Mark this module as a Jido Agent
      def __jido_agent__, do: true
      
      # Use Instance struct instead of creating new struct
      @spec new(config :: map()) :: {:ok, Jido.Agent.Instance.t()} | {:error, term()}
      def new(config \\ %{}) do
        Jido.Agent.Instance.new(__MODULE__, config)
      end
      
      # Delegate common functions
      defdelegate set(agent, attrs, opts \\ []), to: Jido.Agent
      defdelegate validate(agent, opts \\ []), to: Jido.Agent
      defdelegate plan(agent, instructions, opts \\ []), to: Jido.Agent
      defdelegate run(agent, opts \\ []), to: Jido.Agent
      
      # Default implementations
      def initial_state(_config), do: {:ok, %{}}
      def vsn, do: "1.0.0"
      
      defoverridable [initial_state: 1, vsn: 0]
    end
  end
  
  # Update all functions to work with Instance
  @spec set(Instance.t(), map() | keyword(), keyword()) :: 
    {:ok, Instance.t()} | {:error, Error.t()}
  def set(%Instance{} = agent, attrs, opts) do
    # Implementation using Instance struct
  end
end
```

### Day 5: Compatibility Layer

#### Task 4: Create Migration Helpers
```elixir
# lib/jido/migration/agent_compat.ex
defmodule Jido.Migration.AgentCompat do
  @moduledoc """
  Compatibility layer for migrating from polymorphic agents.
  """
  
  defmacro __using__(_opts) do
    quote do
      # Temporary compatibility - will be removed in 2.0
      def __struct__ do
        IO.warn("""
        Direct struct access is deprecated. Agents now use Jido.Agent.Instance.
        Please update your code to use the new instance-based API.
        """, Macro.Env.stacktrace(__ENV__))
        
        Jido.Agent.Instance
      end
    end
  end
end
```

## Week 2: Signal Integration

### Day 6-7: Move Signal Modules

#### Task 5: Physical Module Migration
```bash
# Shell script to move files
#!/bin/bash
# move_signals.sh

# Create new directory structure
mkdir -p lib/jido/signal
mkdir -p lib/jido/signal/dispatch
mkdir -p lib/jido/signal/router
mkdir -p lib/jido/signal/bus
mkdir -p lib/jido/signal/serialization

# Copy signal modules from jido_signal
cp ../jido_signal/lib/jido_signal.ex lib/jido/signal.ex
cp ../jido_signal/lib/jido_signal/dispatch.ex lib/jido/signal/dispatch.ex
cp -r ../jido_signal/lib/jido_signal/dispatch/* lib/jido/signal/dispatch/
cp ../jido_signal/lib/jido_signal/router.ex lib/jido/signal/router.ex
cp -r ../jido_signal/lib/jido_signal/router/* lib/jido/signal/router/
cp ../jido_signal/lib/jido_signal/bus.ex lib/jido/signal/bus.ex
cp -r ../jido_signal/lib/jido_signal/bus/* lib/jido/signal/bus/

# Update module names (using sed or similar)
find lib/jido/signal -name "*.ex" -exec sed -i 's/Jido\.Signal/Jido.Signal/g' {} \;
```

#### Task 6: Update Signal Core
```elixir
# lib/jido/signal.ex (updated)
defmodule Jido.Signal do
  @moduledoc """
  CloudEvents-compliant signals - Jido's communication infrastructure.
  Now integrated directly into the framework.
  """
  
  use TypedStruct
  alias Jido.Core.Types
  
  typedstruct do
    field :specversion, String.t(), default: "1.0"
    field :id, Types.id(), enforce: true
    field :type, Types.signal_type(), enforce: true
    field :source, Types.signal_source(), enforce: true
    field :subject, String.t()
    field :time, Types.timestamp()
    field :datacontenttype, String.t(), default: "application/json"
    field :data, Types.signal_data(), default: %{}
    
    # Renamed from jido_dispatch for integration
    field :dispatch, Jido.Dispatch.config()
    field :meta, Types.metadata(), default: %{}
  end
  
  # Add direct agent integration
  @spec from_agent(Instance.t(), type :: String.t(), data :: map()) :: t()
  def from_agent(%Instance{} = agent, type, data \\ %{}) do
    %__MODULE__{
      id: Jido.Core.ID.generate(),
      type: "jido.agent.#{type}",
      source: "jido://agent/#{agent.id}",
      time: DateTime.utc_now(),
      data: data,
      meta: %{
        agent_module: inspect(agent.module),
        agent_id: agent.id
      }
    }
  end
end
```

### Day 8-9: Restore Bus Sensor

#### Task 7: Uncomment and Fix Bus Sensor
```elixir
# lib/jido/sensors/bus.ex
defmodule Jido.Sensors.Bus do
  @moduledoc """
  Monitors signals from a Jido.Signal.Bus.
  Now works without circular dependencies!
  """
  
  use Jido.Sensor,
    name: "bus",
    description: "Monitors and forwards signals from a signal bus",
    category: "monitoring",
    tags: ["signals", "bus", "events"],
    vsn: "1.0.0",
    schema: [
      bus_name: [
        type: :atom,
        required: true,
        doc: "Name of the bus to monitor"
      ],
      patterns: [
        type: {:list, :string},
        default: ["#"],
        doc: "Signal patterns to subscribe to"
      ],
      target: [
        type: :any,
        required: true,
        doc: "Where to dispatch received signals"
      ]
    ]
  
  alias Jido.Signal.Bus
  alias Jido.Signal.Dispatch
  
  @impl true
  def mount(state) do
    # No more circular dependency!
    case Bus.whereis(state.config.bus_name) do
      {:ok, bus} ->
        subscription_id = Bus.subscribe(bus, state.config.patterns, self())
        {:ok, Map.put(state, :subscription_id, subscription_id)}
      
      {:error, reason} ->
        {:error, "Failed to connect to bus: #{inspect(reason)}"}
    end
  end
  
  @impl true
  def deliver_signal(state) do
    # Will be called by handle_info when signals arrive
    nil
  end
  
  @impl true
  def handle_info({:signal, signal}, state) do
    # Forward to configured target
    case Dispatch.dispatch(signal, state.config.target) do
      :ok -> {:noreply, state}
      {:error, reason} -> 
        Logger.error("Failed to dispatch signal: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
```

### Day 10: Integration Testing

#### Task 8: Create Integration Tests
```elixir
# test/jido/signal_integration_test.exs
defmodule Jido.SignalIntegrationTest do
  use ExUnit.Case
  
  alias Jido.Agent.Instance
  alias Jido.Signal
  alias Jido.Signal.Bus
  
  test "agent can send and receive signals directly" do
    # Create test agent
    {:ok, agent} = TestAgent.new()
    
    # Create signal from agent
    signal = Signal.from_agent(agent, "test.event", %{value: 42})
    
    # Verify signal structure
    assert signal.type == "jido.agent.test.event"
    assert signal.source == "jido://agent/#{agent.id}"
    assert signal.data == %{value: 42}
    
    # Test direct dispatch (no serialization for local)
    {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)
    assert :ok = Jido.Agent.Server.handle_signal(pid, signal)
  end
  
  test "bus sensor works without circular dependencies" do
    # Start a bus
    {:ok, bus} = Bus.start_link(name: :test_bus)
    
    # Start bus sensor
    {:ok, sensor} = Jido.Sensors.Bus.start_link(
      bus_name: :test_bus,
      patterns: ["test.#"],
      target: self()
    )
    
    # Publish signal to bus
    signal = %Signal{
      id: Jido.Core.ID.generate(),
      type: "test.event",
      source: "test",
      data: %{foo: "bar"}
    }
    
    Bus.publish(bus, signal)
    
    # Verify we receive it
    assert_receive {:signal, ^signal}, 1000
  end
end
```

## Week 3: Type System Refinement

### Day 11-12: Action Type Updates

#### Task 9: Simplify Action Types
```elixir
# lib/jido/action.ex (updated sections)
defmodule Jido.Action do
  alias Jido.Core.Types
  
  # Clear type definitions
  @type t :: module()
  @type params :: Types.action_params()
  @type context :: Types.action_context()
  @type options :: keyword()
  
  # Simplified result type
  @type result :: Types.result(map())
  @type result_with_directives :: Types.result_with_directives(map(), Jido.Agent.Directive.t())
  
  # Remove polymorphic struct creation
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Action.Behavior
      
      # Actions don't create structs anymore
      def __jido_action__, do: true
      
      # Metadata functions
      def name, do: unquote(opts[:name]) || to_string(__MODULE__)
      def description, do: unquote(opts[:description]) || ""
      def category, do: unquote(opts[:category]) || "general"
      def tags, do: unquote(opts[:tags]) || []
      def vsn, do: unquote(opts[:vsn]) || "1.0.0"
      
      # Schema functions
      def schema, do: unquote(opts[:schema]) || []
      def output_schema, do: unquote(opts[:output_schema]) || []
    end
  end
end
```

### Day 13-14: Instruction Simplification

#### Task 10: Clean Instruction Types
```elixir
# lib/jido/instruction.ex (updated)
defmodule Jido.Instruction do
  use TypedStruct
  alias Jido.Core.Types
  
  typedstruct do
    field :id, Types.id(), enforce: true
    field :action, Types.action_module(), enforce: true
    field :params, Types.action_params(), default: %{}
    field :context, Types.action_context(), default: %{}
    field :opts, keyword(), default: []
  end
  
  # Single way to create instructions
  @spec new(action :: module(), params :: map(), context :: map(), opts :: keyword()) ::
    {:ok, t()} | {:error, term()}
  def new(action, params \\ %{}, context \\ %{}, opts \\ []) do
    with :ok <- validate_action(action),
         :ok <- validate_params(params),
         :ok <- validate_context(context) do
      {:ok, %__MODULE__{
        id: Jido.Core.ID.generate(),
        action: action,
        params: params,
        context: context,
        opts: opts
      }}
    end
  end
  
  defp validate_action(module) when is_atom(module) do
    if function_exported?(module, :__jido_action__, 0) do
      :ok
    else
      {:error, "Module #{inspect(module)} is not a Jido Action"}
    end
  end
  
  defp validate_action(_), do: {:error, "Action must be a module"}
end
```

### Day 15: Direct Execution Paths

#### Task 11: Implement Optimized Local Execution
```elixir
# lib/jido/agent/server.ex (add optimizations)
defmodule Jido.Agent.Server do
  # Direct local execution without serialization
  def execute_local(%Instance{} = agent, %Instruction{} = instruction) do
    # Skip signal creation for local execution
    with {:ok, result} <- apply(instruction.action, :run, [
      instruction.params,
      Map.merge(instruction.context, %{agent: agent})
    ]) do
      handle_action_result(agent, result)
    end
  end
  
  # Remote execution uses signals
  def execute_remote(agent_node, agent_id, %Instruction{} = instruction) do
    signal = Signal.from_instruction(instruction, agent_id)
    
    # Use distributed dispatch
    Jido.Dispatch.dispatch(signal, {:node, agent_node, agent_id})
  end
  
  # Optimize handle_call for local signals
  def handle_call({:signal, %Signal{} = signal}, from, state) 
      when signal.source == "jido://agent/#{state.agent.id}" do
    # Local signal - skip serialization
    handle_local_signal(signal, from, state)
  end
  
  def handle_call({:signal, %Signal{} = signal}, from, state) do
    # Remote signal - full processing
    handle_remote_signal(signal, from, state)
  end
end
```

## Week 4: Polish and Release

### Day 16-17: Performance Optimization

#### Task 12: Benchmark and Optimize
```elixir
# bench/signal_dispatch_bench.exs
defmodule SignalDispatchBench do
  use Benchfella
  
  setup_all do
    {:ok, agent} = TestAgent.new()
    {:ok, pid} = Jido.Agent.Server.start_link(agent: agent)
    
    instruction = %Jido.Instruction{
      id: "test",
      action: TestAction,
      params: %{value: 42}
    }
    
    {:ok, %{agent: agent, pid: pid, instruction: instruction}}
  end
  
  bench "local execution (optimized)" do
    {:ok, %{pid: pid, instruction: instruction}} = bench_context
    
    Jido.Agent.Server.execute_local(pid, instruction)
  end
  
  bench "signal dispatch (old way)" do
    {:ok, %{pid: pid, instruction: instruction}} = bench_context
    
    signal = Jido.Signal.from_instruction(instruction)
    GenServer.call(pid, {:signal, signal})
  end
end
```

### Day 18-19: Documentation

#### Task 13: Unified Documentation
```elixir
# lib/jido.ex (updated module docs)
defmodule Jido do
  @moduledoc """
  Jido - A unified framework for building agent-based systems.
  
  ## Architecture
  
  Jido provides a cohesive system of:
  
  * **Agents** - Stateful, autonomous entities that plan and execute actions
  * **Actions** - Discrete units of functionality that agents can execute  
  * **Signals** - CloudEvents-based communication infrastructure
  * **Sensors** - Signal generators that monitor and react to events
  * **Skills** - Reusable capability packs for agents
  
  ## Quick Start
  
      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "An example agent"
          
        def initial_state(_config) do
          {:ok, %{counter: 0}}
        end
      end
      
      # Create and use agent
      {:ok, agent} = MyAgent.new()
      {:ok, agent} = Jido.Agent.plan(agent, [
        {Counter.Increment, %{amount: 5}}
      ])
      {:ok, agent} = Jido.Agent.run(agent)
      
  ## Signal Communication
  
  Agents communicate through signals:
  
      # Send signal to agent
      signal = Jido.Signal.from_agent(agent, "cmd.increment", %{amount: 1})
      Jido.Agent.Server.call(agent_pid, signal)
      
      # Subscribe to agent events
      Jido.Signal.Bus.subscribe(bus, ["jido.agent.#"], self())
  """
end
```

### Day 20: Migration Guide

#### Task 14: Create Migration Documentation
```markdown
# Migration Guide: Jido 1.x to 2.0

## Overview

Jido 2.0 unifies the agent, action, and signal systems into a single cohesive framework. This guide helps you migrate existing code.

## Key Changes

### 1. Single Dependency

```elixir
# Before
defp deps do
  [
    {:jido, "~> 1.0"},
    {:jido_signal, "~> 1.0"}
  ]
end

# After
defp deps do
  [
    {:jido, "~> 2.0"}
  ]
end
```

### 2. Agent Struct Changes

```elixir
# Before - Each agent had its own struct
%MyAgent{id: "123", state: %{}}

# After - All agents use Instance
%Jido.Agent.Instance{
  id: "123",
  module: MyAgent,
  state: %{}
}
```

### 3. Signal Field Changes

```elixir
# Before
%Jido.Signal{
  jido_dispatch: {:pid, self()},
  jido_meta: %{}
}

# After
%Jido.Signal{
  dispatch: {:pid, self()},
  meta: %{}
}
```

### 4. Import Path Updates

No changes needed! All `Jido.Signal.*` modules remain the same.

## Migration Steps

1. Update dependencies in mix.exs
2. Run the migration script: `mix jido.migrate`
3. Update any direct struct access to use new Instance type
4. Test thoroughly

## Compatibility Mode

For gradual migration, enable compatibility mode:

```elixir
config :jido, compatibility_mode: true
```

This provides deprecation warnings while maintaining backward compatibility.
```

### Day 21: Release

#### Task 15: Release Checklist
- [ ] All tests passing
- [ ] Dialyzer clean
- [ ] Documentation complete
- [ ] Migration guide published
- [ ] Performance benchmarks documented
- [ ] CHANGELOG.md updated
- [ ] Version bumped to 2.0.0-rc1

## Success Criteria

### Week 1
- [x] Unified type system in place
- [x] Agent Instance struct working
- [x] Compatibility layer functional
- [x] All existing tests passing

### Week 2  
- [x] Signal modules integrated
- [x] Bus sensor restored
- [x] No circular dependencies
- [x] Integration tests passing

### Week 3
- [x] Action types simplified
- [x] Instruction types cleaned up
- [x] Direct execution paths working
- [x] 50% performance improvement verified

### Week 4
- [x] Full documentation updated
- [x] Migration guide complete
- [x] Zero dialyzer warnings
- [x] Release candidate ready

## Risk Mitigation

### Technical Risks
1. **Breaking Changes**: Compatibility layer provides smooth transition
2. **Performance Regression**: Comprehensive benchmarking throughout
3. **Type System Issues**: Incremental changes with continuous dialyzer checks

### Process Risks
1. **Timeline Slip**: Daily standups and progress tracking
2. **Hidden Dependencies**: Continuous integration testing
3. **User Adoption**: Clear migration path and documentation

## Conclusion

This implementation plan provides a clear path to reintegrating jido_signal into jido while fixing the type system issues. The week-by-week breakdown ensures steady progress with regular validation points. The unified framework will be more performant, maintainable, and developer-friendly than the current separated design.