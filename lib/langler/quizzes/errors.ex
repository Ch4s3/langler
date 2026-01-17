defmodule Langler.Quizzes.Errors do
  @moduledoc """
  Structured error helpers for quiz operations.
  """

  defexception [:message, :type]

  @type t :: %__MODULE__{type: atom(), message: String.t()}

  @spec invalid_session() :: t()
  def invalid_session do
    %__MODULE__{type: :invalid_session, message: "Invalid quiz session"}
  end

  @spec missing_article_id() :: t()
  def missing_article_id do
    %__MODULE__{type: :missing_article_id, message: "Article ID is required for quiz operations"}
  end

  @spec invalid_result_format() :: t()
  def invalid_result_format do
    %__MODULE__{type: :invalid_result_format, message: "Quiz result format is invalid"}
  end
end
