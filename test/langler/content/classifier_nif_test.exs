defmodule Langler.Content.ClassifierNifTest do
  use ExUnit.Case, async: true

  alias Langler.Content.ClassifierNif

  test "train fails when the classifier nif is unavailable" do
    assert {:error, _} = capture_result(fn -> ClassifierNif.train(%{}) end)
  end

  test "classify fails when the classifier nif is unavailable" do
    assert {:error, _} = capture_result(fn -> ClassifierNif.classify("document", "{}") end)
  end

  defp capture_result(fun) do
    try do
      fun.()
    rescue
      error ->
        case error do
          %ErlangError{original: original} -> {:error, original}
          other -> {:error, other}
        end
    end
  end
end
