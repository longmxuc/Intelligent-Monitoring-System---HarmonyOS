import { router } from "@kit.ArkUI"

@Entry
@Component
export struct Temp {
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
            Text('🌡️温度监测')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))
            Text('温度是影响环境舒适度的重要参数之一。')
              .fontSize(14)
              .fontColor($r("app.color.home_title_text"))
              .lineHeight(22)
              .textAlign(TextAlign.JUSTIFY)
          }
          .width('100%')

          this.labelLine('适宜范围：', '一般室内温度应保持在 20-25℃ 之间。', 12)

          this.labelLine('为什么重要：', '温度过高或过低都会影响人体舒适度和设备运行稳定性，温度波动还会影响精密仪器的准确性。', 12)

          this.labelLine('监测意义：', '实时监测温度变化，可以及时调整空调系统，保证环境条件的稳定性。', 12)

          this.labelLine('另一数据源：', '系统配备了两个温度传感器（DHT11和BMP280），“另一数据源”显示的是第二个传感器的温度数据。通过对比两个传感器的数据，可以交叉验证测量准确性，并了解不同位置的温度分布情况，提高监测的可靠性。', 12)

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
