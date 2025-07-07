# Jido-Perimeter Integration - Best of Both Worlds

## Overview

Rather than rebuilding jido or working around its limitations, we can integrate it with perimeter patterns to create a robust agent system that combines jido's runtime capabilities with perimeter's type safety architecture.

## Integration Strategy

### Core Insight: Zone-Based Jido Usage

Instead of trying to fix jido's type system completely, we use perimeter's four-zone architecture to manage jido interactions safely:

- **Zone 1**: Strict validation of external inputs before they reach jido
- **Zone 2**: Strategic validation at jido boundaries  
- **Zone 3**: Direct jido usage with productive coupling
- **Zone 4**: Core jido functionality without additional overhead

## Implementation Architecture

### Zone 1: External Perimeter for Jido

```elixir
defmodule OurAI.JidoPerimeter do
  @moduledoc """
  Zone 1: External perimeter that validates all input before jido.
  """
  
  use Perimeter.Zone1
  
  # Strict contracts for external agent requests
  defcontract agent_creation_request :: %{
    required(:type) => atom(),
    required(:config) => map(),
    optional(:skills) => [skill_spec()],
    optional(:sensors) => [sensor_spec()],
    optional(:metadata) => map()
  }
  
  defcontract agent_action_request :: %{
    required(:agent_id) => String.t(),
    required(:action) => atom(),
    required(:params) => map(),
    optional(:timeout) => pos_integer(),
    optional(:context) => map()
  }
  
  # Maximum validation before jido interaction
  @guard input: agent_creation_request(),
         sanitization: true,
         logging: :all_attempts
  def create_agent(request) do
    # Zone 1 -> Zone 2 transition
    OurAI.JidoManager.create_agent_internal(request)
  end
  
  @guard input: agent_action_request(),
         rate_limiting: true,
         authentication: true
  def execute_action(request) do
    # Zone 1 -> Zone 2 transition  
    OurAI.JidoManager.execute_action_internal(request)
  end
end
```

### Zone 2: Jido Boundary Management

```elixir
defmodule OurAI.JidoManager do
  @moduledoc """
  Zone 2: Strategic boundaries around jido components.
  """
  
  use Perimeter.Zone2
  
  # Strategic validation for jido interactions
  defcontract jido_agent_spec :: %{
    required(:module) => module(),
    required(:config) => map(),
    optional(:jido_options) => map()
  }
  
  @guard input: jido_agent_spec(),
         jido_safe: true,
         error_handling: :graceful
  def create_agent_internal(spec) do
    # Convert to jido format and create
    # Zone 2 -> Zone 3 transition (no more validation)
    JidoCoupling.create_with_skills(spec)
  end
  
  @guard input: validated_action_request(),
         jido_safe: true
  def execute_action_internal(request) do
    # Find agent and execute through jido
    # Zone 2 -> Zone 3 transition
    JidoCoupling.execute_on_agent(request)
  end
  
  # Jido-specific validation helpers
  defp validate_jido_agent_exists(agent_id) do
    case Jido.Agent.Registry.whereis(agent_id) do
      nil -> {:error, :agent_not_found}
      _pid -> :ok
    end
  end
end
```

### Zone 3: Productive Jido Coupling

```elixir
defmodule OurAI.JidoCoupling do
  @moduledoc """
  Zone 3: Direct jido usage with productive coupling.
  No perimeter validation - trust Zone 2 boundaries.
  """
  
  # NO use Perimeter - this is a coupling zone
  # Direct jido imports and usage
  alias Jido.{Agent, Skill, Sensor}
  
  def create_with_skills(spec) do
    # Direct jido calls - no validation overhead
    {:ok, agent} = Agent.start_link(spec.module, spec.config)
    
    # Add skills directly
    Enum.each(spec.skills || [], fn skill_spec ->
      skill = build_skill(skill_spec)
      Agent.add_skill(agent, skill)
    end)
    
    # Add sensors directly
    Enum.each(spec.sensors || [], fn sensor_spec ->
      sensor = build_sensor(sensor_spec)
      Agent.add_sensor(agent, sensor)
    end)
    
    {:ok, agent}
  end
  
  def execute_on_agent(request) do
    # Direct registry lookup - no validation
    agent_pid = Jido.Agent.Registry.whereis!(request.agent_id)
    
    # Direct action execution
    result = Agent.execute_action(agent_pid, request.action, request.params)
    
    # Extract variables for our AI optimization
    variables = extract_variables_from_result(result)
    
    {:ok, result, variables}
  end
  
  # Helper functions - no validation needed
  defp build_skill(skill_spec) do
    # Direct skill creation
    Skill.new(skill_spec.name, skill_spec.config)
  end
  
  defp extract_variables_from_result(result) do
    # Our AI-specific variable extraction
    OurAI.VariableExtractor.extract(result)
  end
end
```

### Zone 4: Enhanced Jido Core

```elixir
defmodule OurAI.EnhancedJidoAgents do
  @moduledoc """
  Zone 4: Enhanced jido agents with AI-specific capabilities.
  """
  
  # Pure jido agent implementations with AI features
  
  defmodule LLMAgent do
    use Jido.Agent
    
    # No validation here - Zone 2 guarantees valid input
    def handle_action(:generate, params, state) do
      # Direct LLM call
      response = OurAI.LLM.generate(params.prompt, state.model_config)
      
      # Extract variables for optimization
      variables = %{
        "system_prompt" => state.system_prompt,
        "temperature" => state.model_config.temperature,
        "model" => state.model_config.model
      }
      
      # Return with variable data
      {:ok, response, %{state | last_response: response}, variables}
    end
    
    def handle_action(:optimize_variables, params, state) do
      # Use our optimization engine
      optimized = OurAI.Optimizer.optimize(params.variables, params.evaluation_fn)
      
      # Update state with optimized variables
      new_state = apply_variable_updates(state, optimized)
      
      {:ok, optimized, new_state}
    end
  end
  
  defmodule PipelineAgent do
    use Jido.Agent
    
    def handle_action(:execute_pipeline, params, state) do
      # Direct pipeline execution
      result = OurAI.Pipelines.execute(state.pipeline, params.input)
      
      {:ok, result, state}
    end
  end
end
```

