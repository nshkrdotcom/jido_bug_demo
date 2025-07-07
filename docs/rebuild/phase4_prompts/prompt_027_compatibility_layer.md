# Prompt 27: Implement Runtime Compatibility Layer

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Create comprehensive compatibility layer for v1 code (Prompt 27 of ~35)

References needed:
- Doc 109 (Backward Compatibility), sections 2-4 (lines 80-200)
- Doc 100 (Reintegration Approach), section 4 (compatibility requirements)
- Doc 101, Week 4, Day 20 (migration guide)

Previous work:
- Migration tooling infrastructure
- Code transformation system

Implementation requirements:
1. Create lib/jido/compat/layer.ex from Doc 109 lines 82-150:
   - Compatibility macros for v1 agents
   - Struct conversion helpers
   - Deprecation warning system
   - Runtime adaptation layer

2. Implement polymorphic struct compatibility:
   - Override __struct__/0 and __struct__/1
   - Convert v1 structs to Instance format
   - Maintain field mappings
   - Add deprecation warnings

3. Create lib/jido/compat/signal_adapter.ex:
   - Handle jido_dispatch -> dispatch field mapping
   - Support old signal creation patterns
   - Maintain backward compatible APIs

4. Add lib/jido/compat/agent_adapter.ex:
   - Support v1 agent behavior callbacks
   - Wrap old agent modules with Instance
   - Handle state management differences
   - Preserve agent lifecycle

5. Implement configuration-based compatibility:
   ```elixir
   config :jido, compatibility_mode: true
   config :jido, deprecation_warnings: :once
   ```

6. Create compatibility test suite:
   - Test v1 agent creation
   - Verify signal compatibility
   - Check deprecation warnings
   - Validate runtime behavior

Success criteria:
- v1 code runs without modification
- Clear deprecation warnings guide migration
- No performance impact for v2 code
- Gradual migration path supported
- All v1 tests pass with compatibility layer
- Documentation of all compatibility features