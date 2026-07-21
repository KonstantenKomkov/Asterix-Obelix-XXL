#include "asterix/engine.h"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <new>
#include <thread>

namespace {

template <typename T, std::size_t Maximum>
class SpscRing {
 public:
  explicit SpscRing(std::size_t capacity) : capacity_(capacity) {}

  bool try_push_batch(const T* values, std::size_t count) {
    const auto write = write_.load(std::memory_order_relaxed);
    const auto read = read_.load(std::memory_order_acquire);
    if (count > capacity_ - (write - read)) {
      return false;
    }
    for (std::size_t index = 0; index < count; ++index) {
      storage_[(write + index) % capacity_] = values[index];
    }
    write_.store(write + count, std::memory_order_release);
    return true;
  }

  bool try_push(const T& value) { return try_push_batch(&value, 1); }

  bool try_pop(T& value) {
    const auto read = read_.load(std::memory_order_relaxed);
    const auto write = write_.load(std::memory_order_acquire);
    if (read == write) {
      return false;
    }
    value = storage_[read % capacity_];
    read_.store(read + 1, std::memory_order_release);
    return true;
  }

  std::size_t size() const {
    return write_.load(std::memory_order_acquire) -
           read_.load(std::memory_order_acquire);
  }

 private:
  std::array<T, Maximum> storage_{};
  const std::size_t capacity_;
  alignas(64) std::atomic<std::size_t> write_{0};
  alignas(64) std::atomic<std::size_t> read_{0};
};

bool valid_header(uint32_t struct_size,
                  uint32_t expected_size,
                  uint32_t abi_version) {
  return struct_size >= expected_size &&
         abi_version == ASTERIX_ENGINE_ABI_VERSION;
}

}  // namespace

struct AsterixEngineHandle {
  AsterixEngineHandle(std::size_t command_capacity,
                      std::size_t event_capacity)
      : commands(command_capacity), events(event_capacity) {
    snapshots[0] = {sizeof(AsterixUiSnapshot), ASTERIX_ENGINE_ABI_VERSION,
                    0, 0, 0, 0, 0, 0};
    snapshots[1] = snapshots[0];
    worker = std::thread([this] { run(); });
  }

  ~AsterixEngineHandle() {
    stopped.store(true, std::memory_order_release);
    wake.notify_one();
    if (worker.joinable()) {
      worker.join();
    }
  }

  void run() {
    while (!stopped.load(std::memory_order_acquire)) {
      AsterixCommand command{};
      if (!commands.try_pop(command)) {
        std::unique_lock lock(wake_mutex);
        wake.wait(lock, [this] {
          return stopped.load(std::memory_order_acquire) || commands.size() > 0;
        });
        continue;
      }

      uint64_t generation = 0;
      {
        std::lock_guard lock(snapshot_mutex);
        const auto front = front_snapshot.load(std::memory_order_relaxed);
        const auto back = 1u - front;
        snapshots[back] = snapshots[front];
        snapshots[back].generation += 1;
        if (command.type == ASTERIX_COMMAND_SET_PAUSED) {
          snapshots[back].paused = command.value != 0 ? 1u : 0u;
        } else if (command.type == ASTERIX_COMMAND_ADD_SCORE) {
          snapshots[back].score += command.value;
        }
        snapshots[back].pending_commands =
            static_cast<uint32_t>(commands.size());
        generation = snapshots[back].generation;
        front_snapshot.store(back, std::memory_order_release);
      }

      AsterixEvent event{sizeof(AsterixEvent), ASTERIX_ENGINE_ABI_VERSION,
                         ASTERIX_EVENT_COMMAND_APPLIED, command.type,
                         command.value, generation};
      if (!events.try_push(event)) {
        dropped_event_count.fetch_add(1, std::memory_order_relaxed);
      }
    }
  }

  SpscRing<AsterixCommand, ASTERIX_ENGINE_MAX_COMMANDS> commands;
  SpscRing<AsterixEvent, ASTERIX_ENGINE_MAX_EVENTS> events;
  AsterixUiSnapshot snapshots[2]{};
  std::mutex snapshot_mutex;
  std::atomic<uint32_t> front_snapshot{0};
  std::atomic<bool> stopped{false};
  std::atomic<uint32_t> dropped_event_count{0};
  std::mutex wake_mutex;
  std::condition_variable wake;
  std::thread worker;
};

