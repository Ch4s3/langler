defmodule LanglerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: LanglerWeb.Gettext

  alias Phoenix.Component
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50 mt-16"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary soft outline)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary",
      "soft" => "btn-primary btn-soft",
      "outline" => "btn-outline",
      nil => "btn-primary"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [
          "btn transition-all duration-200 active:scale-[0.98] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary/40",
          Map.fetch!(variants, assigns[:variant])
        ]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={input_class(@class, @errors, @error_class, @type)}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp input_class(custom, errors, error_class, type) do
    [
      custom ||
        "w-full input transition-all duration-200 focus:ring-2 focus:ring-primary/40 focus:ring-offset-2",
      errors != [] && (error_class || "input-error"),
      type in ["url", "email", "text"] && "break-all"
    ]
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a responsive card grid.

  - Mobile/small screens: 1 column
  - Desktop (md: 768px+): 2 columns
  - Chat drawer open: 1 column (via CSS `body-chat-open` override)

  ## Examples

      <.card_grid>
        <.card :for={item <- @items}>...</.card>
      </.card_grid>

      <.card_grid id="articles" phx-update="stream">
        <.card :for={{id, article} <- @streams.articles} id={id}>...</.card>
      </.card_grid>
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-update)
  slot :inner_block, required: true

  def card_grid(assigns) do
    ~H"""
    <div
      id={@id}
      class={["grid gap-4 md:grid-cols-2 card-grid", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a card container with optional header and actions slots.

  Uses DaisyUI's card component classes. Supports multiple variants and
  optional hover effects for interactive cards.

  ## Variants

  - `:default` - Standard card with shadow (`card bg-base-100 shadow-xl`)
  - `:border` - Outlined card (`card card-border bg-base-100`)
  - `:dash` - Dashed border card (`card card-dash bg-base-100`)
  - `:panel` - Frosted glass effect (`card bg-base-100/95 shadow-xl backdrop-blur`)

  ## Examples

      <%!-- Basic card --%>
      <.card>
        <p>Card content</p>
      </.card>

      <%!-- Card with header and actions --%>
      <.card id="article-1" variant={:border} hover>
        <:header>
          <span class="badge badge-primary">New</span>
          <h3 class="card-title">Article Title</h3>
        </:header>

        <p class="text-sm text-base-content/70">Article preview...</p>

        <:actions>
          <.link navigate={~p"/articles/1"} class="btn btn-sm btn-primary">
            Read more
          </.link>
        </:actions>
      </.card>

      <%!-- Card with async loading content --%>
      <.card>
        <.async_result :let={data} assign={@async_data}>
          <:loading><span class="loading loading-spinner"></span></:loading>
          <:failed>Failed to load</:failed>
          <p>{data.content}</p>
        </.async_result>
      </.card>
  """
  attr :id, :string, default: nil, doc: "DOM id for the card element"
  attr :class, :string, default: nil, doc: "Additional CSS classes to merge"

  attr :variant, :atom,
    default: :default,
    values: [:default, :border, :dash, :panel],
    doc: "Card style variant"

  attr :size, :atom,
    default: nil,
    values: [nil, :xs, :sm, :md, :lg, :xl],
    doc: "Card size (maps to DaisyUI card-{size})"

  attr :hover, :boolean,
    default: false,
    doc: "Enable hover effects (translate + shadow)"

  attr :body_class, :string,
    default: nil,
    doc: "Additional classes for the card body wrapper"

  attr :rest, :global, doc: "Additional HTML attributes"

  slot :header, doc: "Optional header content (badges, title). Renders before main content."
  slot :inner_block, required: true, doc: "Main card content"

  slot :conjugations,
    doc: "Optional conjugations section. Renders after main content, before actions."

  slot :actions, doc: "Optional footer with action buttons. Wraps in card-actions div."

  def card(assigns) do
    variant_classes = %{
      default: "bg-base-100 shadow-lg border border-base-200/50",
      border: "card-border bg-base-100 border border-base-300",
      dash: "card-dash bg-base-100 border border-dashed border-base-300",
      panel: "bg-base-100/95 shadow-xl backdrop-blur border border-base-200/50"
    }

    size_classes = %{
      xs: "card-xs",
      sm: "card-sm",
      md: "card-md",
      lg: "card-lg",
      xl: "card-xl"
    }

    base_classes = ["card", Map.fetch!(variant_classes, assigns.variant)]

    size_class =
      if assigns.size do
        Map.fetch!(size_classes, assigns.size)
      else
        nil
      end

    hover_classes =
      if assigns.hover do
        "transition-all duration-300 hover:-translate-y-1 hover:shadow-2xl hover:border-primary/20"
      else
        nil
      end

    card_classes =
      [base_classes, size_class, hover_classes, assigns[:class]]
      |> List.flatten()
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(" ")

    assigns =
      assigns
      |> assign(:card_classes, card_classes)
      |> assign_new(:header, fn -> [] end)
      |> assign_new(:conjugations, fn -> [] end)
      |> assign_new(:actions, fn -> [] end)

    ~H"""
    <div id={@id} class={@card_classes} {@rest}>
      <div class={["card-body", @body_class]}>
        <%= if @header != [] do %>
          <div>
            {render_slot(@header)}
          </div>
        <% end %>

        {render_slot(@inner_block)}

        <%= if @conjugations != [] do %>
          <div>
            {render_slot(@conjugations)}
          </div>
        <% end %>

        <%= if @actions != [] do %>
          <div class="card-actions">
            {render_slot(@actions)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a row of FSRS rating buttons for study cards.

  Displays Again/Hard/Good/Easy buttons that trigger rating events.
  Designed to be placed in the `:actions` slot of a card.

  ## Examples

      <.card_rating
        item_id={@item.id}
        buttons={[
          %{score: 0, label: "Again", class: "btn-error"},
          %{score: 2, label: "Hard", class: "btn-warning"},
          %{score: 3, label: "Good", class: "btn-primary"},
          %{score: 4, label: "Easy", class: "btn-success"}
        ]}
      />
  """
  attr :buttons, :list,
    required: true,
    doc: "List of button configs with :score, :label, and :class keys"

  attr :item_id, :any,
    required: true,
    doc: "The item ID to rate (passed as phx-value-item-id)"

  attr :event, :string,
    default: "rate_word",
    doc: "The event name to fire on click (default: 'rate_word')"

  def card_rating(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <p class="text-xs font-semibold uppercase tracking-widest text-base-content/60 text-center">
        Rate this card
      </p>
      <div class="flex flex-wrap gap-3 justify-center">
        <button
          :for={button <- @buttons}
          type="button"
          class={[
            "btn font-semibold text-white transition-all duration-200 min-h-[56px] px-6 rounded-full",
            "hover:-translate-y-1 hover:shadow-xl active:translate-y-0 active:scale-[0.98]",
            "focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary/40",
            "phx-click-loading:opacity-70 phx-click-loading:cursor-wait",
            button.class
          ]}
          phx-click={@event}
          phx-value-item-id={@item_id}
          phx-value-quality={button.score}
        >
          {button.label}
        </button>
      </div>
    </div>
    """
  end

  def card_rating_mobile(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 w-full md:flex-none">
      <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60 text-center pt-2">
        Rate this card
      </p>
      <div class="grid grid-cols-2 gap-4 px-4 pb-4 md:grid-cols-4 md:px-0 md:pb-0">
        <button
          :for={button <- @buttons}
          type="button"
          class={[
            "btn font-semibold text-white transition-all duration-200 h-20 w-full rounded-2xl text-base",
            "hover:brightness-110 active:scale-[0.96]",
            "focus-visible:ring-2 focus-visible:ring-offset-1 focus-visible:ring-primary/40",
            "phx-click-loading:opacity-70 phx-click-loading:cursor-wait",
            button.class
          ]}
          phx-click={@event}
          phx-value-item-id={@item_id}
          phx-value-quality={button.score}
        >
          {button.label}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a verb conjugation table with moods and tenses.

  Displays conjugations in a two-column layout (singular/plural).
  Handles loading, empty, and populated states gracefully.

  ## States

  - `nil` conjugations - Shows "Loading conjugations..." message
  - Empty map `%{}` - Shows "Conjugations not available" message
  - Populated map - Renders full conjugation tables by mood

  ## Examples

      <%!-- Static conjugations --%>
      <.conjugation_table conjugations={@word.conjugations} />

      <%!-- With async loading --%>
      <.async_result :let={conjugations} assign={@conjugations}>
        <:loading><span class="loading loading-spinner"></span></:loading>
        <:failed>Failed to load conjugations</:failed>
        <.conjugation_table conjugations={conjugations} />
      </.async_result>
  """
  attr :conjugations, :any,
    default: nil,
    doc: "Conjugations map or nil for loading state"

  def conjugation_table(%{conjugations: nil} = assigns) do
    ~H"""
    <p class="text-sm text-base-content/70">Loading conjugations...</p>
    """
  end

  def conjugation_table(%{conjugations: %{}} = assigns)
      when map_size(assigns.conjugations) == 0 do
    ~H"""
    <p class="text-sm text-base-content/70">Conjugations not available for this verb.</p>
    """
  end

  def conjugation_table(assigns) do
    ~H"""
    <div class="space-y-6">
      <h3 class="text-lg font-semibold text-base-content">Conjugations</h3>

      <%= if Map.has_key?(@conjugations, "indicative") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Indicative</h4>
          {render_mood(assigns, @conjugations["indicative"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "subjunctive") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Subjunctive</h4>
          {render_mood(assigns, @conjugations["subjunctive"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "imperative") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Imperative</h4>
          {render_mood(assigns, @conjugations["imperative"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "non_finite") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Non-finite Forms</h4>
          <div class="grid grid-cols-3 gap-2 text-sm">
            <%= if Map.has_key?(@conjugations["non_finite"], "infinitive") do %>
              <div>
                <span class="font-semibold text-base-content/70">Infinitive:</span>
                <span class="ml-2">{@conjugations["non_finite"]["infinitive"]}</span>
              </div>
            <% end %>
            <%= if Map.has_key?(@conjugations["non_finite"], "gerund") do %>
              <div>
                <span class="font-semibold text-base-content/70">Gerund:</span>
                <span class="ml-2">{@conjugations["non_finite"]["gerund"]}</span>
              </div>
            <% end %>
            <%= if Map.has_key?(@conjugations["non_finite"], "past_participle") do %>
              <div>
                <span class="font-semibold text-base-content/70">Past Participle:</span>
                <span class="ml-2">{@conjugations["non_finite"]["past_participle"]}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_mood(assigns, mood_conjugations) when is_map(mood_conjugations) do
    assigns = assign(assigns, :mood_conjugations, mood_conjugations)

    ~H"""
    <div class="space-y-4">
      <%= for {tense, forms} <- @mood_conjugations do %>
        <div class="space-y-2">
          <h5 class="text-sm font-semibold text-base-content/70 capitalize">{tense}</h5>
          {render_two_column_conjugations(assigns, forms)}
        </div>
      <% end %>
    </div>
    """
  end

  defp render_mood(assigns, _) do
    ~H"""
    <p class="text-sm text-base-content/70">No conjugations available.</p>
    """
  end

  defp render_two_column_conjugations(assigns, forms) do
    assigns = assign(assigns, :forms, forms)

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm whitespace-normal conjugation-table">
        <tbody>
          <tr class="bg-base-200/60 text-xs uppercase tracking-widest text-base-content/60">
            <th class="w-32">Singular</th>
            <th>Conjugation</th>
            <th class="w-32">Plural</th>
            <th>Conjugation</th>
          </tr>
          <%= for row <- conjugation_rows(@forms) do %>
            <tr class="align-top">
              <td class={["conjugation-person", "pair-left"]}>{row.left.person}</td>
              <td class={["conjugation-form", "pair-left"]}>{row.left.form}</td>
              <td class={["conjugation-person", "pair-right"]}>{row.right.person}</td>
              <td class={["conjugation-form", "pair-right"]}>{row.right.form}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp conjugation_rows(forms) do
    singular = [
      {"yo", Map.get(forms, "yo")},
      {"tú", Map.get(forms, "tú")},
      {"él/ella/usted", Map.get(forms, "él/ella/usted")}
    ]

    plural = [
      {"nosotros/nosotras", Map.get(forms, "nosotros/nosotras")},
      {"vosotros/vosotras", Map.get(forms, "vosotros/vosotras")},
      {"ellos/ellas/ustedes", Map.get(forms, "ellos/ellas/ustedes")}
    ]

    singular
    |> Enum.zip(plural)
    |> Enum.map(fn {{s_person, s_form}, {p_person, p_form}} ->
      %{
        left: %{person: s_person, form: s_form || "—"},
        right: %{person: p_person, form: p_form || "—"}
      }
    end)
  end

  @doc """
  Renders a search input with icon and clear button.

  ## Examples

      <.search_input
        id="article-search"
        value={@query}
        placeholder="Search articles..."
        event="search"
        clear_event="clear_search"
      />
  """
  attr :id, :string, required: true, doc: "unique DOM id for the search input"
  attr :value, :string, default: "", doc: "current search value"
  attr :placeholder, :string, default: "Search...", doc: "placeholder text"
  attr :event, :string, required: true, doc: "phx-change event name"
  attr :clear_event, :string, required: true, doc: "phx-click event for clear button"
  attr :debounce, :integer, default: 300, doc: "debounce time in milliseconds"
  attr :class, :string, default: nil, doc: "additional CSS classes for wrapper"
  attr :rest, :global, include: ~w(disabled autocomplete)

  def search_input(assigns) do
    ~H"""
    <form phx-change={@event} class={["flex items-center gap-2", @class]}>
      <label class="input input-bordered flex items-center gap-2 w-full focus-within:ring focus-within:ring-primary/30">
        <.icon name="hero-magnifying-glass" class="h-4 w-4 text-base-content/60 shrink-0" />
        <input
          type="text"
          id={@id}
          name="q"
          value={@value}
          placeholder={@placeholder}
          phx-debounce={to_string(@debounce)}
          autocomplete="off"
          class="grow border-none outline-none"
          aria-label={@placeholder}
          {@rest}
        />
        <button
          :if={@value != ""}
          type="button"
          class="btn btn-ghost btn-xs shrink-0"
          phx-click={@clear_event}
          aria-label="Clear search"
        >
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
      </label>
    </form>
    """
  end

  @doc """
  Renders an empty state message with optional title, description, and actions.

  ## Examples

      <.list_empty_state id="articles-empty" class="col-span-3">
        <:title>No articles found</:title>
        <:description>Try adjusting your search or filters.</:description>
        <:actions>
          <button phx-click="clear_search">Clear search</button>
        </:actions>
      </.list_empty_state>
  """
  attr :id, :string, required: true, doc: "DOM id for the empty state container"
  attr :class, :string, default: nil, doc: "additional CSS classes"
  attr :rest, :global

  slot :title, required: true, doc: "main heading text"
  slot :description, doc: "supporting description text"
  slot :actions, doc: "action buttons or links"

  def list_empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex flex-col items-center justify-center rounded-3xl border border-dashed border-base-300 bg-base-100/80 px-8 py-10 text-center text-base-content/70",
        @class
      ]}
      {@rest}
    >
      <p class="text-lg font-semibold text-base-content">
        {render_slot(@title)}
      </p>
      <p :if={@description != []} class="text-sm mt-2">
        {render_slot(@description)}
      </p>
      <div :if={@actions != []} class="mt-4 flex flex-wrap justify-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading spinner with optional text.

  ## Examples

      <.spinner size={:sm} text="Loading..." />
      <.spinner />
  """
  attr :size, :atom, default: :sm, values: [:xs, :sm, :md, :lg], doc: "spinner size"
  attr :text, :string, default: nil, doc: "optional loading text"
  attr :class, :string, default: nil, doc: "additional CSS classes"

  def spinner(assigns) do
    assigns = assign(assigns, :size_class, "loading-#{assigns.size}")

    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <span class={["loading loading-spinner", @size_class]}></span>
      <span :if={@text} class="text-sm text-base-content/70">{@text}</span>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(LanglerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LanglerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a deck selector dropdown.

  ## Examples

      <.deck_selector
        decks={@decks}
        current_deck={@current_deck}
        event="set_current_deck"
      />
  """
  attr :decks, :list, required: true, doc: "List of deck structs"
  attr :current_deck, :map, default: nil, doc: "Currently selected deck"
  attr :event, :string, default: "set_current_deck", doc: "Event name to trigger on selection"
  attr :class, :string, default: "", doc: "Additional CSS classes"
  attr :show_all_option, :boolean, default: false, doc: "Show 'All decks' option at the top"

  def deck_selector(assigns) do
    ~H"""
    <div class={["dropdown dropdown-bottom dropdown-end", @class]}>
      <div
        tabindex="0"
        role="button"
        class="btn btn-sm btn-outline w-full sm:w-auto"
      >
        {if @current_deck, do: @current_deck.name, else: "All decks"}
        <.icon name="hero-chevron-down" class="ml-2 h-4 w-4" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 border border-base-300 p-2 shadow-lg"
      >
        <%= if @show_all_option do %>
          <li>
            <button
              type="button"
              phx-click={@event}
              phx-value-deck_id=""
              class={[
                "flex items-center justify-between",
                is_nil(@current_deck) && "active"
              ]}
            >
              <span>All decks</span>
              <%= if is_nil(@current_deck) do %>
                <.icon name="hero-check" class="h-4 w-4" />
              <% end %>
            </button>
          </li>
        <% end %>
        <li :for={deck <- @decks}>
          <button
            type="button"
            phx-click={@event}
            phx-value-deck_id={deck.id}
            class={[
              "flex items-center justify-between",
              @current_deck && @current_deck.id == deck.id && "active"
            ]}
          >
            <span>
              {deck.name}
              <%= if deck.is_default do %>
                <span class="badge badge-xs badge-primary ml-2">Default</span>
              <% end %>
            </span>
            <%= if @current_deck && @current_deck.id == deck.id do %>
              <.icon name="hero-check" class="h-4 w-4" />
            <% end %>
          </button>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders a settings page layout with title, subtitle, and back link.

  ## Examples

      <.settings_page title="LLM Settings" subtitle="Configure your AI provider." back_path={~p"/users/settings"}>
        <div>Settings content...</div>
      </.settings_page>
  """
  attr :title, :string, required: true, doc: "Page title"
  attr :subtitle, :string, required: true, doc: "Short description below the title"
  attr :back_path, :any, required: true, doc: "Path or navigate target for the back link"
  attr :class, :string, default: "", doc: "Additional CSS classes for the outer wrapper"
  slot :inner_block, required: true, doc: "Main content below the header"

  def settings_page(assigns) do
    ~H"""
    <div class={["mx-auto max-w-4xl space-y-8 py-8", @class]}>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-3xl font-bold text-base-content">{@title}</h1>
          <p class="mt-2 text-sm text-base-content/70">{@subtitle}</p>
        </div>
        <.link navigate={@back_path} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Settings
        </.link>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a card listing configurations with an empty state when the list is empty.

  Use the `:item` slot with `:let={config}` to render each config.

  ## Examples

      <.config_list_card
        title="Your LLM Configurations"
        empty_icon="hero-chat-bubble-left-right"
        empty_title="No LLM configurations yet."
        empty_hint="Add your first API key below to get started."
        configs={@configs}
      >
        <:item :let={config}>
          <div>{config.name}</div>
        </:item>
      </.config_list_card>
  """
  attr :title, :string, required: true, doc: "Card title"

  attr :empty_icon, :string,
    required: true,
    doc: "Heroicon name for empty state (e.g. hero-chat-bubble-left-right)"

  attr :empty_title, :string, required: true, doc: "Message when configs list is empty"
  attr :empty_hint, :string, required: true, doc: "Hint text below empty title"
  attr :configs, :list, default: [], doc: "List of config structs"

  slot :item,
    required: true,
    doc: "Renders one config item; use :let={config} to receive each item"

  def config_list_card(assigns) do
    ~H"""
    <div class="card border border-base-200 bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">{@title}</h2>

        <div :if={@configs == []} class="py-8 text-center">
          <.icon name={@empty_icon} class="mx-auto h-12 w-12 text-base-content/30" />
          <p class="mt-4 text-base-content/70">{@empty_title}</p>
          <p class="text-sm text-base-content/50">{@empty_hint}</p>
        </div>

        <div :if={@configs != []} class="space-y-4">
          <div
            :for={config <- @configs}
            class="rounded-lg border border-base-200 bg-base-50 p-4"
          >
            {render_slot(@item, config)}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
