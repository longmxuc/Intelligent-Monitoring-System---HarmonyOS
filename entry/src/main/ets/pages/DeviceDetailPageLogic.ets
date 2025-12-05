import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 服务器地址配置
export const SERVER_HOST = 'znhj.iepose.cn';

// 传感器数据接口
interface SensorData {
  ts?: number; // 时间戳
  temp?: number; // 温度
  hum?: number; // 湿度
  lux?: number; // 光照
  smoke?: number; // 烟雾
  pressure?: number; // 气压
  temp2?: number; // 温度2
  rs_ro?: number; // 气体传感器比值
}

// WebSocket 消息接口
interface WebSocketMessage {
  type: string;
  device_id?: string; // 设备ID
  ts?: number;
  timestamp?: number;
  temp?: number;
  hum?: number;
  lux?: number;
  smoke?: number;
  pressure?: number;
  temp2?: number;
  rs_ro?: number;
  // 定位相关字段
  lon?: number;
  lat?: number;
  utc?: number | string;
  csq?: number;
  iccid?: string;
  imei?: string;
  location_type?: string;
}

// 趋势结果接口
export interface TrendResult {
  direction: 'up' | 'down' | 'stable'; // 趋势方向
  value: number; // 变化量
  text: string; // 显示文本
}

// 检查是否有真正的错误（错误对象可能存在但属性为空）
function hasError(err: BusinessError | null | undefined): boolean {
  if (!err) {
    return false;
  }
  // 检查错误对象的属性是否有值
  return !!(err.code || err.message || err.name || err.data);
}

// HomePage 视图接口，仅包含需要由逻辑层更新的字段
export interface HomePageView {
  wsConnected: boolean;
  temp: number | undefined;
  hum: number | undefined;
  lux: number | undefined;
  smoke: number | undefined;
  pressure: number | undefined;
  temp2: number | undefined;
  rs_ro: number | undefined;
  lastUpdateTime: string;
  sampleCount: number;
  tempTrend: TrendResult;
  humTrend: TrendResult;
  luxTrend: TrendResult;
  smokeTrend: TrendResult;
  pressureTrend: TrendResult;
  tempDiffTrend: TrendResult;
  // 定位展示字段
  locationStatus: string;
  locationStatusColor: string;
  locationLon: string;
  locationLat: string;
  locationExtra: string;
  locationAvailable: boolean;
  // 图表更新方法
  updateCharts?: (timestamp: number, temp: number, hum: number, lux: number, smoke: number, pressure: number) => void;
}

// HomePage 业务逻辑类：负责 WebSocket 连接与数据解析、趋势计算等
export class DeviceDetailPageLogic {
  private view: HomePageView;
  private deviceId: string; // 当前设备ID

  // 数据存储数组（用于趋势计算）
  private tempsAll: number[] = [];
  private humsAll: number[] = [];
  private luxAll: number[] = [];
  private smokeAll: number[] = [];
  private pressureAll: number[] = [];
  private tempDiffAll: number[] = [];

  // 趋势计算配置
  private readonly N_TREND = 2; // 使用最近2条数据计算趋势（快速响应）
  private readonly MAX_HISTORY = 1000; // 最大历史数据量
  private readonly STABLE_THRESHOLD = 0; // 稳定阈值（设为0，只要有变化就显示趋势）
  private lastDataTimestamp: number = 0; // 上次数据时间戳

  // WebSocket 连接管理
  private ws: webSocket.WebSocket | null = null;
  private reconnectTimer: number | null = null;
  private isReconnecting: boolean = false;
  private reconnectCount: number = 0;
  private readonly MAX_RECONNECT_COUNT = 10;

  constructor(view: HomePageView, deviceId: string = '') {
    this.view = view;
    this.deviceId = deviceId.trim().toUpperCase(); // 规范化设备ID
    console.info(`DeviceDetailPageLogic 构造函数 - deviceId: ${this.deviceId}`);
  }

  // 设置设备ID（用于延迟设置）
  setDeviceId(deviceId: string): void {
    this.deviceId = deviceId.trim().toUpperCase();
    console.info(`DeviceDetailPageLogic 设置 deviceId: ${this.deviceId}`);
  }