extern "C" uint32_t asterix_engine_abi_version(void) {
  return ASTERIX_ENGINE_ABI_VERSION;
}

extern "C" AsterixStatus asterix_engine_create(
    const AsterixEngineConfig* config,
    AsterixEngineHandle** out_handle) {
  if (config == nullptr || out_handle == nullptr) {
    return ASTERIX_STATUS_INVALID_ARGUMENT;
  }
  *out_handle = nullptr;
  if (!valid_header(config->struct_size, ASTERIX_ENGINE_CONFIG_V1_SIZE,
                    config->abi_version)) {
    return config->abi_version == ASTERIX_ENGINE_ABI_VERSION
               ? ASTERIX_STATUS_INVALID_ARGUMENT
               : ASTERIX_STATUS_INCOMPATIBLE_ABI;
  }
  if (config->command_capacity == 0 ||
      config->command_capacity > ASTERIX_ENGINE_MAX_COMMANDS ||
      config->event_capacity == 0 ||
      config->event_capacity > ASTERIX_ENGINE_MAX_EVENTS) {
    return ASTERIX_STATUS_INVALID_ARGUMENT;
  }
  try {
    *out_handle = new AsterixEngineHandle(config->command_capacity,
                                          config->event_capacity);
    return ASTERIX_STATUS_OK;
  } catch (...) {
    return ASTERIX_STATUS_INTERNAL_ERROR;
  }
}

extern "C" void asterix_engine_destroy(AsterixEngineHandle* handle) {
  delete handle;
}

extern "C" AsterixStatus asterix_engine_enqueue(
    AsterixEngineHandle* handle,
    const AsterixCommandBatch* batch) {
  if (handle == nullptr || batch == nullptr ||
      !valid_header(batch->struct_size, ASTERIX_COMMAND_BATCH_V1_SIZE,
                    batch->abi_version) ||
      (batch->command_count > 0 && batch->commands == nullptr)) {
    return ASTERIX_STATUS_INVALID_ARGUMENT;
  }
  if (handle->stopped.load(std::memory_order_acquire)) {
    return ASTERIX_STATUS_STOPPED;
  }
  for (std::size_t index = 0; index < batch->command_count; ++index) {
    const auto type = batch->commands[index].type;
    if (type != ASTERIX_COMMAND_SET_PAUSED &&
        type != ASTERIX_COMMAND_ADD_SCORE) {
      return ASTERIX_STATUS_INVALID_ARGUMENT;
    }
  }
  if (!handle->commands.try_push_batch(batch->commands, batch->command_count)) {
    return ASTERIX_STATUS_QUEUE_FULL;
  }
  handle->wake.notify_one();
  return ASTERIX_STATUS_OK;
}

extern "C" AsterixStatus asterix_engine_copy_ui_snapshot(
    AsterixEngineHandle* handle,
    AsterixUiSnapshot* out_snapshot) {
  if (handle == nullptr || out_snapshot == nullptr ||
      !valid_header(out_snapshot->struct_size, ASTERIX_UI_SNAPSHOT_V1_SIZE,
                    out_snapshot->abi_version)) {
    return ASTERIX_STATUS_INVALID_ARGUMENT;
  }
  std::lock_guard lock(handle->snapshot_mutex);
  const auto front = handle->front_snapshot.load(std::memory_order_relaxed);
  *out_snapshot = handle->snapshots[front];
  out_snapshot->dropped_event_count =
      handle->dropped_event_count.load(std::memory_order_relaxed);
  return ASTERIX_STATUS_OK;
}

extern "C" AsterixStatus asterix_engine_drain_events(
    AsterixEngineHandle* handle,
    AsterixEvent* events,
    size_t* in_out_event_count) {
  if (handle == nullptr || in_out_event_count == nullptr ||
      (*in_out_event_count > 0 && events == nullptr)) {
    return ASTERIX_STATUS_INVALID_ARGUMENT;
  }
  const auto capacity = *in_out_event_count;
  std::size_t count = 0;
  while (count < capacity && handle->events.try_pop(events[count])) {
    ++count;
  }
  *in_out_event_count = count;
  return ASTERIX_STATUS_OK;
}
