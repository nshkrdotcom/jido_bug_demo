# Prompt 14: Integrate Bus System

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Move Bus System with Agent Subscriptions (Prompt 14 of ~30)

## References Needed
- Doc 103, Section 3 (Signal Bus Integration)
- Doc 110, Lines 100-103 (Bus Integration requirements)
- jido_signal/lib/jido_signal/bus.ex (Bus implementation)

## Current State
The bus system provides pub/sub functionality with persistence and replay capabilities. It needs agent-specific enhancements for the integrated system.

## Implementation Requirements

1. **Create Agent Bus Integration**
   Create `lib/jido/signal/bus/agent_integration.ex`:

   ```elixir
   defmodule Jido.Signal.Bus.AgentIntegration do
     @moduledoc """
     Agent-specific enhancements to the signal bus.
     """
     
     alias Jido.Signal.Bus
     alias Jido.Signal.Router.AgentPatterns
     alias Jido.Agent.Instance
     
     @doc """
     Subscribe an agent to signals matching patterns.
     """
     @spec subscribe_agent(GenServer.server(), Instance.t(), [String.t()]) :: 
       {:ok, subscription_id :: String.t()} | {:error, term()}
       
     def subscribe_agent(bus, %Instance{} = agent, patterns \\ []) do
       # Build agent-specific dispatch config
       dispatch_config = build_agent_dispatch(agent)
       
       # Generate default patterns if none provided
       patterns = if patterns == [] do
         AgentPatterns.agent_routes(agent)
         |> Enum.map(fn {pattern, _, _} -> pattern end)
       else
         patterns
       end
       
       # Subscribe with agent metadata
       Bus.subscribe(bus, patterns, dispatch_config, %{
         subscriber_type: :agent,
         agent_id: agent.id,
         agent_module: inspect(agent.module),
         agent_vsn: agent.__vsn__
       })
     end
     
     @doc """
     Publish a signal from an agent with routing hints.
     """
     @spec publish_from_agent(GenServer.server(), Instance.t(), Signal.t()) :: 
       :ok | {:error, term()}
       
     def publish_from_agent(bus, %Instance{} = agent, signal) do
       # Enhance signal with agent context
       enhanced_signal = %{signal | 
         source: build_agent_source(agent),
         meta: Map.merge(signal.meta || %{}, %{
           publisher_type: :agent,
           agent_id: agent.id,
           node: node(),
           published_at: DateTime.utc_now()
         })
       }
       
       Bus.publish(bus, enhanced_signal)
     end
     
     @doc """
     Create agent-aware bus configuration.
     """
     @spec agent_bus_config(keyword()) :: keyword()
     def agent_bus_config(base_config \\ []) do
       Keyword.merge(base_config, [
         middleware: [
           Jido.Signal.Bus.Middleware.AgentContext,
           Jido.Signal.Bus.Middleware.LocalOptimization
           | Keyword.get(base_config, :middleware, [])
         ],
         router_opts: [
           agent_aware: true
         ]
       ])
     end
     
     # Private helpers
     
     defp build_agent_dispatch(%Instance{id: id}) do
       [
         # Try local delivery first
         {:local, target: {:via, Registry, {Jido.Registry, id}}},
         # Fallback to normal named process
         {:named, {:via, Registry, {Jido.Registry, id}}}
       ]
     end
     
     defp build_agent_source(%Instance{id: id, module: module}) do
       "jido://agent/#{inspect(module)}/#{id}"
     end
   end
   ```

2. **Create Agent Context Middleware**
   Create `lib/jido/signal/bus/middleware/agent_context.ex`:

   ```elixir
   defmodule Jido.Signal.Bus.Middleware.AgentContext do
     @moduledoc """
     Adds agent context to signals passing through the bus.
     """
     
     @behaviour Jido.Signal.Bus.Middleware
     
     alias Jido.Signal
     
     @impl true
     def call(%Signal{} = signal, next) do
       # Add routing hints for agent signals
       enhanced = if agent_signal?(signal) do
         add_routing_hints(signal)
       else
         signal
       end
       
       # Continue with next middleware
       next.(enhanced)
     end
     
     defp agent_signal?(%Signal{type: type}) do
       String.starts_with?(type, "jido.agent.")
     end
     
     defp add_routing_hints(%Signal{meta: meta} = signal) do
       hints = %{
         routable: true,
         priority: determine_priority(signal),
         local_optimizable: local_signal?(signal)
       }
       
       %{signal | meta: Map.merge(meta || %{}, hints)}
     end
     
     defp determine_priority(%Signal{type: type}) do
       cond do
         String.contains?(type, ".cmd.") -> :high
         String.contains?(type, ".error.") -> :high
         String.contains?(type, ".event.") -> :normal
         true -> :low
       end
     end
     
     defp local_signal?(%Signal{meta: %{node: signal_node}}) do
       signal_node == node()
     end
     defp local_signal?(_), do: false
   end
   ```

