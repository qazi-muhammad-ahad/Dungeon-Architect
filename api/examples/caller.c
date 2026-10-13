/* Standalone C caller. No C++ headers, structs, allocator or exceptions. */
#include "dungeon_architect_c.h"
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
int main(int argc, char** argv) {
    FILE* file = NULL;
    uint8_t* input = NULL;
    uint8_t* output = NULL;
    da_context context = 0;
    da_job job = 0;
    uint32_t length = 0, state = 0, stage = 0, outcome = 0;
    int result = 1;
    long size;
    if (argc < 2 || argc > 3) { fprintf(stderr,"Usage: dungeon_api_caller PROJECT [operation 1..5]\n"); return 64; }
    file = fopen(argv[1],"rb");
    if (!file || fseek(file,0,SEEK_END) || (size = ftell(file)) <= 0 || (unsigned long)size > DA_MAX_INPUT_BYTES || fseek(file,0,SEEK_SET)) goto cleanup;
    input = (uint8_t*)malloc((size_t)size);
    if (!input || fread(input,1,(size_t)size,file) != (size_t)size) goto cleanup;
    if (da_context_create(DA_ABI_VERSION,DA_PROJECT_SCHEMA,&context) != DA_OK) goto cleanup;
    if (da_job_create(context,argc == 3 ? (uint32_t)atoi(argv[2]) : DA_RUN,input,(uint32_t)size,256,0,&job) != DA_OK) goto cleanup;
    if (da_job_execute(job) != DA_OK || da_job_poll(job,&state,&stage,&outcome) != DA_OK) goto cleanup;
    if (da_job_read(job,DA_REPORT,NULL,0,&length) != DA_BUFFER_TOO_SMALL) goto cleanup;
    output = (uint8_t*)malloc(length);
    if (!output || da_job_read(job,DA_REPORT,output,length,&length) != DA_OK) goto cleanup;
#ifdef _WIN32
    _setmode(_fileno(stdout),_O_BINARY);
#endif
    if (fwrite(output,1,length,stdout) != length) goto cleanup;
    result = outcome == 0 ? 0 : outcome == 1 ? 2 : outcome == 2 ? 7 : outcome == 3 || outcome == 4 ? 3 : outcome == 5 ? 6 : 5;
cleanup:
    free(output);
    free(input);
    if (file) fclose(file);
    if (job) da_job_release(job);
    if (context) da_context_release(context);
    if (result == 1) fprintf(stderr,"API caller failed to load input, run the job, or read its result.\n");
    return result;
}
