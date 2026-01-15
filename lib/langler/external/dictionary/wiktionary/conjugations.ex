defmodule Langler.External.Dictionary.Wiktionary.Conjugations do
  @moduledoc """
  Scrapes Spanish verb conjugation tables from Wiktionary.
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
      with {:ok, body, _url} <- fetch_page(lemma, normalized_language),
           {:ok, doc} <- Floki.parse_document(body),
           conjugations <- parse_conjugations(doc, normalized_language) do
        if map_size(conjugations) > 0 do
          {:ok, conjugations}
        else
          # Debug: log what we found
          require Logger
          language_section = find_language_section(doc, normalized_language)

          tables_count =
            if language_section do
              language_section
              |> Enum.flat_map(fn node -> Floki.find(node, "table") end)
              |> length()
            else
              0
            end

          section_status = if language_section, do: "found", else: "not found"

          Logger.warning(
            "Wiktionary conjugations: no conjugations found for #{lemma}. Language section: #{section_status}, Tables: #{tables_count}"
          )

          {:error, :not_found}
        end
      end
    end)
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
    {_acc, _result} =
      Enum.reduce(children, {false, []}, fn node, {found, acc} ->
        cond do
          language_heading?(node, anchor) ->
            {true, []}

          found && heading?(node) ->
            throw({:done, Enum.reverse(acc)})

          found ->
            {found, [node | acc]}

          true ->
            {found, acc}
        end
      end)
  catch
    {:done, acc} -> Enum.reverse(acc)
  else
    {false, _} -> nil
    {_found, acc} -> Enum.reverse(acc)
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
    # Look for non-finite forms (infinitive, gerund, past participle)
    non_finite = %{}

    # Try to find infinitive from the page title or Spanish heading
    # Fallback: look for dl/dt/dd structure with infinitive
    infinitive =
      section
      |> Enum.find_value(fn node ->
        # Look for h2 with Spanish span
        case node do
          {"h2", _, children} ->
            Enum.find_value(children, fn child ->
              case child do
                {"span", attrs, _} ->
                  id = Enum.find_value(attrs, fn {k, v} -> if k == "id", do: v, else: nil end)

                  if id == "Spanish" do
                    # The infinitive is usually the text before the Spanish span
                    nil
                  else
                    nil
                  end

                _ ->
                  nil
              end
            end)

          _ ->
            nil
        end
      end) ||
        section
        |> Enum.flat_map(fn node -> Floki.find(node, "dl dt, dl dd") end)
        |> Enum.find_value(fn elem ->
          text = Floki.text(elem) |> String.downcase()

          if String.contains?(text, "infinitive") do
            # Try to find the value
            find_next_value(elem)
          else
            nil
          end
        end)

    non_finite =
      if infinitive, do: Map.put(non_finite, "infinitive", infinitive), else: non_finite

    # Look for gerund and past participle
    gerund =
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

    past_participle =
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

    non_finite =
      non_finite
      |> (fn nf -> if gerund, do: Map.put(nf, "gerund", gerund), else: nf end).()
      |> (fn nf ->
            if past_participle, do: Map.put(nf, "past_participle", past_participle), else: nf
          end).()

    if map_size(non_finite) > 0 do
      Map.put(conjugations, "non_finite", non_finite)
    else
      conjugations
    end
  end

  defp parse_conjugation_table(table, acc) do
    # Extract rows from the table
    rows = Floki.find(table, "tr")

    # Group rows by mood (if there are mood headers)
    # Otherwise, parse all rows as indicative
    Enum.reduce(rows, acc, fn row, tense_acc ->
      cells = Floki.find(row, "td, th")

      # Check if this is a header row (all th cells or contains mood name)
      is_header =
        Enum.all?(cells, fn cell ->
          case cell do
            {"th", _, _} -> true
            _ -> false
          end
        end) ||
          (cells != [] &&
             Floki.text(List.first(cells))
             |> String.downcase()
             |> String.contains?(["indicative", "subjunctive", "imperative"]))

      if is_header do
        # Skip header rows
        tense_acc
      else
        # Parse conjugation row
        if length(cells) >= 6 do
          # First cell is usually the tense name
          tense_cell = List.first(cells)
          tense_text = Floki.text(tense_cell) |> String.trim() |> String.downcase()

          # Check if this row contains mood information
          mood =
            cond do
              String.contains?(tense_text, "indicative") -> "indicative"
              String.contains?(tense_text, "subjunctive") -> "subjunctive"
              String.contains?(tense_text, "imperative") -> "imperative"
              # Default to indicative
              true -> "indicative"
            end

          # Extract tense name (remove mood if present)
          tense_name =
            tense_text
            |> String.replace(~r/\b(indicative|subjunctive|imperative)\b/, "")
            |> String.trim()

          # Normalize tense names
          tense_key = normalize_tense(tense_name)

          if tense_key do
            # Remaining cells are conjugations for each person
            person_conjugations = extract_person_conjugations(cells)

            # Store in nested structure: mood -> tense -> persons
            mood_map = Map.get(tense_acc, mood, %{})
            mood_map = Map.put(mood_map, tense_key, person_conjugations)
            Map.put(tense_acc, mood, mood_map)
          else
            tense_acc
          end
        else
          tense_acc
        end
      end
    end)
  end

  defp normalize_tense(tense_text) do
    tense_text = String.downcase(tense_text)

    cond do
      String.contains?(tense_text, "present") ->
        "present"

      String.contains?(tense_text, "preterite") or String.contains?(tense_text, "pretérito") ->
        "preterite"

      String.contains?(tense_text, "imperfect") or String.contains?(tense_text, "imperfecto") ->
        "imperfect"

      String.contains?(tense_text, "future") ->
        "future"

      String.contains?(tense_text, "conditional") ->
        "conditional"

      String.contains?(tense_text, "imperfect subjunctive") ->
        "imperfect"

      String.contains?(tense_text, "future subjunctive") ->
        "future"

      true ->
        nil
    end
  end

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
