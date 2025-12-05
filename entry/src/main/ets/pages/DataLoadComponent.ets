import http from '@ohos.net.http';
import promptAction from '@ohos.promptAction';
import { SensorData, SERVER_HOST } from './DeviceDetailPageLogic';

// 加载方式枚举
export enum LoadMode {
  COUNT, // 按条数
  TIME, // 按时间段
  RANGE, // 自定义范围
  ALL // 全部数据
}

// 时间单位枚举
export enum TimeUnit {
  MINUTE = 'minute',
  HOUR = 'hour',
  DAY = 'day',
  MONTH = 'month'
}

// 加载参数接口
export interface LoadParams {
  mode: LoadMode;
  count?: number; // 按条数：数据条数
  timeValue?: number; // 按时间：时间数量
  timeUnit?: TimeUnit; // 按时间：时间单位
  startTime?: number; // 按范围：开始时间戳
  endTime?: number; // 按范围：结束时间戳
}

// 加载结果回调接口
export interface DataLoadCallback {
  onDataLoaded: (data: SensorData[], count: number) => void;
  onLoadError?: (error: string) => void;
}

// 数据加载器类
export class DataLoader {
  private deviceId: string;
  private callback: DataLoadCallback;

  constructor(deviceId: string, callback: DataLoadCallback) {
    this.deviceId = deviceId;
    this.callback = callback;
  }

  // 执行数据加载
  async load(params: LoadParams): Promise<void> {
    try {
      let url = `http://${SERVER_HOST}/api/history`;
      const queryParams: string[] = [`device_id=${this.deviceId}`];

      switch (params.mode) {
        case LoadMode.COUNT:
          // 按条数加载
          if (params.count !== undefined && params.count > 0) {
            queryParams.push(`limit=${params.count}`);
          }
          break;

        case LoadMode.TIME:
          // 按时间段加载
          if (params.timeValue !== undefined && params.timeUnit !== undefined) {
            const now = Date.now() / 1000;
            let startTime = now;

            switch (params.timeUnit) {
              case TimeUnit.MINUTE:
                startTime = now - params.timeValue * 60;
                break;
              case TimeUnit.HOUR:
                startTime = now - params.timeValue * 3600;
                break;
              case TimeUnit.DAY:
                startTime = now - params.timeValue * 86400;
                break;
              case TimeUnit.MONTH:
                startTime = now - params.timeValue * 2592000; // 30天
                break;
            }

            url = `http://${SERVER_HOST}/api/history/range`;
            queryParams.push(`start=${startTime}`);
            queryParams.push(`end=${now}`);
          }
          break;

        case LoadMode.RANGE:
          // 自定义时间范围
          if (params.startTime !== undefined && params.endTime !== undefined) {
            url = `http://${SERVER_HOST}/api/history/range`;
            queryParams.push(`start=${params.startTime}`);
            queryParams.push(`end=${params.endTime}`);
          }
          break;

        case LoadMode.ALL:
          // 加载全部数据
          queryParams.push('limit=-1');
          break;
      }

      // 拼接查询参数
      url += '?' + queryParams.join('&');

      console.info(`开始加载数据: ${url}`);

      const httpRequest: http.HttpRequest = http.createHttp();
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        }
      });

      httpRequest.destroy();

      if (response && response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as Record<string, Object>;

        if (result['success'] === true && result['data']) {
          const dataArray = result['data'] as Array<Record<string, Object>>;
          console.info(`成功加载 ${dataArray.length} 条数据`);

          // 转换为 SensorData 数组
          const historyData: SensorData[] = [];
          dataArray.forEach((item: Record<string, Object>) => {
            if (item['type'] === 'reading') {
              historyData.push({
                ts: item['ts'] as number,
                temp: item['temp'] as number,
                hum: item['hum'] as number,
                lux: item['lux'] as number,
                smoke: item['smoke'] as number,
                pressure: item['pressure'] as number,
                temp2: item['temp2'] as number,
                rs_ro: item['rs_ro'] as number
              });
            }
          });

          // 回调通知数据加载完成
          this.callback.onDataLoaded(historyData, historyData.length);
        } else {
          const error = '数据加载失败或无数据';
          console.error(error);
          if (this.callback.onLoadError) {
            this.callback.onLoadError(error);
          }
        }
      } else {
        const error = `HTTP请求失败，状态码: ${response?.responseCode}`;
        console.error(error);
        if (this.callback.onLoadError) {
          this.callback.onLoadError(error);
        }
      }
    } catch (err) {
      const error = `数据加载异常: ${err}`;
      console.error(error);
      if (this.callback.onLoadError) {
        this.callback.onLoadError(error);
      }
    }
  }
}

// 数据加载浮动按钮和弹窗组件
@ComponentV2
export struct DataLoadFloatButton {
  @Require @Param deviceId: string;
  @Require @Param onDataLoaded: (data: SensorData[], count: number) => void;
  // 允许父组件传入边距，默认值设为 20 和 40
  @Param rightMargin: number = 20;
  @Param bottomMargin: number = 40;

