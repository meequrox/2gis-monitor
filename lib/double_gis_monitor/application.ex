defmodule DoubleGisMonitor.Application do
  @moduledoc """
  The main application to start a supervisor.
  """

  use Application

  require Logger

  @doc """
  Called when an application is started (usually from `Mix.Project.application/0`).
  This callback is responsible for starting its supervision tree.
  """
  @impl true
  def start(_type, [opts]) do
    Logger.info("Working directory: #{File.cwd!()}")

    opts
    |> get_children()
    |> Supervisor.start_link(strategy: :one_for_one, name: __MODULE__.Supervisor)
  end

  defp get_children(%{env: env} = opts) when is_atom(env) do
    base = [
      get_migrator(opts),
      DoubleGisMonitor.Database.Repo
    ]

    rest =
      case env do
        :test ->
          []

        _other ->
          [
            DoubleGisMonitor.Bot.Telegram,
            DoubleGisMonitor.Pipeline.Worker,
            DoubleGisMonitor.Pipeline.WorkerManager
          ]
      end

    base ++ rest
  end

  defp get_migrator(%{env: env, ecto_repos: repos}) when is_atom(env) and is_list(repos) do
    {Ecto.Migrator,
     repos: repos,
     skip: System.get_env("SKIP_MIGRATIONS", "false") == "true",
     log_migrator_sql: env != :prod}
  end
end
