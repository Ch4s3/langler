defmodule Langler.Quizzes.State do
  @moduledoc """
  Centralized quiz state management for LiveView assigns.

  Provides functions to initialize, update, and reset quiz state
  in a consistent way across the application.
  """

  alias Langler.Quizzes.Result

  @doc """
  Initializes quiz state in a socket.

  Sets default values for quiz-related assigns.
  """
  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    socket
    |> Phoenix.Component.assign_new(:quiz_completed, fn -> false end)
    |> Phoenix.Component.assign_new(:quiz_result, fn -> nil end)
  end

  @doc """
  Marks quiz as completed with a result.

  Updates the socket with quiz completion state and result.
  """
  @spec mark_completed(Phoenix.LiveView.Socket.t(), Result.t()) ::
          Phoenix.LiveView.Socket.t()
  def mark_completed(socket, %Result{} = result) do
    socket
    |> Phoenix.Component.assign(:quiz_completed, true)
    |> Phoenix.Component.assign(:quiz_result, result)
  end

  @doc """
  Resets quiz state.

  Clears quiz completion status and result.
  """
  @spec reset(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reset(socket) do
    socket
    |> Phoenix.Component.assign(:quiz_completed, false)
    |> Phoenix.Component.assign(:quiz_result, nil)
  end
end
