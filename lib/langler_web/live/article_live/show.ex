defmodule LanglerWeb.ArticleLive.Show do
  use LanglerWeb, :live_view
  require Logger

  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.External.Dictionary
  alias Langler.Study
  alias Langler.Vocabulary

  @token_regex ~r/\p{L}+\p{M}*|[^\p{L}]+/u

  def mount(%{"id" => article_id}, _session, socket) do
    scope = socket.assigns.current_scope
    article = Content.get_article_for_user!(scope.user.id, article_id)

    {:ok, assign_article(socket, article)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-4xl space-y-8 px-4 py-8 sm:px-6 lg:px-0">
        <div class="card border border-base-200 bg-base-100/90 shadow-xl backdrop-blur">
          <div class="card-body gap-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-2">
                <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                  {humanize_source(@article)}
                </p>
                <h1 class="text-2xl font-bold text-base-content sm:text-3xl">
                  {display_title(@article)}
                </h1>
                <p class="text-sm text-base-content/70">
                  Imported {format_timestamp(@article.inserted_at)}
                </p>
                <div :if={@article_topics != []} class="flex flex-wrap items-center gap-2">
                  <span class="text-xs font-semibold uppercase tracking-widest text-base-content/50">Topics</span>
                  <span
                    :for={topic <- @article_topics}
                    class="badge badge-sm rounded-full border border-primary/30 bg-primary/10 text-primary"
                  >
                    {topic.topic}
                  </span>
                </div>
              </div>
              <span class="badge badge-lg badge-outline self-start uppercase tracking-wide text-base-content/80">
                {@article.language}
              </span>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-3">
              <.link
                navigate={~p"/articles"}
                class="btn btn-ghost btn-sm gap-2 text-base-content/80"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to library
              </.link>

              <div class="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  class="btn btn-ghost btn-sm gap-2 text-error"
                  phx-click="archive_article"
                  phx-disable-with="Archiving..."
                  phx-confirm="Archive this article? Tracked words stay in your study deck."
                >
                  <.icon name="hero-archive-box" class="h-4 w-4" /> Archive
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm gap-2"
                  phx-click="refresh_article"
                  phx-disable-with="Refreshing..."
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" /> Refresh article
                </button>
                <.link
                  href={@article.url}
                  target="_blank"
                  class="btn btn-outline btn-sm gap-2"
                >
                  View original <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                </.link>
              </div>
            </div>
          </div>
        </div>

        <article
          id="article-reader"
          class="card border border-base-200 bg-base-100/90 p-5 text-base leading-relaxed text-base-content shadow-xl backdrop-blur sm:p-8 sm:text-lg"
        >
          <p
            :for={sentence <- @sentences}
            class="mb-4 break-words text-justify last:mb-0"
            style="font-size: 0;"
          >
            <span
              :for={token <- tokenize_sentence(sentence.content, sentence.word_occurrences || [])}
              data-word={token.lexical? && token.text}
              data-sentence-id={sentence.id}
              data-language={@article.language}
              data-word-id={token.word && token.word.id}
              phx-hook={token.lexical? && "WordTooltip"}
              id={"token-#{sentence.id}-#{token.id}"}
              class={[
                "inline align-baseline text-base sm:text-lg leading-relaxed text-base-content",
                # Restore font size (parent has font-size: 0 to collapse whitespace between spans)
                token.lexical? &&
                  [
                    "cursor-pointer rounded transition hover:bg-primary/10 hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary/40",
                    studied_token?(token, @studied_word_ids, @studied_forms) &&
                      "bg-primary/5 text-primary"
                  ]
              ]}
              style={
                # Remove spacing before punctuation tokens to attach them visually to previous word
                if not token.lexical? and String.match?(token.text, ~r/^[,\.;:!?\)\]\}]/u) do
                  "margin-left: -0.15em;"
                else
                  nil
                end
              }
            >
              {token.text}
            </span>
          </p>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp assign_article(socket, article) do
    user_id = socket.assigns.current_scope.user.id
    sentences = Content.list_sentences(article)
    {studied_word_ids, studied_forms, study_items_by_word} = seed_studied_words(user_id, sentences)
    topics = Content.list_topics_for_article(article.id)

    sentence_lookup =
      Map.new(sentences, fn sentence -> {Integer.to_string(sentence.id), sentence} end)

    socket
    |> assign(:article, article)
    |> assign(:sentences, sentences)
    |> assign(:sentence_lookup, sentence_lookup)
    |> assign(:studied_word_ids, studied_word_ids)
    |> assign(:studied_forms, studied_forms)
    |> assign(:study_items_by_word, study_items_by_word)
    |> assign(:article_topics, topics)
    |> assign(:page_title, article.title || humanize_source(article))
  end

  def handle_event(
        "refresh_article",
        _params,
        %{assigns: %{current_scope: scope, article: article}} = socket
      ) do
    case ArticleImporter.import_from_url(scope.user, article.url) do
      {:ok, updated, _status} ->
        refreshed = Content.get_article_for_user!(scope.user.id, updated.id)
        {:noreply, socket |> assign_article(refreshed) |> put_flash(:info, "Article refreshed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to refresh: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "archive_article",
        _params,
        %{assigns: %{current_scope: scope, article: article}} = socket
      ) do
    case Content.archive_article_for_user(scope.user.id, article.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Article archived")
         |> push_navigate(to: ~p"/articles")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to archive: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "fetch_word_data",
        %{
          "word" => word,
          "language" => language,
          "sentence_id" => sentence_id,
          "dom_id" => dom_id
        } = params,
        socket
      ) do
    word_id = Map.get(params, "word_id")
    trimmed_word = word |> to_string() |> String.trim()
    normalized = Vocabulary.normalize_form(trimmed_word)
    sentence = Map.get(socket.assigns.sentence_lookup, sentence_id)
    context = if sentence, do: sentence.content, else: nil
    {:ok, entry} = Dictionary.lookup(trimmed_word, language: language, target: "en")
    {resolved_word, studied?} = resolve_word(word_id, entry, normalized, language, socket)

    payload =
      entry
      |> Map.take([
        :lemma,
        :part_of_speech,
        :pronunciation,
        :definitions,
        :translation,
        :source_url
      ])
      |> Map.put_new(:definitions, [])
      |> Map.merge(%{
        dom_id: dom_id,
        word: trimmed_word,
        language: language,
        normalized_form: normalized,
        context: context,
        word_id: resolved_word && resolved_word.id,
        studied: studied?,
        rating_required: studied?,
        study_item_id:
          resolved_word &&
            socket.assigns[:study_items_by_word]
            |> Map.get(resolved_word.id)
            |> then(fn
              %{id: id} -> id
              _ -> nil
            end),
        fsrs_sleep_until:
          resolved_word && fsrs_sleep_until(socket.assigns[:study_items_by_word], resolved_word.id)
      })
    Logger.debug("word-data payload: #{inspect(payload)}")

    {:noreply, push_event(socket, "word-data", payload)}
  end

  def handle_event(
        "rate_new_word",
        %{"word_id" => word_id, "quality" => quality} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, item} <- Study.schedule_new_item(scope.user.id, word.id),
         rating <- Study.normalize_rating(quality),
         {:ok, updated} <- Study.review_item(item, rating) do
      study_items_by_word =
        Map.put(socket.assigns[:study_items_by_word] || %{}, word.id, %{
          id: item.id,
          due_date: updated.due_date
        })

      {:noreply,
       socket
       |> assign(:study_items_by_word, study_items_by_word)
       |> push_event("word-rated", %{
         word_id: word.id,
         study_item_id: item.id,
         fsrs_sleep_until: updated.due_date,
         dom_id: Map.get(params, "dom_id")
       })}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to rate word: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "rate_existing_word",
        %{"word_id" => word_id, "quality" => quality} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         %Study.FSRSItem{} = item <- Study.get_item_by_user_and_word(scope.user.id, word.id),
         rating <- Study.normalize_rating(quality),
         {:ok, updated} <- Study.review_item(item, rating) do
      study_items_by_word =
        Map.put(socket.assigns[:study_items_by_word] || %{}, word.id, %{
          id: item.id,
          due_date: updated.due_date
        })

      {:noreply,
       socket
       |> assign(:study_items_by_word, study_items_by_word)
       |> push_event("word-rated", %{
         word_id: word.id,
         study_item_id: item.id,
         fsrs_sleep_until: updated.due_date,
         dom_id: Map.get(params, "dom_id")
       })}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Word is not currently in your study list")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to rate card: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "remove_from_study",
        %{"word_id" => word_id} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, _} <- Study.remove_item(scope.user.id, word.id) do
      studied_word_ids = MapSet.delete(socket.assigns.studied_word_ids, word.id)

      studied_forms =
        case normalized_form_from_word(word) do
          nil -> socket.assigns.studied_forms
          form -> MapSet.delete(socket.assigns.studied_forms, form)
        end

      study_items_by_word =
        Map.delete(socket.assigns[:study_items_by_word] || %{}, word.id)

      {:noreply,
       socket
       |> assign(:studied_word_ids, studied_word_ids)
       |> assign(:studied_forms, studied_forms)
       |> assign(:study_items_by_word, study_items_by_word)
       |> push_event("word-removed", %{word_id: word.id, dom_id: Map.get(params, "dom_id")})}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to remove word: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "add_to_study",
        %{"word_id" => word_id} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, item} <- Study.schedule_new_item(scope.user.id, word.id) do
      studied_word_ids = MapSet.put(socket.assigns.studied_word_ids, word.id)

      studied_forms =
        case normalized_form_from_word(word) do
          nil -> socket.assigns.studied_forms
          form -> MapSet.put(socket.assigns.studied_forms, form)
        end

      study_items_by_word =
        Map.put(socket.assigns[:study_items_by_word] || %{}, word.id, %{
          id: item.id,
          due_date: item.due_date
        })

      {:noreply,
       socket
       |> assign(:studied_word_ids, studied_word_ids)
       |> assign(:studied_forms, studied_forms)
       |> assign(:study_items_by_word, study_items_by_word)
       |> push_event("word-added", %{
         word_id: word.id,
         study_item_id: item.id,
         fsrs_sleep_until: item.due_date,
         dom_id: Map.get(params, "dom_id")
       })
       |> put_flash(:info, "#{word.lemma || word.normalized_form} added to study")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to add word: #{inspect(reason)}")}
    end
  end

  defp tokenize_sentence(content, occurrences)
       when is_binary(content) and is_list(occurrences) do
    occurrence_map =
      occurrences
      |> Enum.reduce(%{}, fn occurrence, acc ->
        case occurrence.word do
          nil -> acc
          word -> Map.put(acc, occurrence.position, word)
        end
      end)

    tokens =
      @token_regex
      |> Regex.scan(content)
      |> Enum.map(&hd/1)
      |> Enum.reject(&(&1 == ""))

    # First pass: trim spaces from punctuation tokens and split them into separate tokens
    # This preserves spaces while keeping words and punctuation separate
    cleaned_tokens =
      tokens
      |> Enum.flat_map(fn text ->
        cond do
          # Punctuation token with spaces (like " , ") - split into space, punctuation, space
          String.match?(text, ~r/^\s+[^\p{L}\s]+\s+$/u) ->
            trimmed = String.trim(text)
            trimmed_leading = String.trim_leading(text)
            trimmed_trailing = String.trim_trailing(text)

            leading_len = String.length(text) - String.length(trimmed_leading)
            trailing_start = String.length(trimmed_trailing)
            text_len = String.length(text)

            leading_space = if leading_len > 0, do: String.slice(text, 0, leading_len), else: ""
            trailing_space = if trailing_start < text_len, do: String.slice(text, trailing_start, text_len - trailing_start), else: ""

            result = []
            result = if leading_space != "", do: [leading_space | result], else: result
            result = if trimmed != "", do: [trimmed | result], else: result
            result = if trailing_space != "", do: [trailing_space | result], else: result
            Enum.reverse(result) |> Enum.filter(&(&1 != ""))

          # Punctuation token with leading/trailing spaces - split them
          String.match?(text, ~r/^[^\p{L}]+$/u) and not String.match?(text, ~r/^\s+$/u) ->
            trimmed = String.trim(text)
            trimmed_leading = String.trim_leading(text)
            trimmed_trailing = String.trim_trailing(text)

            leading_len = String.length(text) - String.length(trimmed_leading)
            trailing_start = String.length(trimmed_trailing)
            text_len = String.length(text)

            leading_space = if leading_len > 0, do: String.slice(text, 0, leading_len), else: ""
            trailing_space = if trailing_start < text_len, do: String.slice(text, trailing_start, text_len - trailing_start), else: ""

            result = []
            result = if leading_space != "", do: [leading_space | result], else: result
            result = if trimmed != "", do: [trimmed | result], else: result
            result = if trailing_space != "", do: [trailing_space | result], else: result
            Enum.reverse(result) |> Enum.filter(&(&1 != ""))

          # Other tokens (words, spaces) - keep as-is
          true ->
            [text]
        end
      end)
      |> Enum.reject(&(&1 == ""))

    # Second pass: attach spaces to words and punctuation tokens
    # Strategy:
    # - Keep words and punctuation as completely separate tokens (for translation)
    # - Attach spaces to words or punctuation tokens to preserve natural spacing
    # - Use CSS to handle visual spacing between word and punctuation spans
    cleaned_tokens
      |> Enum.reduce([], fn token, acc ->
        is_word = String.match?(token, ~r/^\p{L}/u)
        is_punct = String.match?(token, ~r/^[^\p{L}\s]+$/u)
        is_space = String.match?(token, ~r/^\s+$/u)

        cond do
          # Word token - add as new token
          is_word ->
            [token | acc]

          # Punctuation token - keep separate, don't merge with words
          is_punct ->
            [token | acc]

          # Space token - attach to previous token if it's a word or punctuation
          is_space ->
            case acc do
              [prev | rest] ->
                prev_is_word = String.match?(prev, ~r/^\p{L}/u)
                prev_is_punct = String.match?(prev, ~r/^[^\p{L}\s]+$/u)

                if prev_is_word || prev_is_punct do
                  # Attach space to previous word or punctuation
                  [prev <> token | rest]
                else
                  # No previous word/punctuation - keep space separate
                  [token | acc]
                end

              _ ->
                # Empty acc - keep space separate
                [token | acc]
            end

          # Other - keep as-is
          true ->
            [token | acc]
        end
      end)
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {text, idx} ->
        # Map word occurrences - try to find matching word from original position
        word = Map.get(occurrence_map, idx)
        %{id: idx, text: text, lexical?: lexical_token?(text), word: word}
      end)
  end

  defp lexical_token?(text) do
    String.match?(text, ~r/\p{L}/u)
  end

  defp studied_token?(token, studied_ids, studied_forms) do
    cond do
      token.word && MapSet.member?(studied_ids, token.word.id) ->
        true

      token.lexical? &&
          token.text
          |> String.trim()
          |> Vocabulary.normalize_form()
          |> then(&(&1 && MapSet.member?(studied_forms, &1))) ->
        true

      true ->
        false
    end
  end

  defp fetch_word(nil), do: {:error, :missing_word_id}

  defp fetch_word(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> fetch_word(parsed)
      _ -> {:error, :invalid_word_id}
    end
  end

  defp fetch_word(id) when is_integer(id) do
    case Vocabulary.get_word(id) do
      nil -> {:error, :word_not_found}
      word -> {:ok, word}
    end
  end

  defp resolve_word(word_id, entry, normalized, language, socket) do
    case resolve_word_record(word_id, entry, normalized, language) do
      {:ok, word} ->
        studied? =
          MapSet.member?(socket.assigns.studied_word_ids, word.id) ||
            MapSet.member?(socket.assigns.studied_forms, normalized_form_from_word(word))

        {word, studied?}

      {:error, _reason} ->
        {nil, MapSet.member?(socket.assigns.studied_forms, normalized)}
    end
  end

  defp resolve_word_record(nil, entry, normalized, language) do
    lemma =
      Map.get(entry, :lemma) || Map.get(entry, "lemma") || Map.get(entry, :word) || entry[:word]
    definitions = Map.get(entry, :definitions) || Map.get(entry, "definitions") || []

    Vocabulary.get_or_create_word(%{
      normalized_form: normalized,
      language: language,
      lemma: lemma,
      part_of_speech: Map.get(entry, :part_of_speech) || Map.get(entry, "part_of_speech"),
      definitions: definitions
    })
  end

  defp resolve_word_record(word_id, _entry, _normalized, _language) do
    fetch_word(word_id)
  end

  defp normalized_form_from_word(word) when is_nil(word), do: nil

  defp normalized_form_from_word(word) do
    word.normalized_form || Vocabulary.normalize_form(word.lemma)
  end

  defp seed_studied_words(user_id, sentences) do
    word_ids =
      sentences
      |> Enum.flat_map(fn sentence ->
        (sentence.word_occurrences || [])
        |> Enum.map(& &1.word_id)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    existing_items = Study.list_items_for_user(user_id, word_ids: word_ids)

    ids = MapSet.new(Enum.map(existing_items, & &1.word_id))

    forms =
      existing_items
      |> Enum.map(&(&1.word && &1.word.normalized_form))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    items_by_word =
      Enum.reduce(existing_items, %{}, fn item, acc ->
        if item.word_id do
          Map.put(acc, item.word_id, %{id: item.id, due_date: item.due_date})
        else
          acc
        end
      end)

    {ids, forms, items_by_word}
  end

  defp fsrs_sleep_until(map, word_id) do
    case Map.get(map || %{}, word_id) do
      %{due_date: due} -> due
      _ -> nil
    end
  end

  defp humanize_source(article) do
    article.source || URI.parse(article.url).host || "Article"
  end

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    datetime
    |> Calendar.strftime("%b %d, %Y at %H:%M %Z")
  end

  defp display_title(article) do
    cond do
      article.title && article.title != "" -> article.title
      true -> humanize_slug(article.url)
    end
  end

  defp humanize_slug(nil), do: "Article"
  defp humanize_slug(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> case do
      nil -> url
      path ->
        path
        |> Path.basename()
        |> String.replace(~r/[-_]+/, " ")
        |> String.trim()
        |> String.capitalize()
    end
  end
end
