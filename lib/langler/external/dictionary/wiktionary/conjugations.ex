defmodule Langler.External.Dictionary.Wiktionary.Conjugations do
  @moduledoc """
  Scrapes Spanish verb conjugation tables from Wiktionary.

  Extracts verb conjugations including present, past, future tenses and
  non-finite forms (infinitive, gerund, past participle) for language learning.
  """

  alias Langler.External.Dictionary.Cache

  @base_url "https://en.wiktionary.org/wiki"

  @doc """
  Fetches verb conjugations from Wiktionary for a given lemma.

  Returns {:ok, conjugations_map} where conjugations_map follows Wiktionary structure:
  %{
    "indicative" => %{
      "present" => %{"yo" => "hablo", "tú" => "hablas", ...},
      "preterite" => %{...},
      ...
    },
    "subjunctive" => %{...},
    "imperative" => %{...},
    "non_finite" => %{"infinitive" => "hablar", "gerund" => "hablando", "past_participle" => "hablado"}
  }
  """
  @spec fetch_conjugations(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_conjugations(lemma, language) when is_binary(lemma) and is_binary(language) do
    normalized_language = String.downcase(language)
    cache_key = {normalized_language, String.downcase(lemma)}
    table = cache_table()

    Cache.get_or_store(table, cache_key, [ttl: ttl()], fn ->
      fetch_and_parse_conjugations(lemma, normalized_language)
    end)
  end

  defp fetch_and_parse_conjugations(lemma, normalized_language) do
    with {:ok, body, _url} <- fetch_page(lemma, normalized_language),
         {:ok, doc} <- Floki.parse_document(body),
         conjugations <- parse_conjugations(doc, normalized_language) do
      if map_size(conjugations) > 0 do
        {:ok, conjugations}
      else
        log_conjugation_not_found(lemma, doc, normalized_language)
        {:error, :not_found}
      end
    end
  end

  defp log_conjugation_not_found(lemma, doc, normalized_language) do
    require Logger
    language_section = find_language_section(doc, normalized_language)
    tables_count = count_tables_in_section(language_section)
    section_status = if language_section, do: "found", else: "not found"

    Logger.warning(
      "Wiktionary conjugations: no conjugations found for #{lemma}. Language section: #{section_status}, Tables: #{tables_count}"
    )
  end

  defp count_tables_in_section(nil), do: 0

  defp count_tables_in_section(language_section) do
    language_section
    |> Enum.flat_map(fn node -> Floki.find(node, "table") end)
    |> length()
  end

  defp fetch_page(lemma, language) do
    url = build_url(lemma, language)

    case Req.get(url: url, headers: default_headers(), retry: false) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body, url}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(lemma, language) do
    encoded_lemma = URI.encode(lemma)
    anchor = language_anchor(language)
    "#{@base_url}/#{encoded_lemma}##{anchor}"
  end

  defp language_anchor("spanish"), do: "Spanish"
  defp language_anchor("french"), do: "French"
  defp language_anchor("portuguese"), do: "Portuguese"
  defp language_anchor("italian"), do: "Italian"
  defp language_anchor(_), do: "Spanish"

  defp default_headers do
    [
      {"user-agent", "LanglerBot/0.1 (+https://langler.local)"}
    ]
  end

  defp parse_conjugations(doc, language) do
    # Try multiple strategies to find conjugation tables
    # Strategy 1: Find language section and look for tables there
    language_section = find_language_section(doc, language)

    # Strategy 2: Look for tables with Spanish conjugation patterns anywhere in the page
    # Wiktionary Spanish verb pages often have tables with class "inflection-table" or "wikitable"
    # and they contain Spanish person pronouns (yo, tú, él, etc.)
    all_tables = Floki.find(doc, "table.inflection-table, table.wikitable, table")

    # Filter tables that look like Spanish conjugation tables
    conjugation_tables =
      all_tables
      |> Enum.filter(fn table ->
        # Check if table contains Spanish person pronouns
        table_text = Floki.text(table) |> String.downcase()
        String.contains?(table_text, "yo") && String.contains?(table_text, "tú")
      end)

    if conjugation_tables != [] do
      conjugations = %{}

      # Parse all conjugation tables
      conjugations =
        conjugation_tables
        |> Enum.reduce(conjugations, fn table, acc ->
          parse_conjugation_table(table, acc)
        end)

      # Extract non-finite forms from the language section if available, or from the whole doc
      section_to_search = language_section || [doc]
      extract_non_finite(conjugations, section_to_search)
    else
      %{}
    end
  end

  defp find_language_section(doc, language) do
    anchor = language_anchor(language)

    doc
    |> Floki.find("#mw-content-text .mw-parser-output")
    |> List.first()
    |> case do
      nil ->
        nil

      {_tag, _attrs, children} ->
        take_language_section(children, anchor)
    end
  end

  defp take_language_section(children, anchor) do
    {found, acc} =
      Enum.reduce_while(children, {false, []}, fn node, {found, acc} ->
        cond do
          language_heading?(node, anchor) ->
            {:cont, {true, []}}

          found && heading?(node) ->
            {:halt, {found, acc}}

          found ->
            {:cont, {found, [node | acc]}}

          true ->
            {:cont, {found, acc}}
        end
      end)

    case {found, acc} do
      {false, _} -> nil
      {_found, acc} -> Enum.reverse(acc)
    end
  end

  defp language_heading?({"h2", _attrs, children}, anchor) do
    Enum.any?(children, fn
      {"span", span_attrs, _} ->
        id =
          Enum.find_value(span_attrs, fn
            {"id", value} -> value
            _ -> nil
          end)

        class =
          Enum.find_value(span_attrs, fn
            {"class", value} -> value
            _ -> nil
          end)

        id == anchor && String.contains?(class || "", "mw-headline")

      _ ->
        false
    end)
  end

  defp language_heading?(_, _), do: false

  defp heading?({"h2", _, _}), do: true
  defp heading?({"h3", _, _}), do: true
  defp heading?(_), do: false

  defp extract_non_finite(conjugations, section) do
    infinitive = extract_infinitive(section)
    gerund = extract_gerund(section)
    past_participle = extract_past_participle(section)

    non_finite =
      %{}
      |> maybe_put("infinitive", infinitive)
      |> maybe_put("gerund", gerund)
      |> maybe_put("past_participle", past_participle)

    if map_size(non_finite) > 0 do
      Map.put(conjugations, "non_finite", non_finite)
    else
      conjugations
    end
  end

  defp extract_infinitive(section) do
    extract_infinitive_from_h2(section) || extract_infinitive_from_dl(section)
  end

  defp extract_infinitive_from_h2(section) do
    section
    |> Enum.find_value(fn node ->
      case node do
        {"h2", _, children} -> find_span_in_children(children)
        _ -> nil
      end
    end)
  end

  defp find_span_in_children(children) do
    Enum.find_value(children, fn child ->
      case child do
        {"span", attrs, _} -> check_span_id(attrs)
        _ -> nil
      end
    end)
  end

  defp check_span_id(attrs) do
    id = Enum.find_value(attrs, fn {k, v} -> if k == "id", do: v, else: nil end)

    if id == "Spanish" do
      # The infinitive is usually the text before the Spanish span
      nil
    else
      nil
    end
  end

  defp extract_infinitive_from_dl(section) do
    section
    |> Enum.flat_map(fn node -> Floki.find(node, "dl dt, dl dd") end)
    |> Enum.find_value(fn elem ->
      text = Floki.text(elem) |> String.downcase()

      if String.contains?(text, "infinitive") do
        find_next_value(elem)
      else
        nil
      end
    end)
  end

  defp extract_gerund(section) do
    section
    |> Enum.flat_map(fn node -> Floki.find(node, "dl dt, dl dd, table td") end)
    |> Enum.find_value(fn elem ->
      text = Floki.text(elem) |> String.downcase()

      if String.contains?(text, "gerund") do
        find_next_value(elem)
      else
        nil
      end
    end)
  end

  defp extract_past_participle(section) do
    section
    |> Enum.flat_map(fn node -> Floki.find(node, "dl dt, dl dd, table td") end)
    |> Enum.find_value(fn elem ->
      text = Floki.text(elem) |> String.downcase()

      if String.contains?(text, "past participle") or String.contains?(text, "participle") do
        find_next_value(elem)
      else
        nil
      end
    end)
  end

  defp parse_conjugation_table(table, acc) do
    rows = Floki.find(table, "tr")

    Enum.reduce(rows, acc, fn row, tense_acc ->
      cells = Floki.find(row, "td, th")

      if header_row?(cells) do
        tense_acc
      else
        parse_conjugation_row(cells, tense_acc)
      end
    end)
  end

  defp header_row?(cells) do
    all_th_cells?(cells) || contains_mood_name?(cells)
  end

  defp all_th_cells?(cells) do
    Enum.all?(cells, fn cell ->
      case cell do
        {"th", _, _} -> true
        _ -> false
      end
    end)
  end

  defp contains_mood_name?(cells) do
    if cells != [] do
      first_cell_text =
        List.first(cells)
        |> Floki.text()
        |> String.downcase()

      String.contains?(first_cell_text, ["indicative", "subjunctive", "imperative"])
    else
      false
    end
  end

  defp parse_conjugation_row(cells, tense_acc) do
    if length(cells) >= 6 do
      process_conjugation_row(cells, tense_acc)
    else
      tense_acc
    end
  end

  defp process_conjugation_row(cells, tense_acc) do
    tense_cell = List.first(cells)
    tense_text = Floki.text(tense_cell) |> String.trim() |> String.downcase()

    mood = extract_mood(tense_text)
    tense_name = extract_tense_name(tense_text)
    tense_key = normalize_tense(tense_name)

    if tense_key do
      person_conjugations = extract_person_conjugations(cells)
      store_conjugation(tense_acc, mood, tense_key, person_conjugations)
    else
      tense_acc
    end
  end

  defp extract_mood(tense_text) do
    cond do
      String.contains?(tense_text, "indicative") -> "indicative"
      String.contains?(tense_text, "subjunctive") -> "subjunctive"
      String.contains?(tense_text, "imperative") -> "imperative"
      true -> "indicative"
    end
  end

  defp extract_tense_name(tense_text) do
    tense_text
    |> String.replace(~r/\b(indicative|subjunctive|imperative)\b/, "")
    |> String.trim()
  end

  defp store_conjugation(tense_acc, mood, tense_key, person_conjugations) do
    mood_map = Map.get(tense_acc, mood, %{})
    mood_map = Map.put(mood_map, tense_key, person_conjugations)
    Map.put(tense_acc, mood, mood_map)
  end

  defp normalize_tense(tense_text) do
    tense_text = String.downcase(tense_text)

    tense_patterns = [
      {"present", "present"},
      {"preterite", "preterite"},
      {"pretérito", "preterite"},
      {"imperfect subjunctive", "imperfect"},
      {"imperfect", "imperfect"},
      {"imperfecto", "imperfect"},
      {"future subjunctive", "future"},
      {"future", "future"},
      {"conditional", "conditional"}
    ]

    Enum.find_value(tense_patterns, fn {pattern, tense} ->
      if String.contains?(tense_text, pattern) do
        tense
      else
        nil
      end
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp extract_person_conjugations(cells) do
    # Skip first cell (tense name), extract person conjugations
    person_cells = Enum.drop(cells, 1)

    # Standard Spanish conjugation order: yo, tú, él/ella/usted, nosotros, vosotros, ellos/ellas/ustedes
    persons = [
      "yo",
      "tú",
      "él/ella/usted",
      "nosotros/nosotras",
      "vosotros/vosotras",
      "ellos/ellas/ustedes"
    ]

    person_cells
    |> Enum.take(6)
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {cell, idx}, acc ->
      person = Enum.at(persons, idx)
      conjugation = Floki.text(cell) |> String.trim()
      if person && conjugation != "", do: Map.put(acc, person, conjugation), else: acc
    end)
  end

  defp find_next_value(elem) do
    # Try to find the next sibling dd or td with the actual form
    # This is a simplified approach - may need refinement based on actual Wiktionary structure
    case Floki.find(elem, "~ dd, ~ td") do
      [next | _] ->
        Floki.text(next) |> String.trim()

      _ ->
        nil
    end
  end

  defp cache_table do
    config = Application.get_env(:langler, Langler.External.Dictionary.Wiktionary, [])
    Keyword.get(config, :conjugation_cache_table, :wiktionary_conjugation_cache)
  end

  defp ttl do
    config = Application.get_env(:langler, Langler.External.Dictionary.Wiktionary, [])
    Keyword.get(config, :conjugation_ttl, :timer.hours(24))
  end
end
