# Prompt 10: Update Signal Core

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Update Signal Core (Prompt 10 of ~30)

## References Needed
- Doc 103, Section 2 (Signal-Agent Integration Points)
- Doc 110, Lines 84-88 (Update Signal Core requirements)
- jido_signal/lib/jido_signal.ex, Line 198 (jido_dispatch field)

## Current Code Issue
```elixir
# From jido_signal/lib/jido_signal.ex, lines 187-199
typedstruct do
  field(:specversion, String.t(), default: "1.0.2")
  field(:id, String.t(), enforce: true, default: ID.generate!())
  field(:source, String.t(), enforce: true)
  field(:type, String.t(), enforce: true)
  field(:subject, String.t())
  field(:time, String.t())
  field(:datacontenttype, String.t())
  field(:dataschema, String.t())
  field(:data, term())
  # Jido-specific fields
  field(:jido_dispatch, Dispatch.dispatch_configs())  # LINE 198 - NEEDS RENAMING
end
```

## Implementation Requirements

1. **Rename jido_dispatch Field**
   In `lib/jido/signal.ex`:
   - Change `field(:jido_dispatch, ...)` to `field(:dispatch, ...)`
   - Update all references throughout the codebase

2. **Add Agent-Aware Methods**
   Add the following functions to `lib/jido/signal.ex`:

   ```elixir
   alias Jido.Agent.Instance
   alias Jido.Instruction
   
   @agent_signal_prefix "jido.agent"
   
   @doc """
   Creates a signal from an agent context.
   """
   @spec from_agent(Instance.t(), type :: String.t(), data :: map()) :: t()
   def from_agent(%Instance{} = agent, type, data \\ %{}) do
     %__MODULE__{
       id: Jido.Core.ID.generate(),
       type: build_agent_type(type),
       source: build_agent_source(agent),
       time: DateTime.utc_now(),
       data: data,
       meta: %{
         agent_id: agent.id,
         agent_module: inspect(agent.module),
         agent_vsn: agent.__vsn__
       }
     }
   end
   
   @doc """
   Creates a signal from an instruction execution.
   """
   @spec from_instruction(Instruction.t(), Instance.t(), result :: any()) :: t()
   def from_instruction(%Instruction{} = instruction, %Instance{} = agent, result) do
     %__MODULE__{
       id: Jido.Core.ID.generate(),
       type: "#{@agent_signal_prefix}.instruction.completed",
       source: build_agent_source(agent),
       subject: instruction.id,
       time: DateTime.utc_now(),
       data: %{
         instruction_id: instruction.id,
         action: inspect(instruction.action),
         result: result
       },
       meta: %{
         agent_id: agent.id,
         correlation_id: instruction.id
       }
     }
   end
   
   @doc """
   Creates a command signal for an agent.
   """
   @spec command(Instance.t() | String.t(), command :: atom(), params :: map()) :: t()
   def command(agent_or_id, command, params \\ %{})
   
   def command(%Instance{id: agent_id}, command, params) do
     command(agent_id, command, params)
   end
   
   def command(agent_id, command, params) when is_binary(agent_id) do
     %__MODULE__{
       id: Jido.Core.ID.generate(),
       type: "#{@agent_signal_prefix}.cmd.#{command}",
       source: "jido://system",
       subject: agent_id,
       time: DateTime.utc_now(),
       data: params,
       dispatch: {:named, {:via, Registry, {Jido.Registry, agent_id}}}
     }
   end
   
   # Private helpers
   defp build_agent_type(type) when is_binary(type) do
     if String.starts_with?(type, @agent_signal_prefix) do
       type
     else
       "#{@agent_signal_prefix}.#{type}"
     end
   end
   
   defp build_agent_source(%Instance{id: id, module: module}) do
     "jido://agent/#{inspect(module)}/#{id}"
   end
   ```

3. **Update Existing References**
   Search and replace throughout the codebase:
   - `signal.jido_dispatch` → `signal.dispatch`
   - `%{jido_dispatch: ...}` → `%{dispatch: ...}`
   - Update `jido/lib/jido/agent/server_signal.ex` line 180 to use `dispatch`

4. **Add Meta Field**
   Ensure the signal struct includes a meta field for agent-specific metadata:
   ```elixir
   field(:meta, map(), default: %{})
   ```

## Key Code Locations
- `lib/jido/signal.ex`: Main signal module (line 198 for field rename)
- `lib/jido/agent/server_signal.ex`: Line 180 uses jido_dispatch
- Any dispatch-related modules that reference the field

## Success Criteria
- Field renamed from `jido_dispatch` to `dispatch`
- Agent-aware methods (`from_agent`, `from_instruction`, `command`) implemented
- All references updated throughout codebase
- Signal creation from agents works correctly
- Dialyzer passes with no warnings

## Testing Focus
- Test signal creation with `from_agent/3`
- Test instruction result signals with `from_instruction/3`
- Test command signal routing with `command/3`
- Verify dispatch field works correctly after rename