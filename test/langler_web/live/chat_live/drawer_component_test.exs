defmodule LanglerWeb.ChatLive.DrawerComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Langler.Quizzes.Result
  alias LanglerWeb.ChatLive.Drawer
  alias Phoenix.Flash

  defp build_socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, messages: [], flash: %{}},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end

  describe "update/2" do
    test "assigns defaults when no action provided" do
      socket = build_socket()

      assert {:ok, updated} = Drawer.update(%{}, socket)
      assert updated.assigns.chat_open == false
      assert updated.assigns.sidebar_open == false
      assert updated.assigns.sending == false
      assert Map.has_key?(updated.assigns.streams, :messages)
    end

    test "handles add_assistant_message action" do
      socket = build_socket()

      message = %{
        id: 1,
        content: "Hello",
        inserted_at: DateTime.utc_now()
      }

      params = %{
        action: :add_assistant_message,
        message: message,
        tokens: 123
      }

      assert {:ok, updated} = Drawer.update(params, socket)
      assert updated.assigns.total_tokens == 123
      assert updated.assigns.sending == false

      stream = updated.assigns.streams.messages

      assert Enum.any?(stream.inserts, fn {_dom_id, _at, msg, _limit, _update_only} ->
               msg == message
             end)
    end

    test "marks quiz result when badge completes" do
      socket = build_socket()

      params = %{
        action: :add_assistant_message,
        message: assistant_message(),
        tokens: 5,
        quiz_result_action: :quiz_completed,
        quiz_result_map: %{
          "score" => 4,
          "max_score" => 5,
          "questions" => [
            %{
              "question" => "What is the capital?",
              "user_answer" => "Paris",
              "correct" => true,
              "explanation" => "Paris is the capital of France"
            }
          ]
        }
      }

      {:ok, updated} = Drawer.update(params, socket)

      assert updated.assigns.quiz_completed
      assert %Result{} = updated.assigns.quiz_result
    end

    test "surfaces quiz errors to the flash" do
      socket = build_socket()

      params = %{
        action: :add_assistant_message,
        message: assistant_message(),
        tokens: 2,
        quiz_result_action: {:quiz_error, "boom"}
      }

      {:ok, updated} = Drawer.update(params, socket)

      assert Flash.get(updated.assigns.flash, :error) =~ "boom"
    end
  end

  describe "assistant message UI" do
    test "renders copy and download buttons for assistant responses" do
      message = assistant_message(id: "assistant-1", content: "Hello world from assistant")

      html = render_drawer_with_message(message)
      dom_id = stream_dom_id(message.id)

      assert html =~ "id=\"copy-message-#{dom_id}\""
      assert html =~ "data-copy-text=\"Hello world from assistant\""
      assert html =~ "id=\"download-message-#{dom_id}\""
      assert html =~ "data-download-text=\"Hello world from assistant\""
      assert html =~ "data-download-filename=\"langler-response-#{dom_id}.txt\""
    end

    test "does not render actions for user messages" do
      message = assistant_message(id: "user-1", role: "user", content: "User text")

      html = render_drawer_with_message(message)
      dom_id = stream_dom_id(message.id)

      refute html =~ "id=\"copy-message-#{dom_id}\""
      refute html =~ "id=\"download-message-#{dom_id}\""
      refute html =~ "data-copy-text=\"#{message.content}\""
    end
  end

  defp assistant_message(attrs \\ %{}) do
    Map.merge(
      %{
        id: "assistant-2",
        role: "assistant",
        content: "Assistant quiz response",
        inserted_at: DateTime.utc_now()
      },
      Map.new(attrs)
    )
  end

  defp render_drawer_with_message(message) do
    myself = %Phoenix.LiveComponent.CID{cid: 1}
    dom_id = stream_dom_id(message.id)
    assigns = drawer_assigns(myself, dom_id, message)

    render_component(&Drawer.render/1, assigns)
  end

  defp stream_dom_id(message_id), do: "msg-#{message_id}"

  defp drawer_assigns(myself, dom_id, message) do
    %{
      chat_open: true,
      sidebar_open: false,
      keyboard_open: false,
      fullscreen: false,
      current_session: %{id: 1, title: "Test chat", target_language: "spanish"},
      studied_word_ids: MapSet.new(),
      studied_forms: MapSet.new(),
      streams: %{messages: [{dom_id, message}]},
      sending: false,
      llm_config_missing: false,
      total_tokens: 0,
      input_value: "",
      show_tokens: true,
      sessions: [],
      session_search: "",
      open_menu_id: nil,
      rename_input_value: nil,
      renaming_session_id: nil,
      messages: [],
      myself: myself,
      quiz_completed: false,
      quiz_result: nil
    }
  end
end
