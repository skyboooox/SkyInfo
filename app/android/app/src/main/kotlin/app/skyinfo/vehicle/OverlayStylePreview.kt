package app.skyinfo.vehicle

import org.json.JSONObject

internal fun overlayAppearancePatch(style: JSONObject): JSONObject {
    val patch = JSONObject()
    style.keys().forEach { key ->
        require(key in setOf("overlayFont","overlayOpacity"))
        val value = style.get(key) as? Number ?: throw IllegalArgumentException()
        val number = value.toDouble()
        require(number.isFinite() && if (key == "overlayFont") number in listOf(14.0,16.0,18.0,20.0,24.0) else number in 0.1..0.8)
        patch.put(key,value)
    }
    return patch
}

internal fun overlayStylePatch(style: JSONObject): JSONObject {
    require(style.keys().asSequence().all { it == "overlayOpacity" })
    return overlayAppearancePatch(style)
}
