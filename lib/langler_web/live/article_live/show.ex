defmodule LanglerWeb.ArticleLive.Show do
  @moduledoc """
  LiveView for reading and studying an article.
  """

  use LanglerWeb, :live_view
  require Logger

  alias Langler.Accounts
  alias Langler.Accounts.LlmConfig
  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.Content.ArticleUser
  alias Langler.External.Dictionary
  alias Langler.Quizzes
  alias Langler.Repo
  alias Langler.Study
  alias Langler.Vocabulary

  @token_regex ~r/\p{L}+\p{M}*|[^\p{L}]+/u

  def mount(%{"id" => article_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    article = Content.get_article_for_user!(scope.user.id, article_id)

    socket =
      socket
      |> assign_article(article)
      |> maybe_start_quiz_from_params(params, scope.user.id, article)

    {:ok, socket}
  end

  defp maybe_start_quiz_from_params(socket, params, user_id, article) do
    if Map.get(params, "quiz") == "1" do
      maybe_start_quiz(socket, user_id, article)
    else
      socket
    end
  end

  defp maybe_start_quiz(socket, user_id, article) do
    with %ArticleUser{status: "finished"} <- get_article_user(user_id, article.id),
         %{} <- LlmConfig.get_default_config(user_id) do
      send_update(LanglerWeb.ChatLive.Drawer,
        id: "chat-drawer",
        action: :start_article_quiz,
        article_id: article.id,
        article_title: display_title(article),
        article_language: article.language,
        article_topics: Enum.map(socket.assigns.article_topics || [], & &1.topic),
        article_content: article.content
      )
    end

    socket
  end

  defp get_article_user(user_id, article_id) do
    Repo.get_by(ArticleUser, user_id: user_id, article_id: article_id)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <div
          id="article-hero"
          phx-hook="ArticleStickyHeader"
          data-article-target="article-reader"
          class="surface-panel article-meta section-card card w-full rounded-3xl bg-base-100/90"
        >
          <div class="card-body gap-6 lg:grid lg:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)] lg:items-start lg:gap-10">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between lg:col-span-2">
              <div class="space-y-2">
                <p class="article-meta__full text-sm font-semibold uppercase tracking-widest text-base-content/60">
                  {humanize_source(@article)}
                </p>
                <h1 class="article-meta__full text-2xl font-bold text-base-content sm:text-3xl">
                  {display_title(@article)}
                </h1>
                <p class="article-meta__full text-sm text-base-content/70 flex flex-wrap items-center gap-2">
                  <span>Imported {format_timestamp(@article.inserted_at)}</span>
                  <span
                    :if={@reading_time_minutes}
                    class="inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-widest text-primary/80"
                  >
                    <.icon name="hero-clock" class="h-4 w-4" />
                    {@reading_time_minutes} min read
                  </span>
                </p>
                <div
                  :if={@article_topics != []}
                  class="article-meta__full flex flex-wrap items-center gap-2"
                >
                  <span class="text-xs font-semibold uppercase tracking-widest text-base-content/50">
                    Topics
                  </span>
                  <span
                    :for={topic <- @article_topics}
                    class="badge badge-sm rounded-full border border-primary/30 bg-primary/10 text-primary"
                  >
                    {topic.topic}
                  </span>
                </div>
              </div>
              <span class="article-meta__full badge badge-lg badge-outline self-start uppercase tracking-wide text-base-content/80">
                {@article.language}
              </span>
            </div>

            <div class="article-meta__controls flex flex-wrap items-center justify-between gap-2 lg:col-span-2 lg:flex-nowrap">
              <.link
                navigate={~p"/articles"}
                class="btn btn-ghost btn-sm gap-2 text-base-content/80 article-meta__back"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4" />
                <span class="article-meta__button-label">Back to library</span>
              </.link>

              <p class="article-meta__sticky-title text-base font-semibold text-base-content">
                {@article_short_title}
              </p>

              <div class="flex flex-wrap items-center gap-2 article-meta__actions lg:flex-nowrap">
                <div class="tooltip tooltip-right" data-tip="Start a practice chat for this article">
                  <button
                    :if={@article_status in ["imported", "finished"]}
                    type="button"
                    class="article-meta__btn btn btn-primary btn-sm gap-2 text-white"
                    aria-label="Practice with chat"
                    phx-click="start_article_chat"
                  >
                    <.icon name="hero-chat-bubble-left-right" class="h-4 w-4" />
                    <span class="article-meta__button-label">Practice with chat</span>
                  </button>
                </div>
                <div
                  class="tooltip tooltip-right"
                  data-tip="Launch the comprehension quiz for this article"
                >
                  <button
                    :if={@article_status in ["imported", "finished"]}
                    type="button"
                    class="article-meta__btn btn btn-secondary btn-sm gap-2 text-white"
                    aria-label="Take quiz"
                    phx-click="start_article_quiz"
                  >
                    <.icon name="hero-academic-cap" class="h-4 w-4" />
                    <span class="article-meta__button-label">Take quiz</span>
                  </button>
                </div>
                <div
                  :if={@article_status == "imported"}
                  class="dropdown dropdown-bottom dropdown-start tooltip tooltip-right"
                  data-tip="Mark this article as finished"
                >
                  <button
                    type="button"
                    tabindex="0"
                    class="article-meta__btn btn btn-ghost btn-sm gap-2"
                    aria-label="Finish article"
                  >
                    <span class="flex items-center gap-2">
                      <.icon name="hero-flag" class="h-4 w-4" />
                      <span class="article-meta__button-label hidden sm:inline">Finish</span>
                    </span>
                  </button>
                  <ul
                    tabindex="0"
                    class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 border border-base-300 p-2 shadow-lg right-0 left-auto mt-2"
                  >
                    <li>
                      <button
                        type="button"
                        phx-click="finish_without_quiz"
                        phx-confirm="Mark this article as finished without taking a quiz?"
                      >
                        <.icon name="hero-check" class="h-4 w-4" /> Finish without quiz
                      </button>
                    </li>
                  </ul>
                </div>
                <div
                  class="tooltip tooltip-right"
                  data-tip="Archived articles can be deleted from settings."
                >
                  <button
                    type="button"
                    class="article-meta__btn btn btn-ghost btn-sm gap-2 text-error"
                    aria-label="Archive article"
                    phx-click="archive_article"
                    phx-disable-with="Archiving..."
                    phx-confirm="Archive this article? Tracked words stay in your study deck."
                  >
                    <.icon name="hero-archive-box" class="h-4 w-4" />
                    <span class="article-meta__button-label">Archive</span>
                  </button>
                </div>
                <div
                  class="tooltip tooltip-right"
                  data-tip="Re-import the article content and vocabulary"
                >
                  <button
                    type="button"
                    class="article-meta__btn btn btn-ghost btn-sm gap-2"
                    aria-label="Refresh article"
                    phx-click="refresh_article"
                    phx-disable-with="Refreshing..."
                  >
                    <.icon name="hero-arrow-path" class="h-4 w-4" />
                    <span class="article-meta__button-label">Refresh article</span>
                  </button>
                </div>
                <div class="tooltip tooltip-right" data-tip="Open the original article in a new tab">
                  <.link
                    href={@article.url}
                    target="_blank"
                    class="article-meta__btn btn btn-outline btn-sm gap-2"
                    aria-label="View original article"
                  >
                    <span class="article-meta__button-label">View original</span>
                    <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                  </.link>
                </div>
              </div>
            </div>
          </div>
          <div class="article-meta__progress" aria-hidden="true">
            <div class="article-meta__progress-track">
              <div class="article-meta__progress-fill" data-progress-fill></div>
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
              class={
                [
                  "inline align-baseline text-base sm:text-lg leading-relaxed text-base-content",
                  # Restore font size (parent has font-size: 0 to collapse whitespace between spans)
                  token.lexical? &&
                    [
                      "cursor-pointer rounded transition hover:bg-primary/10 hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary/40",
                      studied_token?(token, @studied_word_ids, @studied_forms) &&
                        "bg-primary/5 text-primary"
                    ]
                ]
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

    {studied_word_ids, studied_forms, study_items_by_word} =
      seed_studied_words(user_id, sentences)

    topics = Content.list_topics_for_article(article.id)

    sentence_lookup =
      Map.new(sentences, fn sentence -> {Integer.to_string(sentence.id), sentence} end)

    reading_time_minutes = calculate_reading_time(sentences)

    # Get article_user to determine status
    article_user = get_article_user(user_id, article.id)
    article_status = if article_user, do: article_user.status, else: "imported"

    socket
    |> assign(:article, article)
    |> assign(:sentences, sentences)
    |> assign(:sentence_lookup, sentence_lookup)
    |> assign(:studied_word_ids, studied_word_ids)
    |> assign(:studied_forms, studied_forms)
    |> assign(:study_items_by_word, study_items_by_word)
    |> assign(:article_topics, topics)
    |> assign(:reading_time_minutes, reading_time_minutes)
    |> assign(:article_short_title, truncated_title(article))
    |> assign(:page_title, article.title || humanize_source(article))
    |> assign(:article_status, article_status)
  end

  defp calculate_reading_time(sentences) do
    total_words =
      sentences
      |> Enum.map(&String.split(&1.content || "", ~r/\s+/, trim: true))
      |> Enum.map(&length/1)
      |> Enum.sum()

    minutes = Float.ceil(total_words / 200, 1)

    if minutes > 0 do
      minutes
    else
      nil
    end
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
        "start_article_chat",
        _params,
        %{assigns: %{current_scope: scope, article: article}} = socket
      ) do
    if LlmConfig.get_default_config(scope.user.id) do
      send_update(LanglerWeb.ChatLive.Drawer,
        id: "chat-drawer",
        action: :start_article_chat,
        article_id: article.id,
        article_title: display_title(article),
        article_language: article.language,
        article_topics: Enum.map(socket.assigns.article_topics || [], & &1.topic),
        article_content: article.content
      )

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Add an LLM provider in settings before starting a chat")}
    end
  end

  def handle_event(
        "start_article_quiz",
        _params,
        %{assigns: %{current_scope: scope, article: article}} = socket
      ) do
    if LlmConfig.get_default_config(scope.user.id) do
      send_update(LanglerWeb.ChatLive.Drawer,
        id: "chat-drawer",
        action: :start_article_quiz,
        article_id: article.id,
        article_title: display_title(article),
        article_language: article.language,
        article_topics: Enum.map(socket.assigns.article_topics || [], & &1.topic),
        article_content: article.content
      )

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Add an LLM provider in settings before starting a quiz")}
    end
  end

  def handle_event(
        "finish_without_quiz",
        _params,
        %{assigns: %{current_scope: scope, article: article}} = socket
      ) do
    case Content.finish_article_for_user(scope.user.id, article.id) do
      {:ok, _} ->
        # Create skip attempt
        Quizzes.create_skip_attempt(scope.user.id, article.id)

        {:noreply,
         socket
         |> put_flash(:info, "Article marked as finished")
         |> push_navigate(to: ~p"/articles")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to finish article: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "fetch_word_data",
        %{"word" => word, "language" => language, "dom_id" => dom_id} = params,
        socket
      ) do
    word_id = Map.get(params, "word_id")
    trimmed_word = word |> to_string() |> String.trim()
    normalized = Vocabulary.normalize_form(trimmed_word)
    sentence_id = Map.get(params, "sentence_id")
    sentence = sentence_id && Map.get(socket.assigns.sentence_lookup, sentence_id)

    context =
      cond do
        is_binary(Map.get(params, "context")) -> params["context"]
        sentence -> sentence.content
        true -> nil
      end

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
          resolved_word &&
            fsrs_sleep_until(socket.assigns[:study_items_by_word], resolved_word.id)
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
         {:ok, item} <- Study.schedule_new_item(scope.user.id, word.id),
         {:ok, _deck_word} <- add_word_to_current_deck(scope.user.id, word.id) do
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

  defp add_word_to_current_deck(user_id, word_id) do
    case Accounts.get_current_deck(user_id) do
      nil ->
        {:error, :no_deck_available}

      deck ->
        Vocabulary.add_word_to_deck(deck.id, word_id, user_id)
    end
  end

  defp tokenize_sentence(content, occurrences)
       when is_binary(content) and is_list(occurrences) do
    occurrence_map = build_occurrence_map(occurrences)

    content
    |> extract_tokens()
    |> normalize_tokens()
    |> attach_spaces_to_tokens()
    |> Enum.with_index()
    |> Enum.map(fn {text, idx} ->
      # Map word occurrences - try to find matching word from original position
      word = Map.get(occurrence_map, idx)
      %{id: idx, text: text, lexical?: lexical_token?(text), word: word}
    end)
  end

  defp build_occurrence_map(occurrences) do
    Enum.reduce(occurrences, %{}, fn occurrence, acc ->
      case occurrence.word do
        nil -> acc
        word -> Map.put(acc, occurrence.position, word)
      end
    end)
  end

  defp extract_tokens(content) do
    @token_regex
    |> Regex.scan(content)
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tokens(tokens) do
    tokens
    |> Enum.flat_map(&split_punctuation_token/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_punctuation_token(text) do
    cond do
      String.match?(text, ~r/^\s+[^\p{L}\s]+\s+$/u) ->
        split_with_spaces(text)

      String.match?(text, ~r/^[^\p{L}]+$/u) and not String.match?(text, ~r/^\s+$/u) ->
        split_with_spaces(text)

      true ->
        [text]
    end
  end

  defp split_with_spaces(text) do
    trimmed = String.trim(text)
    trimmed_leading = String.trim_leading(text)
    trimmed_trailing = String.trim_trailing(text)

    leading_len = String.length(text) - String.length(trimmed_leading)
    trailing_start = String.length(trimmed_trailing)
    text_len = String.length(text)

    leading_space = if leading_len > 0, do: String.slice(text, 0, leading_len), else: ""

    trailing_space =
      if trailing_start < text_len,
        do: String.slice(text, trailing_start, text_len - trailing_start),
        else: ""

    result = []
    result = if leading_space != "", do: [leading_space | result], else: result
    result = if trimmed != "", do: [trimmed | result], else: result
    result = if trailing_space != "", do: [trailing_space | result], else: result
    Enum.reverse(result) |> Enum.filter(&(&1 != ""))
  end

  defp attach_spaces_to_tokens(tokens) do
    tokens
    |> Enum.reduce([], &attach_space_token/2)
    |> Enum.reverse()
    |> collapse_space_before_punct()
  end

  # Remove trailing whitespace from tokens when followed by punctuation that attaches
  # to the previous word (like commas, periods, semicolons, etc.)
  # This handles cases where the source text has incorrect spacing like "word , next"
  defp collapse_space_before_punct([]), do: []
  defp collapse_space_before_punct([single]), do: [single]

  defp collapse_space_before_punct(tokens) do
    tokens
    |> Enum.zip(tl(tokens) ++ [nil])
    |> Enum.map(fn
      {current, next} when is_binary(next) ->
        if attaching_punct?(next), do: String.trim_trailing(current), else: current

      {current, nil} ->
        current
    end)
  end

  defp attaching_punct?(token) do
    String.match?(token, ~r/^[,\.;:!?\)\]\}»›"']/u)
  end

  defp attach_space_token(token, acc) do
    case token_kind(token) do
      :word -> [token | acc]
      :punct -> [token | acc]
      :space -> attach_space_to_prev(token, acc)
      :other -> [token | acc]
    end
  end

  defp attach_space_to_prev(space, []), do: [space]

  defp attach_space_to_prev(space, [prev | rest]) do
    case token_kind(prev) do
      :word -> [prev <> space | rest]
      :punct -> [prev <> space | rest]
      _ -> [space, prev | rest]
    end
  end

  defp token_kind(token) do
    cond do
      String.match?(token, ~r/^\p{L}/u) -> :word
      String.match?(token, ~r/^[^\p{L}\s]+$/u) -> :punct
      String.match?(token, ~r/^\s+$/u) -> :space
      true -> :other
    end
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
    if article.title && article.title != "" do
      article.title
    else
      humanize_slug(article.url)
    end
  end

  defp truncated_title(article) do
    title = display_title(article) || "Article"

    if String.length(title) > 60 do
      String.slice(title, 0, 57) <> "..."
    else
      title
    end
  end

  defp humanize_slug(nil), do: "Article"

  defp humanize_slug(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> case do
      nil ->
        url

      path ->
        path
        |> Path.basename()
        |> String.replace(~r/[-_]+/, " ")
        |> String.trim()
        |> String.capitalize()
    end
  end
end
