# Jido Framework Dialyzer Contract Violation Reproduction

This directory contains minimal reproduction cases demonstrating a type contract violation in the Jido framework.

## Files

1. `dialyzer_issue_fork.exs` - Uses the fork version: `github: "nshkrdotcom/jido", branch: "fix/agent-server-terminate-race-condition-v2"`
2. `dialyzer_issue_hex.exs` - Uses the hex version: `{:jido, "~> 1.2"}`
3. `JIDO_PIPELINE_DEBUG.md` - Detailed technical analysis of the issue

## Issue Summary

The Jido framework has a type specification bug where:

1. The `use Jido.Agent` macro generates functions with strict type specifications
2. But the framework internally calls these functions with looser types
3. This creates contract violations that show up in dialyzer when using agents

## Reproduction Steps

### Method 1: Using the example files

```bash
# Test with fork version
cd /home/home/p/g/n/agentjido
elixir dialyzer_issue_fork.exs
mix dialyzer --no-check

# Clean and test with hex version  
rm -rf .mix deps _build
elixir dialyzer_issue_hex.exs
mix dialyzer --no-check
```

### Method 2: Manual reproduction

Create any project that uses `use Jido.Agent` and run dialyzer. You'll see errors like:

```
deps/jido/lib/jido/agent.ex:592:call
The function call will not succeed.

YourAgent.set(_ :: %YourAgent{}, _ :: map(), _ :: any())

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()
```

## Key Evidence

1. **Jido framework alone passes dialyzer** - When you run dialyzer on the Jido framework repository directly, it passes with only minor skipped warnings
2. **Consumer code triggers the violations** - The errors only appear when external code uses `use Jido.Agent`
3. **Specific line identified** - The issue is on line 592 of `deps/jido/lib/jido/agent.ex` where a recursive call passes `any()` to a function expecting `keyword()`

## The Root Cause

In `jido/lib/jido/agent.ex`:

```elixir
# Line 587 - Type specification requires keyword() for 3rd param
@spec set(t() | Jido.server(), keyword() | map(), keyword()) :: agent_result()

# Line 590 - Function accepts any() for opts (no type guard)  
def set(%__MODULE__{} = agent, attrs, opts) when is_list(attrs) do

# Line 592 - Recursive call passes any() to function expecting keyword()
set(agent, mapped_attrs, opts)  # CONTRACT VIOLATION
```

## Impact

This prevents any Jido consumer from achieving clean dialyzer results, undermining the framework's type safety guarantees.

## Recommended Fix

Add proper type guards or adjust the type specification to match actual usage patterns. See `JIDO_PIPELINE_DEBUG.md` for detailed solutions.