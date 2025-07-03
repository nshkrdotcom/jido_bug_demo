# JIDO Type Contract Resolution Prompts

This document contains progressive, self-contained prompts to resolve type contract violations in jido_action and then jido. Each prompt includes all necessary context and file references.

## Prompt 1: Standardize Error Types in jido_action

### Context
The jido_action module has inconsistent error return types. Some functions return `{:error, any()}` while others return `{:error, Error.t()}`. This causes dialyzer warnings and makes error handling unpredictable.

### Required Reading
1. `agentjido/jido/lib/jido/action.ex` - Focus on the action_result type and callback specifications
2. `agentjido/jido/lib/jido/agent/error.ex` - Understand the Error.t() type structure
3. `0001.md` - Background on dialyzer violations

### Task
Standardize all error returns in jido_action to use `{:error, Error.t()}`:

1. Update the `action_result` type specification in `lib/jido/action.ex` to replace `{:error, any()}` with `{:error, Error.t()}`
2. Update all callback specifications that return `{:error, any()}` to return `{:error, Error.t()}`
3. Search for any function implementations that return raw error tuples and wrap them in proper Error structs

### Success Metrics
- All type specifications in jido_action consistently use `{:error, Error.t()}`
- `mix dialyzer` shows reduced warnings related to error types
- No runtime errors from error type mismatches

---

## Prompt 2: Fix Agent Callback Return Types

### Context
The `on_error` callback in `Jido.Agent` has an inconsistent return type `{:error, t()}` where `t()` is an agent struct, while other callbacks return `{:error, Error.t()}`. This creates type confusion.

### Required Reading
1. `agentjido/jido/lib/jido/agent.ex` - Focus on callback definitions
2. `0001_final_analysis.md` - Understanding of struct type issues
3. `jido_architectural_analysis.md` - Framework type system analysis

### Task
Fix the `on_error` callback return type:

1. Locate the `on_error` callback definition in `lib/jido/agent.ex`
2. Change the return type from `{:ok, t()} | {:error, t()}` to `{:ok, t()} | {:error, Error.t()}`
3. Search for all implementations of `on_error` callback and ensure they return proper Error structs on failure
4. Update any calling code that expects an agent struct in error tuples

### Success Metrics
- All agent callbacks have consistent return types
- No dialyzer warnings about callback type mismatches
- Error handling code works uniformly across all callbacks

---

## Prompt 3: Handle Opaque Erlang Queue Type

### Context
The agent struct uses `:queue.queue(instruction())` for the `pending_instructions` field. This is an opaque Erlang type that can cause dialyzer warnings when accessed directly.

### Required Reading
1. `agentjido/jido/lib/jido/agent.ex` - Agent struct definition
2. `type_safe_metaprogramming_patterns.md` - Type-safe patterns for Elixir
3. `ELIXIR_1_20_0_DEV_ANTIPATTERNS.md` - Section on proper data handling

### Task
Create type-safe queue operations:

1. Add private helper functions in `lib/jido/agent.ex` for queue operations:
   - `enqueue_instruction/2` - Add instruction to queue
   - `dequeue_instruction/1` - Remove and return next instruction
   - `queue_to_list/1` - Convert queue to list for inspection
2. Update all direct queue manipulations to use these helpers
3. Add proper type specs for these helper functions
4. Consider adding guards to ensure queue integrity

### Success Metrics
- No direct manipulation of `:queue` opaque type
- Dialyzer passes without queue-related warnings
- Queue operations remain performant and correct

---

## Prompt 4: Resolve Struct Type Hierarchy Issues

### Context
The Jido framework has two different struct definitions - one in `Jido.Agent` with all fields, and another in generated modules with a subset. This causes type mismatches in callbacks.

### Required Reading
1. `agentjido/jido/lib/jido/agent.ex` - Base agent module and struct
2. `0001_final_analysis.md` - Detailed analysis of struct type issues
3. `jido_architectural_analysis.md` - Proposed solutions
4. `defensive_boundary_implementation.md` - Boundary pattern examples

### Task
Implement single struct type solution:

