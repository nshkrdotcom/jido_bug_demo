# 109: Backward Compatibility Details

## Overview

This document provides comprehensive specifications for maintaining backward compatibility during the Jido framework reintegration, ensuring existing applications can migrate smoothly while preserving functionality and minimizing breaking changes.

## Compatibility Strategy

### 1. Version Detection and Routing

```elixir
# lib/jido/compat/version_detector.ex
defmodule Jido.Compat.VersionDetector do
  @moduledoc """
  Detects and routes between v1 and v2 APIs.
  """
  
  @v1_indicators [
    # Module patterns
    ~r/%\w+Agent{/,
    ~r/defstruct.*agent.*state/,
    
    # Field patterns
    ~r/\.jido_dispatch/,
    ~r/\.jido_meta/,
    
    # Import patterns
    ~r/{:jido_signal,/
  ]
  
  @doc """
  Detect if code is using v1 patterns.
  """
  def detect_version(code) when is_binary(code) do
    if Enum.any?(@v1_indicators, &Regex.match?(&1, code)) do
      :v1
    else
      :v2
    end
  end
  
  def detect_version(%module{}) when is_atom(module) do
    # Check runtime module structure
    cond do
      function_exported?(module, :__jido_agent__, 0) and
      Map.has_key?(module.__struct__, :__struct__) ->
        :v1  # Polymorphic agent
        
      function_exported?(module, :__jido_agent__, 0) ->
        :v2  # New agent format
        
      true ->
        :unknown
    end
  end
  
  @doc """
  Get compatibility mode for current application.
  """
  def compatibility_mode do
    case Application.get_env(:jido, :compatibility_mode, :auto) do
      :auto -> detect_app_version()
      :v1 -> :v1
      :v2 -> :v2
      mode -> mode
    end
  end
  
  defp detect_app_version do
    # Analyze application code
    case analyze_app_code() do
      %{v1_patterns: 0} -> :v2
      %{v1_patterns: count} when count > 0 -> :v1
      _ -> :v2  # Default to new version
    end
  end
end
```

### 2. Compatibility Layer

```elixir
# lib/jido/compat/layer.ex
defmodule Jido.Compat.Layer do
  @moduledoc """
  Provides compatibility layer for v1 code.
  """
  
  defmacro __using__(_opts) do
    quote do
      import Jido.Compat.Layer
      
      # Enable v1 compatibility
      @before_compile Jido.Compat.Layer
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      # Inject compatibility functions
      if Module.defines?(__MODULE__, {:__struct__, 0}) do
        Jido.Compat.Layer.make_struct_compatible(__MODULE__)
      end
      
      # Add deprecation warnings
      if function_exported?(__MODULE__, :__jido_agent__, 0) do
        Jido.Compat.Layer.add_agent_compatibility(__MODULE__)
      end
    end
  end
  
  @doc """
  Make polymorphic struct compatible with Instance.
  """
  def make_struct_compatible(module) do
    defoverridable [__struct__: 0, __struct__: 1]
    
    def __struct__ do
      IO.warn("""
      Using polymorphic agent struct #{inspect(__MODULE__)} is deprecated.
      Agents now use Jido.Agent.Instance. Please update your code.
      
      See migration guide: https://hexdocs.pm/jido/migration.html
      """, Macro.Env.stacktrace(__ENV__))
      
      # Return Instance-compatible structure
      %Jido.Agent.Instance{
        module: __MODULE__,
        state: %{},
        id: nil,
        config: %{},
        metadata: %{},
        __vsn__: "1.0.0",
        __dirty__: false
      }
    end
    
    def __struct__(kv) do
      # Convert to Instance format
      instance = __struct__()
      
      Enum.reduce(kv, instance, fn
        {:id, id}, acc -> %{acc | id: id}
        {:state, state}, acc -> %{acc | state: state}
        {k, v}, acc -> put_in(acc.state[k], v)
      end)
    end
  end
  
  @doc """
  Add agent compatibility functions.
  """
  def add_agent_compatibility(module) do
    # Override new/1 to return Instance
    def new(config \\ %{}) do
      IO.warn("""
      #{inspect(__MODULE__)}.new/1 now returns Jido.Agent.Instance.
      Update your pattern matches accordingly.
      """, Macro.Env.stacktrace(__ENV__))
      
      Jido.Agent.Instance.new(__MODULE__, config)
    end
    
    # Add conversion helper
    def to_instance(%__MODULE__{} = old_struct) do
      Jido.Compat.StructConverter.to_instance(old_struct)
    end
  end
end
```

