#ifndef VM_CHALLENGE_LIFETIME_H
#define VM_CHALLENGE_LIFETIME_H
#include <stdbool.h>
// Caller serializes all operations using its request lock. Time is monotonic.
typedef struct { double deadline; bool active, started, completed, cancellationIssued; } VMChallengeLifetime;
static inline VMChallengeLifetime VMLifetimeMake(double deadline) {
 return (VMChallengeLifetime){deadline,true,false,false,false};
}
static inline bool VMLifetimeStart(VMChallengeLifetime *s,double now) {
 if (!s->active || s->started || now>=s->deadline) {s->active=false;return false;}
 s->started=true;return true;
}
static inline bool VMLifetimeComplete(VMChallengeLifetime *s,double now) {
 if (!s->active || !s->started || now>=s->deadline) return false;
 s->active=false;s->completed=true;return true;
}
static inline bool VMLifetimeExpire(VMChallengeLifetime *s) {
 s->active=false;
 if (!s->started || s->completed || s->cancellationIssued) return false;
 s->cancellationIssued=true;return true;
}
#endif
