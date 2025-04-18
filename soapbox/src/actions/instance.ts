import { createAsyncThunk } from '@reduxjs/toolkit';

import { instanceV1Schema, instanceV2Schema } from 'soapbox/schemas/instance.ts';
import { RootState } from 'soapbox/store.ts';
import { getAuthUserUrl, getMeUrl } from 'soapbox/utils/auth.ts';
import { getFeatures } from 'soapbox/utils/features.ts';

import api from '../api/index.ts';

/** Figure out the appropriate instance to fetch depending on the state */
export const getHost = (state: RootState) => {
  const accountUrl = getMeUrl(state) || getAuthUserUrl(state) as string;

  try {
    return new URL(accountUrl).host;
  } catch {
    return null;
  }
};

interface InstanceData {
  instance: Record<string, any>;
  host: string | null | undefined;
}

export const fetchInstance = createAsyncThunk<InstanceData, InstanceData['host'], { state: RootState }>(
  'instance/fetch',
  async(host, { dispatch, getState, rejectWithValue }) => {
    try {
      const response = await api(getState).get('/api/v1/instance');
      const data = await response.json();
      const instance = instanceV1Schema.parse(data);
      const features = getFeatures(instance);

      if (features.instanceV2) {
        dispatch(fetchInstanceV2(host));
      }

      return { instance, host };
    } catch (e) {
      return rejectWithValue(e);
    }
  },
);

export const fetchInstanceV2 = createAsyncThunk<InstanceData, InstanceData['host'], { state: RootState }>(
  'instanceV2/fetch',
  async(host, { getState, rejectWithValue }) => {
    try {
      const response = await api(getState).get('/api/v2/instance');
      const data = await response.json();
      const instance = instanceV2Schema.parse(data);
      return { instance, host };
    } catch (e) {
      return rejectWithValue(e);
    }
  },
);
