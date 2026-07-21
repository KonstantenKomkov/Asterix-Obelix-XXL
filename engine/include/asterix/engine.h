#ifndef ASTERIX_ENGINE_ENGINE_H_
#define ASTERIX_ENGINE_ENGINE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Build-level API used to verify that the native core is linked correctly.
// The versioned runtime transport is introduced separately in task 21.
#define ASTERIX_ENGINE_CORE_VERSION 1u

uint32_t asterix_engine_core_version(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // ASTERIX_ENGINE_ENGINE_H_
