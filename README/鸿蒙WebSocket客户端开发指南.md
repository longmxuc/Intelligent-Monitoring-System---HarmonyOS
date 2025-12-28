# 鸿蒙 WebSocket 客户端开发指南

本文档基于 `index.html` 中的 WebSocket 连接实现，提供鸿蒙（HarmonyOS）前端连接 WebSocket 的完整开发步骤。

ws地址在'znhj.iepose.cn/ws中'

## 一、导入模块

```typescript
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
```

## 二、WebSocket 连接实现

### 1. 定义连接参数和状态

```typescript
// WebSocket 连接对象
let ws: webSocket.WebSocket | null = null;

// 服务器地址（根据实际部署情况修改）
const SERVER_HOST = 'your-server-ip:port'; // 例如: '192.168.1.100:8080'
const USE_SSL = false; // 根据服务器配置选择 true (wss) 或 false (ws)

// 连接状态
let isConnected: boolean = false;
let isReconnecting: boolean = false;
let reconnectTimer: number | null = null;
let isLoadingHistory: boolean = false; // 是否正在加载历史数据

// 构建 WebSocket URL
function buildWebSocketUrl(): string {
  const protocol = USE_SSL ? 'wss://' : 'ws://';
  return `${protocol}${SERVER_HOST}/ws`;
}
```

### 2. 创建 WebSocket 连接函数

```typescript
function connect(): void {
  // 如果正在重连，先清除定时器
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  // 更新连接状态为未连接
  setWsStatus(false);
  isReconnecting = false;

  // 创建 WebSocket 对象
  ws = webSocket.createWebSocket();

  // 订阅 WebSocket 打开事件
  ws.on('open', (err: BusinessError, value: Object) => {
    if (err) {
      console.error('WebSocket 打开失败:', JSON.stringify(err));
      setWsStatus(false);
      scheduleReconnect();
      return;
    }

    console.info('WebSocket 连接成功:', JSON.stringify(value));
    setWsStatus(true);
    isConnected = true;
    isReconnecting = false;
    
    // 连接成功后更新连接状态（如果需要）
    updateConnectionStatus();
  });

  // 订阅消息接收事件
  ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
    if (err) {
      console.error('接收消息失败:', JSON.stringify(err));
      return;
    }

    try {
      // 将消息转换为字符串（如果是 ArrayBuffer）
      let messageStr: string;
      if (typeof value === 'string') {
        messageStr = value;
      } else {
        // ArrayBuffer 转字符串
        const decoder = new TextDecoder('utf-8');
        messageStr = decoder.decode(value);
      }

      // 解析 JSON 消息
      const msg = JSON.parse(messageStr);
      handleWebSocketMessage(msg);
    } catch (parseError) {
      console.error('解析消息失败:', parseError);
    }
  });

  // 订阅关闭事件
  ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
    console.info('WebSocket 连接关闭, code:', value.code, ', reason:', value.reason);
    setWsStatus(false);
    isConnected = false;
    updateConnectionStatus();

    // 如果不是主动关闭，则自动重连
    if (!isReconnecting) {
      scheduleReconnect();
    }
  });

  // 订阅错误事件
  ws.on('error', (err: BusinessError) => {
    console.error('WebSocket 错误:', JSON.stringify(err));
    setWsStatus(false);
    isConnected = false;
    
    // 发生错误时，如果不是正在重连，则安排重连
    if (!isReconnecting) {
      scheduleReconnect();
    }
  });

  // 发起连接
  const url = buildWebSocketUrl();
  console.info('正在连接 WebSocket:', url);
  
  ws.connect(url, (err: BusinessError, value: boolean) => {
    if (err) {
      console.error('WebSocket 连接失败:', JSON.stringify(err));
      setWsStatus(false);
      scheduleReconnect();
    } else {
      console.info('WebSocket 连接请求已发送');
    }
  });
}
```

### 3. 自动重连机制

```typescript
function scheduleReconnect(): void {
  if (isReconnecting) {
    return; // 已经在重连中，避免重复
  }

  isReconnecting = true;
  console.info('1.5 秒后尝试重新连接...');

  // 1.5 秒后重连（与 index.html 保持一致）
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    if (!isConnected) {
      console.info('开始重连 WebSocket...');
      connect();
    }
  }, 1500) as unknown as number;
}
```

### 4. 消息处理函数

