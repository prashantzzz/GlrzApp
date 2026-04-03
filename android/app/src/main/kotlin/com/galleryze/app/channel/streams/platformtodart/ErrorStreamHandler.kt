package com.galleryze.app.channel.streams.platformtodart

import com.galleryze.app.channel.streams.BaseStreamHandler
import com.galleryze.app.utils.LogUtils

class ErrorStreamHandler : BaseStreamHandler() {
    fun notifyError(error: String) = success(error)

    override val logTag = LOG_TAG

    companion object {
        private val LOG_TAG = LogUtils.createTag<ErrorStreamHandler>()
        const val CHANNEL = "deckers.thibault/aves/error"
    }
}