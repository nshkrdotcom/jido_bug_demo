# Jido Library Comprehensive Map

## Overview

This document provides a complete mapping of the jido library structure, documenting every module, function, type, and their relationships. This serves as the definitive AS-IS reference for the codebase analysis.

## Library Structure

```
jido/lib/
├── jido.ex                         # Main entry point
├── jido/
│   ├── action.ex                   # Action behavior
│   ├── actions/                    # Built-in actions (10 files)
│   ├── agent.ex                    # Agent behavior
│   ├── agent/                      # Agent implementation (14 files)
│   ├── application.ex              # OTP application
│   ├── discovery.ex                # Component registry
│   ├── error.ex                    # Error handling
│   ├── exec.ex                     # Execution engine
│   ├── exec/                       # Exec support (2 files)
│   ├── instruction.ex              # Instruction types
│   ├── runner.ex                   # Runner behavior
│   ├── runner/                     # Runner implementations (2 files)
│   ├── scheduler.ex                # Quantum scheduler
│   ├── sensor.ex                   # Sensor behavior
│   ├── sensors/                    # Built-in sensors (3 files)
│   ├── skill.ex                    # Skill behavior
│   ├── skills/                     # Built-in skills (2 files)
│   ├── supervisor.ex               # Helper supervisor
│   ├── telemetry.ex                # Telemetry integration
│   └── util.ex                     # Utilities
```

## Core Modules

### jido.ex
**Purpose**: Main entry point and high-level API for the Jido framework  
**Dependencies**: Discovery, Registry, Util

#### Module: Jido (lines 1-185)

#### Public Functions
- `get_agent/2` (lines 30-45) - Retrieves a running Agent by its ID
- `get_agent!/2` (lines 50-60) - Pipe-friendly version that raises on errors
- `get_agent_state/1` (lines 65-76) - Gets the current state of an agent
- `clone_agent/3` (lines 81-95) - Clones an existing agent with a new ID
- `ensure_started/1` (lines 100-104) - Called by generated `start_link/0` function
- `resolve_pid/1` (lines 109-119) - Resolves a server reference to a PID

#### Delegated Functions (lines 125-185)
- `list_actions/1` - Delegates to Discovery.list_actions/1
- `list_sensors/1` - Delegates to Discovery.list_sensors/1
- `list_agents/1` - Delegates to Discovery.list_agents/1
- `list_skills/1` - Delegates to Discovery.list_skills/1
- `list_demos/1` - Delegates to Discovery.list_demos/1
- `get_action_by_slug/1` - Delegates to Discovery.get_action_by_slug/1
- `get_sensor_by_slug/1` - Delegates to Discovery.get_sensor_by_slug/1
- `get_agent_by_slug/1` - Delegates to Discovery.get_agent_by_slug/1
- `get_skill_by_slug/1` - Delegates to Discovery.get_skill_by_slug/1
- `get_demo_by_slug/1` - Delegates to Discovery.get_demo_by_slug/1

#### Types
- `@type component_metadata :: Discovery.component_metadata()` (line 15)
- `@type server :: GenServer.server() | {:via, module(), term()} | pid()` (line 16)

---

### jido/action.ex
**Purpose**: Defines the behavior and structure for Actions - discrete, composable units of functionality  
**Dependencies**: Error, Util, NimbleOptions

#### Module: Jido.Action (lines 1-892)
- **Behaviors**: None (defines behavior)
- **Attributes**: Module registration for action_attrs

#### Types (lines 45-65)
- `@type name :: String.t()`
- `@type description :: String.t()`
- `@type category :: String.t()`
- `@type tags :: [String.t()]`
- `@type vsn :: String.t()`
- `@type on_error_opt :: :retry | :abort | :continue | :compensate`
- `@type t :: %__MODULE__{}` - Action struct

#### Callbacks (lines 70-145)
- `@callback run(params :: map(), context :: map()) :: result` (required)
- `@callback on_before_validate_params(params :: map()) :: params :: map()`
- `@callback on_after_validate_params(params :: map()) :: params :: map()`
- `@callback on_before_validate_output(output :: any()) :: output :: any()`
- `@callback on_after_validate_output(output :: any()) :: output :: any()`
- `@callback on_after_run(output :: any()) :: output :: any()`
- `@callback on_error(error :: Jido.Error.t(), params :: map(), context :: map(), opts :: keyword()) :: result`