  @Local showLoadPanel: boolean = false;
  @Local showModeSelection: boolean = true; // 是否显示模式选择界面
  @Local selectedMode: LoadMode = LoadMode.COUNT;
  @Local loadCount: number = 1000;
  @Local timeValue: number = 1;
  @Local timeUnit: TimeUnit = TimeUnit.HOUR;
  @Local startDate: Date = new Date(Date.now() - 86400000); // 默认昨天
  @Local endDate: Date = new Date();
  @Local isLoading: boolean = false;

  // 数据加载器
  private loader: DataLoader | null = null;

  aboutToAppear(): void {
    this.loader = new DataLoader(this.deviceId, {
      onDataLoaded: (data: SensorData[], count: number) => {
        this.isLoading = false;
        this.showLoadPanel = false;
        this.showModeSelection = true; // 重置状态
        try {
          promptAction.showToast({ message: `成功加载 ${count} 条数据`, duration: 2000 });
        } catch (e) {
          console.error('显示Toast失败:', e);
        }
        this.onDataLoaded(data, count);
      },
      onLoadError: (error: string) => {
        this.isLoading = false;
        try {
          promptAction.showToast({ message: `加载失败: ${error}`, duration: 2000 });
        } catch (e) {
          console.error('显示Toast失败:', e);
        }
      }
    });
  }

  // 执行加载
  private async executeLoad(): Promise<void> {
    if (this.isLoading || !this.loader) {
      return;
    }

    this.isLoading = true;

    const params: LoadParams = { mode: this.selectedMode };

    switch (this.selectedMode) {
      case LoadMode.COUNT:
        params.count = this.loadCount;
        break;
      case LoadMode.TIME:
        params.timeValue = this.timeValue;
        params.timeUnit = this.timeUnit;
        break;
      case LoadMode.RANGE:
        params.startTime = Math.floor(this.startDate.getTime() / 1000);
        params.endTime = Math.floor(this.endDate.getTime() / 1000);
        break;
      case LoadMode.ALL:
        // 无需额外参数
        break;
    }

    await this.loader.load(params);
  }

  build() {
    // 根容器 Stack
    // 核心修复逻辑：
    // 当 showLoadPanel 为 false 时，宽高设为 auto，此时 Stack 大小 = 按钮大小 + Margin。
    // 由于在父组件中使用了 Stack(BottomEnd)，这个小小的 Stack 会被自动对齐到右下角，完全不影响页面其他区域。
    // 当 showLoadPanel 为 true 时，宽高设为 100%，覆盖全屏显示遮罩。
    Stack({ alignContent: Alignment.BottomEnd }) {

      // 1. 加载面板 (Overlay)
      if (this.showLoadPanel) {
        // 背景遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#40000000')
          .onClick(() => {
            this.showLoadPanel = false;
          })
          .zIndex(998)

        // 面板主体
        Column() {
          // 标题栏
          Row() {
            Text("📊 加载历史数据")
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))
              .layoutWeight(1)

            Text("✕")
              .fontSize(24)
              .fontColor($r("app.color.home_status_text"))
              .onClick(() => {
                this.showLoadPanel = false;
              })
          }
          .width('100%')
          .padding(16)
          .borderColor($r("app.color.home_card_border"))
          .borderWidth({ bottom: 1 })

          Scroll() {
            Column({ space: 12 }) {
              if (this.showModeSelection) {
                this.buildModeSelection()
              } else if (this.selectedMode === LoadMode.COUNT) {
                this.buildCountForm()
              } else if (this.selectedMode === LoadMode.TIME) {
                this.buildTimeForm()
              } else if (this.selectedMode === LoadMode.RANGE) {
                this.buildRangeForm()
              }
            }
            .padding(16)
          }
          .layoutWeight(1)

          // 底部按钮
          Row({ space: 12 }) {
            if (this.showModeSelection) {
              Button("取消")
                .fontSize(14)
                .fontColor($r("app.color.home_value_text"))
                .backgroundColor($r("app.color.home_card_background"))
                .borderWidth(1)
                .borderColor($r("app.color.home_card_border"))
                .layoutWeight(1)
                .onClick(() => {
                  this.showLoadPanel = false;
                })
            } else {
              Button("返回")
                .fontSize(14)
                .fontColor($r("app.color.home_value_text"))
                .backgroundColor($r("app.color.home_card_background"))
                .borderWidth(1)
                .borderColor($r("app.color.home_card_border"))
                .layoutWeight(1)
                .onClick(() => {
                  this.showModeSelection = true;
                })

              Button(this.isLoading ? "加载中..." : "加载数据")
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor('#2563eb')
                .layoutWeight(1)
                .enabled(!this.isLoading)
                .onClick(() => {
                  this.executeLoad();
                })
            }
          }
          .width('100%')
          .padding(16)
          .borderColor($r("app.color.home_card_border"))
          .borderWidth({ top: 1 })
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .height('80%')
        .constraintSize({ maxHeight: 600 })
        .backgroundColor($r("app.color.home_card_background"))
        .borderRadius(16)
        .shadow({
          radius: 20,
          color: '#3F000000',
          offsetX: 0,
          offsetY: 8
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(999)
        .margin({right:"5%",bottom:"15%"})
      }

      // 2. 悬浮按钮 (仅在面板关闭时显示，或者一直显示看需求)
      if (!this.showLoadPanel) {
        Column() {
          Image($r("app.media.ic_loading"))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor('#2563eb')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .shadow({
          radius: 12,
          color: '#4f2563eb',
          offsetX: 0,
          offsetY: 4
        })
        .onClick(() => {
          this.showLoadPanel = true;
          this.showModeSelection = true;
        })
        // 在这里使用传入的 margin 参数
        .margin({ right: this.rightMargin, bottom: this.bottomMargin })
      }
    }
    // 关键改动：尺寸条件控制。面板打开时占满全屏，关闭时收缩为内容大小。
    .width(this.showLoadPanel ? '100%' : 'auto')
    .height(this.showLoadPanel ? '100%' : 'auto')
  }

  // 模式选择界面
  @Builder
  buildModeSelection() {
    Column({ space: 12 }) {
      this.buildModeOption('📝', '按最近条数加载', '加载最近的N条数据记录', () => {
        this.selectedMode = LoadMode.COUNT;
        this.showModeSelection = false;
      })
      this.buildModeOption('⏱️', '按最近时间加载', '加载最近几分钟/小时/天/月的数据', () => {
        this.selectedMode = LoadMode.TIME;
        this.showModeSelection = false;
      })
      this.buildModeOption('📅', '自定义时间范围', '选择开始和结束时间，精确加载', () => {
        this.selectedMode = LoadMode.RANGE;
        this.showModeSelection = false;
      })
      this.buildModeOption('⚠️', '加载全部数据', '加载数据库中的所有历史数据（可能需要较长时间）', () => {
        this.selectedMode = LoadMode.ALL;
        this.showModeSelection = false;
        this.executeLoad();
      })
    }
  }

  // 模式选项组件
  @Builder
  buildModeOption(icon: string, title: string, desc: string, onClick: () => void) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(icon).fontSize(20)
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.home_value_text"))
      }
      .width('100%')
      Text(desc)
        .fontSize(12)
        .fontColor($r("app.color.home_status_text"))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .borderWidth(1)
    .borderColor($r("app.color.home_card_border"))
    .backgroundColor($r("app.color.home_card_background"))
    .onClick(onClick)
  }

