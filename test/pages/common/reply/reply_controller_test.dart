import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter_test/flutter_test.dart';

class _TestReplyController extends ReplyController<MainListReply> {
  @override
  final int oid = 0;

  @override
  final int replyType = 0;

  @override
  int get sourceId => oid;

  @override
  Future<LoadingState<MainListReply>> customGetData() async =>
      const Error('not used in tests');
}

ReplyInfo _reply(int id) => ReplyInfo(id: Int64(id));

/// 走一遍 [CommonListController.queryData] 中「刷新 → 分页追加」的调用顺序。
void _refreshThenAppend(
  _TestReplyController controller,
  MainListReply page,
) {
  controller.customHandleResponse(false, Success(page));
  controller.handleListResponse(page.replies);
  (controller.loadingState.value as Success).response!.addAll(page.replies);
}

void main() {
  test('pagination append drops replies already in the list', () {
    final controller = _TestReplyController();

    final firstPage = MainListReply(replies: [_reply(1), _reply(2)]);
    controller.customHandleResponse(true, Success(firstPage));
    controller.loadingState.value = Success(firstPage.replies);

    // 第二页与第一页有重叠：id 2 已存在，id 3 是新的
    final secondPage = MainListReply(replies: [_reply(2), _reply(3)]);
    _refreshThenAppend(controller, secondPage);

    expect(
      controller.loadingState.value.dataOrNull!.map((e) => e.id.toInt()),
      [1, 2, 3],
    );
  });

  test('duplicates within a single appended page are dropped too', () {
    final controller = _TestReplyController();
    controller.loadingState.value = Success(<ReplyInfo>[_reply(1)]);

    final page = MainListReply(replies: [_reply(1), _reply(1), _reply(2)]);
    _refreshThenAppend(controller, page);

    expect(
      controller.loadingState.value.dataOrNull!.map((e) => e.id.toInt()),
      [1, 2],
    );
  });

  test('refresh responses are not deduplicated', () {
    final controller = _TestReplyController();
    // 刷新时即使数据里有重复也原样保留，去重只用于分页追加
    final page = MainListReply(replies: [_reply(1), _reply(1)]);
    controller.customHandleResponse(true, Success(page));
    controller.handleListResponse(page.replies);

    expect(page.replies.map((e) => e.id.toInt()), [1, 1]);
  });

  test('upTop is not duplicated when it is also in the reply list', () {
    final controller = _TestReplyController();
    final upTop = _reply(9);
    final page = MainListReply(upTop: upTop, replies: [upTop, _reply(1)]);

    controller.customHandleResponse(true, Success(page));

    expect(
      page.replies.map((e) => e.id.toInt()),
      [9, 1],
    );
  });
}
