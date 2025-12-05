import { webSocket } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 服务器地址配置
export const SERVER_HOST = 'znhj.iepose.cn';

// 设备信息接口
export interface DeviceInfo {
  id: string;
  name?: string;
  device_id?: string;
  description?: string;
  has_ble?: boolean;
  has_mqtt?: boolean;
  via?: string[];
  online?: boolean;
}

// 设备实时数据接口
export interface DeviceRealtimeData {
  deviceId: string;
  temp?: number;
  hum?: number;
  ts?: number;
}

// 设备警告信息接口
export interface DeviceWarning {
  device_id: string;
  warning_name?: string;
  warning_value?: number | string;
  warning_unit?: string;
}

// WebSocket 消息接口
interface WebSocketMessage {
  type: string;
  device_id?: string;
  temp?: number;
  hum?: number;
  temp2?: number;
  ts?: number;
  warning_name?: string;
  warning_value?: number | string;
  warning_unit?: string;
}

// DevicesPage 视图更新回调接口
export interface DevicesPageViewCallbacks {
  onWsConnectedChanged: (connected: boolean) => void;
  onDevicesChanged: (devices: DeviceInfo[]) => void;
  onCountsChanged: (onlineCount: number, totalCount: number) => void;
  onRealtimeDataChanged: (data: Map<string, DeviceRealtimeData>) => void;
  onWarningsChanged: (warnings: Map<string, DeviceWarning>) => void;
  onDeviceLastSeenChanged: (lastSeen: Map<string, number>) => void;
}

// 设备离线超时时间(秒)
const DEVICE_OFFLINE_TIMEOUT = 10;

// 检查是否有真正的错误
function hasError(err: BusinessError | null | undefined): boolean {
  if (!err) {
    return false;
  }
  return !!(err.code || err.message || err.name || err.data);
}

// 规范化设备ID
function normalizeDeviceId(id: string | undefined): string {
  if (!id) return '';
  return String(id).trim().toUpperCase();
}

// DevicesPage 业务逻辑类
export class DevicesPageLogic {
  private callbacks: DevicesPageViewCallbacks;
  private devices: DeviceInfo[] = [];
  private realtimeData: Map<string, DeviceRealtimeData> = new Map();
  private warnings: Map<string, DeviceWarning> = new Map();
  private deviceLastSeen: Map<string, number> = new Map();
  private ws: webSocket.WebSocket | null = null;
  private reconnectTimer: number | null = null;
  private isReconnecting: boolean = false;
  private reconnectCount: number = 0;
  private readonly MAX_RECONNECT_COUNT = 10;
  private deviceStatusCheckInterval: number | null = null;
  private wsConnected: boolean = false;

  constructor(callbacks: DevicesPageViewCallbacks) {
    this.callbacks = callbacks;
  }

  // 判断设备是否在线
  private isDeviceOnline(deviceId: string): boolean {
    const normalizedId = normalizeDeviceId(deviceId);
    if (!normalizedId) return false;

    const lastSeen = this.deviceLastSeen.get(normalizedId);
    if (!lastSeen) {
      return false;
    }

    const now = Date.now() / 1000;
    const timeSinceLastSeen = now - lastSeen;
    return timeSinceLastSeen <= DEVICE_OFFLINE_TIMEOUT;
  }

  // 更新设备最后活跃时间
  private updateDeviceLastSeen(deviceId: string): void {
    const normalizedId = normalizeDeviceId(deviceId);
    if (!normalizedId) return;
    this.deviceLastSeen.set(normalizedId, Date.now() / 1000);
    this.callbacks.onDeviceLastSeenChanged(new Map(this.deviceLastSeen));
  }

  // 更新设备数量统计
  private updateDeviceCounts(): void {
    if (!this.devices || this.devices.length === 0) {
      this.callbacks.onCountsChanged(0, 0);
      return;
    }

    let onlineCount = 0;
    this.devices.forEach((dev) => {
      const deviceId = normalizeDeviceId(dev.id || dev.device_id || '');
      if (this.isDeviceOnline(deviceId)) {
        onlineCount++;
      }
    });

    this.callbacks.onCountsChanged(onlineCount, this.devices.length);
  }

