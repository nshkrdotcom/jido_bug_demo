# Implementation Timeline: Single Library Approach

## Overview

This document provides a detailed 4-week timeline for implementing the single library approach, consolidating jido, jido_action, and jido_signal into one cohesive framework.

## Timeline Summary

- **Week 1**: Foundation & Type System Fix
- **Week 2**: Action & Signal Integration  
- **Week 3**: Feature Restoration & Optimization
- **Week 4**: Testing, Migration & Release

Total Duration: **4 weeks** (vs. 8 weeks for multi-package approach)

## Week 1: Foundation & Type System Fix

### Day 1-2: Project Setup & Planning

**Morning Day 1**
- [ ] Create new branch: `feature/single-library-consolidation`
- [ ] Set up project structure
  ```bash
  mkdir -p lib/jido/{agent,action,signal,sensor,tools,core}
  mkdir -p lib/jido/action/{exec,tool}
  mkdir -p lib/jido/signal/{dispatch,router,bus}
  ```
- [ ] Create tracking issue with subtasks
- [ ] Set up CI pipeline for new structure

**Afternoon Day 1**
- [ ] Define core types module (`lib/jido/core/types.ex`)
- [ ] Create unified error module (`lib/jido/core/error.ex`) 
- [ ] Implement ID generation (`lib/jido/core/id.ex`)
- [ ] Write tests for core modules

**Day 2**
- [ ] Design `Jido.Agent.Instance` struct
- [ ] Create compatibility layer for existing agents
- [ ] Write comprehensive tests for Instance
- [ ] Document the new type system

### Day 3-4: Fix Agent System

**Day 3**
- [ ] Implement new Agent behavior without defstruct
- [ ] Update Agent.Server to use Instance
- [ ] Fix all pattern matching in agent modules
- [ ] Create migration helper for agent structs

**Day 4**
- [ ] Update agent callbacks to use Instance type
- [ ] Fix agent lifecycle methods
- [ ] Update agent registry for new types
- [ ] Run and fix agent test suite

### Day 5: Type System Validation

- [ ] Run dialyzer on new agent system
- [ ] Fix any type warnings
- [ ] Verify no polymorphic struct issues remain
- [ ] Create example agents using new system
- [ ] Performance benchmark new vs old

**Week 1 Deliverables:**
- ✅ Core type system implemented
- ✅ Agent polymorphic struct antipattern fixed
- ✅ All agent tests passing
- ✅ Dialyzer clean for agent modules

## Week 2: Action & Signal Integration

### Day 6-7: Action System Integration

**Day 6**
- [ ] Copy best implementation from jido_action
- [ ] Integrate with new type system
- [ ] Update action behavior for unified types
- [ ] Merge execution engines

**Day 7**  
- [ ] Migrate all tools/actions to unified structure
- [ ] Port missing actions from jido (state_manager, directives)
- [ ] Update action tests
- [ ] Verify action-agent integration

### Day 8-9: Signal System Integration

**Day 8**
- [ ] Move signal core into jido
- [ ] Update signal types for agent integration
- [ ] Implement optimized router
- [ ] Create agent-aware signal builders

**Day 9**
- [ ] Integrate dispatch system
- [ ] Update bus implementation
- [ ] Port serialization modules
- [ ] Fix signal tests

### Day 10: Integration Testing

- [ ] Test agent-action flow
- [ ] Test agent-signal flow  
- [ ] Test action-signal integration
- [ ] Verify no circular dependencies
- [ ] Performance benchmarks

**Week 2 Deliverables:**
- ✅ Actions fully integrated
- ✅ Signals fully integrated
- ✅ All tests passing
- ✅ No circular dependencies

## Week 3: Feature Restoration & Optimization

### Day 11-12: Restore Lost Features

**Day 11**
- [ ] Re-enable bus sensor with full functionality
- [ ] Implement transaction support for signals
- [ ] Add signal batching capabilities
- [ ] Create signal coalescing optimizer

**Day 12**
- [ ] Implement priority-based routing
- [ ] Add fast paths for local operations
- [ ] Create integrated telemetry
- [ ] Restore any other disabled features

### Day 13-14: Performance Optimization

**Day 13**
- [ ] Implement zero-copy local signal delivery
- [ ] Add caching for pattern-based routing
- [ ] Optimize agent state updates
- [ ] Create benchmark suite