  // 计算数组首尾差值（用于趋势判断）
  private delta(arr: number[]): number {
    if (arr.length < 2) {
      return 0;
    }
    // 返回：最后一个值 - 第一个值
    return arr[arr.length - 1] - arr[0];
  }

  // 计算趋势
  private calculateTrend(dataArray: number[], unit: string): TrendResult {
    // 过滤NaN值
    const validData = dataArray.filter(x => !Number.isNaN(x));

    // 需要至少2条数据才能计算趋势
    if (validData.length < 2) {
      return { direction: 'stable', value: 0, text: '趋势稳定' };
    }

    // 获取最近N_TREND条数据（如果数据不足N_TREND条，就使用所有有效数据）
    const recentData = validData.slice(-this.N_TREND);

    // 确保至少有2条数据
    if (recentData.length < 2) {
      return { direction: 'stable', value: 0, text: '趋势稳定' };
    }

    const diff = this.delta(recentData);

    // 判断趋势方向（稳定阈值为0，只要有变化就显示）
    if (Math.abs(diff) <= this.STABLE_THRESHOLD) {
      return { direction: 'stable', value: 0, text: '趋势稳定' };
    } else if (diff > 0) {
      return {
        direction: 'up',
        value: diff,
        text: `上升 ${diff.toFixed(2)} ${unit}`
      };
    } else {
      return {
        direction: 'down',
        value: Math.abs(diff),
        text: `下降 ${Math.abs(diff).toFixed(2)} ${unit}`
      };
    }
  }

  // 处理定位数据并更新 UI
  private updateLocationInfo(data: WebSocketMessage): void {
    const lonVal = data.lon !== undefined ? Number(data.lon) : NaN;
    const latVal = data.lat !== undefined ? Number(data.lat) : NaN;

    if (Number.isNaN(lonVal) || Number.isNaN(latVal)) {
      this.view.locationStatus = '定位数据缺失';
      this.view.locationStatusColor = '#ef4444';
      this.view.locationLon = '--';
      this.view.locationLat = '--';
      this.view.locationExtra = '';
      this.view.locationAvailable = false;
      return;
    }

    // 格式化时间：支持 number(秒/毫秒) 与 ISO 字符串
    const formatUtc = (utcVal: number | string | undefined): string => {
      if (utcVal === undefined || utcVal === null) {
        return '';
      }
      if (typeof utcVal === 'number') {
        const ms = utcVal > 1e12 ? utcVal : utcVal * 1000;
        return new Date(ms).toLocaleString('zh-CN');
      }
      const date = new Date(utcVal);
      return Number.isNaN(date.getTime()) ? String(utcVal) : date.toLocaleString('zh-CN');
    };

    this.view.locationLon = lonVal.toFixed(6);
    this.view.locationLat = latVal.toFixed(6);
    this.view.locationAvailable = true;

    const extras: string[] = [];
    if (data.location_type) {
      extras.push(`类型: ${data.location_type}`);
    }
    if (data.csq !== undefined && data.csq !== null) {
      extras.push(`信号: ${data.csq}`);
    }
    const timeText = formatUtc(data.utc);
    if (timeText) {
      extras.push(`时间: ${timeText}`);
    }
    this.view.locationExtra = extras.join(' | ');

    this.view.locationStatus = '定位成功';
    this.view.locationStatusColor = '#22c55e';
  }

  // 更新所有趋势
  private updateTrends(): void {
    this.view.tempTrend = this.calculateTrend(this.tempsAll, '°C');
    this.view.humTrend = this.calculateTrend(this.humsAll, '%');
    this.view.luxTrend = this.calculateTrend(this.luxAll, 'lx');
    this.view.smokeTrend = this.calculateTrend(this.smokeAll, 'ppm');
    this.view.pressureTrend = this.calculateTrend(this.pressureAll, 'hPa');
    this.view.tempDiffTrend = this.calculateTrend(this.tempDiffAll, '°C');
  }

