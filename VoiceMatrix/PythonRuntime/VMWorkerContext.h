#ifndef VM_WORKER_CONTEXT_H
#define VM_WORKER_CONTEXT_H
#include <pthread.h>
typedef struct { pthread_key_t key; } VMWorkerContext;
static inline int VMWorkerContextInit(VMWorkerContext *c) {return pthread_key_create(&c->key,NULL);}
static inline int VMWorkerContextSet(VMWorkerContext *c,void *request) {return pthread_setspecific(c->key,request);}
static inline void *VMWorkerContextGet(VMWorkerContext *c) {return pthread_getspecific(c->key);}
#endif
