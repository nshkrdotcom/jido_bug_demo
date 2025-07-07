# Fixing Jido's Type System Issues - Single Struct Solution

## Overview

This document provides the implementation plan to fix jido's fundamental type system issue: the polymorphic struct anti-pattern that creates dialyzer violations.

## The Core Problem

### Current Broken Pattern
```elixir
# Each agent creates its own struct type
defmodule MyAgent do
  use Jido.Agent
  # This creates %MyAgent{} struct
end

defmodule OtherAgent do  
  use Jido.Agent
  # This creates %OtherAgent{} struct
end

# But callbacks expect unified type:
@callback handle_action(agent :: Jido.Agent.t(), action :: atom(), params :: map()) ::
  {:ok, any()} | {:error, term()}

# Problem: %MyAgent{} ≠ %Jido.Agent{} in type system
```

### Why This Breaks
1. **Structural Typing**: Elixir uses structural types - different structs are different types
2. **Behavior Contracts**: Cannot express "self-type" constraints in behaviors
3. **Dialyzer Confusion**: Static analysis sees type violations everywhere
4. **No Polymorphism**: Elixir doesn't have OOP-style inheritance

## The Single Struct Solution

### Core Concept
**All agents use the same struct type with runtime dispatch.**

```elixir
defmodule Jido.Agent do
  @type t :: %__MODULE__{
    id: String.t(),
    __module__: module(),    # Runtime dispatch target
    state: map(),
    config: map(),
    actions: map(),
    metadata: map()
  }
  
  defstruct [
    :id, :__module__, :state, :config, 
    :actions, :metadata
  ]
end
```

### Benefits
1. **Type Safety**: All functions work with `%Jido.Agent{}`
2. **Runtime Dispatch**: Use `__module__` field for behavior
3. **Backward Compatible**: Minimal API changes
4. **Dialyzer Happy**: No type violations

## Implementation Plan

### Step 1: Update Core Agent Structure

#### Replace jido/lib/jido/agent.ex
```elixir
defmodule Jido.Agent do
  @moduledoc """
  Core agent with single struct type and runtime dispatch.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    __module__: module(),
    state: map(),
    config: map(),
    actions: map(),
    status: :created | :running | :stopped | :error,
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  defstruct [
    :id, :__module__, :state, :config, :actions,
    :status, :metadata, :created_at, :updated_at
  ]
  
  @doc """
  Create a new agent with specified behavior module.
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(module, config \\ %{}, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      __module__: module,
      state: %{},
      config: config,
      actions: %{},
      status: :created,
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Initialize agent state through its behavior module.
  """
  @spec init(t()) :: {:ok, t()} | {:error, term()}
  def init(%__MODULE__{} = agent) do
    case agent.__module__.init(agent.config) do
      {:ok, initial_state} ->
        updated_agent = %{agent | 
          state: initial_state,
          status: :running,
          updated_at: DateTime.utc_now()
        }
        {:ok, updated_agent}
        
      {:error, reason} ->
        error_agent = %{agent | 
          status: :error,
          metadata: Map.put(agent.metadata, :error, reason),
          updated_at: DateTime.utc_now()
        }
        {:error, error_agent}
    end
  end
  
  @doc """
  Execute action through behavior module dispatch.
  """
  @spec execute_action(t(), atom(), map()) :: {:ok, any(), t()} | {:error, term()}
  def execute_action(%__MODULE__{} = agent, action, params) do
    case agent.__module__.handle_action(action, params, agent.state) do
      {:ok, result} ->
        updated_agent = %{agent | updated_at: DateTime.utc_now()}
        {:ok, result, updated_agent}
        
      {:ok, result, new_state} ->
        updated_agent = %{agent | 
          state: new_state,
          updated_at: DateTime.utc_now()
        }
        {:ok, result, updated_agent}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Get current state of agent.
  """
  @spec get_state(t()) :: map()
  def get_state(%__MODULE__{state: state}), do: state
  
  @doc """
  Update agent state.
  """
  @spec put_state(t(), map()) :: t()
  def put_state(%__MODULE__{} = agent, new_state) do
    %{agent | 
      state: new_state,
      updated_at: DateTime.utc_now()
    }
  end
  
  defp generate_id do
    "agent_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
```

