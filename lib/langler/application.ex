defmodule Langler.Application do
  @moduledoc """
  OTP application entry point for Langler.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        LanglerWeb.Telemetry,
        Langler.Repo
      ] ++
        cache_loader_children() ++
        [
          {Oban, oban_config()},
          {DNSCluster, query: Application.get_env(:langler, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Langler.PubSub},
          Langler.Chat.RateLimiter,
          # Start a worker by calling: Langler.Worker.start_link(arg)
          # {Langler.Worker, arg},
          # Start to serve requests, typically the last entry
          LanglerWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Langler.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp oban_config do
    Application.fetch_env!(:langler, Oban)
  end

  defp cache_loader_children do
    loader_config = Application.get_env(:langler, Langler.External.Dictionary.CacheLoader, [])
    enabled? = Keyword.get(loader_config, :enabled, true)

    if enabled?, do: [Langler.External.Dictionary.CacheLoader], else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LanglerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