#### Generated Functions (via __using__ macro)
- `name/0` (lines 350-355) - Returns action name
- `description/0` (lines 360-365) - Returns description
- `category/0` (lines 370-375) - Returns category
- `tags/0` (lines 380-385) - Returns tags list
- `vsn/0` (lines 390-395) - Returns version
- `schema/0` (lines 400-405) - Returns parameter schema
- `output_schema/0` (lines 410-415) - Returns output schema
- `to_json/0` (lines 420-435) - JSON representation
- `to_tool/0` (lines 440-485) - LLM tool format conversion
- `validate_params/1` (lines 490-520) - Validates input parameters
- `validate_output/1` (lines 525-555) - Validates output

#### Private Functions
- `process_action_opts/2` (lines 600-650) - Process use macro options
- `build_tool_properties/1` (lines 700-750) - Build LLM tool properties
- `build_validate_params/0` (lines 800-850) - Build param validation function

---

### jido/agent.ex
**Purpose**: Defines stateful task executors that plan and execute Actions  
**Dependencies**: Error, Signal, Instruction, Directive, Runner, Util

#### Module: Jido.Agent (lines 1-1285)
- **Behaviors**: None (defines behavior)
- **Attributes**: Module registration for agent attributes

#### Types (lines 90-120)
- `@type t :: struct()`
- `@type agent_state :: map()`
- `@type instruction :: Instruction.instruction()`
- `@type instruction_list :: Instruction.instruction_list()`
- `@type result :: {:ok, any()} | {:error, any()}`
- `@type agent_result :: {:ok, t()} | {:error, Error.t()}`
- `@type runner :: module()`

#### Callbacks (lines 125-245)
- `@callback on_before_validate_state(state :: map()) :: state :: map()`
- `@callback on_after_validate_state(state :: map()) :: state :: map()`
- `@callback on_before_plan(agent :: t(), instructions :: instruction_list(), opts :: keyword()) :: {agent :: t(), instructions :: instruction_list()}`
- `@callback on_before_run(agent :: t()) :: agent :: t()`
- `@callback on_after_run(agent :: t(), result :: any(), opts :: keyword()) :: result :: any()`
- `@callback on_error(agent :: t(), error :: Jido.Error.t()) :: agent :: t()`
- `@callback mount(agent :: t(), server_state :: Agent.Server.State.t()) :: {:ok, Agent.Server.State.t()} | {:error, any()}`
- `@callback shutdown(reason :: term(), server_state :: Agent.Server.State.t()) :: :ok`
- `@callback handle_signal(signal :: Signal.t(), server_state :: Agent.Server.State.t()) :: {:noreply, Agent.Server.State.t()} | {:stop, term(), Agent.Server.State.t()}`
- `@callback transform_result(agent :: t(), result :: any(), call_context :: atom()) :: any()`

#### Public Functions
- `new/2` (lines 300-330) - Creates new agent instance with ID and initial state
- `set/3` (lines 335-365) - Updates agent state by deep merging attributes
- `validate/2` (lines 370-400) - Validates agent state against schema
- `plan/3` (lines 405-450) - Plans actions by adding to pending queue
- `run/2` (lines 455-500) - Executes pending instructions via runner
- `cmd/4` (lines 505-540) - Validates, plans and executes instructions
- `reset/1` (lines 545-560) - Resets pending action queue
- `pending?/1` (lines 565-575) - Returns count of pending actions
- `register_action/2` (lines 580-600) - Registers action modules at runtime
- `deregister_action/2` (lines 605-625) - Removes action modules
- `registered_actions/1` (lines 630-640) - Lists all registered actions

#### Private Functions
- `build_agent_struct/1` (lines 700-750) - Builds agent struct definition
- `validate_state/2` (lines 800-850) - Internal state validation
- `normalize_instructions/3` (lines 900-950) - Instruction normalization
- `apply_directives/2` (lines 1000-1100) - Apply agent directives

---

### jido/sensor.ex
**Purpose**: GenServer that emits Signals based on events and retains last values  
**Dependencies**: Error, Signal, Util

#### Module: Jido.Sensor (lines 1-725)
- **Behaviors**: GenServer
- **Attributes**: Module registration for sensor attributes

#### Types (lines 60-70)
- `@type t :: %__MODULE__{}` - Sensor struct
- `@type options :: keyword()`

