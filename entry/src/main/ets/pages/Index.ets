import { DevicesPage } from './DevicesPage';
import { AnalysisPage } from './AnalysisPage';
import { webview } from '@kit.ArkWeb';
import { ControlPage } from './ControlPage';

@Entry
@ComponentV2
struct Index {
  @Local currentIndex: number = 0;
  @Local showWebAnalysis: boolean = false; // 是否在分析Tab中显示Web版本
  @Provider('pageStack') pageStack: NavPathStack = new NavPathStack();

  // 定义主题色，方便后期统一修改
  public readonly selectedColor: string = "#007DFF"; // 选中颜色（华为蓝）
  public readonly normalColor: string = "#999999";   // 未选中颜色（灰色）
  
  // 双击检测
  private lastClickTime: number = 0;
  private lastClickIndex: number = -1;
  private readonly DOUBLE_CLICK_INTERVAL: number = 500; // 500ms内算双击
  
  // WebView 控制器
  private webViewController: webview.WebviewController = new webview.WebviewController();
  
  aboutToAppear(): void {
    // 页面加载时更新主题
    this.updateWebViewTheme();
  }

  build() {
    Navigation(this.pageStack) {
      Tabs({
        index: this.currentIndex,
        barPosition: BarPosition.End
      }) {
        // 1. 首页
        TabContent() {
          DevicesPage()
        }
        .tabBar(this.TabBuilder("首页", 0, $r("app.media.ic_home")))

        // 2. 控制
        TabContent() {
          ControlPage()
        }
        .tabBar(this.TabBuilder("控制", 1, $r("app.media.ic_control")))

        // 3. 分析
        TabContent() {
          if (this.showWebAnalysis) {
            this.buildWebAnalysisPage()
          } else {
            AnalysisPage()
          }
        }
        .tabBar(this.TabBuilder("AI·分析", 2, $r("app.media.ic_analysis")))

        // 4. 消息
        TabContent() {
          Text("消息页内容").fontSize(30)
        }
        .tabBar(this.TabBuilder("消息", 3, $r("app.media.ic_message")))

        // 5. 关于
        TabContent() {
          Text("关于页内容").fontSize(30)
        }
        .tabBar(this.TabBuilder("关于", 4, $r("app.media.ic_about")))
      }
      .backgroundColor($r("app.color.home_background"))
      .barHeight(56)
      .animationDuration(300) // 恢复切换动画
      .onChange((index: number) => {
        this.currentIndex = index;
        // 切换到其他Tab时，自动回到原生分析页
        // if (index !== 2 && this.showWebAnalysis) {
        //   this.showWebAnalysis = false;
        // }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 处理Tab点击
  private handleTabClick(targetIndex: number): void {
    console.info(`[Tab点击] 索引: ${targetIndex}`);
    const currentTime = Date.now();
    
    // 检测双击分析按钮（索引为1）
    if (targetIndex === 2) {
      console.info(`[分析Tab] 上次点击: ${this.lastClickIndex}, 时间间隔: ${currentTime - this.lastClickTime}ms`);
      
      if (this.lastClickIndex === 2 &&
          this.currentIndex === 2 && // 必须已经在分析页
          (currentTime - this.lastClickTime) < this.DOUBLE_CLICK_INTERVAL) {
        // 双击了分析按钮，切换到Web版
        console.info('[双击检测] 触发双击，切换到Web版数据分析');
        this.showWebAnalysis = true;
        // 重置计时器，避免连续触发
        this.lastClickTime = 0;
        this.lastClickIndex = -1;
        return;
      }
    }
    
    // 更新点击记录
    this.lastClickTime = currentTime;
    this.lastClickIndex = targetIndex;
    
    // 切换到目标Tab
    this.currentIndex = targetIndex;
  }
  
  // 更新WebView主题（通过 JavaScript 检测系统主题）
  private updateWebViewTheme(): void {
    try {
      // 通过 JavaScript 的 matchMedia API 检测系统主题
      this.webViewController.runJavaScript(`
        (function() {
          const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
          const theme = isDark ? 'dark' : 'light';
          if (document.documentElement) {
            document.documentElement.setAttribute('data-theme', theme);
            console.log('[Web分析页] 主题已设置为: ' + theme);
          }
        })();
      `);
    } catch (e) {
      console.info('[主题] WebView尚未加载，等待onPageEnd后设置');
    }
  }
  
  // 构建Web版分析页
  @Builder
  buildWebAnalysisPage() {
    Column() {
      // 顶部提示栏
      Row() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Image($r('sys.symbol.chevron_left'))
              .fillColor('#2563eb')
              .width(18)
              .height(18)
            Text('返回原生版')
              .fontSize(14)
              .fontColor('#2563eb')
          }
        }
        .backgroundColor('transparent')
        .onClick(() => {
          this.showWebAnalysis = false;
        })

        Blank()
        
        Text('🌐 Web版数据分析')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ right: 16 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r("app.color.home_background"))
      .borderWidth({ bottom: 1 })
      .borderColor($r("app.color.home_background"))

      // WebView
      Web({ src: 'https://znhj.iepose.cn/analysis.html', controller: this.webViewController })
        .layoutWeight(1)
        .width('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .darkMode(WebDarkMode.Auto) // 自动跟随系统主题
        .onPageBegin(() => {
          console.info('[Web分析页] 开始加载');
        })
        .onPageEnd(() => {
          console.info('[Web分析页] 加载完成');
          // 页面加载完成后设置主题
          this.updateWebViewTheme();
        })
        .onErrorReceive((event) => {
          console.error('[Web分析页] 加载错误:', JSON.stringify(event));
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  // 自定义 TabBar 构建器
  @Builder
  TabBuilder(title: string, targetIndex: number, iconResource: Resource) {
    Column() {
      Image(iconResource)
        .size({ width: 24, height: 24 })
        .objectFit(ImageFit.Contain)
        // 【关键点】这里使用 fillColor 动态改变 SVG 的颜色
        .fillColor(this.currentIndex === targetIndex ? this.selectedColor : this.normalColor)
        // 添加一个简单的缩放动画效果（可选）
        .scale({
          x: this.currentIndex === targetIndex ? 1.1 : 1.0,
          y: this.currentIndex === targetIndex ? 1.1 : 1.0
        })
        .animation({ duration: 200 })

      Text(title)
        .fontSize(10)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === targetIndex ? this.selectedColor : this.normalColor)
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%') // 填满 TabBar 的高度
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // 处理Tab点击
      this.handleTabClick(targetIndex);
    })
  }
}