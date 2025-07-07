# Prompt 34: Release Candidate Preparation

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Prepare v2.0.0-rc1 release candidate (Prompt 34 of ~35)

References needed:
- Doc 101, Week 4, Day 21 (release checklist, lines 665-675)
- Doc 100, section 8 (release criteria)
- Previous prompt work completion status

Previous work:
- All features implemented and tested
- Documentation complete
- Performance validated
- Migration tooling ready

Implementation requirements:
1. Complete release checklist from Doc 101:
   - [ ] All tests passing (unit, integration, property)
   - [ ] Dialyzer clean with no warnings
   - [ ] Documentation complete and reviewed
   - [ ] Migration guide published
   - [ ] Performance benchmarks documented
   - [ ] CHANGELOG.md updated
   - [ ] Version bumped to 2.0.0-rc1

2. Update mix.exs:
   ```elixir
   def project do
     [
       app: :jido,
       version: "2.0.0-rc1",
       elixir: "~> 1.14",
       deps: deps(),
       docs: docs(),
       package: package(),
       description: "Unified autonomous agent framework"
     ]
   end
   ```

3. Create CHANGELOG.md entry:
   - Major changes summary
   - Breaking changes list
   - Performance improvements
   - Migration instructions
   - Acknowledgments

4. Prepare Hex.pm package:
   - Update package metadata
   - Include all necessary files
   - Exclude development files
   - Verify with mix hex.build

5. Create release announcement:
   - Blog post draft
   - Social media templates
   - Migration success stories
   - Performance benchmarks

6. Final quality checks:
   - Run full CI/CD pipeline
   - Manual testing of examples
   - Documentation review
   - Community beta feedback

Success criteria:
- mix hex.build succeeds
- All CI checks green
- Documentation builds on hex.pm
- Release notes comprehensive
- No critical issues found
- Community preview positive