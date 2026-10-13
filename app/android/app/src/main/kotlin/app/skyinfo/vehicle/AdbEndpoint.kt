package app.skyinfo.vehicle

import org.json.JSONObject

internal data class AdbEndpoint(val host: String, val port: Int, val enabled: Boolean, val mode: String) {
    companion object {
        fun from(config: JSONObject): AdbEndpoint {
            for (key in listOf("adbHost", "adbMode")) if (config.has(key)) require(config.get(key) is String)
            if (config.has("adbPort")) { val value = config.get("adbPort"); require(value is Number && value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble()) }
            val host = config.optString("adbHost", "127.0.0.1").trim()
            val port = config.optInt("adbPort", 5555)
            val mode = config.optString("adbMode", "tcp")
            require(host.isNotEmpty() && host.length <= 253 && !host.any { it.isWhitespace() || it in "/@'\";\\" }) { "invalid_adb_host" }
            require(port in 1..65535 && mode in setOf("tcp", "pair")) { "invalid_adb_endpoint" }
            if (config.has("adbEnabled")) require(config.get("adbEnabled") is Boolean)
            return AdbEndpoint(host, port, config.optBoolean("adbEnabled"), mode)
        }
    }
}

internal fun shellArgument(value: String): String = "'" + value.replace("'", "'\"'\"'") + "'"
internal fun bridgeShell(command: Array<String>, environment: Array<String>): String =
    "exec env " + environment.filter { it.startsWith("CLASSPATH=") }.joinToString(" ", transform = ::shellArgument) +
        " " + command.joinToString(" ", transform = ::shellArgument)
