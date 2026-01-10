defmodule LanglerWeb.ArticleLive.Show do
  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.External.Dictionary
  alias Langler.Study
  alias Langler.Vocabulary

  @token_regex ~r/\p{L}+\p{M}*|[^\p{L}]+/u

  def mount(%{"id" => article_id}, _session, socket) do
    scope = socket.assigns.current_scope
    article = Content.get_article_for_user!(scope.user.id, article_id)
    sentences = Content.list_sentences(article)
    {studied_word_ids, studied_forms} = seed_studied_words(scope.user.id, sentences)

    sentence_lookup =
      Map.new(sentences, fn sentence -> {Integer.to_string(sentence.id), sentence} end)

    {:ok,
     socket
     |> assign(:article, article)
     |> assign(:sentences, sentences)
     |> assign(:sentence_lookup, sentence_lookup)
     |> assign(:studied_word_ids, studied_word_ids)
     |> assign(:studied_forms, studied_forms)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl space-y-8 py-8">
        <div class="card border border-base-200 bg-base-100/90 shadow-xl backdrop-blur">
          <div class="card-body gap-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                  {humanize_source(@article)}
                </p>
                <h1 class="text-3xl font-bold text-base-content">{@article.title}</h1>
                <p class="mt-2 text-sm text-base-content/70">
                  Imported {format_timestamp(@article.inserted_at)}
                </p>
              </div>
              <span class="badge badge-lg badge-outline uppercase tracking-wide text-base-content/80">
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

        <article
          id="article-reader"
          class="card border border-base-200 bg-base-100/90 p-8 text-lg leading-relaxed text-base-content shadow-xl backdrop-blur"
        >
          <p :for={sentence <- @sentences} class="mb-4 last:mb-0">
            <span
              :for={token <- tokenize_sentence(sentence.content, sentence.word_occurrences || [])}
              data-word={token.lexical? && token.text}
              data-sentence-id={sentence.id}
              data-language={@article.language}
              data-word-id={token.word && token.word.id}
              phx-hook={token.lexical? && "WordTooltip"}
              id={"token-#{sentence.id}-#{token.id}"}
              class={[
                "inline",
                token.lexical? &&
                  [
                    "cursor-pointer rounded px-0.5 transition hover:bg-primary/10 hover:text-primary",
                    studied_token?(token, @studied_word_ids, @studied_forms) &&
                      "bg-primary/5 text-primary"
                  ]
              ]}
            >
              {token.text}
            </span>
          </p>
        </article>
      </div>
    </Layouts.app>
    """
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
    normalized = Vocabulary.normalize_form(word)
    sentence = Map.get(socket.assigns.sentence_lookup, sentence_id)
    context = if sentence, do: sentence.content, else: nil
    {:ok, entry} = Dictionary.lookup(word, language: language, target: "en")
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
        word: word,
        language: language,
        normalized_form: normalized,
        context: context,
        word_id: resolved_word && resolved_word.id,
        studied: studied?
      })

    {:noreply, push_event(socket, "word-data", payload)}
  end

  def handle_event(
        "add_to_study",
        %{"word_id" => word_id},
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, _item} <- Study.schedule_new_item(scope.user.id, word.id) do
      studied_word_ids = MapSet.put(socket.assigns.studied_word_ids, word.id)

      studied_forms =
        case normalized_form_from_word(word) do
          nil -> socket.assigns.studied_forms
          form -> MapSet.put(socket.assigns.studied_forms, form)
        end

      {:noreply,
       socket
       |> assign(:studied_word_ids, studied_word_ids)
       |> assign(:studied_forms, studied_forms)
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

    @token_regex
    |> Regex.scan(content)
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {text, idx} ->
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
          MapSet.member?(studied_forms, Vocabulary.normalize_form(token.text)) ->
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

    Vocabulary.get_or_create_word(%{
      normalized_form: normalized,
      language: language,
      lemma: lemma,
      part_of_speech: Map.get(entry, :part_of_speech) || Map.get(entry, "part_of_speech")
    })
  end

  defp resolve_word_record(word_id, _entry, _normalized, _language) do
    fetch_word(word_id)
  end

  defp normalized_form_from_word(nil), do: nil

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

    {ids, forms}
  end

  defp humanize_source(article) do
    article.source || URI.parse(article.url).host || "Article"
  end

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    datetime
    |> Calendar.strftime("%b %d, %Y at %H:%M %Z")
  end
end
