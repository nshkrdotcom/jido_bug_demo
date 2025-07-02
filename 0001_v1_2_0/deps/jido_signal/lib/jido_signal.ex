defmodule Jido.Signal do
  @moduledoc """
  Defines the core Signal structure in Jido, implementing the CloudEvents specification (v1.0.2)
  with Jido-specific extensions for agent-based systems.

  https://cloudevents.io/

  ## Overview

  Signals are the universal message format in Jido, serving as the nervous system of your
  agent-based application. Every event, command, and state change flows through the system
  as a Signal, providing:

  - Standardized event structure (CloudEvents v1.0.2 compatible)
  - Rich metadata and context tracking
  - Flexible dispatch configuration
  - Automatic serialization

  ## CloudEvents Compliance

  Each Signal implements the CloudEvents v1.0.2 specification with these required fields:

  - `specversion`: Always "1.0.2"
  - `id`: Unique identifier (UUID v4)
  - `source`: Origin of the event ("/service/component")
  - `type`: Classification of the event ("domain.entity.action")

  And optional fields:

  - `subject`: Specific subject of the event
  - `time`: Timestamp in ISO 8601 format
  - `datacontenttype`: Media type of the data (defaults to "application/json")
  - `dataschema`: Schema defining the data structure
  - `data`: The actual event payload

  ## Jido Extensions

  Beyond the CloudEvents spec, Signals include Jido-specific fields:

  - `jido_dispatch`: Routing and delivery configuration (optional)

  ## Creating Signals

  Signals can be created in several ways:

  ```elixir
  # Basic event
  {:ok, signal} = Signal.new(%{
    type: "user.created",
    source: "/auth/registration",
    data: %{user_id: "123", email: "user@example.com"}
  })

  # With dispatch config
  {:ok, signal} = Signal.new(%{
    type: "metrics.collected",
    source: "/monitoring",
    data: %{cpu: 80, memory: 70},
    jido_dispatch: {:pubsub, topic: "metrics"}
  })
  ```

  ## Custom Signal Types

  You can define custom Signal types using the `use Jido.Signal` pattern:

  ```elixir
  defmodule MySignal do
    use Jido.Signal,
      type: "my.custom.signal",
      default_source: "/my/service",
      datacontenttype: "application/json",
      schema: [
        user_id: [type: :string, required: true],
        message: [type: :string, required: true]
      ]
  end

  # Create instances
  {:ok, signal} = MySignal.new(%{user_id: "123", message: "Hello"})

  # Override runtime fields
  {:ok, signal} = MySignal.new(
    %{user_id: "123", message: "Hello"},
    source: "/different/source",
    subject: "user-notification",
    jido_dispatch: {:pubsub, topic: "events"}
  )
  ```

  ## Signal Types

  Signal types are strings, but typically use a hierarchical dot notation:

  ```
  <domain>.<entity>.<action>[.<qualifier>]
  ```

  Examples:
  - `user.profile.updated`
  - `order.payment.processed.success`
  - `system.metrics.collected`

  Guidelines for type naming:
  - Use lowercase with dots
  - Keep segments meaningful
  - Order from general to specific
  - Include qualifiers when needed

  ## Data Content Types

  The `datacontenttype` field indicates the format of the `data` field:

  - `application/json` (default) - JSON-structured data
  - `text/plain` - Unstructured text
  - `application/octet-stream` - Binary data
  - Custom MIME types for specific formats

  ## Dispatch Configuration

  The `jido_dispatch` field controls how the Signal is delivered:

  ```elixir
  # Single dispatch config
  jido_dispatch: {:pubsub, topic: "events"}

  # Multiple dispatch targets
  jido_dispatch: [
    {:pubsub, topic: "events"},
    {:logger, level: :info},
    {:webhook, url: "https://api.example.com/webhook"}
  ]
  ```

  ## See Also

  - `Jido.Signal.Router` - Signal routing
  - `Jido.Signal.Dispatch` - Dispatch handling
  - CloudEvents spec: https://cloudevents.io/
  """
  alias Jido.Signal.Dispatch
  alias Jido.Signal.ID
  use TypedStruct

  @signal_config_schema NimbleOptions.new!(
                          type: [
                            type: :string,
                            required: true,
                            doc: "The type of the Signal"
                          ],
                          default_source: [
                            type: :string,
                            required: false,
                            doc: "The default source of the Signal"
                          ],
                          datacontenttype: [
                            type: :string,
                            required: false,
                            doc: "The content type of the data field"
                          ],
                          dataschema: [
                            type: :string,
                            required: false,
                            doc: "Schema URI for the data field (optional)"
                          ],
                          schema: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "A NimbleOptions schema for validating the Signal's data parameters"
                          ]
                        )

  @derive {Jason.Encoder,
           only: [
             :id,
             :source,
             :type,
             :subject,
             :time,
             :datacontenttype,
             :dataschema,
             :data,
             :specversion
           ]}

  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true, default: ID.generate!())
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    # Jido-specific fields
    field(:jido_dispatch, Dispatch.dispatch_configs())
  end

  @doc """
  Defines a new Signal module.

  This macro sets up the necessary structure and callbacks for a custom Signal,
  including configuration validation and default implementations.

  ## Options

  #{NimbleOptions.docs(@signal_config_schema)}

  ## Examples

      defmodule MySignal do
        use Jido.Signal,
          type: "my.custom.signal",
          default_source: "/my/service",
          schema: [
            user_id: [type: :string, required: true],
            message: [type: :string, required: true]
          ]
      end

  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@signal_config_schema)

    quote location: :keep do
      alias Jido.Signal
      alias Jido.Signal.ID

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          def type, do: @validated_opts[:type]
          def default_source, do: @validated_opts[:default_source]
          def datacontenttype, do: @validated_opts[:datacontenttype]
          def dataschema, do: @validated_opts[:dataschema]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              type: @validated_opts[:type],
              default_source: @validated_opts[:default_source],
              datacontenttype: @validated_opts[:datacontenttype],
              dataschema: @validated_opts[:dataschema],
              schema: @validated_opts[:schema]
            }
          end

          def __signal_metadata__ do
            to_json()
          end

          @doc """
          Creates a new Signal instance with the configured type and validated data.

          ## Parameters

          - `data`: A map containing the Signal's data payload.
          - `opts`: Additional Signal options (source, subject, etc.)

          ## Returns

          `{:ok, Signal.t()}` if the data is valid, `{:error, String.t()}` otherwise.

          ## Examples

              iex> MySignal.new(%{user_id: "123", message: "Hello"})
              {:ok, %Jido.Signal{type: "my.custom.signal", data: %{user_id: "123", message: "Hello"}, ...}}

          """
          @spec new(map(), keyword()) :: {:ok, Signal.t()} | {:error, String.t()}
          def new(data \\ %{}, opts \\ []) do
            with {:ok, validated_data} <- validate_data(data),
                 {:ok, signal_attrs} <- build_signal_attrs(validated_data, opts) do
              Signal.from_map(signal_attrs)
            else
              {:error, reason} -> {:error, reason}
            end
          end

          @doc """
          Creates a new Signal instance, raising an error if invalid.

          ## Parameters

          - `data`: A map containing the Signal's data payload.
          - `opts`: Additional Signal options (source, subject, etc.)

          ## Returns

          `Signal.t()` if the data is valid.

          ## Raises

          `RuntimeError` if the data is invalid.

          ## Examples

              iex> MySignal.new!(%{user_id: "123", message: "Hello"})
              %Jido.Signal{type: "my.custom.signal", data: %{user_id: "123", message: "Hello"}, ...}

          """
          @spec new!(map(), keyword()) :: Signal.t() | no_return()
          def new!(data \\ %{}, opts \\ []) do
            case new(data, opts) do
              {:ok, signal} -> signal
              {:error, reason} -> raise reason
            end
          end

          @doc """
          Validates the data for the Signal according to its schema.

          ## Examples

              iex> MySignal.validate_data(%{user_id: "123", message: "Hello"})
              {:ok, %{user_id: "123", message: "Hello"}}

              iex> MySignal.validate_data(%{})
              {:error, "Invalid data for Signal: Required key :user_id not found"}

          """
          @spec validate_data(map()) :: {:ok, map()} | {:error, String.t()}
          def validate_data(data) do
            case @validated_opts[:schema] do
              [] ->
                {:ok, data}

              schema when is_list(schema) ->
                case NimbleOptions.validate(Enum.to_list(data), schema) do
                  {:ok, validated_data} ->
                    {:ok, Map.new(validated_data)}

                  {:error, %NimbleOptions.ValidationError{} = error} ->
                    reason = Jido.Signal.Error.format_nimble_validation_error(error, "Signal", __MODULE__)
                    {:error, reason}
                end
            end
          end

          defp build_signal_attrs(validated_data, opts) do
            caller =
              Process.info(self(), :current_stacktrace)
              |> elem(1)
              |> Enum.find(fn {mod, _fun, _arity, _info} ->
                mod_str = to_string(mod)
                mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
              end)
              |> elem(0)
              |> to_string()

            attrs = %{
              "type" => @validated_opts[:type],
              "source" => @validated_opts[:default_source] || caller,
              "data" => validated_data,
              "id" => ID.generate!(),
              "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "specversion" => "1.0.2"
            }

            attrs =
              if @validated_opts[:datacontenttype],
                do: Map.put(attrs, "datacontenttype", @validated_opts[:datacontenttype]),
                else: attrs

            attrs =
              if @validated_opts[:dataschema],
                do: Map.put(attrs, "dataschema", @validated_opts[:dataschema]),
                else: attrs

            # Override with any user-provided options
            final_attrs =
              Enum.reduce(opts, attrs, fn {key, value}, acc ->
                Map.put(acc, to_string(key), value)
              end)

            {:ok, final_attrs}
          end

        {:error, error} ->
          message = Jido.Signal.Error.format_nimble_config_error(error, "Signal", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  @doc """
  Creates a new Signal struct, raising an error if invalid.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `RuntimeError` if the attributes are invalid.

  ## Examples

      iex> Jido.Signal.new!(%{type: "example.event", source: "/example"})
      %Jido.Signal{type: "example.event", source: "/example", ...}

      iex> Jido.Signal.new!(type: "example.event", source: "/example")
      %Jido.Signal{type: "example.event", source: "/example", ...}

  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

      iex> Jido.Signal.new(type: "example.event", source: "/example")
      {:ok, %Jido.Signal{type: "example.event", source: "/example", ...}}

  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    caller =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _fun, _arity, _info} ->
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end)
      |> elem(0)
      |> to_string()

    defaults = %{
      "specversion" => "1.0.2",
      "id" => ID.generate!(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => caller
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with :ok <- parse_specversion(map),
         {:ok, type} <- parse_type(map),
         {:ok, source} <- parse_source(map),
         {:ok, id} <- parse_id(map),
         {:ok, subject} <- parse_subject(map),
         {:ok, time} <- parse_time(map),
         {:ok, datacontenttype} <- parse_datacontenttype(map),
         {:ok, dataschema} <- parse_dataschema(map),
         {:ok, data} <- parse_data(map["data"]),
         {:ok, jido_dispatch} <- parse_jido_dispatch(map["jido_dispatch"]) do
      event = %__MODULE__{
        specversion: "1.0.2",
        type: type,
        source: source,
        id: id,
        subject: subject,
        time: time,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        data: data,
        jido_dispatch: jido_dispatch
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  @doc """
  Converts a struct or list of structs to Signal data format.

  This function is useful for converting domain objects to Signal format
  while preserving their type information through the TypeProvider.

  ## Parameters

  - `signals`: A struct or list of structs to convert
  - `fields`: Additional fields to include (currently unused)

  ## Returns

  Signal struct or list of Signal structs with the original data as payload

  ## Examples

      # Converting a single struct
      iex> user = %User{id: 1, name: "John"}
      iex> signal = Jido.Signal.map_to_signal_data(user)
      iex> signal.data
      %User{id: 1, name: "John"}

      # Converting multiple structs
      iex> users = [%User{id: 1}, %User{id: 2}]
      iex> signals = Jido.Signal.map_to_signal_data(users)
      iex> length(signals)
      2
  """
  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(struct), Keyword.t()) :: list(t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  alias Jido.Signal.Serialization.TypeProvider

  @spec map_to_signal_data(struct, Keyword.t()) :: t()
  def map_to_signal_data(signal, _fields) do
    %__MODULE__{
      id: ID.generate(),
      source: "http://example.com/bank",
      type: TypeProvider.to_string(signal),
      data: signal
    }
  end

  # Parser functions for standard CloudEvents fields

  @spec parse_specversion(map()) :: :ok | {:error, String.t()}
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  @spec parse_type(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  @spec parse_source(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  @spec parse_id(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(%{"id" => ""}), do: {:error, "id given but empty"}
  defp parse_id(_), do: {:ok, ID.generate!()}

  @spec parse_subject(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  @spec parse_time(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  @spec parse_datacontenttype(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  @spec parse_dataschema(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  @spec parse_data(term()) :: {:ok, term()} | {:error, String.t()}
  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  @spec parse_jido_dispatch(term()) :: {:ok, term() | nil} | {:error, String.t()}
  defp parse_jido_dispatch(nil), do: {:ok, nil}

  defp parse_jido_dispatch({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    {:ok, config}
  end

  defp parse_jido_dispatch(config) when is_list(config) do
    {:ok, config}
  end

  defp parse_jido_dispatch(_), do: {:error, "invalid dispatch config"}

  @doc """
  Serializes a Signal or a list of Signals using the specified or default serializer.

  ## Parameters

  - `signal_or_list`: A Signal struct or list of Signal structs
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)

  ## Returns

  `{:ok, binary}` on success, `{:error, reason}` on failure

  ## Examples

      iex> signal = %Jido.Signal{type: "example.event", source: "/example"}
      iex> {:ok, binary} = Jido.Signal.serialize(signal)
      iex> is_binary(binary)
      true

      # Using a specific serializer
      iex> {:ok, binary} = Jido.Signal.serialize(signal, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> is_binary(binary)
      true

      # Serializing multiple Signals
      iex> signals = [
      ...>   %Jido.Signal{type: "event1", source: "/ex1"},
      ...>   %Jido.Signal{type: "event2", source: "/ex2"}
      ...> ]
      iex> {:ok, binary} = Jido.Signal.serialize(signals)
      iex> is_binary(binary)
      true
  """
  @spec serialize(t() | list(t()), keyword()) :: {:ok, binary()} | {:error, term()}
  def serialize(signal_or_list, opts \\ [])

  def serialize(%__MODULE__{} = signal, opts) do
    Jido.Signal.Serialization.Serializer.serialize(signal, opts)
  end

  def serialize(signals, opts) when is_list(signals) do
    Jido.Signal.Serialization.Serializer.serialize(signals, opts)
  end

  @doc """
  Legacy serialize function that returns binary directly (for backward compatibility).
  """
  @spec serialize!(t() | list(t()), keyword()) :: binary()
  def serialize!(signal_or_list, opts \\ []) do
    case serialize(signal_or_list, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Serialization failed: #{reason}"
    end
  end

  @doc """
  Deserializes binary data back into a Signal struct or list of Signal structs.

  ## Parameters

  - `binary`: The serialized binary data to deserialize
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)
    - `:type` - Specific type to deserialize to
    - `:type_provider` - Custom type provider

  ## Returns

  `{:ok, Signal.t() | list(Signal.t())}` if successful, `{:error, reason}` otherwise

  ## Examples

      # JSON deserialization (default)
      iex> json = ~s({"type":"example.event","source":"/example","id":"123"})
      iex> {:ok, signal} = Jido.Signal.deserialize(json)
      iex> signal.type
      "example.event"

      # Using a specific serializer
      iex> {:ok, signal} = Jido.Signal.deserialize(binary, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> signal.type
      "example.event"

      # Deserializing multiple Signals
      iex> json = ~s([{"type":"event1","source":"/ex1"},{"type":"event2","source":"/ex2"}])
      iex> {:ok, signals} = Jido.Signal.deserialize(json)
      iex> length(signals)
      2
  """
  @spec deserialize(binary(), keyword()) :: {:ok, t() | list(t())} | {:error, term()}
  def deserialize(binary, opts \\ []) when is_binary(binary) do
    case Jido.Signal.Serialization.Serializer.deserialize(binary, opts) do
      {:ok, data} ->
        result =
          if is_list(data) do
            # Handle array of Signals
            Enum.map(data, fn signal_data ->
              case convert_to_signal(signal_data) do
                {:ok, signal} -> signal
                {:error, reason} -> raise "Failed to parse signal: #{reason}"
              end
            end)
          else
            # Handle single Signal
            case convert_to_signal(data) do
              {:ok, signal} -> signal
              {:error, reason} -> raise "Failed to parse signal: #{reason}"
            end
          end

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Convert deserialized data to Signal struct
  defp convert_to_signal(%__MODULE__{} = signal), do: {:ok, signal}

  defp convert_to_signal(data) when is_map(data) do
    from_map(data)
  end

  defp convert_to_signal(data) do
    {:error, "Cannot convert #{inspect(data)} to Signal"}
  end
end
