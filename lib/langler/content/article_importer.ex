defmodule Langler.Content.ArticleImporter do
  @moduledoc """
  Fetches remote articles and processes them for language learning.

  Extracts readable content using Readability, seeds sentences for vocabulary
  extraction, and enqueues background jobs for word occurrence tracking.
  """

  alias Langler.Accounts
  alias Langler.Content
  alias Langler.Content.Classifier
  alias Langler.Content.Readability
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
          case persist_article(user, normalized_url, html, parsed) do
            {:ok, article} ->
              enqueue_word_extraction(article)
              {:ok, article, :new}

            {:error, _} = error ->
              error
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
      |> Req.merge(req_options())

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
           length: if(html, do: String.length(html), else: nil)
         }}
    end
  end

  defp req_options do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :req_options, [])
  end

  defp persist_article(user, url, html, parsed) do
    sanitized_content = sanitize_content(parsed[:content] || parsed["content"] || "")

    Repo.transaction(fn ->
      with {:ok, article} <- create_article(parsed, html, url, user),
           {:ok, _} <- Content.ensure_article_user(article, user.id),
           :ok <- seed_sentences(article, sanitized_content),
           :ok <- classify_and_tag_article(article, sanitized_content) do
        # Preload article_topics before returning
        Repo.preload(article, :article_topics)
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

  @dialyzer {:nowarn_function, classify_and_tag_article: 2}
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
        # Preload article_topics before returning
        Repo.preload(article, :article_topics)
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

  @dialyzer {:nowarn_function, html_title: 1}
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
    # Content is already sanitized when passed from refresh_article or persist_article
    # Only sanitize if content contains HTML tags (fallback case)
    processed_content =
      if String.contains?(content, "<") do
        sanitize_content(content)
      else
        content
      end

    # Always normalize punctuation spacing after sanitization/processing
    processed_content =
      processed_content
      |> normalize_punctuation_spacing()

    processed_content
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
      # Plain text from NIF - decode entities, normalize whitespace, and fix punctuation spacing
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
        # Normalize invalid sequences to spaces to avoid raising
        String.replace_invalid(content, " ")
    end
  rescue
    ArgumentError ->
      # If content is not a binary, convert to string first
      content
      |> to_string()
      |> String.replace_invalid(" ")
  end

  defp ensure_utf8(content) when is_list(content) do
    content
    |> IO.iodata_to_binary()
    |> ensure_utf8()
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
    # Use character-by-character parser for comprehensive punctuation normalization
    normalize_punctuation_spacing(content)
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
    # Preload article_topics before returning
    Repo.preload(article, :article_topics)
  end

  defp enqueue_word_extraction(article) do
    %{article_id: article.id}
    |> ExtractWordsWorker.new()
    |> Oban.insert()
  end

  @doc """
  Normalizes punctuation spacing in text according to Spanish typography rules.

  Tokenizes text into words and punctuation, fixes spacing between tokens, then joins back.
  """
  def normalize_punctuation_spacing(content) when is_binary(content) do
    content
    |> String.replace("...", "…")
    |> tokenize_text()
    |> normalize_tokens()
    |> join_tokens()
  end

  def normalize_punctuation_spacing(content), do: to_string(content)

  # Tokenize text into: words (lemmas), punctuation, and spaces
  defp tokenize_text(text) do
    # Use graphemes to handle UTF-8 properly, then group into tokens
    text
    |> String.graphemes()
    |> Enum.chunk_while("", &chunk_into_token/2, &after_chunk/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp chunk_into_token(grapheme, acc) do
    # Ensure grapheme is valid UTF-8
    grapheme = if String.valid?(grapheme), do: grapheme, else: ""
    acc = if String.valid?(acc), do: acc, else: ""

    cond do
      # Letter - continue word token (only if acc is a word, not space/punct)
      String.match?(grapheme, ~r/^\p{L}$/u) ->
        if (acc != "" and String.match?(acc, ~r/^\p{L}+$/u)) or acc == "" do
          {:cont, acc <> grapheme}
        else
          # Acc is space or punct, emit it and start new word
          {:cont, acc, grapheme}
        end

      # Space - emit current token and start space token
      String.match?(grapheme, ~r/^\s$/u) ->
        if acc == "" do
          {:cont, grapheme}
        else
          {:cont, acc, grapheme}
        end

      # Punctuation - emit current token and start punctuation token
      true ->
        if acc == "" do
          {:cont, grapheme}
        else
          {:cont, acc, grapheme}
        end
    end
  end

  defp after_chunk(acc), do: {:cont, ensure_valid_string(acc), ""}

  # Ensure string is valid UTF-8, replace invalid bytes if needed
  defp ensure_valid_string(str) when is_binary(str) do
    if String.valid?(str) do
      str
    else
      # Replace invalid bytes with empty string or try to fix
      str
      |> String.codepoints()
      |> Enum.filter(&String.valid?/1)
      |> Enum.join("")
    end
  end

  defp ensure_valid_string(str), do: to_string(str)

  # Normalize spacing between tokens
  defp normalize_tokens(tokens) do
    # Process tokens with lookahead for straight quote handling
    tokens
    |> Enum.with_index()
    |> Enum.reduce([], fn {token, idx}, acc ->
      normalize_token_with_lookahead(token, acc, tokens, idx)
    end)
    |> Enum.reverse()
  end

  defp normalize_token_with_lookahead(token, acc, tokens, idx) do
    # Ensure token is valid UTF-8 before processing
    token = ensure_valid_string(token)
    # Get the next token for lookahead
    next_token = Enum.at(tokens, idx + 1)
    # Get second next token for better lookahead
    next_next_token = Enum.at(tokens, idx + 2)

    cond do
      # Space token - check if it should be removed
      String.match?(token, ~r/^\s+$/) ->
        case acc do
          [prev | _rest] ->
            # Remove space after opening punctuation/quotes/dashes
            if is_opening_punctuation_token?(prev) or is_opening_quote_token?(prev) or
                 is_dash_token?(prev) do
              acc
            else
              # For straight quotes, check if next token is a word (opening context)
              if is_straight_quote_token?(prev) and next_token != nil and
                   is_word_token?(next_token) do
                # Quote followed by word = opening quote, remove space after
                acc
              else
                # Keep space - it will be checked when next token is processed
                [token | acc]
              end
            end

          # Empty acc - keep space
          _ ->
            [token | acc]
        end

      # Punctuation token - check spacing rules
      is_punctuation_token?(token) ->
        case acc do
          [space | rest] when is_binary(space) ->
            if String.match?(space, ~r/^\s+$/) do
              # Previous token is a space
              # Remove space before closing punctuation, closing quotes, or dashes
              if is_closing_punctuation_token?(token) or is_closing_quote_token?(token) or
                   is_dash_token?(token) do
                [token | rest]
              else
                # For straight quotes, use lookahead to determine if opening or closing
                if is_straight_quote_token?(token) do
                  # If next token is space and then word, it's opening (keep space before)
                  # If next token is space and then punctuation, it's closing (remove space before)
                  cond do
                    # " word -> opening quote, keep space before
                    next_token != nil and is_word_token?(next_token) ->
                      [token | acc]

                    # " . or " , -> closing quote, remove space before  
                    next_token != nil and String.match?(next_token, ~r/^\s+$/) and
                      next_next_token != nil and is_punctuation_token?(next_next_token) ->
                      [token | rest]

                    # " followed by space and word -> opening, keep space before
                    next_token != nil and String.match?(next_token, ~r/^\s+$/) and
                      next_next_token != nil and is_word_token?(next_next_token) ->
                      [token | acc]

                    # Default: keep space (safer for opening quotes)
                    true ->
                      [token | acc]
                  end
                else
                  # Keep space before opening punctuation/quotes (e.g., 'said "hello"')
                  [token | acc]
                end
              end
            else
              # Previous token is not a space
              # Add space after closing punctuation if followed by word (if no space exists)
              if is_closing_punctuation_token?(space) and is_word_token?(token) do
                [token, " " | rest]
              else
                [token | acc]
              end
            end

          # Normal case
          _ ->
            [token | acc]
        end

      # Word token - handle spacing rules
      is_word_token?(token) ->
        case acc do
          # Add space after closing punctuation if no space exists
          [prev | rest] ->
            if is_closing_punctuation_token?(prev) do
              # Keep the punctuation token, add space, then word
              [token, " ", prev | rest]
              # Check if word follows opening quote - no space needed
            else
              if is_opening_quote_token?(prev) or is_opening_punctuation_token?(prev) do
                # Word follows opening quote/punct, no space
                [token | acc]
                # Check if there's a space before an opening quote that should be preserved
              else
                if String.match?(prev, ~r/^\s+$/) do
                  case rest do
                    [punct | rest2] ->
                      if is_opening_punctuation_token?(punct) or is_opening_quote_token?(punct) do
                        # Space is before opening quote, preserve it
                        [token, prev, punct | rest2]
                      else
                        [token | acc]
                      end

                    _ ->
                      [token | acc]
                  end
                else
                  [token | acc]
                end
              end
            end

          _ ->
            [token | acc]
        end

      # Other tokens - keep as is
      true ->
        [token | acc]
    end
  end

  # Join tokens back together - just concatenate, spacing is already normalized
  defp join_tokens(tokens) do
    Enum.join(tokens, "")
  end

  defp is_word_token?(token), do: String.match?(token, ~r/^\p{L}+/u)

  defp is_punctuation_token?(token) do
    # Check if token is not a word (letters) and not a space
    # This includes punctuation, dashes, quotes, etc.
    not String.match?(token, ~r/^\p{L}+/u) and not String.match?(token, ~r/^\s+$/u)
  end

  defp is_closing_punctuation_token?(token) do
    closing_punct = ~r/^[,\.;:!\?\)\]\}\»\›…]+$/
    String.match?(token, closing_punct)
  end

  defp is_opening_punctuation_token?(token) do
    opening_punct = ~r/^[\(\[\{\«\‹¡¿]+$/
    String.match?(token, opening_punct)
  end

  defp is_closing_quote_token?(token) do
    # Match ONLY unambiguous closing quotes: ", », ›
    # U+201D (right double quotation mark)
    smart_quote_close = <<226, 128, 157>>

    # Note: straight quotes " and ' are ambiguous - handled separately
    is_punctuation_token?(token) and
      (token == smart_quote_close or
         String.contains?(token, "»") or
         String.contains?(token, "›"))
  end

  defp is_opening_quote_token?(token) do
    # Match ONLY unambiguous opening quotes: ", «, ‹
    # U+201C (left double quotation mark)
    smart_quote_open = <<226, 128, 156>>

    # Note: straight quotes " and ' are ambiguous - handled separately
    is_punctuation_token?(token) and
      (token == smart_quote_open or
         String.contains?(token, "«") or
         String.contains?(token, "‹"))
  end

  # Straight quotes are ambiguous - we keep space before them
  # because if there's a space, it's likely an opening quote
  defp is_straight_quote_token?(token) do
    token == "\"" or token == "'"
  end

  # Em dashes, en dashes, and minus signs should have no spaces around them
  defp is_dash_token?(token) do
    # U+2014 EM DASH, U+2013 EN DASH, U+2212 MINUS SIGN, U+002D HYPHEN-MINUS
    String.contains?(token, "—") or
      String.contains?(token, "–") or
      String.contains?(token, "−") or
      (String.contains?(token, "-") and String.length(token) == 1)
  end
end