### Step 2: Update Agent Behavior Definition

#### Create jido/lib/jido/agent_behavior.ex
```elixir
defmodule Jido.Agent.Behavior do
  @moduledoc """
  Behavior definition for agent implementations.
  All callbacks work with state maps, not agent structs.
  """
  
  @doc """
  Initialize agent state from configuration.
  """
  @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
  
  @doc """
  Handle action execution.
  """
  @callback handle_action(action :: atom(), params :: map(), state :: map()) ::
    {:ok, result :: any()} |
    {:ok, result :: any(), new_state :: map()} |
    {:error, reason :: term()}
  
  @doc """
  Handle agent termination (optional).
  """
  @callback terminate(reason :: term(), state :: map()) :: any()
  
  @optional_callbacks [terminate: 2]
  
  @doc """
  Convenience macro for implementing agent behaviors.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Agent.Behavior
      
      # Provide default init if not overridden
      def init(config) do
        {:ok, config}
      end
      
      # Provide default terminate if not overridden
      def terminate(_reason, _state) do
        :ok
      end
      
      defoverridable [init: 1, terminate: 2]
    end
  end
end
```

### Step 3: Update Agent Creation Macro

#### Replace jido/lib/jido/agent_macro.ex
```elixir
defmodule Jido.Agent.Macro do
  @moduledoc """
  Macro for defining agent modules (no longer creates structs).
  """
  
  defmacro __using__(opts) do
    quote do
      use Jido.Agent.Behavior
      
      @agent_opts unquote(opts)
      
      @doc """
      Create a new agent instance of this type.
      """
      def new(config \\ %{}, opts \\ []) do
        Jido.Agent.new(__MODULE__, config, opts)
      end
      
      @doc """
      Start a supervised agent process.
      """
      def start_link(config \\ %{}, opts \\ []) do
        agent = new(config, opts)
        Jido.Agent.Server.start_link(agent)
      end
      
      # Helper to get agent type
      def agent_type, do: __MODULE__
    end
  end
end
```

### Step 4: Update Process Server

#### Update jido/lib/jido/agent/server.ex
```elixir
defmodule Jido.Agent.Server do
  @moduledoc """
  GenServer for agent processes with single struct type.
  """
  
  use GenServer
  require Logger
  
  @type server_state :: %{
    agent: Jido.Agent.t(),
    subscribers: MapSet.t(pid()),
    stats: map()
  }
  
  def start_link(%Jido.Agent{} = agent, opts \\ []) do
    name = Keyword.get(opts, :name, {:via, Registry, {Jido.Agent.Registry, agent.id}})
    GenServer.start_link(__MODULE__, agent, name: name)
  end
  
  @impl GenServer
  def init(%Jido.Agent{} = agent) do
    # Initialize through behavior module
    case Jido.Agent.init(agent) do
      {:ok, initialized_agent} ->
        state = %{
          agent: initialized_agent,
          subscribers: MapSet.new(),
          stats: %{started_at: DateTime.utc_now(), actions_executed: 0}
        }
        {:ok, state}
        
      {:error, error_agent} ->
        {:stop, {:init_failed, error_agent}}
    end
  end
  
  @impl GenServer
  def handle_call({:execute_action, action, params}, _from, state) do
    case Jido.Agent.execute_action(state.agent, action, params) do
      {:ok, result, updated_agent} ->
        new_stats = %{state.stats | actions_executed: state.stats.actions_executed + 1}
        new_state = %{state | agent: updated_agent, stats: new_stats}
        {:reply, {:ok, result}, new_state}
        
      {:error, reason} ->
        Logger.warning("Action #{action} failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:get_agent, _from, state) do
    {:reply, state.agent, state}
  end
  
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.agent.state, state}
  end
end
```

