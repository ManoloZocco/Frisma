import { Redirect, useLocation } from 'react-router-dom';

import { openComposeWithText } from 'soapbox/actions/compose.ts';
import { useAppDispatch } from 'soapbox/hooks/useAppDispatch.ts';

const Share = () => {
  const dispatch = useAppDispatch();

  const { search } = useLocation();
  const params = new URLSearchParams(search);

  const text = [
    params.get('title'),
    params.get('text'),
    params.get('url'),
  ]
    .filter(v => v)
    .join('\n\n');

  if (text) {
    dispatch(openComposeWithText('compose-modal', text));
  }

  return (
    <Redirect to='/' />
  );
};

export default Share;
