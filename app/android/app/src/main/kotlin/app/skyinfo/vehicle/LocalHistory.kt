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

class LocalHistory(private val context: Context, private val capacityBytes: Long = CAPACITY_BYTES,
    private val scheduleFlush: ((Long, () -> Unit) -> java.util.concurrent.Future<*>)? = null,
    private val performance: PerformanceProbe? = null) {
    private data class Row(val id: String, val at: Long, val value: Double?, val state: String, val segment: String, val sample: String?) {
        val bytes: Long get() = 64L + 3L*(id.length+state.length+segment.length+(sample?.length ?: 0))
    }
    private val pending = mutableListOf<Row>()
    private var pendingBytes = 0L
    private val batchBytes = minOf(BUFFER_BYTES,(capacityBytes/4).coerceAtLeast(4096))
    private var flushTask: java.util.concurrent.Future<*>? = null
    private var transactions = 0L
    private var writeError: String? = null
    private val gaps = mutableMapOf<String,Row>()
    private var unrecordedSamples = 0L
    private var retryWriteAt = 0L
    private var transactionAttempts = 0L
    private var deferredConfig: JSONObject? = null
    private var loggedWriteError: String? = null
    private fun failedWrite(error: android.database.sqlite.SQLiteException) {
        writeError = error.javaClass.simpleName
        retryWriteAt = android.os.SystemClock.elapsedRealtime()+1000
        if (loggedWriteError != writeError) {
            loggedWriteError = writeError
            android.util.Log.w("SkyInfo.Vehicle","Local history batch pending",error)
        }
    }
    private fun selectedIds(config: JSONObject) = config.optJSONArray("tiles")?.let { tiles ->
        (0 until tiles.length()).flatMap { RuntimeCoordinator.list(tiles.getJSONObject(it).optJSONArray("fields")) }.toSet()
    } ?: emptySet()
    companion object {
        const val CAPACITY_BYTES = 200L * 1024 * 1024
        const val BUFFER_BYTES = 1024L * 1024
        const val MAX_BUFFER_ROWS = 4096
        const val FLUSH_INTERVAL_SECONDS = 120L
    }
    private var database: SQLiteDatabase? = null
    private var persistent = false
    private var minutes = 30
    private var ids = setOf<String>()
    private var lastPrune = 0L
    private var recording = false
    private val session = UUID.randomUUID().toString()
    private val sessionFile = java.io.File(context.cacheDir,"skyinfo-session-history.db")
    @Synchronized fun configure(config: JSONObject) {
        deferredConfig = null
        try { configureStorage(config) }
        catch (error: android.database.sqlite.SQLiteException) {
            failedWrite(error)
            recording = config.optBoolean("localHistory",true)
            ids = selectedIds(config); minutes = config.optInt("localHistoryMinutes",30).coerceIn(1,1440)
            deferredConfig = JSONObject(config.toString())
            schedule()
        }
    }
    private fun configureStorage(config: JSONObject) {
        flush()
        val nextRecording = config.optBoolean("localHistory",true)
        val nextIds = selectedIds(config)
        if (recording) ids.filter { !nextRecording || it !in nextIds }.forEach { id ->
            append(id, JSONObject().put("quality", "paused").put("receivedAt", System.currentTimeMillis()))
        }
        flush()
        recording = nextRecording
        val keep = config.optBoolean("retainHistory")
        minutes = config.optInt("localHistoryMinutes", 30).coerceIn(1, 1440)
        ids = nextIds
        if (!recording && database == null && !keep && pending.isEmpty() && gaps.isEmpty()) { SQLiteDatabase.deleteDatabase(sessionFile);return }
        if (database != null && persistent == keep) { prune(); writeError = null; loggedWriteError = null; retryWriteAt = 0; return }
        val previous = database
        val previousFile = if (persistent) context.getDatabasePath("mqtt-history.db") else sessionFile
        if (previous == null) SQLiteDatabase.deleteDatabase(sessionFile)
        val file = if (keep) context.getDatabasePath("mqtt-history.db") else sessionFile
        val nextDatabase = SQLiteDatabase.openOrCreateDatabase(file.apply { parentFile?.mkdirs() },null)
        try {
        nextDatabase.apply {
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
            val next = nextDatabase
            next.beginTransaction()
            try {
                next.execSQL("DELETE FROM samples")
                previous.rawQuery("SELECT id,at,value,state,segment,sample FROM samples ORDER BY seq",null).use { cursor ->
                    while (cursor.moveToNext()) next.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)",arrayOf<Any?>(
                        cursor.getString(0),cursor.getLong(1),if (cursor.isNull(2)) null else cursor.getDouble(2),cursor.getString(3),cursor.getString(4),cursor.getString(5)))
                }
                next.setTransactionSuccessful()
            } finally { next.endTransaction() }
        }
        } catch (error: Throwable) { nextDatabase.close(); throw error }
        database = nextDatabase; persistent = keep
        previous?.close()
        if (previous != null) SQLiteDatabase.deleteDatabase(previousFile)
        flush()
        prune()
        writeError = null; loggedWriteError = null; retryWriteAt = 0
    }
    @Synchronized fun append(id: String, sample: JSONObject) {
        if (!recording || id !in ids) return
        val valid = sample.optString("quality") in listOf("available", "unverified") && sample.has("value")
        val value = if (valid) sample.opt("value") else null
        val at = sample.optLong("receivedAt", System.currentTimeMillis())
        val segment = "$session|$id|${sample.optLong("sourceEpoch")}|${sample.optString("quality")}|${sample.optString("unit")}|${sample.optInt("definitionVersion",1)}"
        val encoded = performance?.beginTiming() ?: 0L
        val row = Row(id,at,(value as? Number)?.toDouble()?.takeIf { it.isFinite() },
            if (valid) sample.optString("stateLabel",value?.toString() ?: "unavailable") else "unavailable",segment,sample.toString())
        performance?.timing("history_append_encode",encoded)
        performance?.add("history_append_rows")
        performance?.add("history_append_sample_chars",row.sample?.length?.toLong() ?: 0)
        performance?.add("history_append_estimated_bytes",row.bytes)
        if (pending.size >= MAX_BUFFER_ROWS || (pending.isNotEmpty() && pendingBytes+row.bytes > batchBytes) || gaps.isNotEmpty()) {
            val retryAllowed = android.os.SystemClock.elapsedRealtime() >= retryWriteAt
            val recovered = database != null && retryAllowed && try { flush(); true } catch (_: android.database.sqlite.SQLiteException) { false }
            if (!recovered) {
                unrecordedSamples++
                val firstAt = gaps[id]?.at ?: at
                val gap = JSONObject().put("quality","storage_error").put("receivedAt",firstAt).put("lostUntil",at).put("source",id)
                gaps[id] = Row(id,firstAt,null,"unavailable","$session|$id|storage_error",gap.toString())
                return
            }
        }
        pending.add(row); pendingBytes += row.bytes
        if ((pending.size >= MAX_BUFFER_ROWS || pendingBytes >= batchBytes) && database != null) {
            try { flush() } catch (_: android.database.sqlite.SQLiteException) { /* Retain this full batch for recovery. */ }
        } else schedule()
    }
    private fun schedule() {
        if ((pending.isNotEmpty() || gaps.isNotEmpty() || deferredConfig != null) && flushTask == null) flushTask = scheduleFlush?.invoke(if (writeError != null || deferredConfig != null) 1 else FLUSH_INTERVAL_SECONDS) {
            synchronized(this) {
                flushTask = null
                try {
                    flush()
                    deferredConfig?.let { configure(it) }
                } catch (error: android.database.sqlite.SQLiteException) {
                    failedWrite(error)
                    schedule()
                }
            }
        }
    }
    @Synchronized fun flush() {
        val db = database ?: return
        flushTask?.cancel(false); flushTask = null
        if (pending.isEmpty() && gaps.isEmpty()) return
        val measured = performance?.beginTiming() ?: 0L
        val rows = pending + gaps.values
        val maintenance = android.os.SystemClock.elapsedRealtime() - lastPrune >= 60000
        fun commit() {
            transactionAttempts++
            performance?.add("history_transaction_attempts")
            db.beginTransaction()
            var failure: Throwable? = null
            try {
                db.compileStatement("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)").use { statement ->
                    for (row in rows) {
                        statement.clearBindings(); statement.bindString(1,row.id); statement.bindLong(2,row.at)
                        row.value?.let { statement.bindDouble(3,it) } ?: statement.bindNull(3)
                        statement.bindString(4,row.state); statement.bindString(5,row.segment)
                        row.sample?.let { statement.bindString(6,it) } ?: statement.bindNull(6)
                        statement.executeInsert()
                    }
                }
                if (maintenance) deleteExpired(db)
                db.setTransactionSuccessful()
            } catch (error: Throwable) { failure = error; throw error }
            finally {
                try { db.endTransaction() }
                catch (cleanup: Throwable) { if (failure == null) throw cleanup else failure.addSuppressed(cleanup) }
            }
        }
        try {
            while (true) {
                try { commit(); break }
                catch (error: android.database.sqlite.SQLiteFullException) {
                    if (!reclaimOldestWindow(db)) throw error
                }
            }
            transactions++
            performance?.add("history_committed_rows",rows.size.toLong())
            performance?.add("history_transactions")
            if (maintenance) lastPrune = android.os.SystemClock.elapsedRealtime()
            pending.clear(); pendingBytes = 0; gaps.clear(); writeError = null; loggedWriteError = null; retryWriteAt = 0
        } catch (error: android.database.sqlite.SQLiteException) { failedWrite(error); schedule(); throw error }
        finally { performance?.timing("history_flush",measured) }
    }
    private fun reclaimOldestWindow(db: SQLiteDatabase): Boolean {
        val cutoff = db.rawQuery("SELECT MIN(at),MAX(at) FROM samples WHERE seq NOT IN (SELECT (SELECT seq FROM samples latest WHERE latest.id=known.id ORDER BY latest.at DESC,latest.seq DESC LIMIT 1) FROM samples known GROUP BY known.id)",null).use { cursor ->
            if (!cursor.moveToFirst() || cursor.isNull(0)) return false
            cursor.getLong(0) + (cursor.getLong(1)-cursor.getLong(0))/10
        }
        db.execSQL("DELETE FROM samples WHERE at<=? AND seq NOT IN (SELECT (SELECT seq FROM samples latest WHERE latest.id=known.id ORDER BY latest.at DESC,latest.seq DESC LIMIT 1) FROM samples known GROUP BY known.id)",arrayOf(cutoff))
        return db.rawQuery("SELECT changes()",null).use { it.moveToFirst(); it.getLong(0) > 0 }
    }
    @Synchronized fun storageStats(): JSONObject {
        val db = database ?: return JSONObject().put("budgetBytes",capacityBytes).put("open",false).put("writeError",writeError ?: JSONObject.NULL).put("unrecordedSamples",unrecordedSamples)
            .put("bufferedSamples",pending.size).put("bufferedBytes",pendingBytes).put("bufferBudgetBytes",batchBytes).put("bufferRowLimit",MAX_BUFFER_ROWS).put("flushIntervalSeconds",FLUSH_INTERVAL_SECONDS).put("pendingGaps",gaps.size).put("transactionAttempts",transactionAttempts)
        fun pragma(name: String) = db.rawQuery("PRAGMA $name",null).use { c -> c.moveToFirst();c.getLong(0) }
        val size = db.pageSize
        return JSONObject().put("budgetBytes",capacityBytes).put("maximumBytes",db.maximumSize)
            .put("allocatedBytes",pragma("page_count")*size).put("freeBytes",pragma("freelist_count")*size).put("open",true)
            .put("storage","sqlite_file").put("retainedAcrossStarts",persistent)
            .put("bufferedSamples",pending.size).put("bufferedBytes",pendingBytes).put("bufferBudgetBytes",batchBytes).put("bufferRowLimit",MAX_BUFFER_ROWS).put("flushIntervalSeconds",FLUSH_INTERVAL_SECONDS).put("batchTransactions",transactions).put("writeError",writeError ?: JSONObject.NULL)
            .put("unrecordedSamples",unrecordedSamples).put("pendingGaps",gaps.size).put("transactionAttempts",transactionAttempts)
    }
    private fun prune() {
        val db = database ?: return
        deleteExpired(db)
        lastPrune = android.os.SystemClock.elapsedRealtime()
    }
    private fun deleteExpired(db: SQLiteDatabase) {
        val measured = performance?.beginTiming() ?: 0L
        val cutoff = System.currentTimeMillis() - minutes * 60000L
        try { db.execSQL("DELETE FROM samples WHERE at < ? AND seq NOT IN (SELECT (SELECT seq FROM samples latest WHERE latest.id=expired.id AND latest.at<? ORDER BY latest.at DESC,latest.seq DESC LIMIT 1) FROM samples expired WHERE expired.at<? GROUP BY expired.id)", arrayOf(cutoff,cutoff,cutoff)) }
        finally { performance?.timing("history_prune",measured) }
    }
    @Synchronized fun query(id: String, window: Int, field: JSONObject? = null, includeSample: Boolean = true): JSONObject {
        val db = database ?: return JSONObject().put("error", NativeStrings.text_fdedaa14ba)
        val measured = performance?.beginTiming() ?: 0L
        val points = JSONArray()
        val rows = mutableListOf<Row>()
        val queriedAt = System.currentTimeMillis()
        val from = queriedAt - minOf(window,minutes)*60000L
        db.rawQuery(if (includeSample) HISTORY_WINDOW_QUERY else HISTORY_WINDOW_LIGHT_QUERY,
            arrayOf(id,from.toString(),queriedAt.toString(),id,from.toString(),queriedAt.toString())).use { cursor ->
            while (cursor.moveToNext()) rows.add(Row(id,cursor.getLong(0),if (cursor.isNull(1)) null else cursor.getDouble(1),cursor.getString(2),cursor.getString(3),if (cursor.isNull(4)) null else cursor.getString(4)))
        }
        rows.addAll((pending + gaps.values).filter { it.id == id && it.at <= queriedAt })
        val ordered = rows.sortedBy { it.at }
        val predecessor = ordered.indexOfLast { it.at < from }
        var returnedSampleChars = 0L
        for ((index,row) in ordered.withIndex()) {
            if (row.at < from && index != predecessor) continue
                if (measured != 0L && includeSample) returnedSampleChars += row.sample?.length ?: 0
                val segment = row.segment
                val legacy = (field?.has("valueOffset") == true || field?.has("valueScale") == true) && segment.substringAfterLast('|').toIntOrNull() == 1
                val unitMismatch = field?.has("unitField") == true && (field.optString("unit").isEmpty() ||
                    segment.substringAfterLast('|').toIntOrNull() != field.optInt("definitionVersion",1) ||
                    segment.substringBeforeLast('|').substringAfterLast('|') != field.optString("unit"))
                val invalidLegacyCurrent = legacy && id == BATTERY_CURRENT && row.value != null && invalidGbCurrentRaw(row.value)
                val value = if ((row.value == null) || unitMismatch || invalidLegacyCurrent) null else if (legacy) (decodeReading(row.value, field) as Number).toDouble() else row.value
                points.put(JSONObject().put("at", Instant.ofEpochMilli(row.at).toString())
                    .put("value", value ?: JSONObject.NULL).put("state", if (unitMismatch || invalidLegacyCurrent) "unavailable" else if (legacy && value != null) value.toString() else field?.optJSONObject("stateLabels")?.optString(row.state)?.takeIf(String::isNotEmpty) ?: row.state)
                    .put("segment", if (legacy) "$segment|converted:${field.optInt("definitionVersion",1)}" else segment)
                    .also { point -> if (includeSample) point.put("sample",if (row.sample == null) JSONObject.NULL else JSONObject(row.sample)) })
        }
        if (points.length() > 0 && recording && id in ids) {
            val last = points.getJSONObject(points.length()-1)
            if (!last.isNull("value") && last.getString("segment").startsWith("$session|")) last.put("observedUntil",queriedAt)
        }
        performance?.add("history_queries"); performance?.add("history_returned_points",points.length().toLong())
        performance?.add("history_returned_sample_chars",returnedSampleChars)
        performance?.timing("history_query",measured)
        return JSONObject().put("points", points).put("queriedAt",queriedAt)
    }
    @Synchronized fun performanceSettings(): JSONObject {
        val db = database ?: return JSONObject().put("open",false)
        val result = JSONObject().put("open",true)
        try {
            for (key in listOf("journal_mode","synchronous","page_size","wal_autocheckpoint","cache_size","cache_spill")) {
                db.rawQuery("PRAGMA $key",null).use { cursor -> if (cursor.moveToFirst()) result.put(key,cursor.getString(0)) }
            }
        } catch (error: android.database.sqlite.SQLiteException) { result.put("error",error.javaClass.simpleName) }
        return result
    }
    @Synchronized fun pause() {
        if (recording) ids.forEach { append(it,JSONObject().put("quality","paused").put("receivedAt",System.currentTimeMillis())) }
        recording = false
        deferredConfig?.put("localHistory",false)
        try { flush() } catch (_: android.database.sqlite.SQLiteException) { /* Diagnostics retain the pending batch. */ }
    }
    @Synchronized fun close() {
        try { flush() } catch (_: android.database.sqlite.SQLiteException) { return }
        database?.close(); database = null
    }
    @Synchronized fun clear() {
        flushTask?.cancel(false); flushTask = null; pending.clear(); pendingBytes = 0; gaps.clear(); writeError = null; unrecordedSamples = 0; retryWriteAt = 0; deferredConfig = null; loggedWriteError = null
        database?.close(); database = null
        context.deleteDatabase("mqtt-history.db"); SQLiteDatabase.deleteDatabase(sessionFile)
    }
}

/** The visible range and its predecessor use separate ranges of the existing field/time index. */
internal const val HISTORY_WINDOW_QUERY = "SELECT at,value,state,segment,sample,seq FROM samples WHERE id=? AND at>=? AND at<=? UNION ALL SELECT at,value,state,segment,sample,seq FROM (SELECT at,value,state,segment,sample,seq FROM samples WHERE id=? AND at<? AND at<=? ORDER BY at DESC,seq DESC LIMIT 1) ORDER BY at,seq"
/** Identical ranges/order; the UI does not need stored sample JSON. */
internal val HISTORY_WINDOW_LIGHT_QUERY = HISTORY_WINDOW_QUERY.replace("segment,sample,seq","segment,NULL AS sample,seq")
