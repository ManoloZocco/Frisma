defmodule Pleroma.Web.MastodonAPI.TrendsView do
  @moduledoc """
  View per formattare gli hashtag di tendenza secondo lo standard dell'API di Mastodon.
  """
  use Pleroma.Web, :view

  alias Pleroma.Hashtag

  def render("index.json", %{trends: trends}) do
    render_many(trends, __MODULE__, "show.json", as: :trend)
  end

  def render("show.json", %{trend: %Hashtag{} = trend}) do
    %{
      name: trend.name,
      url: Pleroma.Web.Router.Helpers.tag_url(Pleroma.Web.Endpoint, :show, trend.name),
      history: format_history(trend.history),
      count: trend.count,
      account_count: trend.account_count
    }
  end

  defp format_history(history) when is_map(history) do
    case Map.get(history, "history") do
      history_list when is_list(history_list) ->
        # Formatta ogni punto dati dell'istogramma
        Enum.map(history_list, fn point ->
          %{
            "day" => Map.get(point, "day", ""),
            "uses" => Map.get(point, "uses", 0),
            "accounts" => Map.get(point, "accounts", 0)
          }
        end)
      _ -> []
    end
  end

  defp format_history(_), do: []
end