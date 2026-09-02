enum FavOrderType {
  mtime('最近收藏', 'mtime', true),
  mtimeAsc('最早收藏', 'mtime', false),
  view('最多播放', 'view', true),
  viewAsc('最少播放', 'view', false),
  pubtime('最近投稿', 'pubtime', true),
  pubtimeAsc('最早投稿', 'pubtime', false),
  ;

  final String label;
  final String apiName;
  final bool descending;

  const FavOrderType(this.label, this.apiName, this.descending);
}
