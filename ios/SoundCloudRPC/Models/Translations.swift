import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case es = "es"
    case ptBR = "pt-BR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .es: return "Español"
        case .ptBR: return "Português (BR)"
        }
    }
}

enum Translations {
    static func text(_ key: String, language: AppLanguage) -> String {
        switch language {
        case .en: return en[key] ?? key
        case .es: return es[key] ?? en[key] ?? key
        case .ptBR: return ptBR[key] ?? en[key] ?? key
        }
    }

    private static let en: [String: String] = [
        "listenOnSoundcloud": "Listen on SoundCloud",
        "listeningToSoundcloud": "Listening to SoundCloud",
        "client": "Client",
        "darkMode": "Enable Dark Mode",
        "adBlocker": "AdBlocker",
        "enableAdBlocker": "Enable AdBlocker",
        "desktopMode": "Desktop Web Player Mode",
        "desktopModeDesc": "Loads full SoundCloud desktop player with waveforms, track monitoring, and dark mode",
        "enableNavigationControls": "Show Navigation Bar",
        "enableTrackParser": "Enable Track Parser",
        "trackParserDescription": "Parse track titles to extract artist and track names automatically",
        "lastfm": "Last.fm",
        "enableLastFm": "Enable Scrobbling",
        "lastFmApiKey": "Last.fm API Key",
        "lastFmApiSecret": "Last.fm API Secret",
        "connectLastFm": "Authenticate with Last.fm",
        "disconnectLastFm": "Disconnect Last.fm",
        "connected": "Connected",
        "notConnected": "Not Connected",
        "webhooks": "Webhooks",
        "enableWebhooks": "Enable Webhooks",
        "webhookUrl": "Webhook URL",
        "webhookTrigger": "Trigger at",
        "webhookDescription": "Send track data to a webhook URL when playback reaches the specified percentage",
        "discord": "Discord",
        "enableRichPresence": "Enable Rich Presence",
        "displayWhenPaused": "Display when paused",
        "displaySmallIcon": "Display small icon",
        "displayButtons": "Display buttons",
        "useArtistInStatusLine": "Display artist name instead of application name",
        "richPresencePreviewTitle": "Rich Presence Preview",
        "noActivityToShow": "No activity to show",
        "customThemes": "Themes",
        "selectCustomTheme": "Active Theme",
        "noTheme": "No Theme",
        "plugins": "Plugins",
        "noPluginsFound": "No plugins added yet",
        "settings": "Settings",
        "done": "Done",
        "testWebhook": "Send Test Payload"
    ]

    private static let es: [String: String] = [
        "listenOnSoundcloud": "Escuchar en SoundCloud",
        "listeningToSoundcloud": "Escuchando SoundCloud",
        "client": "Cliente",
        "darkMode": "Activar Modo Oscuro",
        "adBlocker": "Bloqueador de anuncios",
        "enableAdBlocker": "Activar Bloqueador de anuncios",
        "desktopMode": "Modo Reproductor de Escritorio",
        "desktopModeDesc": "Carga el reproductor completo de SoundCloud con formas de onda y monitoreo",
        "enableNavigationControls": "Mostrar barra de navegación",
        "enableTrackParser": "Activar analizador de pistas",
        "trackParserDescription": "Analiza los títulos para extraer automáticamente el artista y la canción",
        "lastfm": "Last.fm",
        "enableLastFm": "Activar Scrobbling",
        "lastFmApiKey": "Clave API de Last.fm",
        "lastFmApiSecret": "Secreto API de Last.fm",
        "connectLastFm": "Autenticar con Last.fm",
        "disconnectLastFm": "Desconectar Last.fm",
        "connected": "Conectado",
        "notConnected": "No conectado",
        "webhooks": "Webhooks",
        "enableWebhooks": "Activar Webhooks",
        "webhookUrl": "URL del Webhook",
        "webhookTrigger": "Activar al",
        "webhookDescription": "Envía datos de la pista a un webhook al alcanzar el porcentaje indicado",
        "discord": "Discord",
        "enableRichPresence": "Activar Rich Presence",
        "displayWhenPaused": "Mostrar cuando esté pausado",
        "displaySmallIcon": "Mostrar icono pequeño",
        "displayButtons": "Mostrar botones",
        "useArtistInStatusLine": "Mostrar nombre del artista en lugar de la app",
        "richPresencePreviewTitle": "Vista previa de Rich Presence",
        "noActivityToShow": "Sin actividad para mostrar",
        "customThemes": "Temas",
        "selectCustomTheme": "Tema activo",
        "noTheme": "Sin tema",
        "plugins": "Complementos",
        "noPluginsFound": "No se encontraron complementos",
        "settings": "Ajustes",
        "done": "Listo",
        "testWebhook": "Enviar prueba"
    ]

    private static let ptBR: [String: String] = [
        "listenOnSoundcloud": "Ouvir no SoundCloud",
        "listeningToSoundcloud": "Ouvindo no SoundCloud",
        "client": "Cliente",
        "darkMode": "Ativar Modo Escuro",
        "adBlocker": "Bloqueador de anúncios",
        "enableAdBlocker": "Ativar Bloqueador de anúncios",
        "desktopMode": "Modo Player Desktop",
        "desktopModeDesc": "Carrega o player completo do SoundCloud com waveforms e monitoramento",
        "enableNavigationControls": "Mostrar barra de navegação",
        "enableTrackParser": "Ativar analisador de faixas",
        "trackParserDescription": "Analisa os títulos para extrair automaticamente artista e faixa",
        "lastfm": "Last.fm",
        "enableLastFm": "Ativar Scrobbling",
        "lastFmApiKey": "Chave API do Last.fm",
        "lastFmApiSecret": "Segredo API do Last.fm",
        "connectLastFm": "Autenticar no Last.fm",
        "disconnectLastFm": "Desconectar Last.fm",
        "connected": "Conectado",
        "notConnected": "Não conectado",
        "webhooks": "Webhooks",
        "enableWebhooks": "Ativar Webhooks",
        "webhookUrl": "URL do Webhook",
        "webhookTrigger": "Disparar em",
        "webhookDescription": "Envia dados da faixa para um webhook ao atingir a porcentagem definida",
        "discord": "Discord",
        "enableRichPresence": "Ativar Rich Presence",
        "displayWhenPaused": "Mostrar quando pausado",
        "displaySmallIcon": "Mostrar ícone pequeno",
        "displayButtons": "Mostrar botões",
        "useArtistInStatusLine": "Mostrar nome do artista no lugar do app",
        "richPresencePreviewTitle": "Prévia do Rich Presence",
        "noActivityToShow": "Nenhuma atividade para mostrar",
        "customThemes": "Temas",
        "selectCustomTheme": "Tema ativo",
        "noTheme": "Sem tema",
        "plugins": "Plugins",
        "noPluginsFound": "Nenhum plugin encontrado",
        "settings": "Configurações",
        "done": "Concluído",
        "testWebhook": "Enviar teste"
    ]
}
