import { router } from "@kit.ArkUI"

@Entry
@Component
export struct DisTemp {
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
            Text('📐温度差值监测')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))

            Text('温度差值显示两个温度传感器之间的温差。')
              .fontSize(14)
              .fontColor($r("app.color.home_title_text"))
              .lineHeight(22)
              .textAlign(TextAlign.JUSTIFY)
          }
          .width('100%')

          this.labelLine('测量意义：', '通过对比两个位置的温度，可以了解环境温度分布的均匀性。', 12)

          this.labelLine('正常范围：', '同一空间内不同位置的温差通常应小于2°C，温差过大说明空调系统分布不均或存在局部热源。', 12)

          this.labelLine('应用场景：', '多点温度监测有助于发现温度死角，优化空调出风口位置，确保整体环境的一致性。', 12)

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
