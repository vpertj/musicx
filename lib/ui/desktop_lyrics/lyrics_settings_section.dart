import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musicx/core/settings/desktop_lyrics_settings.dart';
import 'package:musicx/ui/desktop_lyrics/desktop_lyrics_service.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_glass.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_layout.dart';
import 'package:musicx/ui/desktop_lyrics/lyrics_text_view.dart';

/// 设置页「桌面歌词」配置区:实时预览 + 颜色/字号/玻璃参数。
/// 改动即写 provider(持久化)并经 [DesktopLyricsService] 推送到浮窗。
/// 仅桌面平台渲染 —— 调用方需判断 [DesktopLyricsService.supported]。
class LyricsSettingsSection extends ConsumerWidget {
  const LyricsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(desktopLyricsSettingsProvider);
    final notifier = ref.read(desktopLyricsSettingsProvider.notifier);

    void change(DesktopLyricsSettings next) {
      notifier.update(next); // 持久化
      DesktopLyricsService.pushStyle(next); // 实时推送到已打开的浮窗
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewCard(settings: settings),
        const SizedBox(height: 12),
        _StyleRow(
          value: settings.cardStyle,
          onChanged: (v) => change(settings.copyWith(cardStyle: v)),
        ),
        _ColorRow(
          selected: settings.textColor,
          onColor: (c) => change(settings.copyWith(textColor: c)),
        ),
        _SliderRow(
          label: '字号',
          value: settings.fontSize,
          min: DesktopLyricsSettings.minFontSize,
          max: DesktopLyricsSettings.maxFontSize,
          format: (v) => '${v.round()} px',
          onChanged: (v) => change(settings.copyWith(fontSize: v)),
        ),
        if (settings.cardStyle == LyricsCardStyle.glass) ...[
          _SliderRow(
            label: '玻璃浓度',
            value: settings.glassTint.toDouble(),
            min: DesktopLyricsSettings.minGlassTint.toDouble(),
            max: DesktopLyricsSettings.maxGlassTint.toDouble(),
            format: (v) => '${v.round()}',
            onChanged: (v) => change(settings.copyWith(glassTint: v.round())),
          ),
          _SliderRow(
            label: '模糊强度',
            value: settings.blurSigma,
            min: DesktopLyricsSettings.minBlurSigma,
            max: DesktopLyricsSettings.maxBlurSigma,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => change(settings.copyWith(blurSigma: v)),
          ),
          _SliderRow(
            label: '圆角',
            value: settings.cornerRadius,
            min: DesktopLyricsSettings.minCornerRadius,
            max: DesktopLyricsSettings.maxCornerRadius,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => change(settings.copyWith(cornerRadius: v)),
          ),
        ],
        _SwitchRow(
          label: '字号随窗口缩放',
          value: settings.autoScale,
          onChanged: (v) => change(settings.copyWith(autoScale: v)),
        ),
        _SwitchRow(
          label: '显示下一句',
          value: settings.showNext,
          onChanged: (v) => change(settings.copyWith(showNext: v)),
        ),
        if (settings.cardStyle == LyricsCardStyle.glass)
          _SwitchRow(
            label: '用专辑封面做玻璃背景',
            value: settings.showArtwork,
            onChanged: (v) => change(settings.copyWith(showArtwork: v)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => change(const DesktopLyricsSettings()),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('恢复默认'),
          ),
        ),
      ],
    );
  }
}

/// 实时预览:按当前样式渲染浮窗内容(纯文字 / 毛玻璃)。
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.settings});

  final DesktopLyricsSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = resolveLyricsLayout(
      windowSize: const Size(880, 190),
      settings: settings,
      current: '等到树叶都泛了黄',
      next: '等到眼里全是伤',
    );
    final previewLayout = layout.copyWith(
      fontSize: math.min(layout.fontSize, 40),
      nextFontSize: math.min(layout.nextFontSize, 22),
    );
    final content = LyricsTextView(
      layout: previewLayout,
      settings: settings,
      current: '等到树叶都泛了黄',
      next: '等到眼里全是伤',
    );

    // 预览背景只是「窗户」,让纯文字在设置页里也看得见;
    // 浮窗本身在纯文字样式下没有任何背景。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF20242B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SizedBox(
        height: 130,
        width: double.infinity,
        child: settings.cardStyle == LyricsCardStyle.glass
            ? ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: LyricsGlassCard(
                  settings: settings,
                  artworkUrl: null, // 预览不发起网络请求,统一走兜底渐变
                  radius: layout.cardRadius,
                  child: Padding(
                    padding: layout.padding,
                    child: Center(child: content),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(child: content),
              ),
      ),
    );
  }
}

/// 样式选择行。
class _StyleRow extends StatelessWidget {
  const _StyleRow({required this.value, required this.onChanged});

  final LyricsCardStyle value;
  final ValueChanged<LyricsCardStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('样式', style: Theme.of(context).textTheme.bodyMedium),
          ),
          SegmentedButton<LyricsCardStyle>(
            segments: const [
              ButtonSegment(
                value: LyricsCardStyle.plain,
                label: Text('纯文字'),
                icon: Icon(Icons.text_fields_rounded, size: 16),
              ),
              ButtonSegment(
                value: LyricsCardStyle.glass,
                label: Text('毛玻璃'),
                icon: Icon(Icons.blur_on_rounded, size: 16),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

/// 颜色行:预设色板 + 自定义(HSV 三滑杆)。
class _ColorRow extends StatefulWidget {
  const _ColorRow({required this.selected, required this.onColor});

  final Color selected;
  final ValueChanged<Color> onColor;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  static const _presets = <Color>[
    Color(0xFFFF5A76),
    Color(0xFFFFFFFF),
    Color(0xFF8AD4FF),
    Color(0xFFFFD76A),
    Color(0xFF9BFF9B),
    Color(0xFFC79BFF),
    Color(0xFFFFB27A),
    Color(0xFF7A8CFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('歌词颜色',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          for (final c in _presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => widget.onColor(c),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: widget.selected.toARGB32() == c.toARGB32()
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2.5)
                        : Border.all(color: Colors.black12),
                  ),
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final c = await showDialog<Color>(
                context: context,
                builder: (_) => _HsvColorDialog(initial: widget.selected),
              );
              if (c != null) widget.onColor(c);
            },
            child: const Text('自定义'),
          ),
        ],
      ),
    );
  }
}

/// 极简 HSV 取色器:三个滑杆 + 预览,不引第三方依赖。
class _HsvColorDialog extends StatefulWidget {
  const _HsvColorDialog({required this.initial});

  final Color initial;

  @override
  State<_HsvColorDialog> createState() => _HsvColorDialogState();
}

class _HsvColorDialogState extends State<_HsvColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(height: 12),
          _hsvSlider(
            label: '色相',
            value: _hsv.hue,
            max: 360,
            onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
          ),
          _hsvSlider(
            label: '饱和度',
            value: _hsv.saturation,
            max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          ),
          _hsvSlider(
            label: '明度',
            value: _hsv.value,
            max: 1,
            onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _hsvSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            label: format(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            format(value),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
