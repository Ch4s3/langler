defmodule Langler.Quizzes.ResultParser do
  @moduledoc """
  Parses quiz result JSON from LLM assistant messages.

  The LLM emits quiz results in a delimited format:
  ```
  BEGIN_QUIZ_RESULT
  {"score": 4, "max_score": 5, "questions": [...]}
  END_QUIZ_RESULT
  ```

  This module extracts and validates the JSON structure and returns a Result struct.
  """

  alias Langler.Quizzes.Result

  @begin_marker "BEGIN_QUIZ_RESULT"
  @end_marker "END_QUIZ_RESULT"

  @doc """
  Extracts and parses quiz result JSON from assistant message content.

  Returns:
  - `{:ok, %Result{}}` - Successfully parsed result struct
  - `{:error, :not_found}` - Delimiters not found
  - `{:error, :invalid_json}` - JSON parse error
  - `{:error, :invalid_structure}` - JSON doesn't match expected structure
  - `{:error, :invalid_input}` - Input is not a string
  """
  def parse(content) when is_binary(content) do
    with {:ok, json_text} <- extract_json(content),
         {:ok, decoded} <- decode_json(json_text),
         {:ok, result} <- Result.from_map(decoded) do
      {:ok, result}
    else
      {:error, :invalid_question_structure} -> {:error, :invalid_structure}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse(_), do: {:error, :invalid_input}

  defp decode_json(json_text) do
    case Jason.decode(json_text) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp extract_json(content) do
    begin_marker = Regex.escape(@begin_marker)
    end_marker = Regex.escape(@end_marker)
    regex = Regex.compile!("#{begin_marker}\\s*(.+?)\\s*#{end_marker}", "is")

    case Regex.run(regex, content, capture: :all_but_first) do
      [json_text] -> {:ok, String.trim(json_text)}
      _ -> {:error, :not_found}
    end
  end
end
