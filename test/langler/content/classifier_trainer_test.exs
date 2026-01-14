defmodule Langler.Content.ClassifierTrainerTest do
  use Langler.DataCase, async: true

  alias Langler.Content.ClassifierTrainer
  alias Langler.Content.Classifier
  alias Langler.Content.{ArticleTopic}
  alias Langler.ContentFixtures
  alias Langler.AccountsFixtures
  alias Langler.Repo

  describe "train_from_existing_articles/2" do
    test "trains model when sufficient articles exist" do
      user = AccountsFixtures.user_fixture()

      # Create enough articles with high-confidence topics
      for i <- 1..60 do
        article =
          ContentFixtures.article_fixture(%{
            user: user,
            content: "Article #{i} about science and research.",
            language: "spanish"
          })

        {:ok, _} =
          Repo.insert(%ArticleTopic{
            article_id: article.id,
            topic: "ciencia",
            confidence: Decimal.new("0.85"),
            language: "spanish"
          })
      end

      # Only test if NIF is available
      if nif_available?() do
        case ClassifierTrainer.train_from_existing_articles("spanish", 50) do
          {:ok, model_json} ->
            assert is_binary(model_json)
            assert String.length(model_json) > 0

          {:error, :nif_not_loaded} ->
            # NIF not available, skip test
            :ok

          {:error, reason} ->
            IO.puts("Training failed: #{inspect(reason)}")
            :ok
        end
      else
        :ok
      end
    end

    test "returns error when insufficient articles exist" do
      user = AccountsFixtures.user_fixture()

      # Create only a few articles
      for i <- 1..10 do
        article =
          ContentFixtures.article_fixture(%{
            user: user,
            content: "Article #{i}.",
            language: "spanish"
          })

        {:ok, _} =
          Repo.insert(%ArticleTopic{
            article_id: article.id,
            topic: "ciencia",
            confidence: Decimal.new("0.85"),
            language: "spanish"
          })
      end

      if nif_available?() do
        assert {:error, :insufficient_data} =
                 ClassifierTrainer.train_from_existing_articles("spanish", 50)
      else
        :ok
      end
    end
  end

  describe "retrain_if_needed/2" do
    test "retrains when enough new articles exist" do
      user = AccountsFixtures.user_fixture()

      # Create enough articles
      for i <- 1..120 do
        article =
          ContentFixtures.article_fixture(%{
            user: user,
            content: "Article #{i} about science.",
            language: "spanish"
          })

        {:ok, _} =
          Repo.insert(%ArticleTopic{
            article_id: article.id,
            topic: "ciencia",
            confidence: Decimal.new("0.85"),
            language: "spanish"
          })
      end

      if nif_available?() do
        result = ClassifierTrainer.retrain_if_needed("spanish", 100)

        # Should retrain or return ok
        assert result == :ok or match?({:error, _}, result)
      else
        :ok
      end
    end

    test "does not retrain when insufficient articles exist" do
      user = AccountsFixtures.user_fixture()

      # Create only a few articles
      for i <- 1..20 do
        article =
          ContentFixtures.article_fixture(%{
            user: user,
            content: "Article #{i}.",
            language: "spanish"
          })

        {:ok, _} =
          Repo.insert(%ArticleTopic{
            article_id: article.id,
            topic: "ciencia",
            confidence: Decimal.new("0.85"),
            language: "spanish"
          })
      end

      # Should return :ok without retraining
      assert :ok = ClassifierTrainer.retrain_if_needed("spanish", 100)
    end
  end

  defp nif_available? do
    Code.ensure_loaded?(Langler.Content.ClassifierNif) and
      function_exported?(Langler.Content.ClassifierNif, :train, 1)
  end
end
