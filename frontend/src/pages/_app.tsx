import React from 'react';
import type { AppProps } from 'next/app';
import { useRouter } from 'next/router';

import useSocket, { SocketContext } from '../hooks/useSocket';

import '../../styles/globals.scss';

export default function App({ Component, pageProps }: AppProps) {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const { status, socket } = useSocket(projectId);
  return (
    <SocketContext.Provider value={[socket, status]}>
      <Component {...pageProps} />
    </SocketContext.Provider>
  );
}
