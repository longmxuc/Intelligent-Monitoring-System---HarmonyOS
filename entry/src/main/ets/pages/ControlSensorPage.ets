import promptAction from '@ohos.promptAction';
import {
  getSensorState,
  switchSensor,
  setSensorMode,
  MODE_ID_MAP,
  API_MODE_MAP,
  SensorState
} from './ControlSensorPageLogic';

interface ModeItem {
  id: string;
  name: string;
  desc: string;
  icon: ResourceStr;
  color: string; // 模式专属颜色
}

// 传感器信息接口（导出供其他页面使用）
export interface SensorInfo {
  name: string; // 传感器名称
  icon: Resource; // 传感器图标
  iconColor: string; // 图标颜色
  deviceName: string; // 设备名称
  deviceId: string; // 设备ID
}

@ComponentV2
struct ControlSensorPage {
  @Consumer('pageStack') pageStack: NavPathStack = new NavPathStack();
  
  // 接收传递的传感器信息
  @Local sensorInfo: SensorInfo = {
    name: "MQ2 烟雾传感器",
    icon: $r("app.media.ic_sensor_mq2"),
    iconColor: "#FF6B35",
    deviceName: "实验平台",
    deviceId: "D01"
  };

  // 定义主题色
  public readonly selectedColor: string = "#3B82F6"; // 品牌蓝

  // 传感器状态
  @Local sensorState: string = "on"; // "on" | "off"
  @Local currentModeId: string = 'save';
  @Local phaseMessage: string = "自动休眠中";
  @Local nextSwitchTime: string = "距离唤醒 12:46";
  @Local currentModeDisplay: string = "省电模式";
  @Local lastUpdateTime: string = "13:09:29";
  @Local isLoading: boolean = false; // 用户操作加载状态（影响按钮）
  @Local isOnline: boolean = true;

  // 倒计时相关
  private nextSwitchInSec: number = 0; // 后端返回的剩余秒数
  private countdownStartTime: number = 0; // 倒计时开始的时间戳

  // 定时器ID
  private refreshTimer: number | null = null; // 后台状态刷新（30秒一次）
  private countdownTimer: number | null = null; // 倒计时更新（1秒一次）

  // 模式数据源
  private modes: ModeItem[] = [
    { id: 'save', name: '省电模式', desc: '开机5分钟 · 休眠25分钟', icon: $r('app.media.ic_mode_eco'), color: '#10B981' }, // 绿色 - 环保节能
    { id: 'balance', name: '平衡模式', desc: '开机15分钟 · 休眠15分钟', icon: $r('app.media.ic_mode_balance'), color: '#3B82F6' }, // 蓝色 - 平衡稳定
    { id: 'safe', name: '安全模式', desc: '开机25分钟 · 休眠5分钟', icon: $r('app.media.ic_mode_safe'), color: '#F59E0B' }, // 琥珀色 - 安全警示
    { id: 'non_eco', name: '不省电', desc: '持续供电 · 快速响应', icon: $r('app.media.ic_mode_non_eco'), color: '#EF4444' }, // 红色 - 高性能
  ];

  aboutToAppear(): void {
    console.info(`[传感器控制-生命周期] 页面即将显示`);
    // 立即加载一次
    this.loadSensorState();
    
    // 每30秒刷新一次状态（后台轻量级刷新）
    this.refreshTimer = setInterval(() => {
      this.loadSensorState(true); // 传入 true 表示静默刷新
    }, 30000);
    
    // 每1秒更新一次倒计时显示（前端本地计算）
    this.countdownTimer = setInterval(() => {
      this.updateCountdownDisplay();
    }, 1000);
  }

