# WebSocket 实时数据趋势计算实现说明

本文档详细说明如何从 WebSocket 获取数据并计算实时数据的上升和下降趋势，适用于鸿蒙项目参考。

## 一、整体架构

### 1.1 数据流程
```
WebSocket 连接 → 接收消息 → 解析JSON → 存储到数组 → 计算趋势 → 更新UI
```

### 1.2 核心组件
- **WebSocket 连接管理**：建立连接、处理消息
- **数据存储**：使用数组保存历史数据
- **趋势计算**：基于最近 N 条数据计算变化量
- **UI 更新**：显示趋势箭头和数值

---

## 二、WebSocket 连接与数据接收

### 2.1 建立连接

```javascript
function connect() {
    // 根据协议选择 ws:// 或 wss://
    const url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws';
    wsock = new WebSocket(url);
    
    // 连接成功回调
    wsock.onopen = () => {
        setWsStatus(true);
        updateConnectionStatus();
    };
    
    // 连接关闭回调（自动重连）
    wsock.onclose = () => {
        setWsStatus(false);
        updateConnectionStatus();
        setTimeout(connect, 1500); // 1.5秒后重连
    };
    
    // 接收消息回调
    wsock.onmessage = e => {
        try {
            const msg = JSON.parse(e.data);
            
            // 过滤非数据消息
            if (msg.type === 'warning' || msg.type === 'location') {
                // 处理其他类型消息...
                return;
            }
            
            // 处理实时数据
            if (msg.type === 'reading') {
                addRow(msg.ts, msg.temp, msg.hum, msg.lux, msg.smoke, msg.pressure, msg.temp2, msg.rs_ro);
            }
        } catch (error) {
            console.error('解析消息失败:', error);
        }
    };
}
```

### 2.2 消息格式

WebSocket 接收到的数据格式示例：
```json
{
    "type": "reading",
    "ts": 1704067200,        // Unix 时间戳（秒）
    "temp": 25.5,            // 温度（°C）
    "hum": 60.2,             // 湿度（%）
    "lux": 500.0,            // 亮度（lx）
    "smoke": 10.5,           // 烟雾浓度（ppm）
    "pressure": 1013.2,      // 大气压（hPa）
    "temp2": 25.3,           // 第二温度传感器（可选）
    "rs_ro": 0.85            // 传感器原始值（可选）
}
```

---

## 三、数据存储

### 3.1 数据数组定义

```javascript
// 趋势计算使用的数据点数量
const N_TREND = 20;  // 使用最近 20 条数据计算趋势

// 存储所有历史数据的数组
const tempsAll = [];      // 温度数组
const humsAll = [];       // 湿度数组
const luxAll = [];        // 亮度数组
const smokeAll = [];      // 烟雾数组
const pressureAll = [];   // 气压数组
const tempDiffAll = [];   // 温差数组
```

### 3.2 数据添加函数

```javascript
function addRow(ts, t, h, lx, sm, pr, t2, rs_ro) {
    // 1. 时间戳检查（防止添加旧数据）
    if (lastDataTimestamp > 0 && ts <= lastDataTimestamp) {
        console.warn('跳过旧数据');
        return;
    }
    
    // 2. 更新当前值显示
    tempVal.textContent = t.toFixed(2);
    humVal.textContent = h.toFixed(2);
    // ... 其他数值显示
    
    // 3. 将数据添加到数组末尾
    tempsAll.push(t);
    humsAll.push(h);
    luxAll.push(lx == null ? NaN : lx);
    smokeAll.push(sm == null ? NaN : sm);
    pressureAll.push(pr == null ? NaN : pr);
    
    // 4. 计算温差（如果有第二温度传感器）
    let diff = 0;
    if (t2 != null) {
        diff = Math.abs(t - t2);
        tempDiffAll.push(diff);
    } else {
        tempDiffAll.push(NaN);
    }
    
    // 5. 限制数组长度（防止内存溢出）
    if (tempsAll.length > MAX_CHART_HISTORY) {
        tempsAll.shift();  // 移除最旧的数据
        humsAll.shift();
        // ... 其他数组
    }
    
    // 6. 计算并更新趋势（关键步骤）
    updateTrends();
}
```

