defmodule Mix.Tasks.QueryCurrentEra do
  use Mix.Task

  @shortdoc "Perform a local Cardano query"

  def run(_) do
    Application.ensure_all_started(:xander)
    Xander.get_current_era()
  end
end
