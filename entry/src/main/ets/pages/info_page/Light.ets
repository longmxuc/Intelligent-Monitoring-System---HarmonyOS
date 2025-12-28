import { router } from "@kit.ArkUI"

@Entry
@Component
export struct Light {

  @Builder
  labelLine(title: string, content: string, topMargin: number) {
    Text() {
      Span(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r("app.color.show_realtime_data"))
      Span(content)
        .fontSize(14)
        .fontColor($r("app.color.home_title_text"))
    }
    .lineHeight(22)
    .textAlign(TextAlign.JUSTIFY)
    .margin({ top: topMargin })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Text('💡亮度监测')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))
            Text('亮度（照度）反映环境的光照强度，单位为勒克斯（lx）。')
              .fontSize(14)
              .fontColor($r("app.color.home_title_text"))
              .lineHeight(22)
              .textAlign(TextAlign.JUSTIFY)
          }
          .width('100%')

          this.labelLine('适宜范围：', '普通工作区域照度应达到 300-750 lx，精密操作区域需要 750-1500 lx。', 12)

          this.labelLine('为什么重要：', '充足的照明可以减少操作失误，提高工作效率；某些场景需要严格控制光照条件。', 12)

          this.labelLine('监测意义：', '实时监测光照强度，可以自动调整照明系统，节约能耗并提高舒适度。', 12)

          this.labelLine('另一数据源：', '系统还支持外接光照传感器，用于比对不同位置的光照差异，帮助优化灯光布局。', 12)

          Button('知道了')
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r("app.color.show_realtime_data"))
            .borderRadius(12)
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Center)
            .onClick(() => {
              router.back()
            })
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r("app.color.home_card_background"))
        .borderRadius(20)
        .borderColor($r("app.color.home_card_border"))
        .borderWidth(1)
        .shadow({ radius: 10, color: $r("app.color.card_shadow"), offsetY: 4 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: 16, left: 16, right: 16, bottom: 24 })
    .backgroundColor($r("app.color.home_background"))
  }
}