#### Callbacks (lines 75-105)
- `@callback mount(state :: map()) :: {:ok, state :: map()} | {:error, any()}`
- `@callback deliver_signal(state :: map()) :: Signal.t() | nil`
- `@callback on_before_deliver(signal :: Signal.t(), state :: map()) :: {signal :: Signal.t(), state :: map()}`
- `@callback shutdown(state :: map()) :: :ok`

#### Generated Functions (via __using__ macro)
- `name/0` (lines 250-255) - Returns sensor name
- `description/0` (lines 260-265) - Returns description
- `category/0` (lines 270-275) - Returns category
- `tags/0` (lines 280-285) - Returns tags
- `vsn/0` (lines 290-295) - Returns version
- `schema/0` (lines 300-305) - Returns config schema
- `to_json/0` (lines 310-325) - JSON representation
- `start_link/1` (lines 330-340) - Starts sensor process
- `get_config/1` (lines 345-355) - Get all config
- `get_config/2` (lines 360-370) - Get specific config value
- `set_config/2` (lines 375-385) - Update multiple config values
- `set_config/3` (lines 390-400) - Update single config value

#### GenServer Callbacks
- `init/1` (lines 450-480) - Initialize sensor state
- `handle_call/3` (lines 485-550) - Handle sync requests
- `handle_info/2` (lines 555-600) - Handle async messages
- `terminate/2` (lines 605-620) - Cleanup on termination

---

### jido/skill.ex
**Purpose**: Defines reusable capability packs with signal routing, state management, and process supervision  
**Dependencies**: Signal, Error

#### Module: Jido.Skill (lines 1-580)
- **Behaviors**: None (defines behavior)
- **Attributes**: Module registration for skill attributes

#### Types (lines 45-55)
- `@type t :: %__MODULE__{}` - Skill struct
- `@type agent :: Jido.Agent.t()`
- `@type server_state :: Jido.Agent.Server.State.t()`

#### Callbacks (lines 60-90)
- `@callback child_spec(opts :: keyword()) :: Supervisor.child_spec() | nil`
- `@callback router(opts :: keyword()) :: Signal.Router.t() | nil`
- `@callback handle_signal(signal :: Signal.t(), server_state) :: {:noreply, server_state} | {:stop, term(), server_state}`
- `@callback transform_result(agent, result :: any(), call_context :: atom()) :: any()`
- `@callback mount(agent, server_state) :: {:ok, server_state} | {:error, any()}`

#### Generated Functions (via __using__ macro)
- `name/0` (lines 200-205) - Returns skill name
- `description/0` (lines 210-215) - Returns description
- `category/0` (lines 220-225) - Returns category
- `tags/0` (lines 230-235) - Returns tags
- `vsn/0` (lines 240-245) - Returns version
- `opts_key/0` (lines 250-255) - Returns state namespace key
- `signal_patterns/0` (lines 260-265) - Returns handled signal patterns
- `opts_schema/0` (lines 270-275) - Returns config schema
- `to_json/0` (lines 280-295) - JSON representation

---

### jido/instruction.ex
**Purpose**: Represents discrete units of work with action, parameters, context and options  
**Dependencies**: Error, Util

#### Module: Jido.Instruction (lines 1-420)
- **Behaviors**: Uses TypedStruct

#### Types (lines 30-50)
- `@type t :: %__MODULE__{}` - Instruction struct
- `@type instruction :: various instruction formats`
- `@type instruction_list :: [instruction()]`

#### Public Functions
- `new!/1` (lines 100-110) - Creates instruction or raises error
- `new/1` (lines 115-140) - Creates instruction returning result tuple
- `normalize_single/3` (lines 145-200) - Normalizes single instruction
- `normalize/3` (lines 205-240) - Normalizes instruction inputs to list
- `normalize!/3` (lines 245-255) - Same as normalize but raises
- `validate_allowed_actions/2` (lines 260-280) - Validates actions are allowed

#### Private Functions
- `build_instruction/4` (lines 300-350) - Build instruction struct
- `extract_context/1` (lines 355-380) - Extract context from instruction

---

### jido/error.ex
**Purpose**: Standardized error structures and handling  
**Dependencies**: TypedStruct

#### Module: Jido.Error (lines 1-485)
- **Behaviors**: Exception protocol

#### Types (lines 20-35)
- `@type error_type :: atom()` - Error type enumeration
- `@type t :: %__MODULE__{}` - Error struct

