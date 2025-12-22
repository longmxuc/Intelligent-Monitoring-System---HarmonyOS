import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 服务器地址配置（统一管理）
export const SERVER_HOST = 'znhj.iepose.cn';

// WebSocket警告通知消息接口
export interface WarningNotificationMessage {
  type: string;
  warning_type?: string;
  warning_name?: string;
  warning_value?: number | string;
  warning_unit?: string;
  warning_message?: string;
  device_id?: string;
  timestamp?: number;
}

// WebSocket读数消息接口
export interface ReadingMessage {
  type: string;
  device_id?: string;
  temp?: number;
  hum?: number;
  temp2?: number;
  ts?: number;
  lux?: number;
  smoke?: number;
  pressure?: number;
  rs_ro?: number;
}

// WebSocket定位消息接口
export interface LocationMessage {
  type: string;
  device_id?: string;
  lon?: number;
  lat?: number;
  utc?: number | string;
  csq?: number;
  iccid?: string;
  imei?: string;
  location_type?: string;
}

// WebSocket原始消息接口（用于解析JSON）
interface WebSocketRawMessage {
  type?: string;
  device_id?: string;
  temp?: number;
  hum?: number;
  temp2?: number;
  ts?: number;
  lux?: number;
  smoke?: number;
  pressure?: number;
  rs_ro?: number;
  warning_type?: string;
  warning_name?: string;
  warning_value?: number | string;
  warning_unit?: string;
  warning_message?: string;
  timestamp?: number;
  lon?: number;
  lat?: number;
  utc?: number | string;
  csq?: number;
  iccid?: string;
  imei?: string;
  location_type?: string;
}

// WebSocket消息回调接口
export interface WebSocketMessageCallback {
  onWarning?: (message: WarningNotificationMessage) => void;
  onWarningResolved?: (deviceId: string) => void;
  onReading?: (message: ReadingMessage) => void;
  onLocation?: (message: LocationMessage) => void;
  onConnected?: (connected: boolean) => void;
}

// 全局WebSocket管理器（单例模式）
export class WebSocketManager {
  private static instance: WebSocketManager | null = null;
  private ws: webSocket.WebSocket | null = null;
  private callbacks: Set<WebSocketMessageCallback> = new Set();
  private reconnectTimer: number | null = null;
  private isReconnecting: boolean = false;
  private reconnectCount: number = 0;
  private readonly MAX_RECONNECT_COUNT = 10;
  private wsConnected: boolean = false;

  private constructor() {
    // 私有构造函数，确保单例
  }

  // 获取单例实例
  public static getInstance(): WebSocketManager {
    if (!WebSocketManager.instance) {
      WebSocketManager.instance = new WebSocketManager();
    }
    return WebSocketManager.instance;
  }

  // 检查是否有真正的错误
  private hasError(err: BusinessError | null | undefined): boolean {
    if (!err) {
      return false;
    }
    return !!(err.code || err.message || err.name || err.data);
  }

  // 订阅消息回调
  public subscribe(callback: WebSocketMessageCallback): void {
    this.callbacks.add(callback);
    // 如果已连接，立即通知连接状态
    if (this.wsConnected) {
      callback.onConnected?.(true);
    }
  }

  // 取消订阅
  public unsubscribe(callback: WebSocketMessageCallback): void {
    this.callbacks.delete(callback);
  }

  // 通知所有订阅者
  private notifyCallbacks(notifyFn: (callback: WebSocketMessageCallback) => void): void {
    this.callbacks.forEach(notifyFn);
  }

