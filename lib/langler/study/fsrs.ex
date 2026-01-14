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

  @doc """
  Calculates the next review state for a given item and rating.
  """
  @spec calculate_next_review(Item.t(), rating(), Keyword.t()) :: map()
  def calculate_next_review(%Item{} = item, rating, opts \\ []) do
    params = params()
    now = Keyword.get(opts, :now, DateTime.utc_now())
    {item, _elapsed} = elapsed_days(item, now)
    {_item, retrievability} = retrievability(item, now)

    base_result =
      cond do
        item.stability ->
          plan_review(item, rating, params, now, retrievability)

        item.state in [:learning, :relearning] or item.step ->
          plan_learning(item, rating, params, now)

        true ->
          plan_learning(item, rating, params, now)
      end

    Map.merge(base_result, %{
      rating: rating,
      retrievability: retrievability || params.desired_retention
    })
  end

  @doc """
  Updates an ease factor based on the provided rating.
  """
  @spec update_ease_factor(float(), rating()) :: float()
  def update_ease_factor(current, rating) when is_number(current) do
    delta =
      case rating do
        :again -> -0.35
        :hard -> -0.15
        :good -> 0.0
        :easy -> 0.15
      end

    current
    |> Kernel.+(delta)
    |> clamp(1.3, 3.7)
  end

  @doc """
  Calculates the next interval (in days) given the last interval, ease factor, and rating.
  """
  @spec calculate_interval(non_neg_integer(), float(), rating()) :: pos_integer()
  def calculate_interval(0, _ease, :again), do: 1

  def calculate_interval(interval, ease_factor, rating) do
    base =
      cond do
        interval <= 0 -> 1
        interval == 1 -> 6
        true -> round(interval * ease_factor)
      end

    adjusted =
      case rating do
        :again -> 1
        :hard -> max(1, round(base * 0.8))
        :easy -> round(base * 1.3)
        _ -> base
      end

    max(1, adjusted)
  end

  defp apply_overrides(%Item{} = item, overrides) do
    Enum.reduce(overrides, item, fn {key, value}, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, value), else: acc
    end)
  end

  defp plan_learning(%Item{} = item, rating, params, now) do
    steps = params.learning_steps || []
    total_steps = max(length(steps), 1)
    current_step = item.step || 0

    cond do
      rating == :again ->
        due = minutes_from_now(now, Enum.at(steps, 0, 1.0))
        base_learning_response(item, 0, due)

      current_step < total_steps - 1 and rating in [:hard, :good] ->
        next_step = current_step + 1
        due = minutes_from_now(now, Enum.at(steps, next_step, 10.0))
        base_learning_response(item, next_step, due)

      true ->
        start_review(rating, params, now)
    end
  end

  defp plan_review(%Item{} = item, rating, params, now, retrievability) do
    difficulty = next_difficulty(item.difficulty, rating, params)
    ease = update_ease_factor(item.ease_factor || ease_from_difficulty(difficulty), rating)

    retention =
      if retrievability in [nil, 0.0], do: params.desired_retention, else: retrievability

    case rating do
      :again ->
        relearn(difficulty, params, now, ease)

      _ ->
        stability =
          grow_stability(
            item.stability || initial_stability(:good, params),
            difficulty,
            rating,
            retention,
            params
          )

        interval = interval_from_stability(stability)
        due = DateTime.add(now, interval * 86_400, :second)

        %{
          state: :review,
          step: nil,
          difficulty: difficulty,
          stability: stability,
          interval: interval,
          due: due,
          ease_factor: ease
        }
    end
  end

  defp relearn(difficulty, params, now, ease) do
    steps = params.relearning_steps || [10.0]
    due = minutes_from_now(now, Enum.at(steps, 0, 10.0))

    %{
      state: :relearning,
      step: 0,
      difficulty: difficulty,
      stability: setback_stability(difficulty, params),
      interval: 0,
      due: due,
      ease_factor: ease
    }
  end

  defp start_review(rating, params, now) do
    difficulty = initial_difficulty(rating, params)
    stability = initial_stability(rating, params)
    interval = interval_from_stability(stability)
    due = DateTime.add(now, interval * 86_400, :second)

    %{
      state: :review,
      step: nil,
      difficulty: difficulty,
      stability: stability,
      interval: interval,
      due: due,
      ease_factor: ease_from_difficulty(difficulty)
    }
  end

  defp base_learning_response(item, step, due) do
    %{
      state: :learning,
      step: step,
      difficulty: item.difficulty,
      stability: item.stability,
      interval: 0,
      due: due,
      ease_factor: item.ease_factor || 2.5
    }
  end

  defp next_difficulty(nil, rating, params), do: initial_difficulty(rating, params)

  defp next_difficulty(difficulty, rating, params) do
    delta = weight(params, 4, 0.15) * (quality_delta(rating) / 2)
    clamp(difficulty + delta, 1.0, 10.0)
  end

  defp initial_difficulty(rating, params) do
    base = weight(params, 0, 5.0)
    slope = weight(params, 1, 0.3)
    clamp(base + slope * quality_delta(rating), 1.0, 10.0)
  end

  defp initial_stability(rating, params) do
    base = weight(params, 2, 2.5)
    slope = weight(params, 3, 1.2)
    max(0.5, base + slope * quality_delta(rating))
  end

  defp grow_stability(stability, difficulty, rating, retrievability, params) do
    retrieval = min(max(retrievability, 0.01), 0.99)

    factor =
      1.0 +
        :math.exp(weight(params, 5, 0.5)) *
          (11 - difficulty) *
          :math.pow(retrieval, -weight(params, 6, 0.3)) *
          (:math.exp((1 - retrieval) * weight(params, 7, 0.2)) - 1)

    hard_penalty = if rating == :hard, do: weight(params, 8, 0.85), else: 1.0
    easy_bonus = if rating == :easy, do: 1.0 + weight(params, 9, 0.15), else: 1.0

    max(0.5, stability * factor * hard_penalty * easy_bonus)
  end

  defp setback_stability(difficulty, params) do
    base = weight(params, 10, 0.5)
    power = weight(params, 11, 0.5)
    max(0.3, base * :math.pow(difficulty, -power))
  end

  defp interval_from_stability(stability) do
    stability
    |> Float.round(1)
    |> round()
    |> max(1)
  end

  defp ease_from_difficulty(difficulty) do
    3.7 - (difficulty - 1) * ((3.7 - 1.3) / 9)
  end

  defp minutes_from_now(now, minutes) do
    seconds = trunc(minutes * 60)
    DateTime.add(now, seconds, :second)
  end

  defp quality_delta(rating), do: quality_from_rating(rating) - 2

  defp weight(params, idx, default) do
    params.weights
    |> Enum.at(idx)
    |> case do
      nil -> default
      value -> value
    end
  end

  defp clamp(value, min, max) do
    cond do
      value < min -> min
      value > max -> max
      true -> value
    end
  end
end
