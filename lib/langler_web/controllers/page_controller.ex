defmodule LanglerWeb.PageController do
  @moduledoc """
  Serves basic static pages.
  """

  use LanglerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
