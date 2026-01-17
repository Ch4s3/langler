defmodule LanglerWeb.ChatLive.EmptyStateTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LanglerWeb.ChatLive.EmptyState

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

  describe "empty_state/1" do
    test "renders empty state message" do
      html = render_component(&EmptyState.empty_state/1, %{})

      document = document(html)

      assert has_selector?(document, "span.hero-chat-bubble-left-right")
      assert text_for(document, "h4") =~ "Start a conversation"
      assert text_for(document, "p") =~ "Practice your target language with AI assistance"
    end

    test "shows LLM config warning when llm_config_missing is true" do
      html = render_component(&EmptyState.empty_state/1, %{llm_config_missing: true})

      document = document(html)

      assert has_selector?(document, "div.alert.alert-warning")
      assert has_selector?(document, "a[href='/users/settings/llm']")
    end

    test "hides LLM config warning when llm_config_missing is false" do
      html = render_component(&EmptyState.empty_state/1, %{llm_config_missing: false})

      document = document(html)

      refute has_selector?(document, "div.alert.alert-warning")
    end
  end
end
