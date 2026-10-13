package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class CommandReceiptsTest {
    @Test fun receiptsAreBoundedExpireAndNeverCrossConnectionTargets() {
        var now = 1000L
        val queue = CommandReceipts { now }
        val config = JSONObject().put("connection","mqtt").put("mqttHost","one").put("mqttTopic","skyinfo/one")
        repeat(20) { queue.add(config,JSONObject().put("id","id_$it").put("status","confirmed")) }
        assertEquals(16,queue.size)
        assertEquals("id_4",queue.next(config)!!.result.getString("id"))
        queue.delivered("id_4"); assertEquals("id_5",queue.next(config)!!.result.getString("id"))
        assertNotNull(queue.next(JSONObject(config.toString()).put("publishEnabled",false)))
        assertNull(queue.next(JSONObject(config.toString()).put("mqttHost","two")))
        queue.add(config,JSONObject().put("id","late"))
        now += 120001; assertNull(queue.next(config)); assertEquals(0,queue.size)
    }
}
