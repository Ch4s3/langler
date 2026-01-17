defmodule LanglerWeb.ChatLive.ChatInput do
  @moduledoc """
  Functional component for the chat message input form.

  ## Assigns
    * `:input_value` - Current input value (default: "")
    * `:sending` - Whether currently sending (default: false)
    * `:llm_config_missing` - Whether LLM config is missing (default: false)
    * `:total_tokens` - Token count to display (default: 0)
    * `:show_tokens` - Whether to show token count (default: true)
    * `:myself` - Parent LiveComponent CID (required)
  """
  use LanglerWeb, :html

  def chat_input(assigns) do
    assigns =
      assigns
      |> assign_new(:input_value, fn -> "" end)
      |> assign_new(:sending, fn -> false end)
      |> assign_new(:llm_config_missing, fn -> false end)
      |> assign_new(:total_tokens, fn -> 0 end)
      |> assign_new(:show_tokens, fn -> true end)

    ~H"""
    <div class="p-4">
      <form phx-submit="send_message" phx-target={@myself} class="flex gap-2">
        <input
          type="text"
          name="message"
          value={@input_value}
          phx-change="update_input"
          phx-target={@myself}
          placeholder="Type your message..."
          class="input input-bordered flex-1"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
          spellcheck="false"
          disabled={@llm_config_missing || @sending}
        />
        <button
          type="submit"
          class="btn btn-primary"
          disabled={@llm_config_missing || @input_value == "" || @sending}
        >
          <%= if @sending do %>
            <span class="loading loading-spinner loading-sm"></span>
          <% else %>
            <.icon name="hero-paper-airplane" class="h-5 w-5" />
          <% end %>
        </button>
      </form>

      <%!-- Token count display --%>
      <div :if={@show_tokens} class="mt-2 text-right">
        <span class="text-xs text-base-content/40">{@total_tokens} tokens</span>
      </div>
    </div>
    """
  end
end
