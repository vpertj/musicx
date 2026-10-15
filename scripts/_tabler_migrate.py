#!/usr/bin/env python3
"""按映射总表把 Material 图标替换为 AppIcons 语义(Task 3/4/5 共用)。

用法: python3 scripts/_tabler_migrate.py <dart 文件...>
"""
import pathlib
import re
import sys

MAP = {
    'queue_music_rounded': 'queue', 'download_rounded': 'download',
    'add_rounded': 'add', 'music_note_rounded': 'music',
    'chevron_right_rounded': 'chevronRight', 'link_rounded': 'link',
    'extension_rounded': 'extension', 'check_circle_rounded': 'checkCircle',
    'play_arrow_rounded': 'play', 'library_music_rounded': 'library',
    'favorite_rounded': 'favoriteActive', 'close_rounded': 'close',
    'settings_rounded': 'settingsActive', 'settings_outlined': 'settings',
    'rss_feed_rounded': 'rss', 'local_fire_department_rounded': 'fire',
    'insert_drive_file_outlined': 'insertFile', 'history_rounded': 'history',
    'favorite_border_rounded': 'favorite',
    'download_for_offline_outlined': 'downloaded',
    'delete_outline_rounded': 'delete', 'widgets_rounded': 'widgets',
    'search_rounded': 'search', 'restart_alt_rounded': 'restart',
    'repeat_rounded': 'repeat', 'repeat_one_rounded': 'repeatOne',
    'refresh_rounded': 'refresh', 'playlist_play_rounded': 'playlistPlay',
    'playlist_add_rounded': 'addToPlaylist', 'pause_rounded': 'pause',
    'open_in_new_rounded': 'openExternal', 'lyrics_rounded': 'lyricsActive',
    'library_music_outlined': 'libraryOutlined',
    'keyboard_arrow_down_rounded': 'chevronDown',
    'explore_rounded': 'exploreActive', 'explore_outlined': 'explore',
    'cloud_off_rounded': 'cloudOff', 'auto_awesome_rounded': 'autoAwesome',
    'volume_up_rounded': 'volume', 'view_day_rounded': 'viewDay',
    'view_agenda_rounded': 'viewAgenda', 'verified_rounded': 'verified',
    'update_rounded': 'update', 'tune_rounded': 'tune',
    'text_fields_rounded': 'textFields',
    'system_update_alt_rounded': 'updateAlt', 'subtitles_rounded': 'subtitles',
    'skip_previous_rounded': 'prev', 'skip_next_rounded': 'next',
    'shuffle_rounded': 'shuffle',
    'settings_backup_restore_rounded': 'settingsBackup',
    'search_off_rounded': 'searchOff', 'remove_rounded': 'remove',
    'remove_circle_outline_rounded': 'removeCircle', 'radar_rounded': 'radar',
    'palette_outlined': 'palette', 'lyrics_outlined': 'lyrics',
    'light_mode_outlined': 'lightMode', 'label_outline_rounded': 'label',
    'info_outline_rounded': 'info', 'folder_open_rounded': 'folder',
    'error_outline_rounded': 'error', 'edit_outlined': 'edit',
    'download_for_offline_rounded': 'downloadedActive',
    'dark_mode_outlined': 'darkMode', 'check_rounded': 'check',
    'check_circle_outline_rounded': 'checkCircleOutlined',
    'cancel_rounded': 'cancel', 'blur_on_rounded': 'blur',
    'album_rounded': 'album', 'add_circle_outline_rounded': 'addCircle',
}

IMPORT = "import 'package:musicx/ui/icons.dart';"


def migrate(path: str) -> int:
    p = pathlib.Path(path)
    s = p.read_text()
    n = 0
    for mat, sem in MAP.items():
        s, k = re.subn(r'\bIcons\.%s\b' % re.escape(mat), 'AppIcons.%s' % sem, s)
        n += k
    if n and IMPORT not in s:
        anchor = "import 'package:flutter/material.dart';"
        if anchor in s:
            s = s.replace(anchor, anchor + '\n\n' + IMPORT, 1)
        else:
            lines = s.split('\n')
            idx = max(i for i, l in enumerate(lines) if l.startswith('import '))
            lines.insert(idx + 1, IMPORT)
            s = '\n'.join(lines)
    if n:
        p.write_text(s)
    return n


if __name__ == '__main__':
    total = 0
    for f in sys.argv[1:]:
        k = migrate(f)
        total += k
        print(f'{k:3d}  {f}')
    print(f'--- 合计 {total} 处 ---')
