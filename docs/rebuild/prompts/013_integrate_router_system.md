# Prompt 13: Integrate Router System

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Move Router System with Agent Routing (Prompt 13 of ~30)

## References Needed
- Doc 103, Section 3 (Signal Bus Integration - Agent Routes)
- Doc 110, Lines 100-103 (Router Integration requirements)
- jido_signal/lib/jido_signal/router.ex (Trie-based implementation)

## Current State
The router system uses a trie-based structure for efficient pattern matching. It needs enhancement to support agent-specific routing patterns.

## Implementation Requirements

1. **Add Agent-Specific Route Patterns**
   Create `lib/jido/signal/router/agent_patterns.ex`:

   ```elixir
   defmodule Jido.Signal.Router.AgentPatterns do
     @moduledoc """
     Agent-specific routing patterns and helpers.
     """
     
     alias Jido.Agent.Instance
     
     @doc """
     Generate standard route patterns for an agent.
     """
     @spec agent_routes(Instance.t() | String.t()) :: [route_spec()]
     def agent_routes(%Instance{id: id, module: module}), do: agent_routes(id, module)
     def agent_routes(agent_id) when is_binary(agent_id), do: agent_routes(agent_id, nil)
     
     def agent_routes(agent_id, module) do
       base_routes = [
         # Direct commands to this specific agent
         {"jido.agent.cmd.#", {:agent, agent_id}, priority: 100},
         
         # Agent-specific events
         {"jido.agent.#{agent_id}.#", {:agent, agent_id}, priority: 90},
         
         # State change events
         {"jido.agent.event.state.#{agent_id}", {:agent, agent_id}, priority: 95},
         
         # Instruction results
         {"jido.agent.out.instruction.#{agent_id}", {:agent, agent_id}, priority: 85}
       ]
       
       if module do
         base_routes ++ [
           # Route by agent type/module
           {"jido.agent.type.#{inspect(module)}.#", {:agent, agent_id}, priority: 80}
         ]
       else
         base_routes
       end
     end
     
     @doc """
     Create broadcast patterns for agent types.
     """
     @spec type_routes(module()) :: [route_spec()]
     def type_routes(agent_module) when is_atom(agent_module) do
       module_name = inspect(agent_module)
       [
         # Broadcast to all agents of this type
         {"jido.agent.type.#{module_name}.broadcast", {:type, agent_module}, priority: 70},
         
         # Type-specific events
         {"jido.agent.type.#{module_name}.event.#", {:type, agent_module}, priority: 75}
       ]
     end
     
     @doc """
     System-wide agent patterns.
     """
     @spec system_routes() :: [route_spec()]
     def system_routes() do
       [
         # All agent commands
         {"jido.agent.cmd.#", :agent_command, priority: 50},
         
         # All agent events
         {"jido.agent.event.#", :agent_event, priority: 50},
         
         # System broadcasts
         {"jido.system.broadcast", :system_broadcast, priority: 60}
       ]
     end
     
     @doc """
     Check if a signal type is agent-related.
     """
     @spec agent_signal?(String.t()) :: boolean()
     def agent_signal?(type) when is_binary(type) do
       String.starts_with?(type, "jido.agent.")
     end
     
     @doc """
     Extract agent ID from signal type if present.
     """
     @spec extract_agent_id(String.t()) :: {:ok, String.t()} | :error
     def extract_agent_id(type) when is_binary(type) do
       case Regex.run(~r/jido\.agent\.(?:cmd|event|out)\..*\.([^.]+)$/, type) do
         [_, agent_id] -> {:ok, agent_id}
         _ -> :error
       end
     end
   end
   ```

