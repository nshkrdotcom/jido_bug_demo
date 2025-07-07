# Prompt 28: Implement Comprehensive Integration Test Suite

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Create comprehensive test suite for v2 integration (Prompt 28 of ~35)

References needed:
- Doc 105 (Test Strategy), sections 1-3 (lines 1-200)
- Doc 101, Week 2, Day 10 (integration testing)
- Doc 100, section 5 (validation requirements)

Previous work:
- All core functionality implemented
- Migration tooling complete
- Compatibility layer in place

Implementation requirements:
1. Create test/integration/agent_signal_test.exs from Doc 101 lines 312-350:
   - Test agents sending/receiving signals directly
   - Verify Signal.from_agent/3 functionality
   - Test local fast path (no serialization)
   - Validate signal metadata propagation

2. Implement test/integration/bus_sensor_test.exs:
   - Verify bus sensor works without circular deps
   - Test signal subscription and forwarding
   - Validate pattern matching in subscriptions
   - Check sensor lifecycle management

3. Create test/integration/end_to_end_test.exs:
   - Complete workflow tests
   - Multi-agent communication scenarios
   - Action execution through signals
   - State management validation

4. Add test/integration/migration_test.exs:
   - Test v1 to v2 code migration
   - Verify compatibility layer functionality
   - Check deprecated API warnings
   - Validate transformed code behavior

5. Implement performance regression tests:
   - Benchmark signal dispatch vs v1
   - Measure agent creation overhead
   - Test memory usage patterns
   - Validate 50% performance improvement

6. Create test/support/test_factories.ex:
   - Agent instance factories
   - Signal generation helpers
   - Action fixture creation
   - Test scenario builders

Success criteria:
- 100% coverage of integration points
- All v1 functionality preserved
- Performance benchmarks pass
- No flaky tests
- Clear test documentation
- CI/CD integration ready