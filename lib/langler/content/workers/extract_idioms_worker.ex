defmodule Langler.Content.Workers.ExtractIdiomsWorker do
  @moduledoc """
  Oban worker for detecting idioms in articles and storing idiom occurrences.

  Runs only when the user has auto_detect_idioms enabled and an LLM config.
  Deletes existing idiom occurrences for the article before inserting (idempotent).
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  alias Langler.Accounts
  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Encryption
  alias Langler.Content
  alias Langler.Content.IdiomSpanMatcher
  alias Langler.LLM.IdiomDetector
  alias Langler.Repo
  alias Langler.Vocabulary
  alias Langler.Vocabulary.Word

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"article_id" => article_id, "user_id" => user_id}}) do
    article_id = parse_id(article_id)
    user_id = parse_id(user_id)

    cond do
      is_nil(article_id) or is_nil(user_id) ->
        Logger.warning("ExtractIdiomsWorker: invalid article_id or user_id")
        :discard

      not (pref = Accounts.get_user_preference(user_id)) or not pref.auto_detect_idioms ->
        Logger.debug("ExtractIdiomsWorker: auto_detect_idioms disabled for user #{user_id}")
        :ok

      is_nil(LlmConfig.get_default_config(user_id)) ->
        Logger.debug("ExtractIdiomsWorker: no LLM config for user #{user_id}, skipping")
        :ok

      true ->
        config = LlmConfig.get_default_config(user_id)

        case Encryption.decrypt_message(user_id, config.encrypted_api_key) do
          {:ok, api_key} ->
            llm_config = build_llm_config(api_key, config)
            run_detection(article_id, user_id, llm_config)

          {:error, reason} ->
            Logger.warning(
              "ExtractIdiomsWorker: decrypt failed for user #{user_id}: #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  def perform(%Oban.Job{args: _}) do
    Logger.warning("ExtractIdiomsWorker: missing article_id or user_id")
    :discard
  end

  defp run_detection(article_id, _user_id, llm_config) do
    case Content.get_article(article_id) do
      nil ->
        Logger.warning("ExtractIdiomsWorker: article #{article_id} not found")
        :ok

      article ->
        sentences = Content.list_sentences(article)
        if sentences == [], do: :ok, else: process_idiom_detection(article, sentences, llm_config)
    end
  end

  defp process_idiom_detection(article, sentences, llm_config) do
    content = Enum.map_join(sentences, " ", & &1.content)

    case IdiomDetector.detect(content, article.language, llm_config) do
      {:ok, results} ->
        Content.delete_idiom_occurrences_for_article(article.id)
        Enum.each(results, &persist_idiom_results(&1, sentences, article.language))
        :ok

      {:error, reason} ->
        Logger.warning("ExtractIdiomsWorker: IdiomDetector failed: #{inspect(reason)}")
        :ok
    end
  end

  defp persist_idiom_results(%{sentence_index: idx, phrases: phrases}, sentences, language) do
    sentence = Enum.at(sentences, idx)

    if sentence && phrases != [] do
      spans = IdiomSpanMatcher.find_spans(sentence.content, phrases)

      Enum.each(spans, fn %{phrase: phrase, start_position: start_pos, end_position: end_pos} ->
        ensure_idiom_occurrence(sentence.id, phrase, language, start_pos, end_pos)
      end)
    end
  end

  defp ensure_idiom_occurrence(sentence_id, phrase, language, start_position, end_position) do
    normalized = Vocabulary.normalize_form(phrase)

    if is_nil(normalized) or normalized == "" do
      :ok
    else
      attrs = %{
        normalized_form: normalized,
        lemma: phrase,
        language: language,
        is_idiom: true,
        definitions: []
      }

      case Vocabulary.get_or_create_word(attrs) do
        {:ok, word} ->
          word = maybe_update_idiom_flag(word)

          Vocabulary.create_idiom_occurrence(%{
            sentence_id: sentence_id,
            word_id: word.id,
            start_position: start_position,
            end_position: end_position
          })

        {:error, _} ->
          :ok
      end
    end
  end

  defp maybe_update_idiom_flag(%Word{is_idiom: true} = word), do: word

  defp maybe_update_idiom_flag(%Word{} = word) do
    word
    |> Word.changeset(%{is_idiom: true})
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, _} -> word
    end
  end

  defp build_llm_config(api_key, config) do
    %{
      api_key: String.trim(api_key),
      model: config.model || "gpt-4o-mini",
      temperature: config.temperature || 0.3,
      max_tokens: config.max_tokens || 2000
    }
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
