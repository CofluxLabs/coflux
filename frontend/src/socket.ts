export default class Socket {
  private socket: WebSocket;
  private closed = false;
  private lastRequestId = 0;
  private requests: Record<number, (value: any) => void> = {};
  private listeners: Record<string, ((...params: any[]) => void)[]> = {};

  constructor(private readonly projectId: string) {
    this.socket = this.open();
  }

  private open() {
    const socket = new WebSocket(`ws://localhost:7070/projects/${this.projectId}/events`);
    socket.addEventListener('open', this.handleOpen);
    socket.addEventListener('error', this.handleError);
    socket.addEventListener('message', this.handleMessage);
    socket.addEventListener('close', this.handleClose);
    return socket;
  }

  isConnected() {
    return this.socket.readyState == WebSocket.OPEN;
  }

  request(method: string, params: any[], handler?: (result: any) => void) {
    const id = ++this.lastRequestId;
    this.socket.send(JSON.stringify({ id, method, params }));
    if (handler) {
      this.requests[id] = handler;
    }
  }

  addListener(event: string, listener: (...params: any[]) => void) {
    if (!(event in this.listeners)) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(listener);
  }

  removeListener(event: string, listener: (...params: any[]) => void) {
    const index = this.listeners[event].indexOf(listener);
    if (index >= 0) {
      this.listeners[event].splice(index, 1);
    }
  }

  close() {
    this.closed = true;
    this.socket.close();
  }

  private notify(event: string, ...params: any[]) {
    if (event in this.listeners) {
      this.listeners[event].forEach((listener) => {
        listener(...params);
      });
    }
  }

  private handleOpen = (ev: Event) => {
    this.notify('connected');
  }

  private handleError = (ev: Event) => {
    // TODO: ?
  }

  private handleMessage = (ev: MessageEvent) => {
    const message = JSON.parse(ev.data);
    if (message.id) {
      this.requests[message.id](message.result);
    } else {
      this.notify(`notify:${message.method}`, ...message.params);
    }
  }

  private handleClose = (ev: Event) => {
    this.notify('disconnected');
    this.socket.removeEventListener('open', this.handleOpen);
    this.socket.removeEventListener('error', this.handleError);
    this.socket.removeEventListener('message', this.handleMessage);
    this.socket.removeEventListener('close', this.handleClose);
    this.requests = {}
    if (!this.closed) {
      // TODO: backoff with jitter
      setTimeout(() => {
        this.socket = this.open();
        this.notify('connecting');
      }, 500);
    }
  }
}