### 3. Struct Conversion

```elixir
# lib/jido/compat/struct_converter.ex
defmodule Jido.Compat.StructConverter do
  @moduledoc """
  Converts between v1 structs and v2 Instance format.
  """
  
  alias Jido.Agent.Instance
  
  @doc """
  Convert v1 agent struct to Instance.
  """
  def to_instance(%module{} = v1_struct) when module != Instance do
    # Validate it's actually an agent
    unless function_exported?(module, :__jido_agent__, 0) do
      raise ArgumentError, "#{inspect(module)} is not a Jido Agent"
    end
    
    # Extract fields
    %Instance{
      id: get_field(v1_struct, :id, Jido.Core.ID.generate()),
      module: module,
      state: extract_state(v1_struct),
      config: get_field(v1_struct, :config, %{}),
      metadata: extract_metadata(v1_struct),
      __vsn__: get_version(module),
      __dirty__: get_field(v1_struct, :dirty_state?, false)
    }
  end
  
  def to_instance(%Instance{} = instance), do: instance
  
  @doc """
  Convert Instance to v1 struct format (for compatibility).
  """
  def from_instance(%Instance{} = instance, target_module) do
    # Get the struct definition
    struct_def = target_module.__struct__()
    
    # Map Instance fields to struct fields
    base_struct = %{
      __struct__: target_module,
      id: instance.id,
      state: instance.state,
      dirty_state?: instance.__dirty__
    }
    
    # Merge with default struct values
    Map.merge(struct_def, base_struct)
    |> Map.merge(instance.state)
  end
  
  defp extract_state(v1_struct) do
    # Get explicit state field or extract from struct
    case Map.get(v1_struct, :state) do
      nil ->
        # Extract non-framework fields as state
        v1_struct
        |> Map.from_struct()
        |> Map.drop([:id, :dirty_state?, :__struct__, :config])
        
      state ->
        state
    end
  end
  
  defp extract_metadata(v1_struct) do
    base_metadata = %{
      converted_at: DateTime.utc_now(),
      original_struct: v1_struct.__struct__
    }
    
    # Preserve any existing metadata
    case Map.get(v1_struct, :metadata) do
      nil -> base_metadata
      metadata -> Map.merge(metadata, base_metadata)
    end
  end
  
  defp get_field(struct, field, default) do
    Map.get(struct, field, default)
  end
  
  defp get_version(module) do
    if function_exported?(module, :vsn, 0) do
      module.vsn()
    else
      "1.0.0"
    end
  end
end
```

### 4. Signal Field Compatibility

```elixir
# lib/jido/compat/signal_compat.ex
defmodule Jido.Compat.SignalCompat do
  @moduledoc """
  Provides compatibility for signal field changes.
  """
  
  @doc """
  Wrap signal struct with compatibility access.
  """
  defmacro compat_signal(signal) do
    quote do
      %Jido.Compat.SignalWrapper{signal: unquote(signal)}
    end
  end
  
  defmodule SignalWrapper do
    @moduledoc false
    
    defstruct [:signal]
    
    # Delegate new field names
    defdelegate id, to: :signal
    defdelegate type, to: :signal
    defdelegate source, to: :signal
    defdelegate data, to: :signal
    
    # Provide compatibility for old field names
    def jido_dispatch(%__MODULE__{signal: signal}) do
      IO.warn("""
      Accessing signal.jido_dispatch is deprecated. Use signal.dispatch instead.
      """, Macro.Env.stacktrace(__ENV__))
      
      signal.dispatch
    end
    
    def jido_meta(%__MODULE__{signal: signal}) do
      IO.warn("""
      Accessing signal.jido_meta is deprecated. Use signal.meta instead.
      """, Macro.Env.stacktrace(__ENV__))
      
      signal.meta
    end
  end
  
  @doc """
  Update signal creation to handle old field names.
  """
  def new(params) when is_map(params) do
    migrated_params = migrate_params(params)
    Jido.Signal.new(migrated_params)
  end
  
  defp migrate_params(params) do
    params
    |> maybe_rename_field(:jido_dispatch, :dispatch)
    |> maybe_rename_field(:jido_meta, :meta)
    |> maybe_rename_field("jido_dispatch", "dispatch")
    |> maybe_rename_field("jido_meta", "meta")
  end
  
  defp maybe_rename_field(params, old_key, new_key) do
    case Map.pop(params, old_key) do
      {nil, params} -> params
      {value, params} -> 
        emit_deprecation_warning(old_key, new_key)
        Map.put(params, new_key, value)
    end
  end
  
  defp emit_deprecation_warning(old_key, new_key) do
    Process.put(:deprecation_warnings, 
      [{old_key, new_key} | Process.get(:deprecation_warnings, [])]
    )
  end
end
```

