import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/fav_order_type.dart';
import 'package:PiliPlus/models_new/fav/fav_article/data.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/data.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/data.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/models_new/fav/fav_note/list.dart';
import 'package:PiliPlus/models_new/fav/fav_pgc/data.dart';
import 'package:PiliPlus/models_new/fav/fav_topic/data.dart';
import 'package:PiliPlus/models_new/space/space_cheese/data.dart';
import 'package:PiliPlus/models_new/space/space_fav/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_sign.dart';
import 'package:dio/dio.dart';

abstract final class FavHttp {
  static Future<LoadingState<void>> favFavFolder(Object mediaId) async {
    final res = await Request().post(
      Api.favFavFolder,
      data: {
        'media_id': mediaId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> unfavFavFolder(Object mediaId) async {
    final res = await Request().post(
      Api.unfavFavFolder,
      data: {
        'media_id': mediaId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<FavDetailData>> userFavFolderDetail({
    required int mediaId,
    required int pn,
    required int ps,
    String keyword = '',
    FavOrderType order = FavOrderType.mtime,
    int type = 0,
  }) async {
    final res = await Request().get(
      Api.favResourceList,
      queryParameters: {
        'media_id': mediaId,
        'pn': pn,
        'ps': ps,
        'keyword': keyword,
        'order': order.apiName,
        'type': type,
        'tid': 0,
        'platform': 'web',
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavDetailData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 取消订阅
  static Future<LoadingState<void>> cancelSub({
    required int id,
    required int type,
  }) async {
    final res = type == 11
        ? await Request().post(
            Api.unfavFolder,
            data: {
              'media_id': id,
              'csrf': Accounts.main.csrf,
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
          )
        : await Request().post(
            Api.unfavSeason,
            data: {
              'platform': 'web',
              'season_id': id,
              'csrf': Accounts.main.csrf,
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<SubDetailData>> favSeasonList({
    required int id,
    required int pn,
    required int ps,
  }) async {
    final res = await Request().get(
      Api.favSeasonList,
      queryParameters: {
        'season_id': id,
        'ps': ps,
        'pn': pn,
      },
    );
    if (res.data['code'] == 0) {
      return Success(SubDetailData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<SpaceCheeseData>> favPugv({
    required int mid,
    required int page,
  }) async {
    final res = await Request().get(
      Api.favPugv,
      queryParameters: {
        'mid': mid,
        'ps': 20,
        'pn': page,
        'web_location': 333.1387,
      },
    );
    if (res.data['code'] == 0) {
      return Success(SpaceCheeseData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> addFavPugv(Object seasonId) async {
    final res = await Request().post(
      Api.addFavPugv,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> delFavPugv(Object seasonId) async {
    final res = await Request().post(
      Api.delFavPugv,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<FavTopicData>> favTopic({
    required int page,
  }) async {
    final res = await Request().get(
      Api.favTopicList,
      queryParameters: {
        'page_size': 24,
        'page_num': page,
        'web_location': 333.1387,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavTopicData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> addFavTopic(Object topicId) async {
    final res = await Request().post(
      Api.addFavTopic,
      data: {
        'topic_id': topicId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> delFavTopic(Object topicId) async {
    final res = await Request().post(
      Api.delFavTopic,
      data: {
        'topic_id': topicId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> likeTopic(
    Object topicId,
    bool isLike,
  ) async {
    final res = await Request().post(
      Api.likeTopic,
      data: {
        'action': isLike ? 'cancel_like' : 'like',
        'up_mid': Accounts.main.mid,
        'topic_id': topicId,
        'csrf': Accounts.main.csrf,
        'business': 'topic',
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<FavArticleData>> favArticle({
    required int page,
  }) async {
    final res = await Request().get(
      Api.favArticle,
      queryParameters: {
        'page_size': 20,
        'page': page,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavArticleData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> addFavArticle({
    required Object id,
  }) async {
    final res = await Request().post(
      Api.addFavArticle,
      data: {
        'id': id,
        'csrf': Accounts.main.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> delFavArticle({
    required Object id,
  }) async {
    final res = await Request().post(
      Api.delFavArticle,
      data: {
        'id': id,
        'csrf': Accounts.main.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<List<FavNoteItemModel>?>> userNoteList({
    required int page,
  }) async {
    final res = await Request().get(
      Api.userNoteList,
      queryParameters: {
        'pn': page,
        'ps': 10,
        'csrf': Accounts.main.csrf,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      if (data == null) {
        return const Success(null);
      }
      return Success(
        (data['list'] as List<dynamic>?)
            ?.map((e) => FavNoteItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<FavPgcData>> favPgc({
    required int mid,
    required int page,
    required int type,
  }) async {
    final res = await Request().get(
      Api.favPgc,
      queryParameters: {
        'vmid': mid,
        'pn': page,
        'ps': 20,
        'type': type,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavPgcData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> addFavPgc({
    required int seasonId,
  }) async {
    final res = await Request().post(
      Api.addFavPgc,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> delFavPgc({
    required int seasonId,
  }) async {
    final res = await Request().post(
      Api.delFavPgc,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<FavFolderData>> userFavFolder({
    required int mid,
    int pn = 1,
    int ps = 20,
  }) async {
    final res = await Request().get(
      Api.favFolder,
      queryParameters: {
        'up_mid': mid,
        'pn': pn,
        'ps': ps,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavFolderData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }
}
