import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:fcm_tet_01_1008/bindings/webview_binding.dart';
import 'package:fcm_tet_01_1008/data/model/message_model.dart';
import 'package:fcm_tet_01_1008/data/provider/api.dart';
import 'package:fcm_tet_01_1008/data/provider/shared_preferences_api.dart';
import 'package:fcm_tet_01_1008/keyword/group_keys.dart';
import 'package:fcm_tet_01_1008/routes/routes.dart';
import 'package:fcm_tet_01_1008/screen/screen_holder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class MyApp extends StatelessWidget {
  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      initialBinding: WebViewBinding(),
      title: 'Flutter Demo',
      home: ScreenHolder(),
      getPages: routes,
    );
  }


}

void main() async {
  /// 네이티브와 플러터를 바인드를 해줄때 initial 위치가 안맞는 경우가 있음,
  /// 그럴땐 이것을 추가
  WidgetsFlutterBinding.ensureInitialized();

  /// 파일 다운로더 플러그인,  isolate로 동작, debug true시 console log print
  await FlutterDownloader.initialize(debug: true);

  await Permission.storage.request();
  /// 최상위에서 위젯을 호출하기 전에 fcm_background_msg_isolate에 접근
  /// 아래의 IsolateNameServer는 static, isolate간 sendport 공유를 위해 존재
  /// registerPortWithName은 공유할 sendport 등록
  IsolateNameServer.registerPortWithName(
      FCMApi().backGroundMessagePort.sendPort, 'fcm_background_msg_isolate');

  /// myBackgroundMessageHandler는 fcm 백그라운드 isolate 영역
  /// 여기에 미리 등록한 sendport를 myBackgroundMessageHandler에서 호출해 send
  /// myBackgroundMessageHandler에서 send된 메시지는 여기서 받는다.

  runApp(MyApp());
}

groupSummaryNotification(model,
    {String summaryText,
      int total,
      String groupTitle,
      String groupContent,
      List<MessageModel> lines,}) async {
  final flnApiInstance = FLNApi();
  var _androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'fcm_default_channel', '비즈북스', '알람설정',
      setAsGroupSummary: true,
      groupKey: "GROUP_KEY",
      channelAction: AndroidNotificationChannelAction.update,
      styleInformation: InboxStyleInformation(List<String>.from(lines.map((e) => e.msgType).toList()),
          contentTitle: summaryText, summaryText: '$total개의 안 읽은 알림'),
      color: Colors.blue.shade800,
      importance: Importance.max,
      largeIcon: DrawableResourceAndroidBitmap("app_icon"),
      priority: Priority.max);

  await flnApiInstance.flnPlugin.show(
      0,
      groupTitle ?? "group noti title",
      groupContent ?? "group noti body",
      NotificationDetails(
          android: _androidPlatformChannelSpecifics,
          iOS: IOSNotificationDetails()),
      badgeCount: getMsgLength(flnApiInstance.notiListContainer,model.msgType),
      payload:  jsonEncode(model.toMap()));
  print("printDone");
}

