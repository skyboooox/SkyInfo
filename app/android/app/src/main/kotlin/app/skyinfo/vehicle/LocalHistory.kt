package app.skyinfo.vehicle

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

fun migrateLocalHistory(config: JSONObject): Boolean {
    if (config.optInt("localHistoryPolicyVersion") >= 1) return false
    if (config.optString("connection", "ha") == "ha" || !config.has("localHistory")) config.put("localHistory",true)
    config.put("localHistoryPolicyVersion",1)
    return true
}

class LocalHistory(private val context: Context, private val capacityBytes: Long = CAPACITY_BYTES) {
    companion object { const val CAPACITY_BYTES = 200L * 1024 * 1024 }
    private var database: SQLiteDatabase? = null
    private var persistent = false
    private var minutes = 30
    private var ids = setOf<String>()
    private var lastPrune = 0L
    private var writes = 0
    private var recording = false
    private val session = UUID.randomUUID().toString()
    private val sessionFile = java.io.File(context.cacheDir,"skyinfo-session-history.db")
    fun configure(config: JSONObject) {
        val nextRecording = config.optBoolean("localHistory",true)
        val nextIds = config.optJSONArray("tiles")?.let { tiles -> (0 until tiles.length()).flatMap { RuntimeCoordinator.list(tiles.getJSONObject(it).optJSONArray("fields")) }.toSet() } ?: emptySet()
        if (recording) ids.filter { !nextRecording || it !in nextIds }.forEach { id ->
            append(id, JSONObject().put("quality", "paused").put("receivedAt", System.currentTimeMillis()))
        }
        recording = nextRecording
        val keep = config.optBoolean("retainHistory")
        minutes = config.optInt("localHistoryMinutes", 30).coerceIn(1, 1440)
        ids = nextIds
        if (!recording && database == null && !keep) { SQLiteDatabase.deleteDatabase(sessionFile);return }
        if (database != null && persistent == keep) { prune(); return }
        val previous = database
        val previousFile = if (persistent) context.getDatabasePath("mqtt-history.db") else sessionFile
        persistent = keep
        if (previous == null) SQLiteDatabase.deleteDatabase(sessionFile)
        val file = if (keep) context.getDatabasePath("mqtt-history.db") else sessionFile
        database = SQLiteDatabase.openOrCreateDatabase(file.apply { parentFile?.mkdirs() },null)
        database!!.apply {
            maximumSize = capacityBytes
            execSQL("CREATE TABLE IF NOT EXISTS samples (seq INTEGER PRIMARY KEY, id TEXT NOT NULL, at INTEGER NOT NULL, value REAL, state TEXT, segment TEXT NOT NULL, sample TEXT)")
            val hasSample = rawQuery("PRAGMA table_info(samples)",null).use { cursor ->
                var found = false
                while (cursor.moveToNext()) if (cursor.getString(1) == "sample") found = true
                found
            }
            if (!hasSample) execSQL("ALTER TABLE samples ADD COLUMN sample TEXT")
            execSQL("CREATE INDEX IF NOT EXISTS samples_id_at ON samples(id,at)")
        }
        if (previous != null) {
            val next = database!!
            next.beginTransaction()
            try {
                next.execSQL("DELETE FROM samples")
                previous.rawQuery("SELECT id,at,value,state,segment,sample FROM samples ORDER BY seq",null).use { cursor ->
                    while (cursor.moveToNext()) next.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)",arrayOf<Any?>(
                        cursor.getString(0),cursor.getLong(1),if (cursor.isNull(2)) null else cursor.getDouble(2),cursor.getString(3),cursor.getString(4),cursor.getString(5)))
                }
                next.setTransactionSuccessful()
            } finally { next.endTransaction(); previous.close() }
            SQLiteDatabase.deleteDatabase(previousFile)
        }
        prune()
    }
    fun append(id: String, sample: JSONObject) {
        val db = database ?: return
        if (!recording || id !in ids) return
        val valid = sample.optString("quality") in listOf("available", "unverified") && sample.has("value")
        val value = if (valid) sample.opt("value") else null
        val at = sample.optLong("receivedAt", System.currentTimeMillis())
        val segment = "$session|$id|${sample.optLong("sourceEpoch")}|${sample.optString("quality")}|${sample.optString("unit")}|${sample.optInt("definitionVersion",1)}"
        try {
            db.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)", arrayOf<Any?>(id, at,
                (value as? Number)?.toDouble()?.takeIf { it.isFinite() }, if (valid) sample.optString("stateLabel",value?.toString() ?: "unavailable") else "unavailable", segment,sample.toString()))
            writes++
            if (writes >= 256 || System.currentTimeMillis() - lastPrune >= 60000) prune()
        } catch (_: android.database.sqlite.SQLiteFullException) {
            reclaimOldestWindow(db)
            db.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)", arrayOf<Any?>(id, at,
                (value as? Number)?.toDouble()?.takeIf { it.isFinite() }, if (valid) sample.optString("stateLabel",value?.toString() ?: "unavailable") else "unavailable", segment,sample.toString()))
        }
    }
    private fun reclaimOldestWindow(db: SQLiteDatabase) {
        val cutoff = db.rawQuery("SELECT MIN(at),MAX(at) FROM samples",null).use { cursor ->
            if (!cursor.moveToFirst() || cursor.isNull(0)) return
            cursor.getLong(0) + (cursor.getLong(1)-cursor.getLong(0))/10
        }
        db.execSQL("DELETE FROM samples WHERE at<=? AND seq NOT IN (SELECT MAX(seq) FROM samples GROUP BY id)",arrayOf(cutoff))
    }
    fun storageStats(): JSONObject {
        val db = database ?: return JSONObject().put("budgetBytes",capacityBytes).put("open",false)
        fun pragma(name: String) = db.rawQuery("PRAGMA $name",null).use { c -> c.moveToFirst();c.getLong(0) }
        val size = db.pageSize
        return JSONObject().put("budgetBytes",capacityBytes).put("maximumBytes",db.maximumSize)
            .put("allocatedBytes",pragma("page_count")*size).put("freeBytes",pragma("freelist_count")*size).put("open",true)
            .put("storage","sqlite_file").put("retainedAcrossStarts",persistent)
    }
    private fun prune() {
        val db = database ?: return
        writes = 0; lastPrune = System.currentTimeMillis()
        val cutoff = System.currentTimeMillis() - minutes * 60000L
        db.execSQL("DELETE FROM samples WHERE at < ? AND seq NOT IN (SELECT MAX(seq) FROM samples WHERE at < ? GROUP BY id)", arrayOf(cutoff,cutoff))
    }
    fun query(id: String, window: Int, field: JSONObject? = null): JSONObject {
        val db = database ?: return JSONObject().put("error", NativeStrings.text_fdedaa14ba)
        prune()
        val points = JSONArray()
        val queriedAt = System.currentTimeMillis()
        val from = queriedAt - window*60000L
        db.rawQuery("SELECT at,value,state,segment,sample FROM samples WHERE id=? AND at<=? AND (at>=? OR seq=(SELECT seq FROM samples WHERE id=? AND at<? ORDER BY at DESC,seq DESC LIMIT 1)) ORDER BY at,seq",
            arrayOf(id,queriedAt.toString(),from.toString(),id,from.toString())).use { cursor ->
            while (cursor.moveToNext()) {
                val segment = cursor.getString(3)
                val legacy = (field?.has("valueOffset") == true || field?.has("valueScale") == true) && segment.substringAfterLast('|').toIntOrNull() == 1
                val unitMismatch = field?.has("unitField") == true && (field.optString("unit").isEmpty() ||
                    segment.substringAfterLast('|').toIntOrNull() != field.optInt("definitionVersion",1) ||
                    segment.substringBeforeLast('|').substringAfterLast('|') != field.optString("unit"))
                val invalidLegacyCurrent = legacy && id == BATTERY_CURRENT && !cursor.isNull(1) && invalidGbCurrentRaw(cursor.getDouble(1))
                val value = if (cursor.isNull(1) || unitMismatch || invalidLegacyCurrent) null else if (legacy) (decodeReading(cursor.getDouble(1), field!!) as Number).toDouble() else cursor.getDouble(1)
                points.put(JSONObject().put("at", Instant.ofEpochMilli(cursor.getLong(0)).toString())
                    .put("value", value ?: JSONObject.NULL).put("state", if (unitMismatch || invalidLegacyCurrent) "unavailable" else if (legacy && value != null) value.toString() else field?.optJSONObject("stateLabels")?.optString(cursor.getString(2))?.takeIf(String::isNotEmpty) ?: cursor.getString(2))
                    .put("segment", if (legacy) "$segment|converted:${field!!.optInt("definitionVersion",1)}" else segment)
                    .put("sample",if (cursor.isNull(4)) JSONObject.NULL else JSONObject(cursor.getString(4))))
            }
        }
        if (points.length() > 0 && recording && id in ids) {
            val last = points.getJSONObject(points.length()-1)
            if (!last.isNull("value") && last.getString("segment").startsWith("$session|")) last.put("observedUntil",queriedAt)
        }
        return JSONObject().put("points", points).put("queriedAt",queriedAt)
    }
    fun clear() { database?.execSQL("DELETE FROM samples"); database?.close(); database = null; context.deleteDatabase("mqtt-history.db");SQLiteDatabase.deleteDatabase(sessionFile) }
}
