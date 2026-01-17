defmodule LanglerWeb.ChatLive.SpecialCharactersKeyboard do
  @moduledoc """
  Functional component for the special characters keyboard.

  Displays language-specific special characters that can be inserted into the chat input.

  ## Assigns
    * `:target_language` - The target language for special characters (required)
    * `:myself` - Parent LiveComponent CID (required)
    * `:is_open` - Whether keyboard is visible (default: false)
  """
  use LanglerWeb, :html

  def special_characters_keyboard(assigns) do
    assigns = assign_new(assigns, :is_open, fn -> false end)

    ~H"""
    <div
      :if={@is_open}
      id="chat-keyboard"
      class="border-b border-base-200 bg-base-100 p-3"
    >
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs font-semibold text-base-content/60 uppercase tracking-wider">
          Special Characters
        </span>
        <button
          type="button"
          phx-click="toggle_keyboard"
          phx-target={@myself}
          class="btn btn-ghost btn-xs btn-square"
          aria-label="Hide keyboard"
        >
          <.icon name="hero-chevron-down" class="h-4 w-4" />
        </button>
      </div>
      <div class="flex flex-wrap gap-1.5 justify-center">
        <button
          :for={char <- get_special_chars(@target_language)}
          type="button"
          phx-click="insert_char"
          phx-value-char={char}
          phx-target={@myself}
          class="kbd kbd-sm hover:bg-primary hover:text-primary-content transition-colors cursor-pointer"
        >
          {char}
        </button>
      </div>
    </div>
    <div :if={!@is_open} class="px-4 pt-2">
      <button
        type="button"
        phx-click="toggle_keyboard"
        phx-target={@myself}
        class="btn btn-ghost btn-xs gap-1"
        aria-label="Show keyboard"
      >
        <.icon name="hero-chevron-up" class="h-4 w-4" />
        <span class="text-xs">Special Characters</span>
      </button>
    </div>
    """
  end

  defp get_special_chars("spanish"),
    do: ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡", "Á", "É", "Í", "Ó", "Ú", "Ñ", "Ü"]

  defp get_special_chars("french"),
    do: [
      "à",
      "â",
      "ä",
      "é",
      "è",
      "ê",
      "ë",
      "î",
      "ï",
      "ô",
      "ö",
      "ù",
      "û",
      "ü",
      "ÿ",
      "ç",
      "À",
      "Â",
      "Ä",
      "É",
      "È",
      "Ê",
      "Ë",
      "Î",
      "Ï",
      "Ô",
      "Ö",
      "Ù",
      "Û",
      "Ü",
      "Ÿ",
      "Ç"
    ]

  defp get_special_chars("german"), do: ["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"]

  defp get_special_chars("portuguese"),
    do: [
      "á",
      "à",
      "â",
      "ã",
      "é",
      "ê",
      "í",
      "ó",
      "ô",
      "õ",
      "ú",
      "ü",
      "ç",
      "Á",
      "À",
      "Â",
      "Ã",
      "É",
      "Ê",
      "Í",
      "Ó",
      "Ô",
      "Õ",
      "Ú",
      "Ü",
      "Ç"
    ]

  defp get_special_chars("italian"),
    do: [
      "à",
      "è",
      "é",
      "ì",
      "í",
      "î",
      "ò",
      "ó",
      "ù",
      "ú",
      "À",
      "È",
      "É",
      "Ì",
      "Í",
      "Î",
      "Ò",
      "Ó",
      "Ù",
      "Ú"
    ]

  defp get_special_chars(_), do: []
end
