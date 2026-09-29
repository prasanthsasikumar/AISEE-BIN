// aiseebin.cpp: the app's two native bridges.
//
// 1. Glasses frames. Realtek's player (librtk-smart-wear.so, from the smartwear
//    AAR via prefab) decodes the glasses' RTSP stream; we register for its
//    decoded frames as YUV420P and keep the latest Y plane, which is the
//    grayscale image Immersal wants (SmartWear guide §5.3).
// 2. Immersal's native plugin (libPosePlugin.so, SDK 2.4.0), dlopen'd so a build
//    without it still runs and falls back to cloud localization.

#include <jni.h>
#include <dlfcn.h>
#include <android/log.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <vector>

#include "rtk_player_thin_api.h"

#define LOG_TAG "aiseebin-native"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// MARK: - Glasses frames

namespace {
std::mutex g_frame_mutex;
std::vector<uint8_t> g_luma;
int g_width = 0;
int g_height = 0;
int64_t g_pts = 0;
int64_t g_seq = 0;               // frame number of g_luma
int64_t g_captured_ms = 0;       // wall clock when g_luma arrived
bool g_accepting = false;        // cleared by nativeStop so a late callback cannot refill
std::atomic<int64_t> g_frame_count{0};
RTKPlayer *g_player = nullptr;

void OnVideoFrame(const VideoFrame *frame, void * /*user_data*/) {
    if (!frame || frame->format != kImageFormatYUV420P || !frame->data[0]) return;
    const int w = frame->width, h = frame->height;
    if (w <= 0 || h <= 0) return;
    const int64_t seq = g_frame_count.fetch_add(1) + 1;
    {
        std::lock_guard<std::mutex> lock(g_frame_mutex);
        if (!g_accepting) return;
        g_luma.resize(static_cast<size_t>(w) * h);
        for (int y = 0; y < h; ++y) {
            std::memcpy(g_luma.data() + static_cast<size_t>(y) * w,
                        frame->data[0] + static_cast<size_t>(y) * frame->linesize[0], w);
        }
        g_width = w;
        g_height = h;
        g_pts = frame->pts;
        g_seq = seq;
        g_captured_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
    }
}
}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_flowsxr_aiseebin_glasses_GlassesFrames_nativeStart(JNIEnv *, jclass) {
    if (!g_player) g_player = rtk_player_create();
    if (!g_player) { ALOGW("rtk_player_create failed"); return; }
    {
        std::lock_guard<std::mutex> lock(g_frame_mutex);
        g_accepting = true;
    }
    rtk_player_set_video_frame_callback(g_player, kImageFormatYUV420P, OnVideoFrame, nullptr);
    ALOGI("frame callback registered");
}

extern "C" JNIEXPORT void JNICALL
Java_com_flowsxr_aiseebin_glasses_GlassesFrames_nativeStop(JNIEnv *, jclass) {
    if (g_player) rtk_player_remove_video_frame_callback(g_player);
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    g_accepting = false;
    g_luma.clear();
    g_luma.shrink_to_fit();
    g_width = g_height = 0;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_flowsxr_aiseebin_glasses_GlassesFrames_nativeFrameCount(JNIEnv *, jclass) {
    return static_cast<jlong>(g_frame_count.load());
}

// Copies the latest Y plane. meta receives {width, height}, stamp {frame number, arrival ms};
// returns null before the first frame.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_flowsxr_aiseebin_glasses_GlassesFrames_nativeLatestLuma(JNIEnv *env, jclass, jintArray meta, jlongArray stamp) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (g_luma.empty() || g_width <= 0 || g_height <= 0) return nullptr;
    jbyteArray out = env->NewByteArray(static_cast<jsize>(g_luma.size()));
    if (!out) return nullptr;
    env->SetByteArrayRegion(out, 0, static_cast<jsize>(g_luma.size()),
                            reinterpret_cast<const jbyte *>(g_luma.data()));
    jint dims[2] = {g_width, g_height};
    env->SetIntArrayRegion(meta, 0, 2, dims);
    jlong st[2] = {g_seq, g_captured_ms};
    env->SetLongArrayRegion(stamp, 0, 2, st);
    return out;
}

// MARK: - Immersal native plugin

