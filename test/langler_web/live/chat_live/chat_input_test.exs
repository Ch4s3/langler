defmodule LanglerWeb.ChatLive.ChatInputTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LanglerWeb.ChatLive.ChatInput

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

  describe "chat_input/1" do
    test "renders input form" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself
        })

      document = document(html)

      assert has_selector?(document, "form[phx-submit='send_message']")
      assert has_selector?(document, "input[name='message'][value='Hello']")
      assert has_selector?(document, "button[type='submit']")
    end

    test "shows loading spinner when sending" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself,
          sending: true
        })

      document = document(html)

      assert has_selector?(document, "span.loading-spinner")
    end

    test "shows paper airplane icon when not sending" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself,
          sending: false
        })

      document = document(html)

      assert has_selector?(document, "span.hero-paper-airplane")
      refute has_selector?(document, "span.loading-spinner")
    end

    test "disables input when llm_config_missing" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself,
          llm_config_missing: true
        })

      document = document(html)

      assert has_selector?(document, "input[disabled]")
      assert has_selector?(document, "button[disabled]")
    end

    test "disables submit button when input is empty" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "",
          myself: myself
        })

      document = document(html)

      assert has_selector?(document, "button[disabled]")
    end

    test "shows token count when show_tokens is true" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself,
          total_tokens: 150,
          show_tokens: true
        })

      document = document(html)

      assert text_for(document, "div.mt-2 span") =~ "150 tokens"
    end

    test "hides token count when show_tokens is false" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatInput.chat_input/1, %{
          input_value: "Hello",
          myself: myself,
          total_tokens: 150,
          show_tokens: false
        })

      document = document(html)

      refute has_selector?(document, "div.mt-2 span")
    end
  end
end
