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
      current_scope: %{user: %{id: 1, email: "test@example.com"}},
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
      streams: streams,
      decks: [],
      current_deck: nil,
      filter_deck_id: nil,
      show_deck_modal: false,
      editing_deck: nil,
      deck_form: Phoenix.Component.to_form(%{"name" => ""}),
      show_csv_import: false,
      csv_import_deck_id: nil,
      csv_preview: nil,
      csv_content: nil,
      csv_importing: false,
      default_language: "spanish",
      uploads: %{csv_file: %Phoenix.LiveView.UploadConfig{ref: "csv_file", entries: []}}
    }

    html = render_component(&LanglerWeb.StudyLive.Index.render/1, assigns)

    assert html =~ "Study overview"
    assert html =~ "Due now"
    assert html =~ "hola"
  end
end
