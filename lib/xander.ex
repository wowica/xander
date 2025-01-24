defmodule Xander do
  @moduledoc false

  def get_current_era do
    Xander.Query.run(:get_current_era)
  end
end
