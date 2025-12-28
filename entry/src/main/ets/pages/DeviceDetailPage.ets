import { DeviceDetailPageLogic, TrendResult, SensorData } from './DeviceDetailPageLogic';
import { SERVER_HOST } from './WebSocketManager';
import webview from '@ohos.web.webview';
import http from '@ohos.net.http';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { emitter } from '@kit.BasicServicesKit';
import { DataLoadFloatButton } from './DataLoadComponent';

// 定位查询接口返回结构
interface LocationQueryResponse {
  success?: boolean;
  message?: string;
  error?: string;
}

// 顶层趋势行组件（避免作用域问题）
@Component
struct TrendRow {
  @Prop trend: TrendResult;

  build() {
    Row({ space: 4 }) {
      if (this.trend.direction === 'up') {
        Text('↑')
          .fontSize(14)
          .fontColor('#dc2626')
      } else if (this.trend.direction === 'down') {
        Text('↓')
          .fontSize(14)
          .fontColor('#16a34a')
      } else {
        Text('—')
          .fontSize(14)
          .fontColor('#64748b')
      }
      Text(this.trend.text)
        .fontSize(12)
        .fontColor(this.trend.direction === 'up' ? '#dc2626' :
          this.trend.direction === 'down' ? '#16a34a' : '#64748b')
    }

  }
}

// 顶层指标卡片组件
@Component
struct MetricCard {
  @Prop title: string;
  @Prop valueText: string;
  @Prop trend: TrendResult;
  @Prop valueFontSize: number;

  build() {
    Row({ space: 5 }) {
      Column() {
        Column({ space: 10 }) {
          Text(this.title)
            .fontSize(14)
            .fontColor($r("app.color.home_title_text"))
          Text(this.valueText)
            .fontSize(this.valueFontSize)
            .fontWeight(FontWeight.Bolder)
            .fontColor($r("app.color.home_value_text"))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)

        TrendRow({ trend: this.trend })
      }
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width("100%")
    .height(100)
    .padding({
      left: 10,
      top: 10,
      right: 10,
      bottom: 10
    })
    .borderColor($r("app.color.home_card_border"))
    .borderWidth(1)
    .backgroundColor($r("app.color.home_card_background"))
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#1F000000',
      offsetX: 0,
      offsetY: 2
    })
  }
}


@ComponentV2
export struct DeviceDetailPage {
  // 1. 接收路由栈，用于回退
  @Consumer('pageStack') pageStack: NavPathStack = new NavPathStack();
  // 2. 接收页面参数
  @Local deviceId: string = "";
  @Local deviceName: string = ""; // 设备名称
  // UI 状态
  @Local wsConnected: boolean = false;
  @Local temp: number | undefined = undefined;
  @Local hum: number | undefined = undefined;
  @Local lux: number | undefined = undefined;
  @Local smoke: number | undefined = undefined;
  @Local pressure: number | undefined = undefined;
  @Local temp2: number | undefined = undefined;
  @Local rs_ro: number | undefined = undefined;
  @Local lastUpdateTime: string = '--:--:--';
  @Local sampleCount: number = 0;
  // 趋势状态
  @Local tempTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @Local humTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @Local luxTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @Local smokeTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @Local pressureTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @Local tempDiffTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  // 定位状态
  @Local locationStatus: string = '未获取定位';
  @Local locationStatusColor: string = '#9ca3af';
  @Local locationLon: string = '--';
  @Local locationLat: string = '--';
  @Local locationExtra: string = '';
  @Local locationAvailable: boolean = false;
  @Local showLocationMap: boolean = false;
  @Local isQueryingLocation: boolean = false;
  // 业务逻辑实例（负责 WebSocket 与数据处理）
  private logic: DeviceDetailPageLogic | null = null;
  // H5 地图 Web 控制器
  private mapWebController: webview.WebviewController = new webview.WebviewController();
  // 图表 Web 控制器
  private chartsWebController: webview.WebviewController = new webview.WebviewController();
  // 图表是否已就绪
  @Local chartsReady: boolean = false;

  // 生成 H5 地图页面的地址（通过 query 传入经纬度）
  private getLocationMapUrl(): string {
    const baseUrl: string = 'resource://RAWFILE/location_map.html';
    if (!this.locationAvailable) {
      return baseUrl;
    }
    const lonNum: number = Number.parseFloat(this.locationLon);
    const latNum: number = Number.parseFloat(this.locationLat);
    if (Number.isNaN(lonNum) || Number.isNaN(latNum)) {
      return baseUrl;
    }
    // 只传经纬度，其他信息在卡片中展示
    return `${baseUrl}?lon=${lonNum}&lat=${latNum}`;
  }

