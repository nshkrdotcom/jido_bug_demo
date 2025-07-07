# Complete Refactor Roadmap: Jido Framework

## Vision

Transform the Jido framework from a monolithic library with type issues into a well-architected, modular system with clean boundaries, proper types, and production-ready stability.

## Goals

1. **Fix the polymorphic struct antipattern** that prevents type safety
2. **Remove action functionality from jido** and use jido_action
3. **Establish clear module boundaries** between libraries  
4. **Create a unified type system** across all packages
5. **Maintain backward compatibility** where possible
6. **Enable production deployment** with dialyzer compliance

## Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  jido_core  │     │ jido_action  │     │ jido_signal  │
│   (types)   │◄────┤  (actions)   │◄────┤  (events)    │
└──────┬──────┘     └──────┬───────┘     └──────┬───────┘
       │                   │                     │
       └───────────────────┴─────────────────────┘
                           │
                    ┌──────▼──────┐
                    │    jido     │
                    │  (agents)   │
                    └─────────────┘
```

## Implementation Phases

### Phase 0: Foundation (Week 1)
**Create jido_core package for shared types**

1. **Set up new package**
   ```bash
   mix new jido_core
   cd jido_core
   ```

2. **Define core types**
   - `lib/jido_core/types.ex` - Base type definitions
   - `lib/jido_core/error.ex` - Unified error handling
   - `lib/jido_core/result.ex` - Result types with directives
   - `lib/jido_core/id.ex` - Standardized ID generation

3. **Publish initial version**
   ```bash
   mix hex.publish
   ```

### Phase 1: Type System Reform (Week 2-3)
**Fix the polymorphic struct antipattern**

1. **Create Agent Instance type**
   ```elixir
   defmodule Jido.Agent.Instance do
     defstruct [:id, :module, :state, :config, :metadata]
     
     @type t :: %__MODULE__{
       id: String.t(),
       module: module(), 
       state: map(),
       config: map(),
       metadata: map()
     }
   end
   ```

2. **Update Agent behavior**
   - Remove defstruct from `__using__` macro
   - Update all callbacks to use Instance type
   - Fix type specifications

3. **Migrate existing agents**
   - Update all agent implementations
   - Fix pattern matching on agent structs
   - Update tests

### Phase 2: Action System Migration (Week 3-4)
**Replace jido actions with jido_action**

1. **Add dependencies**
   ```elixir
   # All packages depend on jido_core
   {:jido_core, "~> 1.0"}
   
   # jido depends on jido_action
   {:jido_action, "~> 1.0"}
   ```

2. **Port missing actions**
   - StateManager actions → jido_action
   - Directive actions → jido_action  
   - Task management actions → jido_action

3. **Update jido internals**
   - Replace Action imports
   - Update Instruction handling
   - Delegate Exec to jido_action
   - Fix error handling

4. **Remove duplicate code**
   - Delete `jido/lib/jido/action.ex`
   - Delete `jido/lib/jido/actions/`
   - Clean up exec modules

### Phase 3: Signal System Integration (Week 4-5)
**Ensure proper integration with unified types**

1. **Update jido_signal**
   - Use jido_core types
   - Remove duplicate error definitions
   - Standardize result types

2. **Fix signal routing**
   - Update type specifications
   - Ensure compatibility with new agent types
   - Test signal dispatch with new action system

### Phase 4: Testing & Validation (Week 5-6)
**Comprehensive testing of the refactored system**

1. **Update test suites**
   - Migrate ~50 test files
   - Update test actions
   - Fix type assertions
   - Add integration tests

2. **Dialyzer compliance**
   ```bash
   # Run on each package
   mix dialyzer
   ```

3. **Performance testing**
   - Benchmark before/after
   - Memory usage analysis
   - Latency measurements

4. **Integration testing**
   - Cross-library communication
   - Error propagation
   - Type compatibility

### Phase 5: Migration Support (Week 6-7)
**Help users migrate their code**

1. **Migration tooling**
   ```elixir
   mix jido.migrate       # Automated migration
   mix jido.check_types   # Type compatibility check
   ```

2. **Documentation**
   - Migration guide
   - API changes
   - Best practices
   - Common issues

3. **Compatibility layer**
   - Temporary adapters
   - Deprecation warnings
   - Gradual migration path

### Phase 6: Production Readiness (Week 7-8)
**Final preparation for production deployment**

1. **Code cleanup**
   - Remove deprecated code
   - Optimize hot paths
   - Add missing documentation

2. **Release preparation**
   - Version coordination
   - Changelog generation
   - Release notes

3. **Deployment validation**
   - Staging environment testing
   - Load testing
   - Rollback procedures

## Technical Implementation Details

### Type System Changes

#### Before (Broken):
```elixir
defmodule MyAgent do
  use Jido.Agent  # Creates %MyAgent{} struct
  
  def handle_action(%MyAgent{} = agent, action) do
    # Type mismatch: callbacks expect %Jido.Agent{}
  end
