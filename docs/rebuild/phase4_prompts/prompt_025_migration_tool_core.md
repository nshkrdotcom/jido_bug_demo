# Prompt 25: Implement Migration Tool Core Infrastructure

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement core migration tool infrastructure (Prompt 25 of ~35)

References needed:
- Doc 104 (Migration Tooling Implementation), sections 1-2
- Doc 101, Week 4, Day 16-17 tasks
- Doc 109 (Backward Compatibility), section 1 (Version Detection)

Current state after Phases 1-3:
- Core type system implemented (Jido.Core.Types, Jido.Core.Error)
- Agent Instance struct working
- Signal system fully integrated
- Performance optimizations in place

Implementation requirements:
1. Create lib/mix/tasks/jido/migrate.ex following Doc 104 lines 11-108
2. Implement main migration task structure:
   - Parse command line arguments
   - Validate environment (check Jido version)
   - Create backup functionality
   - Analyze codebase
   - Apply migrations (sequential/parallel)
   - Generate report

3. Create lib/jido/migration/analyzer.ex following Doc 104 lines 113-150:
   - Find agent modules using polymorphic structs
   - Detect signal usage patterns
   - Identify deprecations
   - Find type issues

4. Add support modules:
   - lib/jido/migration/backup.ex for creating backups
   - lib/jido/migration/reporter.ex for progress reporting
   - lib/jido/migration/validator.ex for validating results

5. Implement version detection from Doc 109 lines 9-77:
   - Detect v1 vs v2 patterns in code
   - Support auto/v1/v2 compatibility modes
   - Analyze application code for version indicators

Success criteria:
- mix jido.migrate --check analyzes code without changes
- Proper version detection between v1 and v2 code
- Backup creation before any modifications
- Clear progress reporting
- All tests pass
- Dialyzer clean