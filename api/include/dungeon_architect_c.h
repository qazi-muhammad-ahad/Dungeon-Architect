#ifndef DUNGEON_ARCHITECT_C_H
#define DUNGEON_ARCHITECT_C_H

#include <stdint.h>

#if defined(_WIN32)
#  define DA_CALL __cdecl
#  if defined(DA_BUILDING_DLL)
#    define DA_API __declspec(dllexport)
#  else
#    define DA_API __declspec(dllimport)
#  endif
#else
#  define DA_CALL
#  define DA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ABI 1: cdecl, unmangled da_* exports, fixed-width values and opaque tokens.
 * Zero/released tokens are invalid; tokens are never reused. See native_api.md.
 * Byte buffers are caller-owned. UTF-8 lengths exclude a NUL terminator.
 * Non-null pointers must reference accessible storage of the stated length. */
#define DA_ABI_VERSION 1u
#define DA_PROJECT_SCHEMA 1u
#define DA_MAX_INPUT_BYTES (16u * 1024u * 1024u)
#define DA_MAX_TRACE_BATCH 128u
typedef uint32_t da_context;
typedef uint32_t da_job;
typedef uint32_t da_status;
#define DA_OK 0u
#define DA_INVALID_ARGUMENT 1u
#define DA_INVALID_HANDLE 2u
#define DA_BUSY 3u
#define DA_VERSION_MISMATCH 4u
#define DA_BUFFER_TOO_SMALL 5u
#define DA_NOT_READY 6u
#define DA_RESOURCE_FAILURE 7u
#define DA_INTERNAL_ERROR 8u
#define DA_STALE_RESULT 9u
#define DA_VALIDATE 1u
#define DA_GENERATE 2u
#define DA_ROUTE 3u
#define DA_OPTIMIZE 4u
#define DA_RUN 5u
#define DA_NORMALIZE 6u
#define DA_NEW_PROJECT 7u
#define DA_EDIT 8u
#define DA_REALLOCATE 9u
#define DA_GENERATE_DUNGEON 10u
#define DA_SCENARIO 11u
/* REALLOCATE requires this context's retained routed layout and unchanged
 * geometry dependencies. Returns a pipeline report without regenerating.
 * GENERATE_DUNGEON returns a pipeline report with geometry and no allocation. */
/* EDIT accepts {project_json:string,command:object}; returns canonical source and
 * editor_analysis. Transactions preserve source room locks and retained output. */
/* NORMALIZE validates/canonicalizes source; NEW_PROJECT returns core defaults.
 * Both return project_json as an exact JSON string and preserve retained results. */
#define DA_PENDING 0u
#define DA_RUNNING 1u
#define DA_FINISHED 2u
#define DA_REPORT 1u
#define DA_METRICS 2u
#define DA_DETAILED_TRACE 1u

/* Retained bootstrap probes for existing loaders. */
DA_API uint32_t DA_CALL da_bootstrap_abi_version(void);
DA_API uint32_t DA_CALL da_pointer_bits(void);
DA_API da_status DA_CALL da_context_create(uint32_t abi, uint32_t schema, da_context* out);
/* BUSY until all referencing jobs have been released. */
DA_API da_status DA_CALL da_context_release(da_context context);
/* Copies input. One outstanding job/context; max_events <= 4096 per stage. */
DA_API da_status DA_CALL da_job_create(da_context context, uint32_t operation,
    const uint8_t* input, uint32_t length, uint32_t max_events, uint32_t flags, da_job* out);
/* Blocking native call: use a worker thread. Wasm: ccall with async:true.
 * Execute exactly once. No registry lock is held during algorithms. */
DA_API da_status DA_CALL da_job_execute(da_job job);
DA_API da_status DA_CALL da_job_cancel(da_job job);
/* Stage: 0 queued, 1 validation, 2 generation, 3 routing, 4 allocation,
 * 5 serialization, 6 done; not a percentage. Outcome meaningful only FINISHED:
 * 0 success, 1 invalid, 2 exhausted, 3 unsupported size, 4 unsupported schema,
 * 5 cancelled, 6 resource, 7 IO, 8 stale, 9 internal. */
DA_API da_status DA_CALL da_job_poll(da_job job, uint32_t* state, uint32_t* stage, uint32_t* outcome);
/* Probe with NULL,0. No partial writes or trailing NUL. FINISHED jobs only. */
DA_API da_status DA_CALL da_job_read(da_job job, uint32_t kind, uint8_t* buffer, uint32_t capacity, uint32_t* required);
DA_API da_status DA_CALL da_job_trace(da_job job, uint32_t cursor, uint32_t count,
    uint8_t* buffer, uint32_t capacity, uint32_t* required);
/* Last successful report survives errors/cancellation and includes its source. */
DA_API da_status DA_CALL da_context_read(da_context context, uint8_t* buffer, uint32_t capacity, uint32_t* required);
/* BUSY while executing. Pending jobs can be discarded without execution. */
DA_API da_status DA_CALL da_job_release(da_job job);
/* One authoritative cardinal tile step on retained routed geometry.
 * snapshot_job guards against mixing revisions. Phases 14/15 add full controls. */
DA_API da_status DA_CALL da_context_step(da_context context, da_job snapshot_job,
    int32_t x, int32_t y, int32_t dx, int32_t dy, int32_t* out_x, int32_t* out_y);

#ifdef __cplusplus
}
#endif
#endif
