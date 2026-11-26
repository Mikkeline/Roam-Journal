// Generated from fictional fixtures; the embedded key is NOT a secret.
#include "NativeCatalog.h"
namespace {
const uint8_t demoKey[] = {249, 253, 254, 175, 120, 248, 187, 137, 33, 80, 199, 63, 77, 130, 200, 87, 227, 127, 200, 243, 192, 43, 0, 82, 244, 116, 175, 131, 170, 16, 71, 136};
const uint8_t payload0[] = {197, 61, 155, 225, 213, 29, 4, 32, 248, 53, 19, 57, 36, 133, 144, 124, 151, 15, 226, 0, 93, 40, 201, 175, 193, 162, 41, 137, 243, 135, 109, 198, 229, 189, 91, 42, 16, 122, 148, 202, 153, 104, 190};
const uint8_t payload1[] = {165, 97, 15, 87, 115, 200, 89, 34, 215, 91, 211, 186, 78, 66, 98, 35, 34, 125, 73, 254, 6, 1, 188, 96, 12, 28, 88, 176, 219, 107, 245, 223, 130, 28, 153, 66, 94, 99, 221, 185, 95, 190, 101, 235, 78, 120, 250};
const uint8_t payload2[] = {3, 11, 215, 101, 169, 32, 73, 50, 11, 126, 215, 231, 205, 181, 127, 137, 92, 251, 228, 36, 55, 235, 216, 100, 204, 226, 92, 182, 55, 198, 117, 197, 109, 242, 132, 101, 132, 13, 170, 251, 202, 235};
}
extern "C" const uint8_t *trail_catalog_key(size_t *count) {
    if (!count) return nullptr;
    *count = sizeof(demoKey);
    return demoKey;
}
extern "C" const uint8_t *trail_catalog_payload(int32_t identifier, size_t *count) {
    if (!count) return nullptr;
    switch (identifier) {
    case 0: *count = sizeof(payload0); return payload0;
    case 1: *count = sizeof(payload1); return payload1;
    case 2: *count = sizeof(payload2); return payload2;
    default: *count = 0; return nullptr;
    }
}