```typescript
function handleWebSocketMessage(msg: any): void {
  if (!msg || !msg.type) {
    console.warn('收到未知格式的消息:', msg);
    return;
  }

  // 处理警告通知
  if (msg.type === 'warning') {
    handleWarningMessage(msg);
    return;
  }

  // 处理恢复通知
  if (msg.type === 'warning_resolved') {
    handleResolvedMessage(msg);
    return;
  }

  // 处理定位数据
  if (msg.type === 'location') {
    handleLocationData(msg);
    return;
  }

  // 如果正在加载历史数据，暂时忽略实时数据
  if (isLoadingHistory) {
    console.log('⏸️ 正在加载历史数据，暂时跳过实时数据');
    return;
  }

  // 处理传感器读数数据
  if (msg.type === 'reading') {
    handleReadingData(msg);
    return;
  }

  console.warn('未处理的消息类型:', msg.type);
}

// 处理传感器读数数据
function handleReadingData(msg: any): void {
  // 根据实际业务逻辑处理数据
  // msg 包含: ts, temp, hum, lux, smoke, pressure, temp2, rs_ro 等字段
  console.info('收到传感器数据:', {
    timestamp: msg.ts,
    temperature: msg.temp,
    humidity: msg.hum,
    lux: msg.lux,
    smoke: msg.smoke,
    pressure: msg.pressure,
    temp2: msg.temp2,
    rs_ro: msg.rs_ro
  });

  // 更新 UI 显示
  updateSensorDisplay(msg);
}

// 处理警告消息
function handleWarningMessage(msg: any): void {
  console.warn('收到警告消息:', msg);
  // 显示警告通知、更新消息中心等
}

// 处理恢复消息
function handleResolvedMessage(msg: any): void {
  console.info('收到恢复消息:', msg);
  // 更新消息中心状态等
}

// 处理定位数据
function handleLocationData(msg: any): void {
  console.info('收到定位数据:', msg);
  // 更新地图显示等
  // msg 包含: lon, lat, utc, csq 等字段
}
```

### 5. 连接状态管理

```typescript
// 更新连接状态显示
function setWsStatus(connected: boolean): void {
  isConnected = connected;
  // 更新 UI 状态指示器
  // 例如：更新状态徽章、连接指示灯等
}

// 更新连接状态（可调用后端 API 获取详细状态）
async function updateConnectionStatus(): Promise<void> {
  try {
    // 可以调用后端 API 获取蓝牙、MQTT 等连接状态
    // const response = await fetch('/api/status');
    // const data = await response.json();
    // 更新 UI 显示
  } catch (error) {
    console.error('更新连接状态失败:', error);
  }
}
```

### 6. 手动断开连接

```typescript
function disconnect(): void {
  // 停止自动重连
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  isReconnecting = true; // 标记为主动断开，不自动重连

  if (ws) {
    ws.close((err: BusinessError, value: boolean) => {
      if (err) {
        console.error('关闭连接失败:', JSON.stringify(err));
      } else {
        console.info('连接已关闭');
      }
      ws = null;
      setWsStatus(false);
    });
  }
}
```

### 7. 发送消息（如需要）

```typescript
function sendMessage(message: string): void {
  if (!ws || !isConnected) {
    console.error('WebSocket 未连接，无法发送消息');
    return;
  }

  ws.send(message, (err: BusinessError, value: boolean) => {
    if (err) {
      console.error('发送消息失败:', JSON.stringify(err));
    } else {
      console.info('消息发送成功');
    }
  });
}
```

## 三、完整示例代码

