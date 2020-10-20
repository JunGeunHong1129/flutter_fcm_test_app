import 'package:fcm_tet_01_1008/controller/http_controller.dart';
import 'package:fcm_tet_01_1008/controller/webview_controller.dart';
import 'package:fcm_tet_01_1008/keyword/url.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewPage extends StatefulWidget {
  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {

  /// 편한 컨트롤러 접근을 위해 추가, to 생략 가능
  HttpController httpController = HttpController.to;
  WebViewController webViewController = WebViewController.to;

  @override
  void initState() {
    // TODO: implement initState
    webViewController.initNotifications();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        resizeToAvoidBottomPadding: false,
        body: SingleChildScrollView(
          reverse: true,
          physics: NeverScrollableScrollPhysics(),
          child: Container(
            height: Get.height - MediaQuery
                .of(context)
                .padding
                .top,
            width: Get.width,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery
                      .of(context)
                      .viewInsets
                      .bottom),
              child: InAppWebView(
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>[
                  new Factory<
                      OneSequenceGestureRecognizer>(() => new EagerGestureRecognizer(),),
                ].toSet(),
                initialUrl: MAIN_URL,
                initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(
                        debuggingEnabled: true,
                        useShouldOverrideUrlLoading: true)),
                onWebViewCreated: (InAppWebViewController controller) {
                  webViewController.wvc = controller;
                },
                onProgressChanged: (InAppWebViewController controller,
                    int progress) {
                  print("변경시작 : $progress");

                  /// webViewController.isLoadDone은 다이얼로그 중복 Get.back() 을 방지
                  /// TODO 오류픽스쪽에 추가할 것
                  /// TODO 로딩창 구현 (기능개발) + 로딩창 오류 픽스 (오류픽스) 레드마인에 2개로 올리기
                  if(!webViewController.isLoadDone) webViewController.progressChanged((progress / 100));

                  else webViewController.isLoadDone=false;

                },
                onLoadStart:
                    (InAppWebViewController controller, String url) async {
                  //URLLoad시작
                  //시작시 현 컨트롤러 업데이트 & 세션스토리지 로드 + 업데이트 -> 로그인 체크 가능
                  webViewController.wvc = controller;
                  // 서순에 맞게 로딩을 하기위해 future화 -> 다이얼로그가 끝나야 로그인체크를 시작
                  await webViewController.progressDialog();
                     print("$url");
                     SessionStorage ss = SessionStorage(webViewController.wvc);
                     webViewController.ssItem =
                     await ss.getItem(key: "loginUserForm");
                     webViewController.checkSignin(url);

                     //리로드 + 체크용도
                     await webViewController.checkAndReLoadUrl();

                },
                shouldOverrideUrlLoading:
                    (controller, shouldOverrideUrlLoadingRequest) async {
                  var url = shouldOverrideUrlLoadingRequest.url;
                  var uri = Uri.parse(url);
                  if (["tel"].contains(uri.scheme)) {
                    if (await canLaunch(url))
                      await launch(url);
                    return ShouldOverrideUrlLoadingAction.CANCEL;
                  }
                  return ShouldOverrideUrlLoadingAction.ALLOW;
                  // 만약 강제로 리다이렉트, 등등을 원할 경우 여기서 url 편집
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
