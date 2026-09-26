// Simulator stand-ins for libPosePlugin.a, which ships an arm64 device slice
// only. Every call fails the way the real library fails when nothing matches,
// so the app and its tests link and run on the simulator. Excluded from
// device builds in project.yml.
#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include "PosePlugin.h"

int icvLoadMap(const char *bytes) { (void)bytes; return -1; }
int icvFreeMap(int mapHandle) { (void)mapHandle; return 0; }
int icvPointsGetCount(int mapHandle) { (void)mapHandle; return 0; }
int icvGetInteger(const char *param) { (void)param; return -1; }
int icvSetInteger(const char *param, int value) { (void)param; (void)value; return -1; }
struct LocalizeInfo icvLocalize(int n, int *handles, int width, int height, float *intrinsics,
                                void *pixels, int channels, int solverType, float *rot) {
    (void)n; (void)handles; (void)width; (void)height; (void)intrinsics;
    (void)pixels; (void)channels; (void)solverType; (void)rot;
    struct LocalizeInfo info = {0};
    info.handle = -1;
    return info;
}
#endif
