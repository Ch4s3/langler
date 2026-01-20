defmodule Langler.Vocabulary.Workers.ImportCsvWorker do
  @moduledoc """
  Oban worker for importing words from CSV into a deck.
  Processes the import in the background and notifies the user via PubSub when complete.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Langler.Vocabulary
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "csv_content" => csv_content,
          "deck_id" => deck_id,
          "user_id" => user_id,
          "default_language" => default_language,
          "job_id" => job_id,
          "deck_name" => deck_name
        }
      })
      when is_binary(csv_content) and is_integer(deck_id) and is_integer(user_id) and
             is_binary(default_language) and is_integer(job_id) and is_binary(deck_name) do
    Logger.info("Starting CSV import for user #{user_id}, deck #{deck_id}")

    case Vocabulary.import_words_from_csv(csv_content, deck_id, user_id,
           default_language: default_language
         ) do
      {:ok, %{successful: successful, errors: errors, total: total}} ->
        message =
          "#{successful} word#{if successful == 1, do: "", else: "s"} loaded to #{deck_name}"

        PubSub.broadcast(
          Langler.PubSub,
          "csv_import:#{user_id}",
          {:csv_import_complete, job_id,
           {:ok, %{successful: successful, errors: errors, total: total, message: message}}}
        )

        Logger.info("CSV import completed for user #{user_id}: #{message}")
        :ok

      {:error, reason} ->
        error_message = "Failed to import words: #{inspect(reason)}"

        PubSub.broadcast(
          Langler.PubSub,
          "csv_import:#{user_id}",
          {:csv_import_complete, job_id, {:error, error_message}}
        )

        Logger.error("CSV import failed for user #{user_id}: #{error_message}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid args for ImportCsvWorker: #{inspect(args)}")
    {:error, :invalid_args}
  end
end
