defmodule Langler.Vocabulary.Workers.ImportCsvWorkerTest do
  use Langler.DataCase, async: true
  use Oban.Testing, repo: Langler.Repo

  import Langler.AccountsFixtures
  import Langler.VocabularyFixtures

  alias Langler.Vocabulary.Workers.ImportCsvWorker

  describe "perform/1" do
    test "creates job with correct structure" do
      user = user_fixture()
      deck = deck_fixture(%{user_id: user.id})

      job =
        ImportCsvWorker.new(%{
          csv_content: "word,translation\nhello,hola",
          deck_id: deck.id,
          user_id: user.id,
          default_language: "es",
          job_id: 123,
          deck_name: "Test Deck"
        })

      assert job.valid?
      assert job.changes.worker == "Langler.Vocabulary.Workers.ImportCsvWorker"
      assert job.changes.args.deck_id == deck.id
      assert job.changes.args.user_id == user.id
    end

    test "job has correct worker configuration" do
      # Verify the worker is configured properly
      assert ImportCsvWorker.__opts__()[:queue] == :default
      assert ImportCsvWorker.__opts__()[:max_attempts] == 3
    end

    test "returns error for invalid args" do
      # Job with missing required fields
      job = %Oban.Job{
        args: %{
          "invalid" => "args"
        }
      }

      assert {:error, :invalid_args} = ImportCsvWorker.perform(job)
    end

    test "handles CSV import success" do
      user = user_fixture()
      deck = deck_fixture(%{user_id: user.id})

      # Subscribe to pubsub to verify broadcast
      Phoenix.PubSub.subscribe(Langler.PubSub, "csv_import:#{user.id}")

      job = %Oban.Job{
        args: %{
          "csv_content" => "word,translation\nhello,hola\nworld,mundo",
          "deck_id" => deck.id,
          "user_id" => user.id,
          "default_language" => "es",
          "job_id" => 456,
          "deck_name" => "Spanish Deck"
        }
      }

      assert :ok = ImportCsvWorker.perform(job)

      # Verify PubSub broadcast was sent
      assert_receive {:csv_import_complete, 456, {:ok, result}}, 1000
      assert result.successful >= 0
      assert result.total == 2
      assert String.contains?(result.message, "Spanish Deck")
    end

    test "handles CSV import with errors" do
      user = user_fixture()
      deck = deck_fixture(%{user_id: user.id})

      # Subscribe to pubsub
      Phoenix.PubSub.subscribe(Langler.PubSub, "csv_import:#{user.id}")

      # Invalid CSV content (missing header)
      job = %Oban.Job{
        args: %{
          "csv_content" => "invalid csv content without proper format",
          "deck_id" => deck.id,
          "user_id" => user.id,
          "default_language" => "es",
          "job_id" => 789,
          "deck_name" => "Test Deck"
        }
      }

      # Should handle the error gracefully
      result = ImportCsvWorker.perform(job)

      # Either succeeds with errors or returns error
      case result do
        :ok ->
          assert_receive {:csv_import_complete, 789, _}, 1000

        {:error, _reason} ->
          assert_receive {:csv_import_complete, 789, {:error, _}}, 1000
      end
    end
  end
end
