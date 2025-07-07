# 110: Prompt Creation Guide and Roadmap

## Overview

This document serves as the master guide for creating the ~30 prompts needed to implement the Jido-JidoSignal reintegration. It identifies which source files to read, which documents to reference, and provides a structured roadmap for breaking down this massive undertaking into manageable prompt-sized tasks.

## Critical Source Files to Read

### From jido/lib

**Core Type System Issues:**
- `jido/lib/jido/agent.ex` (lines 150-200 for polymorphic struct problem)
- `jido/lib/jido/agent/server.ex` (signal handling integration points)
- `jido/lib/jido/instruction.ex` (type union issues)
- `jido/lib/jido/sensors/bus_sensor.ex` (ENTIRE FILE - commented out!)

**Integration Points:**
- `jido/lib/jido/agent/server_signal.ex` (signal type conventions)
- `jido/lib/jido/util.ex` (ID generation that matches signal system)
- `jido/lib/jido/error.ex` (error types to unify)

### From jido_signal/lib

**Core Signal System:**
- `jido_signal/lib/jido_signal.ex` (main signal struct, jido_dispatch field)
- `jido_signal/lib/jido_signal/dispatch.ex` (dispatch system)
- `jido_signal/lib/jido_signal/bus.ex` (bus that sensor needs)
- `jido_signal/lib/jido_signal/router.ex` (trie-based routing)

**Key Dependencies:**
- `jido_signal/lib/jido_signal/error.ex` (duplicate error handling)
- `jido_signal/lib/jido_signal/id.ex` (UUID7 generation)

## Essential Documents to Reference

### Foundation Documents
1. **Doc 100**: Reintegration Approach - Overall architecture
2. **Doc 101**: Implementation Plan - Week-by-week breakdown
3. **Doc 102**: Type System Specs - Critical for fixing polymorphic structs

### Technical Implementation Docs
4. **Doc 103**: Signal Integration - How to merge the codebases
5. **Doc 106**: Performance Optimization - Fast path implementations
6. **Doc 104**: Migration Tooling - Automated tools needed

### Quality & Safety Docs
7. **Doc 105**: Test Strategy - Validation approach
8. **Doc 107**: Error Handling - Unified error system
9. **Doc 109**: Backward Compatibility - Ensuring smooth migration

## Prompt Breakdown Strategy

### Phase 1: Foundation (Prompts 1-8)

**Prompt 1: Create Core Type System**
- Reference: Doc 102, sections 1-3
- Create `lib/jido/core/types.ex`
- Create `lib/jido/core/error.ex`
- Files to read: Current `jido/lib/jido/error.ex`

**Prompt 2: Agent Instance Implementation**
- Reference: Doc 102, section 3; Doc 100, section 2
- Create `lib/jido/agent/instance.ex`
- Update `lib/jido/agent.ex` to use Instance
- Files to read: `jido/lib/jido/agent.ex`

**Prompt 3: Fix Agent Behavior Macro**
- Reference: Doc 101, Week 1, Task 3
- Remove polymorphic struct creation
- Files to read: `jido/lib/jido/agent.ex` (lines 300-400)

**Prompt 4-8: Update Existing Agents**
- One prompt per built-in agent type
- Convert to Instance pattern
- Test each conversion

### Phase 2: Signal Integration (Prompts 9-16)

**Prompt 9: Move Signal Core Modules**
- Reference: Doc 103, section 1
- Execute migration script
- Create directory structure

**Prompt 10: Update Signal Core**
- Reference: Doc 103, section 2
- Update `lib/jido/signal.ex`
- Add agent-aware methods
- Files to read: `jido_signal/lib/jido_signal.ex`

**Prompt 11: Integrate Dispatch System**
- Move dispatch modules
- Update for local optimization
- Files to read: `jido_signal/lib/jido_signal/dispatch/*.ex`

**Prompt 12: Restore Bus Sensor**
- Reference: Doc 100, section 5
- Uncomment and fix `bus_sensor.ex`
- Files to read: Entire `jido/lib/jido/sensors/bus_sensor.ex`