3. **Create Local Optimization Middleware**
   Create `lib/jido/signal/bus/middleware/local_optimization.ex`:

   ```elixir
   defmodule Jido.Signal.Bus.Middleware.LocalOptimization do
     @moduledoc """
     Optimizes local signal delivery through the bus.
     """
     
     @behaviour Jido.Signal.Bus.Middleware
     
     alias Jido.Signal
     
     @impl true
     def call(%Signal{meta: %{local_optimizable: true}} = signal, next) do
       # Mark for fast path delivery
       tagged_signal = put_in(signal.meta[:delivery_mode], :direct)
       next.(tagged_signal)
     end
     
     def call(signal, next), do: next.(signal)
   end
   ```

4. **Update Bus Module**
   In `lib/jido/signal/bus.ex`, add agent-specific enhancements:

   ```elixir
   # Add alias at top
   alias Jido.Signal.Bus.AgentIntegration
   
   # Add convenience functions for agents
   defdelegate subscribe_agent(bus, agent, patterns \\ []), 
     to: AgentIntegration
     
   defdelegate publish_from_agent(bus, agent, signal), 
     to: AgentIntegration
   
   # In handle_call for subscribe, detect agent subscriptions
   def handle_call({:subscribe, patterns, dispatch, meta}, _from, state) do
     # Check if this is an agent subscription
     subscription_type = Map.get(meta, :subscriber_type, :generic)
     
     subscription = %Subscription{
       id: generate_subscription_id(),
       patterns: patterns,
       dispatch: dispatch,
       meta: meta,
       type: subscription_type
     }
     
     # Add to router with priority for agent subscriptions
     new_router = if subscription_type == :agent do
       # Agent subscriptions get higher priority
       add_with_priority(state.router, patterns, subscription, 100)
     else
       Router.add(state.router, patterns, subscription)
     end
     
     new_state = %{state | 
       router: new_router,
       subscriptions: Map.put(state.subscriptions, subscription.id, subscription)
     }
     
     {:reply, {:ok, subscription.id}, new_state}
   end
   ```

5. **Add Agent-Specific Bus Options**
   Update bus configuration to support agent features:

   ```elixir
   # In lib/jido/signal/bus.ex init function
   def init(opts) do
     # Check for agent-aware mode
     if Keyword.get(opts, :agent_aware, false) do
       opts = AgentIntegration.agent_bus_config(opts)
     end
     
     # Continue with normal initialization...
   end
   ```

## Key Code Locations
- `lib/jido/signal/bus.ex`: Main bus implementation
- Subscription handling around lines 133-152
- Publishing logic around line 175
- Router integration throughout

## Success Criteria
- Agents can subscribe to bus with automatic pattern generation
- Agent-published signals include proper metadata
- Local optimization works for same-node agent communication
- Middleware pipeline processes agent signals correctly
- Bus sensor can subscribe as an agent
- No breaking changes to existing bus API

## Testing Focus
```elixir
test "agent bus integration" do
  {:ok, bus} = Bus.start_link(agent_aware: true)
  
  agent = %Instance{
    id: "test_agent",
    module: TestAgent,
    state: %{},
    __vsn__: 1
  }
  
  # Subscribe agent
  {:ok, subscription} = Bus.subscribe_agent(bus, agent)
  
  # Publish from agent
  signal = Signal.new!(%{
    type: "jido.agent.event.test",
    data: %{value: 42}
  })
  
  :ok = Bus.publish_from_agent(bus, agent, signal)
  
  # Verify signal received with agent context
  assert_receive {:signal_direct, received_signal}
  assert received_signal.meta.agent_id == "test_agent"
  assert received_signal.meta.local_optimizable == true
end
```