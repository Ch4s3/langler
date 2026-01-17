defmodule LanglerWeb.ChatLive.EmptyState do
  @moduledoc """
  Functional component for the empty chat state when no session is selected.

  ## Assigns
    * `:llm_config_missing` - Whether LLM config is missing (default: false)
  """
  use LanglerWeb, :html

  def empty_state(assigns) do
    assigns = assign_new(assigns, :llm_config_missing, fn -> false end)

    ~H"""
    <div class="flex h-full flex-col items-center justify-center gap-4 text-center">
      <.icon name="hero-chat-bubble-left-right" class="h-16 w-16 text-base-content/20" />
      <div>
        <h4 class="text-lg font-semibold text-base-content">Start a conversation</h4>
        <p class="text-sm text-base-content/60">
          Practice your target language with AI assistance
        </p>
      </div>

      <%= if @llm_config_missing do %>
        <div class="alert alert-warning max-w-md">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <div class="text-left">
            <p class="font-semibold">LLM Configuration Required</p>
            <p class="text-sm">
              Please configure your LLM provider in
              <.link navigate={~p"/users/settings/llm"} class="link">settings</.link>
              to start chatting.
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
