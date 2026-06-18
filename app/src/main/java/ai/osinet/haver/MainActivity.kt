package ai.osinet.haver

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlertDialog
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.*
import android.widget.EditText
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.net.URL

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private val kioskPin = "1234"

    // Version file hosted in the repo — developer bumps version_code here to push update notices
    private val versionCheckUrl =
        "https://raw.githubusercontent.com/Mortal18-n/haver-android/main/android-version.json"

    private val permissionsLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { /* WebChromeClient handles actual grant inside WebView */ }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_main)
        webView = findViewById(R.id.webview)

        configureWebView()
        hideSystemUI()
        requestNativePermissions()
        enterKioskMode()
        checkForUpdates()

        webView.loadUrl("https://haver-digital.vercel.app")
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowContentAccess = true
            allowFileAccess = true
            useWideViewPort = true
            loadWithOverviewMode = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            userAgentString = "$userAgentString HaverKiosk/${BuildConfig.VERSION_NAME}"
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                // Keep all HTTPS navigation inside the WebView
                return request.url.scheme != "https"
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            // Auto-grant microphone + camera — key fix for the echo loop:
            // Android's native audio stack handles mic capture, not the browser sandbox.
            override fun onPermissionRequest(request: PermissionRequest) {
                request.grant(request.resources)
            }

            override fun onShowFileChooser(
                view: WebView,
                callback: ValueCallback<Array<Uri>>,
                params: FileChooserParams
            ): Boolean {
                callback.onReceiveValue(null)
                return true
            }
        }
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.run {
                hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        }
    }

    private fun requestNativePermissions() {
        val needed = listOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CAMERA,
            Manifest.permission.MODIFY_AUDIO_SETTINGS
        ).filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) permissionsLauncher.launch(needed.toTypedArray())
    }

    private fun enterKioskMode() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, HaverDeviceAdminReceiver::class.java)
        try {
            if (dpm.isDeviceOwnerApp(packageName)) {
                dpm.setLockTaskPackages(admin, arrayOf(packageName))
            }
            startLockTask()
        } catch (_: Exception) {
            // Graceful fallback (emulator, non-kiosk device)
        }
    }

    // Check android-version.json in the GitHub repo. If the server version_code is higher
    // than this build, show a native update notice so staff know to re-flash the tablet.
    private fun checkForUpdates() {
        val currentVersionCode = BuildConfig.VERSION_CODE
        Thread {
            try {
                val json = URL(versionCheckUrl).openStream().bufferedReader().readText()
                val obj = JSONObject(json)
                val remoteVersionCode = obj.getInt("version_code")
                val remoteVersionName = obj.optString("version_name", "")
                if (remoteVersionCode > currentVersionCode) {
                    runOnUiThread { showUpdateDialog(remoteVersionName) }
                }
            } catch (_: Exception) {
                // Network unavailable or file missing — silently skip
            }
        }.start()
    }

    private fun showUpdateDialog(remoteVersion: String) {
        val msg = if (remoteVersion.isNotEmpty())
            "גרסה חדשה ($remoteVersion) זמינה. אנא פנה לתמיכה לעדכון האפליקציה."
        else
            "עדכון חדש לאפליקציה זמין. אנא פנה לתמיכה."
        AlertDialog.Builder(this)
            .setTitle("עדכון נדרש")
            .setMessage(msg)
            .setPositiveButton("הבנתי", null)
            .setCancelable(false)
            .show()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUI()
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_BACK -> {
                if (webView.canGoBack()) webView.goBack()
                else showKioskExitDialog()
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    private fun showKioskExitDialog() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            hint = "קוד יציאה"
        }
        AlertDialog.Builder(this)
            .setTitle("יציאה מהאפליקציה")
            .setMessage("הכנס את הקוד לסגירה")
            .setView(input)
            .setPositiveButton("אישור") { _, _ ->
                if (input.text.toString() == kioskPin) {
                    stopLockTask()
                    finish()
                } else {
                    Toast.makeText(this, "קוד שגוי", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("ביטול", null)
            .show()
    }
}
