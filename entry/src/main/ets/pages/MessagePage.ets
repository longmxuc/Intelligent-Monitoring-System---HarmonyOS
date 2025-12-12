import { http } from '@kit.NetworkKit';
import { SERVER_HOST } from './WebSocketManager';
import promptAction from '@ohos.promptAction';
import { WebSocketManager, WarningNotificationMessage, WebSocketMessageCallback } from './WebSocketManager';

// API 返回的警告数据接口
interface ApiWarningData {
  id: number;
  warning_type: string;
  warning_message: string;
  warning_value: number | null;
  is_resolved: boolean;
  warning_start_time: number; // Unix时间戳（秒）
  warning_resolved_time: number | null; // Unix时间戳（秒）
  created_at: string;
  device_id: string;
}

// API 返回的日期数据接口
interface ApiDateData {
  date: string;
  count: number;
}

// API 响应接口
interface ApiResponse {
  success: boolean;
  data: ApiWarningData[];
  count: number;
  error?: string;
}

interface ApiDateResponse {
  success: boolean;
  data: ApiDateData[];
  count: number;
  error?: string;
}

// 前端显示的消息项接口
interface MessageItem {
  id: number;
  title: string;
  device: string;
  value: string;
  time: string;
  date: string;
  status: '已恢复' | '未恢复';
}

// 日期时间解析结果接口
interface DateTimeResult {
  time: string;
  date: string;
}

@Entry
@Component
export struct MessagePage {
  // --- 状态管理 ---
  @State filterDevice: string = '全部设备';
  @State filterDate: string = '近7天';
  @State filterType: string = '全部类型';
  @State filterStatus: string = '全部状态';
  @State messages: MessageItem[] = [];
  @State loading: boolean = false;
  @State dateOptions: string[] = ['近7天', '今天', '昨天', '本月'];
  
  // WebSocket管理器实例
  private wsManager: WebSocketManager = WebSocketManager.getInstance();
  private wsCallback: WebSocketMessageCallback | null = null;
  // 映射表：类型代码 -> 中文名称
  private typeMap: Record<string, string> = {
    'T': '温度异常',
    'H': '湿度异常',
    'B': '亮度异常',
    'S': 'PPM异常',
    'P': '大气压异常'
  };
  // 映射表：类型代码 -> 单位
  private unitMap: Record<string, string> = {
    'T': '°C',
    'H': '%',
    'B': 'Lux',
    'S': 'ppm',
    'P': 'kPa'
  };
  // 设备名称映射
  private deviceNameMap: Record<string, string> = {
    'D01': '实验平台',
    'D02': '算力机房',
    'D03': '液冷中心',
    'D04': '访客中心'
  };
  // 设备筛选映射：显示名称 -> 设备ID
  private deviceFilterMap: Record<string, string | null> = {
    '全部设备': null,
    '实验平台': 'D01',
    '算力机房': 'D02',
    '液冷中心': 'D03',
    '访客中心': 'D04'
  };
  // 类型筛选映射：显示名称 -> 类型代码
  private typeFilterMap: Record<string, string | null> = {
    '全部类型': null,
    '温度异常': 'T',
    '湿度异常': 'H',
    '亮度异常': 'B',
    'PPM异常': 'S',
    '大气压异常': 'P'
  };
  // 主题色
  private readonly blueColor: string = "#2A4DD0";
  private readonly grayColor: string = "#666666";

  // 页面初始化
  aboutToAppear(): void {
    this.loadDateOptions();
    this.loadWarnings();
    this.setupWebSocket();
  }

  // 页面销毁
  aboutToDisappear(): void {
    this.cleanupWebSocket();
  }

  // 设置WebSocket订阅（复用DevicesPage的连接，不创建新连接）
  private setupWebSocket(): void {
    // 创建回调对象
    this.wsCallback = {
      onWarning: (message: WarningNotificationMessage) => {
        this.handleWarningNotification(message);
      },
      onWarningResolved: (deviceId: string) => {
        console.info(`[消息页] 设备 ${deviceId} 的警告已恢复`);
        // 警告恢复时，可以刷新列表或更新对应消息的状态
        this.loadWarnings();
      },
      onConnected: (connected: boolean) => {
        console.info(`[消息页] WebSocket连接状态: ${connected ? '已连接' : '已断开'}`);
      }
    };

    // 订阅WebSocket消息（复用DevicesPage的WebSocket连接）
    this.wsManager.subscribe(this.wsCallback);
  }