namespace {
struct PPVector3 { float x, y, z; };
struct PPQuaternion { float x, y, z, w; };
// SDK 2.4.0 layout (imdk-unity Runtime/Scripts/Core.cs): 48 bytes with the trailing rmse. Returned
// through caller memory on arm64, so a shorter struct here lets the plugin write past it.
struct LocalizeInfo { int handle; PPVector3 position; PPQuaternion rotation; int confidence; double rmse; };
static_assert(sizeof(LocalizeInfo) == 48, "LocalizeInfo must match Immersal SDK 2.4.0");

using LoadMapFn = int (*)(const char *);
using FreeMapFn = int (*)(int);
using SetIntegerFn = int (*)(const char *, int);
using LocalizeFn = LocalizeInfo (*)(int, int *, int, int, float *, void *, int, int, float *);

struct PosePlugin {
    bool ok = false;
    LoadMapFn loadMap = nullptr;
    FreeMapFn freeMap = nullptr;
    SetIntegerFn setInteger = nullptr;
    LocalizeFn localize = nullptr;
};

PosePlugin &Plugin() {
    static PosePlugin plugin = [] {
        PosePlugin p;
        void *lib = dlopen("libPosePlugin.so", RTLD_NOW);
        if (!lib) { ALOGW("libPosePlugin.so not loaded: %s", dlerror()); return p; }
        p.loadMap = reinterpret_cast<LoadMapFn>(dlsym(lib, "icvLoadMap"));
        p.freeMap = reinterpret_cast<FreeMapFn>(dlsym(lib, "icvFreeMap"));
        p.setInteger = reinterpret_cast<SetIntegerFn>(dlsym(lib, "icvSetInteger"));
        p.localize = reinterpret_cast<LocalizeFn>(dlsym(lib, "icvLocalize"));
        p.ok = p.loadMap && p.freeMap && p.setInteger && p.localize;
        if (p.ok) {
            // Same ceiling as iOS: frames are sent at 960 wide.
            p.setInteger("LocalizationMaxPixels", 960 * 720);
            // Measured on a Kirin 980: 4 threads take a no-match frame from ~4.4 s to ~3.5 s.
            p.setInteger("NumThreads", 4);
            ALOGI("Immersal native plugin ready");
        } else {
            ALOGW("libPosePlugin.so is missing symbols");
        }
        return p;
    }();
    return plugin;
}
}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_flowsxr_aiseebin_immersal_ImmersalNative_nativeAvailable(JNIEnv *, jclass) {
    return Plugin().ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_flowsxr_aiseebin_immersal_ImmersalNative_setInteger(JNIEnv *env, jclass, jstring name, jint value) {
    if (!Plugin().ok) return -1;
    const char *n = env->GetStringUTFChars(name, nullptr);
    int r = Plugin().setInteger(n, value);
    env->ReleaseStringUTFChars(name, n);
    return r;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_flowsxr_aiseebin_immersal_ImmersalNative_loadMap(JNIEnv *env, jclass, jbyteArray bytes) {
    if (!Plugin().ok) return -1;
    jbyte *data = env->GetByteArrayElements(bytes, nullptr);
    int handle = Plugin().loadMap(reinterpret_cast<const char *>(data));
    env->ReleaseByteArrayElements(bytes, data, JNI_ABORT);
    return handle;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_flowsxr_aiseebin_immersal_ImmersalNative_freeMap(JNIEnv *, jclass, jint handle) {
    return Plugin().ok ? Plugin().freeMap(handle) : -1;
}

// out = {handle, px, py, pz, qx, qy, qz, qw}; handle < 0 means no match.
extern "C" JNIEXPORT void JNICALL
Java_com_flowsxr_aiseebin_immersal_ImmersalNative_localize(JNIEnv *env, jclass, jintArray handles, jint width,
                                                          jint height, jfloatArray intrinsics, jbyteArray pixels,
                                                          jfloatArray out) {
    float result[8] = {-1, 0, 0, 0, 0, 0, 0, 1};
    if (Plugin().ok) {
        jsize n = env->GetArrayLength(handles);
        std::vector<int> hs(static_cast<size_t>(n));
        env->GetIntArrayRegion(handles, 0, n, hs.data());
        float k[4];
        env->GetFloatArrayRegion(intrinsics, 0, 4, k);
        float rot[4] = {0, 0, 0, 1};
        jbyte *px = env->GetByteArrayElements(pixels, nullptr);
        LocalizeInfo info = Plugin().localize(n, hs.data(), width, height, k, px, 1, 0, rot);
        env->ReleaseByteArrayElements(pixels, px, JNI_ABORT);
        result[0] = static_cast<float>(info.handle);
        result[1] = info.position.x; result[2] = info.position.y; result[3] = info.position.z;
        result[4] = info.rotation.x; result[5] = info.rotation.y; result[6] = info.rotation.z; result[7] = info.rotation.w;
    }
    env->SetFloatArrayRegion(out, 0, 8, result);
}
