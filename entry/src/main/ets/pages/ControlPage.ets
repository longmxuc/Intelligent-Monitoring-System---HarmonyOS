import { SensorInfo } from './ControlSensorPage';
import { http } from '@kit.NetworkKit';
import { SERVER_HOST } from './DevicesPageLogic';
import promptAction from '@ohos.promptAction';
import { switchSensor } from './ControlSensorPageLogic';

// API 返回的设备接口
interface ApiDevice {
  id: string;
  name: string;
  online: boolean;
  via?: string[];
  has_ble?: boolean;
  has_mqtt?: boolean;
  description?: string;
}

// 设备信息接口
interface Device {
  id: string;
  name: string;
  icon: Resource;
  online: boolean;
}

// 导航参数接口
interface NavParams {
  sensorInfo: SensorInfo;
}

@ComponentV2
export struct ControlPage {
  @Consumer('pageStack') pageStack: NavPathStack = new NavPathStack();

  // 定义主题色
  public readonly selectedColor: string = "#2A4DD0"; // 选中颜色
  public readonly normalColor: string = "#999999"; // 未选中颜色
  
  // 开关状态
  @Local bleEnabled: boolean = false;
  @Local oledEnabled: boolean = true;
  
  // 设备选择相关
  @Local selectedDeviceIndex: number = 0; // 当前选中的设备索引
  @Local showDeviceSelector: boolean = false; // 是否显示设备选择器
  
  // 可选设备列表（带图标映射）
  private deviceIconMap: Map<string, Resource> = new Map([
    ["D01", $r("app.media.ic_lab")],
    ["D02", $r("app.media.ic_computing")],
    ["D03", $r("app.media.ic_liquid_cooling")],
    ["D04", $r("app.media.ic_visitor")]
  ]);
  
  // 设备列表（从API获取并合并图标，初始化默认值防止崩溃）
  @Local devices: Device[] = [
    { id: "D01", name: "实验平台", icon: $r("app.media.ic_lab"), online: false },
    { id: "D02", name: "算力机房", icon: $r("app.media.ic_computing"), online: false },
    { id: "D03", name: "液冷中心", icon: $r("app.media.ic_liquid_cooling"), online: false },
    { id: "D04", name: "访客中心", icon: $r("app.media.ic_visitor"), online: false }
  ];
  
  // 定时器ID
  private refreshTimer: number | null = null;

  aboutToAppear(): void {
    // 立即加载一次
    this.loadDeviceStatus();
    // 每3秒刷新一次设备状态
    this.refreshTimer = setInterval(() => {
      this.loadDeviceStatus();
    }, 3000);
  }

