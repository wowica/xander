defmodule Xander do
  @moduledoc false

  def get_current_era do
    # Xander.Client.query(:get_current_era) |> IO.inspect()
    # Xander.Client.query(:get_current_era) |> IO.inspect()
    # Xander.Client.query(:get_current_era) |> IO.inspect()
    Xander.ClientStatem.query(:get_current_era) |> IO.inspect()
    Xander.ClientStatem.query(:get_current_era) |> IO.inspect()
    Xander.ClientStatem.query(:get_current_era) |> IO.inspect()
  end
end
