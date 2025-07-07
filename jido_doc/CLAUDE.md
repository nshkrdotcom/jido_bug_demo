# Claude Memory for Jido Project

## Project Overview
Jido is an Elixir framework for building agent-based systems with Actions, Runners, and Directives. The codebase uses both 2-tuple and 3-tuple return patterns for actions.

## Current Task: Dialyzer Error Resolution
Working to fix 65 dialyzer errors stemming from architectural inconsistency between Action behavior contract (2-tuple) and actual implementation patterns (3-tuple with directives).

## Key Architecture Patterns
- **2-tuple returns**: `{:ok, result} | {:error, reason}` - Used by basic actions
- **3-tuple returns**: `{:ok, result, directives} | {:error, reason, directives}` - Used for state management and workflows
- **Runtime support**: Jido.Exec and Runners handle both patterns correctly
- **Test expectations**: Tests expect 3-tuple returns for directive-carrying actions

## Core Files and Roles
- `lib/jido/action.ex` - Action behavior definition (needs callback update)
- `lib/jido/exec.ex` - Action execution engine (handles both patterns)
- `lib/jido/runner/simple.ex` - Simple runner (processes both patterns)
- `lib/jido/runner/chain.ex` - Chain runner (processes both patterns) 
- `lib/jido/actions/state_manager.ex` - State management actions (uses 3-tuple)
- `lib/jido/actions/directives.ex` - Directive actions (uses 3-tuple)

## Commands to Run
- Tests: `mix test`
- Dialyzer: `mix dialyzer`
- Type checking: Available via dialyzer

## Current Status
Analysis complete. Ready to implement systematic fixes starting with Action behavior contract.