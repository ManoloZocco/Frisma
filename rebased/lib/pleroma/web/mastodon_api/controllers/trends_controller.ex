defmodule Pleroma.Web.MastodonAPI.TrendsController do
  @moduledoc """
  Controller che gestisce le tendenze per l'API compatibile con Mastodon.
  Fornisce gli hashtag di tendenza calcolati dal worker.
  """
  use Pleroma.Web, :controller

  alias Pleroma.Config
  alias Pleroma.Repo
  alias Pleroma.Hashtag
  import Ecto.Query

  action_fallback(Pleroma.Web.MastodonAPI.FallbackController)

  # GET /api/v1/trends
  def index(conn, _params) do
    with true <- Config.get([:trends, :enabled], true) do
      trends =
        if Config.get([:trends, :persist_in_database], true) do
          # Recupera le tendenze dal database
          from(h in Hashtag, limit: Config.get([:trends, :limits, :hashtags], 10))
          |> Repo.all()
        else
          # Se la persistenza è disattivata, restituisci un array vuoto
          []
        end

      # Cache le tendenze per un periodo configurabile
      conn
      |> put_cache_headers(Config.get([:cache, :trends_ttl], :timer.minutes(10)))
      |> render("index.json", trends: trends)
    else
      _ -> json(conn, [])
    end
  end

  defp put_cache_headers(conn, max_age) do
    conn
    |> put_resp_header("cache-control", "public, max-age=#{div(max_age, 1000)}")
  end
end