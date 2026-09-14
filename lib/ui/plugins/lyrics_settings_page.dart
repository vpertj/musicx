import 'package:flutter/material.dart';

import 'package:musicx/ui/desktop_lyrics/lyrics_settings_section.dart';

/// 桌面歌词设置二级页。
///
/// 原先这块(实时预览 + 字号/颜色/玻璃参数 + 多个开关)直接内联在设置首页,
/// 把「外观」分组撑得很长、视觉杂乱。参考主流设置页做法:列表只留一行摘要,
/// 具体配置收进二级页。
class LyricsSettingsPage extends StatelessWidget {
  const LyricsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('桌面歌词')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: LyricsSettingsSection(),
          ),
        ),
      ),
    );
  }
}
