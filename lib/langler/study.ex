defmodule Langler.Study do
  @moduledoc """
  Study mode context (FSRS items + helpers).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Study.{FSRS, FSRSItem}

  def list_items_for_user(user_id, opts \\ []) do
    word_ids = Keyword.get(opts, :word_ids)

    FSRSItem
    |> where(user_id: ^user_id)
    |> then(fn query ->
      if word_ids && word_ids != [] do
        where(query, [i], i.word_id in ^word_ids)
      else
        query
      end
    end)
    |> order_by([i], asc: i.due_date)
    |> Repo.all()
    |> Repo.preload(:word)
  end

  def due_items(user_id, reference_datetime \\ DateTime.utc_now()) do
    FSRSItem
    |> where([i], i.user_id == ^user_id)
    |> where([i], not is_nil(i.due_date) and i.due_date <= ^reference_datetime)
    |> order_by([i], asc: i.due_date)
    |> Repo.all()
  end

  def get_item!(id), do: Repo.get!(FSRSItem, id)

  def get_item_by_user_and_word(user_id, word_id) do
    Repo.get_by(FSRSItem, user_id: user_id, word_id: word_id)
  end

  def schedule_new_item(user_id, word_id) do
    case get_item_by_user_and_word(user_id, word_id) do
      %FSRSItem{} = item ->
        {:ok, item}

      nil ->
        create_item(%{
          user_id: user_id,
          word_id: word_id,
          due_date: DateTime.utc_now(),
          state: "learning",
          step: 0,
          repetitions: 0
        })
    end
  end

  def create_item(attrs \\ %{}) do
    %FSRSItem{}
    |> FSRSItem.changeset(attrs)
    |> Repo.insert()
  end

  def review_item(%FSRSItem{} = item, rating, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    rating = normalize_rating(rating)
    quality = FSRS.quality_from_rating(rating)
    interval = next_interval(item.interval || 0, rating)
    ease_factor = adjust_ease_factor(item.ease_factor || 2.5, rating)
    due_date = DateTime.add(now, interval * 86_400, :second)

    attrs = %{
      interval: interval,
      ease_factor: ease_factor,
      due_date: due_date,
      repetitions: (item.repetitions || 0) + 1,
      last_reviewed_at: now
    }

    case append_quality(item, quality, attrs) do
      {:ok, updated} -> {:ok, Repo.preload(updated, :word)}
      error -> error
    end
  end

  def update_item(%FSRSItem{} = item, attrs) do
    item
    |> FSRSItem.changeset(attrs)
    |> Repo.update()
  end

  def change_item(%FSRSItem{} = item, attrs \\ %{}) do
    FSRSItem.changeset(item, attrs)
  end

  def append_quality(%FSRSItem{} = item, quality_score, attrs \\ %{}) do
    history = (item.quality_history || []) ++ [quality_score]
    attrs = attrs |> Enum.into(%{}) |> Map.put(:quality_history, history)

    update_item(item, attrs)
  end

  def to_scheduler_item(%FSRSItem{} = record, overrides \\ []) do
    record
    |> Map.from_struct()
    |> Map.drop([:__meta__, :user, :word])
    |> FSRS.item(overrides)
  end

  defp normalize_rating(rating) when is_atom(rating), do: rating
  defp normalize_rating("again"), do: :again
  defp normalize_rating("hard"), do: :hard
  defp normalize_rating("good"), do: :good
  defp normalize_rating("easy"), do: :easy
  defp normalize_rating(_), do: :good

  defp next_interval(_current, :again), do: 1

  defp next_interval(current, :hard) do
    base = max(current, 1)
    max(1, round(base * 1.2))
  end

  defp next_interval(current, :good) do
    base = max(current, 1)
    max(1, round(base * 2.5))
  end

  defp next_interval(current, :easy) do
    base = max(current, 1)
    max(2, round(base * 3.5))
  end

  defp adjust_ease_factor(ease, :again), do: clamp_ease(ease - 0.3)
  defp adjust_ease_factor(ease, :hard), do: clamp_ease(ease - 0.15)
  defp adjust_ease_factor(ease, :good), do: clamp_ease(ease + 0.05)
  defp adjust_ease_factor(ease, :easy), do: clamp_ease(ease + 0.15)

  defp clamp_ease(value), do: value |> Float.round(2) |> min(3.7) |> max(1.3)
end
