defmodule Jido.Signal.Error do
  @moduledoc """
  Defines error structures and helper functions for Jido

  This module provides a standardized way to create and handle errors within the Jido system.
  It offers a set of predefined error types and functions to create, manipulate, and convert
  error structures consistently across the application.

  > Why not use Exceptions?
  >
  > Jido is designed to be a functional system, strictly adhering to the use of result tuples.
  > This approach provides several benefits:
  >
  > 1. Consistent error handling: By using `{:ok, result}` or `{:error, reason}` tuples,
  >    we ensure a uniform way of handling success and failure cases throughout the system.
  >
  > 2. Composability: Monadic actions can be easily chained together, allowing for
  >    cleaner and more maintainable code.
  >
  > 3. Explicit error paths: The use of result tuples makes error cases explicit,
  >    reducing the likelihood of unhandled errors.
  >
  > 4. No silent failures: Unlike exceptions, which can be silently caught and ignored,
  >    result tuples require explicit handling of both success and error cases.
  >
  > 5. Better testability: Monadic actions are easier to test, as both success and
  >    error paths can be explicitly verified.
  >
  > By using this approach instead of exceptions, we gain more control over the flow of our
  > actions and ensure that errors are handled consistently across the entire system.

  ## Usage

  Use this module to create specific error types when exceptions occur in your Jido actions.
  This allows for consistent error handling and reporting throughout the system.

  Example:

      defmodule MyExec do
        alias Jido.Signal.Error

        def run(params) do
          case validate(params) do
            :ok -> perform_action(params)
            {:error, reason} -> Error.validation_error("Invalid parameters")
          end
        end
      end
  """

  @typedoc """
  Defines the possible error types in the Jido system.

  - `:validation_error`: Used when input validation fails.
  - `:execution_error`: Used when an error occurs during action execution.
  - `:timeout`: Used when an action exceeds its time limit.
  - `:planning_error`: Used when an error occurs during action planning.
  - `:routing_error`: Used when an error occurs during action routing.
  - `:dispatch_error`: Used when an error occurs during signal dispatching.
  """
  @type error_type ::
          :validation_error
          | :execution_error
          | :planning_error
          | :timeout
          | :routing_error
          | :dispatch_error

  use TypedStruct

  @typedoc """
  Represents a structured error in the Jido system.

  Fields:
  - `type`: The category of the error (see `t:error_type/0`).
  - `message`: A human-readable description of the error.
  - `details`: Optional map containing additional error context.
  - `stacktrace`: Optional list representing the error's stacktrace.
  """
  typedstruct do
    field(:type, error_type(), enforce: true)
    field(:message, String.t(), enforce: true)
    field(:details, map(), default: %{})
    field(:stacktrace, list(), default: [])
  end

  @doc """
  Creates a new error struct with the given type and message.

  This is a low-level function used by other error creation functions in this module.
  Consider using the specific error creation functions unless you need fine-grained control.

  ## Parameters
  - `type`: The error type (see `t:error_type/0`).
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Examples

      iex> Jido.Signal.Error.new(:config_error, "Invalid configuration")
      %Jido.Signal.Error{
        type: :config_error,
        message: "Invalid configuration",
        details: nil,
        stacktrace: [...]
      }

      iex> Jido.Signal.Error.new(:execution_error, "Exec failed", %{step: "data_processing"})
      %Jido.Signal.Error{
        type: :execution_error,
        message: "Exec failed",
        details: %{step: "data_processing"},
        stacktrace: [...]
      }
  """
  @spec new(error_type(), String.t(), map() | nil, list() | nil) :: t()
  def new(type, message, details \\ nil, stacktrace \\ nil) do
    %__MODULE__{
      type: type,
      message: message,
      details: details,
      stacktrace: stacktrace || capture_stacktrace()
    }
  end

  @doc """
  Creates a new bad request error.

  Use this when the client sends an invalid or malformed request.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.bad_request("Missing required parameter 'user_id'")
      %Jido.Signal.Error{
        type: :bad_request,
        message: "Missing required parameter 'user_id'",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec bad_request(String.t(), map() | nil, list() | nil) :: t()
  def bad_request(message, details \\ nil, stacktrace \\ nil) do
    new(:bad_request, message, details, stacktrace)
  end

  @doc """
  Creates a new validation error.

  Use this when input validation fails for an action.

  ## Parameters
  - `message`: A string describing the validation error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.validation_error("Invalid email format", %{field: "email", value: "not-an-email"})
      %Jido.Signal.Error{
        type: :validation_error,
        message: "Invalid email format",
        details: %{field: "email", value: "not-an-email"},
        stacktrace: [...]
      }
  """
  @spec validation_error(String.t(), map() | nil, list() | nil) :: t()
  def validation_error(message, details \\ nil, stacktrace \\ nil) do
    new(:validation_error, message, details, stacktrace)
  end

  @doc """
  Creates a new execution error.

  Use this when an error occurs during the execution of an action.

  ## Parameters
  - `message`: A string describing the execution error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.execution_error("Failed to process data", %{step: "data_transformation"})
      %Jido.Signal.Error{
        type: :execution_error,
        message: "Failed to process data",
        details: %{step: "data_transformation"},
        stacktrace: [...]
      }
  """
  @spec execution_error(String.t(), map() | nil, list() | nil) :: t()
  def execution_error(message, details \\ nil, stacktrace \\ nil) do
    new(:execution_error, message, details, stacktrace)
  end

  @doc """
  Creates a new timeout error.

  Use this when an action exceeds its allocated time limit.

  ## Parameters
  - `message`: A string describing the timeout error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.timeout("Exec timed out after 30 seconds", %{action: "FetchUserData"})
      %Jido.Signal.Error{
        type: :timeout,
        message: "Exec timed out after 30 seconds",
        details: %{action: "FetchUserData"},
        stacktrace: [...]
      }
  """
  @spec timeout(String.t(), map() | nil, list() | nil) :: t()
  def timeout(message, details \\ nil, stacktrace \\ nil) do
    new(:timeout, message, details, stacktrace)
  end

  @doc """
  Creates a new routing error.

  Use this when an error occurs during action routing.

  ## Parameters
  - `message`: A string describing the routing error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.routing_error("Invalid route configuration", %{route: "user_action"})
      %Jido.Signal.Error{
        type: :routing_error,
        message: "Invalid route configuration",
        details: %{route: "user_action"},
        stacktrace: [...]
      }
  """
  @spec routing_error(String.t(), map() | nil, list() | nil) :: t()
  def routing_error(message, details \\ nil, stacktrace \\ nil) do
    new(:routing_error, message, details, stacktrace)
  end

  @doc """
  Creates a new dispatch error.

  Use this when an error occurs during signal dispatching.

  ## Parameters
  - `message`: A string describing the dispatch error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Signal.Error.dispatch_error("Failed to deliver signal", %{adapter: :http, reason: :timeout})
      %Jido.Signal.Error{
        type: :dispatch_error,
        message: "Failed to deliver signal",
        details: %{adapter: :http, reason: :timeout},
        stacktrace: [...]
      }
  """
  @spec dispatch_error(String.t(), map() | nil, list() | nil) :: t()
  def dispatch_error(message, details \\ nil, stacktrace \\ nil) do
    new(:dispatch_error, message, details, stacktrace)
  end

  @doc """
  Converts the error struct to a plain map.

  This function transforms the error struct into a plain map,
  including the error type and stacktrace if available. It's useful
  for serialization or when working with APIs that expect plain maps.

  ## Parameters
  - `error`: An error struct of type `t:t/0`.

  ## Returns
  A map representation of the error.

  ## Example

      iex> error = Jido.Signal.Error.validation_error("Invalid input")
      iex> Jido.Signal.Error.to_map(error)
      %{
        type: :validation_error,
        message: "Invalid input",
        stacktrace: [...]
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    error
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Captures the current stacktrace.

  This function is useful when you want to capture the stacktrace at a specific point
  in your code, rather than at the point where the error is created. It drops the first
  two entries from the stacktrace to remove internal function calls related to this module.

  ## Returns
  The current stacktrace as a list.

  ## Example

      iex> stacktrace = Jido.Signal.Error.capture_stacktrace()
      iex> is_list(stacktrace)
      true
  """
  @spec capture_stacktrace() :: list()
  def capture_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    Enum.drop(stacktrace, 2)
  end

  @doc """
  Formats a NimbleOptions validation error for configuration validation.
  Used when validating configuration options at compile or runtime.

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is required"}
      iex> Jido.Signal.Error.format_nimble_config_error(error, "Action")
      "Invalid configuration given to use Jido.Action for key [:name]: is required"
  """
  @spec format_nimble_config_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}): #{message}"
  end

  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}) for key #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_config_error(error, _module_type, _module) when is_binary(error), do: error
  def format_nimble_config_error(error, _module_type, _module), do: inspect(error)

  @doc """
  Formats a NimbleOptions validation error for parameter validation.
  Used when validating runtime parameters.

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      iex> Jido.Signal.Error.format_nimble_validation_error(error, "Action")
      "Invalid parameters for Action at [:input]: is required"
  """
  @spec format_nimble_validation_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}): #{message}"
  end

  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}) at #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_validation_error(error, _module_type, _module) when is_binary(error),
    do: error

  def format_nimble_validation_error(error, _module_type, _module), do: inspect(error)
end

defimpl String.Chars, for: Jido.Signal.Error do
  @doc """
  Implements String.Chars protocol for Jido.Signal.Error.
  Returns a human-readable string representation focusing on type and message.
  """
  def to_string(%Jido.Signal.Error{type: type, message: message, details: details}) do
    base = "[#{type}] #{message}"

    if details do
      "#{base} (#{format_details(details)})"
    else
      base
    end
  end

  # Format map details with sorted keys for consistent output
  defp format_details(details) when is_map(details) do
    details
    |> Enum.reject(fn {_k, v} -> match?(%Jido.Signal.Error{}, v) end)
    |> Enum.sort_by(fn {k, _v} -> Kernel.to_string(k) end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{format_value(v)}" end)
  end

  # Handle nested map values
  defp format_value(%{} = map) do
    map_str =
      map
      |> Enum.sort_by(fn {k, _v} -> Kernel.to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)

    "%{#{map_str}}"
  end

  defp format_value(value), do: inspect(value)
end

defimpl Inspect, for: Jido.Signal.Error do
  import Inspect.Algebra

  @doc """
  Implements Inspect protocol for Jido.Signal.Error.
  Provides a detailed multi-line representation for debugging.
  """
  def inspect(error, opts) do
    # Start with basic error structure
    parts = [
      "#Jido.Signal.Error<",
      concat([
        line(),
        "  type: ",
        to_doc(error.type, opts)
      ]),
      concat([
        line(),
        "  message: ",
        to_doc(error.message, opts)
      ])
    ]

    # Add details if present
    parts =
      if error.details do
        formatted_details = format_error_details(error.details, opts)

        parts ++
          [
            concat([
              line(),
              "  details: ",
              formatted_details
            ])
          ]
      else
        parts
      end

    # Add stacktrace if present and enabled in opts
    parts =
      if error.stacktrace && opts.limit != :infinity do
        formatted_stacktrace =
          error.stacktrace
          |> Enum.take(5)
          |> Enum.map_join("\n    ", &Exception.format_stacktrace_entry/1)

        parts ++
          [
            concat([
              line(),
              "  stacktrace:",
              line(),
              "    ",
              formatted_stacktrace
            ])
          ]
      else
        parts
      end

    concat([
      concat(Enum.intersperse(parts, "")),
      line(),
      ">"
    ])
  end

  # Format details with special handling for original exceptions
  defp format_error_details(%{original_exception: exception} = details, opts)
       when not is_nil(exception) do
    # Format the exception and its stacktrace
    exception_class = exception.__struct__
    exception_message = Exception.message(exception)

    # Create a formatted version of the exception details
    exception_details = "#{exception_class}: #{exception_message}"

    # Remove the original_exception from the details map and add the formatted details
    details_without_exception =
      details
      |> Map.delete(:original_exception)
      |> Map.put(:exception_details, exception_details)

    # Format the remaining details
    to_doc(details_without_exception, opts)
    |> nest(2)
  end

  # Handle nested error in details specially (retained from original inspect_details)
  defp format_error_details(%{original_error: %Jido.Signal.Error{}} = details, opts) do
    to_doc(Map.delete(details, :original_error), opts)
    |> nest(2)
  end

  defp format_error_details(details, opts) do
    to_doc(details, opts)
    |> nest(2)
  end
end
