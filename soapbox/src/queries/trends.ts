import { useQuery } from '@tanstack/react-query';

import { fetchTrendsSuccess } from 'soapbox/actions/trends.ts';
import { useApi } from 'soapbox/hooks/useApi.ts';
import { useAppDispatch } from 'soapbox/hooks/useAppDispatch.ts';
import { normalizeTag } from 'soapbox/normalizers/index.ts';

import type { Tag } from 'soapbox/types/entities.ts';

export default function useTrends() {
  const api = useApi();
  const dispatch = useAppDispatch();

  const getTrends = async(): Promise<ReadonlyArray<Tag>> => {
    try {
      const response = await api.get('/api/v1/trends');
      const data: Tag[] = await response.json();

      dispatch(fetchTrendsSuccess(data));

      const normalizedData = data.map((tag) => normalizeTag(tag));
      return normalizedData;
    } catch (error) {
      console.error('Error fetching trends:', error);
      throw error;
    }
  };

  const result = useQuery<ReadonlyArray<Tag>>({
    queryKey: ['trends'],
    queryFn: getTrends,
    placeholderData: [],
    staleTime: 600000, // 10 minuti
    cacheTime: 900000, // 15 minuti
    refetchOnWindowFocus: false, // Non ricaricare quando la finestra riprende il focus
    refetchInterval: 300000, // Ricarica automaticamente ogni 5 minuti
    retry: 2, // Riprova 2 volte in caso di errore
    retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 30000), // Backoff esponenziale tra i tentativi
  });

  return result;
}