---

## 四、趋势计算核心算法

### 4.1 差值计算函数

```javascript
/**
 * 计算数组首尾差值（用于趋势判断）
 * @param {Array} arr - 数据数组
 * @returns {number} 差值（正数表示上升，负数表示下降）
 */
function delta(arr) {
    if (arr.length < 2) return 0;
    // 返回：最后一个值 - 第一个值
    return arr[arr.length - 1] - arr[0];
}
```

**算法说明**：
- 取数组的第一个值和最后一个值
- 计算差值：`最新值 - 最早值`
- 正数 = 上升趋势，负数 = 下降趋势，接近 0 = 稳定

### 4.2 趋势更新函数

```javascript
/**
 * 更新趋势显示
 * @param {HTMLElement} ele - 趋势显示元素
 * @param {number} d - 差值（delta 函数的返回值）
 * @param {string} unit - 单位（如 '°C', '%', 'lx'）
 */
function setTrend(ele, d, unit) {
    // 移除之前的趋势样式
    ele.classList.remove('up', 'down');
    
    // 获取或创建箭头和文本元素
    const arrow = ele.querySelector('.arrow') || 
                  ele.appendChild(document.createElement('span'));
    arrow.className = 'arrow';
    
    const txt = ele.querySelector('.txt') || 
                ele.appendChild(document.createElement('span'));
    txt.className = 'txt';
    
    // 判断趋势方向
    if (Math.abs(d) < 0.01) {
        // 变化量小于 0.01，视为稳定
        arrow.textContent = '—';
        txt.textContent = '趋势稳定';
    } else if (d > 0) {
        // 正数：上升趋势
        ele.classList.add('up');
        arrow.textContent = '↑';
        txt.textContent = `上升 ${d.toFixed(2)} ${unit}`;
    } else {
        // 负数：下降趋势
        ele.classList.add('down');
        arrow.textContent = '↓';
        txt.textContent = `下降 ${Math.abs(d).toFixed(2)} ${unit}`;
    }
}
```

### 4.3 批量趋势计算

```javascript
function updateTrends() {
    // 1. 获取最近 N_TREND 条数据（从数组末尾截取）
    const tS = tempsAll.slice(-N_TREND);           // 温度：最近 20 条
    const hS = humsAll.slice(-N_TREND);            // 湿度：最近 20 条
    const lS = luxAll.slice(-N_TREND).filter(x => !Number.isNaN(x));      // 亮度：过滤 NaN
    const sS = smokeAll.slice(-N_TREND).filter(x => !Number.isNaN(x));     // 烟雾：过滤 NaN
    const pS = pressureAll.slice(-N_TREND).filter(x => !Number.isNaN(x));  // 气压：过滤 NaN
    const dS = tempDiffAll.slice(-N_TREND).filter(x => !Number.isNaN(x)); // 温差：过滤 NaN
    
    // 2. 计算每个数据集的趋势
    setTrend(tempTrend, delta(tS), '°C');
    setTrend(humTrend, delta(hS), '%');
    
    // 3. 只有数据量 >= 2 时才计算趋势
    if (dS.length >= 2) setTrend(tempDiffTrend, delta(dS), '°C');
    if (lS.length >= 2) setTrend(luxTrend, delta(lS), 'lx');
    if (sS.length >= 2) setTrend(smokeTrend, delta(sS), 'ppm');
    if (pS.length >= 2) setTrend(pressureTrend, delta(pS), 'hPa');
}
```

---

## 五、完整示例代码

### 5.1 简化版实现（可直接移植）