2. **Enhance Router with Agent Support**
   Update `lib/jido/signal/router.ex` to include agent helpers:

   ```elixir
   # Add near the top with other aliases
   alias Jido.Signal.Router.AgentPatterns
   
   # Add new functions for agent routing
   @doc """
   Add routes for an agent.
   """
   @spec add_agent_routes(t(), Instance.t() | String.t(), handler()) :: t()
   def add_agent_routes(router, agent, handler) do
     routes = AgentPatterns.agent_routes(agent)
     |> Enum.map(fn {pattern, _tag, opts} ->
       {pattern, handler, opts}
     end)
     
     add(router, routes)
   end
   
   @doc """
   Remove all routes for an agent.
   """
   @spec remove_agent_routes(t(), String.t()) :: t()
   def remove_agent_routes(router, agent_id) when is_binary(agent_id) do
     # Filter out routes with agent tag
     update_in(router.trie, fn trie ->
       filter_trie(trie, fn {_pattern, handler, _opts} ->
         case handler do
           {:agent, ^agent_id} -> false
           _ -> true
         end
       end)
     end)
   end
   
   @doc """
   Route signal with agent awareness.
   """
   @spec route_agent_signal(t(), Signal.t()) :: {:ok, [handler()]} | {:error, term()}
   def route_agent_signal(router, %Signal{type: type} = signal) do
     handlers = route(router, signal)
     
     # Enhance with agent-specific routing
     enhanced = if AgentPatterns.agent_signal?(type) do
       case AgentPatterns.extract_agent_id(type) do
         {:ok, agent_id} ->
           # Prioritize direct agent handlers
           {agent_handlers, other_handlers} = Enum.split_with(handlers, fn
             {:agent, ^agent_id} -> true
             _ -> false
           end)
           agent_handlers ++ other_handlers
           
         :error ->
           handlers
       end
     else
       handlers
     end
     
     {:ok, enhanced}
   end
   ```

3. **Add Zero-Copy Router Enhancement**
   Implement the zero-copy router from Doc 103:

   ```elixir
   # Create lib/jido/signal/router/zero_copy.ex
   defmodule Jido.Signal.Router.ZeroCopy do
     @moduledoc """
     Implements zero-copy routing for signals using ETS.
     """
     
     use GenServer
     
     @table_name :jido_signal_routes
     
     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: __MODULE__)
     end
     
     @impl GenServer
     def init(_opts) do
       # Create ETS table with read concurrency
       table = :ets.new(@table_name, [
         :named_table,
         :set,
         :public,
         read_concurrency: true,
         write_concurrency: true
       ])
       
       {:ok, %{table: table}}
     end
     
     @doc """
     Add a route without copying data.
     """
     def add_route(pattern, handler, opts \\ []) do
       key = pattern_to_key(pattern)
       value = {handler, opts}
       
       # Direct ETS write - no copying
       :ets.insert(@table_name, {key, value})
       :ok
     end
     
     @doc """
     Route a signal without copying.
     """
     def route(signal_type) when is_binary(signal_type) do
       # Direct ETS lookups - no GenServer call
       keys = build_lookup_keys(signal_type)
       
       handlers = keys
       |> Enum.flat_map(&:ets.lookup(@table_name, &1))
       |> Enum.map(fn {_key, value} -> value end)
       |> Enum.sort_by(fn {_handler, opts} -> 
         Keyword.get(opts, :priority, 0) 
       end, :desc)
       
       {:ok, handlers}
     end
   end
   ```

4. **Integration with Bus**
   The router is used by the bus for pattern matching. Ensure compatibility by maintaining the existing API while adding agent enhancements.

## Key Code Locations
- `lib/jido/signal/router.ex`: Main router implementation
- `lib/jido/signal/bus.ex`: Uses router for subscription matching
- Pattern validation regex at line 17 of router.ex
- Trie implementation details throughout router module

## Success Criteria
- Agent-specific routing patterns work correctly
- Zero-copy routing improves performance
- Existing router API remains unchanged
- Bus can use enhanced router without modifications
- Agent routes can be dynamically added/removed
- Pattern matching remains efficient with trie structure

## Testing Focus
```elixir
test "agent routing patterns" do
  router = Router.new()
  agent_id = "agent_123"
  
  # Add agent routes
  router = Router.add_agent_routes(router, agent_id, self())
  
  # Test command routing
  signal = %Signal{type: "jido.agent.cmd.run"}
  assert {:ok, handlers} = Router.route_agent_signal(router, signal)
  assert {:agent, ^agent_id} in handlers
  
  # Test agent-specific events
  signal = %Signal{type: "jido.agent.#{agent_id}.state_changed"}
  assert {:ok, handlers} = Router.route_agent_signal(router, signal)
  assert {:agent, ^agent_id} in handlers
end
```