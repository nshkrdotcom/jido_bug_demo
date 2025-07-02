defmodule Jido.Signal.Dispatch do
  alias Jido.Signal.Error

  @moduledoc """
  A flexible signal dispatching system that routes signals to various destinations using configurable adapters.

  The Dispatch module serves as the central hub for signal delivery in the Jido system. It provides a unified
  interface for sending signals to different destinations through various adapters. Each adapter implements
  specific delivery mechanisms suited for different use cases.

  ## Built-in Adapters

  The following adapters are provided out of the box:

  * `:pid` - Direct delivery to a specific process (see `Jido.Signal.Dispatch.PidAdapter`)
  * `:bus` - Delivery to an event bus (**UNSUPPORTED** - implementation pending)
  * `:named` - Delivery to a named process (see `Jido.Signal.Dispatch.Named`)
  * `:pubsub` - Delivery via PubSub mechanism (see `Jido.Signal.Dispatch.PubSub`)
  * `:logger` - Log signals using Logger (see `Jido.Signal.Dispatch.LoggerAdapter`)
  * `:console` - Print signals to console (see `Jido.Signal.Dispatch.ConsoleAdapter`)
  * `:noop` - No-op adapter for testing/development (see `Jido.Signal.Dispatch.NoopAdapter`)
  * `:http` - HTTP requests using :httpc (see `Jido.Signal.Dispatch.Http`)
  * `:webhook` - Webhook delivery with signatures (see `Jido.Signal.Dispatch.Webhook`)

  ## Configuration

  Each adapter requires specific configuration options. A dispatch configuration is a tuple of
  `{adapter_type, options}` where:

  * `adapter_type` - One of the built-in adapter types above or a custom module implementing the `Jido.Signal.Dispatch.Adapter` behaviour
  * `options` - Keyword list of options specific to the chosen adapter

  Multiple dispatch configurations can be provided as a list to send signals to multiple destinations.

  ## Dispatch Modes

  The module supports three dispatch modes:

  1. Synchronous (via `dispatch/2`) - Fire-and-forget dispatch that returns when all dispatches complete
  2. Asynchronous (via `dispatch_async/2`) - Returns immediately with a task that can be monitored
  3. Batched (via `dispatch_batch/3`) - Handles large numbers of dispatches in configurable batches

  ## Examples

      # Synchronous dispatch
      config = {:pid, [target: pid, delivery_mode: :async]}
      :ok = Dispatch.dispatch(signal, config)

      # Asynchronous dispatch
      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)

      # Batch dispatch
      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, batch_size: 100)

      # HTTP dispatch
      config = {:http, [
        url: "https://api.example.com/events",
        method: :post,
        headers: [{"x-api-key", "secret"}]
      ]}
      :ok = Dispatch.dispatch(signal, config)

      # Webhook dispatch
      config = {:webhook, [
        url: "https://api.example.com/webhook",
        secret: "webhook_secret",
        event_type_map: %{"user:created" => "user.created"}
      ]}
      :ok = Dispatch.dispatch(signal, config)
  """

  @type adapter ::
          :pid
          | :named
          | :pubsub
          | :logger
          | :console
          | :noop
          | :http
          | :webhook
          | nil
          | module()
  @type dispatch_config :: {adapter(), Keyword.t()}
  @type dispatch_configs :: dispatch_config() | [dispatch_config()]
  @type batch_opts :: [
          batch_size: pos_integer(),
          max_concurrency: pos_integer()
        ]

  @default_batch_size 50
  @default_max_concurrency 5
  @normalize_errors_compile_time Application.compile_env(:jido, :normalize_dispatch_errors, false)

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    named: Jido.Signal.Dispatch.Named,
    pubsub: Jido.Signal.Dispatch.PubSub,
    logger: Jido.Signal.Dispatch.LoggerAdapter,
    console: Jido.Signal.Dispatch.ConsoleAdapter,
    noop: Jido.Signal.Dispatch.NoopAdapter,
    http: Jido.Signal.Dispatch.Http,
    webhook: Jido.Signal.Dispatch.Webhook,
    nil: nil
  }

  # Future Idea
  # use TypedStruct

  # typedstruct do
  #   @typedoc "A dispatch configuration for sending signals"

  #   field :signals, Jido.Signal.t() | [Jido.Signal.t()], default: [], doc: "List of signals to be dispatched"
  #   field :targets, [dispatch_config()], default: [], doc: "List of dispatch_config tuples"
  #   field :mode, :sync | :async, default: :sync, doc: ":sync or :async"
  #   field :opts, Keyword.t(), default: [], doc: "General options including batch settings"
  #   field :validated, boolean(), default: false, doc: "Whether targets have been validated"
  # end

  @doc """
  Validates a dispatch configuration.

  ## Parameters

  - `config` - Either a single dispatch configuration tuple or a list of dispatch configurations

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      # Single config
      iex> config = {:pid, [target: {:pid, self()}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Multiple configs
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: {:pubsub, :audit}, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  # Handle single dispatcher config
  def validate_opts(config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    validate_single_config(config)
  end

  # Handle list of dispatchers
  def validate_opts(configs) when is_list(configs) do
    results = Enum.map(configs, &validate_single_config/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, value} -> value end)}
      error -> error
    end
  end

  def validate_opts(_), do: {:error, :invalid_dispatch_config}

  @doc """
  Dispatches a signal using the provided configuration.

  This is a synchronous operation that returns when all dispatches complete.
  For asynchronous dispatch, use `dispatch_async/2`.
  For batch dispatch, use `dispatch_batch/3`.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Examples

      # Single destination
      iex> config = {:pid, [target: {:pid, pid}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Multiple destinations
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: :audit, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  # Handle single dispatcher
  def dispatch(signal, config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    dispatch_single(signal, config)
  end

  # Handle multiple dispatchers
  def dispatch(signal, configs) when is_list(configs) do
    results = Enum.map(configs, &dispatch_single(signal, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  def dispatch(_signal, _config) do
    {:error, :invalid_dispatch_config}
  end

  @doc """
  Dispatches a signal asynchronously using the provided configuration.

  Returns immediately with a task that can be monitored for completion.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Returns

  - `{:ok, task}` where task is a Task that can be awaited
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)
  """
  @spec dispatch_async(Jido.Signal.t(), dispatch_configs()) :: {:ok, Task.t()} | {:error, term()}
  def dispatch_async(signal, config) do
    case validate_opts(config) do
      {:ok, validated_config} ->
        task =
          Task.Supervisor.async_nolink(Jido.Signal.TaskSupervisor, fn ->
            dispatch(signal, validated_config)
          end)

        {:ok, task}

      error ->
        error
    end
  end

  @doc """
  Dispatches a signal to multiple destinations in batches.

  This is useful when dispatching to a large number of destinations to avoid
  overwhelming the system. The dispatches are processed in batches of configurable
  size with configurable concurrency.

  ## Parameters

  - `signal` - The signal to dispatch
  - `configs` - List of dispatch configurations
  - `opts` - Batch options:
    * `:batch_size` - Size of each batch (default: #{@default_batch_size})
    * `:max_concurrency` - Maximum number of concurrent batches (default: #{@default_max_concurrency})

  ## Returns

  - `:ok` if all dispatches succeed
  - `{:error, errors}` where errors is a list of `{index, reason}` tuples

  ## Examples

      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, batch_size: 100)
  """
  @spec dispatch_batch(Jido.Signal.t(), [dispatch_config()], batch_opts()) ::
          :ok | {:error, [{non_neg_integer(), term()}]}
  def dispatch_batch(signal, configs, opts \\ []) when is_list(configs) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)

    validation_results = validate_configs_with_index(configs)
    {valid_configs, validation_errors} = split_validation_results(validation_results)

    validated_configs_with_idx = extract_validated_configs(valid_configs)

    dispatch_results =
      process_batches(signal, validated_configs_with_idx, batch_size, max_concurrency)

    validation_errors = extract_validation_errors(validation_errors)
    dispatch_errors = extract_dispatch_errors(dispatch_results)

    combine_results(validation_errors, dispatch_errors)
  end

  # Batch processing helpers

  defp validate_configs_with_index(configs) do
    configs_with_index = Enum.with_index(configs)

    Enum.map(configs_with_index, fn {config, idx} ->
      case validate_opts(config) do
        {:ok, validated_config} -> {:ok, {validated_config, idx}}
        {:error, reason} -> {:error, {idx, reason}}
      end
    end)
  end

  defp split_validation_results(validation_results) do
    Enum.split_with(validation_results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
  end

  defp extract_validated_configs(valid_configs) do
    Enum.map(valid_configs, fn {:ok, {config, idx}} -> {config, idx} end)
  end

  defp process_batches(signal, validated_configs_with_idx, batch_size, max_concurrency) do
    if validated_configs_with_idx != [] do
      batches = Enum.chunk_every(validated_configs_with_idx, batch_size)

      Task.Supervisor.async_stream(
        Jido.Signal.TaskSupervisor,
        batches,
        fn batch ->
          Enum.map(batch, fn {config, original_idx} ->
            case dispatch_single(signal, config) do
              :ok -> {:ok, original_idx}
              {:error, reason} -> {:error, {original_idx, reason}}
            end
          end)
        end,
        max_concurrency: max_concurrency,
        ordered: true
      )
      |> Enum.flat_map(fn {:ok, batch_results} -> batch_results end)
    else
      []
    end
  end

  defp extract_validation_errors(validation_errors) do
    Enum.map(validation_errors, fn {:error, error} -> error end)
  end

  defp extract_dispatch_errors(dispatch_results) do
    Enum.reduce(dispatch_results, [], fn
      {:error, error}, acc -> [error | acc]
      {:ok, _}, acc -> acc
    end)
  end

  defp combine_results(validation_errors, dispatch_errors) do
    case {validation_errors, dispatch_errors} do
      {[], []} -> :ok
      {errors, []} -> {:error, Enum.reverse(errors)}
      {[], errors} -> {:error, Enum.reverse(errors)}
      {val_errs, disp_errs} -> {:error, Enum.reverse(val_errs ++ disp_errs)}
    end
  end

  # Private helpers

  defp normalize_error(reason, adapter, config) when is_atom(reason) do
    if should_normalize_errors?() do
      details = %{
        adapter: adapter,
        reason: reason,
        config: config
      }

      {:error, Error.dispatch_error("Dispatch failed: #{reason}", details)}
    else
      {:error, reason}
    end
  end

  defp normalize_error(%Error{} = error, _adapter, _config) do
    {:error, error}
  end

  defp normalize_error(reason, adapter, config) do
    if should_normalize_errors?() do
      details = %{
        adapter: adapter,
        reason: reason,
        config: config
      }

      {:error, Error.dispatch_error("Dispatch failed", details)}
    else
      {:error, reason}
    end
  end

  defp should_normalize_errors? do
    @normalize_errors_compile_time or
      Application.get_env(:jido, :normalize_dispatch_errors, false)
  end

  defp get_target_from_opts(opts) do
    cond do
      target = Keyword.get(opts, :target) -> target
      url = Keyword.get(opts, :url) -> url
      pid = Keyword.get(opts, :pid) -> pid
      name = Keyword.get(opts, :name) -> name
      topic = Keyword.get(opts, :topic) -> topic
      true -> :unknown
    end
  end

  defp validate_single_config({nil, opts}) when is_list(opts) do
    {:ok, {nil, opts}}
  end

  defp validate_single_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    case resolve_adapter(adapter) do
      {:ok, adapter_module} ->
        if adapter_module == nil do
          {:ok, {adapter, opts}}
        else
          case adapter_module.validate_opts(opts) do
            {:ok, validated_opts} -> {:ok, {adapter, validated_opts}}
            {:error, reason} -> normalize_error(reason, adapter, {adapter, opts})
          end
        end

      {:error, reason} ->
        normalize_error(reason, adapter, {adapter, opts})
    end
  end

  defp dispatch_single(_signal, {nil, _opts}), do: :ok

  defp dispatch_single(signal, {adapter, opts}) do
    start_time = System.monotonic_time(:millisecond)

    signal_type =
      case signal do
        %{type: type} -> type
        _ -> :unknown
      end

    metadata = %{
      adapter: adapter,
      signal_type: signal_type,
      target: get_target_from_opts(opts)
    }

    :telemetry.execute([:jido, :dispatch, :start], %{}, metadata)

    result = do_dispatch_single(signal, {adapter, opts})

    end_time = System.monotonic_time(:millisecond)
    latency_ms = end_time - start_time
    success = match?(:ok, result)

    measurements = %{latency_ms: latency_ms}
    metadata = Map.merge(metadata, %{success?: success})

    if success do
      :telemetry.execute([:jido, :dispatch, :stop], measurements, metadata)
    else
      :telemetry.execute([:jido, :dispatch, :exception], measurements, metadata)
    end

    result
  end

  defp do_dispatch_single(signal, {adapter, opts}) do
    case resolve_adapter(adapter) do
      {:ok, adapter_module} ->
        do_dispatch_with_adapter(signal, adapter_module, {adapter, opts})

      {:error, reason} ->
        normalize_error(reason, adapter, {adapter, opts})
    end
  end

  defp do_dispatch_with_adapter(_signal, nil, {_adapter, _opts}), do: :ok

  defp do_dispatch_with_adapter(signal, adapter_module, {adapter, opts}) do
    case adapter_module.validate_opts(opts) do
      {:ok, validated_opts} ->
        case adapter_module.deliver(signal, validated_opts) do
          :ok -> :ok
          {:error, reason} -> normalize_error(reason, adapter, {adapter, opts})
        end

      {:error, reason} ->
        normalize_error(reason, adapter, {adapter, opts})
    end
  end

  defp resolve_adapter(nil), do: {:ok, nil}

  defp resolve_adapter(adapter) when is_atom(adapter) do
    case Map.fetch(@builtin_adapters, adapter) do
      {:ok, module} when not is_nil(module) ->
        {:ok, module}

      {:ok, nil} ->
        {:error, :no_adapter_needed}

      :error ->
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, :deliver, 2) do
          {:ok, adapter}
        else
          {:error,
           "#{inspect(adapter)} is not a valid adapter - must be one of :pid, :named, :pubsub, :logger, :console, :noop, :http, :webhook or a module implementing deliver/2"}
        end
    end
  end
end
