defmodule Pleroma.Trends.HashtagsCalculator do
  alias Pleroma.Repo
  alias Pleroma.Hashtag
  alias Pleroma.Object
  
  import Ecto.Query
  
  @doc """
  Calcola gli hashtag di tendenza in base alla frequenza di utilizzo in un determinato periodo di tempo.
  Restituisce i primi n hashtag ordinati per punteggio di tendenza.
  """
  def get_trending_hashtags(limit \\ 10, hours \\ 24) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)
    
    # Query di base: seleziona gli hashtag usati negli ultimi 'hours'
    query = from h in Hashtag,
            join: ho in "hashtags_objects", on: ho.hashtag_id == h.id,
            join: o in Object, on: o.id == ho.object_id,
            join: a in "activities", on: a.object_id == o.id,
            where: a.inserted_at > ^timestamp,
            # Solo post pubblici o unlisted
            where: fragment("?->>'visibility' in ('public', 'unlisted')", o.data),
            # Raggruppa per hashtag
            group_by: h.id,
            # Calcola il punteggio (frequenza + fattore di velocità)
            select: %{
              name: h.name,
              url: "/tags/#{h.name}",
              # Conteggio di base
              count: count(h.id),
              # Aggiungere un peso per le interazioni uniche
              account_count: fragment("COUNT(DISTINCT ?)", a.actor),
              # Punteggio di tendenza - possiamo aggiungere più fattori qui
              score: count(h.id) + fragment("COUNT(DISTINCT ?) * 0.5", a.actor)
            },
            # Ordina per punteggio discendente
            order_by: [desc: fragment("count(?) + COUNT(DISTINCT ?) * 0.5", h.id, a.actor)],
            limit: ^limit
    
    Repo.all(query)
    |> add_history_data()
  end
  
  @doc """
  Versione ottimizzata per server di grandi dimensioni che usa CTE per migliorare le prestazioni
  """
  def get_trending_hashtags_optimized(limit \\ 10, hours \\ 24) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)
  
    query = """
    WITH recent_hashtags AS (
      SELECT h.id, h.name, COUNT(ho.object_id) as usage_count, COUNT(DISTINCT a.actor) as unique_actors
      FROM hashtags h
      JOIN hashtags_objects ho ON ho.hashtag_id = h.id
      JOIN objects o ON o.id = ho.object_id
      JOIN activities a ON a.object_id = o.id
      WHERE a.inserted_at > $1
      AND o.data->>'visibility' IN ('public', 'unlisted')
      GROUP BY h.id
      ORDER BY usage_count DESC, unique_actors DESC
      LIMIT $2
    )
    SELECT name, 
           '/tags/' || name as url, 
           usage_count as count,
           unique_actors as account_count, 
           usage_count + (unique_actors * 0.5) as score
    FROM recent_hashtags
    ORDER BY score DESC
    """
    
    case Repo.query(query, [timestamp, limit]) do
      {:ok, %{rows: rows, columns: columns}} ->
        # Converti i risultati SQL in una mappa
        column_names = Enum.map(columns, &String.to_atom/1)
        rows
        |> Enum.map(fn row -> 
          mapping = Enum.zip(column_names, row) |> Enum.into(%{})
          # Aggiunta dei dati storici
          Map.put(mapping, :history, get_history_for_hashtag(mapping.name))
        end)
        
      {:error, _} ->
        # Fallback al metodo originale se la query ottimizzata fallisce
        get_trending_hashtags(limit, hours)
    end
  end
  
  @doc """
  Aggiunge dati storici per ogni hashtag per generare grafici di tendenza
  """
  defp add_history_data(hashtags) do
    # Per ogni hashtag, aggiungi l'attività degli ultimi 7 giorni divisa per giorno
    Enum.map(hashtags, fn hashtag ->
      history = get_history_for_hashtag(hashtag.name)
      Map.put(hashtag, :history, history)
    end)
  end
  
  defp get_history_for_hashtag(name) do
    # Calcola l'utilizzo dell'hashtag per ogni giorno negli ultimi 7 giorni
    days = 7
    today = Date.utc_today()
    
    dates = Enum.map(0..(days-1), fn day_offset -> 
      Date.add(today, -day_offset) 
    end)
    
    Enum.map(dates, fn date ->
      start_of_day = date |> NaiveDateTime.new!(~T[00:00:00])
      end_of_day = date |> NaiveDateTime.new!(~T[23:59:59])
      
      query = from h in Hashtag,
              join: ho in "hashtags_objects", on: ho.hashtag_id == h.id,
              join: o in Object, on: o.id == ho.object_id,
              join: a in "activities", on: a.object_id == o.id,
              where: h.name == ^name,
              where: a.inserted_at >= ^start_of_day and a.inserted_at <= ^end_of_day,
              select: %{
                day: type(fragment("?::text", date), :string),
                uses: count(h.id),
                accounts: fragment("COUNT(DISTINCT ?)", a.actor)
              },
              group_by: 1
              
      result = Repo.one(query) || %{day: to_string(date), uses: 0, accounts: 0}
      result
    end)
  end
end