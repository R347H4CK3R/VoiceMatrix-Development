import Foundation
var currentStage="initializing"
func stage(_ name:String) {
    currentStage=name
    FileHandle.standardError.write(Data(("SEPARATION_STORE_STAGE: "+name+"\n").utf8))
}
func runProbe() throws {
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let store=SeparationStore(root:root)
try store.prepare()
let samples:[Float]=[0.25,-0.5,0.75,0.125]
stage("publish initial pair")
let result=try store.publish(vocals:samples,accompaniment:samples,inputName:"test.wav",inputSHA256:String(repeating:"a",count:64))
precondition(result.frames==2 && result.gain==1)
stage("reload initial pair")
let listed=try store.results()
precondition(listed.count==1)
let persisted=listed[0]
// No filenames or receipt content: fixed field equality and numeric timestamp evidence only.
let checks:[String:Bool]=[
 "directoryURL":persisted.directory==result.directory,
 "directoryPath":persisted.directory.path==result.directory.path,
 "receipt":persisted.receipt==result.receipt,
 "id":persisted.receipt.id==result.receipt.id,
 "date":persisted.receipt.date==result.receipt.date,
 "inputName":persisted.receipt.inputName==result.receipt.inputName,
 "inputSHA":persisted.receipt.inputSHA256==result.receipt.inputSHA256,
 "models":persisted.receipt.modelSHA256==result.receipt.modelSHA256,
 "frames":persisted.frames==result.frames,"gain":persisted.gain==result.gain,
 "vocalsSHA":persisted.receipt.vocalsSHA256==result.receipt.vocalsSHA256,
 "backingSHA":persisted.receipt.accompanimentSHA256==result.receipt.accompanimentSHA256]
for key in checks.keys.sorted() {FileHandle.standardError.write(Data(("SEPARATION_STORE_EQUALITY "+key+"="+String(checks[key]!) + "\n").utf8))}
FileHandle.standardError.write(Data(("SEPARATION_STORE_DATE_DELTA="+String(persisted.receipt.date.timeIntervalSince(result.receipt.date))+"\n").utf8))
let original=try Data(contentsOf:result.vocals)
precondition(original.count==60)
do { _=try store.publish(vocals:[.nan,0],accompaniment:[0,0],inputName:"bad",inputSHA256:String(repeating:"a",count:64));fatalError("nonfinite accepted") } catch {}
do { _=try store.publish(vocals:[0,0],accompaniment:[0,0,0,0],inputName:"bad",inputSHA256:String(repeating:"a",count:64));fatalError("mismatched stems accepted") } catch {}
stage("initial reference snapshot")
let handoff=try store.referenceInput(for:result)
precondition(handoff.url != result.vocals && handoff.bytes==original.count)
try handoff.validateCopied(digest:try SeparationStore.digest(handoff.url,maximum:4_000_000),bytes:original.count)
do {try handoff.validateCopied(digest:String(repeating:"0",count:64),bytes:original.count);fatalError("changed bytes accepted")} catch {}
do {try handoff.validateCopied(digest:handoff.sha256,bytes:original.count+1);fatalError("changed size accepted")} catch {}
let copiedVocals=try Data(contentsOf:handoff.url)
precondition(copiedVocals==original)
stage("repeated snapshot reuse")
stage("owned directory parent alias and foreign-directory rejection")
let aliasParent=root.deletingLastPathComponent().appendingPathComponent("store-parent-alias")
try FileManager.default.createSymbolicLink(at:aliasParent,withDestinationURL:root)
let aliased=SeparationStore.Result(receipt:result.receipt,directory:aliasParent.appendingPathComponent(result.directory.lastPathComponent,isDirectory:true))
let noDirectoryHint=SeparationStore.Result(receipt:result.receipt,directory:URL(fileURLWithPath:result.directory.path,isDirectory:false))
let noHintInput=try store.referenceInput(for:noDirectoryHint)
precondition(noHintInput.url==handoff.url)
let aliasInput=try store.referenceInput(for:aliased)
precondition(aliasInput.url==handoff.url)
let leafLink=root.deletingLastPathComponent().appendingPathComponent(result.directory.lastPathComponent,isDirectory:true)
try FileManager.default.createSymbolicLink(at:leafLink,withDestinationURL:result.directory)
let linkedResult=SeparationStore.Result(receipt:result.receipt,directory:leafLink)
do {_=try store.referenceInput(for:linkedResult);fatalError("symlink directory leaf accepted")} catch {}
let foreignParent=root.deletingLastPathComponent().appendingPathComponent("foreign",isDirectory:true)
let foreignDirectory=foreignParent.appendingPathComponent(result.directory.lastPathComponent,isDirectory:true)
try FileManager.default.createDirectory(at:foreignDirectory,withIntermediateDirectories:true)
let foreignResult=SeparationStore.Result(receipt:result.receipt,directory:foreignDirectory)
do {_=try store.referenceInput(for:foreignResult);fatalError("foreign directory with same receipt accepted")} catch {}
let beforeRepeated=try FileManager.default.contentsOfDirectory(atPath:root.path).count
for _ in 0..<70 {
    let reused=try store.referenceInput(for:result)
    precondition(reused.url==handoff.url)
}
let afterRepeated=try FileManager.default.contentsOfDirectory(atPath:root.path).count
precondition(beforeRepeated==afterRepeated)
stage("reuse at full directory budget")
var budgetFiles:[URL]=[]
for i in afterRepeated..<64 {
    let file=root.appendingPathComponent("Budget-"+String(i))
    try Data([0]).write(to:file);budgetFiles.append(file)
}
let fullReuse=try store.referenceInput(for:result)
precondition(fullReuse.url==handoff.url)
for file in budgetFiles {try FileManager.default.removeItem(at:file)}
stage("actual downstream snapshot copy")
let consumed=root.appendingPathComponent("consumed.wav")
let consumedHash=try handoff.copyVerified(to:consumed)
precondition(consumedHash==handoff.sha256)
stage("reject same-size mutation and symlink")
var modifiedSnapshot=original;modifiedSnapshot[modifiedSnapshot.count-1] ^= 1
try modifiedSnapshot.write(to:handoff.url)
do {_=try store.referenceInput(for:result);fatalError("corrupt cache reused")} catch {}
do {_=try handoff.copyVerified(to:root.appendingPathComponent("rejected.wav"));fatalError("changed snapshot consumed")} catch {}
try FileManager.default.removeItem(at:handoff.url)
try FileManager.default.createSymbolicLink(at:handoff.url,withDestinationURL:result.vocals)
do {_=try handoff.copyVerified(to:root.appendingPathComponent("symlink-rejected.wav"));fatalError("linked snapshot accepted")} catch {}
try FileManager.default.removeItem(at:handoff.url)
try original.write(to:handoff.url)
do {_=try handoff.copyVerified(to:consumed);fatalError("overwrote existing destination")} catch {}
let consumedBytes=try Data(contentsOf:consumed)
precondition(consumedBytes==original)
stage("reject stale receipt")
let receiptURL=result.directory.appendingPathComponent("receipt.json")
let receiptBytes=try Data(contentsOf:receiptURL)
var changed=try JSONSerialization.jsonObject(with:receiptBytes) as! [String:Any]
changed["inputName"]="changed.wav"
try JSONSerialization.data(withJSONObject:changed).write(to:receiptURL)
do {_=try store.referenceInput(for:result);fatalError("stale receipt accepted")} catch {}
try receiptBytes.write(to:receiptURL)
try Data([0]).write(to:result.accompaniment)
do {_=try store.referenceInput(for:result);fatalError("corrupt pair accepted")} catch {}
let remaining=try store.results()
precondition(remaining.isEmpty)
let unchanged=try Data(contentsOf:result.vocals)
precondition(unchanged==original)
stage("publish scaled pair")
let scaled=try store.publish(vocals:[2,-2],accompaniment:[1,-1],inputName:"peak.wav",inputSHA256:String(repeating:"b",count:64))
precondition(scaled.gain==0.5)
precondition(scaled.vocals.lastPathComponent != result.vocals.lastPathComponent)
precondition(scaled.accompaniment.lastPathComponent != result.accompaniment.lastPathComponent)
precondition(Set([scaled.vocals,scaled.accompaniment,result.vocals,result.accompaniment].map{$0.lastPathComponent}).count==4)
let a=try Data(contentsOf:scaled.vocals),b=try Data(contentsOf:scaled.accompaniment)
func sample(_ d:Data)->Float {Float(bitPattern:d.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:44,as:UInt32.self)}.littleEndian)}
precondition(sample(a)==1 && sample(b)==0.5)
stage("regular input copy")
let source=root.appendingPathComponent("source.wav")
try original.write(to:source)
let sourceBefore=try SeparationStore.digest(source,maximum:1024)
let copied=try store.copyInput(source)
precondition(copied.sha==sourceBefore)
let sourceAfter=try SeparationStore.digest(source,maximum:1024)
precondition(sourceBefore==sourceAfter)
stage("retained interrupted staging")
let staging=root.appendingPathComponent(".staging-interrupted",isDirectory:true)
try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false)
let afterStaging=try store.results()
precondition(afterStaging.count==1)
let link=root.appendingPathComponent("linked.wav")
try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
do {_=try store.copyInput(link);fatalError("symlink source accepted")}catch{}
stage("cancel publication")
let gate=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
let cancellation=Task.detached {() -> Bool in
    gate.wait()
    do {_=try store.publish(vocals:samples,accompaniment:samples,inputName:"cancelled",inputSHA256:String(repeating:"c",count:64));return false}
    catch is CancellationError {return true}
    catch {return false}
}
cancellation.cancel();gate.signal()
Task.detached {let stopped=await cancellation.value;precondition(stopped);done.signal()}
done.wait()
let afterCancel=try store.results();precondition(afterCancel.count==1)
stage("cancel downstream copy")
let copyGate=DispatchSemaphore(value:0),copyDone=DispatchSemaphore(value:0)
let cancelledCopy=Task.detached {() -> Bool in
    copyGate.wait()
    do {_=try handoff.copyVerified(to:root.appendingPathComponent("cancelled-copy.wav"));return false}
    catch is CancellationError {return true}
    catch {return false}
}
cancelledCopy.cancel();copyGate.signal()
Task.detached {let stopped=await cancelledCopy.value;precondition(stopped);copyDone.signal()}
copyDone.wait()
let finalOriginal=try Data(contentsOf:result.vocals)
precondition(finalOriginal==original)
print("Separation store validation passed, including receipt-bound reusable reference handoff")

}
do { try runProbe() }
catch {
    FileHandle.standardError.write(Data(("FAIL separation store probe stage="+currentStage+" error="+String(describing:error)+"\n").utf8))
    exit(1)
}