  // 按条数加载表单
  @Builder
  buildCountForm() {
    Column({ space: 16 }) {
      Text("数据条数").fontSize(14).fontColor($r("app.color.home_title_text")).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.loadCount.toString() })
          .type(InputType.Number)
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            const num = parseInt(value);
            if (!isNaN(num) && num > 0) this.loadCount = num;
          })
        Text("条").fontSize(14).fontColor($r("app.color.home_status_text"))
      }
      .width('100%')
    }
  }

  // 按时间段加载表单
  @Builder
  buildTimeForm() {
    Column({ space: 16 }) {
      Text("时间数量").fontSize(14).fontColor($r("app.color.home_title_text")).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.timeValue.toString() })
          .type(InputType.Number)
          .fontSize(14)
          .width(100)
          .onChange((value: string) => {
            const num = parseInt(value);
            if (!isNaN(num) && num > 0) this.timeValue = num;
          })
        Select([
          { value: '分钟', icon: '' },
          { value: '小时', icon: '' },
          { value: '天', icon: '' },
          { value: '月', icon: '' }
        ])
          .selected(1)
          .value(this.getTimeUnitText())
          .layoutWeight(1)
          .onSelect((index: number) => {
            switch (index) {
              case 0: this.timeUnit = TimeUnit.MINUTE; break;
              case 1: this.timeUnit = TimeUnit.HOUR; break;
              case 2: this.timeUnit = TimeUnit.DAY; break;
              case 3: this.timeUnit = TimeUnit.MONTH; break;
            }
          })
      }
      .width('100%')
    }
  }

  // 自定义时间范围表单
  @Builder
  buildRangeForm() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text("开始时间").fontSize(14).fontColor($r("app.color.home_title_text")).width('100%')
        DatePicker({ start: new Date('2020-01-01'), end: new Date(), selected: this.startDate })
          .onDateChange((value: Date) => { this.startDate = value; })
      }
      Column({ space: 8 }) {
        Text("结束时间").fontSize(14).fontColor($r("app.color.home_title_text")).width('100%')
        DatePicker({ start: new Date('2020-01-01'), end: new Date(), selected: this.endDate })
          .onDateChange((value: Date) => { this.endDate = value; })
      }
    }
  }

  private getTimeUnitText(): string {
    switch (this.timeUnit) {
      case TimeUnit.MINUTE: return '分钟';
      case TimeUnit.HOUR: return '小时';
      case TimeUnit.DAY: return '天';
      case TimeUnit.MONTH: return '月';
      default: return '小时';
    }
  }
}