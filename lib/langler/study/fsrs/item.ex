defmodule Langler.Study.FSRS.Item do
  @moduledoc """
  Normalized representation of a study item's FSRS state.
  """

  @type state :: :learning | :review | :relearning

  @enforce_keys [:user_id, :word_id]
  defstruct [
    :user_id,
    :word_id,
    :stability,
    :difficulty,
    :retrievability,
    :elapsed_days,
    :last_quality,
    :interval,
    :state,
    :step,
    :due,
    :last_reviewed_at
  ]

  @type t :: %__MODULE__{
          user_id: any(),
          word_id: any(),
          stability: float() | nil,
          difficulty: float() | nil,
          retrievability: float() | nil,
          elapsed_days: non_neg_integer() | nil,
          last_quality: non_neg_integer() | nil,
          interval: non_neg_integer() | nil,
          state: state() | nil,
          step: integer() | nil,
          due: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil
        }

  @doc """
  Builds an FSRS item struct from any record that uses atom keys.
  """
  @spec from_record(map()) :: t()
  def from_record(record) when is_map(record) do
    %__MODULE__{
      user_id: Map.fetch!(record, :user_id),
      word_id: Map.fetch!(record, :word_id),
      stability: Map.get(record, :stability),
      difficulty: Map.get(record, :difficulty),
      retrievability: Map.get(record, :retrievability),
      elapsed_days: Map.get(record, :elapsed_days),
      last_quality: Map.get(record, :last_quality),
      interval: Map.get(record, :interval),
      state: Map.get(record, :state, :learning),
      step: Map.get(record, :step),
      due: Map.get(record, :due_date) || Map.get(record, :due),
      last_reviewed_at: Map.get(record, :last_reviewed_at)
    }
  end

  @doc """
  Returns the elapsed days for a given reference datetime, caching it on the struct.
  """
  @spec elapsed_days(t(), DateTime.t()) :: {t(), non_neg_integer()}
  def elapsed_days(%__MODULE__{} = item, reference_datetime \\ DateTime.utc_now()) do
    case item.last_reviewed_at do
      nil ->
        {item, 0}

      last_reviewed_at ->
        elapsed = max(0, DateTime.diff(reference_datetime, last_reviewed_at, :day))
        {maybe_put(item, :elapsed_days, elapsed), elapsed}
    end
  end

  @doc """
  Calculates retrievability and updates the struct cache.
  """
  @spec retrievability(t(), DateTime.t()) :: {t(), float()}
  def retrievability(%__MODULE__{} = item, reference_datetime \\ DateTime.utc_now()) do
    {item, elapsed_days} = elapsed_days(item, reference_datetime)

    retrievability =
      case {item.stability, elapsed_days} do
        {nil, _} -> 0.0
        {_, 0} -> 0.99
        {stability, elapsed} -> calc_retrievability(stability, elapsed)
      end

    {maybe_put(item, :retrievability, retrievability), retrievability}
  end

  defp calc_retrievability(stability, elapsed_days) do
    decay = -0.5
    factor = :math.pow(0.9, 1 / decay) - 1
    (1 + factor * elapsed_days / stability) ** decay
  end

  defp maybe_put(%__MODULE__{} = item, key, value) do
    case Map.get(item, key) do
      ^value -> item
      _ -> Map.put(item, key, value)
    end
  end
end
