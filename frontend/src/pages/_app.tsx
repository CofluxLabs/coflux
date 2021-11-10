import type { AppProps } from 'next/app';
import React from 'react';
import { SWRConfig } from 'swr';

import '../../styles/globals.scss';

const BASE_URL = 'http://localhost:7070';

const fetcher = (path: string) => fetch(`${BASE_URL}${path}`).then((res) => res.json());

export default function App({ Component, pageProps }: AppProps) {
  return (
    <SWRConfig value={{ fetcher }}>
      <Component {...pageProps} />
    </SWRConfig>
  );
}
