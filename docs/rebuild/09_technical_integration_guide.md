# Technical Integration Guide: Merging the Libraries

## Overview

This guide provides detailed technical steps for merging jido_action and jido_signal back into jido, creating a unified library with improved architecture and performance.

## Pre-Integration Analysis

### Current Package Dependencies

```elixir
# jido/mix.exs
defp deps do
  [
    {:jido_signal, "~> 1.0.0"},
    # jido_action is NOT currently a dependency (duplicate code instead)
    {:ecto, "~> 3.11", optional: true},
    {:phoenix_pubsub, "~> 2.1", optional: true},
    # ... other deps
  ]
end

# jido_action/mix.exs  
defp deps do
  [
    {:uniq, "~> 0.6"},
    {:phoenix_pubsub, "~> 2.1", optional: true},
    # No dependency on jido or jido_signal
  ]
end

# jido_signal/mix.exs
defp deps do
  [
    {:uniq, "~> 0.6"},
    {:phoenix_pubsub, "~> 2.1", optional: true},
    # No dependency on jido or jido_action
  ]
end
```

### Code Overlap Analysis

```elixir
# Duplicate implementations exist:
jido/lib/jido/action.ex          ≈ jido_action/lib/jido_action.ex
jido/lib/jido/instruction.ex     ≈ jido_action/lib/jido_instruction.ex  
jido/lib/jido/exec.ex            ≈ jido_action/lib/jido_action/exec.ex
jido/lib/jido/actions/*          ≈ jido_action/lib/jido_tools/*
```

## Integration Steps

### Step 1: Prepare Unified Structure

```bash
# In jido directory
cd jido

# Create new structure
mkdir -p lib/jido/{action,signal,core}
mkdir -p lib/jido/action/{exec,tool}
mkdir -p lib/jido/signal/{dispatch,router,bus}
```

### Step 2: Merge Core Components

#### 2.1 Unify Error Handling

```elixir
# lib/jido/core/error.ex
defmodule Jido.Error do
  @moduledoc """
  Unified error handling combining all error types
  """
  
  defexception [:type, :message, :details, :stacktrace]
  
  @type error_type :: 
    # From jido
    :invalid_agent | :invalid_action | :execution_error |
    :validation_error | :initialization_error | :runtime_error |
    :config_error | :timeout | :task_failed | :compensation_failed |
    :serialization_error | :deserialization_error | :dispatch_error |
    :directive_error |
    # From jido_signal  
    :invalid_signal | :routing_error | :handler_error |
    :subscription_error | :publish_error | :bus_error |
    # From jido_action
    :invalid_params | :missing_required_param | :invalid_param_type |
    :action_not_found | :output_validation_error |
    # Generic
    :unknown_error
    
  @type t :: %__MODULE__{
    type: error_type(),
    message: String.t(),
    details: map(),
    stacktrace: Exception.stacktrace() | nil
  }
  
  # Unified constructor
  def new(type, message, details \\ %{}) do
    %__MODULE__{
      type: type,
      message: message,
      details: details,
      stacktrace: if(details[:include_stacktrace], do: __STACKTRACE__, else: nil)
    }
  end
  
  # Compatibility helpers during migration
  def from_action_error(%{type: type, message: msg, details: details}) do
    new(type, msg, details)
  end
  
  def from_signal_error(%{type: type, message: msg}) do
    new(type, msg)
  end
end
```

#### 2.2 Unify ID Generation

```elixir
# lib/jido/core/id.ex
defmodule Jido.ID do
  @moduledoc """
  Unified ID generation using UUID v7
  """
  
  # Single source of truth for ID generation
  def generate(prefix \\ nil) do
    id = Uniq.UUID.uuid7()
    
    if prefix do
      "#{prefix}_#{id}"
    else
      id
    end
  end
  
  # Compatibility during migration
  defdelegate generate_id(), to: __MODULE__, as: :generate
end
```

### Step 3: Merge Action System

#### 3.1 Merge Action Behavior

