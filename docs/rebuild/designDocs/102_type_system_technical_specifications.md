# 102: Type System Technical Specifications

## Overview

This document provides detailed technical specifications for the unified type system that will replace the polymorphic struct antipattern and enable proper compile-time guarantees across the integrated Jido framework.

## Core Type Hierarchy

### 1. Base Types Module Structure

```elixir
# lib/jido/core/types.ex
defmodule Jido.Core.Types do
  @moduledoc """
  Foundation types for the entire Jido framework.
  All type references should originate from this module.
  """
  
  # Primitive types
  @type id :: <<_::288>>  # UUID v7 binary (36 bytes)
  @type timestamp :: DateTime.t()
  @type timeout :: non_neg_integer() | :infinity
  @type version :: String.t()  # Semantic version
  
  # Collection types
  @type metadata :: %{optional(atom() | String.t()) => any()}
  @type options :: keyword()
  
  # Result types
  @type ok(value) :: {:ok, value}
  @type error :: {:error, error_reason()}
  @type error_reason :: Jido.Core.Error.t() | String.t() | atom()
  @type result(value) :: ok(value) | error()
  @type result() :: result(any())
  
  # Maybe type for optional values
  @type maybe(value) :: value | nil
  
  # Validation types
  @type validation_error :: {:validation_error, field :: atom(), message :: String.t()}
  @type validation_result :: :ok | {:error, [validation_error()]}
end
```

### 2. Error Type Specifications

```elixir
# lib/jido/core/error.ex
defmodule Jido.Core.Error do
  use TypedStruct
  
  @type error_type :: 
    :validation_error |
    :execution_error |
    :timeout_error |
    :not_found |
    :permission_denied |
    :configuration_error |
    :type_mismatch |
    :serialization_error |
    :dispatch_error |
    :routing_error |
    :agent_error |
    :action_error |
    :signal_error |
    :internal_error
    
  @type error_context :: %{
    optional(:agent_id) => String.t(),
    optional(:action) => module(),
    optional(:signal_id) => String.t(),
    optional(:instruction_id) => String.t(),
    optional(:timestamp) => DateTime.t(),
    optional(:node) => node(),
    optional(atom()) => any()
  }
  
  typedstruct do
    field :type, error_type(), enforce: true
    field :message, String.t(), enforce: true
    field :details, map(), default: %{}
    field :context, error_context(), default: %{}
    field :stacktrace, Exception.stacktrace() | nil
    field :parent, t() | nil  # For error chaining
  end
  
  @spec wrap(error :: any(), type :: error_type(), message :: String.t()) :: t()
  def wrap(error, type, message) when is_exception(error) do
    %__MODULE__{
      type: type,
      message: message,
      details: %{
        original_error: Exception.message(error),
        original_type: error.__struct__
      },
      stacktrace: __STACKTRACE__,
      parent: error_to_t(error)
    }
  end
end
```

### 3. Agent Type Specifications

```elixir
# lib/jido/agent/types.ex
defmodule Jido.Agent.Types do
  alias Jido.Core.Types
  
  # Agent identifiers
  @type agent_id :: Types.id()
  @type agent_ref :: agent_id() | pid() | GenServer.name()
  
  # Agent modules must export these functions
  @type agent_module :: module()
  @callback __jido_agent__() :: true
  @callback initial_state(config :: map()) :: Types.result(agent_state())
  @callback vsn() :: Types.version()
  
  # Agent state
  @type agent_state :: map()
  @type agent_config :: map()
  @type agent_metadata :: Types.metadata()
  
  # Agent instance (replaces polymorphic structs)
  @type instance :: Jido.Agent.Instance.t()
  
  # Agent results
  @type agent_result :: Types.result(instance())
  @type execution_result :: Types.result(execution_output())
  @type execution_output :: %{
    required(:agent) => instance(),
    optional(:result) => any(),
    optional(:directives) => [Jido.Agent.Directive.t()]
  }
  
  # Agent lifecycle
  @type lifecycle_stage :: 
    :initializing |
    :ready |
    :planning |
    :executing |
    :suspended |
    :terminating
    
  # Agent capabilities
  @type capability :: 
    :stateful |
    :async |
    :distributed |
    :persistent |
    :supervised
end
```

### 4. Action Type Specifications

