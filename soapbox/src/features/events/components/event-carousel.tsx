import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg';
import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg';
import { useCallback, useState } from 'react';
import { Link } from 'react-router-dom';
import ReactSwipeableViews from 'react-swipeable-views';

import EventPreview from 'soapbox/components/event-preview.tsx';
import { Card } from 'soapbox/components/ui/card.tsx';
import Icon from 'soapbox/components/ui/icon.tsx';
import { useAppSelector } from 'soapbox/hooks/useAppSelector.ts';
import { makeGetStatus } from 'soapbox/selectors/index.ts';

import PlaceholderEventPreview from '../../placeholder/components/placeholder-event-preview.tsx';

import type { OrderedSet as ImmutableOrderedSet } from 'immutable';

const Event = ({ id }: { id: string }) => {
  const getStatus = useCallback(makeGetStatus(), []);
  const status = useAppSelector(state => getStatus(state, { id }));

  if (!status) return null;

  return (
    <Link
      className='w-full px-1'
      to={`/@${status.getIn(['account', 'acct'])}/events/${status.id}`}
    >
      <EventPreview status={status} floatingAction={false} />
    </Link>
  );
};

interface IEventCarousel {
  statusIds: ImmutableOrderedSet<string>;
  isLoading?: boolean | null;
  emptyMessage: React.ReactNode;
}

const EventCarousel: React.FC<IEventCarousel> = ({ statusIds, isLoading, emptyMessage }) => {
  const [index, setIndex] = useState(0);

  const handleChangeIndex = (index: number) => {
    setIndex(index % statusIds.size);
  };

  if (statusIds.size === 0) {
    if (isLoading) {
      return <PlaceholderEventPreview />;
    }

    return (
      <Card size='lg'>
        {emptyMessage}
      </Card>
    );
  }
  return (
    <div className='relative -mx-1'>
      {index !== 0 && (
        <div className='absolute left-3 top-1/2 z-10 -mt-4'>
          <button
            onClick={() => handleChangeIndex(index - 1)}
            className='flex size-8 items-center justify-center rounded-full bg-white/50 backdrop-blur dark:bg-gray-900/50'
          >
            <Icon src={chevronLeftIcon} className='size-6 text-black dark:text-white' />
          </button>
        </div>
      )}
      <ReactSwipeableViews animateHeight index={index} onChangeIndex={handleChangeIndex}>
        {statusIds.map(statusId => <Event key={statusId} id={statusId} />)}
      </ReactSwipeableViews>
      {index !== statusIds.size - 1 && (
        <div className='absolute right-3 top-1/2 z-10 -mt-4'>
          <button
            onClick={() => handleChangeIndex(index + 1)}
            className='flex size-8 items-center justify-center rounded-full bg-white/50 backdrop-blur dark:bg-gray-900/50'
          >
            <Icon src={chevronRightIcon} className='size-6 text-black dark:text-white' />
          </button>
        </div>
      )}
    </div>
  );
};

export default EventCarousel;
