# Prompt 30: Unify Error Handling System

Continuing Jido-JidoSignal reintegration from Doc 110.

Task: Complete error system unification (Prompt 30 of ~35)

References needed:
- Doc 107 (Error Handling and Recovery), entire document
- Doc 102 (Type System), section 2 (error types)
- Doc 110, lines 147-149 (error unification requirements)

Previous work:
- Core.Error type created in Phase 1
- Basic error handling in place

Implementation requirements:
1. Enhance lib/jido/core/error.ex:
   - Merge error types from jido_signal
   - Add structured error categories
   - Implement error chaining/wrapping
   - Add telemetry integration

2. Create unified error categories:
   ```elixir
   @type error_category :: 
     :validation_error |
     :execution_error |
     :signal_error |
     :agent_error |
     :timeout_error |
     :permission_error
   ```

3. Implement error recovery strategies:
   - Automatic retry logic for transient errors
   - Circuit breaker for repeated failures
   - Error escalation policies
   - Dead letter queue for signals

4. Add error context propagation:
   - Trace error through agent/signal chain
   - Capture stack traces appropriately
   - Include relevant metadata
   - Support distributed tracing

5. Create lib/jido/error/handler.ex:
   - Centralized error handling
   - Configurable error policies
   - Logging and monitoring hooks
   - Error transformation pipeline

6. Update all modules to use unified errors:
   - Replace ad-hoc error tuples
   - Use consistent error structures
   - Add proper error documentation
   - Ensure error type safety

Success criteria:
- All errors use Core.Error type
- Consistent error handling across framework
- Clear error messages for users
- Telemetry events for all errors
- Error recovery strategies work
- Dialyzer validates error types