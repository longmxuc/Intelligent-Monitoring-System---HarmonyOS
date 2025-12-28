# WebSocket 连接与数据解析开发指南

本文档详细说明如何连接后端 WebSocket 服务器并解析实时传感器数据，供鸿蒙前端开发参考。

## 📋 目录

1. [WebSocket 连接流程](#websocket-连接流程)
2. [消息格式说明](#消息格式说明)
3. [鸿蒙代码实现](#鸿蒙代码实现)
4. [数据解析示例](#数据解析示例)
5. [错误处理](#错误处理)
6. [完整示例代码](#完整示例代码)

---

## 🔌 WebSocket 连接流程

### 1. 连接地址

- **协议**：根据服务器协议自动选择
  - HTTP → `ws://`
  - HTTPS → `wss://`
- **路径**：`/ws`
- **完整地址示例**：
  
  目前已开机的后端服务器位于地址znhj.iepose.cn。这里即是后端FastAPI的/

### 2. 连接流程

```
1. 创建 WebSocket 连接
   ↓
2. 连接成功后，服务器会立即发送 "hello" 消息
   ↓
3. 持续接收实时数据（传感器数据、警告、定位等）
   ↓
4. 连接断开后，自动重连（建议延迟 1.5 秒）
```

### 3. 服务器端实现（参考）

```python
# server.py 第 1959-1973 行
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    connections.add(ws)
    # 连接成功后立即发送 hello 消息
    await ws.send_text(json.dumps({"type": "hello", "msg": "connected"}))
    # 保持连接，等待客户端断开
    while True:
        await asyncio.sleep(60)  # 保活
```

---

## 📨 消息格式说明

所有消息都是 **JSON 格式**，包含 `type` 字段用于区分消息类型。

### 1. 连接确认消息（hello）

**触发时机**：连接成功后立即发送

```json
{
  "type": "hello",
  "msg": "connected"
}
```

**字段说明**：
- `type`: 固定为 `"hello"`
- `msg`: 固定为 `"connected"`

---

### 2. 传感器读数数据（reading）

**触发时机**：每 10 秒收到一次传感器数据（来自蓝牙或 MQTT）

```json
{
  "type": "reading",
  "ts": 1704067200.123,
  "temp": 24.61,
  "hum": 45.78,
  "lux": 0.0,
  "smoke": 3.4,
  "pressure": 1014.23,
  "temp2": 26.10,
  "rs_ro": 1.01
}
```

**字段说明**：

| 字段 | 类型 | 说明 | 单位 | 可能为 null |
|------|------|------|------|------------|
| `type` | string | 固定为 `"reading"` | - | ❌ |
| `ts` | number | Unix 时间戳（秒，浮点数） | 秒 | ❌ |
| `temp` | number | 温度（传感器1） | °C | ❌ |
| `hum` | number | 湿度 | % | ❌ |
| `lux` | number | 亮度 | lx | ✅ |
| `smoke` | number | 烟雾浓度 | ppm | ✅ |
| `pressure` | number | 大气压 | hPa | ✅ |
| `temp2` | number | 温度（传感器2，备用） | °C | ✅ |
| `rs_ro` | number | 气体传感器电阻比值 | - | ✅ |

**注意事项**：
- `lux`、`smoke`、`pressure`、`temp2`、`rs_ro` 可能为 `null`（传感器未启用或数据缺失）
- `ts` 是 Unix 时间戳，需要转换为本地时间显示
- 数据更新频率：约每 10 秒一次

**后端生成代码位置**：`server.py` 第 203-227 行

```python
payload = {
    "type": "reading",
    "ts": ts,
    "temp": round(t, 2),
    "hum": round(h, 2),
    "lux": None if lux is None else round(lux, 1),
    "smoke": None if smoke is None else round(smoke, 1),
    "pressure": None if pressure is None else round(pressure, 1),
    "temp2": None if temp2 is None else round(temp2, 2),
    "rs_ro": None if rs_ro is None else round(rs_ro, 2),
}
```

---

### 3. 警告通知（warning）

**触发时机**：传感器值超出正常范围时

```json
{
  "type": "warning",
  "warning_type": "T",
  "warning_name": "温度",
  "warning_value": 32.25,
  "warning_unit": "°C",
  "warning_message": "DT32.25",
  "timestamp": 1704067200.123
}
```

**字段说明**：

| 字段 | 类型 | 说明 | 可能值 |
|------|------|------|--------|
| `type` | string | 固定为 `"warning"` | - |
| `warning_type` | string | 警告类型代码 | `T`(温度), `H`(湿度), `B`(亮度), `S`(PPM), `P`(大气压) |
| `warning_name` | string | 警告类型中文名称 | `温度`, `湿度`, `亮度`, `PPM`, `大气压` |
| `warning_value` | number | 异常值 | - |
| `warning_unit` | string | 单位 | `°C`, `%`, `lux`, `ppm`, `hPa` |
| `warning_message` | string | 原始警告消息 | 如 `DT32.25` |
| `timestamp` | number | Unix 时间戳 | - |

**后端生成代码位置**：`server.py` 第 635-644 行

---

### 4. 警告恢复通知（warning_resolved）

**触发时机**：传感器值恢复正常时（自动恢复或手动恢复）

```json
{
  "type": "warning_resolved",
  "warning_type": "T",
  "warning_name": "温度",
  "timestamp": 1704067200.123,
  "auto_recovered": true
}
```

**字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | string | 固定为 `"warning_resolved"` |
| `warning_type` | string | 警告类型代码 |
| `warning_name` | string | 警告类型中文名称 |
| `timestamp` | number | Unix 时间戳 |
| `auto_recovered` | boolean | 是否为自动恢复（可选） |

**后端生成代码位置**：`server.py` 第 298-305 行（自动恢复）或 572-578 行（手动恢复）

---

### 5. 定位数据（location）

**触发时机**：设备返回定位信息时（通过 MQTT 查询定位后）

```json
{
  "type": "location",
  "lon": 118.0412,
  "lat": 24.37883,
  "utc": "2025-11-04T14:59:53Z",
  "iccid": "898604011025D0227746",
  "imei": "864865082106973",
  "csq": 31,
  "location_type": "LBS",
  "timestamp": 1704067200.123
}
```

**字段说明**：

| 字段 | 类型 | 说明 | 可能为 null |
|------|------|------|------------|
| `type` | string | 固定为 `"location"` | ❌ |
| `lon` | number | 经度 | ❌ |
| `lat` | number | 纬度 | ❌ |
| `utc` | string | UTC 时间（ISO 8601 格式） | ✅ |
| `iccid` | string | SIM 卡 ICCID | ✅ |
| `imei` | string | 设备 IMEI | ✅ |
| `csq` | number | 信号强度（0-31，越大越好） | ✅ |
| `location_type` | string | 定位类型（如 `LBS`） | ✅ |
| `timestamp` | number | Unix 时间戳 | ❌ |

**后端生成代码位置**：`server.py` 第 464-475 行

---

## 💻 鸿蒙代码实现

### 1. 导入模块

```typescript
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
```

### 2. 定义数据接口

```typescript
// 传感器读数数据
interface ReadingData {
  type: 'reading';
  ts: number;
  temp: number;
  hum: number;
  lux: number | null;
  smoke: number | null;
  pressure: number | null;
  temp2: number | null;
  rs_ro: number | null;
}

// 警告通知
interface WarningData {
  type: 'warning';
  warning_type: 'T' | 'H' | 'B' | 'S' | 'P';
  warning_name: string;
  warning_value: number;
  warning_unit: string;
  warning_message: string;
  timestamp: number;
}

// 警告恢复通知
interface WarningResolvedData {
  type: 'warning_resolved';
  warning_type: 'T' | 'H' | 'B' | 'S' | 'P';
  warning_name: string;
  timestamp: number;
  auto_recovered?: boolean;
}

// 定位数据
interface LocationData {
  type: 'location';
  lon: number;
  lat: number;
  utc?: string;
  iccid?: string;
  imei?: string;
  csq?: number;
  location_type?: string;
  timestamp: number;
}

// Hello 消息
interface HelloData {
  type: 'hello';
  msg: string;
}

// 所有消息类型的联合
type WebSocketMessage = ReadingData | WarningData | WarningResolvedData | LocationData | HelloData;
```

### 3. WebSocket 客户端类

```typescript
export class SensorWebSocketClient {
  private ws: webSocket.WebSocket | null = null;
  private isConnected: boolean = false;
  private isReconnecting: boolean = false;
  private reconnectTimer: number | null = null;
  private isLoadingHistory: boolean = false; // 是否正在加载历史数据

  // 服务器配置
  private readonly SERVER_HOST: string = '192.168.1.100:8000'; // 修改为实际服务器地址
  private readonly USE_SSL: boolean = false; // 根据实际情况设置

  // 回调函数
  private onReadingCallback?: (data: ReadingData) => void;
  private onWarningCallback?: (data: WarningData) => void;
  private onWarningResolvedCallback?: (data: WarningResolvedData) => void;
  private onLocationCallback?: (data: LocationData) => void;
  private onConnectedCallback?: () => void;
  private onDisconnectedCallback?: () => void;
  private onErrorCallback?: (error: string) => void;

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

    this.setConnectionStatus(false);
    this.isReconnecting = false;

    this.ws = webSocket.createWebSocket();

    // 订阅打开事件
    this.ws.on('open', (err: BusinessError, value: Object) => {
      if (err) {
        console.error('WebSocket 打开失败:', JSON.stringify(err));
        this.setConnectionStatus(false);
        this.scheduleReconnect();
        if (this.onErrorCallback) {
          this.onErrorCallback(`连接失败: ${JSON.stringify(err)}`);
        }
        return;
      }

      console.info('WebSocket 连接成功');
      this.setConnectionStatus(true);
      this.isConnected = true;
      this.isReconnecting = false;

      if (this.onConnectedCallback) {
        this.onConnectedCallback();
      }
    });

    // 订阅消息接收事件
    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err) {
        console.error('接收消息失败:', JSON.stringify(err));
        return;
      }

      try {
        // 将消息转换为字符串
        let messageStr: string;
        if (typeof value === 'string') {
          messageStr = value;
        } else {
          const decoder = new TextDecoder('utf-8');
          messageStr = decoder.decode(value);
        }

        // 解析 JSON 消息
        const msg: WebSocketMessage = JSON.parse(messageStr);
        this.handleWebSocketMessage(msg);
      } catch (parseError) {
        console.error('解析消息失败:', parseError);
        if (this.onErrorCallback) {
          this.onErrorCallback(`消息解析失败: ${parseError}`);
        }
      }
    });

    // 订阅关闭事件
    this.ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      console.info('WebSocket 连接关闭, code:', value.code, ', reason:', value.reason);
      this.setConnectionStatus(false);
      this.isConnected = false;

      if (this.onDisconnectedCallback) {
        this.onDisconnectedCallback();
      }

      // 如果不是主动关闭，则自动重连
      if (!this.isReconnecting) {
        this.scheduleReconnect();
      }
    });

    // 订阅错误事件
    this.ws.on('error', (err: BusinessError) => {
      console.error('WebSocket 错误:', JSON.stringify(err));
      this.setConnectionStatus(false);
      this.isConnected = false;

      if (this.onErrorCallback) {
        this.onErrorCallback(`WebSocket 错误: ${JSON.stringify(err)}`);
      }

      // 如果不是正在重连，则安排重连
      if (!this.isReconnecting) {
        this.scheduleReconnect();
      }
    });

    // 发起连接
    const url = this.buildWebSocketUrl();
    console.info('正在连接 WebSocket:', url);

    this.ws.connect(url, (err: BusinessError, value: boolean) => {
      if (err) {
        console.error('WebSocket 连接失败:', JSON.stringify(err));
        this.setConnectionStatus(false);
        this.scheduleReconnect();
        if (this.onErrorCallback) {
          this.onErrorCallback(`连接失败: ${JSON.stringify(err)}`);
        }
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

    // 1.5 秒后重连（与 Web 前端保持一致）
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.isConnected) {
        console.info('开始重连 WebSocket...');
        this.connect();
      }
    }, 1500) as unknown as number;
  }

  // 处理消息
  private handleWebSocketMessage(msg: WebSocketMessage): void {
    if (!msg || !msg.type) {
      console.warn('收到未知格式的消息:', msg);
      return;
    }

    switch (msg.type) {
      case 'hello':
        console.info('收到连接确认消息:', (msg as HelloData).msg);
        break;

      case 'reading':
        // 如果正在加载历史数据，暂时忽略实时数据
        if (this.isLoadingHistory) {
          console.log('⏸️ 正在加载历史数据，暂时跳过实时数据');
          return;
        }
        if (this.onReadingCallback) {
          this.onReadingCallback(msg as ReadingData);
        }
        break;

      case 'warning':
        if (this.onWarningCallback) {
          this.onWarningCallback(msg as WarningData);
        }
        break;

      case 'warning_resolved':
        if (this.onWarningResolvedCallback) {
          this.onWarningResolvedCallback(msg as WarningResolvedData);
        }
        break;

      case 'location':
        if (this.onLocationCallback) {
          this.onLocationCallback(msg as LocationData);
        }
        break;

      default:
        console.warn('未处理的消息类型:', (msg as any).type);
    }
  }

  // 更新连接状态
  private setConnectionStatus(connected: boolean): void {
    this.isConnected = connected;
    // 可以在这里更新 UI 状态
  }

  // 断开连接
  public disconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.isReconnecting = true; // 标记为主动断开，不自动重连

    if (this.ws) {
      this.ws.close((err: BusinessError, value: boolean) => {
        if (err) {
          console.error('关闭连接失败:', JSON.stringify(err));
        } else {
          console.info('连接已关闭');
        }
        this.ws = null;
        this.setConnectionStatus(false);
      });
    }
  }

  // 设置回调函数
  public setOnReading(callback: (data: ReadingData) => void): void {
    this.onReadingCallback = callback;
  }

  public setOnWarning(callback: (data: WarningData) => void): void {
    this.onWarningCallback = callback;
  }

  public setOnWarningResolved(callback: (data: WarningResolvedData) => void): void {
    this.onWarningResolvedCallback = callback;
  }

  public setOnLocation(callback: (data: LocationData) => void): void {
    this.onLocationCallback = callback;
  }

  public setOnConnected(callback: () => void): void {
    this.onConnectedCallback = callback;
  }

  public setOnDisconnected(callback: () => void): void {
    this.onDisconnectedCallback = callback;
  }

  public setOnError(callback: (error: string) => void): void {
    this.onErrorCallback = callback;
  }

  // 获取连接状态
  public getConnectionStatus(): boolean {
    return this.isConnected;
  }

  // 设置是否正在加载历史数据
  public setLoadingHistory(loading: boolean): void {
    this.isLoadingHistory = loading;
  }
}
```

---

## 📊 数据解析示例

### 1. 处理传感器读数数据

```typescript
// 设置回调
wsClient.setOnReading((data: ReadingData) => {
  console.info('收到传感器数据:', {
    时间: new Date(data.ts * 1000).toLocaleString(),
    温度: `${data.temp}°C`,
    湿度: `${data.hum}%`,
    亮度: data.lux !== null ? `${data.lux}lx` : '未启用',
    烟雾: data.smoke !== null ? `${data.smoke}ppm` : '未启用',
    大气压: data.pressure !== null ? `${data.pressure}hPa` : '未启用',
    温度2: data.temp2 !== null ? `${data.temp2}°C` : '未启用',
    RsRo: data.rs_ro !== null ? data.rs_ro.toFixed(2) : '未启用'
  });

  // 更新 UI
  updateTemperatureDisplay(data.temp);
  updateHumidityDisplay(data.hum);
  if (data.lux !== null) {
    updateLuxDisplay(data.lux);
  }
  // ... 其他字段
});
```

### 2. 处理警告通知

```typescript
wsClient.setOnWarning((data: WarningData) => {
  console.warn('收到警告:', {
    类型: data.warning_name,
    值: `${data.warning_value}${data.warning_unit}`,
    时间: new Date(data.timestamp * 1000).toLocaleString()
  });

  // 显示警告通知
  showWarningNotification({
    title: `${data.warning_name}异常`,
    message: `当前值: ${data.warning_value}${data.warning_unit}`,
    type: data.warning_type
  });
});
```

### 3. 处理警告恢复通知

```typescript
wsClient.setOnWarningResolved((data: WarningResolvedData) => {
  console.info('警告已恢复:', {
    类型: data.warning_name,
    自动恢复: data.auto_recovered ? '是' : '否',
    时间: new Date(data.timestamp * 1000).toLocaleString()
  });

  // 更新警告状态
  updateWarningStatus(data.warning_type, false);
});
```

### 4. 处理定位数据

```typescript
wsClient.setOnLocation((data: LocationData) => {
  console.info('收到定位数据:', {
    经度: data.lon,
    纬度: data.lat,
    信号强度: data.csq !== null ? data.csq : '未知',
    定位类型: data.location_type || '未知',
    时间: data.utc || new Date(data.timestamp * 1000).toLocaleString()
  });

  // 更新地图显示
  updateMapMarker(data.lon, data.lat);
});
```

---

## ⚠️ 错误处理

### 1. 连接错误

```typescript
wsClient.setOnError((error: string) => {
  console.error('WebSocket 错误:', error);
  // 显示错误提示
  showErrorToast(`连接错误: ${error}`);
});
```

### 2. 消息解析错误

在 `handleWebSocketMessage` 方法中已经包含 try-catch，解析失败时会调用错误回调。

### 3. 数据验证

```typescript
// 验证传感器数据
function validateReadingData(data: ReadingData): boolean {
  if (typeof data.temp !== 'number' || isNaN(data.temp)) {
    console.error('温度数据无效:', data.temp);
    return false;
  }
  if (typeof data.hum !== 'number' || isNaN(data.hum)) {
    console.error('湿度数据无效:', data.hum);
    return false;
  }
  // ... 其他字段验证
  return true;
}

// 使用
wsClient.setOnReading((data: ReadingData) => {
  if (!validateReadingData(data)) {
    console.error('数据验证失败，跳过处理');
    return;
  }
  // 处理数据
});
```

---

## 🎯 完整示例代码

### 使用示例

```typescript
import { SensorWebSocketClient, ReadingData, WarningData } from './SensorWebSocketClient';

// 创建客户端实例
const wsClient = new SensorWebSocketClient();

// 设置服务器地址（根据实际情况修改）
// wsClient.SERVER_HOST = '192.168.1.100:8000';
// wsClient.USE_SSL = false;

// 设置回调函数
wsClient.setOnConnected(() => {
  console.info('✅ WebSocket 已连接');
  // 更新 UI：显示连接状态
});

wsClient.setOnDisconnected(() => {
  console.warn('⚠️ WebSocket 已断开');
  // 更新 UI：显示断开状态
});

wsClient.setOnReading((data: ReadingData) => {
  // 处理传感器数据
  console.info('📊 传感器数据:', data);
  
  // 更新 UI
  // updateUI(data);
});

wsClient.setOnWarning((data: WarningData) => {
  // 处理警告
  console.warn('⚠️ 警告:', data);
  
  // 显示警告通知
  // showWarning(data);
});

wsClient.setOnWarningResolved((data) => {
  // 处理警告恢复
  console.info('✅ 警告已恢复:', data);
  
  // 更新警告状态
  // updateWarningStatus(data);
});

wsClient.setOnLocation((data) => {
  // 处理定位数据
  console.info('📍 定位数据:', data);
  
  // 更新地图
  // updateMap(data);
});

wsClient.setOnError((error: string) => {
  // 处理错误
  console.error('❌ 错误:', error);
  
  // 显示错误提示
  // showError(error);
});

// 连接 WebSocket
wsClient.connect();

// 在组件销毁时断开连接
// wsClient.disconnect();
```

---

## 📝 注意事项

### 1. 时间戳转换

所有时间戳都是 Unix 时间戳（秒，浮点数），需要转换为本地时间：

```typescript
// 转换为 Date 对象
const date = new Date(data.ts * 1000);

// 格式化为本地时间字符串
const timeString = date.toLocaleString('zh-CN', {
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit'
});
```

### 2. 空值处理

部分字段可能为 `null`，需要在使用前检查：

```typescript
if (data.lux !== null && data.lux !== undefined) {
  // 使用 data.lux
} else {
  // 显示"未启用"或隐藏该字段
}
```

### 3. 数据更新频率

- 传感器数据：约每 10 秒更新一次
- 警告/恢复：实时推送（传感器值异常时）
- 定位数据：按需推送（查询定位后）

### 4. 历史数据加载

在加载历史数据期间，建议暂时忽略实时数据，避免数据冲突：

```typescript
// 开始加载历史数据
wsClient.setLoadingHistory(true);
// ... 加载历史数据
// 加载完成后
wsClient.setLoadingHistory(false);
```

### 5. 权限配置

在 `module.json5` 中需要配置网络权限：

```json
{
  "requestPermissions": [
    {
      "name": "ohos.permission.INTERNET"
    }
  ]
}
```

---

## 🔗 相关代码位置

### 后端代码

- **WebSocket 端点**：`server.py` 第 1959-1973 行
- **数据入队函数**：`server.py` 第 203-361 行
- **广播函数**：`server.py` 第 129-140 行
- **警告数据生成**：`server.py` 第 635-644 行
- **定位数据生成**：`server.py` 第 464-475 行

### 前端代码（Web 版参考）

- **WebSocket 连接**：`web/index.html` 第 3764-3812 行
- **消息处理**：`web/index.html` 第 3777-3811 行

---

## 📞 技术支持

如有问题，请参考：
- 后端日志：查看服务器控制台输出
- 前端日志：查看浏览器/鸿蒙应用控制台
- 网络调试：使用 WebSocket 调试工具测试连接

---

**文档版本**：v1.0  
**最后更新**：2025-01-XX  
**适用版本**：后端 v2.11.8+

