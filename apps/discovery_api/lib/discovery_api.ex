defmodule DiscoveryApi do
  @moduledoc false
  def instance(), do: :discovery_api

  def prestige_opts(), do: Application.get_env(:prestige, :session_opts)
end
