package app.skyinfo.vehicle

import android.location.Location
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class GnssAltitudeTest {
    private fun fix(height: Double = -12.5) = Location("gps").apply {
        altitude = height; latitude = 35.123; longitude = 110.456
        elapsedRealtimeNanos = 10000000000L; time = 123456
        verticalAccuracyMeters = 0.7f
    }
    @Test fun keepsNegativeHeightReferenceAndSourceTimeWithoutCoordinates() {
        val sample = altitudeSample(fix(),100000,12000000000L)
        assertEquals(-12.5,sample.getDouble("value"),0.0)
        assertEquals("WGS84",sample.getString("altitudeReference"))
        assertEquals("m",sample.getString("unit")); assertEquals(98000,sample.getLong("receivedAt"))
        assertEquals("available",sample.getString("quality"))
        assertFalse(sample.toString().contains("latitude")); assertFalse(sample.toString().contains("longitude"))
        assertFalse(sample.toString().contains("35.123")); assertFalse(sample.toString().contains("110.456"))
        assertEquals(0.7,sample.getDouble("verticalAccuracy"),0.001)
    }
    @Test fun missingNonFiniteAndExpiredFixesDoNotBecomeFreshZero() {
        assertEquals("disconnected",altitudeSample(null).getString("quality"))
        val absent = fix().apply { removeAltitude() }
        assertFalse(altitudeSample(absent).has("value"))
        assertEquals("invalid",altitudeSample(fix(Double.NaN)).getString("quality"))
        val expired=altitudeSample(fix(),500000,131000000001L)
        assertEquals("stale",expired.getString("quality")); assertFalse(expired.has("value"))
        assertEquals(500000,expired.getLong("receivedAt")); assertEquals(379000,expired.getLong("sourceAt"))
        assertEquals("available",altitudeSample(fix(0.0),500000,10000000000L).getString("quality"))
    }
    @Test fun authorizationRecoveryUsesAppLocationAndReleasesPassiveListener() {
        val app = org.robolectric.RuntimeEnvironment.getApplication()
        val permissions = org.robolectric.Shadows.shadowOf(app)
        permissions.denyPermissions(android.Manifest.permission.ACCESS_FINE_LOCATION,android.Manifest.permission.ACCESS_COARSE_LOCATION)
        val reader = GnssAltitude(app)
        val samples = mutableListOf<JSONObject>()
        reader.configure(true,true,samples::add)
        assertEquals("permission",samples.last().getString("quality")); assertFalse(reader.subscribed)
        reader.configure(true,true,samples::add)
        assertEquals(1,samples.size)
        permissions.grantPermissions(android.Manifest.permission.ACCESS_FINE_LOCATION,android.Manifest.permission.ACCESS_COARSE_LOCATION)
        val manager = app.getSystemService(android.location.LocationManager::class.java)
        val shadow = org.robolectric.Shadows.shadowOf(manager)
        shadow.setProviderEnabled("gps",true)
        val location = fix(14.7).apply { elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos() }
        shadow.setLastKnownLocation("gps",location)
        reader.configure(true,true,samples::add)
        assertTrue(reader.subscribed)
        assertEquals(14.7,reader.read().getDouble("value"),0.001)
        assertEquals("available",samples.last().getString("quality"))
        val fields = mapOf(GNSS_ALTITUDE to JSONObject().put("id",GNSS_ALTITUDE))
        assertEquals(14.7,ReadOnlyVehicle(fields,reader).read(GNSS_ALTITUDE).getDouble("value"),0.001)
        reader.configure(false,false,samples::add)
        assertFalse(reader.subscribed)
        reader.close()
    }
    @Test fun unavailableFixCannotResurrectThePreviousHeight() {
        val old = altitudeSample(fix(),100000,12000000000L)
        stampSampleTimes(old,null,1)
        for (quality in listOf("stale","permission","invalid","disconnected")) {
            val missing = altitudeSample(null).put("quality",quality)
            stampSampleTimes(missing,old,1)
            assertFalse(missing.has("value"))
            assertEquals(old.getLong("updatedAt"),missing.getLong("updatedAt"))
        }
    }
    @Test fun haHeightRemainsNumericWithMeasurementAndNoTextFallback() {
        val field=JSONObject().put("id",GNSS_ALTITUDE).put("valueType","number").put("unit","m").put("encoding","m").put("entityKey","gnss_altitude").put("name","海拔 · GNSS")
        val definition=haSensorDiscovery("demo","skyinfo","0.1.0-alpha.2",field,"sensor.demo_height")
        assertEquals("measurement",definition.getString("state_class"))
        assertEquals("m",definition.getString("unit_of_measurement"))
        assertEquals("invalid",haReading(JSONObject().put("value","12.5").put("quality","available"),field).getString("quality"))
        assertTrue(haReading(altitudeSample(fix(),100000,12000000000L),field).get("value") is Number)
        assertTrue(haReading(altitudeSample(null),field).isNull("value"))
    }
}
