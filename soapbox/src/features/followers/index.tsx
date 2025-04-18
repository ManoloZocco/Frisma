import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useAccountLookup, useFollowers } from 'soapbox/api/hooks/index.ts';
import Account from 'soapbox/components/account.tsx';
import MissingIndicator from 'soapbox/components/missing-indicator.tsx';
import ScrollableList from 'soapbox/components/scrollable-list.tsx';
import { Column } from 'soapbox/components/ui/column.tsx';
import Spinner from 'soapbox/components/ui/spinner.tsx';

const messages = defineMessages({
  heading: { id: 'column.followers', defaultMessage: 'Followers' },
});

interface IFollowers {
  params?: {
    username?: string;
  };
}

/** Displays a list of accounts who follow the given account. */
const Followers: React.FC<IFollowers> = ({ params }) => {
  const intl = useIntl();

  const { account, isUnavailable } = useAccountLookup(params?.username);

  const {
    accounts,
    hasNextPage,
    fetchNextPage,
    isLoading,
  } = useFollowers(account?.id);

  if (isLoading) {
    return (
      <Spinner />
    );
  }

  if (!account) {
    return (
      <MissingIndicator />
    );
  }

  if (isUnavailable) {
    return (
      <div className='flex min-h-[160px] flex-1 items-center justify-center rounded-lg bg-primary-50 p-10 text-center text-gray-900 dark:bg-gray-700 dark:text-gray-300'>
        <FormattedMessage id='empty_column.account_unavailable' defaultMessage='Profile unavailable' />
      </div>
    );
  }

  return (
    <Column label={intl.formatMessage(messages.heading)} transparent>
      <ScrollableList
        scrollKey='followers'
        hasMore={hasNextPage}
        onLoadMore={fetchNextPage}
        emptyMessage={<FormattedMessage id='account.followers.empty' defaultMessage='No one follows this user yet.' />}
        itemClassName='pb-4'
      >
        {accounts.map((account) =>
          <Account key={account.id} account={account} />,
        )}
      </ScrollableList>
    </Column>
  );
};

export default Followers;