  // 处理读数消息
  private handleReadingMessage(payload: WebSocketMessage): void {
    const deviceId = normalizeDeviceId(payload.device_id || 'D01');
    this.updateDeviceLastSeen(deviceId);

    const realtimeData: DeviceRealtimeData = {
      deviceId: deviceId,
      temp: typeof payload.temp === 'number' ? payload.temp : undefined,
      hum: typeof payload.hum === 'number' ? payload.hum : undefined,
      ts: payload.ts || Date.now() / 1000
    };

    this.realtimeData.set(deviceId, realtimeData);
    this.callbacks.onRealtimeDataChanged(new Map(this.realtimeData));
    this.updateDeviceCounts();
  }

  // 处理警告消息
  private handleWarningMessage(payload: WebSocketMessage): void {
    const deviceId = normalizeDeviceId(payload.device_id || 'D01');
    this.updateDeviceLastSeen(deviceId);

    const warning: DeviceWarning = {
      device_id: deviceId,
      warning_name: payload.warning_name,
      warning_value: payload.warning_value,
      warning_unit: payload.warning_unit
    };

    this.warnings.set(deviceId, warning);
    this.callbacks.onWarningsChanged(new Map(this.warnings));
    this.updateDeviceCounts();
  }

  // 处理恢复消息
  private handleResolvedMessage(payload: WebSocketMessage): void {
    const deviceId = normalizeDeviceId(payload.device_id || 'D01');
    this.updateDeviceLastSeen(deviceId);
    this.warnings.delete(deviceId);
    this.callbacks.onWarningsChanged(new Map(this.warnings));
    this.updateDeviceCounts();
  }

  // 处理 WebSocket 消息
  private handleWebSocketMessage(msg: WebSocketMessage): void {
    if (!msg || !msg.type) {
      console.warn('收到未知格式的消息:', msg);
      return;
    }

    switch (msg.type) {
      case 'hello':
        console.info('收到服务器连接确认消息');
        break;
      case 'reading':
        this.handleReadingMessage(msg);
        break;
      case 'warning':
        this.handleWarningMessage(msg);
        break;
      case 'warning_resolved':
        this.handleResolvedMessage(msg);
        break;
      default:
        console.warn('未处理的消息类型:', msg.type);
    }
  }

