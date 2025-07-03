# Jido Type System Crash Demonstration

This directory contains comprehensive examples demonstrating how Jido's type system crashes under realistic application conditions, particularly when following the best practices outlined in the `docs20250702` documentation.

## Overview

The examples show how Jido's internal type specification mismatches cause dialyzer errors when:
1. Implementing defensive boundary patterns
2. Using type-safe metaprogramming
3. Building complex stateful agents
4. Following the framework's own best practices

## Key Issues Demonstrated

### 1. Core Type Specification Mismatch

The fundamental issue is in `Jido.Agent.set/3`:

```elixir
# Type specification declares:
@spec set(t() | Jido.server(), keyword() | map(), keyword()) :: agent_result()

# But implementation accepts any() for opts:
def set(%__MODULE__{} = agent, attrs, opts) when is_list(attrs) do
  mapped_attrs = Map.new(attrs)
  set(agent, mapped_attrs, opts)  # opts is any(), not keyword()
end
```

### 2. Files and Their Demonstrations

#### `lib/test_agent.ex` - Pipeline Management Agent
Demonstrates:
- Real-world workflow state management
- Dynamic action registry with type boundaries
- How type mismatches cascade through agent operations
- Metrics tracking with nested state updates

Key crash points:
- Line 73: `set(agent, validated_state, opts)` - opts type mismatch
- Line 105: `set(acc_agent, %{registered_actions: updated_actions})` - nested update issues
- Line 151: Complex with-expression exposing multiple type violations

#### `lib/boundary_enforcement_demo.ex` - Defensive Boundary Implementation
Demonstrates:
- Implementation of "Defensive Boundary / Offensive Interior" pattern
- Runtime contract validation with caching
- How defensive programming exposes framework type issues

Key crash points:
- Contract registration breaking due to set/3 type specs
- Cache updates triggering nested map type violations
- Enforcement level handling showing opts parameter issues

#### `lib/metaprogramming_crash_demo.ex` - Advanced Metaprogramming
Demonstrates:
- Compile-time contract validation
- Dynamic module generation for state machines
- Complex workflow orchestration
- How metaprogramming best practices trigger type crashes

Key crash points:
- Dynamic module registration with type mismatches
- State transition updates breaking type contracts
- Bulk operations cascading type errors

## Running the Demonstration

1. Ensure you're in the `0002_local` directory
2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Run dialyzer to see the type crashes:
   ```bash
   mix dialyzer
   ```

## Expected Dialyzer Errors

You'll see errors like:

```
lib/test_agent.ex:73:call
The function call will not succeed.

JidoBugDemo.TestAgent.set(_ :: 
  %JidoBugDemo.TestAgent{
    assigns: map(),
    context: map(),
    id: binary(),
    result: _,
    state: map()
  }, _ :: map(), _ :: any())

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()
```

## Why These Patterns Crash

### 1. Following Best Practices Exposes Issues

The documentation in `docs20250702` recommends:
- Defensive boundaries with strict validation
- Type-safe metaprogramming patterns
- Contract-based module generation

However, implementing these patterns reveals that Jido's internal type specifications don't support them properly.

### 2. Real-World Usage Patterns

These aren't contrived examples. They represent common patterns in production Elixir applications:
- State machine implementations
- Workflow orchestration
- Dynamic action dispatch
- Runtime contract validation

### 3. The Cascade Effect

One type mismatch in `set/3` cascades through:
- Agent state updates
- Nested map modifications
- Dynamic module registration
- Error handling paths

## Impact on Application Development

1. **Type Safety Compromised**: Can't rely on dialyzer for catching errors
2. **Best Practices Blocked**: Following docs leads to type errors
3. **Complex Debugging**: Runtime works but static analysis fails
4. **Maintenance Issues**: New developers see walls of dialyzer errors

## Recommended Framework Fix

The issue requires fixing Jido's core type specifications:

```elixir
# Option 1: Fix the type spec
@spec set(t() | Jido.server(), keyword() | map(), keyword() | any()) :: agent_result()

# Option 2: Add type guards
def set(%__MODULE__{} = agent, attrs, opts) when is_list(attrs) and is_list(opts) do
  # ...
end

# Option 3: Normalize opts before recursive call
def set(%__MODULE__{} = agent, attrs, opts) when is_list(attrs) do
  opts = if is_list(opts), do: opts, else: []
  # ...
end
```

## Conclusion

These examples demonstrate that Jido's type system issues aren't academic - they prevent real-world usage patterns and make it impossible to achieve type safety when following the framework's own best practices. The framework needs internal fixes to support the patterns it recommends.