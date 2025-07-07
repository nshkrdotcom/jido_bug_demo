# Prompt 31: Clean Up Deprecated Code and APIs

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Remove deprecated code and clean up APIs (Prompt 31 of ~35)

References needed:
- Doc 100, section 3 (technical debt items)
- Doc 110, lines 215-220 (bus sensor restoration)
- Migration work from previous prompts

Previous work:
- Compatibility layer provides transition path
- Migration tooling helps users update
- All v2 functionality implemented

Implementation requirements:
1. Remove deprecated agent patterns:
   - Delete old polymorphic struct code
   - Remove legacy agent behavior callbacks
   - Clean up unused agent utilities
   - Update all internal usage

2. Clean signal field names:
   - Remove jido_dispatch field support
   - Remove jido_meta field support
   - Update all internal references
   - Ensure compatibility layer handles legacy

3. Consolidate duplicate modules:
   - Merge jido_signal error types into Core.Error
   - Combine ID generation into Core.ID
   - Unify utility functions
   - Remove redundant implementations

4. Clean up circular dependency workarounds:
   - Remove commented bus_sensor.ex code
   - Delete temporary fixes and hacks
   - Consolidate module dependencies
   - Verify no circular deps remain

5. API surface reduction:
   - Mark internal modules as @moduledoc false
   - Move implementation details to private
   - Consolidate public API in main modules
   - Document supported vs internal APIs

6. Update deprecation notices:
   - Add @deprecated tags to compatibility functions
   - Set deprecation removal timeline
   - Update migration guide with deadlines
   - Configure compile-time warnings

Success criteria:
- No duplicate functionality
- Clean module structure
- All tests still pass
- Deprecation warnings clear
- Reduced API surface area
- No circular dependencies