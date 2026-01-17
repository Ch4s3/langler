defmodule LanglerWeb.QuizComponents do
  @moduledoc """
  Reusable UI components for quiz functionality.
  """

  use Phoenix.Component

  import LanglerWeb.CoreComponents

  alias Langler.Quizzes.Result

  @doc """
  Renders a quiz score badge with color coding based on percentage.

  ## Examples

      <.quiz_score_badge result={@quiz_result} />
  """
  attr :result, Result, required: true, doc: "The quiz result struct"
  attr :class, :string, default: "badge badge-lg", doc: "Additional CSS classes"

  def quiz_score_badge(assigns) do
    ~H"""
    <span class={[@class, Langler.Quizzes.Result.badge_class(@result)]}>
      {@result.score}/{@result.max_score}
    </span>
    """
  end

  @doc """
  Renders a quiz percentage display.

  ## Examples

      <.quiz_percentage result={@quiz_result} />
  """
  attr :result, Result, required: true
  attr :class, :string, default: "text-xs text-base-content/60"

  def quiz_percentage(assigns) do
    ~H"""
    <span class={@class}>
      {Langler.Quizzes.Result.percentage(@result)}%
    </span>
    """
  end

  @doc """
  Renders a single quiz question card.

  ## Examples

      <.quiz_question_card question={question} index={idx} />
  """
  attr :question, :map,
    required: true,
    doc: "Question map with question, user_answer, correct, explanation"

  attr :index, :integer,
    required: true,
    doc: "Question index (0-based, will be displayed as index + 1)"

  def quiz_question_card(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-4 space-y-2 transition-all duration-300",
      if(@question["correct"],
        do: "border-success/30 bg-success/5",
        else: "border-error/30 bg-error/5"
      )
    ]}>
      <div class="flex items-start justify-between gap-2">
        <p class="text-sm font-semibold text-base-content flex-1">
          {@index + 1}. {@question["question"]}
        </p>
        <span class={[
          "badge badge-sm",
          if(@question["correct"], do: "badge-success", else: "badge-error")
        ]}>
          {if @question["correct"], do: "✓ Correct", else: "✗ Incorrect"}
        </span>
      </div>
      <div class="text-xs text-base-content/70">
        <p class="font-medium">Your answer:</p>
        <p class="ml-2 break-words">{@question["user_answer"]}</p>
      </div>
      <div class="text-xs text-base-content/80">
        <p class="font-medium">Explanation:</p>
        <p class="ml-2 break-words">{@question["explanation"]}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the complete quiz results display.

  ## Examples

      <.quiz_results result={@quiz_result} myself={@myself} />
  """
  attr :result, Result, required: true, doc: "The quiz result struct"
  attr :myself, Phoenix.LiveView.Component, required: true, doc: "The LiveComponent myself assign"

  def quiz_results(assigns) do
    ~H"""
    <div
      class="mt-6 rounded-2xl border-2 border-primary/30 bg-primary/5 p-6 space-y-4 animate-fade-in"
      phx-hook="QuizResults"
      id="quiz-results"
    >
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold text-base-content">Quiz Results</h3>
        <div class="flex items-center gap-2">
          <.quiz_score_badge result={@result} />
          <.quiz_percentage result={@result} />
        </div>
      </div>

      <div class="space-y-3">
        <.quiz_question_card
          :for={{question, idx} <- Enum.with_index(@result.questions || [])}
          question={question}
          index={idx}
        />
      </div>

      <div class="flex gap-2 pt-2">
        <button
          type="button"
          phx-click="finish_and_archive"
          phx-target={@myself}
          class="btn btn-primary btn-block gap-2"
        >
          <.icon name="hero-check-circle" class="h-5 w-5" /> Finish & Archive Article
        </button>
      </div>
    </div>
    """
  end
end
