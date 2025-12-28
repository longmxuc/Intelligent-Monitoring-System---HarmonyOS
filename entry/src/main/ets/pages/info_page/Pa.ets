import { router } from "@kit.ArkUI"

@Entry
@Component
export struct Pa {
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
            Text('🌤️大气压监测')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.home_value_text"))

            Text('大气压是空气作用在单位面积上的力，单位为百帕（hPa）或千帕（kPa）。')
              .fontSize(14)
              .fontColor($r("app.color.home_title_text"))
              .lineHeight(22)
              .textAlign(TextAlign.JUSTIFY)
          }
          .width('100%')

          this.labelLine('标准值：', '海平面标准大气压约为 1013 hPa（101.3 kPa），正常范围一般在 980-1040 hPa 之间。', 12)

          this.labelLine('为什么重要：', '大气压影响人体舒适度、液体沸点等参数。某些场景需要记录大气压以确保环境条件的稳定性。', 12)

          this.labelLine('气象关联：', '大气压变化与天气变化密切相关，低压通常伴随阴雨天气，高压则多晴朗天气。', 12)

          this.labelLine('监测意义：', '实时监测大气压可以帮助校准精密仪器，预测天气变化，保证环境条件的准确记录。', 12)

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
