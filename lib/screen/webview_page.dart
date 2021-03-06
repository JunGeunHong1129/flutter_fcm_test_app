import 'dart:async';
import 'dart:io';
import 'package:fcm_tet_01_1008/controller/screen_holder_controller.dart';
import 'package:fcm_tet_01_1008/controller/webview_controller.dart';
import 'package:fcm_tet_01_1008/data/model/web_view_model.dart';
import 'package:fcm_tet_01_1008/keyword/url.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewPage extends StatefulWidget {
  final screenHeight;
  final WebViewModel viewModel;
  final GlobalKey<_WebViewPageState> key;


  const WebViewPage({@required this.key, @required this.screenHeight, @required this.viewModel})
      : super(key: key);

  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  /// 편한 컨트롤러 접근을 위해 추가, to 생략 가능
  WebViewController _controller = WebViewController.to;
  ScreenHolderController _holderController = ScreenHolderController.to;
  Future result;
  double _totalHeight;
  bool _isCheckOut = false;
  WebViewModel model;
  List<WebViewPage> pageList;

  @override
  void initState() {
    // TODO: implement initState
    result = _controller.initNotifications();
    model = widget.viewModel;
    pageList = _controller.wvcApiInstance.webViewPages;
    this._totalHeight = Get.height - (widget.screenHeight + ((Platform.isAndroid) ? Get.height * 0.05:Get.height * 0.1));
    super.initState();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    _controller.wvcApiInstance.ajaxApiInstance.streamController.close();
    _controller.wvcApiInstance.ajaxApiInstance.ajaxStreamSubScription.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      reverse: true,
      physics: NeverScrollableScrollPhysics(),
      child: Container(
        height: this._totalHeight,
        width: Get.width,
        child: Padding(
          padding:
          EdgeInsets.only(bottom: MediaQuery
              .of(context)
              .viewInsets
              .bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GetBuilder<WebViewController>(
                  builder: (_) =>
                  (_controller.progress < 1.0)
                      ? LinearProgressIndicator(
                    value: _controller.progress.toDouble(),
                  )
                      : Container()),
              Expanded(
                child: FutureBuilder(
                  future: result,
                  builder: (context, snapshot) {
                    if (snapshot.data != null)
                      return buildWebView();
                    else if (snapshot.hasError)
                      return Text("${snapshot.error} : 오류가 발생하여 접근이 불가합니다.");
                    else
                      return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  buildWebView() {
    return InAppWebView(
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>[
        new Factory<OneSequenceGestureRecognizer>(
              () => new EagerGestureRecognizer(),
        ),
      ].toSet(),
      initialUrl: model.url,
      initialOptions: model.options,
      windowId: model.windowId,
      onWebViewCreated: (InAppWebViewController controller) {
        model.webViewController =
            controller;
        print("웹뷰 생성");
      },
      onProgressChanged:
          (InAppWebViewController controller, int progress) async {
        /// webViewController.isLoadDone은 다이얼로그 중복 Get.back() 을 방지
        _controller.progressChanged((progress / 100));
      },

      /// 웹 페이지 완전 로드 체크를 위해 필요
      /// 로드 이후 연산을 담당
      /// 수임 업체 리스트를 완전 로드시 리로드 체크
      onLoadResource: (controller, resource) async {
        /// TODO : resource.url 분기 세분화 필요!
        try{
          model.webViewController =
              controller;

          /// 관제용리로드 여부 체크(푸시알람 터치후 로그인 하고 온 상태인지 여부)
          if (resource.url.contains("/selectCustlist")) {
            String currentUrl = await controller.getUrl();
            if (currentUrl.contains(MAIN_URL_LIST[0])) await _controller
                .checkAndReLoadUrl();
          }

          if (resource.url.contains("/m_header.js")) {
            String currentUrl = await controller.getUrl();

            ///관제용 메인(수임업체리스트)에서 initlogout
            if (currentUrl.contains(MAIN_URL_LIST[0])) await _controller
                .wvcApiInstance.initLogoutProc(INIT_LOGOUT_BTNS[0]);

            if (currentUrl.contains(MAIN_URL_LIST[1])) {

              /// 일반용 메인(대시보드)에서 ajaxoption false화
              await _controller.wvcApiInstance.ajaxApiInstance.ajaxCompleter.future; // ssItem 업데이트까지 임시 대기
              await _controller.shouldWebViewOptionChange(model);

              ///일반용 리스트에서 initlogout
              await _controller.wvcApiInstance.initLogoutProc(
                  INIT_LOGOUT_BTNS[1]);
            }
          }}catch(e,s){
          print(e);
          print(s);
        }
      },
      onLoadStop: (InAppWebViewController controller, String url) async {
        model.webViewController =
            controller;
        print(url.endsWith("/m"));
        if (url.endsWith("/m")) await _controller.autoLoginProc();
        print("현재 main히스토리 로그 : ${ScreenHolderController.to.currentIndex} : ${await controller.getCopyBackForwardList()}");
        //리로드 + 체크용도
      },
        onDownloadStart: (controller, url) async {
          if (_isCheckOut) {
            _isCheckOut = false;
            return;
          }
          var uri = Uri.parse(url);
          String path = uri.path;
          String fileName = path.substring(path.lastIndexOf("/") + 1);
          Get.snackbar(
            "다운로드 시작", "'${(fileName.length>20)? fileName.substring(0,5)+"..."+fileName.substring(fileName.lastIndexOf(".")-3,fileName.length):fileName}'",
            duration: Duration(seconds: 3),
          );
          var taskId = await FlutterDownloader.enqueue(
              url: url,
              fileName: fileName,
              savedDir: (await getExternalStorageDirectory()).path,
              showNotification: true,
              openFileFromNotification: true)
              .then((value) {
            print("테스트1");
            if (Get.isSnackbarOpen) {
              print("테스트2");
              Get.back();
            }
          });
          Get.snackbar(
              "다운로드 완료", "'${(fileName.length>20)? fileName.substring(0,5)+"..."+fileName.substring(fileName.lastIndexOf(".")-3,fileName.length):fileName}'",
              mainButton: FlatButton(onPressed: () async {
                File f = File(((await getExternalStorageDirectory()).path +
                    "/" +
                    fileName));
                Uri _uri = Uri.file(f.path);
                String url =
                    "/sdcard/Android/data/com.example.fcm_tet_01_1008/files/" +
                        fileName;

                await OpenFile.open(url);
                Get.back();
              }, child: Text("확인"))
          );
          _holderController.onFileurl();
        },
      shouldOverrideUrlLoading:
          (controller, shouldOverrideUrlLoadingRequest) async {
          var url = shouldOverrideUrlLoadingRequest.url;
          var uri = Uri.parse(url);
          print("오버로딩 체크 : $url");
          if (["tel"].contains(uri.scheme)) {
            if (await canLaunch(url)) await launch(url);
            return ShouldOverrideUrlLoadingAction.CANCEL;
          }
          if (url.endsWith("/board/detail?no=undefined&bc=undefined")) return ShouldOverrideUrlLoadingAction.CANCEL;
          if (url.endsWith(".pdf")) {
            var resultCheck = await Get.defaultDialog(
              title: "파일",
              content: Text("저장 하시겠습니까?"),
              actions: <Widget>[
                FlatButton(
                    onPressed: () async {
                      if (await canLaunch(url)) {
                        _isCheckOut = true;
                        await launch(url);
                        ScreenHolderController.to.onFileurl();
                        return Get.back(result: true);
                      }
                    },
                    child: Text("보기")),
                FlatButton(
                    onPressed: () async {
                      return Get.back(result: false);
                      // Get.defaultDialog(title: "다운로드")
                    },
                    child: Text("저장"))
              ],
            );
            if (resultCheck == null) {
              _isCheckOut = true;
              _holderController.onFileurl();
            }
          }
          return ShouldOverrideUrlLoadingAction.ALLOW;

        // 만약 강제로 리다이렉트, 등등을 원할 경우 여기서 url 편집
      },
      shouldInterceptAjaxRequest:
          (InAppWebViewController controller, AjaxRequest ajaxRequest) async {
        String data = ajaxRequest.data;

        if (ajaxRequest.method == "POST" &&
            !data.contains("procType")) _controller.ajaxRequestInterceptProc(
            ajaxRequest);

        return ajaxRequest;
      },
      onAjaxReadyStateChange:
          (InAppWebViewController controller, AjaxRequest ajaxRequest) async {
            model.webViewController =
            controller;

        if (ajaxRequest.method == "POST" &&
            ajaxRequest.readyState == AjaxRequestReadyState.DONE &&
            ajaxRequest.status == 200) await _controller
            .ajaxRequestInterceptResponseProc(ajaxRequest);

        return AjaxRequestAction.PROCEED;
      },
      onConsoleMessage: (controller, consoleMessage) async {
        print("콘솔 로그 : ${consoleMessage.message}");
        if (consoleMessage.message == "logout") {
          await _controller.wvcApiInstance.logoutProc();
          print(pageList.length);
          if(pageList.length>1){
            _holderController.onPressHomeBtn();
          }else{
            if (_controller.wvcApiInstance.procType != "2") {
              model.webViewGroupOptionSetter(true);
              await controller.setOptions(
                  options: model.options);
            }
          }
        }
      },

      /// 대시보드등등 새탭이 열리는 동작을 담당
      onCreateWindow: (controller, createWindowRequest) async {try{
        ScreenHolderController.to.changeWebViewModel(
            WebViewModel(
                url: "about:blank", windowId: createWindowRequest.windowId),
            );
      }catch(e,s){
        print(e);
        print(s);
      }
      return true;
      },
      onLoadHttpError: (controller, url, code, message) {
        print("에러발생!");
        if (Platform.isIOS && code == -999) {
          // NSURLErrorDomain
          return;
        }
        _controller.isError = true;
        Get.defaultDialog(title: "에러발생",
            middleText: "페이지 로드를 실패했습니다.\n잠시후 다시 시도해주세요.",
            actions: <Widget>[FlatButton(child: Text("확인"),onPressed: (){
              if(Platform.isAndroid) exit(0);
              else SystemNavigator.pop();
            })]);
      },
      onLoadError: (controller, url, code, message){
        print("에러발생!");
        if (Platform.isIOS && code == -999) {
          // NSURLErrorDomain
          return;
        }
        _controller.isError = true;
        Get.defaultDialog(title: "에러발생",
            middleText: "페이지 로드를 실패했습니다.\n잠시후 다시 시도해주세요.",
            actions: <Widget>[FlatButton(child: Text("확인"),onPressed: (){
              if(Platform.isAndroid) exit(0);
              else SystemNavigator.pop();
            })]);
      },
    );
  }
}
