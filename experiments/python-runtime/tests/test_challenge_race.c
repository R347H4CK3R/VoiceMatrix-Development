#include <assert.h>
#include <pthread.h>
#include "../VoiceMatrix/PythonRuntime/VMChallengeLifetime.h"
typedef struct { pthread_mutex_t lock; pthread_cond_t condition; VMChallengeLifetime life; bool expired, launched, accepted; } Fixture;
static void *delayedMain(void *arg) {
 Fixture *f=arg;pthread_mutex_lock(&f->lock);
 while (!f->expired) pthread_cond_wait(&f->condition,&f->lock);
 f->launched=VMLifetimeStart(&f->life,2);
 pthread_mutex_unlock(&f->lock);return NULL;
}
static void *lateCallback(void *arg) {
 Fixture *f=arg;pthread_mutex_lock(&f->lock);
 while (!f->expired) pthread_cond_wait(&f->condition,&f->lock);
 f->accepted=VMLifetimeComplete(&f->life,2);
 pthread_mutex_unlock(&f->lock);return NULL;
}
static void expire(Fixture *f) {
 pthread_mutex_lock(&f->lock);VMLifetimeExpire(&f->life);f->expired=true;
 pthread_cond_signal(&f->condition);pthread_mutex_unlock(&f->lock);
}
int main(void) {
 for (int i=0;i<1000;i++) {
  Fixture delayed={PTHREAD_MUTEX_INITIALIZER,PTHREAD_COND_INITIALIZER,VMLifetimeMake(30),false,false,false};
  pthread_t mainThread;assert(!pthread_create(&mainThread,NULL,delayedMain,&delayed));
  expire(&delayed);pthread_join(mainThread,NULL);assert(!delayed.launched);
  pthread_mutex_destroy(&delayed.lock);pthread_cond_destroy(&delayed.condition);
  Fixture late={PTHREAD_MUTEX_INITIALIZER,PTHREAD_COND_INITIALIZER,VMLifetimeMake(30),false,false,false};
  assert(VMLifetimeStart(&late.life,1));
  pthread_t callback;assert(!pthread_create(&callback,NULL,lateCallback,&late));
  expire(&late);pthread_join(callback,NULL);assert(!late.accepted);
  pthread_mutex_destroy(&late.lock);pthread_cond_destroy(&late.condition);
 }
 return 0;
}
