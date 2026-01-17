defmodule Langler.Study do
  @moduledoc """
  Study mode context for managing FSRS items and study sessions.

  Provides functions for creating, updating, and querying study items
  using the FSRS algorithm for spaced repetition learning.
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

  @doc """
  Gets words that are either due for review or marked as not easy (last quality < 4).
  Returns a list of words with their normalized forms.
  """
  def get_practice_words(user_id, reference_datetime \\ DateTime.utc_now()) do
    FSRSItem
    |> where([i], i.user_id == ^user_id)
    |> preload(:word)
    |> Repo.all()
    |> Enum.filter(fn item ->
      not is_nil(item.word) and
        (due_for_practice?(item, reference_datetime) or not_marked_easy?(item))
    end)
    |> Enum.map(fn item -> item.word.normalized_form end)
    |> Enum.uniq()
  end

  defp due_for_practice?(%{due_date: nil}, _), do: true

  defp due_for_practice?(%{due_date: due_date}, reference_datetime) do
    DateTime.compare(due_date, reference_datetime) != :gt
  end

  defp not_marked_easy?(%{quality_history: nil}), do: false
  defp not_marked_easy?(%{quality_history: []}), do: false

  defp not_marked_easy?(%{quality_history: history}) when is_list(history) do
    last_quality = List.last(history)
    not is_nil(last_quality) and last_quality < 4
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

  def remove_item(user_id, word_id) do
    case get_item_by_user_and_word(user_id, word_id) do
      %FSRSItem{} = item -> Repo.delete(item)
      nil -> {:error, :not_found}
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
    scheduler_item = to_scheduler_item(item)
    result = FSRS.calculate_next_review(scheduler_item, rating, now: now)
    quality = FSRS.quality_from_rating(rating)

    attrs = %{
      interval: result.interval,
      ease_factor: result.ease_factor,
      due_date: result.due,
      repetitions: (item.repetitions || 0) + 1,
      last_reviewed_at: now,
      stability: result.stability,
      difficulty: result.difficulty,
      retrievability: result.retrievability,
      state: encode_state(result.state),
      step: result.step
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

  @dialyzer {:nowarn_function, encode_state: 1}
  defp encode_state(nil), do: nil
  defp encode_state(state) when is_atom(state), do: Atom.to_string(state)
  defp encode_state(state) when is_binary(state), do: state

  def normalize_rating(rating) when is_atom(rating), do: rating
  def normalize_rating("again"), do: :again
  def normalize_rating("hard"), do: :hard
  def normalize_rating("good"), do: :good
  def normalize_rating("easy"), do: :easy
  def normalize_rating(_), do: :good

  @doc """
  Gets the user's vocabulary level based on their FSRS study items.
  Returns %{cefr_level: "A1" | "A2" | "B1" | "B2" | "C1" | "C2", numeric_level: float()}
  """
  def get_user_vocabulary_level(user_id) do
    alias Langler.Content.RecommendationScorer
    RecommendationScorer.calculate_user_level(user_id)
  end
end
