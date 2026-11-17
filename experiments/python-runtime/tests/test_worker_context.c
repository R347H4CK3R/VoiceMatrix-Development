#include <assert.h>
#include <pthread.h>
#include "../VoiceMatrix/PythonRuntime/VMWorkerContext.h"
static VMWorkerContext key;
static void *child(void *unused) { (void)unused;assert(VMWorkerContextGet(&key)==NULL);return NULL; }
int main(void) {
 assert(VMWorkerContextInit(&key)==0);int request=42;VMWorkerContextSet(&key,&request);
 assert(VMWorkerContextGet(&key)==&request);
 pthread_t t;assert(!pthread_create(&t,NULL,child,NULL));pthread_join(t,NULL);
 assert(VMWorkerContextGet(&key)==&request);VMWorkerContextSet(&key,NULL);assert(!VMWorkerContextGet(&key));return 0;
}
