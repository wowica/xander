defmodule Xander do
  @moduledoc false

  def get_current_era do
    Xander.ClientStatem.query(:get_current_era)
  end
end