  // 更新传感器数据
  private updateSensorData(data: SensorData): void {
    console.info('更新传感器数据到 UI:', JSON.stringify(data));

    // 时间戳检查（防止添加旧数据）
    if (data.ts !== undefined && data.ts !== null) {
      if (this.lastDataTimestamp > 0 && data.ts <= this.lastDataTimestamp) {
        console.warn('跳过旧数据');
        return;
      }
      this.lastDataTimestamp = data.ts;
    }

    // 更新当前值显示
    this.view.temp = data.temp;
    this.view.hum = data.hum;
    this.view.lux = data.lux;
    this.view.smoke = data.smoke;
    this.view.pressure = data.pressure;
    this.view.temp2 = data.temp2;
    this.view.rs_ro = data.rs_ro;
    this.view.sampleCount++;

    // 更新图表（如果方法存在）
    if (this.view.updateCharts && data.ts !== undefined && data.temp !== undefined && data.hum !== undefined) {
      this.view.updateCharts(
        data.ts,
        data.temp,
        data.hum,
        data.lux ?? 0,
        data.smoke ?? 0,
        data.pressure ?? 0
      );
    }

    // 将数据添加到数组末尾
    if (data.temp !== undefined && data.temp !== null) {
      this.tempsAll.push(data.temp);
    }
    if (data.hum !== undefined && data.hum !== null) {
      this.humsAll.push(data.hum);
    }
    if (data.lux !== undefined && data.lux !== null) {
      this.luxAll.push(data.lux);
    } else {
      this.luxAll.push(NaN);
    }
    if (data.smoke !== undefined && data.smoke !== null) {
      this.smokeAll.push(data.smoke);
    } else {
      this.smokeAll.push(NaN);
    }
    if (data.pressure !== undefined && data.pressure !== null) {
      this.pressureAll.push(data.pressure);
    } else {
      this.pressureAll.push(NaN);
    }

    // 计算温差（如果有第二温度传感器）
    if (data.temp !== undefined && data.temp !== null &&
      data.temp2 !== undefined && data.temp2 !== null) {
      const diff = Math.abs(data.temp - data.temp2);
      this.tempDiffAll.push(diff);
    } else {
      this.tempDiffAll.push(NaN);
    }

    // 限制数组长度（防止内存溢出）
    if (this.tempsAll.length > this.MAX_HISTORY) {
      this.tempsAll.shift();
      this.humsAll.shift();
      this.luxAll.shift();
      this.smokeAll.shift();
      this.pressureAll.shift();
      this.tempDiffAll.shift();
    }

    // 计算并更新趋势
    this.updateTrends();

    // 更新上次更新时间
    const now = new Date();
    const formatTime = (num: number): string => num < 10 ? `0${num}` : `${num}`;
    this.view.lastUpdateTime =
      `${formatTime(now.getHours())}:${formatTime(now.getMinutes())}:${formatTime(now.getSeconds())}`;

    console.info('更新完成 - temp:', this.view.temp, 'hum:', this.view.hum, 'sampleCount:', this.view.sampleCount);
  }

