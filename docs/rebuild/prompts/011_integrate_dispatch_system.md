# Prompt 11: Integrate Dispatch System

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Integrate Dispatch System with Local Optimization (Prompt 11 of ~30)

## References Needed
- Doc 103, Section 3 (Optimization Strategies - Local Signal Fast Path)
- Doc 106, Section 1 (Direct Function Call Path)
- Doc 110, Lines 90-93 (Dispatch Integration requirements)

## Current State
The dispatch system in jido_signal supports multiple adapters but lacks optimization for local agent-to-agent communication. Currently all signals go through serialization even when communicating within the same node.

## Implementation Requirements

1. **Create Local Dispatch Optimizer**
   Create `lib/jido/signal/dispatch/local_optimizer.ex`:

   ```elixir
   defmodule Jido.Signal.Dispatch.LocalOptimizer do
     @moduledoc """
     Optimizes local signal dispatch to avoid serialization.
     """
     
     @behaviour Jido.Signal.Dispatch.Adapter
     
     @impl true
     def validate_opts(opts) do
       with {:ok, target} <- Keyword.fetch(opts, :target),
            true <- local_target?(target) do
         :ok
       else
         :error -> {:error, "Missing :target option"}
         false -> {:error, "Target is not local"}
       end
     end
     
     @impl true
     def deliver(signal, opts) do
       target = Keyword.fetch!(opts, :target)
       
       case local_deliver(signal, target) do
         :ok -> :ok
         {:error, :not_local} -> fallback_deliver(signal, opts)
         error -> error
       end
     end
     
     # Direct in-memory delivery for local targets
     defp local_deliver(signal, {:pid, pid}) when node(pid) == node() do
       # Skip serialization completely
       send(pid, {:signal_direct, signal})
       :ok
     end
     
     defp local_deliver(signal, {:via, Registry, {Jido.Registry, name}}) do
       case Registry.lookup(Jido.Registry, name) do
         [{pid, _}] when node(pid) == node() ->
           send(pid, {:signal_direct, signal})
           :ok
           
         _ ->
           {:error, :not_local}
       end
     end
     
     defp local_deliver(_, _), do: {:error, :not_local}
     
     # Check if target is local
     defp local_target?({:pid, pid}), do: node(pid) == node()
     defp local_target?({:via, Registry, {Jido.Registry, _}}), do: true
     defp local_target?(_), do: false
     
     # Fallback to normal dispatch for remote targets
     defp fallback_deliver(signal, opts) do
       adapter = Keyword.get(opts, :fallback_adapter, :pid)
       adapter_module = Jido.Signal.Dispatch.adapter_for(adapter)
       adapter_module.deliver(signal, opts)
     end
   end
   ```

2. **Update Dispatch Configuration**
   In `lib/jido/signal/dispatch.ex`, add the local optimizer:

   ```elixir
   # Add to built-in adapters list around line 100
   @built_in_adapters %{
     # ... existing adapters ...
     local: Jido.Signal.Dispatch.LocalOptimizer
   }
   ```

3. **Integrate Fast Path in Agent Server**
   Update `lib/jido/agent/server.ex` to handle direct signals:

   ```elixir
   # Add new handle_info clause for direct signals
   def handle_info({:signal_direct, signal}, state) do
     # No deserialization needed - signal is already in memory
     case handle_signal_fast_path(signal, state) do
       {:reply, result, new_state} ->
         # Send result back if needed
         {:noreply, new_state}
         
       {:noreply, new_state} ->
         {:noreply, new_state}
         
       {:stop, reason, new_state} ->
         {:stop, reason, new_state}
     end
   end
   
   # Fast path handler
   defp handle_signal_fast_path(%Signal{} = signal, state) do
     cond do
       instruction_signal?(signal) ->
         handle_instruction_signal_direct(signal, state)
         
       command_signal?(signal) ->
         handle_command_signal_direct(signal, state)
         
       true ->
         # Fall back to normal handling
         Jido.Agent.Server.SignalHandler.handle_signal(signal, state)
     end
   end
   ```

4. **Configure Default Dispatch**
   Update signal creation to use local optimizer by default:

   ```elixir
   # In lib/jido/signal.ex, in agent-aware methods
   def command(agent_id, command, params) when is_binary(agent_id) do
     %__MODULE__{
       # ... other fields ...
       dispatch: [
         {:local, target: {:via, Registry, {Jido.Registry, agent_id}}},
         {:named, {:via, Registry, {Jido.Registry, agent_id}}}
       ]
     }
   end
   ```

5. **Add Batch Support**
   Leverage existing batch processing in dispatch:

   ```elixir
   # In lib/jido/signal/dispatch/local_optimizer.ex
   def deliver_batch(signals, opts) when is_list(signals) do
     # Group by target for efficient delivery
     signals
     |> Enum.group_by(&get_target/1)
     |> Enum.each(fn {target, target_signals} ->
       if local_target?(target) do
         # Send all signals to target in one message
         send(elem(target, 1), {:signal_batch_direct, target_signals})
       else
         # Fallback for remote targets
         Enum.each(target_signals, &fallback_deliver(&1, opts))
       end
     end)
   end
   ```

## Key Code Locations
- `lib/jido/signal/dispatch.ex`: Lines 96-106 for adapter registration
- `lib/jido/agent/server.ex`: Add handle_info for direct signals
- `lib/jido/signal.ex`: Update default dispatch configs

## Success Criteria
- Local signals bypass serialization completely
- 50% performance improvement for local signal dispatch
- Remote signals still work via fallback
- Batch processing works for local signals
- No breaking changes to existing dispatch API

## Performance Testing
```elixir
# Benchmark local vs remote dispatch
defmodule DispatchBenchmark do
  def run do
    signal = Signal.new!(%{type: "test", source: "bench", data: large_payload()})
    
    Benchee.run(%{
      "local_direct" => fn -> 
        Dispatch.dispatch(signal, local: [target: self()])
      end,
      "normal_dispatch" => fn ->
        Dispatch.dispatch(signal, pid: [target: self()])
      end
    })
  end
end
```