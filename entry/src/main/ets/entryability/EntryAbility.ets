import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeMode } from '../common/ThemeMode';
import { WindowStyle } from '../common/WindowStyle';

const DOMAIN: number = 0x0001;
const TAG: string = 'LockWarden';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 恢复用户上次选择的外观（跟随系统 / 明亮 / 深色）
    ThemeMode.init(this.context).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'theme init failed: %{public}s', err.message);
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    // 状态栏 / 底部导航条跟着界面颜色走（否则 TabBar 下面会多一条灰边）
    WindowStyle.attach(windowStage, this.context);
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in loading the content.');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    WindowStyle.refresh(newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
