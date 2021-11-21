import { createContext, useCallback, useContext, useEffect, useState } from 'react';

import Socket, { SocketStatus } from '../socket';

export const SocketContext = createContext<{ socket?: Socket, status?: SocketStatus }>({});

export default function useSocket() {
  return useContext(SocketContext);
}

function applyUpdate(state: any, path: (string | number)[], value: any): any {
  if (path.length == 0) {
    return value;
  } else {
    const [key, ...rest] = path;
    if (typeof key == 'number') {
      if (rest.length == 0) {
        return [...state.slice(0, key), value, ...state.slice(key)];
      } else {
        return [...state.slice(0, key), applyUpdate(state[key], rest, value), ...state.slice(key + 1)];
      }
    } else {
      return { ...state, [key]: applyUpdate(state[key], rest, value) };
    }
  }
}

let lastSubscriptionId = 0;

export function useSubscription<T>(topic: string) {
  const { socket, status } = useSocket();
  const [state, setState] = useState<T>();
  const subscribe = useCallback((socket, topic, subscriptionId) => {
    socket.request('subscribe', [topic, subscriptionId], setState);
    socket.addListener('notify:update', (sId: string, path: (string | number)[], value: any) => {
      if (sId == subscriptionId) {
        setState(state => applyUpdate(state, path, value));
      }
    });
    return () => {
      if (socket.isConnected()) {
        socket.request('unsubscribe', [subscriptionId]);
      }
    }
  }, []);
  useEffect(() => {
    const subscriptionId = ++lastSubscriptionId;
    if (socket && status == 'connected') {
      return subscribe(socket, topic, subscriptionId);
    }
  }, [socket, status, topic, subscribe]);
  return state;
}