```javascript
// ========== 配置 ==========
const N_TREND = 20;  // 使用最近 20 条数据计算趋势
const dataArrays = {
    temp: [],
    hum: [],
    lux: []
};

// ========== WebSocket 连接 ==========
let ws = null;

function connectWebSocket() {
    const url = 'ws://your-server:port/ws';
    ws = new WebSocket(url);
    
    ws.onopen = () => {
        console.log('WebSocket 连接成功');
    };
    
    ws.onclose = () => {
        console.log('WebSocket 连接关闭，尝试重连...');
        setTimeout(connectWebSocket, 1500);
    };
    
    ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'reading') {
                handleData(msg);
            }
        } catch (error) {
            console.error('解析消息失败:', error);
        }
    };
    
    ws.onerror = (error) => {
        console.error('WebSocket 错误:', error);
    };
}

// ========== 数据处理 ==========
function handleData(msg) {
    // 1. 存储数据
    dataArrays.temp.push(msg.temp);
    dataArrays.hum.push(msg.hum);
    dataArrays.lux.push(msg.lux || NaN);
    
    // 2. 限制数组长度
    if (dataArrays.temp.length > 1000) {
        dataArrays.temp.shift();
        dataArrays.hum.shift();
        dataArrays.lux.shift();
    }
    
    // 3. 计算趋势
    updateTrends();
}

// ========== 趋势计算 ==========
function delta(arr) {
    if (arr.length < 2) return 0;
    return arr[arr.length - 1] - arr[0];
}

function calculateTrend(dataArray) {
    // 获取最近 N_TREND 条数据
    const recentData = dataArray.slice(-N_TREND).filter(x => !Number.isNaN(x));
    
    if (recentData.length < 2) {
        return { direction: 'stable', value: 0, text: '数据不足' };
    }
    
    const diff = delta(recentData);
    
    if (Math.abs(diff) < 0.01) {
        return { direction: 'stable', value: 0, text: '趋势稳定' };
    } else if (diff > 0) {
        return { 
            direction: 'up', 
            value: diff, 
            text: `上升 ${diff.toFixed(2)}` 
        };
    } else {
        return { 
            direction: 'down', 
            value: Math.abs(diff), 
            text: `下降 ${Math.abs(diff).toFixed(2)}` 
        };
    }
}

function updateTrends() {
    const tempTrend = calculateTrend(dataArrays.temp);
    const humTrend = calculateTrend(dataArrays.hum);
    const luxTrend = calculateTrend(dataArrays.lux);
    
    // 更新 UI（根据你的框架实现）
    console.log('温度趋势:', tempTrend);
    console.log('湿度趋势:', humTrend);
    console.log('亮度趋势:', luxTrend);
}

// ========== 启动 ==========
connectWebSocket();
```

---

## 六、鸿蒙项目移植要点

### 6.1 WebSocket 连接（HarmonyOS）

```typescript
import webSocket from '@ohos.net.webSocket';

// 建立连接
let ws = webSocket.createWebSocket();
ws.connect('ws://your-server:port/ws');

// 接收消息
ws.on('message', (err, value) => {
    if (err) {
        console.error('接收消息失败:', err);
        return;
    }
    
    // value 是 ArrayBuffer，需要转换为字符串
    const message = String.fromCharCode.apply(null, new Uint8Array(value));
    const data = JSON.parse(message);
    
    if (data.type === 'reading') {
        handleData(data);
    }
});

// 连接关闭
ws.on('close', () => {
    console.log('WebSocket 连接关闭');
    // 实现重连逻辑
});
```

### 6.2 数据存储（HarmonyOS）

