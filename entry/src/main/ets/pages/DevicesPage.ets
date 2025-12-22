import {
  DevicesPageLogic,
  DeviceInfo,
  DeviceRealtimeData,
  DeviceWarning,
  DevicesPageViewCallbacks
} from './DevicesPageLogic';
import promptAction from '@ohos.promptAction';

// 自定义设备卡片组件
@ComponentV2
struct DeviceCard {
  @Require @Param device: DeviceInfo;
  @Require @Param isOnline: boolean;
  @Param realtimeData: DeviceRealtimeData | undefined = undefined;
  @Param warning: DeviceWarning | undefined = undefined;

  build() {
    Column({ space: 12 }) {
      // 设备头部
      Row() {
        Column({ space: 4 }) {
          Text(this.device.name || `设备 ${this.device.id}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bolder)
            .fontColor($r("app.color.home_value_text"))
          Text(`ID: ${this.device.id}`)
            .fontSize(12)
            .fontColor($r("app.color.home_status_text"))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 状态标签
        Row() {
          Text(this.isOnline ? '在线' : '离线')
            .fontSize(12)
            .fontColor(this.isOnline ? '#16a34a' : '#dc2626')
        }
        .padding({
          left: 8,
          right: 8,
          top: 4,
          bottom: 4
        })
        .borderRadius(20)
        .backgroundColor(this.isOnline ? $r("app.color.online_state_bgc") : $r("app.color.offline_state_bgc"))
        .border({
          width: 1,
          color: this.isOnline ? '#22c55e' : '#ef4444',
          style: BorderStyle.Solid
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 实时数据网格
      Grid() {
        GridItem() {
          Column({ space: 6 }) {
            Text('实时温度')
              .fontSize(12)
              .fontColor($r("app.color.home_status_text"))
            Row({ space: 4 }) {
              Text(this.realtimeData?.temp !== undefined && this.realtimeData.temp !== null
                ? this.realtimeData.temp.toFixed(1) : '--')
                .fontSize(20)
                .fontWeight(FontWeight.Bolder)
                .fontColor($r("app.color.home_value_text"))
              Text('°C')
                .fontSize(12)
                .fontColor($r("app.color.home_status_text"))
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .borderColor($r("app.color.home_card_border"))
          .borderWidth(1)
          .backgroundColor($r("app.color.home_card_background"))
        }

        GridItem() {
          Column({ space: 6 }) {
            Text('实时湿度')
              .fontSize(12)
              .fontColor($r("app.color.home_status_text"))
            Row({ space: 4 }) {
              Text(this.realtimeData?.hum !== undefined && this.realtimeData.hum !== null
                ? this.realtimeData.hum.toFixed(1) : '--')
                .fontSize(20)
                .fontWeight(FontWeight.Bolder)
                .fontColor($r("app.color.home_value_text"))
              Text('%')
                .fontSize(12)
                .fontColor($r("app.color.home_status_text"))
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .borderColor($r("app.color.home_card_border"))
          .borderWidth(1)
          .backgroundColor($r("app.color.home_card_background"))
        }
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .width('100%')

      // 更新时间
      Text(`最近更新时间：${this.realtimeData?.ts ? this.formatTime(this.realtimeData.ts) : "--"}`)
        .fontSize(12)
        .fontColor($r("app.color.home_status_text"))
        .width('100%')

      // 警告信息
      Text(this.warning
        ?
        `⚠️ ${this.warning.warning_name || '危险'} · ${this.warning.warning_value || '--'}${this.warning.warning_unit ||
          ''}`
        : (this.isOnline ? '运行状态良好' : '等待实时数据...'))
        .fontSize(13)
        .fontColor(this.warning ? '#ef4444' : $r("app.color.home_status_text"))
        .width('100%')
        .padding({
          left: 10,
          right: 10,
          top: 10,
          bottom: 10
        })
        .borderRadius(10)
        .border({
          width: 1,
          color: this.warning ? '#ef4444' : $r("app.color.home_card_border"),
          style: BorderStyle.Dashed
        })
        .backgroundColor(this.warning ? '#ef444420' : $r("app.color.home_card_background"))
      Text("查看实时数据 ➜")
        .width("100%")
        .fontColor("#2563eb")
        .fontSize(12)
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .border({
      width: this.warning ? 3 : 1,
      color: this.warning ? '#ef4444' : $r("app.color.home_card_border"),
      style: BorderStyle.Solid
    })
    .backgroundColor($r("app.color.home_card_background"))
    .shadow({
      radius: this.warning ? 12 : 8,
      color: this.warning ? '#ef444450' : '#1F000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  private formatTime(ts: number): string {
    const date = new Date(ts * 1000);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }
}

@ComponentV2
export struct DevicesPage {
  // 接收父组件(Index)提供的 pageStack
  @Consumer('pageStack') pageStack: NavPathStack = new NavPathStack();

  @Local wsConnected: boolean = false;
  @Local devices: DeviceInfo[] = [];
  @Local onlineCount: number = 0;
  @Local totalCount: number = 0;
  @Local realtimeData: Map<string, DeviceRealtimeData> = new Map();
  @Local warnings: Map<string, DeviceWarning> = new Map();
  @Local deviceLastSeen: Map<string, number> = new Map();

  // 业务逻辑实例
  private logic: DevicesPageLogic | null = null;

  // 生命周期函数
  aboutToAppear() {
    if (this.logic === null) {
      const callbacks: DevicesPageViewCallbacks = {
        onWsConnectedChanged: (connected: boolean) => {
          this.wsConnected = connected;
        },
        onDevicesChanged: (devices: DeviceInfo[]) => {
          this.devices = devices;
        },
        onCountsChanged: (onlineCount: number, totalCount: number) => {
          this.onlineCount = onlineCount;
          this.totalCount = totalCount;
        },
        onRealtimeDataChanged: (data: Map<string, DeviceRealtimeData>) => {
          this.realtimeData = data;
        },
        onWarningsChanged: (warnings: Map<string, DeviceWarning>) => {
          this.warnings = warnings;
        },
        onDeviceLastSeenChanged: (lastSeen: Map<string, number>) => {
          this.deviceLastSeen = lastSeen;
        }
      };

      this.logic = new DevicesPageLogic(callbacks);
    }
    this.logic.aboutToAppear();
  }

  aboutToDisappear() {
    if (this.logic) {
      this.logic.aboutToDisappear();
    }
  }


  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r("app.media.logo"))
          .width(150)
        Text("智能环境监测系统")
          .fontWeight(FontWeight.Bolder)
          .fontSize(20)
      }
      .justifyContent(FlexAlign.Center)
      .width("100%")
      .margin({ bottom: 10, right: 20 })

      // 状态栏
      Row({ space: 10 }) {
        // 连接状态
        Row({ space: 5 }) {
          Row()
            .backgroundColor(this.wsConnected ? "#4CA154" : "#E53E3E")
            .width(12)
            .height(12)
            .borderRadius(100)
          Text(this.wsConnected ? "已连接" : "未连接")
            .fontColor($r("app.color.home_status_text"))
            .fontSize(12)
        }
        .padding({
          left: 10,
          right: 10,
          top: 5,
          bottom: 5
        })
        .borderColor($r("app.color.home_border"))
        .borderWidth(1)
        .borderRadius(30)

        // 设备统计
        Row({ space: 5 }) {
          Text(`在线：${this.onlineCount} 台 / 总设备：${this.totalCount} 台`)
            .fontColor($r("app.color.home_status_text"))
            .fontSize(12)
        }
        .padding({
          left: 10,
          right: 10,
          top: 5,
          bottom: 5
        })
        .borderColor($r("app.color.home_border"))
        .borderWidth(1)
        .borderRadius(30)
      }
      .width("100%")
      .justifyContent(FlexAlign.Center)
      .padding({ left: 10, right: 10 })

      // 设备列表
      if (this.devices.length === 0) {
        Column() {
          Text("正在加载设备列表...")
            .fontSize(14)
            .fontColor($r("app.color.home_status_text"))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else {
        Scroll() {
          Grid() {
            ForEach(this.devices, (device: DeviceInfo) => {
              GridItem() {
                Column() {
                  DeviceCard({
                    device: device,
                    isOnline: this.logic?.isDeviceOnlinePublic(device.id || device.device_id || '') || false,
                    realtimeData: this.realtimeData.get(device.id || device.device_id || ''),
                    warning: this.warnings.get(device.id || device.device_id || '')
                  })
                }
                .width('100%')
                .onClick(() => this.onDeviceCardTapped(device.id || device.device_id || ''))
              }
            }, (device: DeviceInfo) => device.id || device.device_id || '')
          }
          .columnsTemplate('1fr')
          .columnsGap(16)
          .rowsGap(16)
          .width('100%')
          .padding({
            left: 10,
            right: 10,
            top: 15,
            bottom: 100
          })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .backgroundColor($r("app.color.home_background"))
    .width("100%")
    .height("100%")
    .expandSafeArea()
  }

  private onDeviceCardTapped(rawId: string): void {
    try {
      const normalizedId = (rawId || '').trim().toUpperCase();
      if (!normalizedId) {
        promptAction.showToast({ message: '设备ID无效' });
        return;
      }

      // 查找设备信息以获取设备名称
      const device = this.devices.find(d =>
        (d.id || d.device_id || '').trim().toUpperCase() === normalizedId
      );
      const deviceName = device?.name || `设备 ${normalizedId}`;

      // 跳转到详情页，传递设备ID和名称
      const pathInfo: NavPathInfo = {
        name: "DeviceDetailPage",
        param: {
          "deviceId": normalizedId,
          "deviceName": deviceName
        } as Record<string, string>
      };

      this.pageStack.pushPath(pathInfo);
    } catch (err) {
      console.error('设备卡片点击处理失败:', err);
    }
  }
}