1. Modify the agent macro in `lib/jido/agent.ex` to NOT generate a new struct in child modules
2. Update all generated code to use `Jido.Agent.t()` type consistently
3. Add runtime validation functions to ensure struct integrity
4. Update callback specifications to use `Jido.Agent.t()` throughout

### Success Metrics
- Only one agent struct type exists (`Jido.Agent.t()`)
- All callbacks pass dialyzer with no struct type violations
- Generated modules can still customize behavior without type conflicts

---

## Prompt 5: Add Defensive Boundaries to Action Module

### Context
The action module needs defensive boundaries to validate inputs and outputs at runtime while maintaining type safety.

### Required Reading
1. `agentjido/jido/lib/jido/action.ex` - Current action implementation
2. `type_contract_best_practices.md` - Contract patterns
3. `PERIMETER_gem_0003.md` - Boundary guard examples
4. `defensive_boundary_implementation.md` - Implementation patterns

### Task
Add boundary validation to actions:

1. Create `lib/jido/action/contract.ex` with validation functions
2. Add boundary guards to the `run/2` function that validate params against schema
3. Add output validation that checks results against output_schema
4. Wrap all validation errors in proper Error structs
5. Add compile-time warnings for missing schemas

### Success Metrics
- All action inputs/outputs are validated at boundaries
- Invalid data is caught before entering action logic
- Type specifications accurately reflect runtime behavior
- Clear error messages for contract violations

---

## Prompt 6: Migrate Callback Invocations to Type-Safe Patterns

### Context
Many callback invocations in the codebase don't properly handle the different return types and error cases, leading to runtime failures.

### Required Reading
1. `agentjido/jido/lib/jido/agent.ex` - Callback invocation code
2. `error_handling_type_safety.md` - Error handling patterns
3. `0001_fixes_applied.md` - Previous callback fixes

### Task
Refactor callback invocations:

1. Create a `invoke_callback/3` helper that safely invokes callbacks
2. Handle all possible return types: `{:ok, agent}`, `{:error, Error.t()}`, exceptions
3. Add proper error context when callbacks fail
4. Use pattern matching instead of case statements where possible
5. Add telemetry events for callback execution

### Success Metrics
- All callbacks invoked through safe helper function
- No unhandled callback failures
- Clear error messages with context
- Telemetry provides visibility into callback behavior

---

## Prompt 7: Implement Comprehensive Type Testing

### Context
To ensure type safety improvements don't break functionality, comprehensive testing is needed.

### Required Reading
1. `agentjido/jido/test/` - Existing test structure
2. `migration_strategy_guide.md` - Testing approaches
3. `PERIMETER_gem_0010.md` - Type testing examples

### Task
Add type-focused tests:

1. Create `test/jido/type_safety_test.exs` with dialyzer-friendly tests
2. Add property-based tests for type contracts using StreamData
3. Test all error type conversions and edge cases
4. Add integration tests that verify type safety across module boundaries
5. Create a `mix test.types` task that runs only type-related tests

### Success Metrics
- All type contracts have corresponding tests
- Property tests catch edge cases
- CI runs dialyzer and type tests
- No type-related regressions

---

## Prompt 8: Final Integration and Documentation

### Context
After implementing all type fixes, the changes need to be integrated and documented for maintainability.

### Required Reading
1. All previous prompt results
2. `README.md` - Current documentation
3. `docs20250702/README.md` - Documentation patterns

### Task
Finalize type safety improvements:

1. Run full dialyzer analysis and fix any remaining warnings
2. Update README with type safety guidelines
3. Add a `TYPES.md` document explaining the type system
4. Create migration guide for existing code
5. Add type annotations to all public functions
6. Set up CI to enforce dialyzer compliance

### Success Metrics
- Zero dialyzer warnings in codebase
- Clear documentation on type patterns
- CI prevents type regressions
- Easy migration path for users

---

## Execution Order

1. Start with Prompts 1-3 to fix immediate type violations in jido_action
2. Move to Prompt 4 to resolve the fundamental struct type issue
3. Apply Prompts 5-6 to add defensive boundaries and safe patterns
4. Use Prompt 7 to ensure changes don't break functionality
5. Complete with Prompt 8 for integration and documentation

Each prompt builds on previous fixes while remaining self-contained enough to be executed independently if needed.