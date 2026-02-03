defmodule LanglerWeb.AudioLive.Player do
  @moduledoc """
  LiveView for audio player with subtitles and quiz integration.
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts.TtsConfig
  alias Langler.Audio
  alias Langler.Audio.AudioFile
  alias Langler.Audio.Storage
  alias Langler.Content
  alias Langler.Quizzes.Service
  alias Langler.Repo
  alias Langler.TTS.GenerateAudioJob
  alias Oban

  @impl true
  def mount(%{"id" => article_id_str}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    # Convert article_id to integer
    case Integer.parse(article_id_str) do
      {article_id, _} ->
        # Redirect to settings if TTS not configured
        if TtsConfig.tts_enabled?(user_id) do
          mount_with_tts(socket, user_id, article_id)
        else
          {:ok,
           socket
           |> put_flash(
             :info,
             gettext("Configure a Text-to-Speech provider to listen to articles")
           )
           |> push_navigate(to: ~p"/users/settings/tts")}
        end

      :error ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Invalid article ID"))
         |> push_navigate(to: ~p"/articles")}
    end
  end

  defp mount_with_tts(socket, user_id, article_id) when is_integer(article_id) do
    article = Content.get_article_for_user!(user_id, article_id)
    sentences = Content.list_sentences(article)
    audio_file = Audio.get_audio_file(user_id, article_id)
    initial_listening_position = listening_position(audio_file)

    # Enqueue generation if needed
    if audio_file == nil or audio_file.status == "pending" do
      {:ok, _} = Audio.get_or_create_audio_file(user_id, article_id)

      case Oban.insert(
             GenerateAudioJob.new(%{
               user_id: user_id,
               article_id: article_id
             })
           ) do
        {:ok, %Oban.Job{} = job} ->
          require Logger

          Logger.info(
            "Enqueued GenerateAudioJob for user_id=#{user_id}, article_id=#{article_id}, job_id=#{job.id}"
          )

        {:error, reason} ->
          require Logger
          Logger.error("Failed to enqueue GenerateAudioJob: #{inspect(reason)}")
      end
    end

    # Subscribe to audio ready notifications
    if audio_file == nil or audio_file.status == "pending" do
      Phoenix.PubSub.subscribe(Langler.PubSub, "audio:user:#{user_id}:article:#{article_id}")
    end

    socket =
      socket
      |> assign(:article, article)
      |> assign(:sentences, sentences)
      |> assign(:audio_file, audio_file)
      |> assign(:audio_url, get_audio_url(audio_file))
      |> assign(:initial_listening_position, initial_listening_position)
      |> assign(:current_sentence_idx, 0)
      |> assign(:subtitles_visible, false)
      |> assign(:playback_rate, 1.0)
      |> assign(:is_playing, false)
      |> assign(:audio_loading, audio_file == nil or audio_file.status == "pending")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl space-y-6 py-8">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-base-content">Listen to Article</h1>
            <p class="mt-2 text-sm text-base-content/70">
              {display_title(@article)}
            </p>
          </div>
          <.link navigate={~p"/articles/#{@article.id}"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Article
          </.link>
        </div>

        <div :if={@audio_loading} class="card border border-base-200 bg-base-100 shadow-xl">
          <div class="card-body text-center">
            <span class="loading loading-spinner loading-lg"></span>
            <p class="mt-4 text-base-content/70">Generating audio...</p>
            <p class="text-sm text-base-content/50">This may take a few moments</p>
          </div>
        </div>

        <%!-- Combined Audio Player & Subtitles --%>
        <div
          :if={!@audio_loading && @audio_url}
          class="card border border-base-200 bg-base-100 shadow-xl"
        >
          <div class="card-body p-6 space-y-6">
            <%!-- Player Controls (with phx-update ignore) --%>
            <div
              id="audio-player"
              phx-hook="AudioPlayer"
              phx-update="ignore"
              data-audio-url={@audio_url}
              data-playback-rate={@playback_rate}
              data-sentences={Jason.encode!(Enum.map(@sentences, &%{id: &1.id, content: &1.content}))}
              data-initial-position={@initial_listening_position}
            >
              <div class="flex flex-col gap-4">
                <div class="flex flex-wrap items-center gap-3 lg:grid lg:grid-cols-10">
                  <span
                    id="audio-time-current"
                    class="text-xs sm:text-sm font-mono text-base-content/70 lg:col-span-1"
                  >
                    0:00
                  </span>
                  <div class="flex-1 min-w-[180px] lg:col-span-8 lg:min-w-0">
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value="0"
                      class="range range-primary range-lg w-full"
                      id="audio-seek"
                    />
                  </div>
                  <span
                    id="audio-time-duration"
                    class="text-xs sm:text-sm font-mono text-base-content/70 lg:col-span-1 lg:text-right"
                  >
                    --:--
                  </span>
                </div>

                <div class="flex flex-col gap-4 lg:grid lg:grid-cols-10 lg:items-center">
                  <div class="flex items-center justify-center gap-4 lg:col-start-4 lg:col-span-4">
                    <button
                      type="button"
                      class="btn btn-circle btn-ghost btn-md sm:btn-sm lg:btn-xs audio-skip-back-button"
                      aria-label="Skip backward 10 seconds"
                    >
                      <.icon name="hero-arrow-uturn-left" class="h-5 w-5" />
                    </button>

                    <button
                      type="button"
                      class="btn btn-circle btn-primary btn-lg sm:btn-md lg:btn-sm audio-play-button shadow-lg hover:scale-110 transition-transform"
                      aria-label={if @is_playing, do: "Pause", else: "Play"}
                    >
                      <%= if @is_playing do %>
                        <.icon name="hero-pause" class="h-6 w-6" />
                      <% else %>
                        <.icon name="hero-play" class="h-6 w-6" />
                      <% end %>
                    </button>

                    <button
                      type="button"
                      class="btn btn-circle btn-ghost btn-md sm:btn-sm lg:btn-xs audio-skip-forward-button"
                      aria-label="Skip forward 10 seconds"
                    >
                      <.icon name="hero-arrow-uturn-right" class="h-5 w-5" />
                    </button>
                  </div>

                  <div class="flex flex-wrap items-center justify-center gap-3 lg:col-start-8 lg:col-span-3 lg:justify-end">
                    <.form
                      for={%{}}
                      as={:playback_rate}
                      phx-change="change_playback_rate"
                      phx-target="#audio-player"
                    >
                      <select
                        class="select select-bordered select-sm bg-base-100"
                        name="playback_rate[rate]"
                        value={@playback_rate}
                      >
                        <option value="0.5">0.5x</option>
                        <option value="1.0">1.0x</option>
                        <option value="1.5">1.5x</option>
                        <option value="2.0">2.0x</option>
                      </select>
                    </.form>

                    <div class="flex items-center gap-2">
                      <.icon name="hero-speaker-wave" class="h-4 w-4 text-base-content/60" />
                      <input
                        type="range"
                        min="0"
                        max="100"
                        value="100"
                        class="range range-secondary range-sm w-24"
                        id="audio-volume"
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Subtitles (Limited to 4 lines) --%>
            <div :if={@subtitles_visible} class="border-t border-base-300 pt-6 overflow-hidden">
              <div
                class="space-y-3 overflow-y-auto overflow-x-hidden"
                style="max-height: 24rem;"
                id="subtitles-container"
              >
                <p
                  :for={{sentence, idx} <- Enum.with_index(@sentences)}
                  class={[
                    "w-full p-3 rounded-xl transition-all duration-300 cursor-pointer text-base break-words",
                    if(idx == @current_sentence_idx,
                      do: [
                        "bg-primary/15 border-2 border-primary/40 text-primary",
                        "shadow-lg"
                      ],
                      else: [
                        "bg-base-200/50 border-2 border-transparent",
                        "hover:bg-base-200 hover:border-base-300"
                      ]
                    )
                  ]}
                  id={"sentence-#{idx}"}
                  data-sentence-index={idx}
                  data-active={idx == @current_sentence_idx}
                >
                  {sentence.content}
                </p>
              </div>
            </div>

            <%!-- Actions --%>
            <div class="flex flex-wrap items-center justify-between gap-4 border-t border-base-300 pt-6">
              <button type="button" class="btn btn-ghost" phx-click="toggle_subtitles">
                {if @subtitles_visible, do: "Hide Subtitles", else: "Show Subtitles"}
              </button>

              <div class="flex flex-wrap gap-3">
                <button type="button" class="btn btn-primary" phx-click="start_listening_quiz">
                  <.icon name="hero-academic-cap" class="h-5 w-5" /> Take Listening Quiz
                </button>

                <a href={@audio_url} download class="btn btn-outline">
                  <.icon name="hero-arrow-down-tray" class="h-5 w-5" /> Download
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={!@audio_loading && !@audio_url}
        class="card border border-base-200 bg-base-100 shadow-xl"
      >
        <div class="card-body text-center">
          <p class="text-base-content/70 mb-4">
            Audio generation failed. Please try again later.
          </p>
          <p
            :if={@audio_file && @audio_file.error_message}
            class="text-sm text-base-content/50 mb-4"
          >
            Error: {@audio_file.error_message}
          </p>
          <button
            type="button"
            class="btn btn-primary"
            phx-click="retry_audio_generation"
          >
            <.icon name="hero-arrow-path" class="h-4 w-4" /> Retry Generation
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("toggle_play", _, socket) do
    # Event is handled by JavaScript onclick handler
    {:noreply, socket}
  end

  def handle_event("toggle_subtitles", _, socket) do
    {:noreply, assign(socket, :subtitles_visible, !socket.assigns.subtitles_visible)}
  end

  def handle_event("change_playback_rate", %{"playback_rate" => %{"rate" => rate}}, socket) do
    playback_rate = String.to_float(rate)
    {:noreply, assign(socket, :playback_rate, playback_rate)}
  end

  def handle_event("sentence_changed", %{"index" => idx}, socket) do
    {:noreply, assign(socket, :current_sentence_idx, idx)}
  end

  def handle_event("audio_playing", _, socket) do
    {:noreply, assign(socket, :is_playing, true)}
  end

  def handle_event("audio_paused", _, socket) do
    {:noreply, assign(socket, :is_playing, false)}
  end

  def handle_event("audio_ended", _, socket) do
    {:noreply,
     socket
     |> assign(:is_playing, false)
     |> assign(:current_sentence_idx, 0)}
  end

  def handle_event("audio_loaded", _, socket) do
    {:noreply, assign(socket, :audio_loading, false)}
  end

  def handle_event("audio_load_error", %{"error" => error_code}, socket) do
    require Logger
    Logger.error("Audio player failed to load audio: error code #{error_code}")

    {:noreply,
     socket
     |> put_flash(:error, gettext("Failed to load audio file. Please try refreshing the page."))
     |> assign(:audio_loading, false)}
  end

  def handle_event("save_listening_position", %{"position_seconds" => position_param}, socket) do
    case parse_listening_position(position_param) do
      position when is_number(position) and position >= 0 ->
        _ =
          Audio.update_listening_position(
            socket.assigns.current_scope.user.id,
            socket.assigns.article.id,
            position
          )

      _ ->
        :noop
    end

    {:noreply, socket}
  end

  def handle_event("retry_audio_generation", _, socket) do
    user_id = socket.assigns.current_scope.user.id
    article_id = socket.assigns.article.id

    # Reset the audio file status to pending
    case Audio.get_audio_file(user_id, article_id) do
      nil ->
        {:ok, _} = Audio.get_or_create_audio_file(user_id, article_id)

      audio_file ->
        # Reset to pending status using AudioFile changeset
        audio_file
        |> AudioFile.changeset(%{status: "pending", error_message: nil})
        |> Repo.update()
    end

    # Enqueue a new job
    case Oban.insert(
           GenerateAudioJob.new(%{
             user_id: user_id,
             article_id: article_id
           })
         ) do
      {:ok, %Oban.Job{} = job} ->
        require Logger

        Logger.info(
          "Retried GenerateAudioJob for user_id=#{user_id}, article_id=#{article_id}, job_id=#{job.id}"
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Audio generation restarted. Please wait a moment."))
         |> assign(:audio_loading, true)
         |> assign(:audio_file, nil)
         |> assign(:audio_url, nil)
         |> assign(:initial_listening_position, 0)}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Failed to restart audio generation: %{reason}", reason: inspect(reason))
         )}
    end
  end

  def handle_event("start_listening_quiz", _, socket) do
    user = socket.assigns.current_scope.user
    article = socket.assigns.article
    topics = Content.list_topics_for_article(article.id)

    assigns = %{
      article_id: article.id,
      article_title: display_title(article),
      article_language: article.language,
      article_topics: Enum.map(topics, & &1.topic),
      article_content: article.content,
      context_type: "article_listening_quiz"
    }

    case Service.start_quiz_session(assigns, user) do
      {:ok, _session} ->
        send_update(LanglerWeb.ChatLive.Drawer,
          id: "chat-drawer",
          action: :start_article_quiz,
          article_id: article.id,
          article_title: display_title(article),
          article_language: article.language,
          article_topics: Enum.map(topics, & &1.topic),
          article_content: article.content
        )

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Failed to start quiz: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @impl true
  def handle_info({:audio_ready, audio_file}, socket) do
    # Unsubscribe since we got the audio
    Phoenix.PubSub.unsubscribe(
      Langler.PubSub,
      "audio:user:#{socket.assigns.current_scope.user.id}:article:#{socket.assigns.article.id}"
    )

    socket =
      socket
      |> assign(:audio_file, audio_file)
      |> assign(:audio_url, get_audio_url(audio_file))
      |> assign(:initial_listening_position, listening_position(audio_file))
      |> assign(:audio_loading, false)

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp get_audio_url(nil), do: nil

  defp get_audio_url(%{status: "ready", file_path: file_path}) when not is_nil(file_path),
    do: Storage.Local.public_url(file_path)

  defp get_audio_url(_), do: nil

  defp display_title(article) do
    if article.title && article.title != "" do
      article.title
    else
      URI.parse(article.url).host || "Article"
    end
  end

  defp parse_listening_position(position) when is_number(position), do: position

  defp parse_listening_position(position) when is_binary(position) do
    case Float.parse(position) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp parse_listening_position(_), do: nil

  defp listening_position(%AudioFile{last_position_seconds: last_position_seconds})
       when is_number(last_position_seconds) and last_position_seconds >= 0 do
    last_position_seconds
  end

  defp listening_position(_), do: 0.0
end