  // 自动重连机制
  private scheduleReconnect(): void {
    if (this.isReconnecting) {
      return;
    }

    if (this.reconnectCount >= this.MAX_RECONNECT_COUNT) {
      console.error(`已达到最大重连次数 ${this.MAX_RECONNECT_COUNT}，停止重连`);
      return;
    }

    this.reconnectCount++;
    this.isReconnecting = true;
    console.info(`1.5 秒后尝试重新连接... (第 ${this.reconnectCount} 次)`);

    const timerId = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.wsConnected) {
        console.info('开始重连 WebSocket...');
        this.connect();
      }
    }, 1500);
    this.reconnectTimer = timerId as number;
  }

  // 建立 WebSocket 连接
  public connect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws) {
      try {
        this.ws.close((err: BusinessError) => {
          if (this.hasError(err)) {
            console.warn('关闭旧连接时出错:', JSON.stringify(err));
          }
        });
      } catch (e) {
        console.warn('关闭旧连接时异常:', e);
      }
      this.ws = null;
    }

    this.wsConnected = false;
    this.notifyCallbacks((cb) => cb.onConnected?.(false));
    this.isReconnecting = false;

    this.ws = webSocket.createWebSocket();

    this.ws.on('open', (err: BusinessError) => {
      if (this.hasError(err)) {
        console.error('WebSocket 打开失败:', JSON.stringify(err));
        this.wsConnected = false;
        this.notifyCallbacks((cb) => cb.onConnected?.(false));
        this.scheduleReconnect();
        return;
      }

      console.info('WebSocket 连接成功');
      this.wsConnected = true;
      this.notifyCallbacks((cb) => cb.onConnected?.(true));
      this.isReconnecting = false;
      this.reconnectCount = 0;
    });

    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (this.hasError(err)) {
        console.error('接收消息失败:', JSON.stringify(err));
        return;
      }

      try {
        const msgStr = value as string;
        const msg = JSON.parse(msgStr) as WebSocketRawMessage;
        this.handleWebSocketMessage(msg);
      } catch (parseError) {
        console.error('解析消息失败:', parseError);
      }
    });

    this.ws.on('close', (_err: BusinessError, value: webSocket.CloseResult) => {
      console.info('WebSocket 连接关闭, code:', value.code, ', reason:', value.reason);
      this.wsConnected = false;
      this.notifyCallbacks((cb) => cb.onConnected?.(false));

      if (!this.isReconnecting && value.code !== 1000) {
        console.info('检测到异常关闭，将尝试重连');
        this.scheduleReconnect();
      } else if (value.code === 1000) {
        console.info('正常关闭连接，不重连');
        this.reconnectCount = 0;
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      if (this.hasError(err)) {
        console.error('WebSocket 错误:', JSON.stringify(err));
        this.wsConnected = false;
        this.notifyCallbacks((cb) => cb.onConnected?.(false));

        if (!this.isReconnecting) {
          this.scheduleReconnect();
        }
      }
    });

    const url = `ws://${SERVER_HOST}/ws`;
    console.info('正在连接 WebSocket:', url);

    this.ws.connect(url, (err: BusinessError) => {
      if (this.hasError(err)) {
        console.error('WebSocket 连接失败:', JSON.stringify(err));
        this.wsConnected = false;
        this.notifyCallbacks((cb) => cb.onConnected?.(false));
        this.scheduleReconnect();
      } else {
        console.info('WebSocket 连接请求已发送');
      }
    });
  }

  // 处理 WebSocket 消息
  private handleWebSocketMessage(msg: WebSocketRawMessage): void {
    if (!msg || !msg.type || typeof msg.type !== 'string') {
      console.warn('收到未知格式的消息:', msg);
      return;
    }

    const msgType = msg.type;
    switch (msgType) {
      case 'hello':
        console.info('收到服务器连接确认消息');
        break;
      case 'reading':
        const readingMsg: ReadingMessage = {
          type: msgType,
          device_id: msg.device_id,
          temp: msg.temp,
          hum: msg.hum,
          temp2: msg.temp2,
          ts: msg.ts,
          lux: msg.lux,
          smoke: msg.smoke,
          pressure: msg.pressure,
          rs_ro: msg.rs_ro
        };
        this.notifyCallbacks((cb) => cb.onReading?.(readingMsg));
        break;
      case 'location':
        const locationMsg: LocationMessage = {
          type: msgType,
          device_id: msg.device_id,
          lon: msg.lon,
          lat: msg.lat,
          utc: msg.utc,
          csq: msg.csq,
          iccid: msg.iccid,
          imei: msg.imei,
          location_type: msg.location_type
        };
        this.notifyCallbacks((cb) => cb.onLocation?.(locationMsg));
        break;
      case 'warning':
        // 处理警告通知消息
        const warningMsg: WarningNotificationMessage = {
          type: msgType,
          warning_type: msg.warning_type,
          warning_name: msg.warning_name,
          warning_value: msg.warning_value,
          warning_unit: msg.warning_unit,
          warning_message: msg.warning_message,
          device_id: msg.device_id || 'D01',
          timestamp: msg.timestamp || Date.now() / 1000
        };
        this.notifyCallbacks((cb) => cb.onWarning?.(warningMsg));
        break;
      case 'warning_resolved':
        const deviceId = msg.device_id || 'D01';
        this.notifyCallbacks((cb) => cb.onWarningResolved?.(deviceId));
        break;
      default:
        console.warn('未处理的消息类型:', msgType);
    }
  }

  // 断开连接
  public disconnect(): void {
    // 停止自动重连
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.isReconnecting = true;
    this.reconnectCount = 0;

    // 断开 WebSocket 连接
    if (this.ws) {
      this.ws.close((err: BusinessError) => {
        if (this.hasError(err)) {
          console.error('关闭连接失败:', JSON.stringify(err));
        } else {
          console.info('连接已关闭');
        }
        this.ws = null;
        this.wsConnected = false;
        this.notifyCallbacks((cb) => cb.onConnected?.(false));
      });
    }
  }

  // 获取连接状态
  public isConnected(): boolean {
    return this.wsConnected;
  }
}

