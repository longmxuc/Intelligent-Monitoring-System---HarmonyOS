import { DevicesPage } from './DevicesPage'; // 假设你有这个文件

@Entry
@ComponentV2
struct Index {
  @Local currentIndex: number = 0;
  @Provider('pageStack') pageStack: NavPathStack = new NavPathStack();

  // 定义主题色，方便后期统一修改
  private readonly selectedColor: string = "#007DFF"; // 选中颜色（华为蓝）
  private readonly normalColor: string = "#999999";   // 未选中颜色（灰色）

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

        // 2. 分析
        TabContent() {
          Text("分析页内容").fontSize(30)
        }
        .tabBar(this.TabBuilder("分析", 1, $r("app.media.ic_analysis")))

        // 3. 消息
        TabContent() {
          Text("消息页内容").fontSize(30)
        }
        .tabBar(this.TabBuilder("消息", 2, $r("app.media.ic_message")))

        // 4. 关于
        TabContent() {
          Text("关于页内容").fontSize(30)
        }
        .tabBar(this.TabBuilder("关于", 3, $r("app.media.ic_about")))
      }
      .backgroundColor($r("app.color.home_background")) // 确保你在 colors.json 定义了这个颜色，或者直接写 "#F1F3F5"
      .barHeight(56) // 稍微加高一点底部栏，更符合现代手势操作
      .scrollable(false) // 建议：通常底部导航禁止左右滑动切换，防止和列表侧滑冲突
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      // 这会让 Tabs 的背景色延伸到顶部的状态栏区域（SYSTEM）和底部的导航条区域
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
    // 扩大点击热区，提升体验
    .hitTestBehavior(HitTestMode.Transparent)
  }
}