```elixir
# lib/jido/action/action.ex
defmodule Jido.Action do
  @moduledoc """
  Unified action behavior combining jido and jido_action implementations
  """
  
  # Use the more complete implementation from jido_action
  # but with unified types
  
  @type t :: module()
  @type params :: map()
  @type context :: map()
  @type result :: {:ok, map()} | {:ok, map(), directive_or_directives()} | {:error, Jido.Error.t()}
  @type directive_or_directives :: Jido.Agent.Directive.t() | [Jido.Agent.Directive.t()]
  
  @callback run(params(), context()) :: result()
  @callback describe() :: map()
  @callback schema() :: NimbleOptions.t()
  
  # Optional callbacks
  @callback on_before_validate_params(params()) :: params()
  @callback on_after_validate_params(params()) :: params()
  @callback on_before_run(params(), context()) :: {params(), context()}
  @callback on_after_run(result(), params(), context()) :: result()
  @callback on_error(Jido.Error.t(), params(), context(), keyword()) :: 
    {:ok, :compensated} | {:ok, :no_compensation} | {:error, Jido.Error.t()}
  
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Action
      
      # Implementation combining best of both versions
      # ... (merged implementation)
    end
  end
end
```

#### 3.2 Merge Execution Engine

```elixir
# lib/jido/action/exec.ex
defmodule Jido.Action.Exec do
  @moduledoc """
  Unified execution engine with optimizations
  """
  
  alias Jido.{Action, Agent, Signal, Error, Telemetry}
  
  @default_timeout Application.compile_env(:jido, :default_action_timeout, 5_000)
  @max_retries Application.compile_env(:jido, :default_max_retries, 3)
  
  def run(action, params, context, opts \\ []) do
    # Integrated execution with direct agent access
    with {:ok, action_mod} <- validate_action(action),
         {:ok, params} <- validate_params(action_mod, params),
         {:ok, context} <- prepare_context(context, opts) do
      
      # Check if we're in an agent context for optimizations
      case context[:agent] do
        %Agent.Instance{} = agent ->
          # Optimized agent execution path
          execute_in_agent_context(agent, action_mod, params, context, opts)
          
        nil ->
          # Standard execution path
          execute_standard(action_mod, params, context, opts)
      end
    end
  end
  
  defp execute_in_agent_context(agent, action, params, context, opts) do
    # Skip serialization for local execution
    if local_action?(agent, action) do
      # Direct execution
      result = apply(action, :run, [params, context])
      handle_result(result, agent)
    else
      # Signal-based execution for remote actions
      signal = Signal.command(agent, :run_action, %{
        action: action,
        params: params
      })
      Signal.dispatch(signal, agent.router)
    end
  end
end
```

#### 3.3 Migrate Tools/Actions

```elixir
# Move and consolidate actions
# jido/lib/jido/actions/* → jido/lib/jido/tools/*
# jido_action/lib/jido_tools/* → jido/lib/jido/tools/*

# lib/jido/tools/basic.ex
defmodule Jido.Tools.Basic do
  @moduledoc "Basic actions consolidated from both libraries"
  
  defmodule Sleep do
    use Jido.Action,
      name: "tools.basic.sleep",
      description: "Sleep for specified duration",
      schema: [
        duration: [type: :non_neg_integer, required: true]
      ]
    
    def run(%{duration: duration}, _context) do
      Process.sleep(duration)
      {:ok, %{slept_for: duration}}
    end
  end
  
  # ... other basic actions
end
```

### Step 4: Integrate Signal System

#### 4.1 Move Signal Core

