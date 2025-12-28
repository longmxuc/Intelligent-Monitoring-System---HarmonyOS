import { router } from "@kit.ArkUI"

@Entry
@Component
export struct Wet {
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
            Text('💧湿度监测')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))

            Text('湿度反映空气中水蒸气的含量，对环境舒适度至关重要。')
              .fontSize(14)
              .fontColor($r("app.color.home_title_text"))
              .lineHeight(22)
              .textAlign(TextAlign.JUSTIFY)
          }
          .width('100%')

          this.labelLine('适宜范围：', '标准室内湿度应控制在 40-70% 之间。', 12)

          this.labelLine('为什么重要：', '湿度过高容易导致设备腐蚀、物品霉变；湿度过低则可能产生静电，影响人体舒适度和电子设备。', 12)

          this.labelLine('温湿度关系：', '温度和湿度相互影响，温度升高时相对湿度会降低，因此需要同时监测这两个参数。', 12)

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
