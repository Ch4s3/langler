defmodule LanglerWeb.DictionarySearchLive.ModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LanglerWeb.DictionarySearchLive.Modal

  defp build_socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end

  describe "update/2" do
    test "assigns defaults when no action provided" do
      socket = build_socket()

      assert {:ok, updated} = Modal.update(%{}, socket)
      assert updated.assigns.open == false
      assert updated.assigns.query == ""
      assert updated.assigns.searching == false
      assert updated.assigns.result == nil
      assert updated.assigns.conjugations == nil
      assert updated.assigns.word_id == nil
      assert updated.assigns.already_studying == false
      assert updated.assigns.just_added == false
      assert updated.assigns.error == nil
    end

    test "preserves existing assigns when updating" do
      socket = build_socket()

      {:ok, socket} = Modal.update(%{open: true, query: "hablar"}, socket)

      assert socket.assigns.open == true
      assert socket.assigns.query == "hablar"

      # Update with new assigns, should preserve old ones
      {:ok, updated} = Modal.update(%{error: "test error"}, socket)

      assert updated.assigns.open == true
      assert updated.assigns.query == "hablar"
      assert updated.assigns.error == "test error"
    end
  end

  describe "render/1" do
    test "renders modal container" do
      html = render_modal(%{open: false})

      assert html =~ "id=\"dictionary-search-modal-wrapper\""
      assert html =~ "id=\"dictionary-search-modal\""
      assert html =~ "Dictionary Search"
    end

    test "renders modal-open class when open" do
      html = render_modal(%{open: true})

      assert html =~ "modal-open"
    end

    test "does not render modal-open class when closed" do
      html = render_modal(%{open: false})

      refute html =~ "modal-open"
    end

    test "renders search form" do
      html = render_modal(%{open: true})

      assert html =~ "id=\"dictionary-search-form\""
      assert html =~ "name=\"query\""
      assert html =~ "Search for a word"
    end

    test "renders empty state when no query" do
      html = render_modal(%{open: true, query: "", result: nil})

      assert html =~ "Type a word to search"
    end

    test "renders error message when error present" do
      html = render_modal(%{open: true, error: "Could not find word"})

      assert html =~ "Could not find word"
      assert html =~ "alert-error"
    end

    test "renders search results when result present" do
      result = %{
        word: "hablar",
        lemma: "hablar",
        part_of_speech: "verb",
        pronunciation: "aˈβlaɾ",
        translation: "to speak",
        definitions: ["To speak", "To talk"],
        source_url: "https://en.wiktionary.org/wiki/hablar"
      }

      html = render_modal(%{open: true, result: result, word_id: 123})

      assert html =~ "id=\"dictionary-result\""
      assert html =~ "hablar"
      assert html =~ "to speak"
      assert html =~ "To speak"
      assert html =~ "To talk"
      assert html =~ "verb"
      assert html =~ "aˈβlaɾ"
      assert html =~ "Wiktionary"
    end

    test "renders add to study button when result present and not studying" do
      result = %{
        word: "hablar",
        lemma: "hablar",
        part_of_speech: "verb",
        pronunciation: nil,
        translation: "to speak",
        definitions: ["To speak"],
        source_url: nil
      }

      html =
        render_modal(%{
          open: true,
          result: result,
          word_id: nil,
          already_studying: false,
          just_added: false
        })

      assert html =~ "id=\"add-to-study-btn\""
      assert html =~ "Add to Study"
    end

    test "renders already studying badge when already_studying is true" do
      result = %{
        word: "hablar",
        lemma: "hablar",
        part_of_speech: "verb",
        pronunciation: nil,
        translation: "to speak",
        definitions: ["To speak"],
        source_url: nil
      }

      html =
        render_modal(%{
          open: true,
          result: result,
          word_id: 123,
          already_studying: true,
          just_added: false
        })

      assert html =~ "id=\"already-studying-badge\""
      assert html =~ "Already Studying"
      refute html =~ "id=\"add-to-study-btn\""
    end

    test "renders just added badge after adding to study" do
      result = %{
        word: "hablar",
        lemma: "hablar",
        part_of_speech: "verb",
        pronunciation: nil,
        translation: "to speak",
        definitions: ["To speak"],
        source_url: nil
      }

      html =
        render_modal(%{
          open: true,
          result: result,
          word_id: 123,
          already_studying: true,
          just_added: true
        })

      assert html =~ "id=\"study-added-badge\""
      assert html =~ "Added to Study"
    end

    test "renders conjugations when present" do
      result = %{
        word: "hablar",
        lemma: "hablar",
        part_of_speech: "verb",
        pronunciation: nil,
        translation: "to speak",
        definitions: ["To speak"],
        source_url: nil
      }

      conjugations = %{
        "indicative" => %{
          "present" => %{
            "yo" => "hablo",
            "tú" => "hablas",
            "él/ella/usted" => "habla",
            "nosotros/nosotras" => "hablamos",
            "vosotros/vosotras" => "habláis",
            "ellos/ellas/ustedes" => "hablan"
          }
        },
        "non_finite" => %{
          "infinitive" => "hablar",
          "gerund" => "hablando",
          "past_participle" => "hablado"
        }
      }

      html =
        render_modal(%{
          open: true,
          result: result,
          conjugations: conjugations,
          word_id: 123
        })

      assert html =~ "Conjugations"
      assert html =~ "Indicative"
      assert html =~ "Present"
      assert html =~ "hablo"
      assert html =~ "hablas"
      assert html =~ "Non-finite Forms"
      assert html =~ "hablando"
    end
  end

  defp render_modal(overrides) do
    myself = %Phoenix.LiveComponent.CID{cid: 1}

    assigns =
      %{
        open: false,
        query: "",
        searching: false,
        result: nil,
        conjugations: nil,
        word_id: nil,
        already_studying: false,
        just_added: false,
        error: nil,
        myself: myself
      }
      |> Map.merge(overrides)

    render_component(&Modal.render/1, assigns)
  end
end