  // 检查所有设备状态
  private checkAllDevicesStatus(): void {
    this.updateDeviceCounts();
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
        this.connectWebSocket();
      }
    }, 1500);
    // setTimeout 返回 number 类型，直接赋值
    this.reconnectTimer = timerId as number;
  }

  // 建立 WebSocket 连接
  private connectWebSocket(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws) {
      try {
        this.ws.close((err: BusinessError) => {
          if (hasError(err)) {
            console.warn('关闭旧连接时出错:', JSON.stringify(err));
          }
        });
      } catch (e) {
        console.warn('关闭旧连接时异常:', e);
      }
      this.ws = null;
    }

    this.wsConnected = false;
    this.callbacks.onWsConnectedChanged(false);
    this.isReconnecting = false;

    this.ws = webSocket.createWebSocket();

    this.ws.on('open', (err: BusinessError) => {
      if (hasError(err)) {
        console.error('WebSocket 打开失败:', JSON.stringify(err));
        this.wsConnected = false;
        this.callbacks.onWsConnectedChanged(false);
        this.scheduleReconnect();
        return;
      }

      console.info('WebSocket 连接成功');
      this.wsConnected = true;
      this.callbacks.onWsConnectedChanged(true);
      this.isReconnecting = false;
      this.reconnectCount = 0;
    });

    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (hasError(err)) {
        console.error('接收消息失败:', JSON.stringify(err));
        return;
      }

      try {
        const msg: WebSocketMessage = JSON.parse(value as string) as WebSocketMessage;
        this.handleWebSocketMessage(msg);
      } catch (parseError) {
        console.error('解析消息失败:', parseError);
      }
    });

    this.ws.on('close', (_err: BusinessError, value: webSocket.CloseResult) => {
      console.info('WebSocket 连接关闭, code:', value.code, ', reason:', value.reason);
      this.wsConnected = false;
      this.callbacks.onWsConnectedChanged(false);

      if (!this.isReconnecting && value.code !== 1000) {
        console.info('检测到异常关闭，将尝试重连');
        this.scheduleReconnect();
      } else if (value.code === 1000) {
        console.info('正常关闭连接，不重连');
        this.reconnectCount = 0;
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      if (hasError(err)) {
        console.error('WebSocket 错误:', JSON.stringify(err));
        this.wsConnected = false;
        this.callbacks.onWsConnectedChanged(false);

        if (!this.isReconnecting) {
          this.scheduleReconnect();
        }
      }
    });

    const url = `ws://${SERVER_HOST}/ws`;
    console.info('正在连接 WebSocket:', url);

    this.ws.connect(url, (err: BusinessError) => {
      if (hasError(err)) {
        console.error('WebSocket 连接失败:', JSON.stringify(err));
        this.wsConnected = false;
        this.callbacks.onWsConnectedChanged(false);
        this.scheduleReconnect();
      } else {
        console.info('WebSocket 连接请求已发送');
      }
    });
  }

  // 加载设备列表
  async loadDevices(): Promise<void> {
    const httpRequest = http.createHttp();

    try {
      const url = `http://${SERVER_HOST}/api/devices`;
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET
      });

      if (response && response.responseCode === 200) {
        interface ApiResponse {
          success: boolean;
          devices?: DeviceInfo[];
          error?: string;
        }
        const result: ApiResponse = JSON.parse(response.result.toString()) as ApiResponse;
        if (result.success && result.devices) {
          // 规范化设备ID
          const normalizedDevices: DeviceInfo[] = [];
          for (let i = 0; i < result.devices.length; i++) {
            const d = result.devices[i];
            normalizedDevices.push({
              id: normalizeDeviceId(d.id || d.device_id || ''),
              name: d.name,
              device_id: d.device_id,
              description: d.description,
              has_ble: d.has_ble,
              has_mqtt: d.has_mqtt,
              via: d.via,
              online: d.online
            });
          }
          this.devices = normalizedDevices;
          this.callbacks.onDevicesChanged(this.devices);
          this.updateDeviceCounts();
          console.info('设备列表加载成功:', this.devices.length, '台设备');
        } else {
          console.error('获取设备列表失败:', result.error || '未知错误');
          this.devices = [];
          this.callbacks.onDevicesChanged([]);
        }
      } else {
        console.error('HTTP 请求失败:', response.responseCode);
        this.devices = [];
        this.callbacks.onDevicesChanged([]);
      }
    } catch (error) {
      console.error('加载设备列表失败:', error);
      this.devices = [];
      this.callbacks.onDevicesChanged([]);
    } finally {
      httpRequest.destroy();
    }
  }

  // 判断设备是否在线(公开方法)
  isDeviceOnlinePublic(deviceId: string): boolean {
    return this.isDeviceOnline(deviceId);
  }

  // 页面即将显示
  aboutToAppear(): void {
    this.loadDevices();
    this.connectWebSocket();
    // 启动设备状态检查定时器，每5秒检查一次
    const intervalId = setInterval(() => {
      this.checkAllDevicesStatus();
    }, 5000);
    // setInterval 返回 number 类型，直接赋值
    this.deviceStatusCheckInterval = intervalId as number;
  }

  // 页面即将隐藏
  aboutToDisappear(): void {
    // 停止设备状态检查定时器
    if (this.deviceStatusCheckInterval !== null) {
      clearInterval(this.deviceStatusCheckInterval);
      this.deviceStatusCheckInterval = null;
    }

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
        if (hasError(err)) {
          console.error('关闭连接失败:', JSON.stringify(err));
        } else {
          console.info('连接已关闭');
        }
        this.ws = null;
        this.wsConnected = false;
        this.callbacks.onWsConnectedChanged(false);
      });
    }
  }
}

