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
      |> assign_new(:sidebar_open, fn -> false end)

    ~H"""
    <div class="p-4 bg-base-100/95 backdrop-blur-sm">
      <form phx-submit="send_message" phx-target={@myself} class="w-full">
        <div class="relative">
          <textarea
            name="message"
            value={@input_value}
            phx-change="update_input"
            phx-focus="close_sidebar"
            phx-target={@myself}
            placeholder={if @sidebar_open, do: "", else: "Type your message..."}
            rows="1"
            class="textarea textarea-bordered w-full rounded-2xl pr-14 py-3 resize-none min-h-[48px] max-h-[200px]"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            disabled={@llm_config_missing || @sending}
            oninput="this.style.height = 'auto'; this.style.height = Math.min(this.scrollHeight, 200) + 'px';"
          ></textarea>
          <button
            type="submit"
            class={[
              "absolute right-2 top-1/2 -translate-y-1/2 btn btn-primary btn-circle btn-xs sm:btn-sm shadow-lg hover:scale-110 transition-transform",
              @sidebar_open && "hidden"
            ]}
            disabled={@llm_config_missing || @input_value == "" || @sending}
            aria-label="Send message"
          >
            <%= if @sending do %>
              <span class="loading loading-spinner loading-sm"></span>
            <% else %>
              <.icon name="hero-paper-airplane" class="h-4 w-4" />
            <% end %>
          </button>
        </div>
      </form>

      <%!-- Token count display --%>
      <div :if={@show_tokens} class="mt-2 flex items-center justify-between">
        <span class="text-xs text-base-content/40">{@total_tokens} tokens</span>
      </div>
    </div>
    """
  end
end
