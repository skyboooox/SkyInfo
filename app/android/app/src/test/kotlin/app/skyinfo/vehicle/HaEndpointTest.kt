package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HaEndpointTest {
    @Test fun domainsPrivateAddressesAndIpv6AcceptBothTransports() {
        for(url in listOf("http://home.example.com:8123/", "http://192.168.10.40:8123/",
            "https://ha.example.com/", "http://[::1]:8123/", "HTTP://home.example.com:8123/", "HTTPS://HA.example.com/")) {
            assertEquals(url,ConfigValidator.validate(JSONObject().put("haUrl",url),emptyMap()).getString("haUrl"))
        }
        assertEquals(HaEndpoint.identity("https://HA.example.com/"),HaEndpoint.identity("https://ha.example.com:443"))
        assertNotEquals(HaEndpoint.identity("http://ha.example.com"),HaEndpoint.identity("https://ha.example.com"))
    }
    @Test fun malformedSchemesPortsAndEmbeddedCredentialsRemainRejected() {
        for(url in listOf("ftp://example.com/","http://user:password@example.com/","http://example.com:0/",
            "https://example.com:65536/","http://example.com/?x=1","https://example.com/#a")) {
            try { ConfigValidator.validate(JSONObject().put("haUrl",url),emptyMap());fail(url) }
            catch (_: IllegalArgumentException) {}
        }
    }
}
