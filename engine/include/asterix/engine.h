#ifndef ASTERIX_ENGINE_ENGINE_H_
#define ASTERIX_ENGINE_ENGINE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ASTERIX_ENGINE_ABI_VERSION 1u
#define ASTERIX_ENGINE_MAX_COMMANDS 256u
#define ASTERIX_ENGINE_MAX_EVENTS 256u

typedef struct AsterixEngineHandle AsterixEngineHandle;

typedef uint32_t AsterixStatus;
#define ASTERIX_STATUS_OK 0u
#define ASTERIX_STATUS_INVALID_ARGUMENT 1u
#define ASTERIX_STATUS_INCOMPATIBLE_ABI 2u
#define ASTERIX_STATUS_QUEUE_FULL 3u
#define ASTERIX_STATUS_STOPPED 4u
#define ASTERIX_STATUS_INTERNAL_ERROR 5u

typedef uint32_t AsterixCommandType;
#define ASTERIX_COMMAND_SET_PAUSED 1u
#define ASTERIX_COMMAND_ADD_SCORE 2u

typedef uint32_t AsterixEventType;
#define ASTERIX_EVENT_COMMAND_APPLIED 1u

typedef struct AsterixEngineConfig {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t command_capacity;
  uint32_t event_capacity;
} AsterixEngineConfig;

typedef struct AsterixCommand {
  uint32_t type;
  uint32_t reserved;
  int64_t value;
} AsterixCommand;

typedef struct AsterixCommandBatch {
  uint32_t struct_size;
  uint32_t abi_version;
  const AsterixCommand* commands;
  size_t command_count;
} AsterixCommandBatch;

typedef struct AsterixUiSnapshot {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t generation;
  int64_t score;
  uint32_t paused;
  uint32_t pending_commands;
  uint32_t dropped_event_count;
  uint32_t reserved;
} AsterixUiSnapshot;

typedef struct AsterixEvent {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t type;
  uint32_t command_type;
  int64_t value;
  uint64_t generation;
} AsterixEvent;

#define ASTERIX_ENGINE_CONFIG_V1_SIZE \
  ((uint32_t)(offsetof(AsterixEngineConfig, event_capacity) + \
              sizeof(((AsterixEngineConfig*)0)->event_capacity)))
#define ASTERIX_COMMAND_BATCH_V1_SIZE \
  ((uint32_t)(offsetof(AsterixCommandBatch, command_count) + \
              sizeof(((AsterixCommandBatch*)0)->command_count)))
#define ASTERIX_UI_SNAPSHOT_V1_SIZE \
  ((uint32_t)(offsetof(AsterixUiSnapshot, reserved) + \
              sizeof(((AsterixUiSnapshot*)0)->reserved)))

uint32_t asterix_engine_abi_version(void);
AsterixStatus asterix_engine_create(const AsterixEngineConfig* config,
                                    AsterixEngineHandle** out_handle);
void asterix_engine_destroy(AsterixEngineHandle* handle);
AsterixStatus asterix_engine_enqueue(AsterixEngineHandle* handle,
                                     const AsterixCommandBatch* batch);
AsterixStatus asterix_engine_copy_ui_snapshot(AsterixEngineHandle* handle,
                                              AsterixUiSnapshot* out_snapshot);
AsterixStatus asterix_engine_drain_events(AsterixEngineHandle* handle,
                                          AsterixEvent* events,
                                          size_t* in_out_event_count);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // ASTERIX_ENGINE_ENGINE_H_
