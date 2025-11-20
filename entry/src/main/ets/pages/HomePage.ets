import { HomePageLogic, TrendResult, SERVER_HOST } from './HomePageLogic';
import webview from '@ohos.web.webview';
import http from '@ohos.net.http';

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


@Component
export struct HomePage {
  // UI 状态
  @State wsConnected: boolean = false;
  @State temp: number | undefined = undefined;
  @State hum: number | undefined = undefined;
  @State lux: number | undefined = undefined;
  @State smoke: number | undefined = undefined;
  @State pressure: number | undefined = undefined;
  @State temp2: number | undefined = undefined;
  @State rs_ro: number | undefined = undefined;
  @State lastUpdateTime: string = '--:--:--';
  @State sampleCount: number = 0;
  // 趋势状态
  @State tempTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @State humTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @State luxTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @State smokeTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @State pressureTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  @State tempDiffTrend: TrendResult = { direction: 'stable', value: 0, text: '趋势稳定' };
  // 定位状态
  @State locationStatus: string = '未获取定位';
  @State locationStatusColor: string = '#9ca3af';
  @State locationLon: string = '--';
  @State locationLat: string = '--';
  @State locationExtra: string = '';
  @State locationAvailable: boolean = false;
  @State showLocationMap: boolean = false;
  @State isQueryingLocation: boolean = false;
  // 业务逻辑实例（负责 WebSocket 与数据处理）
  private logic: HomePageLogic | null = null;
  // H5 地图 Web 控制器
  private mapWebController: webview.WebviewController = new webview.WebviewController();

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
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        }
      });

      let isOk: boolean = false;
      if (response && response.responseCode === 200) {
        // 如果后端返回 JSON，可以在这里按需解析
        // 这里为了避免 any/unknown，仅根据状态码判断成功
        isOk = true;
      }

      if (!isOk) {
        this.locationStatus = '获取失败';
        this.locationStatusColor = '#ef4444';
      }
      // 成功的情况：保持“正在获取定位...”，等待 WebSocket 推送 location 数据来更新 UI
    } catch {
      console.error('定位查询请求失败');
      this.locationStatus = '请求失败';
      this.locationStatusColor = '#ef4444';
    } finally {
      httpRequest.destroy();
      this.isQueryingLocation = false;
    }
  }

  // 生命周期函数
  aboutToAppear() {
    if (this.logic === null) {
      this.logic = new HomePageLogic(this);
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

          // 定位信息卡片（参考 README/index.html 的布局与配色）
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
        }
      }
      .width("100%")
      .padding({bottom:100})

    }

    .backgroundColor($r("app.color.home_background"))
    .width("100%")
    .height("100%")
    .expandSafeArea()
  }
}
