package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class RuntimeDataTest {
    private val id = "1032/7/1128267816"
    private fun fields() = mapOf(id to JSONObject().put("id",id).put("name","低压电压").put("unit","V").put("entityKey","low_voltage").put("displayAllowed",true))
    private fun config(mode: String = "ha", local: Boolean = false): JSONObject = JSONObject().put("schema",2).put("connection",mode)
        .put("localHistory",local).put("haUrl","http://192.168.10.20:8123/").put("prefix","skyinfo_demo")
        .put("tiles",JSONArray().put(JSONObject().put("id","a").put("title","电压").put("kind","number").put("fields",JSONArray().put(id))))
    private fun temperatures() = listOf("1014/5/1148190752", "1014/5/1148190736", "1014/5/1148190776").associateWith { key ->
        JSONObject().put("id",key).put("name","电池温度").put("unit","°C").put("valueOffset",-30)
            .put("definitionVersion",2).put("unitConfidence","user_supplied").put("entityKey",key.replace('/','_'))
    }
    @Test fun pairedUnitsUseSdkCodesAndKeepTheirRawReadings() {
        val temp="1000/5/1077936168"; val tempUnit="1000/5/1077936167"
        val fuel="1014/7/1246760996"; val fuelUnit="1007/5/1246761027"
        val catalog=mapOf(temp to JSONObject().put("unitField",tempUnit),fuel to JSONObject().put("unitField",fuelUnit),tempUnit to JSONObject(),fuelUnit to JSONObject())
        assertEquals(setOf(temp,tempUnit,fuel,fuelUnit),expandDependencies(setOf(temp,fuel),catalog))
        val degrees=JSONObject().put("raw",77).put("value",77).put("quality","unverified")
        resolvePairedUnit(temp,degrees,mapOf(tempUnit to JSONObject().put("value",0).put("quality","unverified")),catalog)
        assertEquals(25.0,degrees.getDouble("value"),0.0); assertEquals(77,degrees.getInt("raw")); assertEquals("°C",degrees.getString("unit"))
        val unpaired=JSONObject().put("raw",25).put("value",25).put("quality","unverified")
        resolvePairedUnit(temp,unpaired,emptyMap(),catalog)
        assertEquals("",unpaired.getString("unit")); assertEquals("unverified",unpaired.getString("quality"))
        for ((code,unit) in mapOf(1 to "L/100km",2 to "km/L",3 to "MPG",4 to "L/h")) {
            val sample=JSONObject().put("raw",13.9).put("value",13.9).put("quality","unverified")
            resolvePairedUnit(fuel,sample,mapOf(fuelUnit to JSONObject().put("value",code).put("quality","available")),catalog)
            assertEquals(unit,sample.getString("unit")); assertEquals(13.9,sample.getDouble("value"),0.0)
        }
    }
    @Test fun knownStateLabelsKeepNumericRawAndUnknownCodes() {
        val door="1001/5/692060168"
        val reader=ReadOnlyVehicle(mapOf(door to JSONObject().put("unit","").put("stateLabels",JSONObject().put("0","关闭").put("1","打开"))))
        val closed=reader.fromRaw(door,0)
        assertEquals("关闭",closed.getString("stateLabel")); assertEquals(0,closed.getInt("raw")); assertEquals(0,closed.getInt("value"))
        val unknown=reader.fromRaw(door,15)
        assertFalse(unknown.has("stateLabel")); assertEquals(15,unknown.getInt("value"))
    }
    @Test fun localPairedHistoryDoesNotConnectDifferentFuelUnits() {
        val fuel="1014/7/1246760996"; val cfg=config("mqtt",true)
        cfg.getJSONArray("tiles").getJSONObject(0).put("fields",JSONArray().put(fuel))
        val history=LocalHistory(RuntimeEnvironment.getApplication()); history.configure(cfg)
        history.append(fuel,JSONObject().put("value",13.9).put("quality","available").put("unit","L/100km").put("definitionVersion",2))
        history.append(fuel,JSONObject().put("value",1.2).put("quality","available").put("unit","L/h").put("definitionVersion",2))
        val points=history.query(fuel,30,JSONObject().put("unitField","1007/5/1246761027").put("unit","L/h").put("definitionVersion",2)).getJSONArray("points")
        assertTrue(points.getJSONObject(0).isNull("value")); assertEquals(1.2,points.getJSONObject(1).getDouble("value"),0.0)
    }
    @Test fun firstReadingInitializesChangeTimeAndSameValuesDoNotRefreshIt() {
        fun fresh(value: Int, at: Long, quality: String = "available") = JSONObject().put("value",value).put("receivedAt",at).put("quality",quality)
        val first = fresh(38,1000); stampSampleTimes(first,null,1)
        assertEquals(1000,first.getLong("changedAt")); assertEquals(1000,first.getLong("updatedAt"))
        val same = fresh(38,2000); stampSampleTimes(same,first,1)
        assertEquals(1000,same.getLong("changedAt")); assertEquals(2000,same.getLong("updatedAt"))
        val status = fresh(38,2500,"unverified"); stampSampleTimes(status,same,1)
        assertEquals(1000,status.getLong("changedAt"))
        val changed = fresh(39,3000); stampSampleTimes(changed,status,1)
        assertEquals(3000,changed.getLong("changedAt"))
        val reconnect = fresh(39,4000); stampSampleTimes(reconnect,changed,2)
        assertEquals(4000,reconnect.getLong("changedAt"))
    }
    @Test fun failedReadingKeepsBothClocksAndLegacySamplesGetABaseline() {
        val old = JSONObject().put("value",38).put("raw",68).put("updatedAt",1000).put("sourceEpoch",1)
        val same = JSONObject().put("value",38).put("receivedAt",2000); stampSampleTimes(same,old,1)
        assertEquals(1000,same.getLong("changedAt"))
        val failed = JSONObject().put("quality","disconnected").put("receivedAt",3000); stampSampleTimes(failed,same,2)
        assertEquals(1000,failed.getLong("changedAt")); assertEquals(2000,failed.getLong("updatedAt"))
        val empty = JSONObject().put("quality","permission"); stampSampleTimes(empty,null,1)
        assertFalse(empty.has("changedAt")); assertFalse(empty.has("updatedAt"))
    }
    @Test fun batteryTemperatureSubtracts30OnceAndKeepsRawAndOtherFields() {
        val catalog = temperatures() + fields()
        val reader = ReadOnlyVehicle(catalog)
        temperatures().keys.forEach { key ->
            val sample = reader.fromRaw(key,68)
            assertEquals(38.0,sample.getDouble("value"),0.0); assertEquals(68,sample.getInt("raw"))
            assertEquals("available",sample.getString("quality")); assertEquals(2,sample.getInt("definitionVersion"))
            assertEquals(-10.0,reader.fromRaw(key,20).getDouble("value"),0.0)
            assertEquals("invalid",reader.fromRaw(key,Float.NaN).getString("quality"))
        }
        assertEquals(13.7,reader.fromRaw(id,13.7).getDouble("value"),0.0)
    }
    @Test fun convertedDefaultsMigrateWithoutChangingCustomUnitsOrSelections() {
        val key = temperatures().keys.first()
        val cfg = config(); val tile = cfg.getJSONArray("tiles").getJSONObject(0)
        tile.put("units",JSONObject().put(key,"原值").put(id,"自定义"))
        cfg.put("overlays",JSONArray().put(JSONObject().put("field",key).put("unit","原值")))
            .put("uploaded",JSONArray().put(id))
        assertTrue(migrateConvertedUnits(cfg,temperatures()+fields()))
        assertFalse(tile.getJSONObject("units").has(key)); assertEquals("自定义",tile.getJSONObject("units").getString(id))
        assertEquals("°C",cfg.getJSONArray("overlays").getJSONObject(0).getString("unit"))
        assertEquals(id,cfg.getJSONArray("uploaded").getString(0)); assertFalse(migrateConvertedUnits(cfg,temperatures()+fields()))
    }
    @Test fun haPublishesConvertedTemperatureAndDocumentsItsUserRule() {
        var posted: JSONObject? = null
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            if (chain.request().method == "GET") return@addInterceptor Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Not Found").body("{}".toResponseBody()).build()
            val buffer = okio.Buffer(); chain.request().body!!.writeTo(buffer); posted=JSONObject(JSONObject(buffer.readUtf8()).getString("payload"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val key=temperatures().keys.first(); val sample=ReadOnlyVehicle(temperatures()).fromRaw(key,68)
        val client=ConnectionClient(RuntimeEnvironment.getApplication(),object: SecretStore { override fun secret(name:String)="test" },http)
        client.publish(config(),mapOf(key to sample),temperatures())
        assertEquals(38.0,posted!!.getDouble("value"),0.0)
        val attrs=posted!!
        assertEquals(68,attrs.getInt("raw")); assertEquals("°C",attrs.getString("unit"))
        assertEquals(2,attrs.getInt("definition_version")); assertEquals("user_supplied",attrs.getString("unit_confidence"))
    }
    @Test fun mqttLocalTemperatureHistoryConvertsLegacyOnceAndSeparatesDefinitions() {
        val key=temperatures().keys.first(); val cfg=config("mqtt",true)
        cfg.getJSONArray("tiles").getJSONObject(0).put("fields",JSONArray().put(key))
        val history=LocalHistory(RuntimeEnvironment.getApplication()); history.configure(cfg)
        history.append(key,JSONObject().put("value",68).put("quality","unverified"))
        history.append(key,ReadOnlyVehicle(temperatures()).fromRaw(key,68))
        val points=history.query(key,30,temperatures().getValue(key)).getJSONArray("points")
        assertEquals(38.0,points.getJSONObject(0).getDouble("value"),0.0); assertEquals(38.0,points.getJSONObject(1).getDouble("value"),0.0)
        assertNotEquals(points.getJSONObject(0).getString("segment"),points.getJSONObject(1).getString("segment"))
    }
    @Test fun temperatureHistoryAllowsOnlyTheDocumentedRawPairAndPreservesDisplayOptions() {
        val high = "1014/5/1148190752"; val low = "1014/5/1148190736"
        val catalog = fields() + mapOf(high to JSONObject().put("unit", "").put("encoding", "原值").put("displayAllowed", true),
            low to JSONObject().put("unit", "").put("encoding", "原值").put("displayAllowed", true))
        val cfg = config(); val tile = cfg.getJSONArray("tiles").getJSONObject(0)
        tile.put("kind", "comparison").put("fields", JSONArray().put(high).put(low))
            .put("showTitle", false).put("showUnits", false).put("showIcon", false).put("showDataIcons", true)
        val restored = ConfigValidator.validate(cfg, catalog).getJSONArray("tiles").getJSONObject(0)
        assertFalse(restored.getBoolean("showTitle")); assertFalse(restored.getBoolean("showUnits"))
        assertFalse(restored.getBoolean("showIcon")); assertTrue(restored.getBoolean("showDataIcons"))
        tile.put("fields", JSONArray().put(high).put(id))
        assertThrows(IllegalArgumentException::class.java) { ConfigValidator.validate(cfg, catalog) }
    }
    @Test fun verticalStripPlacementRemainsInsideStatusBar() {
        assertEquals(StripPlacement(0,84), stripPlacement(84,0,36))
        assertEquals(StripPlacement(24,60), stripPlacement(84,24,36))
        assertEquals(StripPlacement(48,36), stripPlacement(84,180,36))
        assertEquals(StripPlacement(0,84), stripPlacement(84,-5,36))
        assertEquals(StripPlacement(0,20), stripPlacement(20,180,36))
    }
    @Test fun floatingPositionClampsAndRestoresAcrossScreenSizes() {
        assertEquals(800,floatingCoordinate(0.5,0,1920,320))
        assertEquals(320,floatingCoordinate(0.5,0,800,160))
        assertEquals(0,floatingCoordinate(null,-40,1920,160))
        assertEquals(1760,floatingCoordinate(null,2000,1920,160))
        assertEquals(0,floatingCoordinate(1.0,0,100,160))
        val valid = config().put("overlayX",0.25).put("overlayY",0.75)
        assertEquals(0.75,ConfigValidator.validate(valid,fields()).getDouble("overlayY"),0.0)
        assertThrows(IllegalArgumentException::class.java) { ConfigValidator.validate(valid.put("overlayX",1.1),fields()) }
    }
    @Test fun touchFramesScaleCoordinatesAndCancelMultipleFingers() {
        val decoder = TouchFrameDecoder(1920,1080,0,3840,0,2160)
        fun line(code: String, value: String) = decoder.line(code+" "+value,100)
        line("EV_ABS ABS_MT_TRACKING_ID","00000001")
        line("EV_ABS ABS_MT_POSITION_X","00000300")
        line("EV_ABS ABS_MT_POSITION_Y","00000100")
        assertEquals(TouchPoint(android.view.MotionEvent.ACTION_DOWN,384f,128f,100),line("EV_SYN SYN_REPORT","00000000"))
        line("EV_ABS ABS_MT_SLOT","00000001"); line("EV_ABS ABS_MT_TRACKING_ID","00000002")
        assertEquals(android.view.MotionEvent.ACTION_CANCEL,line("EV_SYN SYN_REPORT","00000000")!!.action)
        line("EV_ABS ABS_MT_TRACKING_ID","ffffffff"); line("EV_ABS ABS_MT_SLOT","00000000")
        line("EV_ABS ABS_MT_TRACKING_ID","ffffffff"); line("EV_SYN SYN_REPORT","00000000")
        line("EV_ABS ABS_MT_TRACKING_ID","00000003")
        assertEquals(android.view.MotionEvent.ACTION_DOWN,line("EV_SYN SYN_REPORT","00000000")!!.action)
        line("EV_ABS ABS_MT_TRACKING_ID","ffffffff")
        assertEquals(android.view.MotionEvent.ACTION_UP,line("EV_SYN SYN_REPORT","00000000")!!.action)
        assertEquals(android.view.MotionEvent.ACTION_CANCEL,line("EV_SYN SYN_DROPPED","00000000")!!.action)
        assertNull(line("EV_ABS ABS_MT_TRACKING_ID","00000004")); assertNull(line("EV_SYN SYN_REPORT","00000000"))
    }
    @Test fun configStripsSecretsAndRejectsNonReadonlyFields() {
        val source = config().put("haToken","secret").put("mqttPassword","secret")
        val normalized = ConfigValidator.validate(source, fields())
        assertFalse(normalized.has("haToken")); assertFalse(normalized.has("mqttPassword"))
        source.getJSONArray("tiles").getJSONObject(0).put("fields",JSONArray().put("write/engine"))
        assertThrows(IllegalArgumentException::class.java) { ConfigValidator.validate(source, fields()) }
    }
    @Test fun haModeRecordsLocalHistoryWithoutServerOrEntityMapping() {
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(config("ha",true))
        history.append(id,JSONObject().put("value",13.6).put("quality","available"))
        assertEquals(13.6,history.query(id,30).getJSONArray("points").getJSONObject(0).getDouble("value"),0.0)
        assertFalse(RuntimeEnvironment.getApplication().getDatabasePath("mqtt-history.db").exists())
    }
    @Test fun optionalChartBoundsMustBeFiniteAndOrdered() {
        val settings = config()
        val tile = settings.getJSONArray("tiles").getJSONObject(0).put("kind", "trend").put("minimum", 20).put("maximum", 10)
        assertThrows(IllegalArgumentException::class.java) { ConfigValidator.validate(settings, fields()) }
        tile.put("maximum", 30)
        assertEquals(30, ConfigValidator.validate(settings, fields()).getJSONArray("tiles").getJSONObject(0).getInt("maximum"))
    }
    @Test fun historyOnlyRecordsHomeFieldsAndSurvivesConnectionChanges() {
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(config("mqtt",true))
        history.append("other",JSONObject().put("value",999).put("quality","available"))
        history.append(id,JSONObject().put("value",13.6).put("quality","available").put("sourceEpoch",1))
        history.append(id,JSONObject().put("value",13.6).put("quality","disconnected").put("sourceEpoch",1))
        val points = history.query(id,30).getJSONArray("points")
        assertEquals(2,points.length()); assertEquals(13.6,points.getJSONObject(0).getDouble("value"),0.0)
        assertTrue(points.getJSONObject(1).isNull("value")); assertEquals("unavailable",points.getJSONObject(1).getString("state"))
        history.configure(config("ha",true)); assertEquals(2,history.query(id,30).getJSONArray("points").length())
    }
    @Test fun haPublishesQualityWithoutRefreshingOldSampleTime() {
        var posted: JSONObject? = null
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            assertEquals("192.168.10.20",chain.request().url.host)
            if (chain.request().method == "GET") return@addInterceptor Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Not Found").body("{}".toResponseBody()).build()
            val buffer = okio.Buffer(); chain.request().body!!.writeTo(buffer); posted = JSONObject(JSONObject(buffer.readUtf8()).getString("payload"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val secrets = object : SecretStore { override fun secret(name: String) = "test-only-token" }
        val client = ConnectionClient(RuntimeEnvironment.getApplication(),secrets,http)
        client.publish(config(),mapOf(id to JSONObject().put("value",13.6).put("quality","disconnected").put("updatedAt",1000)),fields())
        assertTrue(posted!!.isNull("value")); assertEquals("disconnected",posted!!.getString("quality"))
        assertEquals(1000,posted!!.getLong("sampled_at"))
        assertTrue(posted!!.isNull("value"))
        assertTrue(posted!!.isNull("source_timestamp"))
    }
    @Test fun tyrePressureOutsideSdkBoundsIsNotPresentedAsValidPressure() {
        val tyre = "1016/5/-1728052956"
        val reader = ReadOnlyVehicle(mapOf(tyre to JSONObject().put("unit","")))
        val invalid = reader.fromRaw(tyre,58880)
        assertEquals("invalid",invalid.getString("quality")); assertEquals(58880,invalid.getInt("raw")); assertFalse(invalid.has("value"))
        assertEquals("unverified",reader.fromRaw(tyre,230).getString("quality"))
    }
    @Test fun callbackFloat32MatchesBinderValueAfterJsonRoundTrip() {
        val raw = 0.7000122f
        val reader = ReadOnlyVehicle(fields())
        val callback = JSONObject(reader.fromRaw(id,raw).toString())
        assertEquals(raw.toDouble(),callback.getDouble("value"),0.0)
        assertEquals(raw.toDouble(),callback.getDouble("raw"),0.0)
    }
    @Test fun negativeRawAndInvalidSentinelsRemainFieldSpecific() {
        val negativeId = "1005/5/1031798840"
        val reader = ReadOnlyVehicle(fields()+mapOf(negativeId to JSONObject().put("unit","")))
        assertEquals(-42,reader.fromRaw(negativeId,-42).getInt("value"))
        assertEquals("invalid",reader.fromRaw(id,Float.NaN).getString("quality"))
    }
    @Test fun localHistoryMigrationEnablesOldHaOnceAndKeepsExplicitPauses() {
        val ha=config("ha",false)
        assertTrue(migrateLocalHistory(ha)); assertTrue(ha.getBoolean("localHistory"))
        ha.put("localHistory",false)
        assertFalse(migrateLocalHistory(ha)); assertFalse(ha.getBoolean("localHistory"))
        val mqtt=config("mqtt",false)
        assertTrue(migrateLocalHistory(mqtt)); assertFalse(mqtt.getBoolean("localHistory"))
    }
    @Test fun removingFieldsAndPausingDoesNotEraseRecordedHistory() {
        val history=LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(config("ha",true))
        history.append(id,JSONObject().put("value",13.6).put("quality","available"))
        history.configure(config("ha",false).put("tiles",JSONArray()))
        history.append(id,JSONObject().put("value",99).put("quality","available"))
        val paused=history.query(id,30).getJSONArray("points")
        assertEquals(2,paused.length()); assertTrue(paused.getJSONObject(1).isNull("value"))
        history.configure(config("ha",true))
        history.append(id,JSONObject().put("value",13.7).put("quality","available"))
        val resumed=history.query(id,30).getJSONArray("points")
        assertEquals(3,resumed.length()); assertTrue(resumed.getJSONObject(1).isNull("value"))
        assertEquals(13.7,resumed.getJSONObject(2).getDouble("value"),0.0)
    }
    @Test fun changingPersistenceCopiesHistoryAndRestartBreaksSegments() {
        val context=RuntimeEnvironment.getApplication()
        context.deleteDatabase("mqtt-history.db")
        val history=LocalHistory(context)
        val cfg=config("ha",true)
        history.configure(cfg)
        history.append(id,JSONObject().put("value",13.6).put("quality","available"))
        cfg.put("retainHistory",true); history.configure(cfg)
        val resumed=LocalHistory(context); resumed.configure(cfg)
        resumed.append(id,JSONObject().put("value",13.7).put("quality","available"))
        val points=resumed.query(id,30).getJSONArray("points")
        assertEquals(2,points.length())
        assertNotEquals(points.getJSONObject(0).getString("segment"),points.getJSONObject(1).getString("segment"))
        resumed.configure(JSONObject(cfg.toString()).put("retainHistory",false))
        assertEquals(2,resumed.query(id,30).getJSONArray("points").length())
        resumed.clear(); history.clear()
    }
    @Test fun stripOpacityChangesBackgroundOnlyAndCompensatesSystemTouchLimit() {
        val ink=android.graphics.Color.rgb(235,230,210)
        val background=android.graphics.Color.rgb(28,30,24)
        assertEquals(26,android.graphics.Color.alpha(stripBackgroundColor(background,0.1)))
        assertEquals(204,android.graphics.Color.alpha(stripBackgroundColor(background,0.8)))
        assertEquals(255,android.graphics.Color.alpha(ink))
        assertEquals(255,android.graphics.Color.alpha(stripBackgroundColor(background,0.8,0.8f)))
    }

    @Test fun localHistoryMigratesLegacyDatabaseAndRetainsRawMetadata() {
        val context=RuntimeEnvironment.getApplication()
        context.deleteDatabase("mqtt-history.db")
        android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath("mqtt-history.db"),null).use { db ->
            db.execSQL("CREATE TABLE samples (seq INTEGER PRIMARY KEY, id TEXT NOT NULL, at INTEGER NOT NULL, value REAL, state TEXT, segment TEXT NOT NULL)")
            db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",arrayOf<Any?>(id,System.currentTimeMillis(),13.5,"13.5","old|1|available|V|1"))
        }
        val history=LocalHistory(context)
        history.configure(config("ha",true).put("retainHistory",true))
        history.append(id,JSONObject().put("value",13.6).put("raw",13.600001).put("unit","V").put("definitionVersion",2).put("quality","available"))
        val points=history.query(id,30).getJSONArray("points")
        assertEquals(2,points.length()); assertTrue(points.getJSONObject(0).isNull("sample"))
        assertEquals(13.600001,points.getJSONObject(1).getJSONObject("sample").getDouble("raw"),0.0)
        history.clear()
    }
    @Test fun documentedUnitsReplaceOnlyLegacyRawLabels() {
        val catalog=fields()
        val cfg=config().put("overlays",JSONArray().put(JSONObject().put("field",id).put("unit","原值")))
        cfg.getJSONArray("tiles").getJSONObject(0).put("units",JSONObject().put(id,"原值"))
        assertTrue(migrateConvertedUnits(cfg,catalog))
        assertEquals("V",cfg.getJSONArray("overlays").getJSONObject(0).getString("unit"))
        assertFalse(cfg.getJSONArray("tiles").getJSONObject(0).getJSONObject("units").has(id))
        cfg.getJSONArray("overlays").getJSONObject(0).put("unit","自定义")
        assertFalse(migrateConvertedUnits(cfg,catalog))
    }

    @Test fun userConfirmedUnitsKeepRawValuesAndMigrateOnlyOldFieldNames() {
        val json=JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        val field=(0 until json.length()).map { json.getJSONObject(it) }.single { it.getString("id")=="1012/5/339738656" }
        val catalog=mapOf("1012/5/339738656" to field)
        assertEquals(3,field.getInt("definitionVersion")); assertEquals("user_supplied",field.getString("unitConfidence"))
        val sample=ReadOnlyVehicle(catalog).fromRaw("1012/5/339738656",-357)
        assertEquals(-357,sample.getInt("raw")); assertEquals(-357,sample.getInt("value")); assertEquals("kW",sample.getString("unit"))
        val tile=JSONObject().put("title","ENGINE_POWER候选").put("fields",JSONArray().put("1012/5/339738656"))
            .put("labels",JSONObject().put("1012/5/339738656","ENGINE_POWER候选"))
        tile.put("units",JSONObject().put("1012/5/339738656","W"))
        val overlay=JSONObject().put("field","1012/5/339738656").put("unit","W")
        val cfg=JSONObject().put("tiles",JSONArray().put(tile)).put("overlays",JSONArray().put(overlay))
        assertTrue(migrateConvertedUnits(cfg,catalog))
        assertFalse(tile.getJSONObject("units").has("1012/5/339738656")); assertEquals("kW",overlay.getString("unit"))
        assertEquals("动力功率",tile.getString("title")); assertEquals("动力功率",tile.getJSONObject("labels").getString("1012/5/339738656"))
        tile.put("title","我的功率"); tile.getJSONObject("labels").put("1012/5/339738656","自定义"); overlay.put("unit","自定义")
        assertFalse(migrateConvertedUnits(cfg,catalog)); assertEquals("我的功率",tile.getString("title"))
    }

    @Test fun healthPercentAndAebRawCodesFollowCatalogWithoutInventedEnums() {
        val json=JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        val catalog=(0 until json.length()).map { json.getJSONObject(it) }.associateBy { it.getString("id") }
        val health="1014/5/1145045032"; val aeb="1038/5/303038502"
        val reader=ReadOnlyVehicle(catalog)
        val sample=reader.fromRaw(health,100)
        assertEquals(100,sample.getInt("value")); assertEquals(100,sample.getInt("raw"))
        assertEquals("%",sample.getString("unit")); assertEquals("user_supplied",catalog.getValue(health).getString("unitConfidence"))
        assertTrue(catalog.getValue(aeb).getBoolean("rawDisplay")); assertFalse(catalog.getValue(aeb).has("stateLabels"))
        for (code in listOf(0,1,3)) {
            val raw=reader.fromRaw(aeb,code)
            assertEquals(code,raw.getInt("raw")); assertEquals(code,raw.getInt("value")); assertFalse(raw.has("stateLabel"))
            assertEquals("",raw.getString("unit"))
        }
        val tile=JSONObject().put("title","AEB激活候选").put("fields",JSONArray().put(aeb))
        val config=JSONObject().put("tiles",JSONArray().put(tile))
        assertTrue(migrateConvertedUnits(config,catalog)); assertEquals("AEB激活",tile.getString("title"))
    }

    @Test fun annotatedUnitsPreserveRawValuesAndMigrateLegacyLabelsOnly() {
        val json=JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        val catalog=(0 until json.length()).map { json.getJSONObject(it) }.associateBy { it.getString("id") }
        val expected=mapOf(
            "1014/5/1147142192" to "mV",
            "1014/5/1147142160" to "mV",
            "1006/5/1186988096" to "rpm",
            "1039/5/1302331672" to "°C",
            "1039/5/1178624024" to "°C",
            "1039/5/1302331756" to "°C",
            "1039/5/1178624040" to "°C",
            "1039/5/1302331648" to "°C",
            "1039/5/1178624016" to "°C",
            "1039/5/1302331748" to "°C",
            "1039/5/1178624032" to "°C",
            "1000/5/1320181776" to "°C",
            "1039/5/919601208" to "°C",
            "1007/5/1246797848" to "°C",
            "1007/5/1246797860" to "°C",
            "1007/5/1246797872" to "°C",
            "1007/5/1246797884" to "°C")
        val reader=ReadOnlyVehicle(catalog)
        for ((id,unit) in expected) {
            val field=catalog.getValue(id)
            val raw=if (unit=="mV") 3238 else if (unit=="rpm") 1440 else 33
            val sample=reader.fromRaw(id,raw)
            assertEquals(raw,sample.getInt("raw")); assertEquals(raw,sample.getInt("value"))
            assertEquals(unit,sample.getString("unit")); assertEquals("available",sample.getString("quality"))
            assertEquals(2,field.getInt("definitionVersion")); assertEquals("user_supplied",field.getString("unitConfidence"))
            assertFalse(field.has("valueOffset")); assertFalse(field.has("unitField"))
            val tile=JSONObject().put("fields",JSONArray().put(id)).put("units",JSONObject().put(id,"原值"))
            val overlay=JSONObject().put("field",id).put("unit","原值")
            val cfg=JSONObject().put("tiles",JSONArray().put(tile)).put("overlays",JSONArray().put(overlay))
            assertTrue(migrateConvertedUnits(cfg,catalog)); assertFalse(tile.getJSONObject("units").has(id))
            assertEquals(unit,overlay.getString("unit"))
            tile.getJSONObject("units").put(id,"自定义"); overlay.put("unit","自定义")
            assertFalse(migrateConvertedUnits(cfg,catalog)); assertEquals("自定义",overlay.getString("unit"))
        }
        assertEquals(-30,catalog.getValue("1014/5/1148190752").getInt("valueOffset"))
        for (id in listOf("1014/5/877658136","1014/5/877658120","1006/5/843055176","1006/5/818937864","1032/7/1150289944"))
            assertEquals("",catalog.getValue(id).getString("unit"))
    }

    @Test fun motorDirectionAndUnitsApplyOnceAcrossDisplayHistoryAndHa() {
        val json=JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        val catalog=(0 until json.length()).map { json.getJSONObject(it) }.associateBy { it.getString("id") }
        val front="1012/5/1141899272"; val rear="1012/5/621805576"
        val reader=ReadOnlyVehicle(catalog)
        for ((id,unit) in mapOf(front to "rpm",rear to "rpm","1009/7/1186988040" to "A","1009/7/1186988056" to "A")) {
            val sample=reader.fromRaw(id,-120)
            assertEquals(-120,sample.getInt("raw")); assertEquals(if (id==front) 120.0 else -120.0,sample.getDouble("value"),0.0)
            assertEquals(unit,sample.getString("unit")); assertEquals("available",sample.getString("quality"))
        }
        assertEquals(-120.0,reader.fromRaw(front,120).getDouble("value"),0.0)
        assertEquals(0.0,reader.fromRaw(front,0).getDouble("value"),0.0)
        val cfg=config("mqtt",true)
        cfg.getJSONArray("tiles").getJSONObject(0).put("fields",JSONArray().put(front))
        val history=LocalHistory(RuntimeEnvironment.getApplication()); history.configure(cfg)
        history.append(front,JSONObject().put("value",-120).put("raw",-120).put("unit","").put("quality","unverified").put("definitionVersion",1))
        history.append(front,reader.fromRaw(front,-120))
        val points=history.query(front,30,catalog.getValue(front)).getJSONArray("points")
        assertEquals(120.0,points.getJSONObject(0).getDouble("value"),0.0)
        assertEquals(120.0,points.getJSONObject(1).getDouble("value"),0.0)
        assertEquals(-120,points.getJSONObject(0).getJSONObject("sample").getInt("raw"))
        assertNotEquals(points.getJSONObject(0).getString("segment"),points.getJSONObject(1).getString("segment"))
        var body=JSONObject()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            if (chain.request().method == "GET") return@addInterceptor Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Not Found").body("{}".toResponseBody()).build()
            val buffer=okio.Buffer(); chain.request().body!!.writeTo(buffer); body=JSONObject(JSONObject(buffer.readUtf8()).getString("payload"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val client=ConnectionClient(RuntimeEnvironment.getApplication(),object : SecretStore { override fun secret(name:String)="test" },http)
        client.publish(config(),mapOf(front to reader.fromRaw(front,-120)),catalog)
        assertEquals(120.0,body.getDouble("value"),0.0)
        assertEquals(-120,body.getInt("raw"))
        assertEquals("rpm",body.getString("unit"))
    }

    @Test fun removingAHomeFieldKeepsAGapEvenIfAnotherConsumerStillCollectsIt() {
        val history=LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(config("ha",true))
        history.append(id,JSONObject().put("value",13.6).put("quality","available").put("sourceEpoch",1))
        history.configure(config("ha",true).put("tiles",JSONArray()))
        history.append(id,JSONObject().put("value",99).put("quality","available").put("sourceEpoch",1))
        history.configure(config("ha",true))
        history.append(id,JSONObject().put("value",13.7).put("quality","available").put("sourceEpoch",1))
        val points=history.query(id,30).getJSONArray("points")
        assertEquals(3,points.length()); assertTrue(points.getJSONObject(1).isNull("value"))
        assertEquals(13.6,points.getJSONObject(0).getDouble("value"),0.0)
        assertEquals(13.7,points.getJSONObject(2).getDouble("value"),0.0)
    }

    @Test fun localHistoryKeepsStablePredecessorWithoutInventingFreshSampleTimes() {
        val history=LocalHistory(RuntimeEnvironment.getApplication()); history.configure(config("ha",true))
        val original=System.currentTimeMillis()-2*60*60*1000
        history.append(id,JSONObject().put("value",43).put("raw",73).put("quality","available").put("receivedAt",original).put("updatedAt",original).put("unit","°C").put("definitionVersion",2))
        val result=history.query(id,30); val points=result.getJSONArray("points")
        assertEquals(1,points.length()); assertEquals(43,points.getJSONObject(0).getInt("value"))
        assertEquals(original,java.time.Instant.parse(points.getJSONObject(0).getString("at")).toEpochMilli())
        assertEquals(original,points.getJSONObject(0).getJSONObject("sample").getLong("receivedAt"))
        assertEquals(result.getLong("queriedAt"),points.getJSONObject(0).getLong("observedUntil"))
        history.append(id,JSONObject().put("quality","disconnected").put("receivedAt",System.currentTimeMillis()))
        val failed=history.query(id,30).getJSONArray("points")
        assertEquals(2,failed.length()); assertTrue(failed.getJSONObject(1).isNull("value")); assertFalse(failed.getJSONObject(1).has("observedUntil"))
    }
    @Test fun priorAppSessionAndPausedHistoryDoNotExtendOldStateToNow() {
        val context=RuntimeEnvironment.getApplication(); context.deleteDatabase("mqtt-history.db")
        val history=LocalHistory(context); val cfg=config("ha",true).put("retainHistory",true); history.configure(cfg)
        history.append(id,JSONObject().put("value",13.6).put("quality","available"))
        val resumed=LocalHistory(context); resumed.configure(cfg)
        assertFalse(resumed.query(id,30).getJSONArray("points").getJSONObject(0).has("observedUntil"))
        resumed.append(id,JSONObject().put("value",13.7).put("quality","available"))
        resumed.configure(JSONObject(cfg.toString()).put("localHistory",false))
        val paused=resumed.query(id,30).getJSONArray("points")
        assertTrue(paused.getJSONObject(paused.length()-1).isNull("value"))
        assertFalse(paused.getJSONObject(paused.length()-1).has("observedUntil"))
        resumed.clear(); history.clear()
    }
    @Test fun retentionProtectsOneBaselinePerFieldAndStillBoundsTheDatabase() {
        val context=RuntimeEnvironment.getApplication(); context.deleteDatabase("mqtt-history.db")
        val second="1014/5/1148190752"
        val cfg=config("ha",true).put("retainHistory",true)
        cfg.getJSONArray("tiles").getJSONObject(0).put("fields",JSONArray().put(id).put(second))
        val history=LocalHistory(context); history.configure(cfg)
        val db=android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath("mqtt-history.db").path,null,android.database.sqlite.SQLiteDatabase.OPEN_READWRITE)
        val old=System.currentTimeMillis()-60*60*1000
        db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",arrayOf<Any>(id,old,13.6,"13.6","old|available|V|1"))
        db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",arrayOf<Any>(id,old+1,13.7,"13.7","old|available|V|1"))
        db.beginTransaction()
        try { repeat(12100) { n -> db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",arrayOf<Any>(second,System.currentTimeMillis(),43+n%2,"43","test")) }; db.setTransactionSuccessful() }
        finally { db.endTransaction() }
        val baseline=history.query(id,30).getJSONArray("points")
        assertEquals(1,baseline.length()); assertEquals(13.7,baseline.getJSONObject(0).getDouble("value"),0.0)
        db.rawQuery("SELECT COUNT(*) FROM samples",null).use { c -> c.moveToFirst(); assertEquals(12101,c.getInt(0)) }
        assertEquals(LocalHistory.CAPACITY_BYTES,history.storageStats().getLong("maximumBytes"))
        db.close(); history.clear()
    }

}
