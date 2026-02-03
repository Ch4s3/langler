defmodule Mix.Tasks.Langler.Gettext.Seed do
  @moduledoc """
  Seeds Gettext translation files with machine-generated translations.

  This task extracts English source strings from the codebase and uses
  the configured LLM to generate translations for all supported locales.

  ## Configuration

  Add to `config/dev.secrets.exs` (and import it from `config/dev.exs`):

      import Config
      config :langler, Langler.Gettext.Seed,
        api_key: "sk-..."  # or System.get_env("OPENAI_API_KEY")

  Optional: `model` (default: "gpt-5-mini"), `base_url`, `temperature`, `max_tokens`.

  ## Usage

      mix langler.gettext.seed

  ## Options

      --locale LOCALE         Only seed translations for the specified locale (e.g., es, fr)
      --force                 Overwrite existing translations
      --skip-already-done     Skip locales that already have all strings translated

  ## Examples

      mix langler.gettext.seed
      mix langler.gettext.seed --locale fr
      mix langler.gettext.seed --force
      mix langler.gettext.seed --skip-already-done

  """
  use Mix.Task

  alias Langler.Gettext.Seed, as: GettextSeed

  @shortdoc "Seeds Gettext translations using LLM"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse!(args,
        strict: [locale: :string, force: :boolean, skip_already_done: :boolean],
        aliases: [l: :locale, f: :force, s: :skip_already_done]
      )

    locale = opts[:locale]
    force = opts[:force] || false
    skip_already_done = opts[:skip_already_done] || false

    locales_to_seed =
      if locale do
        [locale]
      else
        ["es", "fr", "it", "ro", "ca", "pt_BR", "pt_PT"]
      end

    Mix.shell().info("Seeding translations for locales: #{inspect(locales_to_seed)}")
    Mix.shell().info("Force mode: #{force}")
    Mix.shell().info("Skip already done: #{skip_already_done}")

    case run_seed(locales_to_seed, force, skip_already_done) do
      :ok ->
        Mix.shell().info("")

        Mix.shell().info(
          "Done. Run mix gettext.merge if you need to merge new .pot entries into existing .po files."
        )

      {:error, reason} ->
        Mix.raise("Gettext seed failed: #{inspect(reason)}")
    end
  end

  defp run_seed(locales_to_seed, force, skip_already_done) do
    with {:ok, config} <- get_llm_config(),
         {:ok, pot_path} <- ensure_pot(),
         {:ok, entries} <- parse_entries(pot_path) do
      seed_all_locales(config, locales_to_seed, entries, force, skip_already_done)
    end
  end

  defp seed_all_locales(config, locales_to_seed, entries, force, skip_already_done) do
    strings = Enum.map(entries, & &1.msgid)
    Mix.shell().info("Found #{length(strings)} strings to translate.")

    Enum.reduce_while(locales_to_seed, :ok, fn locale, _acc ->
      seed_locale_step(config, locale, entries, strings, force, skip_already_done)
    end)
  end

  defp seed_locale_step(config, locale, entries, strings, force, skip_already_done) do
    if skip_already_done and locale_already_seeded?(locale, entries) do
      Mix.shell().info("  #{locale}: skipped (already done)")
      {:cont, :ok}
    else
      case seed_locale(config, locale, entries, strings, force) do
        :ok ->
          Mix.shell().info("  #{locale}: ok")
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:locale, locale, reason}}}
      end
    end
  end

  defp locale_already_seeded?(locale, entries) do
    po_path = Path.join([File.cwd!(), "priv/gettext", locale, "LC_MESSAGES", "default.po"])
    existing = GettextSeed.load_existing_po(po_path)

    translated_count =
      Enum.count(entries, fn %{msgid: msgid} ->
        str = Map.get(existing, msgid)
        is_binary(str) and String.trim(str) != ""
      end)

    translated_count == length(entries)
  end

  defp get_llm_config do
    seed_config = Application.get_env(:langler, Langler.Gettext.Seed, [])
    api_key = Keyword.get(seed_config, :api_key) || System.get_env("OPENAI_API_KEY")

    if is_binary(api_key) and api_key != "" do
      config =
        seed_config
        |> Keyword.take([:api_key, :model, :base_url, :temperature, :max_tokens, :timeout])
        |> Enum.into(%{})
        |> Map.put(:api_key, api_key)
        |> Map.put_new(:model, "gpt-5-mini")
        |> Map.put_new(:temperature, 1.0)
        |> Map.put_new(:timeout, 120_000)

      {:ok, config}
    else
      {:error,
       "No API key. Set config :langler, Langler.Gettext.Seed, api_key: \"...\" in config/dev.secrets.exs or OPENAI_API_KEY env."}
    end
  end

  defp ensure_pot do
    base = Path.join(File.cwd!(), "priv/gettext")
    pot_path = Path.join([base, "default.pot"])

    if File.exists?(pot_path) do
      {:ok, pot_path}
    else
      Mix.shell().info("Running mix gettext.extract --merge to generate default.pot...")
      Mix.Task.run("gettext.extract", ["--merge"])

      if File.exists?(pot_path),
        do: {:ok, pot_path},
        else: {:error, "default.pot not found after extract"}
    end
  end

  defp parse_entries(pot_path) do
    {:ok, GettextSeed.parse_pot(pot_path)}
  end

  defp seed_locale(config, locale, entries, strings, force) do
    po_path = Path.join([File.cwd!(), "priv/gettext", locale, "LC_MESSAGES", "default.po"])

    case translate_in_batches(config, strings, locale) do
      {:ok, all_translations} ->
        GettextSeed.write_po(po_path, entries, all_translations, force: force)

      {:error, _} = err ->
        err
    end
  end

  defp translate_in_batches(config, strings, locale) do
    batch_size = 15
    batches = Enum.chunk_every(strings, batch_size)
    total = length(batches)

    batches
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, fn {batch, i}, {:ok, acc} ->
      Mix.shell().info("    Translating batch #{i}/#{total} (#{length(batch)} strings)...")
      handle_batch_result(config, batch, locale, acc, i, total)
    end)
  end

  defp handle_batch_result(config, batch, locale, acc, i, total) do
    case GettextSeed.translate_strings(config, batch, locale) do
      {:ok, map} ->
        {:cont, {:ok, Map.merge(acc, map)}}

      {:error, :invalid_json_response} ->
        Mix.shell().info("    Retrying batch #{i}/#{total} (invalid JSON)...")

        case GettextSeed.translate_strings(config, batch, locale) do
          {:ok, map} -> {:cont, {:ok, Map.merge(acc, map)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end
end
