defmodule Langler.Study.FSRS do
  @moduledoc """
  Thin façade around the FSRS algorithm that loads configuration and normalizes items.
  """

  alias Langler.Study.FSRS.{Item, Params}

  @type rating :: :again | :hard | :good | :easy

  @quality_from_rating %{again: 0, hard: 2, good: 3, easy: 4}
  @rating_from_quality %{0 => :again, 1 => :hard, 2 => :hard, 3 => :good, 4 => :easy}

  @spec params(Keyword.t() | map()) :: Params.t()
  def params(overrides \\ []), do: Params.load(overrides)

  @spec item(map(), Keyword.t()) :: Item.t()
  def item(record, overrides \\ []) when is_map(record) do
    record
    |> Item.from_record()
    |> apply_overrides(overrides)
  end

  @doc """
  Converts a user-facing rating into the FSRS quality score.
  """
  @spec quality_from_rating(rating()) :: 0..4
  def quality_from_rating(rating), do: Map.fetch!(@quality_from_rating, rating)

  @doc """
  Maps a FSRS quality score (0-4) to the nearest discrete rating.
  """
  @spec rating_from_quality(0..4) :: rating()
  def rating_from_quality(score), do: Map.fetch!(@rating_from_quality, score)

  @doc """
  Returns `{item, elapsed_days}` ensuring the cached value stays fresh.
  """
  @spec elapsed_days(Item.t(), DateTime.t()) :: {Item.t(), non_neg_integer()}
  def elapsed_days(%Item{} = item, reference_datetime \\ DateTime.utc_now()) do
    Item.elapsed_days(item, reference_datetime)
  end

  @doc """
  Returns `{item, retrievability}` using the default forgetting curve.
  """
  @spec retrievability(Item.t(), DateTime.t()) :: {Item.t(), float()}
  def retrievability(%Item{} = item, reference_datetime \\ DateTime.utc_now()) do
    Item.retrievability(item, reference_datetime)
  end

  defp apply_overrides(%Item{} = item, overrides) do
    Enum.reduce(overrides, item, fn {key, value}, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, value), else: acc
    end)
  end
end
