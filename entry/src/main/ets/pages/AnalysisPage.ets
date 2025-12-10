import { SensorData, SERVER_HOST } from './DeviceDetailPageLogic';
import { DeviceInfo } from './DevicesPageLogic';
import { AnalysisDataLoadComponent } from './AnalysisDataLoadComponent';
import http from '@ohos.net.http';
import promptAction from '@ohos.promptAction';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';

@ComponentV2
export struct AnalysisPage {
  @Consumer('pageStack') pageStack: NavPathStack = new NavPathStack();
  @Local currentData: SensorData[] = [];
  @Local selectedDeviceId: string | null = null; // null表示全部设备
  @Local deviceList: DeviceInfo[] = [];
  @Local isLoadingDevices: boolean = false;
  @Local hasData: boolean = false;
  @Local shouldBounce: boolean = false; // 控制弹跳动画
  
  // WebView 控制器
  private webviewController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.loadDeviceList();
  }
  
  // 更新 WebView 中的数据
  private updateWebViewData(): void {
    try {
      const message = JSON.stringify({
        type: 'updateData',
        sensorData: this.currentData,
        selectedDeviceId: this.selectedDeviceId,
        deviceList: this.deviceList
      });
      this.webviewController.runJavaScript(`
        window.postMessage(${message}, '*');
      `);
      console.info('已更新 WebView 数据');
    } catch (err) {
      console.error('更新 WebView 数据失败:', JSON.stringify(err));
    }
  }
  
  // 更新 WebView 主题（通过 JavaScript 检测系统主题）
  private updateWebViewTheme(): void {
    try {
      // 通过 JavaScript 的 matchMedia API 检测系统主题
      this.webviewController.runJavaScript(`
        (function() {
          const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
          const theme = isDark ? 'dark' : 'light';
          if (document.documentElement) {
            document.documentElement.setAttribute('data-theme', theme);
            console.log('[AI助手] 主题已设置为: ' + theme);
          }
        })();
      `);
    } catch (err) {
      console.error('[AI助手主题] 设置失败:', JSON.stringify(err));
    }
  }
  
  // 代理 AI 请求（避免 CORS）
  private async proxyAIRequest(requestBody: string): Promise<void> {
    try {
      console.info('鸿蒙端代理 AI 请求');
      
      const httpRequest: http.HttpRequest = http.createHttp();
      const url = `https://${SERVER_HOST}/api/ai/chat`;
      
      // 监听响应数据（流式响应）
      let fullResponse = '';
      let isFirstChunk = true;
      let lineBuffer = '';
      
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const decoder = new util.TextDecoder('utf-8', { fatal: false, ignoreBOM: true });
        const chunk = decoder.decodeWithStream(new Uint8Array(data), { stream: true });
        
        console.info('[AI] 收到数据块，长度:', chunk.length);
        
        // 添加到行缓冲区
        lineBuffer += chunk;
        
        // 处理SSE格式：按行分割
        const lines = lineBuffer.split('\n');
        // 保留最后一个可能不完整的行
        lineBuffer = lines.pop() || '';
        
        for (const line of lines) {
          const trimmedLine = line.trim();
          
          if (trimmedLine.startsWith('data: ')) {
            const dataStr = trimmedLine.substring(6).trim();
            
            if (dataStr === '[DONE]') {
              // 流式传输完成
              console.info('[AI] 流式传输完成');
              this.webviewController.runJavaScript(`
                window.handleAIStreamEnd();
              `);
              continue;
            }
            
            if (!dataStr) {
              continue;
            }
            
            try {
              const json = JSON.parse(dataStr) as Record<string, ESObject>;
              const choices = json['choices'] as Array<Record<string, ESObject>>;
              
              if (!choices || choices.length === 0) {
                continue;
              }
              
              const firstChoice = choices[0];
              const delta = firstChoice?.['delta'] as Record<string, ESObject>;
              const message = firstChoice?.['message'] as Record<string, ESObject>;
              const content = (delta?.['content'] || message?.['content'] || '') as string;
              const reasoningContent = (delta?.['reasoning_content'] || message?.['reasoning_content'] || '') as string;
              
              // 发送到 WebView
              if (isFirstChunk && (content || reasoningContent)) {
                isFirstChunk = false;
                console.info('[AI] 开始流式传输');
                this.webviewController.runJavaScript(`
                  window.handleAIStreamStart();
                `);
              }
              
              // 处理思考过程
              if (reasoningContent) {
                fullResponse += reasoningContent;
                
                const escapedThinking = reasoningContent
                  .replace(/\\/g, '\\\\')
                  .replace(/'/g, "\\'")
                  .replace(/\n/g, '\\n')
                  .replace(/\r/g, '\\r')
                  .replace(/\t/g, '\\t');
                
                this.webviewController.runJavaScript(`
                  window.handleAIStreamChunk('${escapedThinking}', true);
                `);
              }
              
              // 处理正常内容
              if (content) {
                fullResponse += content;
                
                const escapedContent = content
                  .replace(/\\/g, '\\\\')
                  .replace(/'/g, "\\'")
                  .replace(/\n/g, '\\n')
                  .replace(/\r/g, '\\r')
                  .replace(/\t/g, '\\t');
                
                this.webviewController.runJavaScript(`
                  window.handleAIStreamChunk('${escapedContent}', false);
                `);
              }
            } catch (e) {
              console.error('[AI] 解析JSON失败:', JSON.stringify(e), '数据:', dataStr.substring(0, 100));
            }
          }
        }
      });
      
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: requestBody,
        connectTimeout: 60000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.STRING
      });
      
      console.info('AI 响应状态:', response?.responseCode);
      
      if (response && response.responseCode === 200) {
        console.info('[AI] 请求成功完成');
        
        // 如果没有通过流式接收到数据，检查是否有完整响应
        if (!fullResponse && response.result) {
          const result = response.result as string;
          console.info('[AI] 收到完整响应，长度:', result.length);
          
          // 检查是否是流式格式（SSE）
          if (result.includes('data: ')) {
            console.info('[AI] 检测到SSE格式，但未通过dataReceive处理，尝试手动解析');
            // 手动处理SSE格式
            const lines = result.split('\n');
            let combinedContent = '';
            
            for (const line of lines) {
              if (line.trim().startsWith('data: ')) {
                const dataStr = line.trim().substring(6).trim();
                if (dataStr && dataStr !== '[DONE]') {
                  try {
                    const json = JSON.parse(dataStr) as Record<string, ESObject>;
                    const choices = json['choices'] as Array<Record<string, ESObject>>;
                    const delta = choices?.[0]?.['delta'] as Record<string, ESObject>;
                    const message = choices?.[0]?.['message'] as Record<string, ESObject>;
                    const content = (delta?.['content'] || message?.['content'] || '') as string;
                    if (content) {
                      combinedContent += content;
                    }
                  } catch (e) {
                    // 忽略解析错误
                  }
                }
              }
            }
            
            if (combinedContent) {
              const escapedContent = combinedContent
                .replace(/\\/g, '\\\\')
                .replace(/'/g, "\\'")
                .replace(/\n/g, '\\n')
                .replace(/\r/g, '\\r')
                .replace(/\t/g, '\\t');
              
              this.webviewController.runJavaScript(`
                window.handleAIResponse('${escapedContent}');
              `);
            }
          } else {
            // 尝试作为普通JSON解析
            try {
              const json = JSON.parse(result) as Record<string, ESObject>;
              const choices = json['choices'] as Array<Record<string, ESObject>>;
              const message = choices?.[0]?.['message'] as Record<string, ESObject>;
              const content = (message?.['content'] || '') as string;
              
              if (content) {
                const escapedContent = content
                  .replace(/\\/g, '\\\\')
                  .replace(/'/g, "\\'")
                  .replace(/\n/g, '\\n')
                  .replace(/\r/g, '\\r')
                  .replace(/\t/g, '\\t');
                
                this.webviewController.runJavaScript(`
                  window.handleAIResponse('${escapedContent}');
                `);
              } else {
                console.error('[AI] 未找到有效内容');
                this.webviewController.runJavaScript(`
                  window.handleAIError('AI返回的内容为空');
                `);
              }
            } catch (e) {
              console.error('[AI] 解析响应失败:', JSON.stringify(e));
              console.error('[AI] 响应前100字符:', result.substring(0, 100));
              this.webviewController.runJavaScript(`
                window.handleAIError('解析响应失败，请重试');
              `);
            }
          }
        } else if (fullResponse) {
          console.info('[AI] 已通过流式接收完成，总长度:', fullResponse.length);
        }
      } else {
        const errorMsg = `请求失败: ${response?.responseCode}`;
        this.webviewController.runJavaScript(`
          window.handleAIError('${errorMsg}');
        `);
      }
      
      httpRequest.destroy();
    } catch (err) {
      console.error('代理 AI 请求失败:', JSON.stringify(err));
      let errorMsg = '请求失败';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      }
      this.webviewController.runJavaScript(`
        window.handleAIError('${errorMsg}');
      `);
    }
  }

  // 加载设备列表
  private async loadDeviceList(): Promise<void> {
    this.isLoadingDevices = true;
    try {
      const httpRequest: http.HttpRequest = http.createHttp();
      const url = `http://${SERVER_HOST}/api/devices`;

      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        }
      });

      httpRequest.destroy();

      if (response && response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as Record<string, Object>;

        if (result['success'] === true && result['devices']) {
          const devices = result['devices'] as Array<Record<string, Object>>;
          this.deviceList = devices.map((item: Record<string, Object>) => {
            const id = item['id'] || item['device_id'] || '';
            return {
              id: String(id).trim().toUpperCase(),
              name: item['name'] as string | undefined,
              device_id: String(id).trim().toUpperCase(),
              description: item['description'] as string | undefined,
              has_ble: item['has_ble'] as boolean | undefined,
              has_mqtt: item['has_mqtt'] as boolean | undefined,
              via: item['via'] as string[] | undefined,
              online: item['online'] as boolean | undefined
            } as DeviceInfo;
          });
          console.info(`成功加载 ${this.deviceList.length} 个设备`);
        }
      }
    } catch (err) {
      console.error('加载设备列表失败:', JSON.stringify(err));
      try {
        promptAction.showToast({ message: '加载设备列表失败', duration: 2000 });
      } catch (e) {
        console.error('显示Toast失败:', JSON.stringify(e));
      }
    } finally {
      this.isLoadingDevices = false;
    }
  }

  // 处理数据加载完成
  private onDataLoaded(data: SensorData[], count: number): void {
    this.currentData = data;
    this.hasData = data.length > 0;
    console.info(`分析页：成功加载 ${count} 条数据`);
    
    // 更新 WebView 中的数据
    if (this.hasData) {
      setTimeout(() => {
        this.updateWebViewData();
      }, 500);
    }
  }

  // 处理设备选择变化
  private onDeviceChanged(deviceId: string | null): void {
    this.selectedDeviceId = deviceId;
    // 切换设备时清空当前数据
    this.currentData = [];
    this.hasData = false;
    
    // 更新 WebView
    this.updateWebViewData();
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // 数据加载区域
          Column({ space: 12 }) {
            Text('🔍 数据加载')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))
              .width('100%')

            Text('选择数据加载方式，支持按条数、按时间范围、自定义时间或加载全部数据。')
              .fontSize(13)
              .fontColor($r("app.color.home_status_text"))
              .width('100%')
              .margin({ bottom: 8 })

            // 数据加载组件（支持设备选择）
            AnalysisDataLoadComponent({
              deviceList: this.deviceList,
              selectedDeviceId: this.selectedDeviceId,
              shouldBounce: this.shouldBounce,
              onDeviceChanged: (deviceId: string | null) => {
                this.onDeviceChanged(deviceId);
              },
              onDataLoaded: (data: SensorData[], count: number) => {
                this.onDataLoaded(data, count);
              }
            })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r("app.color.home_card_background"))
          .borderRadius(12)
          .border({
            width: 1,
            color: $r("app.color.home_card_border"),
            style: BorderStyle.Solid
          })
          .shadow({
            radius: 8,
            color: '#1F000000',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ left: 16, right: 16, top: 8 })

          // AI 分析助手（使用 WebView）
          Web({ src: $rawfile('ai_chat.html'), controller: this.webviewController })
            .width('100%')
            .height(600)
            .borderRadius(12)
            .margin({ left: 16, right: 16 })
            .backgroundColor($r("app.color.home_background"))
            .clip(true) // 裁剪边界，确保圆角生效
            .darkMode(WebDarkMode.Auto) // 自动跟随系统主题
            .onControllerAttached(() => {
              console.info('WebView 控制器已附加');
              // WebView 加载完成后，立即更新数据和主题
              setTimeout(() => {
                this.updateWebViewData();
                this.updateWebViewTheme();
              }, 1000);
            })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .mixedMode(MixedMode.All)
            .cacheMode(CacheMode.None)
            .onlineImageAccess(true)
            .imageAccess(true)
            .blockNetwork(false)
            .onSslErrorEventReceive((event) => {
              // 允许 HTTP 请求（忽略 SSL 错误）
              console.warn('WebView SSL 错误，继续加载');
              event.handler.handleConfirm();
            })
            .onErrorReceive((event) => {
              console.error('WebView 错误:', JSON.stringify(event));
              if (event?.error) {
                console.error('错误详情:', event.error.getErrorInfo());
              }
            })
            .onPageEnd(() => {
              console.info('WebView 页面加载完成');
              // 页面加载完成后，更新数据和主题
              setTimeout(() => {
                this.updateWebViewData();
                this.updateWebViewTheme();
              }, 500);
            })
            .onConsole((event) => {
              // 转发 WebView 的 console 日志
              const msg = event?.message.getMessage();
              console.info('[WebView Console]', msg);
              
              // 拦截 AI 请求调用
              if (msg && msg.includes('[AI_REQUEST]')) {
                try {
                  const jsonStr = msg.substring(msg.indexOf('{'));
                  this.proxyAIRequest(jsonStr);
                } catch (e) {
                  console.error('解析 AI 请求失败:', e);
                }
              }
              
              // 拦截需要加载数据的提示
              if (msg && msg.includes('[NEED_LOAD_DATA]')) {
                try {
                  promptAction.showToast({ 
                    message: '⚠️ 请先加载传感器数据', 
                    duration: 2500,
                    bottom: 200
                  });
                  
                  // 触发弹跳动画
                  this.shouldBounce = true;
                  setTimeout(() => {
                    this.shouldBounce = false;
                  }, 1000);
                } catch (e) {
                  console.error('显示Toast失败:', e);
                }
              }
              
              return false;
            })
            .onHttpErrorReceive((event) => {
              console.error('[WebView HTTP错误]', JSON.stringify({
                url: event?.request.getRequestUrl(),
                statusCode: event?.response.getResponseCode()
              }));
            })

          // 底部空白，避免被浮动按钮遮挡
          Blank()
            .height(100)
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding({left:10,right:10})
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.home_background"))
  }
}