#### Public Functions
- `new/4` (lines 60-75) - Creates new error struct
- `invalid_action/3` (lines 80-90) - Invalid action error
- `invalid_sensor/3` (lines 95-105) - Invalid sensor error
- `bad_request/3` (lines 110-120) - Bad request error
- `validation_error/3` (lines 125-135) - Validation error
- `config_error/3` (lines 140-150) - Configuration error
- `execution_error/3` (lines 155-165) - Execution error
- `planning_error/3` (lines 170-180) - Planning error
- `action_error/3` (lines 185-195) - General action error
- `internal_server_error/3` (lines 200-210) - Internal error
- `timeout/3` (lines 215-225) - Timeout error
- `invalid_async_ref/3` (lines 230-240) - Invalid async reference
- `routing_error/3` (lines 245-255) - Routing error
- `dispatch_error/3` (lines 260-270) - Dispatch error
- `compensation_error/3` (lines 275-285) - Compensation error
- `to_map/1` (lines 290-310) - Convert to plain map
- `capture_stacktrace/0` (lines 315-325) - Capture current stacktrace
- `format_nimble_config_error/3` (lines 330-380) - Format config errors
- `format_nimble_validation_error/3` (lines 385-435) - Format validation errors

---

### jido/exec.ex
**Purpose**: Robust execution engine for Actions with retries, timeouts, and telemetry  
**Dependencies**: Error, Instruction, Logger, Telemetry

#### Module: Jido.Exec (lines 1-380)
- **Behaviors**: None

#### Types (lines 25-35)
- `@type async_ref :: reference()`
- `@type run_opts :: keyword()`

#### Public Functions
- `run/4` (lines 60-120) - Execute action synchronously
- `run_async/4` (lines 125-160) - Execute action asynchronously
- `await/2` (lines 165-200) - Wait for async result
- `cancel/1` (lines 205-220) - Cancel running async action

#### Private Functions
- `do_run/4` (lines 250-300) - Internal execution logic
- `handle_timeout/2` (lines 305-320) - Timeout handling
- `validate_options/1` (lines 325-350) - Option validation

---

### jido/discovery.ex
**Purpose**: Component registry with caching and lookup of Actions, Sensors, Agents, Skills  
**Dependencies**: :persistent_term, :crypto

#### Module: Jido.Discovery (lines 1-680)
- **Behaviors**: None

#### Types (lines 20-35)
- `@type component :: atom()`
- `@type component_type :: :action | :sensor | :agent | :skill | :demo`
- `@type component_metadata :: map()`
- `@type filter_fun :: (component_metadata() -> boolean())`

#### Public Functions
- `init/0` (lines 60-80) - Initialize discovery cache
- `refresh/0` (lines 85-100) - Force cache refresh
- `last_updated/0` (lines 105-115) - Get cache update time
- `get_action_by_slug/1` (lines 120-130) - Find action by slug
- `get_sensor_by_slug/1` (lines 135-145) - Find sensor by slug
- `get_agent_by_slug/1` (lines 150-160) - Find agent by slug
- `get_skill_by_slug/1` (lines 165-175) - Find skill by slug
- `get_demo_by_slug/1` (lines 180-190) - Find demo by slug
- `list_actions/1` (lines 195-210) - List actions with filters
- `list_sensors/1` (lines 215-230) - List sensors with filters
- `list_agents/1` (lines 235-250) - List agents with filters
- `list_skills/1` (lines 255-270) - List skills with filters
- `list_demos/1` (lines 275-290) - List demos with filters

#### Private Functions
- `discover_components/0` (lines 350-450) - Discover all components
- `build_cache/1` (lines 455-500) - Build component cache
- `slugify/1` (lines 505-520) - Convert name to slug
- `filter_components/2` (lines 525-550) - Apply filters to components

---

### jido/util.ex
**Purpose**: Collection of utility functions used throughout the framework  
**Dependencies**: Error, Signal.ID, Logger

#### Module: Jido.Util (lines 1-280)
- **Behaviors**: None

#### Public Functions
- `generate_id/0` (lines 25-30) - Generate unique ID
- `string_to_binary!/1` (lines 35-45) - Convert string to binary
- `validate_name/1` (lines 50-65) - Validate component names
- `validate_actions/1` (lines 70-90) - Validate action modules list
- `validate_runner/1` (lines 95-110) - Validate runner module
- `pluck/2` (lines 115-125) - Extract field from enumerable
- `via_tuple/2` (lines 130-140) - Create via tuple for registration
- `whereis/2` (lines 145-165) - Find process by name/pid
- `cond_log/4` (lines 170-195) - Conditional logging