  aboutToDisappear(): void {
    // 清除定时器
    if (this.refreshTimer !== null) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  // 加载设备在线状态
  async loadDeviceStatus(): Promise<void> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(`http://${SERVER_HOST}/api/devices`, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        interface ApiResponse {
          success: boolean;
          devices?: ApiDevice[];
          count?: number;
        }
        const result = JSON.parse(response.result as string) as ApiResponse;
        
        if (result.success && result.devices) {
          // 将API设备数据与图标映射合并
          const updatedDevices: Device[] = [];
          for (const apiDevice of result.devices) {
            const icon = this.deviceIconMap.get(apiDevice.id) || $r("app.media.ic_lab");
            const device: Device = {
              id: apiDevice.id,
              name: apiDevice.name,
              icon: icon,
              online: apiDevice.online
            };
            updatedDevices.push(device);
          }
          this.devices = updatedDevices;
          console.info(`[设备状态] 加载成功，在线: ${updatedDevices.filter(d => d.online).length}/${updatedDevices.length}`);
        }
      }
    } catch (err) {
      console.error(`[设备状态] 加载失败: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Column() {
      // 顶部选择设备
      Column({ space: 10 }) {
        Text("请选择需要控制的设备")
          .fontColor($r("app.color.home_title_text"))
          .fontSize(12)
          .width("100%")
        
        // 设备选择框
        Row() {
          Row({ space: 8 }) {
            Image(this.devices[this.selectedDeviceIndex].icon)
              .width(24)
              .height(24)
              .fillColor(this.selectedColor)
            
            Text(this.devices[this.selectedDeviceIndex].name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedColor)
          }
          
          Blank()

          // 箭头
          Column()
            .width(7)
            .height(7)
            .borderWidth({bottom:2,right:2})
            .borderColor("#2A4DD0")
            .rotate({angle:45})
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .width("100%")
        .borderRadius(12)
        .backgroundColor($r("app.color.control_device_select_bg"))
        .onClick(() => {
          this.showDeviceSelector = true;
        })
      }
      .padding(20)
      .width("100%")
      .backgroundColor($r("app.color.home_card_background"))

      // 传感器列表
      Scroll() {
        Column({ space: 16 }) {
          // 1. MQ2 烟雾传感器
          this.SensorCard(
            $r("app.media.ic_sensor_mq2"),
            "#FF6B35",
            "MQ2 烟雾传感器",
            "节能调度",
            false
          )
          
          // 2. BMP180 气压传感器
          this.SensorCard(
            $r("app.media.ic_sensor_bmp180"),
            "#EF4444",
            "BMP180 气压传感器",
            "节能调度",
            false
          )
          
          // 3. BH1750 亮度传感器
          this.SensorCard(
            $r("app.media.ic_sensor_bh1750"),
            "#F59E0B",
            "BH1750 亮度传感器",
            "节能调度",
            false
          )
          
          // 4. BLE 蓝牙模块
          this.SensorCard(
            $r("app.media.ic_sensor_ble"),
            "#3B82F6",
            "BLE 蓝牙模块",
            "远程控制",
            true,
            this.bleEnabled
          )
          
          // 5. OLED 显示屏
          this.SensorCard(
            $r("app.media.ic_sensor_oled"),
            "#6B7280",
            "OLED 显示屏",
            "远程控制",
            true,
            this.oledEnabled
          )
        }
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .width("100%")
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("app.color.home_background"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showDeviceSelector, this.DeviceSelectorSheet(), {
      height: 400,
      dragBar: true,
      backgroundColor: $r("app.color.home_card_background"),
      onDisappear: () => {
        this.showDeviceSelector = false;
      }
    })
  }

  // 设备选择器面板
  @Builder
  DeviceSelectorSheet() {
    Column({ space: 0 }) {
      // 标题
      Row() {
        Text("选择控制设备")
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r("app.color.home_title_text"))
        
        Blank()
        
        Image($r('sys.symbol.xmark'))
          .width(20)
          .height(20)
          .fillColor($r("app.color.home_subtitle_text"))
          .onClick(() => {
            this.showDeviceSelector = false;
          })
      }
      .width("100%")
      .padding({ left: 20, right: 20, top: 20, bottom: 16 })
      
      Divider()
        .color($r("app.color.home_card_border"))
      
      // 设备列表
      List({ space: 0 }) {
        ForEach(this.devices, (device: Device, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              // 设备图标
              Row() {
                Image(device.icon)
                  .width(20)
                  .height(20)
                  .fillColor(!device.online ? "#CCCCCC" : 
                    (this.selectedDeviceIndex === index ? this.selectedColor : this.normalColor))
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r("app.color.control_icon_bg"))
              .justifyContent(FlexAlign.Center)
              .opacity(!device.online ? 0.5 : 1)
              
              // 设备信息
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(device.name)
                    .fontSize(16)
                    .fontWeight(this.selectedDeviceIndex === index ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(!device.online ? "#CCCCCC" :
                      (this.selectedDeviceIndex === index ? this.selectedColor : $r("app.color.home_title_text")))
                  
                  // 离线标签
                  if (!device.online) {
                    Text("离线")
                      .fontSize(10)
                      .fontColor("#EF4444")
                      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                      .backgroundColor("#FEE2E2")
                      .borderRadius(4)
                  }
                }
                
                Text(`设备ID: ${device.id}`)
                  .fontSize(12)
                  .fontColor(!device.online ? "#CCCCCC" : $r("app.color.home_subtitle_text"))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              
              // 选中标记
              if (this.selectedDeviceIndex === index) {
                Image($r('sys.symbol.checkmark_circle_fill'))
                  .width(24)
                  .height(24)
                  .fillColor(this.selectedColor)
              }
            }
            .width("100%")
            .padding({ left: 20, right: 20, top: 16, bottom: 16 })
            .opacity(!device.online ? 0.6 : 1)
            .onClick(() => {
              // 离线设备不可选择
              if (!device.online) {
                promptAction.showToast({
                  message: '设备离线，无法选择',
                  duration: 2000
                });
                return;
              }
              this.selectedDeviceIndex = index;
              this.showDeviceSelector = false;
            })
          }
          .backgroundColor($r("app.color.home_card_background"))
        }, (device: Device) => device.id)
      }
      .width("100%")
      .layoutWeight(1)
      .divider({
        strokeWidth: 1,
        color: $r("app.color.home_card_border")
      })
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("app.color.home_card_background"))
  }

  // 传感器卡片组件
  @Builder
  SensorCard(
    icon: Resource,
    iconColor: string,
    title: string,
    mode: string,
    isSwitch: boolean,
    switchState?: boolean
  ) {
    Row({ space: 16 }) {
      // 左侧图标
      Row() {
        Image(icon)
          .width(32)
          .height(32)
          .fillColor(iconColor)
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor($r("app.color.control_icon_bg"))
      .justifyContent(FlexAlign.Center)
      
      // 中间文字信息
      Column({ space: 6 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.home_title_text"))
        
        Text(mode)
          .fontSize(12)
          .fontColor($r("app.color.home_subtitle_text"))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      
      // 右侧按钮或开关
      if (isSwitch) {
        Toggle({ type: ToggleType.Switch, isOn: switchState })
          .width(48)
          .height(28)
          .selectedColor("#3B82F6")
          .onChange(async (isOn: boolean) => {
            console.info(`[控制页-开关] ${title} 切换到: ${isOn ? "开启" : "关闭"}`);
            
            // 获取当前选中的设备
            const currentDevice = this.devices[this.selectedDeviceIndex];
            
            // 检查设备是否在线
            if (!currentDevice.online) {
              promptAction.showToast({
                message: '设备离线，无法控制',
                duration: 2000
              });
              // 恢复开关状态
              if (title.includes("BLE")) {
                this.bleEnabled = !isOn;
              } else if (title.includes("OLED")) {
                this.oledEnabled = !isOn;
              }
              return;
            }
            
            try {
              // 调用 API 控制传感器
              const action = isOn ? 'on' : 'off';
              const result = await switchSensor(title, currentDevice.id, action);
              
              console.info(`[控制页-开关] API返回: ${JSON.stringify(result)}`);
              
              if (result.success) {
                // 更新本地状态
                if (title.includes("BLE")) {
                  this.bleEnabled = isOn;
                } else if (title.includes("OLED")) {
                  this.oledEnabled = isOn;
                }
                promptAction.showToast({
                  message: `${title} ${isOn ? "开启" : "关闭"}成功`,
                  duration: 2000
                });
              } else {
                // 失败时恢复开关状态
                promptAction.showToast({
                  message: `操作失败: ${result.error}`,
                  duration: 2000
                });
                if (title.includes("BLE")) {
                  this.bleEnabled = !isOn;
                } else if (title.includes("OLED")) {
                  this.oledEnabled = !isOn;
                }
              }
            } catch (err) {
              console.error(`[控制页-开关] 控制失败: ${JSON.stringify(err)}`);
              promptAction.showToast({
                message: '控制失败',
                duration: 2000
              });
              // 恢复开关状态
              if (title.includes("BLE")) {
                this.bleEnabled = !isOn;
              } else if (title.includes("OLED")) {
                this.oledEnabled = !isOn;
              }
            }
          })
      } else {
        Button("配置")
          .fontSize(14)
          .fontColor("#3B82F6")
          .backgroundColor("transparent")
          .border({ width: 1, color: "#3B82F6", radius: 8 })
          .padding({ left: 8, right: 8, top: 1, bottom: 1 })
          .onClick(() => {
            console.info(`配置 ${title}`);
            // 获取当前选中的设备
            const currentDevice = this.devices[this.selectedDeviceIndex];
            // 构造传感器信息对象
            const sensorInfo: SensorInfo = {
              name: title,
              icon: icon,
              iconColor: iconColor,
              deviceName: currentDevice.name,
              deviceId: currentDevice.id
            };
            // 构造导航参数对象
            const navParams: NavParams = {
              sensorInfo: sensorInfo
            };
            // 传递传感器和设备信息到配置页面
            this.pageStack.pushPath({
              name: 'ControlSensorPage',
              param: navParams
            });
          })
      }
    }
    .width("100%")
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r("app.color.home_card_background"))
    .shadow({
      radius: 8,
      color: $r("app.color.card_shadow"),
      offsetX: 0,
      offsetY: 2
    })
  }
}
