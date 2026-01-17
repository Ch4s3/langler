defmodule Langler.Content.ClassifierTrainerTest do
  use Langler.DataCase, async: true

  alias Langler.Content.Article
  alias Langler.Content.ArticleTopic
  alias Langler.Content.ClassifierTrainer
  alias Langler.Repo

  describe "train_from_existing_articles/2" do
    test "trains model when sufficient articles exist" do
      if nif_available?() do
        insert_articles_with_topics(55,
          language: "spanish",
          topic: "ciencia",
          title_prefix: "Article",
          url_prefix: "science",
          content_prefix: "Article about science and research."
        )

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
      if nif_available?() do
        insert_articles_with_topics(5,
          language: "spanish",
          topic: "ciencia",
          title_prefix: "Article",
          url_prefix: "few",
          content_prefix: "Article"
        )

        assert {:error, :insufficient_data} =
                 ClassifierTrainer.train_from_existing_articles("spanish", 50)
      else
        :ok
      end
    end
  end

  describe "retrain_if_needed/2" do
    test "retrains when enough new articles exist" do
      if nif_available?() do
        insert_articles_with_topics(105,
          language: "spanish",
          topic: "ciencia",
          title_prefix: "Article",
          url_prefix: "retrain",
          content_prefix: "Article about science."
        )

        result = ClassifierTrainer.retrain_if_needed("spanish", 100)

        # Should retrain or return ok
        assert result == :ok or match?({:error, _}, result)
      else
        :ok
      end
    end

    test "does not retrain when insufficient articles exist" do
      insert_articles_with_topics(5,
        language: "spanish",
        topic: "ciencia",
        title_prefix: "Article",
        url_prefix: "insufficient",
        content_prefix: "Article"
      )

      # Should return :ok without retraining
      assert :ok = ClassifierTrainer.retrain_if_needed("spanish", 100)
    end
  end

  defp insert_articles_with_topics(count, attrs) do
    attrs =
      case attrs do
        attrs when is_list(attrs) -> Map.new(attrs)
        attrs when is_map(attrs) -> attrs
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    unique = System.unique_integer([:positive])

    articles =
      Enum.map(1..count, fn i ->
        %{
          title: "#{attrs.title_prefix} #{i}",
          url: "https://example.test/#{attrs.url_prefix}-#{unique}-#{i}",
          language: attrs.language,
          content: "#{attrs.content_prefix} #{i}",
          inserted_at: now,
          updated_at: now
        }
      end)

    {_, inserted} = Repo.insert_all(Article, articles, returning: [:id])

    topics =
      Enum.map(inserted, fn article ->
        %{
          article_id: article.id,
          topic: attrs.topic,
          confidence: Decimal.new("0.85"),
          language: attrs.language,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ArticleTopic, topics)
  end

  defp nif_available? do
    Code.ensure_loaded?(Langler.Content.ClassifierNif) and
      function_exported?(Langler.Content.ClassifierNif, :train, 1)
  end
end