```typescript
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class WebSocketClient {
  private ws: webSocket.WebSocket | null = null;
  private isConnected: boolean = false;
  private isReconnecting: boolean = false;
  private reconnectTimer: number | null = null;
  private isLoadingHistory: boolean = false;
  
  private readonly SERVER_HOST: string = 'your-server-ip:port';
  private readonly USE_SSL: boolean = false;

  // 构建 WebSocket URL
  private buildWebSocketUrl(): string {
    const protocol = this.USE_SSL ? 'wss://' : 'ws://';
    return `${protocol}${this.SERVER_HOST}/ws`;
  }

  // 连接 WebSocket
  public connect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this.setWsStatus(false);
    this.isReconnecting = false;

    this.ws = webSocket.createWebSocket();

    this.ws.on('open', (err: BusinessError, value: Object) => {
      if (err) {
        console.error('WebSocket 打开失败:', JSON.stringify(err));
        this.setWsStatus(false);
        this.scheduleReconnect();
        return;
      }

      console.info('WebSocket 连接成功');
      this.setWsStatus(true);
      this.isConnected = true;
      this.isReconnecting = false;
      this.updateConnectionStatus();
    });

    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err) {
        console.error('接收消息失败:', JSON.stringify(err));
        return;
      }

      try {
        let messageStr: string;
        if (typeof value === 'string') {
          messageStr = value;
        } else {
          const decoder = new TextDecoder('utf-8');
          messageStr = decoder.decode(value);
        }

        const msg = JSON.parse(messageStr);
        this.handleWebSocketMessage(msg);
      } catch (parseError) {
        console.error('解析消息失败:', parseError);
      }
    });

    this.ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      console.info('WebSocket 连接关闭, code:', value.code);
      this.setWsStatus(false);
      this.isConnected = false;
      this.updateConnectionStatus();

      if (!this.isReconnecting) {
        this.scheduleReconnect();
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      console.error('WebSocket 错误:', JSON.stringify(err));
      this.setWsStatus(false);
      this.isConnected = false;

      if (!this.isReconnecting) {
        this.scheduleReconnect();
      }
    });

    const url = this.buildWebSocketUrl();
    console.info('正在连接 WebSocket:', url);

    this.ws.connect(url, (err: BusinessError, value: boolean) => {
      if (err) {
        console.error('WebSocket 连接失败:', JSON.stringify(err));
        this.setWsStatus(false);
        this.scheduleReconnect();
      } else {
        console.info('WebSocket 连接请求已发送');
      }
    });
  }

  // 自动重连
  private scheduleReconnect(): void {
    if (this.isReconnecting) {
      return;
    }

    this.isReconnecting = true;
    console.info('1.5 秒后尝试重新连接...');

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.isConnected) {
        console.info('开始重连 WebSocket...');
        this.connect();
      }
    }, 1500) as unknown as number;
  }

  // 处理消息
  private handleWebSocketMessage(msg: any): void {
    if (!msg || !msg.type) {
      console.warn('收到未知格式的消息:', msg);
      return;
    }

    switch (msg.type) {
      case 'warning':
        this.handleWarningMessage(msg);
        break;
      case 'warning_resolved':
        this.handleResolvedMessage(msg);
        break;
      case 'location':
        this.handleLocationData(msg);
        break;
      case 'reading':
        if (!this.isLoadingHistory) {
          this.handleReadingData(msg);
        } else {
          console.log('⏸️ 正在加载历史数据，暂时跳过实时数据');
        }
        break;
      default:
        console.warn('未处理的消息类型:', msg.type);
    }
  }

  // 处理传感器数据
  private handleReadingData(msg: any): void {
    // 实现数据更新逻辑
    console.info('收到传感器数据:', msg);
  }

  // 处理警告消息
  private handleWarningMessage(msg: any): void {
    console.warn('收到警告消息:', msg);
  }

  // 处理恢复消息
  private handleResolvedMessage(msg: any): void {
    console.info('收到恢复消息:', msg);
  }

  // 处理定位数据
  private handleLocationData(msg: any): void {
    console.info('收到定位数据:', msg);
  }

  // 更新连接状态
  private setWsStatus(connected: boolean): void {
    this.isConnected = connected;
    // 更新 UI
  }

  // 更新连接状态详情
  private async updateConnectionStatus(): Promise<void> {
    // 实现状态更新逻辑
  }

  // 断开连接
  public disconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.isReconnecting = true;

    if (this.ws) {
      this.ws.close((err: BusinessError, value: boolean) => {
        if (err) {
          console.error('关闭连接失败:', JSON.stringify(err));
        } else {
          console.info('连接已关闭');
        }
        this.ws = null;
        this.setWsStatus(false);
      });
    }
  }

  // 发送消息
  public sendMessage(message: string): void {
    if (!this.ws || !this.isConnected) {
      console.error('WebSocket 未连接，无法发送消息');
      return;
    }

    this.ws.send(message, (err: BusinessError, value: boolean) => {
      if (err) {
        console.error('发送消息失败:', JSON.stringify(err));
      } else {
        console.info('消息发送成功');
      }
    });
  }
}
```

## 四、使用示例

```typescript
// 创建 WebSocket 客户端实例
const wsClient = new WebSocketClient();

// 连接 WebSocket
wsClient.connect();

// 在组件销毁时断开连接
// wsClient.disconnect();
```

## 五、注意事项

1. **URL 配置**：根据实际服务器地址和端口修改 `SERVER_HOST`，根据是否使用 SSL 修改 `USE_SSL`。

2. **自动重连**：实现了与 `index.html` 相同的 1.5 秒自动重连机制。

3. **消息格式**：服务器发送的消息为 JSON 格式，包含 `type` 字段用于区分消息类型。

4. **消息类型**：
   - `reading`: 传感器读数数据
   - `warning`: 警告通知
   - `warning_resolved`: 警告恢复通知
   - `location`: 定位数据

5. **历史数据加载**：在加载历史数据期间，会暂时忽略实时数据，避免数据冲突。

6. **错误处理**：所有 WebSocket 操作都包含错误处理，确保应用稳定性。

7. **权限配置**：在 `module.json5` 中需要配置网络权限：
   ```json
   {
     "requestPermissions": [
       {
         "name": "ohos.permission.INTERNET"
       }
     ]
   }
   ```

## 六、与 index.html 的对应关系

| index.html 功能 | 鸿蒙实现 |
|---------------|---------|
| `new WebSocket(url)` | `webSocket.createWebSocket()` + `ws.connect(url)` |
| `wsock.onopen` | `ws.on('open', ...)` |
| `wsock.onmessage` | `ws.on('message', ...)` |
| `wsock.onclose` | `ws.on('close', ...)` |
| `setTimeout(connect, 1500)` | `scheduleReconnect()` 函数 |
| `JSON.parse(e.data)` | `JSON.parse(messageStr)` |
| 消息类型判断 | `handleWebSocketMessage()` 中的 switch 语句 |

