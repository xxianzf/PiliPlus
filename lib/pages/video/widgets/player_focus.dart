import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class PlayerFocus extends StatelessWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.numpadAdd ||
        logicalKey == LogicalKeyboardKey.numpadSubtract ||
        logicalKey == LogicalKeyboardKey.numpadMultiply;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          double cur = plPlayerController.playbackSpeed;
          double nextSpeed;
          if (event.scrollDelta.dy < 0) {
            // 滚轮上 +0.1
            nextSpeed = double.parse((cur + 0.1).toStringAsFixed(1));
          } else {
            // 滚轮下 -0.1
            nextSpeed = double.parse((cur - 0.1).toStringAsFixed(1));
          }
          if (nextSpeed >= 0.2 && nextSpeed <= 4.0) {
            plPlayerController.setPlaybackSpeed(nextSpeed);
            SmartDialog.showToast('${nextSpeed}x播放');
          }
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final handled = _handleKey(context, event);
          if (handled || _shouldHandle(event.logicalKey)) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }

  bool get isFullScreen => plPlayerController.isFullScreen.value;
  bool get hasPlayer => plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(
            plPlayerController.maxVolume,
            plPlayerController.volume.value + 0.1,
          )
        : math.max(0.0, plPlayerController.volume.value - 0.1);
    plPlayerController.setVolume(volume);
  }

  // 小键盘 ± 步长0.1，已移除 .value
  void _numpadSpeed({required LogicalKeyboardKey key}) {
    double sp = plPlayerController.playbackSpeed;
    if (key == LogicalKeyboardKey.numpadAdd) {
      sp += 0.1;
    } else if (key == LogicalKeyboardKey.numpadSubtract) {
      sp -= 0.1;
    } else if (key == LogicalKeyboardKey.numpadMultiply) {
      sp = 1.0;
    }
    sp = double.parse(sp.toStringAsFixed(1));
    if (sp >= 0.2 && sp <= 4.0) {
      plPlayerController.setPlaybackSpeed(sp);
      SmartDialog.showToast('${sp}x播放');
    }
  }

  bool _handleKey(BuildContext context, KeyEvent event) {
    final key = event.logicalKey;

    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      _updateVolume(event, isIncrease: isArrowUp);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!plPlayerController.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer) {
            plPlayerController.onForward(const Duration(seconds: -30));
          }
        }
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!plPlayerController.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer && !plPlayerController.longPressStatus.value) {
            plPlayerController
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => plPlayerController
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          plPlayerController.cancelLongPressTimer();
          if (hasPlayer) {
            if (plPlayerController.longPressStatus.value) {
              plPlayerController.setLongPressStatus(false);
            } else {
              plPlayerController.onForward(
                plPlayerController.fastForBackwardDuration,
              );
            }
          }
        }
      }
      return true;
    }

    if (event is KeyDownEvent) {
      switch (key) {
        case LogicalKeyboardKey.space:
          if (plPlayerController.isLive || canPlay!()) {
            if (hasPlayer) {
              plPlayerController.onDoubleTapCenter();
            }
          }
          return true;

        case LogicalKeyboardKey.numpadDivide:
          plPlayerController.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: false,
          );
          return true;

        case LogicalKeyboardKey.home:
          if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
            plPlayerController.toggleDesktopPip();
          }
          return true;

        case LogicalKeyboardKey.enter:
          // Enter：仅跳过分段，移除发弹幕
          if (onSkipSegment?.call() ?? false) {
            return true;
          }
          return true;

        case LogicalKeyboardKey.numpadAdd:
        case LogicalKeyboardKey.numpadSubtract:
        case LogicalKeyboardKey.numpadMultiply:
          if (!plPlayerController.isLive && hasPlayer) {
            _numpadSpeed(key: key);
          }
          return true;
      }

      if (!plPlayerController.isLive) {
        switch (key) {
          case LogicalKeyboardKey.end:
            // End：稍后观看
            introController?.viewLater();
            return true;

          case LogicalKeyboardKey.pageUp:
            if (introController case final introController?) {
              if (!introController.prevPlay()) {
                SmartDialog.showToast('第一集');
              }
            }
            return true;

          case LogicalKeyboardKey.pageDown:
            if (introController case final introController?) {
              if (!introController.nextPlay()) {
                SmartDialog.showToast('最后一集');
              }
            }
            return true;
        }
      }
    }

    return false;
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      plPlayerController.cancelLongPressTimer();
    }
  }
}