---

### jido/runner.ex
**Purpose**: Behavior for executing planned actions on an Agent  
**Dependencies**: None (behavior definition)

#### Module: Jido.Runner (lines 1-85)
- **Behaviors**: None (defines behavior)

#### Types (lines 20-25)
- `@type agent :: Jido.Agent.t()`
- `@type result :: {:ok, agent} | {:error, any()}`

#### Callbacks (lines 30-35)
- `@callback run(agent, opts :: keyword()) :: result`

---

### jido/telemetry.ex
**Purpose**: Centralized telemetry event handling and metrics  
**Dependencies**: :telemetry, Logger

#### Module: Jido.Telemetry (lines 1-320)
- **Behaviors**: GenServer

#### Public Functions
- `start_link/1` (lines 30-40) - Start telemetry handler
- `handle_event/4` (lines 45-200) - Handle telemetry events
- `span/2` (lines 205-230) - Execute function with telemetry

#### Private Functions
- `log_event/3` (lines 250-280) - Log telemetry events
- `format_metadata/1` (lines 285-300) - Format event metadata

---

### jido/application.ex
**Purpose**: OTP application entry point  
**Dependencies**: Supervisor, Logger

#### Module: Jido.Application (lines 1-120)
- **Behaviors**: Application

#### Public Functions
- `start/2` (lines 20-80) - Start application supervision tree
- `stop/1` (lines 85-90) - Stop application

#### Children Started
1. Jido.Telemetry
2. Task.Supervisor (name: Jido.TaskSupervisor)
3. Registry (name: Jido.Registry)
4. DynamicSupervisor (name: Jido.Agent.Supervisor)
5. Jido.Scheduler (name: Jido.Quantum)

---

### jido/supervisor.ex
**Purpose**: Helper supervisor for Jido instances  
**Dependencies**: Supervisor

#### Module: Jido.Supervisor (lines 1-95)
- **Behaviors**: Supervisor

#### Public Functions
- `start_link/2` (lines 25-35) - Start supervisor
- `init/1` (lines 40-75) - Initialize children

---

### jido/scheduler.ex
**Purpose**: Quantum-based job scheduler integration  
**Dependencies**: Quantum

#### Module: Jido.Scheduler (lines 1-35)
- **Behaviors**: Uses Quantum
- **Note**: Simply declares `use Quantum, otp_app: :jido`

---

## Runner Implementations

### jido/runner/simple.ex
**Purpose**: Executes single instruction from agent's queue  
**Dependencies**: Instruction, Error, Agent.Directive, Exec

#### Module: Jido.Runner.Simple (lines 1-180)
- **Behaviors**: Jido.Runner

#### Public Functions
- `run/2` (lines 30-120) - Execute single instruction

#### Private Functions
- `execute_instruction/3` (lines 130-160) - Execute with error handling

---

### jido/runner/chain.ex
**Purpose**: Sequential instruction execution with result chaining  
**Dependencies**: Instruction, Agent.Directive, Error, Exec

#### Module: Jido.Runner.Chain (lines 1-285)
- **Behaviors**: Jido.Runner

#### Options
- `merge_results` (default: true) - Flow results between instructions
- `apply_directives?` (default: true) - Apply directives during execution

#### Public Functions
- `run/2` (lines 35-180) - Execute instruction chain

#### Private Functions
- `execute_chain/4` (lines 190-250) - Recursive chain execution
- `merge_context/3` (lines 255-270) - Merge execution contexts

---

## Action Collections

### jido/actions/basic.ex
**Purpose**: Collection of basic reusable actions  
**Dependencies**: Jido.Action

#### Module: Jido.Actions.Basic (lines 1-15)
- Contains multiple nested action modules

#### Action: Sleep (lines 20-45)
- **Schema**: duration (required, non_neg_integer)
- **run/2**: Sleeps for specified milliseconds

#### Action: Log (lines 50-85)
- **Schema**: message (required), level (optional, default: :info)
- **run/2**: Logs message at specified level

#### Action: Todo (lines 90-115)
- **Schema**: description (required, string)
- **run/2**: Logs TODO placeholder

#### Action: RandomSleep (lines 120-155)
- **Schema**: min (required), max (required)
- **run/2**: Sleeps random duration in range

#### Action: Increment (lines 160-185)
- **Schema**: value (required, integer)
- **run/2**: Returns value + 1

