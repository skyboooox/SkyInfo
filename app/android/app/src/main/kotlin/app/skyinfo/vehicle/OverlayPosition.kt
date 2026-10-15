package app.skyinfo.vehicle

import kotlin.math.roundToInt

internal fun maximumStripWidth(screen: Int, density: Float): Int =
    (screen - (32 * density).roundToInt()).coerceAtLeast(1)

internal fun floatingCoordinate(fraction: Double?, initial: Int, screen: Int, size: Int): Int =
    (fraction?.let { (it * (screen - size).coerceAtLeast(0)).roundToInt() } ?: initial).coerceIn(0,(screen-size).coerceAtLeast(0))

internal fun overlayHit(x: Float, y: Float, width: Int, height: Int): Boolean =
    x >= 0 && y >= 0 && x < width && y < height
