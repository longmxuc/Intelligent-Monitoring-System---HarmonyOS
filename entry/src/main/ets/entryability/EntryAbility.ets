import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    
    // 初始化当前颜色模式到AppStorage
    try {
      const config = this.context.config;
      if (config?.colorMode !== undefined) {
        AppStorage.setOrCreate('currentColorMode', config.colorMode);
        hilog.info(DOMAIN, 'testTag', '初始化颜色模式: %{public}d', config.colorMode);
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get colorMode. Cause: %{public}s', JSON.stringify(err));
      // 默认使用亮色模式
      AppStorage.setOrCreate('currentColorMode', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    }
    
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  // 系统配置变化回调（包括主题切换）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', '系统配置变化 colorMode: %{public}d', newConfig.colorMode ?? -1);
    
    // 更新AppStorage中的颜色模式
    if (newConfig.colorMode !== undefined) {
      AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
      hilog.info(DOMAIN, 'testTag', '更新颜色模式到AppStorage: %{public}d', newConfig.colorMode);
      
      // 发送主题变化事件
      try {
        emitter.emit({ eventId: 1001 }, { data: { colorMode: newConfig.colorMode } });
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', '发送主题变化事件失败: %{public}s', JSON.stringify(err));
      }
    }
  }
}