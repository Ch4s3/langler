defmodule LanglerWeb.PageController do
  use LanglerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