  // 处理 WebSocket 消息
  private handleWebSocketMessage(msg: WebSocketMessage): void {
    if (!msg || !msg.type) {
      console.warn('收到未知格式的消息:', msg);
      return;
    }

    // 打印原始消息用于调试
    console.info('收到WebSocket消息:', JSON.stringify(msg));

    // 处理连接成功消息
    if (msg.type === 'hello') {
      console.info('收到服务器连接确认消息');
      return;
    }

    // 过滤设备ID：只处理当前设备的消息
    const msgDeviceId = msg.device_id ? msg.device_id.trim().toUpperCase() : '';
    
    // 对于包含device_id的消息，只处理匹配当前设备的消息
    if (msgDeviceId && msgDeviceId !== this.deviceId) {
      console.info(`跳过其他设备的消息: ${msgDeviceId} (当前设备: ${this.deviceId})`);
      return;
    }

    // 处理警告通知
    if (msg.type === 'warning') {
      console.warn('收到警告消息:', msg);
      return;
    }

    // 处理恢复通知
    if (msg.type === 'warning_resolved') {
      console.info('收到恢复消息:', msg);
      return;
    }

    // 处理定位数据
    if (msg.type === 'location') {
      console.info('收到定位数据:', msg);
      this.updateLocationInfo(msg);
      return;
    }

    // 处理传感器读数数据
    if (msg.type === 'reading') {
      const sensorData: SensorData = {
        ts: msg.ts,
        temp: msg.temp,
        hum: msg.hum,
        lux: msg.lux,
        smoke: msg.smoke,
        pressure: msg.pressure,
        temp2: msg.temp2,
        rs_ro: msg.rs_ro
      };
      this.updateSensorData(sensorData);
      return;
    }

    console.warn('未处理的消息类型:', msg.type);
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
      if (!this.view.wsConnected) {
        console.info('开始重连 WebSocket...');
        this.connectWebSocket();
      }
    }, 1500);
    this.reconnectTimer = timerId as number;
  }

  // 建立 WebSocket 连接
  private connectWebSocket(): void {
    // 如果正在重连，先清除定时器
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    // 如果已有连接，先关闭
    if (this.ws) {
      try {
        this.ws.close((err: BusinessError, value: boolean) => {
          if (hasError(err)) {
            console.warn('关闭旧连接时出错:', JSON.stringify(err));
          }
        });
      } catch (e) {
        console.warn('关闭旧连接时异常:', e);
      }
      this.ws = null;
    }

    // 更新连接状态为未连接
    this.view.wsConnected = false;
    this.isReconnecting = false;

    // 创建 WebSocket 对象
    this.ws = webSocket.createWebSocket();

    // 订阅 WebSocket 打开事件
    this.ws.on('open', (err: BusinessError, value: Object) => {
      if (hasError(err)) {
        console.error('WebSocket 打开失败:', JSON.stringify(err));
        this.view.wsConnected = false;
        this.scheduleReconnect();
        return;
      }

      console.info('WebSocket 连接成功');
      this.view.wsConnected = true;
      this.isReconnecting = false;
      this.reconnectCount = 0;
      // 连接成功后等待定位推送
      this.view.locationStatus = '等待定位数据';
      this.view.locationStatusColor = '#f59e0b';
      this.view.locationLon = '--';
      this.view.locationLat = '--';
      this.view.locationExtra = '';
      this.view.locationAvailable = false;
    });

    // 订阅消息接收事件
    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (hasError(err)) {
        console.error('接收消息失败:', JSON.stringify(err));
        return;
      }

      try {
        // 解析 JSON 消息
        const msg: WebSocketMessage = JSON.parse(value as string) as WebSocketMessage;
        this.handleWebSocketMessage(msg);
      } catch (parseError) {
        console.error('解析消息失败:', parseError);
      }
    });

    // 订阅关闭事件
    this.ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      console.info('WebSocket 连接关闭, code:', value.code, ', reason:', value.reason);
      this.view.wsConnected = false;
      this.view.locationStatus = '定位未连接';
      this.view.locationStatusColor = '#9ca3af';
      this.view.locationLon = '--';
      this.view.locationLat = '--';
      this.view.locationExtra = '';
      this.view.locationAvailable = false;

      if (!this.isReconnecting && value.code !== 1000) {
        console.info('检测到异常关闭，将尝试重连');
        this.scheduleReconnect();
      } else if (value.code === 1000) {
        console.info('正常关闭连接，不重连');
        this.reconnectCount = 0;
      }
    });

    // 订阅错误事件
    this.ws.on('error', (err: BusinessError) => {
      if (hasError(err)) {
        console.error('WebSocket 错误:', JSON.stringify(err));
        this.view.wsConnected = false;

        if (!this.isReconnecting) {
          this.scheduleReconnect();
        }
      }
    });

    // 发起连接，拼接ws服务器地址
    const url = `ws://${SERVER_HOST}/ws`;
    console.info('正在连接 WebSocket:', url);

    this.ws.connect(url, (err: BusinessError, value: boolean) => {
      if (hasError(err)) {
        console.error('WebSocket 连接失败:', JSON.stringify(err));
        this.view.wsConnected = false;
        this.scheduleReconnect();
      } else {
        console.info('WebSocket 连接请求已发送');
      }
    });
  }

  // 页面即将显示：建立连接
  aboutToAppear(): void {
    this.connectWebSocket();
  }

  // 页面即将隐藏：清理连接与定时器
  aboutToDisappear(): void {
    // 停止自动重连
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.isReconnecting = true; // 标记为主动断开，不自动重连
    this.reconnectCount = 0;

    // 断开 WebSocket 连接
    if (this.ws) {
      this.ws.close((err: BusinessError, value: boolean) => {
        if (hasError(err)) {
          console.error('关闭连接失败:', JSON.stringify(err));
        } else {
          console.info('连接已关闭');
        }
        this.ws = null;
        this.view.wsConnected = false;
      });
    }
  }
}