**Prompts 13-16: Router and Bus Integration**
- Move router system
- Move bus system
- Update imports and dependencies

### Phase 3: Performance Optimization (Prompts 17-22)

**Prompt 17: Implement Fast Path**
- Reference: Doc 106, section 1
- Create `lib/jido/agent/server/fast_path.ex`
- Files to read: `jido/lib/jido/agent/server.ex`

**Prompt 18: Zero-Copy Optimizations**
- Reference: Doc 106, section 2
- Implement zero-copy signal passing

**Prompts 19-22: Other Optimizations**
- Object pooling
- Batch processing
- JIT optimizations
- Caching layer

### Phase 4: Migration & Compatibility (Prompts 23-28)

**Prompt 23: Migration Tool Core**
- Reference: Doc 104, section 1
- Create mix task infrastructure

**Prompt 24: Code Analyzer**
- Reference: Doc 104, section 2
- Detect polymorphic struct usage

**Prompt 25: Code Transformer**
- Reference: Doc 104, section 3
- Automated code updates

**Prompt 26: Compatibility Layer**
- Reference: Doc 109, sections 2-3
- Support v1 code patterns

**Prompts 27-28: Testing & Validation**
- Migration test suite
- Compatibility tests

### Phase 5: Final Integration (Prompts 29-30+)

**Prompt 29: Error System Unification**
- Reference: Doc 107
- Merge error handling
- Unify error types

**Prompt 30: Full System Testing**
- Reference: Doc 105
- Integration tests
- Performance benchmarks

## Key Code Patterns to Extract

### From Existing Code
```elixir
# The polymorphic struct antipattern (from agent.ex)
defstruct [:id, :name, :state, ...]  # This must go!

# Signal integration points (from server_signal.ex)
@cmd_base @agent_base ++ [@config.cmd_prefix]

# The circular dependency (from bus_sensor.ex)
# alias Jido.Bus  # This causes the circular dep!
```

### To New Patterns
```elixir
# Unified Instance struct
%Jido.Agent.Instance{module: MyAgent, state: %{}, ...}

# Direct signal handling
def handle_signal(%Signal{meta: %{node: node()}} = signal, state)
  when node() == node() do
  # Fast path - no serialization
end
```

## Context Management Strategy

Since context is limited, each prompt should:

1. **Start with**: "Continuing Jido-JidoSignal reintegration from Doc 110"
2. **Reference**: Specific document sections needed
3. **Include**: Only relevant code snippets
4. **Focus on**: One specific task
5. **End with**: Clear success criteria

## Example Prompt Structure

```
Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement Agent Instance struct (Prompt 2 of ~30)

References needed:
- Doc 102, section 3 (Agent Type Specifications)
- Doc 100, section 2 (Unified Type System)

Current code issue:
[Include relevant snippet from jido/lib/jido/agent.ex]

Implementation requirements:
1. Create lib/jido/agent/instance.ex
2. Define Instance struct with fields: id, module, state, config, metadata, __vsn__, __dirty__
3. Implement new/2 function
4. Add validation

Success criteria:
- No polymorphic structs
- Dialyzer clean
- All tests pass
```

## Priority Order

1. **Must Fix First**: Polymorphic struct antipattern (blocks everything)
2. **Critical Path**: Signal module movement and integration
3. **High Value**: Bus sensor restoration (proves circular dep is fixed)
4. **Performance**: Fast path optimizations
5. **Polish**: Migration tools and compatibility

## Notes for Prompt Creation

- Each prompt should be self-contained
- Include line numbers when referencing existing code
- Reference specific sections of the 100-109 docs
- Keep prompts focused on 1-2 files max
- Test requirements should be explicit
- Include rollback strategy if applicable

This guide provides everything needed to create the ~30 prompts that will implement the complete Jido-JidoSignal reintegration, fixing the type system and achieving the performance goals outlined in the extensive documentation.