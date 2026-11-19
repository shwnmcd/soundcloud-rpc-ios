package com.soundcloudrpc.android.ui

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

private const val SNIFFER_JS = """
(function(){
  if (window.__scAndroidSniff) return;
  window.__scAndroidSniff = true;
  function check(url) {
    if (!url || typeof url !== 'string') return;
    var m = url.match(/[?&]client_id=([a-zA-Z0-9_-]{16,})/);
    if (m && m[1] && window.SCAndroidBridge) {
      window.SCAndroidBridge.onClientId(m[1]);
    }
  }
  var of = window.fetch;
  if (of) {
    window.fetch = function(input) {
      check(typeof input === 'string' ? input : (input && input.url));
      return of.apply(this, arguments);
    };
  }
  var oo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, url) {
    check(url);
    return oo.apply(this, arguments);
  };
})();
"""

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SignInWebViewScreen(
    onSignedIn: (token: String, clientId: String) -> Unit,
    onClose: () -> Unit
) {
    var capturedClientId by remember { mutableStateOf("") }
    var capturedToken by remember { mutableStateOf("") }
    var completed by remember { mutableStateOf(false) }

    fun tryComplete() {
        val cookies = CookieManager.getInstance().getCookie("https://soundcloud.com") ?: ""
        val tokenMatch = Regex("""oauth_token=([^;]+)""").find(cookies)
        if (tokenMatch != null) {
            capturedToken = tokenMatch.groupValues[1].trim()
        }
        if (!completed && capturedToken.isNotBlank() && capturedClientId.isNotBlank()) {
            completed = true
            onSignedIn(capturedToken, capturedClientId)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF111111))
            .statusBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
            }
            Text(
                text = "Sign in to SoundCloud",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleMedium
            )
        }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString =
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                    addJavascriptInterface(object {
                        @JavascriptInterface
                        fun onClientId(id: String) {
                            capturedClientId = id
                            post { tryComplete() }
                        }
                    }, "SCAndroidBridge")

                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            view?.evaluateJavascript(SNIFFER_JS, null)
                            tryComplete()
                            // Once logged in on soundcloud.com, load /discover to guarantee client_id fires
                            if (capturedToken.isNotBlank() && capturedClientId.isBlank() && url?.contains("discover") == false) {
                                view?.loadUrl("https://soundcloud.com/discover")
                            }
                        }

                        override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): android.webkit.WebResourceResponse? {
                            val reqUrl = request?.url?.toString() ?: ""
                            val m = Regex("""[?&]client_id=([a-zA-Z0-9_-]{16,})""").find(reqUrl)
                            if (m != null) {
                                capturedClientId = m.groupValues[1]
                                post { tryComplete() }
                            }
                            return super.shouldInterceptRequest(view, request)
                        }
                    }

                    loadUrl("https://soundcloud.com/signin")
                }
            }
        )
    }
}