### 5. API Compatibility Shims

```elixir
# lib/jido/compat/api_shims.ex
defmodule Jido.Compat.ApiShims do
  @moduledoc """
  Provides API compatibility shims for v1 code.
  """
  
  @doc """
  Install compatibility shims based on detected version.
  """
  def install do
    case Jido.Compat.VersionDetector.compatibility_mode() do
      :v1 -> install_v1_shims()
      _ -> :ok
    end
  end
  
  defp install_v1_shims do
    # Override key functions with compatibility versions
    
    # Agent creation
    defoverridable [new: 1, new: 2]
    
    def new(module, config \\ %{}) when is_atom(module) do
      IO.warn("""
      Jido.new/2 is deprecated. Use Module.new/1 directly.
      """, Macro.Env.stacktrace(__ENV__))
      
      apply(module, :new, [config])
    end
    
    # Pattern matching helpers
    defmacro match_agent(module, pattern) do
      quote do
        %Jido.Agent.Instance{
          module: unquote(module)
        } = unquote(pattern)
      end
    end
    
    # Field access helpers
    def get_agent_field(agent, field) do
      case agent do
        %Jido.Agent.Instance{} = instance ->
          get_instance_field(instance, field)
          
        %module{} = v1_struct ->
          Map.get(v1_struct, field)
      end
    end
    
    defp get_instance_field(instance, field) do
      case field do
        :state -> instance.state
        :id -> instance.id
        field when is_atom(field) -> 
          # Check state map for v1 fields
          Map.get(instance.state, field)
      end
    end
  end
  
  @doc """
  Compatibility wrapper for action execution.
  """
  def run_action(action, params, context) do
    # Detect context format
    context = normalize_context(context)
    
    # Run with compatibility
    case apply(action, :run, [params, context]) do
      # Handle v1 response formats
      {:ok, result, directives} when is_list(directives) ->
        {:ok, result, directives}
        
      {:ok, result, directive} ->
        {:ok, result, [directive]}
        
      # v2 format
      result ->
        result
    end
  end
  
  defp normalize_context(context) do
    case context do
      %{agent: %module{}} = ctx when module != Jido.Agent.Instance ->
        # Convert v1 agent to Instance
        %{ctx | agent: Jido.Compat.StructConverter.to_instance(ctx.agent)}
        
      ctx ->
        ctx
    end
  end
end
```

### 6. Deprecation Warnings

```elixir
# lib/jido/compat/deprecation.ex
defmodule Jido.Compat.Deprecation do
  @moduledoc """
  Centralized deprecation warning system.
  """
  
  use GenServer
  
  defstruct [
    :warnings,
    :emitted,
    :config
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      warnings: %{},
      emitted: MapSet.new(),
      config: %{
        enabled: Keyword.get(opts, :enabled, true),
        once: Keyword.get(opts, :once, true),
        log_level: Keyword.get(opts, :log_level, :warn)
      }
    }
    
    {:ok, state}
  end
  
  @doc """
  Emit a deprecation warning.
  """
  def warn(feature, message, opts \\ []) do
    GenServer.cast(__MODULE__, {:warn, feature, message, opts})
  end
  
  @impl GenServer
  def handle_cast({:warn, feature, message, opts}, state) do
    if should_emit?(feature, state) do
      emit_warning(feature, message, opts, state.config)
      
      new_state = if state.config.once do
        %{state | emitted: MapSet.put(state.emitted, feature)}
      else
        state
      end
      
      # Track warning
      warnings = Map.update(state.warnings, feature, 1, &(&1 + 1))
      
      {:noreply, %{new_state | warnings: warnings}}
    else
      {:noreply, state}
    end
  end
  
  defp should_emit?(feature, state) do
    state.config.enabled and
    (not state.config.once or feature not in state.emitted)
  end
  
  defp emit_warning(feature, message, opts, config) do
    stacktrace = Keyword.get(opts, :stacktrace, get_stacktrace())
    
    full_message = """
    
    ================== DEPRECATION WARNING ==================
    Feature: #{feature}
    #{message}
    
    Called from:
    #{format_stacktrace(stacktrace)}
    
    Migration guide: https://hexdocs.pm/jido/migration.html##{slugify(feature)}
    ========================================================
    """
    
    Logger.log(config.log_level, full_message)
  end
  
  defp get_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stack} -> 
        # Skip internal frames
        Enum.drop(stack, 3)
      _ -> 
        []
    end
  end
  
  defp format_stacktrace(stack) do
    stack
    |> Enum.take(5)
    |> Enum.map(&Exception.format_stacktrace_entry/1)
    |> Enum.join("\n")
  end
  
  defp slugify(feature) do
    feature
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
  end
  
  @doc """
  Get deprecation report.
  """
  def report do
    GenServer.call(__MODULE__, :report)
  end
  
  @impl GenServer
  def handle_call(:report, _from, state) do
    report = %{
      total_warnings: map_size(state.warnings),
      warnings_by_feature: state.warnings,
      unique_features: MapSet.size(state.emitted)
    }
    
    {:reply, report, state}
  end
end
```