/// TOP_Level BackgroundMessageHandler
/// isolate domain
Future<dynamic> myBackgroundMessageHandler(dynamic message) async {
  /// 여기에서 한번 더 flutter_local_notification인스턴스에 접근할 필요가 있어서
  /// flutter_local_notification을 싱글톤화 해야했다.
  try{
  final flnApiInstance = FLNApi();
  final fcmApiInstance = FCMApi();
  final spApiInstance = SPApi();

  final ReceivePort recPort = ReceivePort();

  /// SP init
  await spApiInstance.init();

  MessageModel model;
  
  /// 리슨은 한번만 해도 되니 bool로 체크 하게끔 isListening 추가
    if (!fcmApiInstance.isListening) {
    IsolateNameServer.registerPortWithName(
        recPort.sendPort, "fcm_background_isolate_return");
    // await flnApiInstance.initFLN();
    print("FCM ISOLATE : ReceivePort Initialized");

    recPort.listen((message) async {
      print("FCM ISOLATE : $message");

      if (message["TOTAL"] != null){
        flnApiInstance.notiListContainer = message["TOTAL"];
        await spApiInstance.setList(flnApiInstance.notiListContainer);
      }
      if (message["BACKGROUND"] != null)
        flnApiInstance.backGroundNotiList = message["BACKGROUND"];
      if(message is SendPort)
        message.send({"TOTAL":flnApiInstance.notiListContainer,"BACKGROUND":flnApiInstance.backGroundNotiList});
     // FlutterAppBadger.updateBadgeCount(flnApiInstance.notiListContainer.length);
      return Future<void>.value();
    });
  }

    List<MessageModel> list = spApiInstance.getList;
    print("저장된 리스트의 길이 : ${list.length}");
    if (list != null) {
      flnApiInstance.notiListContainer = list;
      print(list);
    }

    print(message);
    MessageModel lastOne;
    if (flnApiInstance.notiListContainer.length > 0)
      lastOne = flnApiInstance.notiListContainer.last;
    flnApiInstance.addList(message);
    await spApiInstance.setList(flnApiInstance.notiListContainer);
    model = flnApiInstance.notiListContainer.last;
    var _androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'fcm_default_channel', '비즈북스', '알람설정',
        groupKey: "GROUP_KEY",
        styleInformation: BigTextStyleInformation(model.body,
            contentTitle: model.title, summaryText: model.title + " 알림"),
        color: Colors.blue.shade800,
        importance: Importance.max,
        largeIcon: DrawableResourceAndroidBitmap("app_icon"),
        priority: Priority.max);
    var _iOSPlatformChannelSpecifics = IOSNotificationDetails();

    var _platformChannelSpecifics = NotificationDetails(
        android: _androidPlatformChannelSpecifics,
        iOS: _iOSPlatformChannelSpecifics);

    /// notification ID
    int msgId = int.tryParse(model.msgType) ?? 0;

    /// 게시판, 서류함 기타등등 메시지 종류별로 하나씩만 리스트에 넣기 위해 if문으로 중복을 체크
    if (!flnApiInstance.backGroundNotiList
        .map((e) => e.msgType)
        .toList()
        .contains(model.msgType)) {
      flnApiInstance.backGroundNotiList.add(model);
    }

    /// 앞서 선언, 초기화 한 토대로 notification을 띄움

    await flnApiInstance.flnPlugin.show(
        msgId, model.title, model.body, _platformChannelSpecifics,
        badgeCount:
            getMsgLength(flnApiInstance.notiListContainer, model.msgType),
        payload: jsonEncode(model.toMap()));

    /// 날라온 fcm notification 메시지들을 그룹화 시켜서 띄워주는 메소드
    if (lastOne != null && lastOne.msgType != model.msgType)
      await groupSummaryNotification(model,
          summaryText: "${MESSAGE_TYPE_LIST[msgId]} 알림이 도착했습니다",
          groupTitle: MESSAGE_TYPE_LIST[msgId],
          groupContent: "${MESSAGE_TYPE_LIST[msgId]} 관련 알림이 도착해있습니다",
          total: flnApiInstance.notiListContainer.length,
          lines: flnApiInstance.backGroundNotiList);

    fcmApiInstance.isListening = true;
    // FlutterAppBadger.updateBadgeCount(flnApiInstance.notiListContainer.length);
    /// 이 메서드는 isolate domain -> 이 메서드 속 resource가 공유안됨
    /// 여기서는 앞서 등록한 sendport를 가져와 메시지를 send
    final SendPort port =
        IsolateNameServer.lookupPortByName('fcm_background_msg_isolate');

    port.send(
        {"TOTAL": model, "BACKGROUND": flnApiInstance.backGroundNotiList});

    return Future<void>.value();
  } catch (e, s) {
    print(e);
    print(s);
  }
}

int getMsgLength(List<MessageModel> list, String msgType) =>
    list.where((e) => e.msgType == msgType).toList().length;