```elixir
# lib/jido/action/types.ex
defmodule Jido.Action.Types do
  alias Jido.Core.Types
  
  # Action modules must export these functions
  @type action_module :: module()
  @callback __jido_action__() :: true
  @callback run(params :: params(), context :: context()) :: action_result()
  
  # Action parameters and context
  @type params :: %{optional(atom()) => any()}
  @type context :: %{
    required(:agent) => Jido.Agent.Instance.t(),
    optional(:signal) => Jido.Signal.t(),
    optional(:instruction) => Jido.Instruction.t(),
    optional(:correlation_id) => Types.id(),
    optional(:causation_id) => Types.id(),
    optional(:timeout) => Types.timeout(),
    optional(atom()) => any()
  }
  
  # Action results
  @type action_result :: Types.result(action_output())
  @type action_output :: map()
  
  # Action results with directives
  @type directive :: Jido.Agent.Directive.t()
  @type action_result_with_directives :: 
    {:ok, action_output()} |
    {:ok, action_output(), directive() | [directive()]} |
    {:error, Types.error_reason()}
    
  # Action metadata
  @type action_metadata :: %{
    name: String.t(),
    description: String.t(),
    category: String.t(),
    tags: [String.t()],
    vsn: Types.version(),
    schema: NimbleOptions.schema(),
    output_schema: NimbleOptions.schema()
  }
  
  # Action lifecycle callbacks
  @type lifecycle_stage :: 
    :validating_params |
    :preparing |
    :executing |
    :compensating |
    :completing
end
```

### 5. Signal Type Specifications

```elixir
# lib/jido/signal/types.ex
defmodule Jido.Signal.Types do
  alias Jido.Core.Types
  
  # CloudEvents core types
  @type ce_version :: String.t()  # "1.0"
  @type ce_type :: String.t()     # Reverse-DNS format
  @type ce_source :: String.t()   # URI-reference
  @type ce_subject :: String.t()  # Context subject
  
  # Signal instance
  @type signal :: Jido.Signal.t()
  @type signal_id :: Types.id()
  
  # Signal data
  @type signal_data :: map() | binary() | String.t()
  @type content_type :: String.t()  # MIME type
  
  # Dispatch configuration
  @type dispatch_adapter :: 
    :pid | :named | :pubsub | :logger | 
    :console | :noop | :http | :webhook | :bus
    
  @type dispatch_opts :: keyword()
  @type dispatch_config :: 
    dispatch_adapter() |
    {dispatch_adapter(), dispatch_opts()} |
    [dispatch_config()]
    
  # Routing types
  @type route_pattern :: String.t()  # "user.*", "order.#"
  @type route_target :: any()
  @type route_priority :: -100..100
  @type route_options :: %{
    optional(:priority) => route_priority(),
    optional(:filter) => (signal() -> boolean()),
    optional(:transform) => (signal() -> signal())
  }
  
  # Bus types
  @type subscription_id :: Types.id()
  @type subscriber :: %{
    id: subscription_id(),
    pattern: route_pattern(),
    target: route_target(),
    created_at: Types.timestamp()
  }
end
```

### 6. Instruction Type Specifications

```elixir
# lib/jido/instruction/types.ex
defmodule Jido.Instruction.Types do
  alias Jido.Core.Types
  alias Jido.Action.Types, as: ActionTypes
  
  # Instruction instance
  @type instruction :: Jido.Instruction.t()
  @type instruction_id :: Types.id()
  
  # Instruction collections
  @type instruction_list :: [instruction()]
  @type instruction_queue :: :queue.queue(instruction())
  
  # Instruction creation inputs
  @type instruction_input ::
    ActionTypes.action_module() |
    {ActionTypes.action_module(), ActionTypes.params()} |
    {ActionTypes.action_module(), ActionTypes.params(), ActionTypes.context()} |
    instruction()
    
  # Instruction state
  @type instruction_state :: 
    :pending |
    :executing |
    :completed |
    :failed |
    :compensated
    
  # Instruction metadata
  @type instruction_metadata :: %{
    optional(:created_at) => Types.timestamp(),
    optional(:started_at) => Types.timestamp(),
    optional(:completed_at) => Types.timestamp(),
    optional(:retry_count) => non_neg_integer(),
    optional(:parent_id) => instruction_id(),
    optional(atom()) => any()
  }
end
```

## Type Conversion Specifications

### 1. Agent Struct Migration

