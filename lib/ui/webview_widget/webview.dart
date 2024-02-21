import 'dart:convert';
import 'dart:io';
import 'dart:developer';

import 'package:chatwoot_sdk/chatwoot_sdk.dart';
import 'package:chatwoot_sdk/ui/webview_widget/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    as webview_flutter_android;
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// #enddocregion platform_imports

///Chatwoot webview widget
/// {@category FlutterClientSdk}
class Webview extends StatefulWidget {
  /// Url for Chatwoot widget in webview
  late final String widgetUrl;

  /// Chatwoot user & locale initialisation script
  late final String injectedJavaScript;

  /// See [ChatwootWidget.closeWidget]
  final void Function()? closeWidget;

  /// See [ChatwootWidget.onAttachFile]
  final Future<List<String>> Function()? onAttachFile;

  /// See [ChatwootWidget.onLoadStarted]
  final void Function()? onLoadStarted;

  final void Function(String)? onChatwootHandler;

  final void Function(String)? onGolfdiggHandler;

  /// See [ChatwootWidget.onLoadProgress]
  final void Function(int)? onLoadProgress;

  /// See [ChatwootWidget.onLoadCompleted]
  final void Function()? onLoadCompleted;

  Webview(
      {Key? key,
      required String websiteToken,
      required String baseUrl,
      ChatwootUser? user,
      String locale = "en",
      customAttributes,
      this.closeWidget,
      this.onAttachFile,
      this.onLoadStarted,
      this.onChatwootHandler,
      this.onGolfdiggHandler,
      this.onLoadProgress,
      this.onLoadCompleted})
      : super(key: key) {
    widgetUrl =
        "${baseUrl}/widget?website_token=${websiteToken}&locale=${locale}";

    injectedJavaScript = generateScripts(
        user: user, locale: locale, customAttributes: customAttributes);
  }

  @override
  _WebviewState createState() => _WebviewState();
}

class _WebviewState extends State<Webview> {
  WebViewController? _controller;
  late final WebViewCookieManager cookieManager = WebViewCookieManager();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String webviewUrl = widget.widgetUrl;
      final cwCookie = await StoreHelper.getCookie();
      if (cwCookie.isNotEmpty) {
        webviewUrl = "${webviewUrl}&cw_conversation=${cwCookie}";
      }
      setState(() {
        late final PlatformWebViewControllerCreationParams params;
        if (WebViewPlatform.instance is WebKitWebViewPlatform) {
          params = WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }
        _controller = WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (int progress) {
                // Update loading bar.
                widget.onLoadProgress?.call(progress);
              },
              onPageStarted: (String url) {
                widget.onLoadStarted?.call();
              },
              onPageFinished: (String url) async {
                final String cookies = await _controller
                    ?.runJavaScriptReturningResult('document.cookie') as String;
                log("Cookies finish: $cookies");
                widget.onLoadCompleted?.call();
              },
              onWebResourceError: (WebResourceError error) {
                print("web Error: ${error.description}");
              },
              onNavigationRequest: (NavigationRequest request) {
                // _goToUrl(request.url);
                print("Navigation request: ${request.url}");
                print("Navigation request: ${request}");
                final uri = Uri.parse(request.url);
                if (uri.scheme == 'chatwoothandle') {
                  final message = getMessage(uri.query);
                  widget.onChatwootHandler?.call(request.url);
                  return NavigationDecision.prevent;
                }
                if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
                  launchUrl(uri);
                  return NavigationDecision.prevent;
                }
                if (uri.scheme == 'golfdigg') {
                  widget.onGolfdiggHandler?.call(request.url);
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            ),
          )
          ..addJavaScriptChannel("ReactNativeWebView",
              onMessageReceived: (JavaScriptMessage jsMessage) {
            print("Chatwoot message received: ${jsMessage.message}");
            log("Chatwoot message received: ${jsMessage.message}");
            final message = getMessage(jsMessage.message);
            if (isJsonString(message)) {
              final parsedMessage = jsonDecode(message);
              log("Chatwoot parsed message: ${parsedMessage}");
              final eventType = parsedMessage["event"];
              final type = parsedMessage["type"];
              if (eventType == 'loaded') {
                final authToken = parsedMessage["config"]["authToken"];
                StoreHelper.storeCookie(authToken);
                _controller?.runJavaScript(widget.injectedJavaScript);
              }
              if (type == 'close-widget') {
                widget.closeWidget?.call();
              }
            }
          })
          ..addJavaScriptChannel("parent",
              onMessageReceived: (JavaScriptMessage jsMessage) async {
            print("Chatwoot message received: ${jsMessage.message}");
            log("Chatwoot message received: ${jsMessage.message}");
            final message = getMessage(jsMessage.message);
            if (isJsonString(message)) {
              final parsedMessage = jsonDecode(message);
              final eventType = parsedMessage["event"];
              final type = parsedMessage["type"];
              if (eventType == 'setAuthCookie') {
                final authToken = parsedMessage["data"]["widgetAuthToken"];
                StoreHelper.storeCookie(authToken);
              }
            }
          })
          ..loadRequest(Uri.parse(webviewUrl));

        if (Platform.isAndroid && widget.onAttachFile != null) {
          final androidController = _controller!.platform
              as webview_flutter_android.AndroidWebViewController;
          androidController
              .setOnShowFileSelector((_) => widget.onAttachFile!.call());
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return _controller != null
        ? WebViewWidget(
            gestureRecognizers: {
              Factory<VerticalDragGestureRecognizer>(
                () => VerticalDragGestureRecognizer(),
              )
            },
            controller: _controller!,
          )
        : SizedBox();
  }

  _goToUrl(String url) {
    launchUrl(Uri.parse(url));
  }

  Future<void> _onListCookies(BuildContext context) async {
    final String cookies = await _controller
        ?.runJavaScriptReturningResult('document.cookie') as String;
    // if (context.mounted) {
    //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    //     content: Column(
    //       mainAxisAlignment: MainAxisAlignment.end,
    //       mainAxisSize: MainAxisSize.min,
    //       children: <Widget>[
    //         const Text('Cookies:'),
    //         _getCookieList(cookies),
    //       ],
    //     ),
    //   ));
    // }
  }
}
