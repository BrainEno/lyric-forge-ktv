import '../../../core/navigation/routes.dart';
import 'global_search_item.dart';

GlobalSearchItem _page(
  String id,
  String title,
  String subtitle,
  String route,
  List<String> keywords,
) => GlobalSearchItem(
  kind: GlobalSearchKind.action,
  id: id,
  title: title,
  subtitle: subtitle,
  keywords: keywords,
  target: OpenRouteTarget(route),
);

/// The pages and actions the global search offers (D-065).
///
/// Listed in this order when the search is empty. Keywords add the English
/// name and the pinyin (whole and initials), so a user typing without
/// switching input method still finds 设置 as "settings", "shezhi" or "sz".
///
/// The phone has no recognition and no project pages (D-058), so it gets its
/// own list.
List<GlobalSearchItem> globalSearchActions({required bool phone}) {
  final library = [
    _page('library', '音乐库', '本机的全部歌曲', Routes.library, [
      'library',
      'songs',
      'yinyueku',
      'yyk',
    ]),
    _page('artists', '艺人', '按艺人浏览音乐库', Routes.libraryArtists, [
      'artists',
      'yiren',
      'yr',
      '歌手',
    ]),
    _page('albums', '专辑', '按专辑浏览音乐库', Routes.libraryAlbums, [
      'albums',
      'zhuanji',
      'zj',
    ]),
    _page('favorites', '收藏', '收藏的歌曲', Routes.collections, [
      'favorites',
      'shoucang',
      'sc',
      '喜欢',
    ]),
    _page('playlists', '歌单', '全部播放列表', Routes.playlists, [
      'playlists',
      'gedan',
      'gd',
      '播放列表',
    ]),
    _page('now-playing', '正在播放', '当前歌曲和播放队列', Routes.nowPlaying, [
      'now playing',
      'queue',
      'zhengzaibofang',
      'zzbf',
      '播放队列',
    ]),
  ];
  const shortcuts = GlobalSearchItem(
    kind: GlobalSearchKind.action,
    id: 'shortcuts',
    title: '快捷键',
    subtitle: '查看所有键盘快捷键',
    keywords: ['shortcuts', 'keyboard', 'hotkeys', 'kuaijiejian', 'kjj', '键盘'],
    target: ShowShortcutsTarget(),
  );
  if (phone) {
    return [
      _page('home', '听歌', '回到听歌首页', Routes.home, [
        'home',
        'listen',
        'tingge',
        'tg',
        '首页',
      ]),
      ...library,
      _page('lyrics', '歌词', '有歌词的歌曲', Routes.review, [
        'lyrics',
        'geci',
        'gc',
      ]),
      _page('from-computer', '从电脑获取', '连接电脑，下载或在线播放', Routes.remoteLibrary, [
        'transfer',
        'computer',
        'download',
        'diannao',
        '传输',
        '下载',
      ]),
      _page('settings', '设置', '外观主题与诊断', Routes.settings, [
        'settings',
        'shezhi',
        'sz',
        '主题',
        '外观',
      ]),
    ];
  }
  return [
    _page('import', '导入并识别', '导入歌曲，识别歌词', Routes.import, [
      'import',
      'transcribe',
      'daoru',
      'shibie',
      'dr',
      '识别歌词',
      '新建工程',
    ]),
    _page('projects', '全部工程', '搜索、多选和删除工程', Routes.projects, [
      'projects',
      'gongcheng',
      'gc',
      '工程列表',
    ]),
    _page('review', '校对', '挑选需要校对的歌词', Routes.review, [
      'review',
      'proofread',
      'jiaodui',
      'jd',
      '校对歌词',
    ]),
    ...library,
    _page('trash', '最近删除', '30 天内删除的工程，可以恢复', Routes.projectTrash, [
      'trash',
      'deleted',
      'restore',
      'zuijinshanchu',
      'zjsc',
      '回收站',
      '恢复',
    ]),
    _page(
      'duplicates',
      '清理重复工程',
      '找出同一首歌的重复工程',
      '${Routes.projects}?duplicates=1',
      ['duplicates', 'dedupe', 'chongfu', 'qingli', '重复'],
    ),
    _page('media-sharing', '传到手机', '让手机下载或在线播放本机的歌', Routes.mediaSharing, [
      'transfer',
      'phone',
      'share',
      'chuanshu',
      'shouji',
      '传输',
      '共享',
    ]),
    _page('settings', '设置', '外观主题、识别环境、诊断与试识别', Routes.settings, [
      'settings',
      'shezhi',
      'sz',
      '主题',
      '外观',
      '模型',
    ]),
    shortcuts,
  ];
}
