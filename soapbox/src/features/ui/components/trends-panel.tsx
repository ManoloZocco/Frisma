import { defineMessages, FormattedMessage, useIntl } from 'react-intl';
import { Link } from 'react-router-dom';

import { setFilter } from 'soapbox/actions/search.ts';
import Hashtag from 'soapbox/components/hashtag.tsx';
import HStack from 'soapbox/components/ui/hstack.tsx';
import Text from 'soapbox/components/ui/text.tsx';
import Widget from 'soapbox/components/ui/widget.tsx';
import PlaceholderSidebarTrends from 'soapbox/features/placeholder/components/placeholder-sidebar-trends.tsx';
import { useAppDispatch } from 'soapbox/hooks/useAppDispatch.ts';
import { useFeatures } from 'soapbox/hooks/useFeatures.ts';
import useTrends from 'soapbox/queries/trends.ts';

interface ITrendsPanel {
  limit?: number;
}

const messages = defineMessages({
  title: { id: 'trends.title', defaultMessage: 'Tendenze' },
  viewAll: {
    id: 'trends_panel.view_all',
    defaultMessage: 'Vedi tutti',
  },
  emptyMessage: {
    id: 'trends.empty', 
    defaultMessage: 'Nessuna tendenza al momento'
  },
  refresh: {
    id: 'trends.refresh',
    defaultMessage: 'Aggiorna'
  }
});

const TrendsPanel = ({ limit = 5 }: ITrendsPanel) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const features = useFeatures();

  const { data: trends, isFetching, isError, refetch } = useTrends();
  
  const setHashtagsFilter = () => {
    dispatch(setFilter('hashtags'));
  };

  if (!features.trends || (!isFetching && !trends?.length && !isError)) {
    return null;
  }

  return (
    <Widget
      title={<FormattedMessage id='trends.title' defaultMessage='Tendenze' />}
      action={
        <HStack alignItems='center' space={2}>
          {!isFetching && (
            <button onClick={() => refetch()} className='text-primary-600 hover:underline dark:text-primary-400'>
              <Text tag='span' size='sm'>
                {intl.formatMessage(messages.refresh)}
              </Text>
            </button>
          )}
          <Link className='text-right' to='/explore' onClick={setHashtagsFilter}>
            <Text tag='span' theme='primary' size='sm' className='hover:underline'>
              {intl.formatMessage(messages.viewAll)}
            </Text>
          </Link>
        </HStack>
      }
    >
      {isFetching ? (
        <PlaceholderSidebarTrends limit={limit} />
      ) : isError ? (
        <Text theme='muted' size='sm' align='center'>
          <FormattedMessage id='trends.error' defaultMessage='Errore nel caricamento delle tendenze' />
        </Text>
      ) : trends && trends.length > 0 ? (
        trends?.slice(0, limit).map((hashtag) => (
          <Hashtag key={hashtag.name} hashtag={hashtag} />
        ))
      ) : (
        <Text theme='muted' size='sm' align='center'>
          {intl.formatMessage(messages.emptyMessage)}
        </Text>
      )}
    </Widget>
  );
};

export default TrendsPanel;