#### Action: Decrement (lines 190-215)
- **Schema**: value (required, integer)
- **run/2**: Returns value - 1

#### Action: Noop (lines 220-235)
- **Schema**: none
- **run/2**: Returns empty map

#### Action: Inspect (lines 240-265)
- **Schema**: value (required)
- **run/2**: Inspects and returns value

#### Action: Today (lines 270-290)
- **Schema**: none
- **run/2**: Returns current date

---

### Additional Built-in Actions

#### jido/actions/directives.ex
Contains directive-focused actions:
- `SetState` - Sets agent state
- `UpdateState` - Updates state with function
- `Emit` - Emits signals
- `Enqueue` - Enqueues instructions

#### jido/actions/chain.ex
- `Chain` - Chains multiple actions sequentially

#### jido/actions/result.ex
- `Result` - Returns value as-is

#### jido/actions/runtime.ex
- `Runtime` - Runtime execution actions

#### jido/actions/state_manager.ex
- `StateManager` - Complex state management

#### jido/actions/steps.ex
- `Steps` - Step-based execution

#### jido/actions/workflow.ex
- `Workflow` - Workflow management actions

---

## Agent Server Components

### jido/agent/server.ex
**Purpose**: GenServer implementation managing agent lifecycle and runtime  
**Dependencies**: Multiple Server.* submodules

#### Module: Jido.Agent.Server (lines 1-380)
- **Behaviors**: GenServer

#### Public Functions
- `start_link/1` (lines 40-60) - Start agent server
- `child_spec/1` (lines 65-85) - Supervisor child spec
- `state/1` (lines 90-100) - Get current state
- `call/3` (lines 105-120) - Synchronous signal
- `cast/2` (lines 125-135) - Asynchronous signal
- `via_tuple/2` (lines 140-150) - Registration tuple

#### GenServer Callbacks
- `init/1` (lines 160-200) - Initialize server
- `handle_call/3` (lines 205-250) - Handle sync requests
- `handle_cast/2` (lines 255-280) - Handle async messages
- `handle_info/2` (lines 285-310) - Handle info messages
- `terminate/2` (lines 315-330) - Cleanup

---

### jido/agent/directive.ex
**Purpose**: Type-safe agent state modifications through validated directives  
**Dependencies**: Error, Instruction

#### Module: Jido.Agent.Directive (lines 1-580)
- **Behaviors**: Uses TypedStruct for each directive type

#### Directive Types
- `Enqueue` (lines 50-80) - Add instruction to queue
- `StateModification` (lines 85-120) - Modify state at path
- `RegisterAction` (lines 125-150) - Register action module
- `DeregisterAction` (lines 155-180) - Remove action module
- `Spawn` (lines 185-220) - Spawn child process
- `Kill` (lines 225-250) - Terminate child process

#### Public Functions
- `apply_agent_directive/3` (lines 280-350) - Apply to Agent struct
- `apply_server_directive/3` (lines 355-425) - Apply to ServerState
- `split_directives/1` (lines 430-450) - Split agent/server directives

#### Private Functions
- `normalize_directive/1` (lines 480-550) - Normalize directive formats

---

### Additional Agent Server Modules

#### jido/agent/server/state.ex
- Server state management with skills, children, dispatch config

#### jido/agent/server/init.ex
- Server initialization logic

#### jido/agent/server/call.ex
- Synchronous call handling

#### jido/agent/server/cast.ex
- Asynchronous cast handling

#### jido/agent/server/signal.ex
- Signal processing and dispatch

#### jido/agent/server/skill.ex
- Skill mounting and management

#### jido/agent/server/supervisor_utils.ex
- Child process supervision utilities

---

## Built-in Sensors

### jido/sensors/heartbeat.ex
**Purpose**: Periodic heartbeat signal emission  
**Dependencies**: Jido.Sensor

#### Module: Jido.Sensors.Heartbeat (lines 1-120)
- **Schema**: interval_ms (default: 60000), custom_data (optional)
- **mount/1**: Schedules recurring heartbeat
- **deliver_signal/1**: Creates heartbeat signal

---

### jido/sensors/timer.ex
**Purpose**: One-shot timer signal after delay  
**Dependencies**: Jido.Sensor

#### Module: Jido.Sensors.Timer (lines 1-110)
- **Schema**: delay_ms (required), signal_data (optional)
- **mount/1**: Schedules one-time timer
- **deliver_signal/1**: Creates timer signal

