import { createContext, Dispatch, SetStateAction, useContext, useEffect, useState } from 'react';

import Socket, { SocketStatus } from '../socket';

export const SocketContext = createContext<{ socket?: Socket, status?: SocketStatus }>({});

export default function useSocket() {
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

function subscribe<T>(socket: Socket, topic: string, args: any[], subscriptionId: string, setState: Dispatch<SetStateAction<T | null | undefined>>) {
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

export function useSubscription<T>(topic: string, ...args: any) {
  const { socket, status } = useSocket();
  const [state, setState] = useState<T | null>();
  useEffect(() => {
    if (socket && status == 'connected') {
      const subscriptionId = ++lastSubscriptionId;
      return subscribe(socket, topic, args, subscriptionId.toString(), setState);
    }
  }, [socket, status, topic, ...args]);
  return state;
}