### Step 5: Migration for Existing Agents

#### Create Migration Helper
```elixir
defmodule Jido.Migration.SingleStruct do
  @moduledoc """
  Helper to migrate existing agent implementations.
  """
  
  @doc """
  Convert old-style agent module to new behavior pattern.
  """
  def migrate_agent_module(module_source) do
    # Parse AST
    {:ok, ast} = Code.string_to_quoted(module_source)
    
    # Transform AST
    new_ast = Macro.postwalk(ast, &transform_agent_node/1)
    
    # Generate new source
    new_source = Macro.to_string(new_ast)
    
    {:ok, new_source}
  end
  
  defp transform_agent_node({:use, meta, [{:__aliases__, _, [:Jido, :Agent]} | opts]}) do
    # Replace use Jido.Agent with use Jido.Agent.Macro
    {:use, meta, [{:__aliases__, [], [:Jido, :Agent, :Macro]} | opts]}
  end
  
  defp transform_agent_node({:defstruct, _meta, _fields}) do
    # Remove defstruct - no longer needed
    nil
  end
  
  defp transform_agent_node(node), do: node
end
```

## Example Migration

### Before (Broken Type System)
```elixir
defmodule MyBot do
  use Jido.Agent
  
  defstruct [:name, :personality]  # Creates %MyBot{}
  
  def handle_action(:chat, params, state) do
    response = generate_response(params.message, state.personality)
    {:ok, response}
  end
end
```

### After (Fixed Type System)
```elixir
defmodule MyBot do
  use Jido.Agent.Macro  # No struct creation
  
  def init(config) do
    # Initialize state map
    {:ok, %{
      name: config[:name] || "Bot",
      personality: config[:personality] || :friendly
    }}
  end
  
  def handle_action(:chat, params, state) do
    response = generate_response(params.message, state.personality)
    {:ok, response}
  end
  
  defp generate_response(message, personality) do
    # Bot logic unchanged
  end
end

# Usage (same API)
bot_agent = MyBot.new(%{name: "Chatty", personality: :helpful})
{:ok, response, _updated_agent} = Jido.Agent.execute_action(bot_agent, :chat, %{message: "Hello"})
```

## Dialyzer Impact

### Before: Multiple Type Errors
```
lib/jido/agent.ex:45: The call Jido.Agent.handle_action(%MyBot{}, :action, %{}) 
will never return since the success typing is 
(%Jido.Agent{}, atom(), map()) -> {:ok, any()} | {:error, term()}
and the contract is 
(%Jido.Agent{}, atom(), map()) -> {:ok, any()} | {:error, term()}
```

### After: Clean Type Analysis
```
# No type errors - all functions use %Jido.Agent{} consistently
```

## Performance Impact

### Memory
- **Before**: Each agent type creates separate struct definition
- **After**: Single struct definition shared by all agents
- **Impact**: Reduced memory overhead for type information

### Runtime
- **Before**: Direct method dispatch
- **After**: Indirect dispatch through `__module__` field
- **Impact**: Negligible - one additional field access

## Compatibility Strategy

### Backward Compatibility
1. **Old agents work with new macro**
2. **Same public API**
3. **Migration tool provided**
4. **Gradual migration possible**

### Breaking Changes
1. **Struct access patterns** (rare in practice)
2. **Pattern matching on struct type** (can be updated)
3. **Direct struct creation** (should use new/2 anyway)

## Timeline

**Week 1**: Implement single struct and behavior system
**Week 2**: Update process server and registry  
**Week 3**: Migration tools and testing
**Week 4**: Update documentation and examples

**Total**: 4 weeks to complete type system fix

**Outcome**: Dialyzer-clean agent system with minimal breaking changes and maintained functionality.