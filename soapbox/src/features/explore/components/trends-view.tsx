import { defineMessages, FormattedMessage, useIntl } from 'react-intl';
import { Link } from 'react-router-dom';

import Hashtag from 'soapbox/components/hashtag.tsx';
import Stack from 'soapbox/components/ui/stack.tsx';
import Text from 'soapbox/components/ui/text.tsx';
import PlaceholderSidebarTrends from 'soapbox/features/placeholder/components/placeholder-sidebar-trends.tsx';
import useTrends from 'soapbox/queries/trends.ts';

const messages = defineMessages({
  title: { id: 'trends.title', defaultMessage: 'Tendenze' },
  subtitle: { id: 'trends.subtitle', defaultMessage: 'Argomenti di tendenza in questo momento' },
  emptyMessage: { id: 'trends.empty', defaultMessage: 'Nessuna tendenza al momento' },
  errorMessage: { id: 'trends.error', defaultMessage: 'Errore nel caricamento delle tendenze' }
});

const TrendsView = () => {
  const intl = useIntl();
  const { data: trends, isFetching, isError, refetch } = useTrends();

  return (
    <Stack space={4} className='p-4'>
      <Stack>
        <Text size='xl' weight='bold'>
          {intl.formatMessage(messages.title)}
        </Text>
        <Text theme='muted'>
          {intl.formatMessage(messages.subtitle)}
        </Text>
      </Stack>

      {isFetching ? (
        <div className='p-4'>
          <PlaceholderSidebarTrends limit={12} />
        </div>
      ) : isError ? (
        <div className='p-4 text-center'>
          <Text theme='muted' size='lg'>
            {intl.formatMessage(messages.errorMessage)}
          </Text>
          <button 
            onClick={() => refetch()} 
            className='mt-2 text-primary-600 hover:underline dark:text-primary-400'
          >
            <FormattedMessage id='trends.refresh' defaultMessage='Aggiorna' />
          </button>
        </div>
      ) : trends && trends.length > 0 ? (
        <div className='grid gap-2 sm:grid-cols-2 md:grid-cols-3'>
          {trends.map((hashtag) => (
            <div key={hashtag.name} className='rounded-lg border p-3 hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900'>
              <Link to={`/tags/${hashtag.name}`} className='block'>
                <Hashtag hashtag={hashtag} detailed />
              </Link>
            </div>
          ))}
        </div>
      ) : (
        <div className='p-4 text-center'>
          <Text theme='muted' size='lg'>
            {intl.formatMessage(messages.emptyMessage)}
          </Text>
        </div>
      )}
    </Stack>
  );
};

export default TrendsView;