#ifndef TRAIL_NATIVE_CATALOG_H
#define TRAIL_NATIVE_CATALOG_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Immutable buffers owned by the catalog; callers copy before changing bytes.
const uint8_t *trail_catalog_key(size_t *count);
const uint8_t *trail_catalog_payload(int32_t identifier, size_t *count);
#ifdef __cplusplus
}
#endif
#endif
