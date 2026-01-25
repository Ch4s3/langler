defmodule Langler.Vocabulary do
  @moduledoc """
  Vocabulary and word occurrence management domain.

  Handles vocabulary words, their frequency ranks, and tracking word occurrences
  in articles for language learning purposes.
  """

  import Ecto.Query, warn: false
  alias Langler.Accounts.GoogleTranslateConfig
  alias Langler.External.Dictionary
  alias Langler.Repo
  alias Langler.Study
  alias Langler.Vocabulary.{Deck, DeckWord, Word, WordOccurrence}

  def normalize_form(nil), do: nil

  def normalize_form(term) when is_binary(term) do
    term
    |> String.normalize(:nfd)
    |> String.downcase()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  def get_word(id), do: Repo.get(Word, id)
  def get_word!(id), do: Repo.get!(Word, id)

  def get_word_by_normalized_form(normalized_form, language) do
    Repo.get_by(Word, normalized_form: normalized_form, language: language)
  end

  def get_or_create_word(attrs) do
    normalized =
      attrs
      |> fetch_any([:normalized_form, "normalized_form", :lemma])
      |> normalize_form()

    language = fetch_any(attrs, [:language, "language"])
    definitions = fetch_optional(attrs, [:definitions, "definitions"]) || []

    case get_word_by_normalized_form(normalized, language) do
      nil ->
        attrs
        |> Enum.into(%{})
        |> Map.put(:normalized_form, normalized)
        |> Map.put(:language, language)
        |> Map.put_new(:definitions, definitions)
        |> create_word()

      word ->
        maybe_update_definitions(word, definitions)
    end
  end

  defp fetch_any(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when value not in [nil, ""] -> value
        _ -> nil
      end
    end) || raise ArgumentError, "missing required attribute"
  end

  def create_word(attrs \\ %{}) do
    %Word{}
    |> Word.changeset(attrs)
    |> Repo.insert()
  end

  def update_word_definitions(%Word{} = word, definitions) when is_list(definitions) do
    word
    |> Word.changeset(%{definitions: definitions})
    |> Repo.update()
  end

  def update_word_conjugations(%Word{} = word, conjugations) when is_map(conjugations) do
    word
    |> Word.changeset(%{conjugations: conjugations})
    |> Repo.update()
  end

  defp maybe_update_definitions(word, definitions)
       when definitions in [nil, []] or definitions == word.definitions do
    {:ok, word}
  end

  defp maybe_update_definitions(%Word{} = word, definitions) do
    word
    |> Word.changeset(%{definitions: definitions})
    |> Repo.update()
  end

  defp fetch_optional(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when value not in [nil, ""] -> value
        _ -> nil
      end
    end)
  rescue
    _ -> nil
  end

  def change_word(%Word{} = word, attrs \\ %{}) do
    Word.changeset(word, attrs)
  end

  def create_occurrence(attrs \\ %{}) do
    %WordOccurrence{}
    |> WordOccurrence.changeset(attrs)
    |> Repo.insert()
  end

  def list_occurrences_for_sentence(sentence_id) do
    WordOccurrence
    |> where(sentence_id: ^sentence_id)
    |> order_by([o], asc: o.position)
    |> Repo.all()
    |> Repo.preload(:word)
  end

  ## Deck Management

  @doc """
  Gets or creates a default deck for a user.
  Ensures exactly one default deck exists per user.
  """
  def get_or_create_default_deck(user_id) do
    case Repo.one(
           from(d in Deck,
             where: d.user_id == ^user_id and d.is_default == true,
             limit: 1
           )
         ) do
      nil ->
        create_deck(user_id, %{name: "Default", is_default: true})

      deck ->
        {:ok, deck}
    end
  end

  @doc """
  Creates a new deck for a user.
  """
  def create_deck(user_id, attrs) do
    attrs = Map.put(attrs, :user_id, user_id)

    %Deck{}
    |> Deck.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all decks for a user, ordered by most recently used (when words were added).
  """
  def list_decks_for_user(user_id) do
    # Get all decks with their most recent word addition time
    decks_with_times =
      from(d in Deck,
        where: d.user_id == ^user_id,
        left_join: dw in DeckWord,
        on: dw.deck_id == d.id,
        group_by: d.id,
        select: %{
          deck_id: d.id,
          last_used: max(dw.inserted_at)
        }
      )
      |> Repo.all()
      |> Map.new(fn %{deck_id: deck_id, last_used: last_used} -> {deck_id, last_used} end)

    # Get all decks and sort by last_used (desc), then by name (asc)
    Deck
    |> where(user_id: ^user_id)
    |> Repo.all()
    |> Repo.preload([:words])
    |> Enum.sort(fn deck1, deck2 ->
      last_used1 = Map.get(decks_with_times, deck1.id) || ~U[1970-01-01 00:00:00Z]
      last_used2 = Map.get(decks_with_times, deck2.id) || ~U[1970-01-01 00:00:00Z]

      case DateTime.compare(last_used1, last_used2) do
        :gt -> true
        :lt -> false
        :eq -> deck1.name <= deck2.name
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Gets a deck by ID, ensuring it belongs to the user.
  """
  def get_deck_for_user!(deck_id, user_id) do
    Repo.get_by!(Deck, id: deck_id, user_id: user_id)
  end

  @doc """
  Gets a deck by ID, ensuring it belongs to the user.
  Returns nil if not found.
  """
  def get_deck_for_user(deck_id, user_id) do
    Repo.get_by(Deck, id: deck_id, user_id: user_id)
  end

  @doc """
  Updates a deck, ensuring it belongs to the user.
  Prevents unsetting is_default on the default deck.
  """
  def update_deck(deck_id, user_id, attrs) do
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        {:error, :not_found}

      deck ->
        # Prevent unsetting is_default on default deck
        attrs =
          if deck.is_default && Map.get(attrs, :is_default) == false do
            Map.delete(attrs, :is_default)
          else
            attrs
          end

        deck
        |> Deck.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a deck, ensuring it belongs to the user.
  Prevents deleting the default deck.
  """
  def delete_deck(deck_id, user_id) do
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        {:error, :not_found}

      %Deck{is_default: true} ->
        {:error, :cannot_delete_default}

      deck ->
        Repo.delete(deck)
    end
  end

  @doc """
  Adds a word to a deck.
  Ensures the deck belongs to the user.
  """
  def add_word_to_deck(deck_id, word_id, user_id) do
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        {:error, :deck_not_found}

      _deck ->
        case Repo.get_by(DeckWord, deck_id: deck_id, word_id: word_id) do
          nil ->
            %DeckWord{}
            |> DeckWord.changeset(%{deck_id: deck_id, word_id: word_id})
            |> Repo.insert()

          existing ->
            {:ok, existing}
        end
    end
  end

  @doc """
  Removes a word from a deck.
  Ensures the deck belongs to the user.
  """
  def remove_word_from_deck(deck_id, word_id, user_id) do
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        {:error, :deck_not_found}

      _deck ->
        case Repo.get_by(DeckWord, deck_id: deck_id, word_id: word_id) do
          nil ->
            {:ok, nil}

          deck_word ->
            Repo.delete(deck_word)
        end
    end
  end

  @doc """
  Lists all words in a deck with their associations preloaded.
  """
  def list_words_in_deck(deck_id, user_id) do
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        []

      _deck ->
        DeckWord
        |> where(deck_id: ^deck_id)
        |> join(:inner, [dw], w in Word, on: dw.word_id == w.id)
        |> order_by([dw, w], asc: w.normalized_form)
        |> select([dw, w], w)
        |> Repo.all()
        |> Repo.preload([:fsrs_items])
    end
  end

  @doc """
  Gets the word count for a deck.
  """
  def get_deck_word_count(deck_id) do
    Repo.aggregate(
      from(dw in DeckWord, where: dw.deck_id == ^deck_id),
      :count,
      :id
    )
  end

  @doc """
  Imports words from a CSV string into a deck.

  CSV format can be:
  - Single column: word
  - Two columns: word, language

  Uses user's target_language if not specified in CSV.
  """
  def import_words_from_csv(csv_content, deck_id, user_id, opts \\ []) do
    default_language = Keyword.get(opts, :default_language, "spanish")

    {:ok, rows} = parse_csv(csv_content)
    import_words_from_rows(rows, deck_id, user_id, default_language)
  end

  defp parse_csv(content) when is_binary(content) do
    rows =
      content
      |> String.trim()
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_csv_line/1)

    {:ok, rows}
  end

  defp parse_csv_line(line) do
    # Simple CSV parsing - split by comma
    # For more complex cases, we could use nimble_csv, but this handles basic cases
    case String.split(line, ",") do
      [word] ->
        {String.trim(word), nil}

      [word, language] ->
        {String.trim(word), String.trim(language)}

      parts when length(parts) > 2 ->
        # Take first two columns, ignore rest
        [word, language | _] = parts
        {String.trim(word), String.trim(language)}
    end
  end

  defp import_words_from_rows(rows, deck_id, user_id, default_language) do
    # Verify deck ownership
    case get_deck_for_user(deck_id, user_id) do
      nil ->
        {:error, :deck_not_found}

      _deck ->
        results =
          rows
          |> Enum.map(fn {word_text, language} ->
            process_csv_row(word_text, language || default_language, deck_id, user_id)
          end)

        successful = Enum.count(results, fn r -> match?({:ok, _}, r) end)
        errors = Enum.count(results, fn r -> match?({:error, _}, r) end)

        {:ok, %{successful: successful, errors: errors, total: length(rows)}}
    end
  end

  defp process_csv_row(word_text, language, deck_id, user_id) do
    word_text = String.trim(word_text)

    if word_text == "" do
      {:error, :empty_word}
    else
      import_single_word(word_text, language, deck_id, user_id)
    end
  end

  defp import_single_word(word_text, language, deck_id, user_id) do
    with {:ok, word} <- get_or_create_word_from_text(word_text, language, user_id),
         {:ok, _deck_word} <- add_word_to_deck(deck_id, word.id, user_id),
         {:ok, _item} <- Study.schedule_new_item(user_id, word.id) do
      {:ok, word}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_word_from_text(word_text, language, user_id) do
    normalized = normalize_form(word_text)

    case get_word_by_normalized_form(normalized, language) do
      nil ->
        # Lookup dictionary entry to get definitions
        api_key = GoogleTranslateConfig.get_api_key(user_id)

        case Dictionary.lookup(word_text, language: language, api_key: api_key, user_id: user_id) do
          {:ok, entry} ->
            # entry.definitions is always a list per Dictionary.entry type, but handle nil defensively
            definitions = if entry.definitions, do: entry.definitions, else: []

            create_word(%{
              normalized_form: normalized,
              lemma: entry.lemma,
              language: language,
              part_of_speech: entry.part_of_speech,
              definitions: definitions
            })

          {:error, reason} ->
            # Log warning but still create word without definitions
            require Logger
            Logger.warning("Dictionary lookup failed for word import: #{inspect(reason)}")

            create_word(%{
              normalized_form: normalized,
              lemma: nil,
              language: language,
              part_of_speech: nil,
              definitions: []
            })
        end

      word ->
        {:ok, word}
    end
  end
end
