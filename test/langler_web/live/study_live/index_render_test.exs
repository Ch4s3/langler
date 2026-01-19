defmodule LanglerWeb.StudyLive.IndexRenderTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Phoenix.LiveView.AsyncResult

  alias Langler.Vocabulary.Word

  test "renders study overview and cards" do
    word = %Word{
      id: 1,
      lemma: "hola",
      normalized_form: "hola",
      language: "spanish",
      definitions: ["hello"]
    }

    item = %{
      id: 42,
      due_date: DateTime.utc_now(),
      ease_factor: 2.5,
      interval: 3,
      repetitions: 2,
      quality_history: [4, 3],
      word: word
    }

    streams = %{items: [{"items-#{item.id}", item}]}

    assigns = %{
      flash: %{},
      current_scope: nil,
      filters: [
        %{id: :now, label: "Due now"},
        %{id: :today, label: "Due today"},
        %{id: :all, label: "All words"}
      ],
      filter: :now,
      search_query: "",
      quality_buttons: [
        %{score: 0, label: "Again", class: "btn-error"},
        %{score: 3, label: "Good", class: "btn-primary"}
      ],
      stats: %{due_now: 1, due_today: 1, total: 1, completion: 100},
      all_items: [item],
      visible_count: 1,
      flipped_cards: MapSet.new(),
      expanded_conjugations: MapSet.new(),
      conjugations_loading: MapSet.new(),
      definitions_loading: MapSet.new(),
      user_level: %{cefr_level: "A1"},
      recommended_articles: AsyncResult.ok([]),
      streams: streams
    }

    html = render_component(&LanglerWeb.StudyLive.Index.render/1, assigns)

    assert html =~ "Study overview"
    assert html =~ "Due now"
    assert html =~ "hola"
  end
end