  // 清理WebSocket订阅
  private cleanupWebSocket(): void {
    if (this.wsCallback) {
      this.wsManager.unsubscribe(this.wsCallback);
      this.wsCallback = null;
    }
  }

  // 处理WebSocket推送的警告通知
  private handleWarningNotification(message: WarningNotificationMessage): void {
    console.info(`[消息页] 收到实时警告通知:`, JSON.stringify(message));
    
    // 解析后端推送的警告通知数据
    // 数据格式：{
    //   "type": "warning",
    //   "warning_type": "B",
    //   "warning_name": "亮度异常",
    //   "warning_value": 4.17,
    //   "warning_unit": "Lux",
    //   "warning_message": "DB4.17",
    //   "device_id": "D01",
    //   "timestamp": 1765520625
    // }
    
    // 将警告通知转换为MessageItem格式
    const warningType = message.warning_type || 'B';
    const title = this.typeMap[warningType] || (message.warning_name || '未知异常');
    const unit = this.unitMap[warningType] || (message.warning_unit || '');
    const warningValue = message.warning_value;
    const value = warningValue !== null && warningValue !== undefined 
      ? `${warningValue} ${unit}` : '未知';
    
    const deviceId = message.device_id || 'D01';
    const deviceName = this.deviceNameMap[deviceId];
    const device = deviceName || `设备 ${deviceId}`;
    
    // 解析时间戳（后端推送的是Unix时间戳，秒级）
    const timestamp = message.timestamp || Date.now() / 1000;
    const dateTimeResult: DateTimeResult = this.parseDateTimeFromTimestamp(timestamp);
    
    // 创建新的消息项
    const newMessage: MessageItem = {
      id: Math.floor(timestamp * 1000), // 使用时间戳作为ID，确保唯一性
      title: title,
      device: device,
      value: value,
      time: dateTimeResult.time,
      date: dateTimeResult.date,
      status: '未恢复'
    };
    
    // 检查是否已存在相同的消息（避免重复添加）
    const existingIndex = this.messages.findIndex(msg => 
      msg.id === newMessage.id || 
      (msg.device === newMessage.device && 
       msg.title === newMessage.title && 
       msg.time === newMessage.time)
    );
    
    if (existingIndex === -1) {
      // 将新消息添加到列表顶部
      this.messages = [newMessage, ...this.messages];
      
      // 显示Toast通知
      promptAction.showToast({
        message: `${device} - ${title}: ${value}`,
        duration: 3000
      });
    } else {
      // 如果消息已存在，更新它
      const updatedMessages = [...this.messages];
      updatedMessages[existingIndex] = newMessage;
      this.messages = updatedMessages;
    }
  }

