# Prompt 26: Implement Code Transformer for Automated Updates

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Implement automated code transformation system (Prompt 26 of ~35)

References needed:
- Doc 104 (Migration Tooling Implementation), section 3
- Doc 109 (Backward Compatibility), sections 2-3
- Doc 102 (Type System), section 3 (Agent Instance specification)

Previous work completed:
- Migration tool core infrastructure (Prompt 25)
- Code analyzer for detecting v1 patterns

Implementation requirements:
1. Create lib/jido/migration/transformer.ex with:
   - AST manipulation for code updates
   - Transform polymorphic struct to Instance pattern
   - Update signal field names (jido_dispatch -> dispatch)
   - Convert agent struct access to Instance methods

2. Implement transformation rules:
   ```elixir
   # Transform from:
   %MyAgent{id: "123", state: %{}}
   # To:
   %Jido.Agent.Instance{id: "123", module: MyAgent, state: %{}}
   ```

3. Handle use statements:
   - Detect `use Jido.Agent` with defstruct
   - Remove defstruct from agent modules
   - Add compatibility layer if needed

4. Update signal field references:
   - Replace `.jido_dispatch` with `.dispatch`
   - Replace `.jido_meta` with `.meta`
   - Update pattern matches accordingly

5. Create lib/jido/migration/ast_helpers.ex:
   - Safe AST traversal functions
   - Pattern matching helpers
   - Code generation utilities

6. Add transformation validation:
   - Verify transformed code compiles
   - Check type safety with dialyzer
   - Ensure semantic equivalence

Success criteria:
- Automated transformation of v1 code to v2
- Preserve code formatting and comments
- Handle edge cases gracefully
- Rollback capability on errors
- Comprehensive test coverage
- No compilation errors after transformation