  // 发送定位查询命令（HTTP 调用后端 /api/location/query）
  private async sendLocationQuery(): Promise<void> {
    if (this.isQueryingLocation) {
      return;
    }

    this.isQueryingLocation = true;
    this.locationStatus = '正在获取定位...';
    this.locationStatusColor = '#f59e0b';

    const httpRequest: http.HttpRequest = http.createHttp();

    try {
      const url: string = `http://${SERVER_HOST}/api/location/query`;
      // 构造请求体，包含设备ID
      const requestBody = JSON.stringify({
        device_id: this.deviceId
      });

      console.info(`发送定位查询请求 - 设备ID: ${this.deviceId}`);

      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: requestBody
      });

      let isOk: boolean = false;
      if (response && response.responseCode === 200) {
        isOk = true;
        console.info(`定位查询请求成功 - 设备: ${this.deviceId}`);
      }

      if (!isOk) {
        this.locationStatus = '获取失败';
        this.locationStatusColor = '#ef4444';
      }
      // 成功的情况：保持"正在获取定位..."，等待 WebSocket 推送 location 数据来更新 UI
    } catch (err) {
      console.error(`定位查询请求失败 - 设备: ${this.deviceId}`, err);
      this.locationStatus = '请求失败';
      this.locationStatusColor = '#ef4444';
    } finally {
      httpRequest.destroy();
      this.isQueryingLocation = false;
    }
  }

  // 更新图表数据（由Logic层调用）
  updateCharts(timestamp: number, temp: number, hum: number, lux: number, smoke: number, pressure: number): void {
    // 检查图表是否已就绪
    if (!this.chartsReady) {
      console.warn('图表尚未就绪，跳过实时数据');
      return;
    }

    try {
      // 构造JavaScript调用字符串
      const jsCode = `window.addDataPoint(${timestamp}, ${temp}, ${hum}, ${lux || 0}, ${smoke || 0}, ${pressure || 0})`;
      // 执行JavaScript
      this.chartsWebController.runJavaScript(jsCode);
    } catch (err) {
      console.error('更新图表失败:', err);
    }
  }

  // 清空图表数据
  clearCharts(): void {
    if (!this.chartsReady) {
      return;
    }
    try {
      this.chartsWebController.runJavaScript('window.clearData()');
      console.info('图表数据已清空');
    } catch (err) {
      console.error('清空图表失败:', err);
    }
  }

  // 批量加载历史数据到图表（由Logic层调用）
  loadHistoryToCharts(historyData: SensorData[]): void {
    // 检查图表是否已就绪
    if (!this.chartsReady) {
      console.warn('图表尚未就绪，延迟加载历史数据');
      // 延迟1秒后重试
      setTimeout(() => {
        this.loadHistoryToCharts(historyData);
      }, 1000);
      return;
    }

    try {
      console.info(`开始加载 ${historyData.length} 条历史数据到图表`);
      // 先清空旧数据
      this.clearCharts();
      // 将数据转换为JSON字符串，批量传递给Web端
      const dataJson = JSON.stringify(historyData);
      const jsCode = `window.loadHistoryData('${dataJson.replace(/'/g, "\\'")}')`;
      this.chartsWebController.runJavaScript(jsCode);
      console.info('历史数据已发送到图表');
    } catch (err) {
      console.error('加载历史数据到图表失败:', err);
    }
  }

  // 更新图表主题
  updateChartsTheme(): void {
    try {
      // 从AppStorage获取当前颜色模式
      const currentMode = AppStorage.get<number>('currentColorMode');
      const isDarkMode = currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      console.info(`更新图表主题: ${isDarkMode ? '暗色' : '亮色'} (currentMode=${currentMode}, DARK=${ConfigurationConstant.ColorMode.COLOR_MODE_DARK})`);
      // 调用Web端的setTheme方法
      const jsCode = `window.setTheme(${isDarkMode})`;
      this.chartsWebController.runJavaScript(jsCode);
    } catch (err) {
      console.error('更新图表主题失败:', err);
    }
  }


  // 处理页面就绪的方法
  private handlePageReady(context: NavDestinationContext): void {
    const params = context.pathInfo.param as Record<string, string>;
    if (params) {
      if (params['deviceId']) {
        this.deviceId = params['deviceId'];
        console.info(`DeviceDetailPage onReady - 获取到 deviceId: ${this.deviceId}`);
      }
      if (params['deviceName']) {
        this.deviceName = params['deviceName'];
        console.info(`DeviceDetailPage onReady - 获取到 deviceName: ${this.deviceName}`);
      }
    }

    // 如果AppStorage中没有颜色模式，使用默认值
    if (!AppStorage.has('currentColorMode')) {
      AppStorage.setOrCreate('currentColorMode', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    }

    // 获取参数后，设置deviceId并启动WebSocket连接
    if (this.logic && this.deviceId) {
      this.logic.setDeviceId(this.deviceId);
      this.logic.aboutToAppear();
    } else {
      console.error('Logic未初始化或deviceId为空');
    }
  }

  // 生命周期函数
  aboutToAppear() {
    console.info(`DeviceDetailPage aboutToAppear - deviceId: ${this.deviceId}`);
    if (this.logic === null) {
      // 先创建Logic，deviceId稍后在onReady中设置
      this.logic = new DeviceDetailPageLogic(this);
    }

    // 订阅主题变化事件
    try {
      emitter.on({ eventId: 1001 }, () => {
        console.info('收到主题变化事件，更新图表');
        this.updateChartsTheme();
      });
    } catch (err) {
      console.error('订阅主题变化事件失败:', err);
    }
    // 注意：这里暂不调用 aboutToAppear，等获取到 deviceId 后再连接
  }

  aboutToDisappear() {
    // 取消订阅主题变化事件
    try {
      emitter.off(1001);
    } catch (err) {
      console.error('取消订阅主题变化事件失败:', err);
    }

    if (this.logic) {
      this.logic.aboutToDisappear();
    }
  }

  // 自定义标题栏组件
  @Builder
  CustomNavBar() {
    Stack({ alignContent: Alignment.Center }) {
      // 左侧返回按钮
      Row() {
        Image($r("app.media.ic_back"))
          .height("100%")
        // .fillColor($r("app.color.home_title_text"))

      }
      .width(30)
      .height(30)
      .borderRadius(15)
      // .backgroundColor(Color.Red)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .position({ x: 10, y: 10 }) // 绝对定位在左侧
      .onClick(() => {
        this.pageStack.pop();
      })
      .zIndex(10) // 确保在最上层，可点击

      // 2. 中间内容：Logo + 标题
      Row({ space: 5 }) { // 使用 Row 让 Logo 和文字并排
        // Logo 图片
        Image($r("app.media.logo"))
          .width(150)
          .objectFit(ImageFit.Contain) // 保持比例完整显示
          .autoResize(true)

        // 标题文字
        Text(this.deviceName || "设备详情")
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r("app.color.home_value_text"))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .margin({ right: 20 })
      .height('100%')
      .justifyContent(FlexAlign.Center) // 整体居中
      .alignItems(VerticalAlign.Center)
      .width('70%') // 限制中间区域宽度，防止遮挡两边
      .hitTestBehavior(HitTestMode.None) // 中间区域不拦截点击，虽然这里没有交互，但是好习惯
    }
    .width('100%')
    .height(45) // 导航栏高度
  }

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        // 插入自定义标题栏
        this.CustomNavBar()

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

          // 上次更新
          Row({ space: 5 }) {
            Text(`上次更新: ${this.lastUpdateTime}`)
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

          // 样本数
          Row({ space: 5 }) {
            Text(`样本数: ${this.sampleCount}`)
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
        // .backgroundColor(Color.Red)
        .padding({ left: 10, right: 10 })

        // -------------------------------------------------------------------------------------
        // 1. Stack 加 .layoutWeight(1)，让它填满 Column 剩余空间，而不是被 Scroll 撑大
        // 2. Scroll 加 .height('100%')，让它适配 Stack 的高度
        // -------------------------------------------------------------------------------------
        Stack({ alignContent: Alignment.BottomEnd }) {
          Scroll() {
            Column({ space: 15 }) {
              // 传感器数据展示区域（Grid 三列两行）
              Grid() {
                // 温度
                GridItem() {
                  MetricCard({
                    title: "温度",
                    valueText: `${this.temp !== undefined && this.temp !== null ? this.temp.toFixed(2) : '--'} ℃`,
                    trend: this.tempTrend,
                    valueFontSize: 24
                  })
                }

                // 温差 Δ
                GridItem() {
                  MetricCard({
                    title: "温度 Δ",
                    valueText: `${this.temp !== undefined && this.temp !== null && this.temp2 !== undefined &&
                      this.temp2 !== null ? Math.abs(this.temp - this.temp2).toFixed(2) : '--'} ℃`,
                    trend: this.tempDiffTrend,
                    valueFontSize: 24
                  })
                }

                // 湿度
                GridItem() {
                  MetricCard({
                    title: "湿度",
                    valueText: `${this.hum !== undefined && this.hum !== null ? this.hum.toFixed(2) : '--'} %`,
                    trend: this.humTrend,
                    valueFontSize: 24
                  })
                }

                // 亮度
                GridItem() {
                  MetricCard({
                    title: "亮度",
                    valueText: `${this.lux !== undefined && this.lux !== null ? this.lux.toFixed(1) : '--'} lux`,
                    trend: this.luxTrend,
                    valueFontSize: 24
                  })
                }

                // 烟雾
                GridItem() {
                  MetricCard({
                    title: "烟雾",
                    valueText: `${this.smoke !== undefined && this.smoke !== null ? this.smoke.toFixed(1) : '--'} ppm`,
                    trend: this.smokeTrend,
                    valueFontSize: 24
                  })
                }

                // 大气压
                GridItem() {
                  MetricCard({
                    title: "大气压",
                    valueText: `${this.pressure !== undefined && this.pressure !== null ? this.pressure.toFixed(1) :
                      '--'} hPa`,
                    trend: this.pressureTrend,
                    valueFontSize: 22
                  })
                }
              }
              .columnsTemplate("1fr 1fr")
              // .rowsTemplate("auto auto auto")
              .columnsGap(12)
              .rowsGap(12)
              .constraintSize({ maxWidth: 600 })
              .width("100%")
              .padding({
                // left: 15,
                // right: 15,
                top: 15
              })

              // 定位信息卡片
              Column() {
                Row({ space: 8 }) {
                  Text("📍 设备定位")
                    .fontWeight(FontWeight.Bolder)
                    .fontSize(16)
                    .fontColor($r("app.color.home_value_text"))
                  Text(this.locationStatus)
                    .fontColor(this.locationStatusColor)
                    .fontSize(12)
                    .margin({ left: 8 })
                }
                .width("100%")

                if (this.locationAvailable) {
                  Grid() {
                    GridItem() {
                      Column({ space: 4 }) {
                        Text("经度")
                          .fontSize(12)
                          .fontColor($r("app.color.home_status_text"))
                        Text(this.locationLon)
                          .fontSize(22)
                          .fontWeight(FontWeight.Bolder)
                          .fontColor($r("app.color.home_value_text"))
                      }
                    }

                    GridItem() {
                      Column({ space: 4 }) {
                        Text("纬度")
                          .fontSize(12)
                          .fontColor($r("app.color.home_status_text"))
                        Text(this.locationLat)
                          .fontSize(22)
                          .fontWeight(FontWeight.Bolder)
                          .fontColor($r("app.color.home_value_text"))
                      }
                    }
                  }
                  .columnsTemplate("1fr 1fr")
                  .columnsGap(12)
                  .margin({ top: 10 })
                } else {
                  Text("等待服务器推送定位数据...")
                    .fontSize(12)
                    .fontColor($r("app.color.home_status_text"))
                    .margin({ top: 10 })
                }

                if (this.locationExtra && this.locationExtra.length > 0) {
                  Text(this.locationExtra)
                    .fontSize(12)
                    .fontColor($r("app.color.home_status_text"))
                    .margin({ top: 8 })
                }

                // 发送定位按钮 + 地图开关
                Row({ space: 8 }) {
                  Button(this.isQueryingLocation ? "⏳ 正在获取定位..." : "📍 发送定位")
                    .fontSize(12)
                    .fontColor(Color.White)
                    .backgroundColor('#2563eb')
                    .borderRadius(8)
                    .padding({
                      left: 10,
                      right: 10,
                      top: 6,
                      bottom: 6
                    })
                    .enabled(!this.isQueryingLocation)
                    .onClick(() => {
                      if (this.isQueryingLocation) {
                        return;
                      }
                      this.sendLocationQuery();
                      // 主动展开地图，等待定位结果
                      if (!this.showLocationMap) {
                        this.showLocationMap = true;
                      }
                    })

                  Button(this.showLocationMap ? "🗺 收起地图" : "🗺 显示地图")
                    .fontSize(12)
                    .fontColor(Color.White)
                    .backgroundColor(this.locationAvailable ? '#2563eb' : '#4b5563')
                    .borderRadius(8)
                    .padding({
                      left: 10,
                      right: 10,
                      top: 6,
                      bottom: 6
                    })
                    .enabled(this.locationAvailable)
                    .onClick(() => {
                      if (!this.locationAvailable) {
                        return;
                      }
                      this.showLocationMap = !this.showLocationMap;
                    })
                }
                .margin({ top: 10 })

                if (this.locationAvailable) {
                  // 始终渲染地图容器，通过高度和透明度配合 animation 实现过渡动画
                  Column() {
                    Web({
                      src: this.getLocationMapUrl(),
                      controller: this.mapWebController
                    })
                      .javaScriptAccess(true)
                      .width('100%')
                      .height('100%')
                  }
                  .width('100%')
                  .height(this.showLocationMap ? 260 : 0)
                  .opacity(this.showLocationMap ? 1 : 0)
                  .margin({ top: 12 })
                  .animation({
                    duration: 250,
                    curve: Curve.EaseInOut
                  })
                }
              }
              .constraintSize({ maxWidth: 600 })
              .width("100%")
              .padding({
                left: 12,
                right: 12,
                top: 12,
                bottom: 12
              })
              .borderColor($r("app.color.home_card_border"))
              .borderWidth(1)
              .backgroundColor($r("app.color.home_card_background"))
              .borderRadius(12)
              .shadow({
                radius: 8,
                color: '#1F000000',
                offsetX: 0,
                offsetY: 2
              })

              // 数据图表区域
              Column() {
                Web({
                  src: 'resource://RAWFILE/charts.html',
                  controller: this.chartsWebController
                })
                  .javaScriptAccess(true)
                  .domStorageAccess(true)
                  .width('100%')
                  .height(1200) // 4个图表，每个约200px高 + 间距
                  .backgroundColor(Color.Transparent)
                  .onPageEnd(() => {
                    // 页面加载完成后，立即设置主题并标记图表已就绪
                    console.info('图表页面加载完成，设置初始主题');
                    setTimeout(() => {
                      this.updateChartsTheme();
                      this.chartsReady = true; // 标记图表已就绪
                      console.info('图表已就绪，可以接收数据');
                    }, 100); // 延迟100ms确保图表已初始化
                  })
              }
              .constraintSize({ maxWidth: 600 })
              .width("100%")
            }
          }
          .width("100%")
          .height('100%') // 关键：Scroll必须占满限制后的Stack高度
          .scrollBar(BarState.Auto) // 显式显示滚动条以便调试
          .padding({ bottom: 100, left: 15, right: 15 })

          // 数据加载悬浮按钮
          DataLoadFloatButton({
            deviceId: this.deviceId,
            onDataLoaded: (data: SensorData[], count: number) => {
              // 重新加载数据到图表
              this.loadHistoryToCharts(data);
              // 更新样本数和显示
              this.sampleCount = count;
              if (data.length > 0) {
                const lastData = data[data.length - 1];
                this.temp = lastData.temp;
                this.hum = lastData.hum;
                this.lux = lastData.lux;
                this.smoke = lastData.smoke;
                this.pressure = lastData.pressure;
                this.temp2 = lastData.temp2;
              }
            },
            // 使用 props 传递边距，而不是在外层设置
            rightMargin: 20,
            bottomMargin: 40
          })
            // .backgroundColor(Color.Green)
        }
        .width("100%")
        .layoutWeight(1) // 强制Stack占据Column剩余空间，限制Scroll高度，激活滚动！
        // .backgroundColor(Color.Pink)

      }
      .backgroundColor($r("app.color.home_background"))
      .width("100%")
      .height("100%")
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true) // 彻底隐藏系统标题栏，使用我们自己的 CustomNavBar
    .onReady((context: NavDestinationContext) => {
      this.handlePageReady(context);
    })
  }
}


// 导出 Builder 给 route_map.json 使用
@Builder
export function DeviceDetailPageBuilder() {
  DeviceDetailPage()
}