---

### jido/sensors/bus.ex (COMMENTED OUT)
**Purpose**: Should monitor signals from a Jido.Bus  
**Dependencies**: Would depend on Jido.Signal.Bus
**Note**: Entire module is commented out due to circular dependency with jido_signal

---

## Built-in Skills

### jido/skills/workflow.ex
**Purpose**: Workflow orchestration capabilities  
**Dependencies**: Jido.Skill

#### Module: Jido.Skills.Workflow (lines 1-180)
- Provides workflow management patterns
- Signal patterns for workflow events
- Child spec for workflow processes

---

### jido/skills/artemis_skills.ex
**Purpose**: Collection of Artemis-specific skills  
**Dependencies**: Jido.Skill

#### Module: Jido.Skills.ArtemisSkills (lines 1-250)
- Multiple nested skill modules for Artemis functionality
- Includes file operations, command execution, etc.

---

## Exec Support Modules

### jido/exec/task_supervisor.ex
**Purpose**: Task supervision for async execution  
**Dependencies**: Task.Supervisor

#### Module: Jido.Exec.TaskSupervisor (lines 1-95)
- Manages async task lifecycle
- Provides task tracking and cancellation

---

### jido/exec/with_span.ex
**Purpose**: Telemetry span wrapper for execution  
**Dependencies**: Telemetry

#### Module: Jido.Exec.WithSpan (lines 1-85)
- Wraps execution with telemetry events
- Captures timing and metadata

---

## Key Architectural Patterns

1. **Behavior-Based Design**: Core components (Action, Agent, Sensor, Skill) are behaviors with comprehensive callbacks
2. **Compile-Time Configuration**: Components configured via `use` macro with NimbleOptions validation
3. **Result Tuples**: Consistent `{:ok, result} | {:error, Error.t()}` pattern throughout
4. **State Management**: Agents maintain validated state with dirty tracking and schema validation
5. **Instruction Queue**: Agents queue instructions for execution by configurable runners
6. **Directive System**: Type-safe state modifications with agent and server directives
7. **Discovery System**: Runtime component registry with caching and slug-based lookup
8. **Process Supervision**: Full OTP supervision tree with DynamicSupervisor for agents
9. **Telemetry Integration**: Built-in observability with standardized event names
10. **Error Handling**: Structured errors with type, message, details, and optional stacktrace
11. **Signal Integration**: Deep integration with jido_signal for event-driven communication
12. **Modular Actions**: Composable action system with lifecycle callbacks
13. **Skill System**: Reusable capability packs with signal routing and child processes
14. **Runner Abstraction**: Pluggable execution strategies (Simple, Chain)
15. **Utility Module**: Centralized utilities preventing code duplication

## Notable Issues and Observations

1. **Bus Sensor Commented Out**: The bus sensor (jido/sensors/bus.ex) is completely commented out due to circular dependency with jido_signal
2. **Action Duplication**: Significant code duplication exists between jido and jido_action implementations
3. **String-Based Coupling**: Heavy use of string-based type references for cross-package communication
4. **Complex Server Structure**: Agent.Server split into many submodules (14 files) for organization
5. **Signal Dependency**: Deep dependency on jido_signal throughout the codebase
6. **Type Safety Concerns**: Polymorphic struct pattern in agents could cause dialyzer issues
7. **Discovery Performance**: Discovery system rebuilds entire cache on refresh
8. **Limited Documentation**: Many internal modules lack comprehensive documentation

## Module Dependency Graph

```
Jido (Main API)
├── Agent (Core Behavior)
│   ├── Agent.Server (GenServer Implementation)
│   │   └── Server.* (14 submodules)
│   ├── Agent.Directive (State Modifications)
│   ├── Runner (Execution Strategy)
│   └── Instruction (Work Units)
├── Action (Core Behavior)
│   ├── Exec (Execution Engine)
│   └── Actions.* (Built-in Actions)
├── Sensor (Core Behavior)
│   └── Sensors.* (Built-in Sensors)
├── Skill (Core Behavior)
│   └── Skills.* (Built-in Skills)
├── Discovery (Component Registry)
├── Error (Standardized Errors)
├── Util (Common Utilities)
├── Telemetry (Observability)
├── Application (OTP App)
├── Supervisor (Helper Supervisor)
└── Scheduler (Quantum Integration)
```

This comprehensive map provides a complete view of the jido library structure, ready for refactoring analysis and planning.