  // 加载日期选项（从API获取有数据的日期）
  async loadDateOptions(): Promise<void> {
    try {
      const httpRequest = http.createHttp();
      const deviceId = this.getDeviceIdFromFilter();
      const url = `http://${SERVER_HOST}/api/warnings/dates${deviceId ? `?device_id=${deviceId}` : ''}`;

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const result: ApiDateResponse = JSON.parse(response.result as string) as ApiDateResponse;
        if (result.success && result.data) {
          // 构建日期选项：近7天、今天、昨天、本月 + 有数据的日期
          const options: string[] = ['近7天', '今天', '昨天', '本月'];
          const today = new Date();
          const todayStr = this.formatDate(today);
          const yesterday = new Date(today);
          yesterday.setDate(yesterday.getDate() - 1);
          const yesterdayStr = this.formatDate(yesterday);

          // 添加有数据的日期（排除今天和昨天）
          for (const dateItem of result.data) {
            if (dateItem.date !== todayStr && dateItem.date !== yesterdayStr) {
              options.push(dateItem.date);
            }
          }

          this.dateOptions = options;

          // 如果当前选择的日期不在新选项中，重置为"近7天"
          if (!options.includes(this.filterDate)) {
            this.filterDate = '近7天';
          }
        }
      }
    } catch (err) {
      console.error(`[消息页] 加载日期列表失败: ${JSON.stringify(err)}`);
    }
  }

  // 加载警告数据
  async loadWarnings(): Promise<void> {
    this.loading = true;
    try {
      const httpRequest = http.createHttp();

      // 构建查询参数
      const params: string[] = [];
      params.push(`limit=100`);

      // 设备筛选
      const deviceId = this.getDeviceIdFromFilter();
      if (deviceId) {
        params.push(`device_id=${deviceId}`);
      }

      // 类型筛选
      const warningType = this.getWarningTypeFromFilter();
      if (warningType) {
        params.push(`warning_type=${warningType}`);
      }

      // 状态筛选
      const isResolved = this.getIsResolvedFromFilter();
      if (isResolved !== null) {
        params.push(`is_resolved=${isResolved}`);
      }

      // 日期筛选
      const date = this.getDateFromFilter();
      if (date) {
        params.push(`date=${date}`);
      }

      const url = `http://${SERVER_HOST}/api/warnings?${params.join('&')}`;

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const result: ApiResponse = JSON.parse(response.result as string) as ApiResponse;
        if (result.success && result.data) {
          // 转换为前端显示格式
          this.messages = this.convertApiDataToMessages(result.data);
          console.info(`[消息页] 加载成功，共 ${this.messages.length} 条消息`);
        } else {
          console.error(`[消息页] API返回失败: ${result.error || '未知错误'}`);
          this.messages = [];
          promptAction.showToast({
            message: `加载失败: ${result.error || '未知错误'}`,
            duration: 2000
          });
        }
      } else {
        console.error(`[消息页] HTTP请求失败: ${response.responseCode}`);
        this.messages = [];
        promptAction.showToast({
          message: '加载失败，请检查网络连接',
          duration: 2000
        });
      }
    } catch (err) {
      console.error(`[消息页] 加载警告数据失败: ${JSON.stringify(err)}`);
      this.messages = [];
      promptAction.showToast({
        message: '加载失败，请检查网络连接',
        duration: 2000
      });
    } finally {
      this.loading = false;
    }
  }

  // 将API数据转换为前端显示格式
  private convertApiDataToMessages(apiData: ApiWarningData[]): MessageItem[] {
    return apiData.map((item) => {
      const warningType = item.warning_type || 'B';
      const title = this.typeMap[warningType] || '未知异常';
      const unit = this.unitMap[warningType] || '';
      const value = item.warning_value !== null ? `${item.warning_value} ${unit}` : '未知';
      const deviceName = this.deviceNameMap[item.device_id];
      const device = deviceName ? `${deviceName}（${item.device_id}）` : `设备 ${item.device_id}`;

      // 解析时间：优先使用 warning_start_time（Unix时间戳），否则使用 created_at（字符串）
      let dateTimeResult: DateTimeResult;
      if (item.warning_start_time && item.warning_start_time > 0) {
        // 使用Unix时间戳（秒级）
        dateTimeResult = this.parseDateTimeFromTimestamp(item.warning_start_time);
      } else {
        // 使用字符串格式
        dateTimeResult = this.parseDateTimeFromString(item.created_at);
      }
      const time = dateTimeResult.time;
      const date = dateTimeResult.date;

      const messageItem: MessageItem = {
        id: item.id,
        title: title,
        device: device,
        value: value,
        time: time,
        date: date,
        status: item.is_resolved ? '已恢复' : '未恢复'
      };
      return messageItem;
    });
  }

  // 从Unix时间戳（秒）解析日期时间
  private parseDateTimeFromTimestamp(timestamp: number): DateTimeResult {
    try {
      // Unix时间戳是秒级，需要乘以1000转换为毫秒
      const date = new Date(timestamp * 1000);
      return this.formatDateTime(date);
    } catch (err) {
      console.error(`[消息页] 解析时间戳失败: ${timestamp}`, err);
      const errorResult: DateTimeResult = {
        time: '00:00',
        date: '未知'
      };
      return errorResult;
    }
  }

  // 从字符串解析日期时间
  private parseDateTimeFromString(dateTimeStr: string): DateTimeResult {
    try {
      const date = new Date(dateTimeStr);
      return this.formatDateTime(date);
    } catch (err) {
      console.error(`[消息页] 解析日期时间字符串失败: ${dateTimeStr}`, err);
      const errorResult: DateTimeResult = {
        time: '00:00',
        date: '未知'
      };
      return errorResult;
    }
  }

  // 格式化日期时间为显示文本
  private formatDateTime(date: Date): DateTimeResult {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const messageDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

    // 格式化时间 HH:mm
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const time = `${hours}:${minutes}`;

    // 判断日期显示
    let dateText: string;
    if (messageDate.getTime() === today.getTime()) {
      dateText = '今天';
    } else if (messageDate.getTime() === yesterday.getTime()) {
      dateText = '昨天';
    } else {
      // 其他日期显示为 YYYY-MM-DD
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      dateText = `${date.getFullYear()}-${month}-${day}`;
    }

    const result: DateTimeResult = {
      time: time,
      date: dateText
    };
    return result;
  }

  // 格式化日期为 YYYY-MM-DD
  private formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  // 从设备筛选获取设备ID
  private getDeviceIdFromFilter(): string | null {
    return this.deviceFilterMap[this.filterDevice] || null;
  }

  // 从类型筛选获取警告类型代码
  private getWarningTypeFromFilter(): string | null {
    return this.typeFilterMap[this.filterType] || null;
  }

  // 从状态筛选获取is_resolved值
  private getIsResolvedFromFilter(): number | null {
    if (this.filterStatus === '全部状态') {
      return null;
    } else if (this.filterStatus === '已恢复') {
      return 1;
    } else {
      return 0;
    }
  }

  // 从日期筛选获取日期字符串
  private getDateFromFilter(): string | null {
    if (this.filterDate === '近7天' || this.filterDate === '本月') {
      return null; // 近7天和本月由后端处理，不传date参数
    } else if (this.filterDate === '今天') {
      return this.formatDate(new Date());
    } else if (this.filterDate === '昨天') {
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      return this.formatDate(yesterday);
    } else {
      // 直接是日期字符串 YYYY-MM-DD
      return this.filterDate;
    }
  }

  // 辅助函数：将字符串数组转为 Select 组件需要的 SelectOption 数组
  private getOptions(options: string[]): SelectOption[] {
    return options.map((item) => ({ value: item } as SelectOption));
  }

  // 辅助函数：判断是否高亮（非默认值时高亮）
  private getFontColor(currentValue: string, defaultValue: string): string {
    return (currentValue !== defaultValue && currentValue !== '近7天') ? this.blueColor : this.grayColor;
  }

  build() {
    Column() {
      // 1. 顶部提示栏
      Row() {
        Text("在此处查看系统的全部异常消息")
          .fontSize(12)
          .fontColor($r("app.color.home_status_text"))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 12, bottom: 12, left: 16 })
      .backgroundColor($r("app.color.home_card_background"))

      // 2. 原生筛选栏 (使用 Select 组件)
      Row() {
        // 设备筛选
        this.NativeSelect(
          this.filterDevice,
          ['全部设备', '实验平台', '算力机房', '液冷中心', '访客中心'],
          (val: string) => {
            this.filterDevice = val;
            // 设备改变时，重新加载日期选项和警告数据
            this.loadDateOptions();
            this.loadWarnings();
          }
        )

        // 日期筛选
        this.NativeSelect(
          this.filterDate,
          this.dateOptions,
          (val: string) => {
            this.filterDate = val;
            this.loadWarnings();
          }
        )

        // 类型筛选
        this.NativeSelect(
          this.filterType,
          ['全部类型', '温度异常', '湿度异常', '亮度异常', 'PPM异常', '大气压异常'],
          (val: string) => {
            this.filterType = val;
            this.loadWarnings();
          }
        )

        // 状态筛选
        this.NativeSelect(
          this.filterStatus,
          ['全部状态', '未恢复', '已恢复'],
          (val: string) => {
            this.filterStatus = val;
            this.loadWarnings();
          }
        )
      }
      .width('100%')
      .height(44)
      .backgroundColor($r("app.color.home_card_background"))
      .shadow({ radius: 10, color: $r("app.color.card_shadow"), offsetY: 2 })
      .zIndex(10)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 8, right: 8 })

      // 3. 消息列表
      if (this.loading) {
        // 加载中提示
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.blueColor)
          Text("加载中...")
            .fontSize(12)
            .fontColor($r("app.color.home_status_text"))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.messages.length === 0) {
        // 空列表提示
        Column() {
          Text("暂无消息")
            .fontSize(14)
            .fontColor($r("app.color.home_subtitle_text"))
            .margin({ top: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ListItem().height(8) // 顶部留白

          ForEach(this.messages, (msg: MessageItem) => {
            ListItem() {
              this.MessageCard(msg)
            }
          }, (msg: MessageItem) => msg.id.toString())

          ListItem() {
            Text("已显示全部历史消息")
              .fontSize(10)
              .fontColor($r("app.color.home_subtitle_text"))
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 10, bottom: 30 })
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1) // 占满剩余空间
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r("app.color.home_background"))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.home_background"))
  }

  // --- 封装的原生 Select 组件构建器 ---
  @Builder
  NativeSelect(currentValue: string, options: string[], onSelect: (val: string) => void) {
    Select(this.getOptions(options))
      .selected(0)
      .value(currentValue)
      .font({
        size: 12,
        weight: FontWeight.Medium
      })
      .fontColor(this.getFontColor(currentValue, options[0]))
      .selectedOptionFont({ size: 14, weight: FontWeight.Medium })
      .selectedOptionFontColor(this.blueColor)
      .optionFont({ size: 14, weight: FontWeight.Normal })
      .optionFontColor($r("app.color.home_value_text"))
      .backgroundColor(Color.Transparent)
      .onSelect((_index: number, value: string) => {
        onSelect(value);
      })
      .height('100%')
      .padding(0)
  }

  // --- 消息卡片组件 ---
  @Builder
  MessageCard(msg: MessageItem) {
    Column() {
      // Header
      Row() {
        Row({ space: 8 }) {
          // 状态圆点
          Circle({ width: 8, height: 8 })
            .fill(msg.status === '未恢复' ? "#EF4444" : "#22C55E")

          Text(msg.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r("app.color.home_value_text"))

          // 状态标签
          Text(msg.status)
            .fontSize(10)
            .fontColor(msg.status === '未恢复' ? "#DC2626" : "#16A34A")
            .padding({
              left: 6,
              right: 6,
              top: 2,
              bottom: 2
            })
            .backgroundColor(msg.status === '未恢复' ? "#FEF2F2" : "#F0FDF4")
            .border({ width: 1, color: msg.status === '未恢复' ? "#FECACA" : "#DCFCE7" })
            .borderRadius(4)
        }

        Row() {
          Text(msg.time)
            .fontSize(12)
            .fontColor($r("app.color.home_status_text"))
            .fontWeight(FontWeight.Medium)
          Text(` · ${msg.date}`)
            .fontSize(10)
            .fontColor($r("app.color.home_subtitle_text"))
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 12 })

      // Content
      Row() {
        Column() {
          Text("来源设备")
            .fontSize(10)
            .fontColor($r("app.color.home_status_text"))
            .margin({ bottom: 4 })
          Text(msg.device)
            .fontSize(13)
            .fontColor($r("app.color.home_value_text"))
            .fontWeight(FontWeight.Medium)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text("异常数值")
            .fontSize(10)
            .fontColor($r("app.color.home_status_text"))
            .margin({ bottom: 4 })
          Text(msg.value)
            .fontSize(13)
            .fontColor($r("app.color.home_value_text"))
            .fontWeight(FontWeight.Medium)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r("app.color.control_icon_bg"))
      .borderRadius(8)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r("app.color.home_card_background"))
    .borderRadius(12)
    .shadow({ radius: 10, color: $r("app.color.card_shadow"), offsetY: 2 })
  }
}