```elixir
# lib/jido/agent/instance_converter.ex
defmodule Jido.Agent.InstanceConverter do
  @moduledoc """
  Converts legacy polymorphic agent structs to Instance format.
  """
  
  alias Jido.Agent.Instance
  alias Jido.Agent.Types
  
  @doc """
  Detects if a value is a legacy agent struct.
  """
  @spec legacy_agent?(any()) :: boolean()
  def legacy_agent?(%module{} = struct) do
    # Check if it has agent-like fields but isn't Instance
    module != Instance &&
    Map.has_key?(struct, :id) &&
    Map.has_key?(struct, :state) &&
    function_exported?(module, :__jido_agent__, 0)
  end
  
  @doc """
  Converts a legacy agent to Instance format.
  """
  @spec to_instance(struct()) :: {:ok, Instance.t()} | {:error, term()}
  def to_instance(%module{} = legacy_agent) do
    with true <- legacy_agent?(legacy_agent) do
      {:ok, %Instance{
        id: Map.get(legacy_agent, :id),
        module: module,
        state: Map.get(legacy_agent, :state, %{}),
        config: extract_config(legacy_agent),
        metadata: extract_metadata(legacy_agent),
        __vsn__: module.vsn(),
        __dirty__: Map.get(legacy_agent, :dirty_state?, false)
      }}
    else
      false -> {:error, "Not a legacy agent struct"}
    end
  end
end
```

### 2. Signal Field Migration

```elixir
# lib/jido/signal/field_migrator.ex
defmodule Jido.Signal.FieldMigrator do
  @moduledoc """
  Migrates legacy jido_dispatch fields to new format.
  """
  
  @doc """
  Migrates signal fields from old to new format.
  """
  @spec migrate_fields(map()) :: map()
  def migrate_fields(%{"jido_dispatch" => dispatch} = signal) do
    signal
    |> Map.delete("jido_dispatch")
    |> Map.put("dispatch", dispatch)
    |> migrate_meta_field()
  end
  
  def migrate_fields(%{jido_dispatch: dispatch} = signal) do
    signal
    |> Map.delete(:jido_dispatch)
    |> Map.put(:dispatch, dispatch)
    |> migrate_meta_field()
  end
  
  def migrate_fields(signal), do: migrate_meta_field(signal)
  
  defp migrate_meta_field(%{"jido_meta" => meta} = signal) do
    signal
    |> Map.delete("jido_meta")
    |> Map.put("meta", meta)
  end
  
  defp migrate_meta_field(%{jido_meta: meta} = signal) do
    signal
    |> Map.delete(:jido_meta)
    |> Map.put(:meta, meta)
  end
  
  defp migrate_meta_field(signal), do: signal
end
```

## Type Validation Specifications

### 1. Runtime Type Validation

```elixir
# lib/jido/core/type_validator.ex
defmodule Jido.Core.TypeValidator do
  @moduledoc """
  Runtime type validation for critical paths.
  """
  
  alias Jido.Core.Types
  
  @doc """
  Validates a value against a type specification.
  """
  @spec validate(value :: any(), type :: atom()) :: Types.validation_result()
  def validate(value, :agent_id) when is_binary(value) do
    if valid_uuid?(value), do: :ok, else: type_error(:agent_id, value)
  end
  
  def validate(value, :action_module) when is_atom(value) do
    if function_exported?(value, :__jido_action__, 0) do
      :ok
    else
      {:error, [{:validation_error, :action_module, "Not a valid action module"}]}
    end
  end
  
  def validate(value, :signal) do
    required_fields = [:id, :type, :source, :specversion]
    missing = Enum.reject(required_fields, &Map.has_key?(value, &1))
    
    if missing == [] do
      :ok
    else
      {:error, Enum.map(missing, fn field ->
        {:validation_error, field, "Required field missing"}
      end)}
    end
  end
  
  @spec valid_uuid?(String.t()) :: boolean()
  defp valid_uuid?(string) do
    case UUID.info(string) do
      {:ok, _} -> true
      _ -> false
    end
  end
  
  defp type_error(expected_type, actual_value) do
    {:error, [{:validation_error, expected_type, 
      "Expected #{expected_type}, got: #{inspect(actual_value)}"}]}
  end
end
```

### 2. Compile-Time Type Checking

