package com.navee.trustbridge.vpn

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import kotlin.concurrent.thread

class VpnHealthCheckJobService : JobService() {
    companion object {
        private const val TAG = "VpnHealthCheckJob"
        private const val JOB_ID = 91071
        private const val CHECK_INTERVAL_MS = 2 * 60 * 1000L
        private const val CHECK_DEADLINE_MS = CHECK_INTERVAL_MS + 20_000L

        fun schedule(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                return
            }
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            val component = ComponentName(context, VpnHealthCheckJobService::class.java)
            val builder = JobInfo.Builder(JOB_ID, component)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .setBackoffCriteria(30_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .setMinimumLatency(CHECK_INTERVAL_MS)
                .setOverrideDeadline(CHECK_DEADLINE_MS)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setRequiresBatteryNotLow(false)
            }

            try {
                scheduler.schedule(builder.build())
            } catch (error: Exception) {
                Log.e(TAG, "Unable to schedule VPN health-check job", error)
            }
        }

        fun cancel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                return
            }
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            try {
                scheduler.cancel(JOB_ID)
            } catch (_: Exception) {
            }
        }
    }

    override fun onStartJob(params: JobParameters?): Boolean {
        thread(name = "tb-vpn-healthcheck") {
            try {
                val store = VpnPreferencesStore(this)
                val config = store.loadConfig()
                if (!config.enabled) {
                    return@thread
                }
                if (VpnService.prepare(this) != null) {
                    Log.w(TAG, "Health-check skipped: VPN permission missing")
                    return@thread
                }

                val startIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_START
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                        ArrayList(config.blockedCategories)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                        ArrayList(config.blockedDomains)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                        ArrayList(config.temporaryAllowedDomains)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_PACKAGES,
                        ArrayList(config.blockedPackages)
                    )
                    putExtra(DnsVpnService.EXTRA_UPSTREAM_DNS, config.upstreamDns)
                    putExtra(DnsVpnService.EXTRA_PARENT_ID, config.parentId)
                    putExtra(DnsVpnService.EXTRA_CHILD_ID, config.childId)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(startIntent)
                } else {
                    startService(startIntent)
                }
            } catch (error: Exception) {
                Log.e(TAG, "VPN health-check execution failed", error)
            } finally {
                schedule(this)
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        schedule(this)
        return true
    }
}
