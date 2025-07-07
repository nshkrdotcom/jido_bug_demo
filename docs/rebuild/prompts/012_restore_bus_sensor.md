# Prompt 12: Restore Bus Sensor

Continuing Jido-JidoSignal reintegration from Doc 110.

**Task**: Restore Bus Sensor and Fix Circular Dependency (Prompt 12 of ~30)

## References Needed
- Doc 100, Section 5 (Bus Sensor Integration - implied)
- Doc 110, Lines 95-98 (Restore Bus Sensor requirements)
- jido/lib/jido/sensors/bus_sensor.ex (entire file - commented out)

## Current Code Issue
The entire bus_sensor.ex file is commented out due to a circular dependency. The sensor needs `Jido.Bus` which is part of the signal system being integrated.

```elixir
# From bus_sensor.ex, lines 144-156 - shows the circular dependency
case Jido.Bus.whereis(config.bus_name) do  # This causes circular dep!
  {:ok, bus} ->
    Jido.Bus.subscribe(
      bus,
      stream,
      "#{id}_subscription", 
      self(),
      start_from: :origin
    )
```

## Implementation Requirements

1. **Uncomment and Update Imports**
   In `lib/jido/sensors/bus_sensor.ex`:
   - Uncomment the entire file (remove `#` from all lines)
   - Update imports to use the integrated signal modules:
   
   ```elixir
   # Add at top of file after defmodule
   alias Jido.Signal
   alias Jido.Signal.Bus
   alias Jido.Signal.Dispatch
   ```

2. **Fix Module References**
   Update all module references:
   - `Jido.Bus` → `Jido.Signal.Bus`
   - `Jido.Bus.RecordedSignal` → `Jido.Signal.Bus.RecordedSignal`
   - Ensure `Jido.Signal` is used (already correct in file)

3. **Update Dispatch Field References**
   Since we renamed `jido_dispatch` to `dispatch`:
   - Line 217: `jido_metadata` field references should remain unchanged
   - No dispatch field references found in this file

4. **Update Schema Configuration**
   The sensor schema looks correct but verify patterns field:
   
   ```elixir
   schema: [
     bus_name: [
       type: :atom,
       required: true,
       doc: "Name of the bus to monitor"
     ],
     stream_id: [
       type: :string,
       required: true,
       doc: "Stream ID to monitor"
     ],
     filter_source: [
       type: :string,
       required: false,
       doc: "Optional source ID to filter out"
     ]
   ]
   ```

5. **Verify Bus Integration Points**
   Key integration points that need to work:
   - `Bus.whereis/1` - Find bus by name
   - `Bus.subscribe/5` - Subscribe to bus with patterns
   - `Bus.unsubscribe/2` - Cleanup on shutdown
   - Signal conversion between bus signals and sensor signals

6. **Handle Direct Dispatch**
   Update the dispatch logic to use the new local optimizer:
   
   ```elixir
   # Around line 189, update dispatch to use local optimizer
   case Jido.Signal.Dispatch.dispatch(
          converted,
          [{:local, target: extract_dispatch_target(state.target)},
           state.target]
        ) do
     :ok ->
       Logger.debug("Successfully dispatched signal")
   ```

7. **Add Helper for Dispatch Target Extraction**
   
   ```elixir
   defp extract_dispatch_target({:pid, opts}) when is_list(opts) do
     {:pid, Keyword.get(opts, :target)}
   end
   defp extract_dispatch_target({:pid, pid}) when is_pid(pid) do
     {:pid, pid}
   end
   defp extract_dispatch_target(other), do: other
   ```

## Key Code Locations
- Entire file needs uncommenting (lines 1-259)
- Line 144: Bus.whereis call
- Line 146: Bus.subscribe call  
- Line 129: Bus.unsubscribe call
- Line 189: Dispatch.dispatch call
- Lines 212-218: Signal metadata handling

## Success Criteria
- Bus sensor compiles without circular dependency errors
- Can subscribe to a bus and receive signals
- Signals are properly converted and dispatched to targets
- Integration test from Doc 101 passes:
  ```elixir
  test "bus sensor works without circular dependencies" do
    {:ok, bus} = Bus.start_link(name: :test_bus)
    {:ok, sensor} = Jido.Sensors.Bus.start_link(
      bus_name: :test_bus,
      patterns: ["test.#"],
      target: self()
    )
    # Test signal flow...
  end
  ```
- No compilation warnings about undefined modules

## Testing Focus
- Bus sensor can start and subscribe to bus
- Signals published to bus are received by sensor
- Signal conversion preserves all metadata
- Proper cleanup on sensor shutdown
- Direct dispatch optimization works for local targets