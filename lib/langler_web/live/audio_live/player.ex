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
           |> put_flash(:info, "Configure a Text-to-Speech provider to listen to articles")
           |> push_navigate(to: ~p"/users/settings/tts")}
        end

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid article ID")
         |> push_navigate(to: ~p"/articles")}
    end
  end

  defp mount_with_tts(socket, user_id, article_id) when is_integer(article_id) do
    article = Content.get_article_for_user!(user_id, article_id)
    sentences = Content.list_sentences(article)
    audio_file = Audio.get_audio_file(user_id, article_id)

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
      <div class="mx-auto max-w-4xl space-y-8 py-8">
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

        <div :if={!@audio_loading && @audio_url} class="space-y-6">
          <%!-- Audio Player and Subtitles --%>
          <div class="card border border-base-200 bg-base-100 shadow-xl">
            <div class="card-body">
              <%!-- Audio Controls (ignored by LiveView) --%>
              <div
                id="audio-player"
                phx-hook="AudioPlayer"
                phx-update="ignore"
                data-audio-url={@audio_url}
                data-playback-rate={@playback_rate}
                data-sentences={
                  Jason.encode!(Enum.map(@sentences, &%{id: &1.id, content: &1.content}))
                }
              >
                <div class="flex items-center gap-4">
                  <button
                    type="button"
                    class="btn btn-circle btn-primary audio-play-button"
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
                    class="btn btn-circle btn-ghost audio-skip-back-button"
                    aria-label="Skip backward 10 seconds"
                  >
                    <.icon name="hero-arrow-uturn-left" class="h-5 w-5" />
                  </button>

                  <span id="audio-time-display" class="text-sm font-mono min-w-[100px] text-center">
                    0:00 / 0:00
                  </span>

                  <div class="flex-1">
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value="0"
                      class="range range-primary"
                      id="audio-seek"
                    />
                  </div>

                  <button
                    type="button"
                    class="btn btn-circle btn-ghost audio-skip-forward-button"
                    aria-label="Skip forward 10 seconds"
                  >
                    <.icon name="hero-arrow-uturn-right" class="h-5 w-5" />
                  </button>

                  <div class="flex items-center gap-2">
                    <.form
                      for={%{}}
                      as={:playback_rate}
                      phx-change="change_playback_rate"
                      phx-target="#audio-player"
                    >
                      <select
                        class="select select-bordered select-sm"
                        name="playback_rate[rate]"
                        value={@playback_rate}
                      >
                        <option value="0.5">0.5x</option>
                        <option value="1.0">1.0x</option>
                        <option value="1.5">1.5x</option>
                        <option value="2.0">2.0x</option>
                      </select>
                    </.form>

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

              <%!-- Subtitles (updated by LiveView) --%>
              <div
                :if={@subtitles_visible}
                class="mt-6 space-y-2 overflow-y-auto"
                style="max-height: calc(4 * (1.5rem + 1.5rem) + 3 * 0.5rem);"
                id="subtitles-container"
              >
                <p
                  :for={{sentence, idx} <- Enum.with_index(@sentences)}
                  class={[
                    "p-3 rounded-lg transition",
                    if(idx == @current_sentence_idx,
                      do: "bg-primary/20 border-2 border-primary",
                      else: "bg-base-200"
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

            <%!-- Card Footer with Actions (updated by LiveView) --%>
            <div class="card-footer flex items-center justify-between p-4 border-t border-base-200">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="toggle_subtitles"
              >
                {if @subtitles_visible, do: "Hide", else: "Show"} Subtitles
              </button>

              <div class="flex gap-4">
                <button
                  type="button"
                  class="btn btn-primary btn-sm"
                  phx-click="start_listening_quiz"
                >
                  <.icon name="hero-academic-cap" class="h-4 w-4" /> Take Listening Quiz
                </button>

                <a
                  href={@audio_url}
                  download
                  class="btn btn-outline btn-sm"
                >
                  <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download Audio
                </a>
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
     |> put_flash(:error, "Failed to load audio file. Please try refreshing the page.")
     |> assign(:audio_loading, false)}
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
         |> put_flash(:info, "Audio generation restarted. Please wait a moment.")
         |> assign(:audio_loading, true)
         |> assign(:audio_file, nil)
         |> assign(:audio_url, nil)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to restart audio generation: #{inspect(reason)}")}
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
        {:noreply, put_flash(socket, :error, "Failed to start quiz: #{inspect(reason)}")}
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
end
