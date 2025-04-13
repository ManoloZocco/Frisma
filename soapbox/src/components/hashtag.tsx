import { FormattedMessage } from 'react-intl';
import { Link } from 'react-router-dom';
import { Sparklines, SparklinesCurve } from 'react-sparklines';


import HStack from 'soapbox/components/ui/hstack.tsx';
import Stack from 'soapbox/components/ui/stack.tsx';
import Text from 'soapbox/components/ui/text.tsx';

import { shortNumberFormat } from '../utils/numbers.tsx';

import type { Tag } from 'soapbox/types/entities.ts';

interface IHashtag {
  hashtag: Tag;
  detailed?: boolean;
}

const Hashtag: React.FC<IHashtag> = ({ hashtag, detailed = false }) => {
  // Estrai il numero di account che usano questo hashtag
  const count = Number(hashtag.history?.get(0)?.accounts);
  
  // Estrai i valori per il grafico
  const historyData = hashtag.history ? 
    hashtag.history.reverse().map((day) => +day.uses).toArray() : 
    [];

  return (
    <HStack alignItems='center' justifyContent='between' data-testid='hashtag' className='py-2'>
      <Stack>
        <Link to={`/tags/${hashtag.name}`} className='hover:underline'>
          <Text tag='span' size='sm' weight='semibold'>#{hashtag.name}</Text>
        </Link>
        
        {Boolean(count) && (
          <Text theme='muted' size='sm'>
            <FormattedMessage
              id='trends.count_by_accounts'
              defaultMessage='{count} {rawCount, plural, one {persona} other {persone}} ne parlano'
              values={{
                rawCount: count,
                count: <strong>{shortNumberFormat(count)}</strong>,
              }}
            />
          </Text>
        )}
        
        {detailed && hashtag.account_count && hashtag.count && (
          <Text theme='muted' size='xs'>
            <FormattedMessage
              id='trends.detailed_stats'
              defaultMessage='{usageCount} post da {accountCount} account'
              values={{
                usageCount: <strong>{shortNumberFormat(hashtag.count)}</strong>,
                accountCount: <strong>{shortNumberFormat(hashtag.account_count)}</strong>,
              }}
            />
          </Text>
        )}
      </Stack>

      {hashtag.history && historyData.length > 0 && (
        <div className='w-[40px]' data-testid='sparklines'>
          <Sparklines
            width={40}
            height={28}
            data={historyData}
          >
            <SparklinesCurve style={{ fill: 'none' }} color='#818cf8' />
          </Sparklines>
        </div>
      )}
    </HStack>
  );
};

export default Hashtag;
