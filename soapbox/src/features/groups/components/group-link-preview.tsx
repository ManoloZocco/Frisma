import { FormattedMessage } from 'react-intl';

import Avatar from 'soapbox/components/ui/avatar.tsx';
import Button from 'soapbox/components/ui/button.tsx';
import { CardTitle } from 'soapbox/components/ui/card.tsx';
import Stack from 'soapbox/components/ui/stack.tsx';
import { type Card as StatusCard } from 'soapbox/types/entities.ts';

interface IGroupLinkPreview {
  card: StatusCard;
}

const GroupLinkPreview: React.FC<IGroupLinkPreview> = ({ card }) => {
  const { group } = card;
  if (!group) return null;

  return (
    <Stack className='cursor-default overflow-hidden rounded-lg border border-gray-300 text-center dark:border-gray-800'>
      <div
        className='-mb-8 h-32 w-full bg-cover bg-center'
        style={{ backgroundImage: `url(${group.header})` }}
      />

      <Avatar
        className='mx-auto border-4 border-white dark:border-primary-900'
        src={group.avatar}
        size={64}
      />

      <Stack space={4} className='p-4'>
        <CardTitle title={group.display_name} />

        <Button theme='primary' to={`/group/${group.slug}`} block>
          <FormattedMessage id='group.popover.action' defaultMessage='View Group' />
        </Button>
      </Stack>
    </Stack>
  );
};

export { GroupLinkPreview };