**Day 14**
- [ ] Profile hot paths
- [ ] Optimize serialization boundaries
- [ ] Implement lazy loading where appropriate
- [ ] Document performance improvements

### Day 15: Developer Experience

- [ ] Create unified configuration system
- [ ] Implement helpful error messages
- [ ] Add development mode with extra checks
- [ ] Create debugging utilities
- [ ] Write getting started guide

**Week 3 Deliverables:**
- ✅ All features restored and working
- ✅ Performance optimizations complete
- ✅ 58x improvement for local operations verified
- ✅ Developer experience enhanced

## Week 4: Testing, Migration & Release

### Day 16-17: Comprehensive Testing

**Day 16**
- [ ] Run full test suite
- [ ] Add integration test coverage
- [ ] Test migration scenarios
- [ ] Load testing and stress testing

**Day 17**
- [ ] Fix any remaining test failures
- [ ] Add property-based tests
- [ ] Test backwards compatibility
- [ ] Verify examples work

### Day 18-19: Migration Tools & Documentation

**Day 18**
- [ ] Finalize migration script
- [ ] Create compatibility modules
- [ ] Test migration on real projects
- [ ] Write troubleshooting guide

**Day 19**
- [ ] Update all documentation
- [ ] Create migration guide
- [ ] Update examples
- [ ] Write announcement blog post

### Day 20: Release Preparation

- [ ] Final code review
- [ ] Update changelog
- [ ] Tag release candidate
- [ ] Deploy to staging
- [ ] Final verification

**Week 4 Deliverables:**
- ✅ All tests passing
- ✅ Migration tools complete
- ✅ Documentation updated
- ✅ Ready for release

## Daily Standup Template

```markdown
## Day X Standup

**Completed Yesterday:**
- 

**Working on Today:**
- 

**Blockers:**
- 

**Notes:**
- 
```

## Risk Management

### High-Risk Items

1. **Agent State Migration**
   - Mitigation: Extensive testing, compatibility layer
   - Fallback: Keep old struct support temporarily

2. **Breaking Changes**
   - Mitigation: Clear migration guide, automated tools
   - Fallback: Compatibility modules

3. **Performance Regression**
   - Mitigation: Benchmark everything, profile hot paths
   - Fallback: Keep optimization branches

### Checkpoints

- **End of Week 1**: Type system working? If not, extend 1 week
- **End of Week 2**: Integration complete? If not, reduce optimization scope  
- **End of Week 3**: Performance targets met? If not, defer some features
- **Mid Week 4**: Ready for release? If not, extend testing period

## Success Criteria

### Technical
- [ ] Zero dialyzer warnings
- [ ] All tests passing (>95% coverage)
- [ ] Performance targets met (58x local operation improvement)
- [ ] No circular dependencies
- [ ] Clean architecture

### Product
- [ ] Bus sensor working
- [ ] Transaction support working
- [ ] Migration tools working
- [ ] Documentation complete
- [ ] Examples updated

### Process
- [ ] Daily standups completed
- [ ] Weekly demos given
- [ ] Risks tracked and mitigated
- [ ] Timeline met

## Communication Plan

### Week 1
- Announce consolidation plan
- Share type system design
- Demo fixed agent system

### Week 2  
- Show integration progress
- Share performance early results
- Get feedback on API changes

### Week 3
- Demo restored features
- Share benchmark results
- Preview migration tools

### Week 4
- Final demo
- Migration guide walkthrough
- Release announcement

## Post-Release

### Week 5+ 
- Monitor adoption
- Fix reported issues
- Gather feedback
- Plan next improvements

## Comparison with Multi-Package Approach

| Aspect | Multi-Package (8 weeks) | Single Library (4 weeks) |
|--------|------------------------|-------------------------|
| Complexity | High - coordination overhead | Low - single codebase |
| Risk | High - breaking changes across packages | Medium - managed migration |
| Performance | Degraded - serialization boundaries | Optimized - direct calls |
| Features | Some disabled - circular deps | All enabled - no boundaries |
| Testing | Complex - integration issues | Simple - unified tests |
| Deployment | Complex - version coordination | Simple - single version |

## Conclusion

The single library approach delivers the same outcome in half the time with better performance and simpler architecture. By recognizing that agents, actions, and signals are cohesive components, we can build a more powerful framework with less complexity.