### 7. Runtime Compatibility Detection

```elixir
# lib/jido/compat/runtime.ex
defmodule Jido.Compat.Runtime do
  @moduledoc """
  Runtime compatibility detection and adaptation.
  """
  
  @doc """
  Wrap function calls with compatibility detection.
  """
  defmacro compat_call(module, function, args) do
    quote do
      Jido.Compat.Runtime.do_compat_call(
        unquote(module),
        unquote(function),
        unquote(args),
        __ENV__
      )
    end
  end
  
  def do_compat_call(module, function, args, env) do
    # Detect calling context
    version = detect_caller_version(env)
    
    # Transform arguments if needed
    transformed_args = transform_args(args, version, {module, function})
    
    # Call function
    result = apply(module, function, transformed_args)
    
    # Transform result if needed
    transform_result(result, version, {module, function})
  end
  
  defp detect_caller_version(env) do
    # Check if caller is using v1 patterns
    cond do
      using_polymorphic_struct?(env) -> :v1
      using_old_signal_fields?(env) -> :v1
      true -> :v2
    end
  end
  
  defp using_polymorphic_struct?(env) do
    # Analyze caller's module
    case env.module do
      nil -> false
      module ->
        module
        |> Module.get_attribute(:struct)
        |> Kernel.&&(function_exported?(module, :__jido_agent__, 0))
    end
  end
  
  defp transform_args(args, :v1, {Jido.Agent, :new}) do
    # Transform v1 agent creation
    case args do
      [config] -> [v1_to_v2_config(config)]
      args -> args
    end
  end
  
  defp transform_args(args, _, _), do: args
  
  defp transform_result({:ok, %Jido.Agent.Instance{} = instance}, :v1, {_, :new}) do
    # Wrap Instance for v1 compatibility
    wrapped = Jido.Compat.StructWrapper.wrap(instance)
    {:ok, wrapped}
  end
  
  defp transform_result(result, _, _), do: result
end
```

### 8. Gradual Migration Support

```elixir
# lib/jido/compat/migration_helper.ex
defmodule Jido.Compat.MigrationHelper do
  @moduledoc """
  Helpers for gradual migration from v1 to v2.
  """
  
  @doc """
  Migrate a module gradually.
  """
  defmacro migrate_module(module, opts \\ []) do
    quote do
      defmodule unquote(module).V2 do
        @moduledoc """
        Migrated version of #{inspect(unquote(module))}.
        """
        
        use Jido.Agent, unquote(opts)
        
        # Import v1 module functions
        import unquote(module), except: [new: 1, __struct__: 0]
        
        # Use v2 patterns
        def initial_state(config) do
          # Call v1 initialization if exists
          if function_exported?(unquote(module), :init, 1) do
            unquote(module).init(config)
          else
            {:ok, %{}}
          end
        end
        
        # Delegate other callbacks
        defdelegate handle_signal(signal, state), to: unquote(module)
        defdelegate handle_action(agent, instruction), to: unquote(module)
      end
      
      # Add switcher function
      def use_v2? do
        Application.get_env(:jido, :use_v2_modules, false)
      end
      
      def new(config \\ %{}) do
        if use_v2?() do
          unquote(module).V2.new(config)
        else
          # Original v1 implementation
          struct(__MODULE__, config)
        end
      end
    end
  end
  
  @doc """
  Gradually migrate pattern matches.
  """
  defmacro migrate_match(pattern, do: block) do
    quote do
      case unquote(pattern) do
        # Try v2 pattern first
        %Jido.Agent.Instance{} = instance ->
          unquote(block)
          
        # Fall back to v1 pattern
        %module{} = v1_struct when is_atom(module) ->
          # Convert and retry
          instance = Jido.Compat.StructConverter.to_instance(v1_struct)
          unquote(block)
      end
    end
  end
end
```

