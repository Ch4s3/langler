defmodule LanglerWeb.ArticleLive.ShowRenderTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.Content.Article
  alias Langler.Content.Sentence
  alias Langler.Vocabulary.Word

  describe "render" do
    test "renders the article reader with tokens" do
      assigns = base_assigns()

      html = render_component(&LanglerWeb.ArticleLive.Show.render/1, assigns)

      assert html =~ "Sample Article"
      assert html =~ "Hola"
      assert html =~ "cultura"
    end

    test "shows chat controls when article is imported" do
      assigns =
        base_assigns(%{
          article_status: "imported",
          reading_time_minutes: 5,
          article_topics: [%{topic: "cultura"}, %{topic: "deportes"}]
        })

      html = render_component(&LanglerWeb.ArticleLive.Show.render/1, assigns)

      assert html =~ "Practice with chat"
      assert html =~ "Take quiz"
      assert html =~ "Finish without quiz"
      assert html =~ "5 min read"
      assert html =~ "deportes"
    end

    test "hides finish actions when article is finished" do
      assigns = base_assigns(%{article_status: "finished"})

      html = render_component(&LanglerWeb.ArticleLive.Show.render/1, assigns)

      refute html =~ "Finish without quiz"
      assert html =~ "Practice with chat"
      assert html =~ "Take quiz"
    end
  end

  defp base_assigns(overrides \\ %{}) do
    article = %Article{
      id: 2,
      title: "Sample Article",
      url: "https://example.com/sample",
      language: "spanish",
      inserted_at: DateTime.utc_now(),
      source: "Langler",
      content: "Hola mundo."
    }

    word = %Word{
      id: 5,
      lemma: "hola",
      normalized_form: "hola",
      language: "spanish"
    }

    sentence = %Sentence{
      id: 1,
      content: "Hola mundo.",
      word_occurrences: [
        %{
          id: 1,
          position: 0,
          word: word,
          word_id: word.id
        }
      ]
    }

    defaults = %{
      flash: %{},
      current_scope: nil,
      article: article,
      sentences: [sentence],
      sentence_lookup: %{"1" => sentence},
      studied_word_ids: MapSet.new([word.id]),
      studied_forms: MapSet.new(["hola"]),
      studied_phrases: [],
      study_items_by_word: %{word.id => %{id: 99, due_date: DateTime.utc_now()}},
      article_topics: [%{topic: "cultura"}],
      reading_time_minutes: 1.0,
      article_short_title: "Sample",
      page_title: "Sample Article",
      article_status: "imported",
      tts_enabled: false
    }

    Map.merge(defaults, overrides)
  end
end