end
```

#### After (Fixed):
```elixir
defmodule MyAgent do
  use Jido.Agent  # No struct created
  
  def handle_action(%Jido.Agent.Instance{module: __MODULE__} = agent, action) do
    # Type safe: all agents use same struct type
  end
end
```

### Action Migration

#### Before:
```elixir
defmodule MyWorkflow do
  alias Jido.Action
  alias Jido.Actions.Basic
  
  def run do
    Action.run(Basic.Sleep, %{duration: 1000}, %{})
  end
end
```

#### After:
```elixir
defmodule MyWorkflow do
  alias JidoAction.Exec
  alias JidoTools.Basic
  
  def run do
    Exec.run(Basic.Sleep, %{duration: 1000}, %{})
  end
end
```

### Error Handling

#### Before (Multiple error types):
```elixir
{:error, %Jido.Error{type: :validation_error}}
{:error, %JidoAction.Error{type: :validation_error}}
{:error, %Jido.Signal.Error{type: :routing_error}}
```

#### After (Unified):
```elixir
{:error, %JidoCore.Error{type: :validation_error}}
# Same type used everywhere
```

## Success Metrics

1. **Zero dialyzer warnings** across all packages
2. **100% backward compatibility** for public APIs (with deprecations)
3. **Performance parity** or improvement
4. **Clean module boundaries** with no circular dependencies
5. **Comprehensive test coverage** including integration tests

## Risk Analysis

### High Risk Items
1. **Breaking changes** to agent struct types
2. **Performance regression** from indirection
3. **User code migration** complexity
4. **Cross-library compatibility** issues

### Mitigation Strategies
1. **Gradual rollout** with feature flags
2. **Extensive testing** at each phase
3. **Migration tools** and documentation
4. **Beta testing** with key users
5. **Rollback plan** at each phase

## Timeline Summary

- **Week 1**: Foundation - Create jido_core
- **Week 2-3**: Type System - Fix polymorphic struct  
- **Week 3-4**: Actions - Migrate to jido_action
- **Week 4-5**: Signals - Integration updates
- **Week 5-6**: Testing - Comprehensive validation
- **Week 6-7**: Migration - User support tools
- **Week 7-8**: Production - Final preparation

Total: **8 weeks** for complete refactor

## Post-Refactor Opportunities

Once the refactor is complete:

1. **Enhanced Features**
   - Better composition patterns
   - Advanced routing capabilities
   - Improved error recovery

2. **Performance Optimizations**
   - Reduced allocations
   - Better caching strategies
   - Optimized dispatch paths

3. **New Capabilities**
   - Multi-agent coordination
   - Distributed agent support
   - Advanced telemetry

4. **Developer Experience**
   - Better error messages
   - IDE support improvements
   - Interactive debugging tools

## Conclusion

This refactor addresses fundamental architectural issues while preserving the core value of the Jido framework. By fixing the type system, establishing clear boundaries, and providing migration support, we can deliver a production-ready agent framework suitable for complex AI applications.