```elixir
# lib/jido/signal/signal.ex
defmodule Jido.Signal do
  @moduledoc """
  Integrated signal system for agent communication
  """
  
  use TypedStruct
  
  alias Jido.{Agent, Error, ID}
  
  # CloudEvents spec + Jido extensions
  typedstruct do
    field :specversion, String.t(), default: "1.0.2"
    field :id, String.t(), default: &ID.generate/0
    field :type, String.t(), enforce: true
    field :source, String.t(), enforce: true
    field :subject, String.t()
    field :time, DateTime.t(), default: &DateTime.utc_now/0
    field :datacontenttype, String.t(), default: "application/json"
    field :data, map(), default: %{}
    
    # Jido extensions - now properly integrated
    field :jido_agent, Agent.Instance.t()
    field :jido_routing, routing(), default: :local
    field :jido_priority, priority(), default: :normal
  end
  
  @type routing :: :local | :remote | {:pubsub, String.t()} | {:pattern, String.t()}
  @type priority :: :low | :normal | :high | :critical
  
  # Type-safe signal builders integrated with agents
  def from_agent(%Agent.Instance{} = agent, type, data \\ %{}) do
    %__MODULE__{
      type: "jido.agent.#{type}",
      source: "jido://agent/#{agent.module}/#{agent.id}",
      data: data,
      jido_agent: agent,
      jido_routing: determine_routing(agent, type)
    }
  end
end
```

#### 4.2 Integrate Router with Agent System

```elixir
# lib/jido/signal/router.ex  
defmodule Jido.Signal.Router do
  @moduledoc """
  Signal router with agent-aware optimizations
  """
  
  alias Jido.{Signal, Agent}
  
  # Direct agent-to-agent routing
  def route(%Signal{jido_routing: :local, jido_agent: %{id: agent_id}} = signal) do
    # Optimized local delivery
    case Agent.Registry.lookup(agent_id) do
      {:ok, pid} -> 
        send(pid, {:signal, signal})
        {:ok, :delivered_local}
      
      :error ->
        {:error, Error.new(:agent_not_found, "Agent #{agent_id} not running")}
    end
  end
  
  # Pattern-based routing with agent context
  def route(%Signal{jido_routing: {:pattern, pattern}} = signal) do
    # Use integrated agent registry for pattern matching
    matching_agents = Agent.Registry.match_pattern(pattern)
    
    for {_id, pid} <- matching_agents do
      send(pid, {:signal, signal})
    end
    
    {:ok, {:delivered_to, length(matching_agents)}}
  end
end
```

### Step 5: Fix Circular Dependencies

#### 5.1 Restore Bus Sensor

```elixir
# lib/jido/sensors/bus_sensor.ex
defmodule Jido.Sensors.Bus do
  @moduledoc """
  Bus sensor - restored with full integration!
  """
  
  use Jido.Sensor
  
  alias Jido.{Signal, Agent}
  
  # Now has direct access to Signal.Bus
  def init(opts) do
    bus = Keyword.get(opts, :bus, Signal.Bus)
    patterns = Keyword.get(opts, :patterns, ["**"])
    
    # Subscribe directly - no circular dependency
    :ok = Signal.Bus.subscribe(bus, patterns, self())
    
    {:ok, %{
      bus: bus,
      patterns: patterns,
      signal_count: 0,
      agents_seen: MapSet.new()
    }}
  end
  
  def handle_info({:signal, %Signal{} = signal}, state) do
    # Can access all integrated types
    state = state
    |> update_in([:signal_count], &(&1 + 1))
    |> track_agent(signal.jido_agent)
    
    # Forward to agent if configured
    if state[:forward_to_agent] do
      Agent.Server.handle_signal(state.agent, signal)
    end
    
    {:noreply, state}
  end
  
  defp track_agent(state, %Agent.Instance{id: id}) do
    update_in(state, [:agents_seen], &MapSet.put(&1, id))
  end
  defp track_agent(state, nil), do: state
end
```

### Step 6: Update Configuration

#### 6.1 Unified Application

```elixir
# lib/jido/application.ex
defmodule Jido.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Core supervisor
      {Task.Supervisor, name: Jido.TaskSupervisor},
      
      # Agent registry
      {Registry, keys: :unique, name: Jido.Agent.Registry},
      
      # Signal bus (if configured)
      signal_bus_spec(),
      
      # PubSub (if configured)
      pubsub_spec(),
      
      # Telemetry
      {Jido.Telemetry, []}
    ]
    |> Enum.filter(& &1)
    
    opts = [strategy: :one_for_one, name: Jido.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp signal_bus_spec do
    if Application.get_env(:jido, :enable_signal_bus, true) do
      {Jido.Signal.Bus, name: Jido.Signal.Bus}
    end
  end
  
  defp pubsub_spec do
    if pubsub = Application.get_env(:jido, :pubsub) do
      {Phoenix.PubSub, name: pubsub}
    end
  end
end
```

