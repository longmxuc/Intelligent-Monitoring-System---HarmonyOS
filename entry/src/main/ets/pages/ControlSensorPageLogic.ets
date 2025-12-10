import { http } from '@kit.NetworkKit';
import { SERVER_HOST } from './DevicesPageLogic';

// 传感器状态接口
export interface SensorState {
  success: boolean;
  state?: string; // "on" | "off"
  mode?: string; // "eco" | "balance" | "safe" | "always"
  mode_name?: string;
  mode_icon?: string;
  mode_on_sec?: number;
  mode_off_sec?: number;
  phase?: string;
  phase_message?: string;
  phase_until?: number;
  next_switch_in_sec?: number;
  last_value?: number;
  updated_at?: string | number; // 支持字符串或时间戳（秒级/毫秒级）
  last_via?: string;
  device_id?: string;
  error?: string;
}

// 开关响应接口
export interface SwitchResponse {
  success: boolean;
  action?: string;
  command?: string;
  via?: string;
  topic?: string;
  state?: string;
  updated_at?: string | number; // 支持字符串或时间戳（秒级/毫秒级）
  last_via?: string;
  device_id?: string;
  error?: string;
}

// 模式响应接口
export interface ModeResponse {
  success: boolean;
  mode?: string;
  mode_name?: string;
  mode_icon?: string;
  mode_on_sec?: number;
  mode_off_sec?: number;
  device_id?: string;
  error?: string;
}

// 传感器类型映射
const SENSOR_API_MAP: Record<string, string> = {
  'MQ2 烟雾传感器': 'mq2',
  'BMP180 气压传感器': 'bmp180',
  'BH1750 亮度传感器': 'bh1750',
  'BLE 蓝牙模块': 'ble',
  'OLED 显示屏': 'oled'
};

// 获取传感器 API 前缀
function getSensorApiPrefix(sensorName: string): string {
  return SENSOR_API_MAP[sensorName] || 'mq2';
}

/**
 * 获取传感器状态
 */
export async function getSensorState(sensorName: string, deviceId: string): Promise<SensorState> {
  const apiPrefix = getSensorApiPrefix(sensorName);
  const url = `http://${SERVER_HOST}/api/${apiPrefix}/state?device_id=${deviceId}`;
  
  try {
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    
    httpRequest.destroy();
    
    if (response.responseCode === 200) {
      const result = JSON.parse(response.result as string) as SensorState;
      console.info(`[传感器状态] 获取成功: ${sensorName}, device: ${deviceId}, state: ${result.state}`);
      return result;
    } else {
      console.error(`[传感器状态] HTTP错误: ${response.responseCode}`);
      return {
        success: false,
        error: `HTTP ${response.responseCode}`
      };
    }
  } catch (err) {
    console.error(`[传感器状态] 获取失败: ${JSON.stringify(err)}`);
    return {
      success: false,
      error: err.message || '网络请求失败'
    };
  }
}

/**
 * 切换传感器开关
 */
export async function switchSensor(
  sensorName: string,
  deviceId: string,
  action: 'on' | 'off'
): Promise<SwitchResponse> {
  const apiPrefix = getSensorApiPrefix(sensorName);
  const url = `http://${SERVER_HOST}/api/${apiPrefix}/switch`;
  
  try {
    console.info(`[传感器开关] 请求: ${url}, action: ${action}, device_id: ${deviceId}`);
    
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        action: action,
        device_id: deviceId
      }),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    
    httpRequest.destroy();
    
    if (response.responseCode === 200) {
      const result = JSON.parse(response.result as string) as SwitchResponse;
      console.info(`[传感器开关] 成功: ${sensorName}, action: ${action}, via: ${result.via}`);
      return result;
    } else {
      console.error(`[传感器开关] HTTP错误: ${response.responseCode}`);
      return {
        success: false,
        error: `HTTP ${response.responseCode}`
      };
    }
  } catch (err) {
    console.error(`[传感器开关] 切换失败: ${JSON.stringify(err)}`);
    return {
      success: false,
      error: err.message || '网络请求失败'
    };
  }
}

/**
 * 设置传感器模式
 */
export async function setSensorMode(
  sensorName: string,
  deviceId: string,
  mode: string
): Promise<ModeResponse> {
  const apiPrefix = getSensorApiPrefix(sensorName);
  const url = `http://${SERVER_HOST}/api/${apiPrefix}/mode`;
  
  try {
    console.info(`[传感器模式] 请求: ${url}, mode: ${mode}, device_id: ${deviceId}`);
    
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        mode: mode,
        device_id: deviceId
      }),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    
    httpRequest.destroy();
    
    if (response.responseCode === 200) {
      const result = JSON.parse(response.result as string) as ModeResponse;
      console.info(`[传感器模式] 成功: ${sensorName}, mode: ${mode}, mode_name: ${result.mode_name}`);
      return result;
    } else {
      console.error(`[传感器模式] HTTP错误: ${response.responseCode}`);
      return {
        success: false,
        error: `HTTP ${response.responseCode}`
      };
    }
  } catch (err) {
    console.error(`[传感器模式] 设置失败: ${JSON.stringify(err)}`);
    return {
      success: false,
      error: err.message || '网络请求失败'
    };
  }
}

/**
 * 模式 ID 到 API 模式的映射
 */
export const MODE_ID_MAP: Record<string, string> = {
  'save': 'eco',
  'balance': 'balance',
  'safe': 'safe',
  'non_eco': 'always'
};

/**
 * API 模式到模式 ID 的映射
 */
export const API_MODE_MAP: Record<string, string> = {
  'eco': 'save',
  'balance': 'balance',
  'safe': 'safe',
  'always': 'non_eco'
};