```elixir
# lib/jido/core/type_check.ex
defmodule Jido.Core.TypeCheck do
  @moduledoc """
  Compile-time type checking macros.
  """
  
  @doc """
  Ensures a module implements required callbacks.
  """
  defmacro ensure_behaviour(module, behaviour) do
    quote do
      unless unquote(module) in Module.get_attribute(__MODULE__, :behaviour, []) do
        raise CompileError,
          description: "Module must implement #{inspect(unquote(behaviour))} behaviour"
      end
    end
  end
  
  @doc """
  Validates function specifications at compile time.
  """
  defmacro validate_spec(function, arity, expected_spec) do
    quote do
      @after_compile {unquote(__MODULE__), :__validate_spec__, 
        [unquote(function), unquote(arity), unquote(expected_spec)]}
    end
  end
  
  def __validate_spec__(env, function, arity, expected_spec) do
    case Typespec.get_spec(env.module, function, arity) do
      nil ->
        IO.warn("No @spec found for #{function}/#{arity}", env)
      
      actual_spec ->
        unless compatible_spec?(actual_spec, expected_spec) do
          raise CompileError,
            description: "Invalid @spec for #{function}/#{arity}. " <>
                        "Expected: #{inspect(expected_spec)}"
        end
    end
  end
end
```

## Dialyzer Type Specifications

### 1. PLT Configuration

```elixir
# .dialyzer_ignore.exs
[
  # Ignore warnings from legacy code during migration
  {"lib/jido/migration/agent_compat.ex", :unknown_function},
  
  # Temporary ignores for gradual migration
  {"lib/jido/agent.ex", :pattern_match, 100..200}
]
```

### 2. Type Spec Generator

```elixir
# lib/mix/tasks/jido.generate_types.ex
defmodule Mix.Tasks.Jido.GenerateTypes do
  @moduledoc """
  Generates type specification files for dialyzer.
  """
  
  use Mix.Task
  
  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    
    specs = collect_type_specs()
    generate_type_file(specs)
    generate_dialyzer_config(specs)
  end
  
  defp collect_type_specs do
    for module <- all_jido_modules(),
        {type, spec} <- Typespec.get_types(module) do
      {module, type, spec}
    end
  end
  
  defp generate_type_file(specs) do
    content = EEx.eval_string("""
    # Generated type specifications for Jido
    # Generated at: <%= DateTime.utc_now() %>
    
    <%= for {module, type, spec} <- specs do %>
    # <%= inspect(module) %>.<%= type %>
    <%= Macro.to_string(spec) %>
    <% end %>
    """, specs: specs)
    
    File.write!("priv/types/jido_types.ex", content)
  end
end
```

## Type System Integration Points

### 1. With OTP Behaviors

```elixir
# Type-safe GenServer integration
defmodule Jido.Agent.Server do
  use GenServer
  
  # Properly typed state
  @type state :: %{
    agent: Jido.Agent.Instance.t(),
    subscribers: %{Jido.Signal.Types.subscription_id() => pid()},
    children: %{Jido.Core.Types.id() => pid()},
    config: map()
  }
  
  @impl GenServer
  @spec init(keyword()) :: {:ok, state()} | {:stop, term()}
  def init(opts) do
    # Type-safe initialization
  end
end
```

### 2. With External Libraries

```elixir
# Integration with NimbleOptions
defmodule Jido.Schema do
  @spec to_nimble_schema(keyword()) :: NimbleOptions.schema()
  def to_nimble_schema(internal_schema) do
    Enum.map(internal_schema, fn {key, spec} ->
      {key, convert_type_spec(spec)}
    end)
  end
  
  defp convert_type_spec({:type, type}), do: [type: type]
  defp convert_type_spec({:required, type}), do: [type: type, required: true]
end
```

## Type Safety Guarantees

### 1. Invariants

- All agent operations return `Jido.Agent.Instance.t()`
- All errors are wrapped in `Jido.Core.Error.t()`
- All IDs are UUID v7 format
- All timestamps are UTC `DateTime`
- All module references are validated at runtime

### 2. Type Contracts

```elixir
# Every public API must have these properties:
# 1. Explicit @spec annotation
# 2. Result type (success/error tuple)
# 3. Validated inputs
# 4. Consistent error handling
```

This comprehensive type system specification provides the foundation for a type-safe, maintainable, and dialyzer-friendly Jido framework.