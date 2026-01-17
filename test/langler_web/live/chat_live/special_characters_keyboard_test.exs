defmodule LanglerWeb.ChatLive.SpecialCharactersKeyboardTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LanglerWeb.ChatLive.SpecialCharactersKeyboard

  defp document(html), do: LazyHTML.from_fragment(html)

  defp has_selector?(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.any?()
  end

  defp text_for(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end

  describe "special_characters_keyboard/1" do
    test "renders keyboard when is_open is true" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SpecialCharactersKeyboard.special_characters_keyboard/1, %{
          target_language: "spanish",
          myself: myself,
          is_open: true
        })

      document = document(html)

      assert has_selector?(document, "#chat-keyboard")
      assert text_for(document, "#chat-keyboard") =~ "Special Characters"
      assert text_for(document, "#chat-keyboard") =~ "á"
      assert text_for(document, "#chat-keyboard") =~ "ñ"
      assert text_for(document, "#chat-keyboard") =~ "¿"
    end

    test "renders toggle button when is_open is false" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SpecialCharactersKeyboard.special_characters_keyboard/1, %{
          target_language: "spanish",
          myself: myself,
          is_open: false
        })

      document = document(html)

      assert text_for(document, "button[aria-label='Show keyboard']") =~ "Special Characters"
      assert has_selector?(document, "button[phx-click='toggle_keyboard']")
      refute has_selector?(document, "#chat-keyboard")
    end

    test "shows correct characters for spanish" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SpecialCharactersKeyboard.special_characters_keyboard/1, %{
          target_language: "spanish",
          myself: myself,
          is_open: true
        })

      document = document(html)

      assert text_for(document, "#chat-keyboard") =~ "á"
      assert text_for(document, "#chat-keyboard") =~ "é"
      assert text_for(document, "#chat-keyboard") =~ "í"
      assert text_for(document, "#chat-keyboard") =~ "ó"
      assert text_for(document, "#chat-keyboard") =~ "ú"
      assert text_for(document, "#chat-keyboard") =~ "ñ"
      assert text_for(document, "#chat-keyboard") =~ "¿"
      assert text_for(document, "#chat-keyboard") =~ "¡"
    end

    test "shows correct characters for french" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SpecialCharactersKeyboard.special_characters_keyboard/1, %{
          target_language: "french",
          myself: myself,
          is_open: true
        })

      document = document(html)

      assert text_for(document, "#chat-keyboard") =~ "à"
      assert text_for(document, "#chat-keyboard") =~ "é"
      assert text_for(document, "#chat-keyboard") =~ "ç"
      assert text_for(document, "#chat-keyboard") =~ "ü"
    end

    test "shows empty for unknown language" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SpecialCharactersKeyboard.special_characters_keyboard/1, %{
          target_language: "unknown",
          myself: myself,
          is_open: true
        })

      document = document(html)

      assert has_selector?(document, "#chat-keyboard")
      refute has_selector?(document, "button.kbd")
    end
  end
end
