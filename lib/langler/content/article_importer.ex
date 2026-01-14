defmodule Langler.Content.ArticleImporter do
  @moduledoc """
  Fetches remote articles, extracts readable content, and seeds sentences + background jobs.
  """

  @dialyzer {:nowarn_function, remove_spaces_before_punctuation: 1}

  alias Langler.Accounts
  alias Langler.Content
  alias Langler.Content.Readability
  alias Langler.Content.Classifier
  alias Langler.Content.Workers.ExtractWordsWorker
  alias Langler.Repo
  alias Oban

  import Ecto.Query, warn: false
  require Logger

  @type import_result :: {:ok, Content.Article.t(), :new | :existing} | {:error, term()}

  @spec import_from_url(Accounts.User.t(), String.t()) :: import_result
  def import_from_url(%Accounts.User{} = user, url) when is_binary(url) do
    with {:ok, normalized_url} <- normalize_url(url),
         {:ok, html} <- fetch_html(normalized_url),
         {:ok, parsed} <- parse_article_html(html, normalized_url) do
      case Content.get_article_by_url(normalized_url) do
        %Content.Article{} = article ->
          case refresh_article(article, user, normalized_url, html, parsed) do
            {:ok, refreshed} ->
              enqueue_word_extraction(refreshed)
              {:ok, refreshed, :existing}

            {:error, reason} ->
              Logger.warning("Article refresh failed: #{inspect(reason)}")
              {:ok, ensure_association(article, user), :existing}
          end

        nil ->
          with {:ok, article} <- persist_article(user, normalized_url, html, parsed) do
            enqueue_word_extraction(article)
            {:ok, article, :new}
          else
            {:error, _} = error -> error
          end
      end
    end
  end

  def import_from_url(_, _), do: {:error, :invalid_user}

  defp normalize_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme} = uri} when scheme in ["http", "https"] ->
        {:ok, URI.to_string(uri)}

      {:ok, _} ->
        {:error, :invalid_scheme}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_html(url) do
    req =
      Req.new(
        url: url,
        method: :get,
        redirect: :follow,
        headers: [{"user-agent", "LanglerBot/0.1"}],
        receive_timeout: 10_000
      )

    case Req.get(req) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_article_html(html, url) do
    case Readability.parse(html, base_url: url) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        Logger.warning(
          "ArticleImporter: Readability parse failed for #{url}: #{inspect(reason)}. Falling back to raw HTML."
        )

        {:ok,
         %{
           title: html_title(html),
           content: html,
           excerpt: nil,
           author: nil,
           length: html && String.length(html)
         }}
    end
  end

  defp persist_article(user, url, html, parsed) do
    sanitized_content = sanitize_content(parsed[:content] || parsed["content"] || "")

    Repo.transaction(fn ->
      with {:ok, article} <- create_article(parsed, html, url, user),
           {:ok, _} <- Content.ensure_article_user(article, user.id),
           :ok <- seed_sentences(article, sanitized_content),
           :ok <- classify_and_tag_article(article, sanitized_content) do
        article
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp classify_and_tag_article(article, content) when is_binary(content) do
    language = article.language
    topics = Classifier.classify(content, language)
    Content.tag_article(article, topics)
  end

  defp classify_and_tag_article(_article, _), do: :ok

  defp refresh_article(article, user, url, html, parsed) do
    sanitized_content = sanitize_content(parsed[:content] || parsed["content"] || "")

    Repo.transaction(fn ->
      attrs = %{
        title: derive_title(parsed, html, url),
        source: URI.parse(url).host,
        content: sanitized_content,
        extracted_at: DateTime.utc_now()
      }

      with {:ok, article} <- Content.update_article(article, attrs),
           _ <-
             Repo.delete_all(
               from s in Langler.Content.Sentence, where: s.article_id == ^article.id
             ),
           :ok <- seed_sentences(article, sanitized_content),
           {:ok, _} <- Content.ensure_article_user(article, user.id, %{status: "imported"}),
           :ok <- classify_and_tag_article(article, sanitized_content) do
        article
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp derive_title(parsed, html, url) do
    raw_title = parsed[:title] || parsed["title"] || html_title(html) || url

    processed =
      raw_title
      |> strip_tags()
      |> decode_html_entities()
      |> String.trim()

    if processed == "", do: url, else: processed
  end

  defp html_title(html) when is_binary(html) do
    with {:ok, document} <- Floki.parse_document(html),
         [title | _] <- Floki.find(document, "title") do
      title
      |> Floki.text()
      |> String.trim()
    else
      _ -> nil
    end
  end

  defp html_title(_), do: nil

  defp create_article(parsed, html, url, user) do
    language = user_language(user)
    source = URI.parse(url).host
    content = sanitize_content(parsed[:content] || parsed["content"] || "")

    Content.create_article(%{
      title: derive_title(parsed, html, url),
      url: url,
      source: source,
      language: language,
      content: content,
      extracted_at: DateTime.utc_now()
    })
  end

  defp user_language(user) do
    case Accounts.get_user_preference(user.id) do
      nil -> "spanish"
      pref -> pref.target_language
    end
  end

  defp seed_sentences(article, content) when is_binary(content) do
    content
    |> sanitize_content()
    |> split_sentences()
    |> Enum.map(&remove_noise_prefix/1)
    |> filter_noise_sentences()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {sentence, idx}, _ ->
      case Content.create_sentence(%{
             article_id: article.id,
             content: sentence,
             position: idx
           }) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp remove_noise_prefix(sentence) do
    # Remove navigation noise that appears at the start of sentences
    # Specifically target the pattern: "Ir al contenido ____ Seleccione...EspañaAmérica...Consulte la portada"

    # Pattern 1: Remove everything from "Ir al contenido" up to (but not including) "Consulte la portada"
    sentence =
      Regex.replace(
        ~r/^(?i)ir\s+al\s+contenido[^.]*?(?=consulte\s+la\s+portada)/i,
        sentence,
        ""
      )

    # Pattern 2: Remove concatenated country names at the start
    sentence =
      Regex.replace(
        ~r/^(?i)(españa|américa|méxico|colombia|chile|argentina)(españa|américa|méxico|colombia|chile|argentina)+(us\s+español|us\s+english)?(?=\s+[A-Z])/i,
        sentence,
        ""
      )

    # Pattern 3: Remove "Seleccione :- - -" patterns at the start
    sentence =
      Regex.replace(
        ~r/^(?i)seleccione\s*:?\s*-+\s*(?=\s*[A-Z])/i,
        sentence,
        ""
      )

    # Pattern 4: Remove "Ciencia / Materia" and subject categories at the start
    sentence =
      Regex.replace(
        ~r/^(?i)(ciencia\s*\/\s*materia|astrofísica|medio\s+ambiente|investigaci[oó]n\s+médica|matemáticas|paleontología|avance)\s*(?=\s*[A-Z])/i,
        sentence,
        ""
      )

    # Pattern 5: Remove "uscríbeteHHOLAIniciar sesión" at the start
    sentence =
      Regex.replace(
        ~r/^(?i)uscr[ií]bete\s*HHOLA\s*iniciar\s+sesi[oó]n\s*(?=\s*[A-Z])/i,
        sentence,
        ""
      )

    String.trim(sentence)
  end

  defp filter_noise_sentences(sentences) do
    sentences
    |> Enum.reject(&noise_sentence?/1)
  end

  defp noise_sentence?(sentence) do
    trimmed = String.trim(sentence)

    [
      &short_sentence?/1,
      &punctuation_only?/1,
      &navigation_caps?/1,
      &special_char_runs?/1,
      &navigation_phrase?/1,
      &region_listing?/1,
      &subject_category?/1,
      &has_high_noise_ratio?/1
    ]
    |> Enum.any?(fn predicate -> predicate.(trimmed) end)
  end

  defp short_sentence?(sentence), do: String.length(sentence) < 10

  defp punctuation_only?(sentence), do: Regex.match?(~r/^[^\p{L}]+$/, sentence)

  defp navigation_caps?(sentence) do
    Regex.match?(~r/^[A-Z\s|\/\\-]+$/, sentence) and String.length(sentence) < 50
  end

  defp special_char_runs?(sentence), do: Regex.match?(~r/[|\/\\-_]{3,}/, sentence)

  defp navigation_phrase?(sentence) do
    Regex.match?(
      ~r/^(?i)(ir\s+al\s+contenido|seleccione|uscr[ií]bete|iniciar\s+sesi[oó]n|ciencia\s*\/\s*materia|avance)$/,
      sentence
    )
  end

  defp region_listing?(sentence) do
    Regex.match?(
      ~r/^(?i)(españa|américa|méxico|colombia|chile|argentina|us\s+español|us\s+english)(\s*[|\/\\-]\s*(españa|américa|méxico|colombia|chile|argentina|us\s+español|us\s+english))*$/,
      sentence
    )
  end

  defp subject_category?(sentence) do
    Regex.match?(
      ~r/^(?i)(astrofísica|medio\s+ambiente|investigaci[oó]n\s+médica|matemáticas|paleontología)(\s*[|\/\\-]\s*(astrofísica|medio\s+ambiente|investigaci[oó]n\s+médica|matemáticas|paleontología))*$/,
      sentence
    )
  end

  defp has_high_noise_ratio?(sentence) do
    # Count navigation words vs total words
    navigation_words = [
      "ir",
      "al",
      "contenido",
      "seleccione",
      "uscríbete",
      "uscribe",
      "iniciar",
      "sesión",
      "hola",
      "ciencia",
      "materia",
      "españa",
      "américa",
      "méxico",
      "colombia",
      "chile",
      "argentina",
      "español",
      "english",
      "astrofísica",
      "medio",
      "ambiente",
      "investigación",
      "médica",
      "matemáticas",
      "paleontología",
      "avance",
      "consulte",
      "portada",
      "edición",
      "nacional"
    ]

    words = String.split(sentence, ~r/\s+/, trim: true)
    total_words = length(words)

    if total_words == 0 do
      false
    else
      navigation_count =
        words
        |> Enum.count(fn word ->
          normalized = String.downcase(String.trim(word, ".,;:!?"))
          Enum.any?(navigation_words, &String.contains?(normalized, &1))
        end)

      # If more than 50% of words are navigation words, it's likely noise
      navigation_count > total_words / 2 and total_words < 20
    end
  end

  defp sanitize_content(nil), do: ""

  defp sanitize_content(content) do
    content = ensure_utf8(content)

    # If content is already plain text (from NIF paragraph extraction),
    # we only need minimal processing
    if String.contains?(content, "<") do
      # Still has HTML tags - fallback case or raw HTML
      require Logger

      Logger.warning(
        "[ArticleImporter] Content contains HTML tags, using full sanitization (fallback mode?)"
      )

      content
      |> String.replace(~r/<head[\s\S]*?<\/head>/im, "")
      |> String.replace(~r/<(script|style|nav|header|footer|aside)[\s\S]*?>[\s\S]*?<\/\1>/im, "")
      |> strip_tags()
      |> decode_html_entities()
      |> remove_navigation_noise()
      |> String.replace(~r/\s+/, " ")
      |> fix_punctuation_spacing()
      |> String.trim()
    else
      # Plain text from NIF - just decode entities and normalize whitespace
      require Logger

      Logger.info(
        "[ArticleImporter] Content is plain text (from NIF paragraph extraction), using minimal processing"
      )

      content
      |> decode_html_entities()
      |> String.replace(~r/\s+/, " ")
      |> fix_punctuation_spacing()
      |> String.trim()
    end
  end

  defp ensure_utf8(content) when is_binary(content) do
    case String.valid?(content) do
      true ->
        content

      false ->
        :unicode.characters_to_binary(content, :utf8, {:replace, <<32>>})
    end
  rescue
    ArgumentError ->
      :unicode.characters_to_binary(to_string(content), :utf8, {:replace, <<32>>})
  end

  defp ensure_utf8(_), do: ""

  defp strip_tags(content) do
    Regex.replace(~r/<[^>]*>/, content, "")
  end

  defp decode_html_entities(content) do
    content
    |> String.replace(~r/&#x27;/i, "'")
    |> String.replace(~r/&#39;/i, "'")
    |> String.replace(~r/&apos;/i, "'")
    |> String.replace(~r/&quot;/i, "\"")
    |> String.replace(~r/&amp;/i, "&")
    |> String.replace(~r/&lt;/i, "<")
    |> String.replace(~r/&gt;/i, ">")
    |> String.replace(~r/&nbsp;/i, " ")
    |> decode_numeric_entities()
  end

  defp fix_punctuation_spacing(content) do
    # Remove spaces before punctuation and ensure proper spacing after
    content
    |> remove_spaces_before_punctuation()
    |> ensure_space_after_punctuation()
    |> ensure_space_after_inverted_marks()
    |> squeeze_whitespace()
  end

  defp decode_numeric_entities(content) do
    # Decode hex entities like &#x27;
    content =
      Regex.replace(~r/&#x([0-9a-fA-F]+);/i, content, fn _match, captures ->
        hex = if is_list(captures), do: List.first(captures), else: captures

        case Integer.parse(hex, 16) do
          {code, _} when code in 0..0x10FFFF -> <<code::utf8>>
          _ -> ""
        end
      end)

    # Decode decimal entities like &#39;
    Regex.replace(~r/&#(\d+);/i, content, fn _match, captures ->
      dec = if is_list(captures), do: List.first(captures), else: captures

      case Integer.parse(dec) do
        {code, _} when code in 0..0x10FFFF -> <<code::utf8>>
        _ -> ""
      end
    end)
  end

  defp remove_navigation_noise(content) do
    # First, split on known noise patterns to separate them from content
    content = split_on_noise_patterns(content)

    # Common navigation/menu patterns to remove
    noise_patterns = [
      # Menu items with separators
      ~r/[A-Za-z]+\s*[|\/\\]\s*[A-Za-z]+/,
      # Repeated dashes/underscores (often used as separators)
      ~r/_{3,}/,
      ~r/-{3,}/,
      # Common navigation phrases (with word boundaries to catch standalone instances)
      ~r/(?i)\b(ir\s+al\s+contenido|seleccione|uscr[ií]bete|iniciar\s+sesi[oó]n|ciencia\s*\/\s*materia)\b/,
      # Country/region lists (concatenated or with separators)
      ~r/(?i)(españa|américa|méxico|colombia|chile|argentina|us\s+español|us\s+english)(\s*[|\/\\-]\s*|\s*)(españa|américa|méxico|colombia|chile|argentina|us\s+español|us\s+english)*/,
      # Concatenated country names (no spaces)
      ~r/(?i)(españa|américa|méxico|colombia|chile|argentina)(españa|américa|méxico|colombia|chile|argentina)+/,
      # Subject/menu categories
      ~r/(?i)\b(astrofísica|medio\s+ambiente|investigaci[oó]n\s+médica|matemáticas|paleontología|avance)\b/,
      # Short isolated words that are likely navigation
      ~r/\b(?:HHOLA|HH|____)\b/,
      # Patterns like "Seleccione :- - -" or "Seleccione : - -"
      ~r/(?i)seleccione\s*:?\s*-+\s*/,
      # "Ir al contenido" followed by underscores or dashes
      ~r/(?i)ir\s+al\s+contenido\s*_{2,}\s*/,
      ~r/(?i)ir\s+al\s+contenido\s*-{2,}\s*/,
      # "Ciencia / Materia" patterns
      ~r/(?i)ciencia\s*\/\s*materia/,
      # "US Español" or "US English" patterns
      ~r/(?i)us\s+(español|english)/
    ]

    Enum.reduce(noise_patterns, content, fn pattern, acc ->
      Regex.replace(pattern, acc, " ")
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp split_on_noise_patterns(content) do
    # Split on patterns that indicate navigation boundaries
    # This helps separate noise from actual content
    split_patterns = [
      # Split before "Consulte la portada" or similar actual content markers
      ~r/(?=Consulte\s+la\s+portada)/i
    ]

    Enum.reduce(split_patterns, content, fn pattern, acc ->
      String.split(acc, pattern)
      |> Enum.join(" ")
    end)
  end

  defp split_sentences(content) do
    content
    |> String.trim()
    |> String.split(~r/(?<=[\.!\?])\s+/, trim: true)
  end

  defp ensure_association(article, user) do
    {:ok, _} = Content.ensure_article_user(article, user.id)
    article
  end

  defp enqueue_word_extraction(article) do
    %{article_id: article.id}
    |> ExtractWordsWorker.new()
    |> Oban.insert()
  end

  @spec remove_spaces_before_punctuation(String.t()) :: String.t()
  defp remove_spaces_before_punctuation(content) when is_binary(content) do
    step1 = String.replace(content, ~r/\s+([,\.;:!?\)\]\}])/u, "\\1")
    step2 = String.replace(step1, ~r/\s+([¡¿])/u, "\\1")
    String.replace(step2, ~r/([\(\[\{])\s+/u, "\\1")
  end

  defp remove_spaces_before_punctuation(content), do: to_string(content)

  defp ensure_space_after_punctuation(content) do
    Regex.replace(~r/([,\.;:!?])([^\s,\.;:!?\)\]\}]|$)/u, content, "\\1 \\2")
  end

  defp ensure_space_after_inverted_marks(content) do
    Regex.replace(~r/([¡¿])([^\s])/u, content, "\\1 \\2")
  end

  defp squeeze_whitespace(content) do
    String.replace(content, ~r/\s+/u, " ")
  end
end
