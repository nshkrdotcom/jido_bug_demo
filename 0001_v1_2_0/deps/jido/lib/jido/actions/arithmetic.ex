defmodule Jido.Actions.Arithmetic do
  @moduledoc """
  Provides basic arithmetic operations as actions. The operations defined here are obviously trivial.
  This module is intended to be used as a reference for how to write your own actions.

  This module defines a set of arithmetic actions that can be used in actions:
  - Add: Adds two numbers together
  - Subtract: Subtracts one number from another
  - Multiply: Multiplies two numbers
  - Divide: Divides one number by another, handling division by zero
  - Square: Squares a number

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule Add do
    @moduledoc false
    use Action,
      name: "add",
      description: "Adds two numbers",
      schema: [
        value: [type: :integer, required: true, doc: "The first number to add"],
        amount: [type: :integer, required: true, doc: "The second number to add"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value + amount}}
    end
  end

  defmodule Subtract do
    @moduledoc false
    use Action,
      name: "subtract",
      description: "Subtracts one number from another",
      schema: [
        value: [type: :integer, required: true, doc: "The number to subtract from"],
        amount: [type: :integer, required: true, doc: "The number to subtract"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value - amount}}
    end
  end

  defmodule Multiply do
    @moduledoc false
    use Action,
      name: "multiply",
      description: "Multiplies two numbers",
      schema: [
        value: [type: :integer, required: true, doc: "The first number to multiply"],
        amount: [type: :integer, required: true, doc: "The second number to multiply"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value * amount}}
    end
  end

  defmodule Divide do
    @moduledoc false
    use Action,
      name: "divide",
      description: "Divides one number by another",
      schema: [
        value: [type: :integer, required: true, doc: "The number to be divided (dividend)"],
        amount: [type: :integer, required: true, doc: "The number to divide by (divisor)"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{value: _value, amount: 0}, _context) do
      {:error, "Cannot divide by zero"}
    end

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value / amount}}
    end
  end

  defmodule Square do
    @moduledoc false
    use Action,
      name: "square",
      description: "Squares a number",
      schema: [
        value: [type: :float, required: true, doc: "The number to be squared"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value}, _context) do
      {:ok, %{result: value * value}}
    end
  end
end
