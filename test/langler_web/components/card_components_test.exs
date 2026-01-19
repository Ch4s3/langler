defmodule LanglerWeb.CardComponentsTest do
  use LanglerWeb.ConnCase, async: true
  use LanglerWeb, :html

  import Phoenix.LiveViewTest

  alias LanglerWeb.CoreComponents

  describe "card/1" do
    test "renders with default variant" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card>Card content</.card>
            """
          end,
          %{}
        )

      assert html =~ "card"
      assert html =~ "card-body"
      assert html =~ "Card content"
    end

    test "renders header slot" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card>
              <:header>Header content</:header>
              Main content
            </.card>
            """
          end,
          %{}
        )

      assert html =~ "Header content"
      assert html =~ "Main content"
    end

    test "renders actions slot with card-actions class" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card>
              Main content
              <:actions>Actions content</:actions>
            </.card>
            """
          end,
          %{}
        )

      assert html =~ "card-actions"
      assert html =~ "Actions content"
    end

    test "applies hover classes when hover=true" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card hover>Content</.card>
            """
          end,
          %{}
        )

      assert html =~ "hover:-translate-y-1"
      assert html =~ "hover:shadow-2xl"
    end

    test "applies variant classes" do
      html_border =
        render_component(
          fn assigns ->
            ~H"""
            <.card variant={:border}>Content</.card>
            """
          end,
          %{}
        )

      html_dash =
        render_component(
          fn assigns ->
            ~H"""
            <.card variant={:dash}>Content</.card>
            """
          end,
          %{}
        )

      html_panel =
        render_component(
          fn assigns ->
            ~H"""
            <.card variant={:panel}>Content</.card>
            """
          end,
          %{}
        )

      assert html_border =~ "card-border"
      assert html_dash =~ "card-dash"
      assert html_panel =~ "backdrop-blur"
    end

    test "applies size classes" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card size={:lg}>Content</.card>
            """
          end,
          %{}
        )

      assert html =~ "card-lg"
    end

    test "merges custom classes" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card class="custom-class">Content</.card>
            """
          end,
          %{}
        )

      assert html =~ "custom-class"
    end

    test "applies id attribute" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.card id="test-card">Content</.card>
            """
          end,
          %{}
        )

      assert html =~ ~s(id="test-card")
    end
  end

  describe "card_rating/1" do
    test "renders rating buttons with correct events" do
      buttons = [
        %{score: 0, label: "Again", class: "btn-error"},
        %{score: 3, label: "Good", class: "btn-primary"}
      ]

      html = render_component(&CoreComponents.card_rating/1, item_id: 123, buttons: buttons)

      assert html =~ "Rate this card"
      assert html =~ "Again"
      assert html =~ "Good"
      assert html =~ ~s(phx-click="rate_word")
      assert html =~ ~s(phx-value-item-id="123")
      assert html =~ ~s(phx-value-quality="0")
      assert html =~ ~s(phx-value-quality="3")
    end

    test "uses custom event name" do
      buttons = [%{score: 3, label: "Good", class: "btn-primary"}]

      html =
        render_component(&CoreComponents.card_rating/1,
          item_id: 123,
          buttons: buttons,
          event: "custom_rate"
        )

      assert html =~ ~s(phx-click="custom_rate")
    end
  end

  describe "conjugation_table/1" do
    test "renders loading state when conjugations is nil" do
      html = render_component(&CoreComponents.conjugation_table/1, conjugations: nil)

      assert html =~ "Loading conjugations..."
    end

    test "renders empty state when conjugations is empty map" do
      html = render_component(&CoreComponents.conjugation_table/1, conjugations: %{})

      assert html =~ "Conjugations not available for this verb."
    end

    test "renders indicative mood tenses" do
      conjugations = %{
        "indicative" => %{
          "present" => %{
            "yo" => "hablo",
            "tú" => "hablas",
            "él/ella/usted" => "habla"
          }
        }
      }

      html = render_component(&CoreComponents.conjugation_table/1, conjugations: conjugations)

      assert html =~ "Conjugations"
      assert html =~ "Indicative"
      assert html =~ "present"
      assert html =~ "hablo"
      assert html =~ "hablas"
      assert html =~ "habla"
    end

    test "renders subjunctive mood tenses" do
      conjugations = %{
        "subjunctive" => %{
          "present" => %{
            "yo" => "hable",
            "tú" => "hables"
          }
        }
      }

      html = render_component(&CoreComponents.conjugation_table/1, conjugations: conjugations)

      assert html =~ "Subjunctive"
      assert html =~ "hable"
      assert html =~ "hables"
    end

    test "renders two-column layout for conjugation rows" do
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
        }
      }

      html = render_component(&CoreComponents.conjugation_table/1, conjugations: conjugations)

      assert html =~ "table"
      assert html =~ "Singular"
      assert html =~ "Plural"
      assert html =~ "yo"
      assert html =~ "nosotros/nosotras"
    end

    test "renders non-finite forms" do
      conjugations = %{
        "non_finite" => %{
          "infinitive" => "hablar",
          "gerund" => "hablando",
          "past_participle" => "hablado"
        }
      }

      html = render_component(&CoreComponents.conjugation_table/1, conjugations: conjugations)

      assert html =~ "Non-finite Forms"
      assert html =~ "Infinitive"
      assert html =~ "hablar"
      assert html =~ "Gerund"
      assert html =~ "hablando"
      assert html =~ "Past Participle"
      assert html =~ "hablado"
    end
  end
end