### 9. Compatibility Testing

```elixir
# test/compat/compatibility_test.exs
defmodule Jido.Compat.CompatibilityTest do
  use ExUnit.Case
  
  # Define v1-style agent for testing
  defmodule V1Agent do
    defstruct [:id, :state, :config, :dirty_state?]
    
    def __jido_agent__, do: true
    
    def new(config \\ %{}) do
      %__MODULE__{
        id: "test-id",
        state: %{count: 0},
        config: config,
        dirty_state?: false
      }
    end
  end
  
  describe "struct compatibility" do
    test "v1 struct converts to Instance" do
      v1_agent = V1Agent.new(%{name: "test"})
      
      instance = Jido.Compat.StructConverter.to_instance(v1_agent)
      
      assert %Jido.Agent.Instance{
        id: "test-id",
        module: V1Agent,
        state: %{count: 0},
        config: %{name: "test"}
      } = instance
    end
    
    test "Instance converts back to v1 struct" do
      {:ok, instance} = Jido.Agent.Instance.new(V1Agent, %{name: "test"})
      
      v1_struct = Jido.Compat.StructConverter.from_instance(instance, V1Agent)
      
      assert %V1Agent{
        id: instance.id,
        state: %{},
        config: %{name: "test"}
      } = v1_struct
    end
  end
  
  describe "signal field compatibility" do
    test "old field names are migrated" do
      params = %{
        id: "123",
        type: "test",
        source: "test",
        jido_dispatch: {:pid, self()},
        jido_meta: %{foo: "bar"}
      }
      
      {:ok, signal} = Jido.Compat.SignalCompat.new(params)
      
      assert signal.dispatch == {:pid, self()}
      assert signal.meta == %{foo: "bar"}
      refute Map.has_key?(signal, :jido_dispatch)
    end
  end
  
  describe "API compatibility" do
    test "v1 agent creation still works" do
      # Should emit deprecation warning
      assert capture_io(:stderr, fn ->
        {:ok, agent} = V1Agent.new()
        assert %Jido.Agent.Instance{} = agent
      end) =~ "deprecated"
    end
  end
end
```

### 10. Version-Specific Documentation

```elixir
# lib/jido/compat/docs.ex
defmodule Jido.Compat.Docs do
  @moduledoc """
  Version-specific documentation generator.
  """
  
  @doc """
  Generate compatibility documentation.
  """
  def generate do
    """
    # Jido Compatibility Guide
    
    ## Version Detection
    
    Jido automatically detects which version your code is using:
    
    ```elixir
    # V1 code (polymorphic structs)
    defmodule MyAgent do
      use Jido.Agent
      defstruct [:id, :state, :name]
    end
    
    # V2 code (Instance-based)
    defmodule MyAgent do
      use Jido.Agent
      
      def initial_state(config) do
        {:ok, %{name: config.name}}
      end
    end
    ```
    
    ## Gradual Migration
    
    You can migrate gradually using compatibility mode:
    
    ```elixir
    # config/config.exs
    config :jido, compatibility_mode: :v1
    ```
    
    ## Field Changes
    
    Signal fields have been renamed:
    - `jido_dispatch` → `dispatch`
    - `jido_meta` → `meta`
    
    Old field names still work but emit deprecation warnings.
    
    ## Pattern Matching
    
    Update pattern matches:
    
    ```elixir
    # Old
    case agent do
      %MyAgent{state: state} -> ...
    end
    
    # New
    case agent do
      %Jido.Agent.Instance{module: MyAgent, state: state} -> ...
    end
    ```
    
    ## For more information
    
    See the full migration guide: https://hexdocs.pm/jido/migration.html
    """
  end
end
```

This comprehensive backward compatibility system ensures existing Jido applications can migrate smoothly to the unified framework while maintaining functionality and providing clear upgrade paths.