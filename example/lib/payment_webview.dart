import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a hosted-checkout page (the `redirect_url` returned by
/// signup / setupPaymentMethod / checkout) inside the app.
///
/// The card is still entered on NjiaPay's hosted page — we never touch the PAN,
/// so this stays in the light PCI scope — but the user never leaves the app.
/// When the hosted flow finishes it redirects to the storefront `return_url`;
/// we watch for that, cancel the navigation (so the storefront never loads),
/// and pop back to the app.
///
/// Pops `true` when the return_url was reached (flow completed — the caller
/// should refresh and read the real result), or `false` if the user closed it.
class PaymentWebView extends StatefulWidget {
  const PaymentWebView({
    super.key,
    required this.url,
    required this.returnUrlPrefix,
  });

  /// The hosted-checkout URL to load.
  final String url;

  /// When navigation reaches a URL starting with this, the flow is done.
  final String returnUrlPrefix;

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  bool _returned = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isReturn(request.url)) {
              // Flow finished — don't load the storefront, just come back.
              _finish();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // Android WebView doesn't always fire onNavigationRequest for
          // server-side (3xx) redirects — and the return to the storefront IS
          // such a redirect — so also catch the landing here.
          onPageStarted: (url) {
            if (_isReturn(url)) {
              _finish();
            } else if (mounted) {
              setState(() => _loading = true);
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// True once navigation reaches the storefront return_url. Matches on host
  /// (robust to path/query differences on the way back) or the exact prefix.
  bool _isReturn(String url) {
    // Deliberately not logged: the hosted-payment URL carries a session token
    // in its query string, which shouldn't land in device logs.
    final target = Uri.tryParse(url);
    final ret = Uri.tryParse(widget.returnUrlPrefix);
    if (target == null || ret == null) return false;
    return (ret.host.isNotEmpty && target.host == ret.host) ||
        url.startsWith(widget.returnUrlPrefix);
  }

  void _finish() {
    if (_returned) return;
    _returned = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    // Stop any in-flight load so the native WebView doesn't keep working after
    // the page is popped (the post-payment jank we observed).
    _controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
