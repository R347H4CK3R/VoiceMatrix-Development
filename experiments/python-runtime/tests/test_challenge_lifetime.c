#include <assert.h>
#include "../VoiceMatrix/PythonRuntime/VMChallengeLifetime.h"
int main(void) {
 VMChallengeLifetime delayed=VMLifetimeMake(10);
 assert(!VMLifetimeStart(&delayed,11)); // main dispatch after deadline cannot launch
 assert(!VMLifetimeComplete(&delayed,11));
 VMChallengeLifetime late=VMLifetimeMake(10);
 assert(VMLifetimeStart(&late,1));
 assert(VMLifetimeExpire(&late)); // cancel exactly the launched job
 assert(!VMLifetimeComplete(&late,2)); // late callback cannot revive expired job
 assert(!VMLifetimeExpire(&late)); // cancellation is one-shot
 VMChallengeLifetime deadline=VMLifetimeMake(10);
 assert(VMLifetimeStart(&deadline,1));
 assert(!VMLifetimeComplete(&deadline,10)); // no acceptance at/after deadline
 assert(VMLifetimeExpire(&deadline));
 VMChallengeLifetime next=VMLifetimeMake(20);
 assert(VMLifetimeStart(&next,12));
 assert(!VMLifetimeExpire(&late));
 assert(VMLifetimeComplete(&next,13)); // unrelated request untouched
 assert(!VMLifetimeExpire(&next)); // completed job not cancelled
 assert(!VMLifetimeComplete(&next,14)); // duplicate callback ignored
 return 0;
}