## Perimeter-Enhanced Jido Patterns

### Pattern 1: Safe Jido Agent Creation

```elixir
defmodule OurAI.SafeAgentFactory do
  use Perimeter.Zone1
  
  defcontract llm_agent_config :: %{
    required(:model) => String.t(),
    required(:system_prompt) => String.t(),
    optional(:temperature) => float() |> between(0.0, 2.0),
    optional(:max_tokens) => pos_integer(),
    optional(:skills) => [skill_name()]
  }
  
  @guard input: llm_agent_config()
  def create_llm_agent(config) do
    # Validated config goes to jido
    jido_config = %{
      model_config: extract_model_config(config),
      system_prompt: config.system_prompt,
      skills: config.skills || []
    }
    
    # Direct jido usage in coupling zone
    {:ok, agent_pid} = OurAI.EnhancedJidoAgents.LLMAgent.start_link(jido_config)
    
    # Add skills through jido
    Enum.each(config.skills, fn skill_name ->
      skill = OurAI.SkillLibrary.get_skill(skill_name)
      Jido.Agent.add_skill(agent_pid, skill)
    end)
    
    {:ok, agent_pid}
  end
end
```

### Pattern 2: Variable-Aware Jido Actions

```elixir
defmodule OurAI.VariableAwareJido do
  @moduledoc """
  Wrapper that adds variable tracking to jido actions.
  """
  
  use Perimeter.Zone2
  
  defcontract action_with_variables :: %{
    required(:agent_id) => String.t(),
    required(:action) => atom(),
    required(:params) => map(),
    optional(:track_variables) => boolean()
  }
  
  @guard input: action_with_variables(),
         variable_extraction: true
  def execute_with_tracking(request) do
    # Execute through jido
    result = Jido.Agent.execute_action(
      request.agent_id, 
      request.action, 
      request.params
    )
    
    # Extract variables if requested
    variables = if request.track_variables do
      extract_variables_from_action(request.agent_id, request.action, result)
    else
      %{}
    end
    
    # Return enhanced result
    {:ok, result, variables}
  end
  
  defp extract_variables_from_action(agent_id, action, result) do
    # Get agent state
    agent_state = Jido.Agent.get_state(agent_id)
    
    # Extract variables based on action type
    OurAI.VariableExtractor.extract_from_action(action, agent_state, result)
  end
end
```

### Pattern 3: Jido Pipeline Integration

```elixir
defmodule OurAI.JidoPipelineIntegration do
  @moduledoc """
  Integration between our pipeline system and jido agents.
  """
  
  use Perimeter.Zone2
  
  defcontract pipeline_with_agents :: %{
    required(:pipeline_spec) => pipeline_spec(),
    required(:agent_assignments) => %{String.t() => String.t()},  # step_id -> agent_id
    optional(:optimization_config) => optimization_config()
  }
  
  @guard input: pipeline_with_agents()
  def execute_pipeline_with_agents(request) do
    # Compile pipeline
    compiled = OurAI.Pipelines.compile(request.pipeline_spec)
    
    # Execute each step through assigned jido agents
    results = Enum.map(compiled.steps, fn step ->
      agent_id = request.agent_assignments[step.id]
      
      # Direct jido execution
      Jido.Agent.execute_action(agent_id, step.action, step.params)
    end)
    
    # Aggregate results
    final_result = OurAI.Pipelines.aggregate_results(results)
    
    {:ok, final_result}
  end
end
```

## Benefits of Integration

### 1. **Keep Jido's Strengths**
- Runtime agent functionality works perfectly
- Skill and sensor systems are mature
- Process supervision is robust
- Community ecosystem exists

### 2. **Add Perimeter's Safety**
- Type safety at system boundaries
- Clear validation placement
- Protection from external threats
- Graceful error handling

### 3. **Enable AI Features**
- Variable extraction and optimization
- Performance tracking
- Multi-agent coordination
- Pipeline integration

### 4. **Minimize Risk**
- No need to rebuild jido
- Gradual integration possible
- Backward compatibility maintained
- Clear migration path

## Integration Timeline

### Week 1: Zone 1 External Perimeters
- Create external validation for agent creation
- Add perimeter guards for action execution
- Set up rate limiting and authentication

### Week 2: Zone 2 Jido Boundaries  
- Create strategic boundaries around jido components
- Add jido-specific validation helpers
- Implement error handling and recovery

### Week 3: Zone 3 Coupling Implementation
- Direct jido usage patterns
- Variable extraction integration
- Performance optimization

### Week 4: Zone 4 Enhanced Agents
- AI-specific jido agent implementations
- Pipeline integration
- Testing and validation

## Conclusion

**Jido + Perimeter = Best of Both Worlds**

This integration approach:
- ✅ Keeps jido's proven runtime capabilities
- ✅ Adds perimeter's type safety and architecture
- ✅ Enables AI-specific features and optimization
- ✅ Provides clear migration path
- ✅ Minimizes risk and development time

**Timeline**: 4 weeks to production-ready integrated system
**Risk**: Low (no fundamental changes to either system)
**Outcome**: Robust, type-safe agent platform with AI optimization capabilities