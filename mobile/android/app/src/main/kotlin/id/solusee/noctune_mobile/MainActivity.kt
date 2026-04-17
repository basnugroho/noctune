package id.solusee.noctune_mobile

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"noc_tune/device_info"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"getDeviceContext" -> result.success(getDeviceContext())
				else -> result.notImplemented()
			}
		}
	}

	private fun getDeviceContext(): Map<String, Any?> {
		val batteryStatus = registerReceiver(
			null,
			IntentFilter(Intent.ACTION_BATTERY_CHANGED)
		)

		val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
		val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
		val batteryPct = if (level >= 0 && scale > 0) {
			((level.toFloat() / scale.toFloat()) * 100).toInt()
		} else {
			null
		}

		val chargeStatus = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
		val isCharging = chargeStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
			chargeStatus == BatteryManager.BATTERY_STATUS_FULL

		val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
		val linkProperties = connectivityManager.getLinkProperties(connectivityManager.activeNetwork)
		val dnsServers = linkProperties
			?.dnsServers
			?.mapNotNull { it.hostAddress ?: it.hostName }
			?.filter { it.isNotBlank() }
			?: emptyList()
		val dnsPrimary = dnsServers.firstOrNull()

		val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
		val wifiInfo = wifiManager.connectionInfo
		val wifiRssi = wifiInfo
			?.rssi
			?.takeIf { it > -127 }
		val frequency = wifiInfo?.frequency?.takeIf { it > 0 }
		val wifiChannel = frequency?.let { frequencyToChannel(it) }
		val wifiBand = frequency?.let { frequencyToBand(it) }

		return mapOf(
			"deviceName" to Build.MANUFACTURER,
			"deviceModel" to listOfNotNull(Build.MANUFACTURER, Build.MODEL)
				.joinToString(" ")
				.trim()
				.ifEmpty { null },
			"osName" to "Android",
			"osVersion" to Build.VERSION.RELEASE,
			"connectivityType" to getConnectivityType(connectivityManager),
			"batteryLevel" to batteryPct,
			"batteryCharging" to isCharging,
			"wifiRssi" to wifiRssi,
			"wifiBand" to wifiBand,
			"wifiChannel" to wifiChannel,
			"dnsPrimary" to dnsPrimary,
			"dnsServers" to dnsServers
		)
	}

	private fun getConnectivityType(connectivityManager: ConnectivityManager): String {
		val activeNetwork = connectivityManager.activeNetwork ?: return "No Connection"
		val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
			?: return "Unknown"

		return when {
			capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
			capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
			capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Fixed"
			else -> "Unknown"
		}
	}

	private fun frequencyToChannel(frequency: Int): Int? {
		return when {
			frequency in 2412..2484 -> ((frequency - 2412) / 5) + 1
			frequency in 5170..5895 -> ((frequency - 5000) / 5)
			frequency in 5955..7115 -> ((frequency - 5950) / 5)
			else -> null
		}
	}

	private fun frequencyToBand(frequency: Int): String {
		return when {
			frequency in 2400..2500 -> "2.4 GHz"
			frequency in 4900..5900 -> "5 GHz"
			frequency in 5925..7125 -> "6 GHz"
			else -> "Unknown"
		}
	}
}
