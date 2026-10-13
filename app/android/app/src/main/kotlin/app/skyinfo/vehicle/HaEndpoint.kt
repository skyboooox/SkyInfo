package app.skyinfo.vehicle

import java.net.URI

object HaEndpoint {
    fun validate(url: String): URI = URI(url.trim()).also {
        require(it.scheme?.lowercase() in setOf("http", "https") && !it.host.isNullOrEmpty() &&
            it.userInfo == null && it.fragment == null && it.query == null &&
            (it.port == -1 || it.port in 1..65535)) { "invalid_ha_url" }
    }
    fun identity(url: String): String {
        if (url.isBlank()) return ""
        val uri = validate(url)
        val port = if (uri.port == -1) if (uri.scheme.equals("https",true)) 443 else 80 else uri.port
        return "${uri.scheme.lowercase()}://${uri.host.lowercase()}:$port${uri.path.orEmpty().trimEnd('/')}"
    }
}