```typescript
// 使用数组存储数据
class DataManager {
    private tempArray: number[] = [];
    private humArray: number[] = [];
    private readonly N_TREND = 20;
    private readonly MAX_SIZE = 1000;
    
    addData(temp: number, hum: number) {
        this.tempArray.push(temp);
        this.humArray.push(hum);
        
        // 限制数组长度
        if (this.tempArray.length > this.MAX_SIZE) {
            this.tempArray.shift();
            this.humArray.shift();
        }
    }
    
    calculateTrend(dataArray: number[]): TrendResult {
        const recent = dataArray.slice(-this.N_TREND);
        if (recent.length < 2) {
            return { direction: 'stable', value: 0 };
        }
        
        const diff = recent[recent.length - 1] - recent[0];
        
        if (Math.abs(diff) < 0.01) {
            return { direction: 'stable', value: 0 };
        } else if (diff > 0) {
            return { direction: 'up', value: diff };
        } else {
            return { direction: 'down', value: Math.abs(diff) };
        }
    }
}
```

### 6.3 UI 更新（HarmonyOS）

```typescript
@State tempTrend: TrendResult = { direction: 'stable', value: 0 };

build() {
    Row() {
        // 趋势箭头
        if (this.tempTrend.direction === 'up') {
            Text('↑').fontColor(Color.Red);
        } else if (this.tempTrend.direction === 'down') {
            Text('↓').fontColor(Color.Green);
        } else {
            Text('—').fontColor(Color.Gray);
        }
        
        // 趋势文本
        Text(this.tempTrend.value > 0 
            ? `上升 ${this.tempTrend.value.toFixed(2)}°C`
            : this.tempTrend.value < 0
            ? `下降 ${Math.abs(this.tempTrend.value).toFixed(2)}°C`
            : '趋势稳定'
        )
    }
}
```

---

## 七、关键参数说明

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `N_TREND` | 用于计算趋势的数据点数量 | 20（可根据数据频率调整） |
| `MAX_SIZE` | 数组最大长度 | 1000-5000（根据内存情况） |
| `稳定阈值` | 判断为"稳定"的最小变化量 | 0.01（根据数据类型调整） |

### 参数调整建议

- **数据频率高**（如每秒 1 条）：`N_TREND = 20` 表示最近 20 秒的趋势
- **数据频率低**（如每 10 秒 1 条）：`N_TREND = 6` 表示最近 1 分钟的趋势
- **需要更敏感的趋势**：减小 `N_TREND`（如 10）
- **需要更平滑的趋势**：增大 `N_TREND`（如 30）

---

## 八、注意事项

1. **时间戳检查**：防止添加旧数据导致趋势计算错误
2. **NaN 处理**：某些传感器可能返回空值，需要过滤
3. **数组长度限制**：防止内存溢出
4. **重连机制**：WebSocket 断开后自动重连
5. **数据同步**：确保数据按时间顺序添加

---

## 九、扩展优化

### 9.1 加权平均趋势（更平滑）

```javascript
function weightedDelta(arr) {
    if (arr.length < 2) return 0;
    
    // 给最近的数据更高权重
    let weightedSum = 0;
    let totalWeight = 0;
    
    for (let i = 0; i < arr.length; i++) {
        const weight = i + 1; // 越新权重越大
        weightedSum += arr[i] * weight;
        totalWeight += weight;
    }
    
    const avg = weightedSum / totalWeight;
    const latest = arr[arr.length - 1];
    
    return latest - avg;
}
```

### 9.2 线性回归趋势（更准确）

```javascript
function linearRegressionTrend(arr) {
    if (arr.length < 2) return 0;
    
    const n = arr.length;
    let sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    
    for (let i = 0; i < n; i++) {
        sumX += i;
        sumY += arr[i];
        sumXY += i * arr[i];
        sumXX += i * i;
    }
    
    const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    
    return slope * n; // 返回整个时间段的趋势
}
```

---

## 十、总结

核心思路：
1. **建立 WebSocket 连接**，接收实时数据
2. **将数据存储到数组**，维护历史记录
3. **取最近 N 条数据**，计算首尾差值
4. **根据差值判断趋势**：正数=上升，负数=下降，接近0=稳定
5. **更新 UI 显示**趋势箭头和数值

这个方案简单高效，适合实时监测场景。在鸿蒙项目中，只需要将 JavaScript 语法转换为 TypeScript，并使用 HarmonyOS 的 WebSocket API 即可。

