defmodule Langler.Quizzes.StateTest do
  use ExUnit.Case, async: true

  alias Langler.Quizzes.{Result, State}

  describe "init/1" do
    test "adds quiz defaults to the socket" do
      socket = %Phoenix.LiveView.Socket{}

      socket = State.init(socket)

      assert socket.assigns.quiz_completed == false
      assert socket.assigns.quiz_result == nil
    end
  end

  describe "mark_completed/2" do
    test "marks the quiz as completed and stores the result" do
      result = %Result{score: 5, max_score: 5}
      socket = %Phoenix.LiveView.Socket{}

      socket = State.mark_completed(socket, result)

      assert socket.assigns.quiz_completed
      assert socket.assigns.quiz_result == result
    end
  end

  describe "reset/1" do
    test "clears the quiz state" do
      socket =
        %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            quiz_completed: true,
            quiz_result: %Result{score: 2, max_score: 3}
          }
        }

      socket = State.reset(socket)

      assert socket.assigns.quiz_completed == false
      assert socket.assigns.quiz_result == nil
    end
  end
end
