#import "VMPythonRuntime.h"
#import <Python/Python.h>
#import "VMChallengeLifetime.h"
#import "VMWorkerContext.h"
static VMJavaScriptEvaluator vmEvaluator;
static VMJavaScriptCanceller vmCanceller;
static dispatch_queue_t vmQueue;
static BOOL vmReady = NO;
@interface VMResolverRequest : NSObject
@property(nonatomic) BOOL cancelled;
@property(nonatomic, copy) dispatch_block_t cancelChallenge;
@end
@implementation VMResolverRequest
@end
static NSMutableDictionary<NSString *,VMResolverRequest *> *vmRequests;
static VMWorkerContext vmWorkerContext;
static BOOL vmWorkerContextReady;
static VMResolverRequest *VMCurrentRequest(void) {
    return vmWorkerContextReady ? (__bridge VMResolverRequest *)VMWorkerContextGet(&vmWorkerContext) : nil;
}
static BOOL VMCancelled(VMResolverRequest *request) {
    @synchronized(request) {return request.cancelled;}
}
static PyObject *vmIsCancelled(PyObject *self, PyObject *args) {
    VMResolverRequest *context=VMCurrentRequest();
    return PyBool_FromLong(!context || VMCancelled(context));
}
static NSError *VMError(void) {
    return [NSError errorWithDomain:@"VoiceMatrix.Python" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The on-device media resolver is unavailable."}];
}
static PyObject *vmEvaluate(PyObject *self, PyObject *args) {
    VMResolverRequest *context=VMCurrentRequest();
    if (!context) {PyErr_SetString(PyExc_RuntimeError,"resolver_worker_required");return NULL;}
    const char *scriptUTF8, *inputUTF8;
    if (!PyArg_ParseTuple(args, "ss", &scriptUTF8, &inputUTF8)) return NULL;
    NSString *script = [NSString stringWithUTF8String:scriptUTF8];
    NSString *input = [NSString stringWithUTF8String:inputUTF8];
    if (VMCancelled(context) || [NSThread isMainThread] || !vmEvaluator || !vmCanceller || [script lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4*1024*1024 || [input lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024*1024) {
        PyErr_SetString(PyExc_RuntimeError, "challenge_unavailable"); return NULL;
    }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    // Recursive lock permits a provider's synchronous fail-closed completion.
    // Hold it across launch so expiration cannot win between the guard and launch.
    NSRecursiveLock *lock = [NSRecursiveLock new];
    NSString *requestID = NSUUID.UUID.UUIDString;
    __block NSString *output = nil;
    __block VMChallengeLifetime lifetime = VMLifetimeMake(NSProcessInfo.processInfo.systemUptime + 30);
    dispatch_time_t waitDeadline = dispatch_time(DISPATCH_TIME_NOW, 30*NSEC_PER_SEC);
    dispatch_block_t cancelChallenge = ^{
        [lock lock];
        BOOL cancelStarted = VMLifetimeExpire(&lifetime);
        [lock unlock];
        dispatch_semaphore_signal(done);
        if (cancelStarted) dispatch_async(dispatch_get_main_queue(), ^{vmCanceller(requestID);});
    };
    @synchronized(context) {context.cancelChallenge = cancelChallenge;}
    if (VMCancelled(context)) cancelChallenge();
    dispatch_async(dispatch_get_main_queue(), ^{
        [lock lock];
        if (!VMLifetimeStart(&lifetime, NSProcessInfo.processInfo.systemUptime)) {
            [lock unlock]; dispatch_semaphore_signal(done); return;
        }
        vmEvaluator(script, input, requestID, ^(NSString *value, NSError *error) {
            [lock lock];
            if (VMLifetimeComplete(&lifetime, NSProcessInfo.processInfo.systemUptime) && !error &&
                [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 1024*1024) output = [value copy];
            [lock unlock]; dispatch_semaphore_signal(done);
        });
        [lock unlock];
    });
    __block BOOL needsCancel = NO;
    NSString *result = nil;
    Py_BEGIN_ALLOW_THREADS
    long waitResult = dispatch_semaphore_wait(done, waitDeadline);
    // Close acceptance BEFORE reacquiring the GIL, even if another Python thread
    // is holding it. Timeout can never accept a callback that arrives afterwards.
    [lock lock];
    needsCancel = VMLifetimeExpire(&lifetime);
    result = waitResult == 0 ? output : nil;
    [lock unlock];
    if (needsCancel) dispatch_async(dispatch_get_main_queue(), ^{ vmCanceller(requestID); });
    Py_END_ALLOW_THREADS
    @synchronized(context) {context.cancelChallenge = nil;}
    if (VMCancelled(context)) result = nil;
    if (!result) { PyErr_SetString(PyExc_RuntimeError, "challenge_unavailable"); return NULL; }
    return PyUnicode_FromString([result UTF8String]);
}
static PyMethodDef vmMethods[] = {{"is_cancelled",vmIsCancelled,METH_NOARGS,"Cooperative resolver cancellation."},{"evaluate",vmEvaluate,METH_VARARGS,"Evaluate isolated on-device JavaScript."},{NULL,NULL,0,NULL}};
static struct PyModuleDef vmModule = {PyModuleDef_HEAD_INIT,"vm_webkit",NULL,-1,vmMethods};
static PyObject *PyInit_vm_webkit(void) {return PyModule_Create(&vmModule);}
static BOOL VMInitialize(void) {
    if (vmReady) return YES;
    if (Py_IsInitialized()) return NO; // Never attach to an unknown interpreter.
    NSString *base = NSBundle.mainBundle.resourcePath;
    NSString *home = [base stringByAppendingPathComponent:@"python"];
    NSString *packages = [base stringByAppendingPathComponent:@"app_packages"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[home stringByAppendingPathComponent:@"lib/python3.13/encodings/__init__.py"]]) return NO;
    if (PyImport_AppendInittab("vm_webkit",PyInit_vm_webkit) != 0) return NO;
    PyConfig config; PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0; config.site_import = 0; config.install_signal_handlers = 0;
    PyStatus status = PyConfig_SetBytesString(&config, &config.home, home.UTF8String);
    if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) return NO;
    PyObject *path=PySys_GetObject("path");
    PyObject *p=PyUnicode_FromString(packages.UTF8String);
    BOOL valid = p && path && PyList_Insert(path,0,p)==0;
    Py_XDECREF(p);
    if (PyErr_Occurred()) PyErr_Clear();
    vmReady = valid;
    PyEval_SaveThread();
    return valid;
}
typedef NS_ENUM(NSUInteger, VMOperation) {
    VMOperationResolve,
    VMOperationMKVStage
};

@interface VMPythonRuntime ()
- (NSString *)invokeJSON:(NSString *)request operation:(VMOperation)operation completion:(void (^)(NSString *, NSError *))completion;
@end

@implementation VMPythonRuntime
- (instancetype)initWithJavaScriptEvaluator:(VMJavaScriptEvaluator)evaluator canceller:(VMJavaScriptCanceller)canceller {
    if ((self=[super init])) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ vmWorkerContextReady=VMWorkerContextInit(&vmWorkerContext)==0; vmRequests=[NSMutableDictionary new]; vmEvaluator=[evaluator copy]; vmCanceller=[canceller copy]; vmQueue=dispatch_queue_create("com.voicematrix.python",DISPATCH_QUEUE_SERIAL); });
    }
    return self;
}
- (NSString *)resolveJSON:(NSString *)request completion:(void (^)(NSString *, NSError *))completion {
    return [self invokeJSON:request operation:VMOperationResolve completion:completion];
}
- (NSString *)decideMKVStageJSON:(NSString *)request completion:(void (^)(NSString *, NSError *))completion {
    return [self invokeJSON:request operation:VMOperationMKVStage completion:completion];
}
- (NSString *)invokeJSON:(NSString *)request operation:(VMOperation)operation completion:(void (^)(NSString *, NSError *))completion {
    NSString *copy=[request copy];
    BOOL stage=operation==VMOperationMKVStage;
    NSString *identity=NSUUID.UUID.UUIDString;
    VMResolverRequest *context=[VMResolverRequest new];
    @synchronized(vmRequests) {vmRequests[identity]=context;}
    dispatch_async(vmQueue, ^{
        @autoreleasepool {
            BOOL owned=vmWorkerContextReady && VMWorkerContextSet(&vmWorkerContext,(__bridge void *)context)==0;
            NSString *result=nil;
            NSUInteger inputLimit=stage ? 4096 : 16384;
            Py_ssize_t outputLimit=stage ? 4096 : 1024*1024;
            if (owned && !VMCancelled(context) && copy && [copy lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= inputLimit && VMInitialize()) {
                PyGILState_STATE gil=PyGILState_Ensure();
                PyObject *module=PyImport_ImportModule(stage ? "voicematrix_mkv_stage" : "voicematrix_resolver");
                PyObject *fn=module?PyObject_GetAttrString(module,stage ? "decide" : "resolve"):NULL;
                PyObject *arg=NULL;
                if (stage) {
                    NSData *data=[copy dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
                    if (data && data.length<=inputLimit) {
                        arg=PyUnicode_DecodeUTF8(data.length ? data.bytes : "", (Py_ssize_t)data.length, "strict");
                    }
                } else {
                    arg=PyUnicode_FromString(copy.UTF8String);
                }
                PyObject *response=fn && PyCallable_Check(fn) && arg?PyObject_CallOneArg(fn,arg):NULL;
                if (response && PyUnicode_Check(response)) {
                    Py_ssize_t size=0; const char *utf8=PyUnicode_AsUTF8AndSize(response,&size);
                    if (utf8 && size<=outputLimit) result=[[NSString alloc] initWithBytes:utf8 length:(NSUInteger)size encoding:NSUTF8StringEncoding];
                }
                Py_XDECREF(response);Py_XDECREF(arg);Py_XDECREF(fn);Py_XDECREF(module);
                // Never expose URLs, cookies or raw upstream exception strings through logs.
                if (PyErr_Occurred()) PyErr_Clear();
                PyGILState_Release(gil);
            }
            if (owned) VMWorkerContextSet(&vmWorkerContext,NULL);
            dispatch_async(dispatch_get_main_queue(), ^{
                // Removing the identity is the completion commit point: later cancellation
                // is a no-op because delivery has already begun.
                @synchronized(vmRequests) { [vmRequests removeObjectForKey:identity]; }
                if (VMCancelled(context)) completion(nil,VMError());
                else completion(result,result?nil:VMError());
            });
        }
    });
    return identity;
}
- (void)cancelRequest:(NSString *)requestID {
    VMResolverRequest *context;
    @synchronized(vmRequests) {context=vmRequests[requestID];}
    if (!context) return;
    dispatch_block_t cancel;
    @synchronized(context) {context.cancelled=YES;cancel=context.cancelChallenge;}
    if (cancel) cancel();
}
@end
