defmodule Dashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DashboardWeb.Telemetry,
      Dashboard.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:dashboard, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dashboard.PubSub},
      Dashboard.RSS.Scheduler,
      Supervisor.child_spec(
        {PartitionSupervisor,
         child_spec: Dashboard.SSR.Worker,
         name: Dashboard.SSR.Worker.Pool,
         partitions:
           Application.get_env(:dashboard, Dashboard.SSR.Worker)[:pool_size] ||
             System.schedulers_online()},
        # When the pool exhausts its own max_restarts, let it die quietly
        # rather than crashing the Phoenix application. SSR degrades to CSR.
        restart: :temporary
      ),
      # Start a worker by calling: Dashboard.Worker.start_link(arg)
      # {Dashboard.Worker, arg},
      # Start to serve requests, typically the last entry
      DashboardWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