  aboutToDisappear(): void {
    console.info(`[传感器控制-生命周期] 页面即将销毁`);
    // 清除所有定时器
    if (this.refreshTimer !== null) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
    if (this.countdownTimer !== null) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = null;
    }
  }

  // 更新倒计时显示（前端本地计算）
  updateCountdownDisplay(): void {
    if (this.nextSwitchInSec <= 0 || this.countdownStartTime === 0) {
      return;
    }
    
    // 计算已经过去的秒数
    const elapsedSec = Math.floor((Date.now() - this.countdownStartTime) / 1000);
    const remainingSec = Math.max(0, this.nextSwitchInSec - elapsedSec);
    
    if (remainingSec > 0) {
      const minutes = Math.floor(remainingSec / 60);
      const seconds = remainingSec % 60;
      this.nextSwitchTime = `距离切换 ${minutes}:${seconds.toString().padStart(2, '0')}`;
    } else {
      this.nextSwitchTime = "即将切换";
      // 倒计时结束，触发一次刷新
      this.loadSensorState(true);
    }
  }

  // 加载传感器状态
  async loadSensorState(silent: boolean = false): Promise<void> {
    if (!silent) {
      console.info(`[传感器控制-加载] 开始加载状态，传感器: ${this.sensorInfo.name}, 设备: ${this.sensorInfo.deviceId}`);
    }
    
    try {
      // 只有用户操作时才显示加载状态（静默刷新不影响按钮）
      if (!silent) {
        this.isLoading = true;
      }
      
      const state = await getSensorState(this.sensorInfo.name, this.sensorInfo.deviceId);
      
      if (!silent) {
        console.info(`[传感器控制-加载] API返回: ${JSON.stringify(state)}`);
      }
      
      if (state.success) {
        this.sensorState = state.state || "on";
        this.phaseMessage = state.phase_message || "运行中";
        this.currentModeDisplay = state.mode_name || "省电模式";
        
        if (!silent) {
          console.info(`[传感器控制-加载] 状态已更新: state=${this.sensorState}, phase=${this.phaseMessage}, mode=${this.currentModeDisplay}`);
        }
        
        // 更新模式ID
        if (state.mode && API_MODE_MAP[state.mode]) {
          this.currentModeId = API_MODE_MAP[state.mode];
        }
        
        // 更新倒计时（记录后端返回的秒数和当前时间）
        if (state.next_switch_in_sec !== null && state.next_switch_in_sec !== undefined && state.next_switch_in_sec > 0) {
          this.nextSwitchInSec = state.next_switch_in_sec;
          this.countdownStartTime = Date.now(); // 记录倒计时开始时间
          // 立即更新显示
          this.updateCountdownDisplay();
        } else {
          this.nextSwitchTime = "无定时切换";
          this.nextSwitchInSec = 0;
          this.countdownStartTime = 0;
        }
        
        // 更新时间（处理时间戳或ISO格式）
        if (state.updated_at !== null && state.updated_at !== undefined) {
          let date: Date;
          
          if (!silent) {
            console.info(`[传感器控制-加载] 原始 updated_at: ${state.updated_at}, 类型: ${typeof state.updated_at}`);
          }
          
          // 判断是时间戳还是字符串
          if (typeof state.updated_at === 'number') {
            // 如果是数字，判断是秒级还是毫秒级时间戳
            // 秒级时间戳通常是10位数字（< 10000000000）
            // 毫秒级时间戳通常是13位数字（> 10000000000）
            if (state.updated_at < 10000000000) {
              date = new Date(state.updated_at * 1000); // 秒级转毫秒级
              if (!silent) {
                console.info(`[传感器控制-加载] 识别为秒级时间戳，转换后: ${date.toISOString()}`);
              }
            } else {
              date = new Date(state.updated_at); // 毫秒级
              if (!silent) {
                console.info(`[传感器控制-加载] 识别为毫秒级时间戳，转换后: ${date.toISOString()}`);
              }
            }
          } else {
            // 字符串格式（ISO 8601等）
            date = new Date(state.updated_at);
            if (!silent) {
              console.info(`[传感器控制-加载] 识别为字符串格式，转换后: ${date.toISOString()}`);
            }
          }
          
          const timeStr = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
          this.lastUpdateTime = timeStr;
          
          if (!silent) {
            console.info(`[传感器控制-加载] 最近操作时间已更新: ${timeStr}`);
          }
        } else {
          if (!silent) {
            console.warn(`[传感器控制-加载] updated_at 为空`);
          }
        }
      } else {
        if (!silent) {
          console.error(`[传感器控制-加载] 加载失败: ${state.error}`);
          promptAction.showToast({
            message: `加载状态失败: ${state.error}`,
            duration: 2000
          });
        }
      }
    } catch (err) {
      if (!silent) {
        console.error(`[传感器控制-加载] 异常: ${JSON.stringify(err)}`);
        promptAction.showToast({
          message: '加载状态失败',
          duration: 2000
        });
      }
    } finally {
      if (!silent) {
        this.isLoading = false;
        console.info(`[传感器控制-加载] 加载完成`);
      }
    }
  }

  // 开启传感器
  async turnOnSensor(): Promise<void> {
    console.info(`[传感器控制-UI] 开启按钮被点击，传感器: ${this.sensorInfo.name}, 设备: ${this.sensorInfo.deviceId}`);
    
    if (this.isLoading) {
      console.warn(`[传感器控制-UI] 正在加载中，忽略点击`);
      return;
    }
    
    try {
      this.isLoading = true;
      console.info(`[传感器控制-UI] 开始调用开启API...`);
      const result = await switchSensor(this.sensorInfo.name, this.sensorInfo.deviceId, 'on');
      
      console.info(`[传感器控制-UI] API返回结果: ${JSON.stringify(result)}`);
      
      if (result.success) {
        promptAction.showToast({
          message: '开启成功',
          duration: 2000
        });
        
        // 立即刷新一次状态（获取中间状态，如"手动开启，等待调度"）
        console.info(`[传感器控制-UI] 立即刷新状态...`);
        await this.loadSensorState(false);
        
        // 延迟1.5秒后再刷新一次（获取最终状态）
        setTimeout(() => {
          console.info(`[传感器控制-UI] 延迟刷新状态...`);
          this.loadSensorState(true); // 静默刷新，不影响按钮
        }, 1500);
      } else {
        promptAction.showToast({
          message: `开启失败: ${result.error}`,
          duration: 2000
        });
      }
    } catch (err) {
      console.error(`[传感器控制-UI] 开启失败: ${JSON.stringify(err)}`);
      promptAction.showToast({
        message: '开启失败',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  // 关闭传感器
  async turnOffSensor(): Promise<void> {
    console.info(`[传感器控制-UI] 关闭按钮被点击，传感器: ${this.sensorInfo.name}, 设备: ${this.sensorInfo.deviceId}`);
    
    if (this.isLoading) {
      console.warn(`[传感器控制-UI] 正在加载中，忽略点击`);
      return;
    }
    
    try {
      this.isLoading = true;
      console.info(`[传感器控制-UI] 开始调用关闭API...`);
      const result = await switchSensor(this.sensorInfo.name, this.sensorInfo.deviceId, 'off');
      
      console.info(`[传感器控制-UI] API返回结果: ${JSON.stringify(result)}`);
      
      if (result.success) {
        promptAction.showToast({
          message: '关闭成功',
          duration: 2000
        });
        
        // 立即刷新一次状态（获取中间状态，如"手动关闭，等待调度"）
        console.info(`[传感器控制-UI] 立即刷新状态...`);
        await this.loadSensorState(false);
        
        // 延迟1.5秒后再刷新一次（获取最终状态）
        setTimeout(() => {
          console.info(`[传感器控制-UI] 延迟刷新状态...`);
          this.loadSensorState(true); // 静默刷新，不影响按钮
        }, 1500);
      } else {
        promptAction.showToast({
          message: `关闭失败: ${result.error}`,
          duration: 2000
        });
      }
    } catch (err) {
      console.error(`[传感器控制-UI] 关闭失败: ${JSON.stringify(err)}`);
      promptAction.showToast({
        message: '关闭失败',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  // 切换模式
  async changeMode(modeId: string): Promise<void> {
    // BLE 和 OLED 不支持模式切换
    if (this.sensorInfo.name.includes('BLE') || this.sensorInfo.name.includes('OLED')) {
      return;
    }
    
    if (this.isLoading || modeId === this.currentModeId) return;
    
    try {
      this.isLoading = true;
      const apiMode = MODE_ID_MAP[modeId];
      
      if (!apiMode) {
        promptAction.showToast({
          message: '无效的模式',
          duration: 2000
        });
        return;
      }
      
      const result = await setSensorMode(this.sensorInfo.name, this.sensorInfo.deviceId, apiMode);
      
      if (result.success) {
        this.currentModeId = modeId;
        promptAction.showToast({
          message: '模式切换成功',
          duration: 2000
        });
        
        // 立即刷新一次状态（获取中间状态）
        console.info(`[传感器控制-模式] 立即刷新状态...`);
        await this.loadSensorState(false);
        
        // 延迟1.5秒后再刷新一次（获取最终状态）
        setTimeout(() => {
          console.info(`[传感器控制-模式] 延迟刷新状态...`);
          this.loadSensorState(true); // 静默刷新，不影响按钮
        }, 1500);
      } else {
        promptAction.showToast({
          message: `模式切换失败: ${result.error}`,
          duration: 2000
        });
      }
    } catch (err) {
      console.error(`[传感器控制] 模式切换失败: ${JSON.stringify(err)}`);
      promptAction.showToast({
        message: '模式切换失败',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  // 判断是否支持模式切换（BLE和OLED不支持）
  supportsModeSwitch(): boolean {
    return !this.sensorInfo.name.includes('BLE') && !this.sensorInfo.name.includes('OLED');
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // --- 顶部大卡片 ---
            Column() {
              // 顶部 Icon 和 设备标签
              Row() {
                Row() {
                  Image(this.sensorInfo.icon)
                    .width("60%")
                    .fillColor(this.sensorInfo.iconColor) // 动态传感器颜色
                }
                .justifyContent(FlexAlign.Center)
                .width(50)
                .height(50)
                .backgroundColor($r("app.color.home_card_background"))
                .borderRadius(16)
                .shadow({ radius: 20, color: $r("app.color.card_shadow"), offsetY: 4 })

                // 显示设备名称标签
                Row({ space: 6 }) {
                  Circle({ width: 6, height: 6 }).fill(Color.Green)
                  Text(this.sensorInfo.deviceName)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.selectedColor)
                }
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(20)
                .backgroundColor($r("app.color.home_card_background"))
                .border({ width: 1, color: $r("app.color.home_card_border") })
              }
              .width("100%")
              .justifyContent(FlexAlign.SpaceBetween)

              // 中间状态文字
              Column() {
                Text("当前状态")
                  .fontSize(12)
                  .fontColor($r("app.color.home_subtitle_text"))
                  .fontWeight(FontWeight.Medium)
                  .margin({ bottom: 4 })
                Text(this.phaseMessage)
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r("app.color.home_value_text"))
                  .margin({ bottom: 12 })

                // 倒计时（仅对支持模式的传感器显示）
                if (this.supportsModeSwitch()) {
                  Row({ space: 4 }) {
                    Image($r('app.media.ic_public_clock'))
                      .width(14)
                      .height(14)
                    Text(this.nextSwitchTime)
                      .fontSize(12)
                      .fontColor(this.selectedColor)
                      .fontWeight(FontWeight.Medium)
                  }
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r("app.color.control_device_select_bg"))
                  .borderRadius(8)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .width("100%")
              .margin({ top: 20, bottom: 25 })

              // 底部数据网格
              Row({ space: 10 }) {
                // 当前模式
                Column() {
                  Text("当前模式")
                    .fontSize(10)
                    .fontColor($r("app.color.home_title_text"))
                    .margin({ bottom: 4 })
                  Text(this.currentModeDisplay)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r("app.color.home_value_text"))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .padding(12)
                .backgroundColor($r("app.color.home_card_background"))
                .borderRadius(12)

                // 最近操作
                Column() {
                  Text("最近操作")
                    .fontSize(10)
                    .fontColor($r("app.color.home_title_text"))
                    .margin({ bottom: 4 })
                  Text(this.lastUpdateTime)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r("app.color.home_value_text"))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .padding(12)
                .backgroundColor($r("app.color.home_card_background"))
                .borderRadius(12)
              }
              .width("100%")
            }
            .padding(24)
            .width("100%")
            .backgroundColor($r("app.color.control_device_select_bg"))
            .borderRadius(32)
            .border({ width: 1, color: $r("app.color.home_card_border") })
            .shadow({ 
              radius: 12, 
              color: $r("app.color.card_shadow"), 
              offsetX: 0, 
              offsetY: 4 
            })

            // --- 运行模式标题（仅对支持模式的传感器显示） ---
            if (this.supportsModeSwitch()) {
              Text("运行模式")
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r("app.color.home_title_text"))
                .width("100%")
                .margin({ top: 30, bottom: 15, left: 5 })

              // --- 模式选择列表 ---
              Column({ space: 12 }) {
                ForEach(this.modes, (item: ModeItem) => {
                // 判断当前是否选中
                // 选中：使用模式专属颜色背景，白色图标和文字
                // 未选中：白色背景，使用模式专属颜色的图标
                Row() {
                  // 左侧图标
                  Row() {
                    if (this.currentModeId === item.id) {
                      // 选中时图标变白色
                      Image(item.icon)
                        .width(24)
                        .height(24)
                        .fillColor(Color.White)
                    } else {
                      // 非选中时不使用fillColor，保持图标原色
                      Image(item.icon)
                        .width(24)
                        .height(24)
                    }
                  }
                  .width(48)
                  .height(48)
                  .justifyContent(FlexAlign.Center)
                  // 选中时半透明白色背景，未选中时浅色背景
                  .backgroundColor(this.currentModeId === item.id ? "rgba(255,255,255,0.2)" : $r("app.color.control_icon_bg"))
                  .borderRadius(24)
                  .margin({ right: 15 })

                  // 中间文字
                  Column() {
                    Text(item.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      // 选中变白，未选中使用主题文字颜色
                      .fontColor(this.currentModeId === item.id ? Color.White : $r("app.color.home_value_text"))
                      .margin({ bottom: 4 })
                    Text(item.desc)
                      .fontSize(12)
                      // 选中变半透明白，未选中使用副标题颜色
                      .fontColor(this.currentModeId === item.id ? "rgba(255,255,255,0.85)" : $r("app.color.home_title_text"))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width("100%")
                .padding(16)
                // 背景色逻辑：选中时使用模式专属颜色，未选中用卡片背景色
                .backgroundColor(this.currentModeId === item.id ? item.color : $r("app.color.home_card_background"))
                .borderRadius(16)
                // 边框逻辑：选中时使用模式颜色，未选中用卡片边框色
                .border({
                  width: 1.5,
                  color: this.currentModeId === item.id ? item.color : $r("app.color.home_card_border")
                })
                // 阴影：选中时使用对应颜色的阴影
                .shadow(this.currentModeId === item.id ? { 
                  radius: 15, 
                  color: `${item.color}4D`, // 30% 透明度
                  offsetY: 8 
                } : { radius: 0 })
                .animation({ duration: 250, curve: Curve.FastOutSlowIn })
                .onClick(() => {
                  this.changeMode(item.id);
                })
                })
              }
              .margin({ bottom: 100 })
            }
          }
          .padding({ left: 20, right: 20, top: 10 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // --- 底部固定操作栏 ---
        Column() {
          Text("远程指令")
            .fontSize(12)
            .fontColor($r("app.color.home_title_text"))
            .fontWeight(FontWeight.Bold)
            .width("100%")
            .margin({ bottom: 12 })

          Row({ space: 15 }) {
            Button(this.isLoading ? "处理中..." : "关闭传感器")
              .layoutWeight(1)
              .height(56)
              .backgroundColor($r("app.color.control_icon_bg"))
              .fontColor($r("app.color.home_title_text"))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .borderRadius(16)
              .enabled(!this.isLoading)
              .onClick(() => {
                console.info(`[传感器控制-UI] "关闭"按钮被点击`);
                this.turnOffSensor();
              })

            Button(this.isLoading ? "处理中..." : "开启传感器")
              .layoutWeight(1)
              .height(56)
              .backgroundColor(this.selectedColor)
              .fontColor(Color.White)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .borderRadius(16)
              .shadow({ radius: 20, color: $r("app.color.card_shadow"), offsetY: 5 })
              .enabled(!this.isLoading)
              .onClick(() => {
                console.info(`[传感器控制-UI] "开启"按钮被点击`);
                this.turnOnSensor();
              })
          }
        }
        .padding({ left: 20, right: 20, top: 20, bottom: 30 })
        .backgroundColor($r("app.color.home_card_background"))
        .borderRadius({ topLeft: 24, topRight: 24 })
        .shadow({ radius: 40, color: $r("app.color.card_shadow"), offsetY: -5 })
      }
      .height("100%")
      .backgroundColor($r("app.color.home_background"))
    }
    .title(`${this.sensorInfo.name} 控制`)
    .onReady((context: NavDestinationContext) => {
      // 接收导航传递的参数
      const param = context.pathInfo.param as Record<string, Object>;
      if (param && param.sensorInfo) {
        this.sensorInfo = param.sensorInfo as SensorInfo;
      }
      // 加载传感器状态
      this.loadSensorState();
    })
  }

  @Builder InfoGridItem(title: string, value: string) {
    Column() {
      Text(title)
        .fontSize(10)
        .fontColor($r("app.color.home_title_text"))
        .margin({ bottom: 4 })
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r("app.color.home_value_text"))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(12)
    .backgroundColor($r("app.color.home_card_background"))
    .borderRadius(12)
  }
}

@Builder
export function ControlSensorPageBuilder() {
  ControlSensorPage()
}