defmodule JidoBugDemo.TestAgent do
  use Jido.Agent,
    name: "test_agent",
    description: "Minimal agent to reproduce dialyzer issue",
    schema: [
      value: [type: :integer, default: 0]
    ]

  @spec mount(t(), keyword()) :: {:ok, map()} | {:error, any()}
  def mount(_agent, _opts), do: {:ok, %{}}

  @spec shutdown(t(), any()) :: {:ok, map()} | {:error, any()}
  def shutdown(_agent, _reason), do: {:ok, %{}}

  # Override generated typespecs to match dialyzer's success typing
  @spec do_validate(t(), map(), keyword()) :: {:ok, map()} | {:error, Jido.Error.t()}
  @spec pending?(t()) :: non_neg_integer()
  @spec reset(t()) :: {:ok, t()} | {:error, Jido.Error.t()}
end
