# Script to load Spanish word frequency data from CSV
# Source: OpenSubtitles corpus (https://github.com/hermitdave/FrequencyWords)
# Run with: mix run priv/repo/seeds/word_frequencies.exs

alias Langler.Repo
alias Langler.Vocabulary.Word

# Check if frequency_rank column exists
case Repo.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'words' AND column_name = 'frequency_rank'") do
  {:ok, %{rows: []}} ->
    IO.puts("ERROR: frequency_rank column does not exist. Please run migrations first.")
    System.halt(1)

  {:ok, _} ->
    # Column exists, proceed with loading
    csv_path = Path.join([__DIR__, "data", "spanish_frequencies.csv"])

    if not File.exists?(csv_path) do
      IO.puts("ERROR: CSV file not found at #{csv_path}")
      IO.puts("Please download the OpenSubtitles Spanish frequency list and save it as:")
      IO.puts("  #{csv_path}")
      IO.puts("")
      IO.puts("Source: https://github.com/hermitdave/FrequencyWords/blob/master/content/2018/es/es_50k.txt")
      System.halt(1)
    end

    IO.puts("Loading Spanish word frequencies from #{csv_path}...")

    # Read and parse CSV manually
    entries =
      csv_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&(&1 != ""))
      |> Enum.drop(1)  # Skip header row
      |> Enum.map(fn line ->
        [word, frequency_rank_str, cefr_level] =
          line
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        frequency_rank = String.to_integer(frequency_rank_str)

        # Normalize the word form (lowercase, remove accents for matching)
        normalized = Langler.Vocabulary.normalize_form(word)

        %{
          normalized_form: normalized,
          language: "spanish",
          frequency_rank: frequency_rank,
          cefr_level: cefr_level,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

    IO.puts("Found #{length(entries)} words to process")

    # Process in chunks of 500
    entries
    |> Enum.chunk_every(500)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      IO.puts("Processing chunk #{index} (#{length(chunk)} words)...")

      # Upsert words - update frequency_rank and cefr_level for existing words
      # Insert new words if they don't exist
      Repo.insert_all(
        Word,
        chunk,
        on_conflict: {:replace_all_except, [:id, :inserted_at, :normalized_form, :language]},
        conflict_target: [:normalized_form, :language]
      )
    end)

    IO.puts("✓ Successfully loaded #{length(entries)} word frequencies")

    # Trigger difficulty calculation for all discovered articles
    IO.puts("Enqueuing difficulty calculation for existing discovered articles...")
    case Code.ensure_loaded(Langler.Content) do
      {:module, Langler.Content} ->
        if function_exported?(Langler.Content, :enqueue_difficulty_backfill, 0) do
          Langler.Content.enqueue_difficulty_backfill()
          IO.puts("✓ Difficulty calculation jobs enqueued")
        else
          IO.puts("⚠ Difficulty backfill function not yet implemented, skipping...")
        end

      {:error, _} ->
        IO.puts("⚠ Langler.Content module not available, skipping difficulty backfill...")
    end
end
