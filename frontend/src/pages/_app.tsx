import React, { useEffect, useState } from 'react';
import type { AppProps } from 'next/app';
import { useRouter } from 'next/router';

import Socket, { SocketStatus } from '../socket';
import { SocketContext } from '../hooks/useSocket';

import '../../styles/globals.scss';

function createSocket(
  projectId: string | null,
  setStatus: (status: SocketStatus) => void,
  setSocket: (socket: Socket | undefined) => void
) {
  if (projectId) {
    const socket = new Socket(projectId);
    socket.addListener('connecting', () => setStatus('connecting'));
    socket.addListener('connected', () => setStatus('connected'));
    socket.addListener('disconnected', () => setStatus('disconnected'));
    setStatus('connecting');
    setSocket(socket);
    return () => {
      socket.close();
      setSocket(undefined);
    }
  }
}

export default function App({ Component, pageProps }: AppProps) {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const [status, setStatus] = useState<SocketStatus>('disconnected');
  const [socket, setSocket] = useState<Socket>();
  useEffect(() => createSocket(projectId, setStatus, setSocket), [projectId]);
  return (
    <SocketContext.Provider value={{ socket, status }}>
      <Component {...pageProps} />
    </SocketContext.Provider>
  );
}
