defmodule Langler.Gettext.Seed do
  @moduledoc """
  Seeds Gettext .po files by translating source strings from the .pot template
  using an LLM. Used by `mix langler.gettext.seed`.
  """

  alias Langler.Languages
  alias Langler.LLM.Adapters.ChatGPT

  @doc """
  Parses a .pot file and returns a list of entries.

  Each entry is `%{comments: [String.t()], msgid: String.t()}`.
  Skips the header entry (empty msgid).
  """
  def parse_pot(path) when is_binary(path) do
    path
    |> File.read!()
    |> parse_pot_content()
  end

  @doc """
  Translates a list of source strings from English to the target locale using the LLM.

  Returns `{:ok, %{msgid => msgstr}}` or `{:error, reason}`.
  Preserves placeholders like `%{source}` in translations.
  """
  def translate_strings(config, strings, target_locale) when is_list(strings) do
    if strings == [] do
      {:ok, %{}}
    else
      target_language = locale_to_language_name(target_locale)
      prompt = build_translation_prompt(strings, target_language)
      messages = [%{role: "user", content: prompt}]

      case ChatGPT.chat(messages, config) do
        {:ok, %{content: content}} ->
          parse_translations_response(content, strings)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Loads existing msgid => msgstr from a .po file. Returns %{} if file missing.
  """
  def load_existing_po(path) when is_binary(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> parse_po_existing()
    else
      %{}
    end
  end

  @doc """
  Writes a .po file for the given locale, merging in translations.

  - `path`: path to the .po file (e.g. `priv/gettext/es/LC_MESSAGES/default.po`)
  - `entries`: list from `parse_pot/1`
  - `translations`: map of msgid => msgstr from `translate_strings/3`
  - `opts`: `[force: boolean]` — if false, existing non-empty msgstr from file are kept
  """
  def write_po(path, entries, translations, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    existing = if force, do: %{}, else: load_existing_po(path)

    merged =
      Enum.reduce(entries, %{}, fn %{msgid: msgid}, acc ->
        existing_str = Map.get(existing, msgid)
        new_str = Map.get(translations, msgid)

        str =
          if force or existing_str in [nil, ""] do
            new_str || existing_str || ""
          else
            existing_str || new_str || ""
          end

        Map.put(acc, msgid, str)
      end)

    locale = locale_from_po_path(path)
    header = po_header(locale)

    body = Enum.map_join(entries, "\n\n", &po_entry(&1, merged))

    content = header <> "\n\n" <> body <> "\n"
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    :ok
  end

  @doc """
  Returns the gettext priv path (absolute).
  """
  def gettext_priv_path do
    Application.app_dir(:langler, "priv/gettext")
  end

  # --- Parsing ---

  defp parse_pot_content(content) do
    content
    |> String.split(~r/\n(?=#:|\n\n|\z)/, include_captures: false)
    |> Enum.flat_map(&parse_block/1)
    |> Enum.reject(&(&1.msgid == ""))
  end

  defp parse_block(block) do
    block = String.trim(block)

    if block == "" or not String.contains?(block, "msgid ") do
      []
    else
      comments =
        block
        |> String.split("\n")
        |> Enum.take_while(
          &(String.starts_with?(&1, "#") and not String.starts_with?(&1, "msgid"))
        )
        |> Enum.map(&String.trim_trailing/1)

      msgid = extract_value(block, "msgid")
      [%{comments: comments, msgid: msgid}]
    end
  end

  defp extract_value(block, key) do
    key_pattern = ~r/^#{Regex.escape(key)}\s+"(.*)"/m
    multiline = ~r/^#{Regex.escape(key)}\s+""\n"(.*)"/ms

    cond do
      Regex.match?(multiline, block) ->
        [_, inner] = Regex.run(multiline, block)

        inner
        |> String.split(~r/\n"/)
        |> Enum.map_join("\n", fn s -> String.replace(s, ~r/^"/, "") |> unescape_po() end)

      Regex.match?(key_pattern, block) ->
        [_, single] = Regex.run(key_pattern, block)
        unescape_po(single)

      true ->
        ""
    end
  end

  defp unescape_po(s) do
    s
    |> String.replace(~r/\\n/, "\n")
    |> String.replace(~r/\\t/, "\t")
    |> String.replace(~r/\\"/, "\"")
    |> String.replace(~r/\\\\/, "\\")
  end

  defp escape_po(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
  end

  # --- Translation ---

  defp build_translation_prompt(strings, target_language) do
    numbered =
      strings
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {s, i} -> "#{i}. #{s}" end)

    """
    You are a professional UI translator. Translate the following English UI strings into #{target_language}.

    Application context: These strings are from Langler, a language-learning app. Users read articles in their target language, build vocabulary, study with spaced repetition (flashcards), and can chat with an AI for practice. The UI covers: onboarding, settings (account, AI/LLM, TTS, Google Translate), library (importing articles, recommendations), study (decks, due cards, filters), and general navigation (log in, theme, etc.). Use clear, friendly UI language appropriate for learners.

    Rules:
    - Keep placeholders exactly as-is, e.g. %{source}, %{name}. Do not translate or change them.
    - Return ONLY a JSON object: keys are the line numbers (1, 2, 3, ...), values are the translations.
    - No explanations, no markdown code fence, just the JSON object.
    - Preserve tone (formal/informal) appropriate for UI in #{target_language}.

    Strings:
    #{numbered}
    """
  end

  defp parse_translations_response(content, strings) do
    json_str = extract_json_object(content)

    case Jason.decode(json_str) do
      {:ok, map} when is_map(map) -> {:ok, build_translations_map(map, strings)}
      _ -> {:error, :invalid_json_response}
    end
  end

  # Extract first {...} from response; handles markdown code blocks and leading/trailing text
  defp extract_json_object(content) do
    trimmed = String.trim(content)

    trimmed =
      trimmed
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```\s*$/i, "")
      |> String.trim()

    case :binary.match(trimmed, "{") do
      {start, _len} -> slice_balanced_brace(trimmed, start)
      :nomatch -> trimmed
    end
  end

  # From first "{", find matching "}" while skipping "..."
  defp slice_balanced_brace(str, start) do
    len = String.length(str)

    case find_balanced_end(str, start + 1, len, 1) do
      nil -> str
      last -> String.slice(str, start..last)
    end
  end

  defp find_balanced_end(str, i, len, depth) when i < len do
    c = String.at(str, i)

    cond do
      c == "{" -> find_balanced_end(str, i + 1, len, depth + 1)
      c == "}" -> if depth == 1, do: i, else: find_balanced_end(str, i + 1, len, depth - 1)
      c == "\"" -> find_balanced_end(str, skip_quoted(str, i + 1, len), len, depth)
      true -> find_balanced_end(str, i + 1, len, depth)
    end
  end

  defp find_balanced_end(_str, _i, _len, _depth), do: nil

  defp skip_quoted(str, i, len) when i < len do
    c = String.at(str, i)

    if c == "\\",
      do: skip_quoted(str, i + 2, len),
      else: if(c == "\"", do: i + 1, else: skip_quoted(str, i + 1, len))
  end

  defp skip_quoted(_str, i, _len), do: i

  defp build_translations_map(map, strings) do
    # Normalize keys: API may return "1", 1, or other; we need string keys for lookup
    map_normalized =
      Map.new(map, fn
        {k, v} when is_integer(k) -> {to_string(k), v}
        {k, v} when is_binary(k) -> {k, v}
      end)

    strings
    |> Enum.with_index(1)
    |> Map.new(fn {msgid, i} ->
      key = to_string(i)
      str = Map.get(map_normalized, key) || Map.get(map, i) || msgid
      str = if is_binary(str), do: str, else: msgid
      {msgid, str}
    end)
  end

  defp locale_to_language_name(locale) do
    # Map gettext locale to language code for prompt
    code =
      case locale do
        "pt_BR" -> "pt-BR"
        "pt_PT" -> "pt-PT"
        other -> other
      end

    case Languages.supported?(code) do
      true -> Languages.native_name(code)
      false -> locale
    end
  end

  # --- Writing .po ---

  defp po_header(locale) do
    lang = locale_to_language_name(locale)
    plural = "nplurals=2; plural=(n != 1);"

    """
    ## Translations for #{lang} (#{locale}).
    msgid ""
    msgstr ""
    "Language: #{locale}\\n"
    "Plural-Forms: #{plural}\\n"
    """
  end

  defp po_entry(%{comments: comments, msgid: msgid}, translations) do
    msgstr = Map.get(translations, msgid) || ""

    comment_block = Enum.join(comments, "\n")

    """
    #{comment_block}
    msgid "#{escape_po(msgid)}"
    msgstr "#{escape_po(msgstr)}"
    """
  end

  defp parse_po_existing(content) do
    content
    |> String.split(~r/\n(?=#:|\n\n|\z)/, include_captures: false)
    |> Enum.reduce(%{}, &parse_po_block_to_map/2)
  end

  defp parse_po_block_to_map(block, acc) do
    block = String.trim(block)

    has_both =
      block != "" and String.contains?(block, "msgid ") and String.contains?(block, "msgstr ")

    if has_both do
      msgid = extract_value(block, "msgid")
      if msgid != "", do: Map.put(acc, msgid, extract_value(block, "msgstr")), else: acc
    else
      acc
    end
  end

  defp locale_from_po_path(path) do
    path
    |> Path.split()
    |> Enum.at(-3, "en")
  end
end
