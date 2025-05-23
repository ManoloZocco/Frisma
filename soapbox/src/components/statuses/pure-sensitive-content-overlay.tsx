import dotsIcon from '@tabler/icons/outline/dots.svg';
import eyeOffIcon from '@tabler/icons/outline/eye-off.svg';
import eyeIcon from '@tabler/icons/outline/eye.svg';
import headsetIcon from '@tabler/icons/outline/headset.svg';
import trashIcon from '@tabler/icons/outline/trash.svg';
import clsx from 'clsx';
import { forwardRef, useEffect, useMemo, useState } from 'react';
import { defineMessages, useIntl } from 'react-intl';

import { openModal } from 'soapbox/actions/modals.ts';
import { deleteStatus } from 'soapbox/actions/statuses.ts';
import DropdownMenu from 'soapbox/components/dropdown-menu/index.ts';
import Button from 'soapbox/components/ui/button.tsx';
import HStack from 'soapbox/components/ui/hstack.tsx';
import Text from 'soapbox/components/ui/text.tsx';
import { useAppDispatch } from 'soapbox/hooks/useAppDispatch.ts';
import { useOwnAccount } from 'soapbox/hooks/useOwnAccount.ts';
import { useSettings } from 'soapbox/hooks/useSettings.ts';
import { useSoapboxConfig } from 'soapbox/hooks/useSoapboxConfig.ts';
import { Status as StatusEntity } from 'soapbox/schemas/index.ts';
import { emojifyText } from 'soapbox/utils/emojify.tsx';
import { defaultMediaVisibility } from 'soapbox/utils/status.ts';

const messages = defineMessages({
  delete: { id: 'status.delete', defaultMessage: 'Delete' },
  deleteConfirm: { id: 'confirmations.delete.confirm', defaultMessage: 'Delete' },
  deleteHeading: { id: 'confirmations.delete.heading', defaultMessage: 'Delete post' },
  deleteMessage: { id: 'confirmations.delete.message', defaultMessage: 'Are you sure you want to delete this post?' },
  hide: { id: 'moderation_overlay.hide', defaultMessage: 'Hide content' },
  sensitiveTitle: { id: 'status.sensitive_warning', defaultMessage: 'Sensitive content' },
  underReviewTitle: { id: 'moderation_overlay.title', defaultMessage: 'Content Under Review' },
  underReviewSubtitle: { id: 'moderation_overlay.subtitle', defaultMessage: 'This Post has been sent to Moderation for review and is only visible to you. If you believe this is an error please contact Support.' },
  sensitiveSubtitle: { id: 'status.sensitive_warning.subtitle', defaultMessage: 'This content may not be suitable for all audiences.' },
  contact: { id: 'moderation_overlay.contact', defaultMessage: 'Contact' },
  show: { id: 'moderation_overlay.show', defaultMessage: 'Show Content' },
});

interface IPureSensitiveContentOverlay {
  status: StatusEntity;
  onToggleVisibility?(): void;
  visible?: boolean;
}

const PureSensitiveContentOverlay = forwardRef<HTMLDivElement, IPureSensitiveContentOverlay>((props, ref) => {
  const { onToggleVisibility, status } = props;

  const { account } = useOwnAccount();
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const { displayMedia, deleteModal } = useSettings();
  const { links } = useSoapboxConfig();

  const isUnderReview = status.visibility === 'self';
  const isOwnStatus = status.account.id === account?.id;

  const [visible, setVisible] = useState<boolean>(defaultMediaVisibility(status, displayMedia));

  const toggleVisibility = (event: React.MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();

    if (onToggleVisibility) {
      onToggleVisibility();
    } else {
      setVisible((prevValue) => !prevValue);
    }
  };

  const handleDeleteStatus = () => {
    if (!deleteModal) {
      dispatch(deleteStatus(status.id, false));
    } else {
      dispatch(openModal('CONFIRM', {
        icon: trashIcon,
        heading: intl.formatMessage(messages.deleteHeading),
        message: intl.formatMessage(messages.deleteMessage),
        confirm: intl.formatMessage(messages.deleteConfirm),
        onConfirm: () => dispatch(deleteStatus(status.id, false)),
      }));
    }
  };

  const menu = useMemo(() => {
    return [
      {
        text: intl.formatMessage(messages.delete),
        action: handleDeleteStatus,
        icon: trashIcon,
        destructive: true,
      },
    ];
  }, []);

  useEffect(() => {
    if (typeof props.visible !== 'undefined') {
      setVisible(!!props.visible);
    }
  }, [props.visible]);

  return (
    <div
      className={clsx('absolute z-40', {
        'cursor-default backdrop-blur-lg rounded-lg w-full h-full border-0 flex justify-center': !visible,
        'bg-gray-800/75 inset-0': !visible,
        'bottom-1 right-1': visible,
      })}
      data-testid='sensitive-overlay'
    >
      {visible ? (
        <Button
          text={intl.formatMessage(messages.hide)}
          icon={eyeOffIcon}
          onClick={toggleVisibility}
          theme='primary'
          size='sm'
        />
      ) : (
        <div className='flex max-h-screen items-center justify-center'>
          <div className='mx-auto w-3/4 space-y-4 text-center' ref={ref}>
            <div className='space-y-1'>
              <Text theme='white' weight='semibold'>
                {intl.formatMessage(isUnderReview ? messages.underReviewTitle : messages.sensitiveTitle)}
              </Text>

              <Text theme='white' size='sm' weight='medium'>
                {intl.formatMessage(isUnderReview ? messages.underReviewSubtitle : messages.sensitiveSubtitle)}
              </Text>

              {status.spoiler_text && (
                <div className='py-4 italic'>
                  {/* eslint-disable formatjs/no-literal-string-in-jsx */}
                  <Text className='line-clamp-6' theme='white' size='md' weight='medium'>
                    &ldquo;<span>{emojifyText(status.spoiler_text, status.emojis)}</span>&rdquo;
                  </Text>
                  {/* eslint-enable formatjs/no-literal-string-in-jsx */}
                </div>
              )}
            </div>

            <HStack alignItems='center' justifyContent='center' space={2}>
              {isUnderReview ? (
                <>
                  {links.get('support') && (
                    <a
                      href={links.get('support')}
                      target='_blank'
                      onClick={(event) => event.stopPropagation()}
                    >
                      <Button
                        type='button'
                        theme='outline'
                        size='sm'
                        icon={headsetIcon}
                      >
                        {intl.formatMessage(messages.contact)}
                      </Button>
                    </a>
                  )}
                </>
              ) : null}

              <Button
                type='button'
                theme='outline'
                size='sm'
                icon={eyeIcon}
                onClick={toggleVisibility}
              >
                {intl.formatMessage(messages.show)}
              </Button>

              {(isUnderReview && isOwnStatus) ? (
                <DropdownMenu
                  items={menu}
                  src={dotsIcon}
                />
              ) : null}
            </HStack>
          </div>
        </div>
      )}
    </div>
  );
});

export default PureSensitiveContentOverlay;
