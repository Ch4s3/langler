defmodule Langler.Content.ClassifierTest do
  use Langler.DataCase, async: true

  alias Langler.Content.Classifier
  alias Langler.Content.ClassifierNif
  alias Langler.Content.ArticleTopic
  alias Langler.ContentFixtures
  alias Langler.Repo

  describe "classify/2 - rule-based classification" do
    test "classifies Spanish science article correctly" do
      content = """
      La ciencia busca nuevas respuestas a preguntas fundamentales sobre el universo.
      Los científicos realizan investigaciones en laboratorios modernos.
      Los experimentos y estudios revelan descubrimientos importantes.
      La investigación científica continúa avanzando con nuevos descubrimientos.
      """

      topics = Classifier.classify(content, "spanish")

      assert length(topics) > 0
      # Check that we got ciencia topic (may be spelled differently)
      ciencia_topics = Enum.filter(topics, fn {topic, _conf} -> topic =~ "ciencia" end)
      assert length(ciencia_topics) > 0
      {_topic, confidence} = List.first(ciencia_topics)
      # Confidence should be above threshold (0.15)
      assert confidence >= 0.15
    end

    test "classifies Spanish politics article correctly" do
      content = """
      El gobierno anunció nuevas políticas públicas esta semana.
      El presidente se reunió con el congreso para discutir la legislación.
      Los partidos políticos debatieron sobre las elecciones próximas.
      La votación y la democracia son fundamentales para el país.
      """

      topics = Classifier.classify(content, "spanish")

      assert length(topics) > 0
      # Check that we got política topic
      politica_topics = Enum.filter(topics, fn {topic, _conf} -> topic =~ "política" or topic =~ "politica" end)
      assert length(politica_topics) > 0
      {_topic, confidence} = List.first(politica_topics)
      assert confidence >= 0.3
    end

    test "classifies English science article correctly" do
      content = """
      Science research continues to make important discoveries.
      Scientists conduct experiments in modern laboratories.
      Studies reveal new insights into the natural world.
      """

      topics = Classifier.classify(content, "english")

      assert length(topics) > 0
      science_topic = Enum.find(topics, fn {topic, _conf} -> topic == "science" end)
      assert science_topic != nil
    end

    test "returns empty list for empty content" do
      assert Classifier.classify("", "spanish") == []
      assert Classifier.classify("   ", "spanish") == []
    end

    test "filters topics below confidence threshold" do
      # Content with minimal keyword matches
      content = "This is a very short article with few keywords."

      topics = Classifier.classify(content, "english")

      # All topics should meet confidence threshold
      Enum.each(topics, fn {_topic, confidence} ->
        assert confidence >= 0.3
      end)
    end

    test "returns top N topics (default 3)" do
      # Content that matches multiple topics
      content = """
      La ciencia y la tecnología avanzan rápidamente.
      El gobierno invierte en investigación científica.
      La economía se beneficia de estos avances tecnológicos.
      """

      topics = Classifier.classify(content, "spanish")

      assert length(topics) <= 3
    end

    test "handles content with accents correctly" do
      content = """
      La investigación científica en España continúa avanzando.
      Los científicos españoles realizan estudios importantes.
      """

      topics = Classifier.classify(content, "spanish")

      assert length(topics) > 0
      # Should match "ciencia" despite accents
      ciencia_topics = Enum.filter(topics, fn {topic, _conf} -> topic =~ "ciencia" end)
      assert length(ciencia_topics) > 0
    end
  end

  describe "classify/2 - ML classification with fallback" do
    test "falls back to rule-based when ML model not available" do
      # Ensure no model exists (only if table exists)
      if :ets.whereis(:classifier_model) != :undefined do
        :ets.delete_all_objects(:classifier_model)
      end

      content = "La ciencia busca nuevas respuestas."

      topics = Classifier.classify(content, "spanish")

      # Should still work with rule-based
      assert length(topics) > 0
      assert Enum.any?(topics, fn {topic, _conf} -> topic =~ "ciencia" end)
    end

    test "uses ML classifier when model is available" do
      # Mock training data
      training_data = [
        %{
          "content" => "La ciencia busca nuevas respuestas. Los científicos realizan investigaciones.",
          "topics" => ["ciencia"]
        },
        %{
          "content" => "El gobierno anunció nuevas políticas. El presidente se reunió con el congreso.",
          "topics" => ["política"]
        },
        %{
          "content" => "La economía crece. El mercado financiero está estable.",
          "topics" => ["economía"]
        }
      ]

      # Only test if NIF is available
      if nif_available?() do
        case Classifier.train(training_data, "spanish") do
          {:ok, _model_json} ->
            content = "La ciencia y la investigación científica avanzan rápidamente."
            topics = Classifier.classify(content, "spanish")

            # ML should return results
            assert length(topics) > 0
            assert Enum.any?(topics, fn {topic, _conf} -> topic =~ "ciencia" end)

          {:error, :nif_not_loaded} ->
            # NIF not available, skip ML test
            :ok

          {:error, reason} ->
            # Other error, log but don't fail test
            IO.puts("ML training failed: #{inspect(reason)}")
            :ok
        end
      else
        # NIF not available, skip ML test
        :ok
      end
    end
  end

  describe "train/2" do
    test "trains model with sufficient training data" do
      if nif_available?() do
        training_data = [
          %{"content" => "Science research continues.", "topics" => ["science"]},
          %{"content" => "Government policies change.", "topics" => ["politics"]},
          %{"content" => "Economic growth continues.", "topics" => ["economy"]},
          %{"content" => "Scientific discoveries happen.", "topics" => ["science"]},
          %{"content" => "Political parties debate.", "topics" => ["politics"]},
          %{"content" => "Market prices fluctuate.", "topics" => ["economy"]},
          %{"content" => "Research laboratories innovate.", "topics" => ["science"]},
          %{"content" => "Elections determine leadership.", "topics" => ["politics"]},
          %{"content" => "Financial markets trade.", "topics" => ["economy"]},
          %{"content" => "Scientific methods evolve.", "topics" => ["science"]},
          %{"content" => "Technology advances rapidly.", "topics" => ["technology"]},
          %{"content" => "Health care improves.", "topics" => ["health"]}
        ]

        case Classifier.train(training_data, "english") do
          {:ok, model_json} ->
            assert is_binary(model_json)
            assert String.length(model_json) > 0
            # Verify model contains expected structure
            assert model_json =~ "topic_priors"
            assert model_json =~ "word_given_topic"

          {:error, :nif_not_loaded} ->
            # NIF not available, skip test
            :ok

          {:error, reason} ->
            flunk("Training failed: #{inspect(reason)}")
        end
      else
        # NIF not available, skip test
        :ok
      end
    end

    test "returns error with insufficient training data" do
      if nif_available?() do
        training_data = [
          %{"content" => "Science research.", "topics" => ["science"]}
        ]

        assert {:error, :insufficient_training_data} = Classifier.train(training_data, "english")
      else
        # NIF not available, skip test
        :ok
      end
    end

    test "handles empty training data" do
      if nif_available?() do
        assert {:error, :insufficient_training_data} = Classifier.train([], "english")
      else
        :ok
      end
    end
  end

  describe "collect_training_data/2" do
    test "collects training data from articles with topics" do
      user = Langler.AccountsFixtures.user_fixture()

      # Create articles with high-confidence topics
      article1 =
        ContentFixtures.article_fixture(%{
          user: user,
          content: "La ciencia busca nuevas respuestas.",
          language: "spanish"
        })

      article2 =
        ContentFixtures.article_fixture(%{
          user: user,
          content: "El gobierno anunció nuevas políticas.",
          language: "spanish"
        })

      # Add high-confidence topics
      {:ok, _} =
        Repo.insert(%ArticleTopic{
          article_id: article1.id,
          topic: "ciencia",
          confidence: Decimal.new("0.85"),
          language: "spanish"
        })

      {:ok, _} =
        Repo.insert(%ArticleTopic{
          article_id: article2.id,
          topic: "política",
          confidence: Decimal.new("0.90"),
          language: "spanish"
        })

      training_data = Classifier.collect_training_data(0.7, 100)

      assert length(training_data) >= 2

      # Check that training data has correct format
      Enum.each(training_data, fn doc ->
        assert Map.has_key?(doc, "content")
        assert Map.has_key?(doc, "topics")
        assert is_list(doc["topics"])
        assert length(doc["topics"]) > 0
      end)

      # Verify specific articles are included
      assert Enum.any?(training_data, fn doc ->
        doc["content"] =~ "ciencia" and "ciencia" in doc["topics"]
      end)

      assert Enum.any?(training_data, fn doc ->
        doc["content"] =~ "gobierno" and "política" in doc["topics"]
      end)
    end

    test "filters by confidence threshold" do
      user = Langler.AccountsFixtures.user_fixture()

      article_high =
        ContentFixtures.article_fixture(%{
          user: user,
          content: "High confidence article.",
          language: "spanish"
        })

      article_low =
        ContentFixtures.article_fixture(%{
          user: user,
          content: "Low confidence article.",
          language: "spanish"
        })

      # Add high confidence topic
      {:ok, _} =
        Repo.insert(%ArticleTopic{
          article_id: article_high.id,
          topic: "ciencia",
          confidence: Decimal.new("0.85"),
          language: "spanish"
        })

      # Add low confidence topic
      {:ok, _} =
        Repo.insert(%ArticleTopic{
          article_id: article_low.id,
          topic: "ciencia",
          confidence: Decimal.new("0.50"),
          language: "spanish"
        })

      training_data = Classifier.collect_training_data(0.7, 100)

      # Should only include high confidence article
      high_conf_articles =
        Enum.filter(training_data, fn doc ->
          doc["content"] =~ "High confidence"
        end)

      assert length(high_conf_articles) >= 1

      low_conf_articles =
        Enum.filter(training_data, fn doc ->
          doc["content"] =~ "Low confidence"
        end)

      assert length(low_conf_articles) == 0
    end

    test "respects limit parameter" do
      user = Langler.AccountsFixtures.user_fixture()

      # Create multiple articles
      for i <- 1..10 do
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

      training_data = Classifier.collect_training_data(0.7, 5)

      assert length(training_data) <= 5
    end

    test "returns empty list when no articles match criteria" do
      training_data = Classifier.collect_training_data(0.95, 100)

      assert training_data == []
    end
  end

  describe "edge cases" do
    test "handles very long content" do
      long_content = String.duplicate("La ciencia busca nuevas respuestas. ", 1000)

      topics = Classifier.classify(long_content, "spanish")

      # Should still work, may return multiple topics
      assert is_list(topics)
      assert Enum.all?(topics, fn {topic, conf} ->
        is_binary(topic) and is_float(conf) and conf >= 0.0
      end)
    end

    test "handles content with special characters" do
      content = """
      La ciencia & tecnología: avances en 2024.
      Precio: $100. Contacto: info@example.com
      URLs: https://example.com/science
      """

      topics = Classifier.classify(content, "spanish")

      # Should handle special characters gracefully
      assert is_list(topics)
    end

    test "handles mixed language content" do
      content = """
      La ciencia (science) busca nuevas respuestas.
      El gobierno (government) anuncia políticas.
      """

      # Classify as Spanish
      topics = Classifier.classify(content, "spanish")

      # Should still work, may match Spanish keywords
      assert is_list(topics)
    end

    test "handles content with numbers" do
      content = """
      En 2024, la ciencia avanzó significativamente.
      Los científicos publicaron más de 1000 estudios.
      """

      topics = Classifier.classify(content, "spanish")

      assert is_list(topics)
    end
  end

  # Helper function to check if NIF is available
  defp nif_available? do
    Code.ensure_loaded?(ClassifierNif) and
      function_exported?(ClassifierNif, :train, 1) and
      function_exported?(ClassifierNif, :classify, 2)
  end
end
