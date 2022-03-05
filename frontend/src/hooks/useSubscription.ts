import { createContext, createElement, Dispatch, ReactNode, SetStateAction, useContext, useEffect, useState } from 'react';

import Socket from '../socket';

const SocketContext = createContext<{ socket?: Socket, status?: SocketStatus }>({});

type SocketStatus = 'connecting' | 'connected' | 'disconnected';

type SocketProviderProps = {
  projectId: string | undefined;
  children: ReactNode;
}

export function SocketProvider({ projectId, children }: SocketProviderProps) {
  const [status, setStatus] = useState<SocketStatus>();
  const [socket, setSocket] = useState<Socket>();
  useEffect(() => {
    if (projectId) {
      const socket = new Socket(projectId);
      socket.addListener('connecting', () => setStatus('connecting'));
      socket.addListener('connected', () => setStatus('connected'));
      socket.addListener('disconnected', () => setStatus('disconnected'));
      setStatus('connecting');
      setSocket(socket);
      return () => {
        setSocket(undefined);
        socket.close();
      }
    }
  }, [projectId]);
  return createElement(SocketContext.Provider, { value: { socket, status } }, children);
}

export function useSocket() {
  return useContext(SocketContext);
}

function applyUpdate(state: any, path: (string | number)[], value: any): any {
  if (path.length == 0) {
    return value;
  } else if (value === null && path.length == 1) {
    const [key] = path;
    const { [key]: _oldValue, ...rest } = state;
    return rest;
  } else {
    const [key, ...rest] = path;
    return { ...state, [key]: applyUpdate(state[key], rest, value) };
  }
}

function subscribe<T>(socket: Socket, topic: string, args: any[], subscriptionId: string, setState: Dispatch<SetStateAction<T | undefined>>) {
  const listener = (sId: string, path: (string | number)[], value: any) => {
    if (sId == subscriptionId) {
      setState(state => applyUpdate(state, path, value));
    }
  }
  setState(undefined);
  socket.addListener('notify:update', listener);
  socket.request('subscribe', [topic, args, subscriptionId], (value) => {
    setState(value);
  });
  return () => {
    socket.removeListener('notify:update', listener);
    if (socket.isConnected()) {
      socket.request('unsubscribe', [subscriptionId]);
    }
  }
}

let lastSubscriptionId = 0;

export default function useSubscription<T>(topic: string, ...args: any[]) {
  const { socket, status } = useSocket();
  const [state, setState] = useState<T>();
  useEffect(() => {
    if (socket && status == 'connected' && !args.some((a) => a === undefined)) {
      const subscriptionId = ++lastSubscriptionId;
      return subscribe(socket, topic, args, subscriptionId.toString(), setState);
    }
  }, [socket, status, topic, ...args]);
  return state;
}
