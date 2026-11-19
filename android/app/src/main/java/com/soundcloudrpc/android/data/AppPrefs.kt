package com.soundcloudrpc.android.data

import android.content.Context
import android.content.SharedPreferences

class AppPrefs(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("soundcloud_rpc_prefs", Context.MODE_PRIVATE)

    var oauthToken: String
        get() = prefs.getString("oauth_token", "") ?: ""
        set(v) = prefs.edit().putString("oauth_token", v).apply()

    var clientId: String
        get() = prefs.getString("client_id", "") ?: ""
        set(v) = prefs.edit().putString("client_id", v).apply()

    var trackParserEnabled: Boolean
        get() = prefs.getBoolean("track_parser", true)
        set(v) = prefs.edit().putBoolean("track_parser", v).apply()

    var rpcEnabled: Boolean
        get() = prefs.getBoolean("rpc_enabled", true)
        set(v) = prefs.edit().putBoolean("rpc_enabled", v).apply()

    var rpcRelayUrl: String
        get() = prefs.getString("rpc_relay_url", "") ?: ""
        set(v) = prefs.edit().putString("rpc_relay_url", v).apply()

    var lastFmEnabled: Boolean
        get() = prefs.getBoolean("lfm_enabled", false)
        set(v) = prefs.edit().putBoolean("lfm_enabled", v).apply()

    var lastFmApiKey: String
        get() = prefs.getString("lfm_api_key", "") ?: ""
        set(v) = prefs.edit().putString("lfm_api_key", v).apply()

    var lastFmSecret: String
        get() = prefs.getString("lfm_secret", "") ?: ""
        set(v) = prefs.edit().putString("lfm_secret", v).apply()

    var lastFmSessionKey: String
        get() = prefs.getString("lfm_session_key", "") ?: ""
        set(v) = prefs.edit().putString("lfm_session_key", v).apply()

    var webhookEnabled: Boolean
        get() = prefs.getBoolean("wh_enabled", false)
        set(v) = prefs.edit().putBoolean("wh_enabled", v).apply()

    var webhookUrl: String
        get() = prefs.getString("wh_url", "") ?: ""
        set(v) = prefs.edit().putString("wh_url", v).apply()

    var webhookDiscordFormat: Boolean
        get() = prefs.getBoolean("wh_discord", false)
        set(v) = prefs.edit().putBoolean("wh_discord", v).apply()

    var webhookTriggerPercent: Int
        get() = prefs.getInt("wh_percent", 50)
        set(v) = prefs.edit().putInt("wh_percent", v).apply()
}
