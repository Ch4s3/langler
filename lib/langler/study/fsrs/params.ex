defmodule Langler.Study.FSRS.Params do
  @moduledoc """
  Loads FSRS scheduler parameters from config so they can be tweaked without recompiling.
  """

  @enforce_keys [
    :weights,
    :desired_retention,
    :learning_steps,
    :relearning_steps,
    :maximum_interval,
    :enable_fuzzing
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          weights: [float()],
          desired_retention: float(),
          learning_steps: [float()],
          relearning_steps: [float()],
          maximum_interval: pos_integer(),
          enable_fuzzing: boolean()
        }

  @defaults %{
    weights: [],
    desired_retention: 0.9,
    learning_steps: [1.0, 10.0],
    relearning_steps: [10.0],
    maximum_interval: 36_500,
    enable_fuzzing: true
  }

  @doc """
  Returns the configured FSRS parameters as a struct.
  """
  @spec load(Keyword.t() | map()) :: t()
  def load(overrides \\ []) do
    config = Application.get_env(:langler, __MODULE__, %{})

    merged =
      @defaults
      |> Map.merge(normalize(config))
      |> Map.merge(normalize(overrides))

    struct!(__MODULE__, merged)
  end

  defp normalize(%{} = map), do: map
  defp normalize(keyword) when is_list(keyword), do: Map.new(keyword)
end
