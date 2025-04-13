defmodule Pleroma.Workers.TrendingHashtagsWorker do
  @moduledoc """
  Worker che calcola e aggiorna gli hashtag di tendenza periodicamente.
  """

  use Oban.Worker, queue: :trending, max_attempts: 3

  import Ecto.Query

  alias Pleroma.Config
  alias Pleroma.Repo
  alias Pleroma.Object
  alias Pleroma.Hashtag
  alias Pleroma.Web.CommonAPI

  require Logger

  @impl Oban.Worker
  def perform(_args) do
    if Config.get([:trends, :enabled], true) do
      Logger.info("Calcolo hashtag di tendenza")
      
      # Configura i parametri di calcolo
      timeframe_hours = Config.get([:trends, :timeframe_hours], 24)
      hashtag_limit = Config.get([:trends, :limits, :hashtags], 10)
      use_optimized = Config.get([:trends, :use_optimized_query], false)
      persist = Config.get([:trends, :persist_in_database], true)
      refresh_interval = Config.get([:trends, :refresh_interval], :timer.minutes(30))

      # Calcola le tendenze in base al metodo configurato
      trending_hashtags = if use_optimized do
        calculate_trending_hashtags_optimized(timeframe_hours, hashtag_limit)
      else
        calculate_trending_hashtags(timeframe_hours, hashtag_limit)
      end

      # Salva le tendenze nel database se configurato
      if persist do
        save_trending_hashtags(trending_hashtags)
      end

      # Pianifica il prossimo calcolo
      %{worker: __MODULE__}
      |> Oban.Job.new(scheduled_at: refresh_interval_to_scheduled_at(refresh_interval))
      |> Oban.insert()

      {:ok, %{hashtags_count: length(trending_hashtags)}}
    else
      {:ok, %{message: "Calcolo tendenze disabilitato nelle impostazioni"}}
    end
  end

  # Converte un intervallo di refresh in un timestamp per la pianificazione
  defp refresh_interval_to_scheduled_at(interval) do
    DateTime.utc_now()
    |> DateTime.add(div(interval, 1000), :second)
  end

  # Calcola gli hashtag di tendenza usando una query standard
  defp calculate_trending_hashtags(timeframe_hours, limit) do
    timeframe = DateTime.utc_now() |> DateTime.add(-timeframe_hours * 60 * 60, :second)

    # Query di base per gli oggetti recenti
    query =
      from o in Object,
        where: o.inserted_at > ^timeframe,
        where: fragment("?->>'type' = 'Create'", o.data),
        where: fragment("?->>'hashtags' is not null", o.data)

    # Estrazione degli hashtag e conteggio
    query
    |> select([o], %{
      name: fragment("jsonb_array_elements_text(?->>'hashtags')", o.data),
      actor: fragment("?->>'actor'", o.data)
    })
    |> Repo.all()
    |> Enum.reduce(%{}, fn %{name: tag, actor: actor}, acc ->
      # Normalizza il nome del tag
      normalized_tag = String.downcase(tag)
      
      # Aggiorna contatori nel map accumulatore
      Map.update(
        acc,
        normalized_tag,
        %{count: 1, accounts: MapSet.new([actor])},
        fn %{count: count, accounts: accounts} ->
          %{count: count + 1, accounts: MapSet.put(accounts, actor)}
        end
      )
    end)
    # Converti in lista, calcola account_count e ordina
    |> Enum.map(fn {name, %{count: count, accounts: accounts}} ->
      %{
        name: name,
        count: count,
        account_count: MapSet.size(accounts)
      }
    end)
    |> Enum.sort_by(fn %{count: count, account_count: account_count} -> 
      # Formula di tendenza: pesa sia il numero totale che la diffusione
      count * :math.log(account_count + 1) 
    end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn %{name: name, count: count, account_count: account_count} ->
      calculate_history_for_hashtag(name, timeframe_hours)
      |> Map.put(:name, name)
      |> Map.put(:count, count)
      |> Map.put(:account_count, account_count)
    end)
  end

  # Calcola gli hashtag di tendenza usando una query ottimizzata per istanze più grandi
  defp calculate_trending_hashtags_optimized(timeframe_hours, limit) do
    timeframe = DateTime.utc_now() |> DateTime.add(-timeframe_hours * 60 * 60, :second)

    # Query più efficiente che utilizza indici e limit
    Repo.query!(
      """
      SELECT name, COUNT(DISTINCT actor) as account_count, COUNT(*) as count
      FROM (
        SELECT jsonb_array_elements_text(data->>'hashtags') as name, data->>'actor' as actor
        FROM objects
        WHERE inserted_at > $1
          AND data->>'type' = 'Create'
          AND data->>'hashtags' IS NOT NULL
      ) as tags
      GROUP BY name
      ORDER BY count * ln(account_count + 1) DESC
      LIMIT $2
      """,
      [timeframe, limit]
    )
    |> Map.get(:rows)
    |> Enum.map(fn [name, account_count, count] -> 
      calculate_history_for_hashtag(name, timeframe_hours)
      |> Map.put(:name, name)
      |> Map.put(:count, count)
      |> Map.put(:account_count, account_count)
    end)
  end

  # Calcola l'istogramma storico per un hashtag
  defp calculate_history_for_hashtag(name, timeframe_hours) do
    # Divide il periodo in 5 intervalli per il grafico
    interval_hours = div(timeframe_hours, 5)
    now = DateTime.utc_now()
    
    # Crea 5 punti dati per mostrare l'andamento nel tempo
    history = Enum.map(0..4, fn i ->
      start_time = DateTime.add(now, -(i + 1) * interval_hours * 60 * 60, :second)
      end_time = DateTime.add(now, -i * interval_hours * 60 * 60, :second)
      
      # Conta l'utilizzo dell'hashtag nell'intervallo
      query =
        from o in Object,
        where: o.inserted_at >= ^start_time,
        where: o.inserted_at < ^end_time,
        where: fragment("?->>'type' = 'Create'", o.data),
        where: fragment("(?->>'hashtags')::jsonb @> ?", o.data, ^Jason.encode!([name]))
      
      # Esegui il conteggio e raccogli gli attori unici
      result = 
        query
        |> select([o], %{
          actor: fragment("?->>'actor'", o.data)
        })
        |> Repo.all()
      
      unique_accounts = Enum.uniq_by(result, & &1.actor) |> length()
      
      # Restituisci dati per questo punto nell'istogramma
      %{
        day: DateTime.to_date(start_time) |> Date.to_string(),
        uses: length(result),
        accounts: unique_accounts
      }
    end)
    |> Enum.reverse() # Metti in ordine cronologico
    
    %{history: history}
  end
  
  # Salva gli hashtag di tendenza nel database
  defp save_trending_hashtags(hashtags) do
    # Cancella le tendenze precedenti
    Repo.delete_all(Pleroma.Hashtag)
    
    # Inserisci le nuove tendenze
    Enum.each(hashtags, fn hashtag ->
      %Pleroma.Hashtag{}
      |> Pleroma.Hashtag.changeset(%{
        name: hashtag.name,
        count: hashtag.count,
        account_count: hashtag.account_count,
        history: hashtag.history
      })
      |> Repo.insert()
    end)
  end
end