#### 6.2 Unified Configuration

```elixir
# config/config.exs
config :jido,
  # Agent configuration
  default_agent_timeout: 5_000,
  agent_registry: Jido.Agent.Registry,
  
  # Action configuration  
  default_action_timeout: 5_000,
  max_action_retries: 3,
  
  # Signal configuration
  enable_signal_bus: true,
  signal_serializer: Jido.Signal.Serializer.Json,
  pubsub: MyApp.PubSub,
  
  # Unified telemetry
  telemetry_prefix: [:jido]
```

### Step 7: Migration Helpers

#### 7.1 Compatibility Modules

```elixir
# lib/jido/compat.ex
defmodule JidoAction do
  @moduledoc """
  Compatibility shim - remove in v3.0
  """
  @deprecated "Use Jido.Action instead"
  
  defdelegate __using__(opts), to: Jido.Action
end

defmodule JidoSignal do
  @moduledoc """
  Compatibility shim - remove in v3.0
  """
  @deprecated "Use Jido.Signal instead"
  
  defdelegate new(attrs), to: Jido.Signal
  defdelegate new!(attrs), to: Jido.Signal
end

defmodule JidoTools do
  @moduledoc """
  Compatibility shim - remove in v3.0
  """
  @deprecated "Use Jido.Tools instead"
  
  # Forward all module lookups
  def __MODULE__.unquote(:"$handle_undefined_function")(name, args) do
    apply(Jido.Tools, name, args)
  end
end
```

### Step 8: Update Tests

#### 8.1 Consolidated Test Structure

```elixir
# test/support/test_case.ex
defmodule Jido.TestCase do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      import Jido.TestHelpers
      alias Jido.{Agent, Action, Signal, Error}
      
      # Common test setup
      setup do
        # Start test registry
        start_supervised!({Registry, keys: :unique, name: Jido.Test.Registry})
        
        # Start test pubsub
        start_supervised!({Phoenix.PubSub, name: Jido.Test.PubSub})
        
        :ok
      end
    end
  end
end
```

### Step 9: Performance Optimizations

#### 9.1 Integrated Fast Paths

```elixir
# lib/jido/agent/server.ex
defmodule Jido.Agent.Server do
  # Optimized message handling with integrated types
  
  def handle_call({:run_action, action, params}, from, state) do
    # Direct execution for local actions
    result = Action.Exec.run(action, params, %{agent: state.agent})
    
    case result do
      {:ok, data, directives} ->
        # Apply directives directly without signals
        new_state = apply_directives(state, directives)
        {:reply, {:ok, data}, new_state}
        
      {:ok, data} ->
        {:reply, {:ok, data}, state}
        
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  # Integrated signal handling
  def handle_info({:signal, %Signal{} = signal}, state) do
    # Fast path for agent signals
    if signal.jido_agent && signal.jido_agent.id == state.agent.id do
      handle_local_signal(signal, state)
    else
      handle_remote_signal(signal, state)
    end
  end
end
```

## Verification Checklist

After integration:

- [ ] All tests pass
- [ ] No dialyzer warnings
- [ ] Bus sensor works
- [ ] Agent-action-signal flow works
- [ ] Performance benchmarks show improvement
- [ ] Migration script works on example projects
- [ ] Documentation is updated
- [ ] Examples are updated

## Rollback Plan

If issues arise:

1. Git tags before major changes
2. Keep original packages published
3. Compatibility modules allow gradual migration
4. Feature flags for new behavior
5. Clear upgrade path documentation

## Next Steps

1. Complete integration following this guide
2. Run comprehensive test suite
3. Benchmark performance improvements
4. Update all documentation
5. Create migration guide for users
6. Plan deprecation timeline for compatibility modules