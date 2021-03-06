unit resa;

{$ifdef fpc}{$mode delphi}{$H+}{$endif}

interface

uses
  Classes, SysUtils, HashClasses;

type
  TResourceFlags = set of (
    rfLoading,    // loading in progress
    rfLoadingCancel, // loading is in progress, but should be discarded on completion (due to Unloadcalls)
    rfLoaded,     // loaded
    rfReloading,  // is reloading
    rfReloadingCancel, // reloading is in progress, but should be discarded on completion (due to Unloadcalls)
    rfReloaded,   // reloaded version is ready
    rfFixed       // cannot be unloaded
  );

  TResourceHandler = class;
  TResourceLoader = class;
  TResourceManager = class;

  TResObjectInfo = record
    obj    : TObject;
    loader : TResourceLoader;
    size   : Int64;
  end;

  { TResourceObject }

  TResourceObject = class(TObject)
  // object of the no interface
  private
    RefCount : Integer;
    Handlers : TList;
    flock    : TRTLCriticalSection;
    fRefName : string;
    fManager : TResourceManager;
    procedure UnloadAll;
    procedure UnloadInfo(var inf: TResObjectInfo; isReloadObj: Boolean);

    function SwapLoads: Boolean;
    procedure ClearLoad(i: integer);
  public
    Flags      : TResourceFlags;
    resObj     : array [0..1] of TResObjectInfo;
    Tags       : TList; // the list of owner TObjects

    constructor Create(const ARefName: string; AManager: TResourceManager);
    destructor Destroy; override;
    function AllocHandle: TResourceHandler;
    procedure ReleaseHandle(var AHnd: TResourceHandler);
    procedure Lock;
    procedure Unlock;
    function GetFlags: TResourceFlags;
    procedure AddFlags(fl: TResourceFlags);
    procedure RemoveFlags(fl: TResourceFlags);
    property RefName: string read fRefName; // readonly. no need to lock
    property Manager: TResourceManager read fManager;
  end;

  { TResourceHandler }

  TResourceHandler = class(TObject)
  private
    fOwner : TResourceObject;
  public
    // call the constructor only while TResourceObject is locked
    constructor Create(AOwner: TResourceObject);
    destructor Destroy; override;
    procedure FreeInstance; override;
    property Owner: TResourceObject read fOwner;

    procedure OwnerLock;
    procedure OwnerUnlock;
  end;

  TResourceProvider = class;

  TLoadResult = (
    lrSuccess,
    lrLoaded,
    lrAlreadyLoaded,
    lrLoadScheduled,
    lrLoadCancelled,
    lrErrNoPhysResource,
    lrErrNoStream,
    lrErrUnkResource,
    lrErrFailToLoad
  );

  TResouceManagerLog = (
    noteStartLoading,
    noteStartReloading,
    noteLoadSuccess,
    noteUnloadingResObj,
    noteUnloadedResObj,
    noteLoadCancel,
    noteSwapped,
    noteMemCleanup,
    noteMemResourceCleanup,
    wantFailToLoad,
    warnAbnormalLoad  // function returned true, but no object was provided
  );

  TSwapResult = (
    srSuccess,
    srInvResource,
    srNotLoaded,
    srNotReloaded
  );

  { TQueueTask }

  TQueueTask = class(TObject)
    res    : TResourceObject;
    isLoad : Boolean;
    idx    : Integer;
    constructor Create(res: TResourceObject; isLoad : Boolean; idx: Integer);
  end;

  { TQueueOfTasks }

  TQueueOfTasks = class(TObject)
  private
    fItems : TList;
    flock  : TRTLCriticalSection;
    procedure Lock;
    procedure Unlock;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(res: TResourceObject; toLoad: boolean; idx: integer);
    procedure AddPriotity(res: TResourceObject; toLoad: boolean; idx: integer);
    function Pop(out res: TResourceObject; out toLoad: boolean; out idx: integer): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

  { TResourceManThread }

  TResourceManThread = class(TThread)
  protected
    manager    : TResourceManager;
    ShouldStop : Boolean;
    inProc     : Boolean;
    inLoop     : Boolean;
    procedure Execute; override;
  end;

  { TResourceManager }

  TResourceManager = class(TObject)
  private
    resList     : THashedStringListEx;
    flock       : TRTLCriticalSection;
    memVerified : Boolean;
    queue       : TQueueOfTasks;
    threads     : array of TResourceManThread;
    function GetResource(const refName: string; forced: Boolean): TResourceObject;

    function FindLoader(p: TResourceProvider; const refName: string; out st: TStream;
       out ld: TResourceLoader): TLoadResult;

    procedure RunMemTest(loadedRes: TResourceObject; newSize: int64);
    function PerformLoad(p: TResourceProvider; res: TResourceObject; isReload: Boolean): TLoadResult;

    procedure Log(const logMsg: TResouceManagerLog; const refName: string; param1: Int64 = 0; param2: Int64 = 0);
    procedure UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader; Sz: int64; isReloadObj: Boolean);

    procedure AddMem(const Amount: Int64);
    procedure VerifyMem(skipRes: TResourceObject; unloadSync: Boolean);

    procedure WakeAsync;
    procedure AsyncProc(out AnyJobDone: boolean);
    procedure AwaitThreads;
  public
    LogProc   : procedure (Sender: TResourceManager;
                  const logMsg: TResouceManagerLog;
                  const refName: string;
                  param1: Int64 = 0; param2: Int64 = 0) of object;
    maxMem    : QWord;
    memUse    : QWord;
    maxThread : LongWord;
    constructor Create;
    destructor Destroy; override;
    function RegisterResource(const refName: string): TResourceObject;
    function ResourceExists(const refName: string): TResourceObject;

    function LoadRes(res: TResourceObject; isReloadObj: Boolean; Sync: Boolean): TLoadResult;
    function UnloadRes(res: TResourceObject; isReloadObj: Boolean; Sync: Boolean): Boolean;

    function SwapResObj(res: TResourceObject): TSwapResult;

    procedure Lock;
    procedure Unlock;
  end;

  TResourceProvider = class(TObject)
    function Exists(const refName: string): Boolean; virtual; abstract;
    function AllocStream(const refName: string): TStream; virtual; abstract;
    procedure StreamDone(str: TStream); virtual; abstract;
  end;

  { TResourceLoader }

  TResourceLoader = class(TObject)
  public
    function CanLoad(const refName: string; stream: TStream): Boolean;
      virtual; abstract;
    function EstimateMem(const refName: string; stream: TStream; var ExpectedMem: QWord): Boolean;
      virtual;
    function LoadResource(
      const refName: string; stream: TStream;
      out Size: QWord; out resObject: TObject
    ): Boolean; virtual; abstract;
    function UnloadResource(const refName: string; var resObject: TObject): Boolean;
      virtual; abstract;
  end;

function CheckNeedsLoad(flags: TResourceFlags): Boolean;

type
  // conventional external (non-pascal) resource
  TExternalResource = class(TObject)
    resRef    : Pointer;
    resRefNum : Integer;
  end;

const
  IDX_LOAD   = 0;
  IDX_RELOAD = 1;

implementation

uses
  resa_providers, resa_loaders;

const
  ReloadIdx : array [boolean] of integer = (IDX_LOAD, IDX_RELOAD);

function CheckNeedsLoad(flags: TResourceFlags): Boolean;
begin
  Result := (flags *[rfLoading, rfLoaded, rfReloading, rfReloaded]) = [];
end;

{ TResourceManThread }

procedure TResourceManThread.Execute;
var
  anyDone: boolean;
begin
  inLoop := true;
  try
    while (true) do begin
      inProc:=true;
      manager.AsyncProc(anyDone);
      inProc:=false;
      if not anyDone then Break;
      if ShouldStop then Break;
    end;
  except
  end;
  inLoop := false;
end;

{ TQueueTask }

constructor TQueueTask.Create(res: TResourceObject; isLoad: Boolean;
  idx: Integer);
begin
  Self.res := res;
  Self.isLoad := isLoad;
  self.idx := idx;
end;

{ TQueueOfTasks }

procedure TQueueOfTasks.Lock;
begin
  EnterCriticalsection(flock);
end;

procedure TQueueOfTasks.Unlock;
begin
  LeaveCriticalsection(flock);
end;

constructor TQueueOfTasks.Create;
begin
  inherited Create;
  fItems := TList.Create;
  InitCriticalSection(flock);
end;

destructor TQueueOfTasks.Destroy;
begin
  Clear;
  fItems.Free;
  DoneCriticalsection(flock);
  inherited Destroy;
end;

procedure TQueueOfTasks.Add(res: TResourceObject; toLoad: boolean; idx: integer);
begin
  Lock;
  try
    fItems.add(TQueueTask.Create(res, toLoad, idx));
  finally
    Unlock;
  end;
end;

procedure TQueueOfTasks.AddPriotity(res: TResourceObject; toLoad: boolean;
  idx: integer);
begin
  Lock;
  try
    if fitems.Count=0 then
      fItems.Add(TQueueTask.Create(res, toLoad, idx))
    else
      fItems.Insert(0, TQueueTask.Create(res, toLoad, idx));
  finally
    Unlock;
  end;
end;

function TQueueOfTasks.Pop(out res: TResourceObject; out toLoad: boolean; out idx: integer): Boolean;
var
  t : TQueueTask;
begin
  Lock;
  try
    res := nil;
    toLoad :=false;
    idx := 0;
    Result:=fItems.Count>0;
    if not Result then Exit;

    t := TQueueTask(fItems[0]);
    res := t.res;
    idx := t.idx;
    toLoad := t.isLoad;
    t.Free;

    fItems.Delete(0);
  finally
    Unlock;
  end;
end;

function TQueueOfTasks.Count: Integer;
begin
  Lock;
  try
    Result:=fItems.Count;
  finally
    Unlock;
  end;
end;

procedure TQueueOfTasks.Clear;
var
  i : integer;
begin
  Lock;
  try
    for i:=0 to fItems.Count-1 do
      TObject(fItems[i]).free;
    fItems.Clear;
  finally
    Unlock;
  end;
end;

{ TResourceLoader }

function TResourceLoader.EstimateMem(const refName: string; stream: TStream;
  var ExpectedMem: QWord): Boolean;
begin
  Result:=false;
end;

{ TResourceLoader }

{ TResourceHandler }

constructor TResourceHandler.Create(AOwner: TResourceObject);
begin
  inherited Create;
  fOwner:=AOwner;
end;

destructor TResourceHandler.Destroy;
begin
  if Assigned(fOwner) then
    fOwner.ReleaseHandle(Self)
  else
    inherited Destroy;
end;

procedure TResourceHandler.FreeInstance;
begin
  inherited FreeInstance;
end;

procedure TResourceHandler.OwnerLock;
begin
  owner.Lock;
end;

procedure TResourceHandler.OwnerUnlock;
begin
  Owner.Unlock;
end;

{ TResourceManager }

function TResourceManager.GetResource(const refName: string; forced: Boolean): TResourceObject;
var
  i : integer;
begin
  i:=resList.IndexOf(refName);
  if (i>=0) then begin
    Result:=TResourceObject(resList.Objects[i]);
    Exit;
  end;
  if forced then begin
    Result:=TResourceObject.Create(refName, Self);
    resList.AddObject(refName, Result);
  end else
    Result:=nil;
end;

function TResourceManager.FindLoader(p: TResourceProvider;
  const refName: string; out st: TStream; out ld: TResourceLoader): TLoadResult;
var
  i : integer;
  rld : TResourceLoader;
begin
  ld := nil;
  st := p.AllocStream(refName);
  if not Assigned(st) then begin
    Result := lrErrNoStream;
    Exit;
  end;

  for i:=0 to loaders.Count-1 do begin
    rld := TResourceLoader(loaders[i]);

    st.Position:=0;
    if rld.CanLoad(refName, st) then begin
      ld:=rld;
      break;
    end;
  end;
  if not Assigned(ld) then begin
    Result := lrErrUnkResource;
    Exit;
  end;
  Result := lrSuccess;
end;

procedure TResourceManager.RunMemTest(loadedRes: TResourceObject; newSize: int64);
begin
  inc(memUse, newSize);
end;

function TResourceManager.PerformLoad(p: TResourceProvider;
  res: TResourceObject; isReload: Boolean): TLoadResult;
var
  st : TStream;
  ld : TResourceLoader;
  sz : QWord;
  obj : TObject;
  idx : Integer;

  loadingFlag : TResourceFlags;
  loadedFlag  : TResourceFlags;
  cancelFlag  : TResourceFlags;
  loadLog     : TResouceManagerLog;
begin
  Result := FindLoader(p, res.RefName, st, ld);
  if Result<>lrSuccess then Exit;
  try
    if isReload then begin
      loadedFlag := [rfReloaded];
      loadingFlag := [rfReloading];
      loadLog := noteStartReloading;
      cancelFlag := [rfReloadingCancel];
    end else begin
      loadedFlag := [rfLoaded];
      loadingFlag := [rfLoading];
      loadLog := noteStartLoading;
      cancelFlag := [rfLoadingCancel];
    end;
    idx := ReloadIdx[isReload];

    res.AddFlags(loadingFlag);
    try
      Log(loadLog, res.RefName, idx);

      if not ld.LoadResource(res.RefName, st, sz, obj) then begin
        Log(wantFailToLoad, res.RefName, idx);
        Result:=lrErrFailToLoad;
        Exit;
      end;
      if not Assigned(obj) then begin
        Log(warnAbnormalLoad, res.RefName, idx);
        Result:=lrErrFailToLoad;
        Exit;
      end;

      if res.GetFlags * cancelFlag <> [] then begin
        ld.UnloadResource(res.refName, obj);
        Log(noteLoadCancel, res.RefName, idx);
        Result := lrLoadCancelled;
      end else begin
        res.Lock;
        try
          idx := ReloadIdx[isReload];
          res.resObj[idx].obj := obj;
          res.resObj[idx].loader := ld;
          res.resObj[idx].size := sz;
          res.AddFlags(loadedFlag);
        finally
          res.Unlock;
        end;
        Log(noteLoadSuccess, res.RefName, idx);
        AddMem(sz);
        Result := lrLoaded;
      end;
    finally
      res.RemoveFlags(loadingFlag);
    end;
  finally
    p.StreamDone(st);
    st.Free;
  end;
end;

procedure TResourceManager.Log(const logMsg: TResouceManagerLog;
  const refName: string; param1: Int64 = 0; param2: Int64 = 0);
begin
  try
    if Assigned(LogProc) then
      LogProc(Self, logMsg, refName, param1, param2);
  except
  end;
end;

procedure TResourceManager.UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader; Sz: int64; isReloadObj: Boolean);
var
  paramUnload : array [Boolean] of Int64 = (IDX_LOAD, IDX_RELOAD);
begin
  if ASsigned(loadedWith) and Assigned(obj) then begin
    Log(noteUnloadingResObj, refName, paramUnload[isReloadObj]);
    loadedWith.UnloadResource(refName, obj);
    AddMem(Sz);
    Log(noteUnloadedResObj, refName, paramUnload[isReloadObj]);
  end;
end;

procedure TResourceManager.AddMem(const Amount: Int64);
begin
  Lock;
  try
    memUse := memUse + Amount;
    memVerified := false;
  finally
    Unlock;
  end;
end;

procedure TResourceManager.VerifyMem(skipRes: TResourceObject; unloadSync: Boolean);
var
  doVerify  : Boolean;
  victim    : TList;
  cleanMem  : QWord;
  victimMem : QWord;
  obj       : TObject;
  ro        : TResourceObject;
  i         : Integer;
begin
  cleanMem :=0;
  lock;
  try
    doVerify := not memVerified and (maxMem >0);
    if doVerify and (memUse > maxMem) then
      cleanMem := memUse - maxMem;

    if (not doVerify) or (cleanMem = 0) then
      memVerified := true;
    if (cleanMem = 0) or not (doVerify) then Exit;

    log(noteMemCleanup, '', memUse, maxMem);
    victim := TList.Create;
    victimMem := 0;
    for i:=0 to resList.Count-1 do begin
      obj := resList.Objects[i];
      if not Assigned(obj) then Continue;
      if not (obj is TResourceObject) then Continue;

      ro := TResourceObject(obj);
      if rfFixed in ro.Flags then Continue; // skipping
      if ro = skipRes then Continue;

      ro.Lock;
      try
        if Assigned(ro.resObj[0].obj) or Assigned(ro.resObj[1].obj) then begin
          if Assigned(ro.resObj[0].obj) then inc(victimMem, ro.resObj[0].size);
          if Assigned(ro.resObj[1].obj) then inc(victimMem, ro.resObj[1].size);
          Log(noteMemResourceCleanup, ro.RefName);
          victim.Add(obj);
        end;
      finally
        ro.Unlock;
      end;
      if victimMem > cleanMem then break; // found enough blood!
    end;

    for i:=0 to victim.Count-1 do begin
      ro := TResourceObject(victim[i]);
      ro.Lock;
      try
        if unloadSync then
          ro.UnloadAll
        else begin
          if Assigned(ro.resObj[0].obj) then
            queue.AddPriotity(ro, false, 0);
          if Assigned(ro.resObj[1].obj) then
            queue.AddPriotity(ro, false, 1);
        end;
      finally
        ro.Unlock;
      end;
    end;

    if (not unloadSync) and (victim.Count>0) then
      WakeAsync;

    victim.Free;
    memVerified := true;

  finally
    unlock;
  end;
end;

procedure TResourceManager.WakeAsync;
var
  i      : integer;
  tr     : TResourceManThread;
  needed : Integer;
begin
  if (length(threads)=0) then
    SetLength(threads, maxThread);

  needed := queue.Count;
  for i:=0 to length(threads)-1 do begin
    tr := threads[i];
    if Assigned(tr) then begin
      if tr.inProc then Continue;
      if not tr.inLoop then begin
        tr.WaitFor; // risky?
        tr.Free;
        tr:=nil;
        threads[i]:=nil;
      end;
    end;

    if not Assigned(tr) then begin
      tr:=TResourceManThread.Create(true);
      tr.manager:=Self;
      threads[i]:=tr;
      tr.Start;
      dec(needed);
    end;
    if (needed = 0) then
      break; // should have enough threads by now
  end;
end;

procedure TResourceManager.AsyncProc(out AnyJobDone: boolean);
var
  res    : TResourceObject;
  toLoad : boolean;
  idx    : integer;
begin
  AnyJobDone:=queue.Pop(res, toLoad, idx);
  if not AnyJobDone then Exit;

  if toLoad then
    LoadRes(res, idx>0, true)
  else
    UnloadRes(res, idx>0, true);
end;

procedure TResourceManager.AwaitThreads;
var
  i : integer;
begin
  lock;
  try
    for i:=0 to length(threads)-1 do begin
      if not Assigned(threads[i]) then Continue;
      if threads[i].inLoop then
        threads[i].ShouldStop := true;

      threads[i].WaitFor;
      threads[i].Free;
      threads[i]:=nil;
    end;
  finally
    unlock;
  end;
end;

constructor TResourceManager.Create;
begin
  inherited Create;
  InitCriticalSection(flock);
  resList:=THashedStringListEx.Create;
  maxMem:=0; // limitless
  maxThread:=4;
  memVerified:=true;
  queue:=TQueueOfTasks.Create;
end;

destructor TResourceManager.Destroy;
var
  i : integer;
begin
  AwaitThreads;

  for i:=0 to resList.Count-1 do
    TObject(resList.Objects[i]).Free;
  resList.Free;
  DoneCriticalsection(flock);
  queue.Free;
  inherited Destroy;
end;

function TResourceManager.RegisterResource(const refName: string): TResourceObject;
begin
  Lock;
  try
    Result := GetResource(refName, true);
  finally
    Unlock;
  end;
end;

function TResourceManager.ResourceExists(const refName: string): TResourceObject;
begin
  Lock;
  try
    Result := GetResource(refName, true);
  finally
    Unlock;
  end;
end;

function TResourceManager.LoadRes(res: TResourceObject; isReloadObj: Boolean;
  Sync: Boolean): TLoadResult;
var
  p : TResourceProvider;
begin
  res.Lock;
  try
    if isReloadObj then begin
      if res.Flags * [rfLoaded, rfLoading] = [] then
        isReloadObj := false; // the file has not been loaded yet
    end;

    if not isReloadObj and (res.Flags * [rfLoaded, rfLoading] <> []) then begin
      Result:=lrAlreadyLoaded;
      Exit;
    end else if isReloadObj and (res.Flags * [rfReloading] <> []) then begin
      // it's ok to reload already loaded object
      Result:=lrAlreadyLoaded; // don't interrupt reloading
      Exit;
    end;
  finally
    res.Unlock;
  end;

  if Sync then begin
    FindProvider(res.RefName, p);
    if p = nil then begin
      Result:=lrErrNoPhysResource;
      Exit;
    end;

    Result := PerformLoad(p, res, isReloadObj);
    VerifyMem(res, true);
  end else begin
    queue.Add(res, true, ReloadIdx[isReloadObj]);
    WakeAsync;
  end;
end;


function TResourceManager.UnloadRes(res: TResourceObject; isReloadObj: Boolean;
  Sync: Boolean): Boolean;
var
  idx : integer;
  cnFlag : TResourceFlags;
  clrFlag : TResourceFlags;
  progFlag : TResourceFlags;
  flag : TResourceFlags;
begin
  if not Assigned(res) then begin
    Result:=false;
    Exit;
  end;

  res.Lock;
  try
    flag := res.Flags;
    idx := ReloadIdx[isReloadObj];
    if isReloadObj then begin
      cnFlag := [rfReloadingCancel];
      clrFlag := [rfReloaded];
      progFlag := [rfReloading];
    end else begin
      idx := IDX_LOAD;
      cnFlag := [rfLoadingCancel];
      clrFlag := [rfLoaded];
      progFlag := [rfReloading];
    end;


    // the resource is being loaded. Marking it as to be cancelled!
    if (flag * progFlag <> []) then begin
      res.Flags := res.Flags + cnFlag;
      Result := true;
    end;

    // it's already unloaded nothing to worry about
    if (flag * clrFlag = []) then begin
      Result := true;
      Exit;
    end;

    if Sync then begin
      if Assigned(res.ResObj[idx].obj) and Assigned(res.ResObj[idx].loader) then begin
        UnloadResObj(res.RefName, res.ResObj[idx].obj, res.ResObj[idx].loader, res.ResObj[idx].size, isReloadObj);
        res.ClearLoad(idx);
        res.Flags := res.Flags - clrFlag;
      end;
      Result := true;
    end else begin
      queue.Add(res, false, idx);
      WakeAsync;
    end;

  finally
    res.Unlock;
  end;

end;

function TResourceManager.SwapResObj(res: TResourceObject): TSwapResult;
begin
  if not Assigned(res) then begin
    Result:=srInvResource;
    Exit;
  end;
  if not (rfLoaded in res.Flags) then begin
    Result:=srNotLoaded;
    Exit;
  end;
  if (rfReloading in res.Flags) or not (rfReloaded in res.Flags) then begin
    Result:=srNotReloaded;
    Exit;
  end;
  res.SwapLoads;
  Log(noteSwapped, res.refName);
end;

procedure TResourceManager.Lock;
begin
  EnterCriticalsection(flock);
end;

procedure TResourceManager.Unlock;
begin
  LeaveCriticalsection(flock);
end;

{ TResourceObject }

function TResourceObject.GetFlags: TResourceFlags;
begin
  Lock;
  try
    Result:=Flags;
  finally
    Unlock;
  end;
end;

procedure TResourceObject.AddFlags(fl: TResourceFlags);
begin
  Lock;
  try
    Flags:=Flags+fl;
  finally
    Unlock;
  end;
end;

procedure TResourceObject.RemoveFlags(fl: TResourceFlags);
begin
  lock;
  try
    Flags:=Flags-fl;
  finally
    Unlock;
  end;
end;

function TResourceObject.SwapLoads: Boolean;
var
  info : TResObjectInfo;
begin
  Result:=false;
  Lock;
  try
    if not Assigned(resObj[0].obj) or not Assigned(resObj[1].obj) then Exit;
    info := resObj[0];
    resObj[0] := resObj[1];
    resObj[1] := info;
    Result := true;
  finally
    Unlock;
  end;
end;

procedure TResourceObject.ClearLoad(i: integer);
begin
  if (i<0) or (i>=length(resObj)) then Exit;
  resObj[i].obj:=nil;
  resObj[i].loader:=nil;
end;

procedure TResourceObject.UnloadAll;
begin
  UnloadInfo(resObj[0], false);
  UnloadInfo(resObj[1], true);
end;

procedure TResourceObject.UnloadInfo(var inf: TResObjectInfo; isReloadObj: Boolean);
begin
  if Assigned(inf.obj) and Assigned(inf.loader) then begin
    manager.UnloadResObj(refName, inf.obj, inf.loader, inf.size, isReloadObj);
    inf.obj := nil;
    inf.loader := nil;
  end;
end;

constructor TResourceObject.Create(const ARefName: string; AManager: TResourceManager);
begin
  inherited Create;
  Tags:=TList.Create;
  InitCriticalSection(flock);
  Handlers := TList.Create;
  fRefName := ARefName;
  fManager := AManager;
end;

destructor TResourceObject.Destroy;
var
  i : integer;
begin
  for i:=0 to Tags.Count-1 do
    TObject(Tags[i]).Free;
  for i:=0 to Handlers.count-1 do begin
    TResourceHandler(Handlers[i]).fOwner:=nil;
    TObject(Handlers[i]).Free;
  end;
  Tags.Free;
  DoneCriticalsection(flock);
  Handlers.free;
  UnloadAll;
  inherited Destroy;
end;

function TResourceObject.AllocHandle: TResourceHandler;
begin
  Lock;
  try
    Result:=TResourceHandler.Create(Self);
    inc(RefCount);
    Handlers.Add(Result);
  finally
    Unlock;
  end;
end;

procedure TResourceObject.ReleaseHandle(var AHnd: TResourceHandler);
begin
  if not Assigned(AHnd) then Exit;
  Lock;
  try
    if AHnd.fOwner<>self then Exit;
    Handlers.Remove(AHnd);
    dec(RefCount);
    AHnd.fOwner:=nil; // must nil-out the owner first!
    AHnd.Free;
  finally
    Unlock;
  end;
end;

procedure TResourceObject.Lock;
begin
  EnterCriticalsection(flock);
end;

procedure TResourceObject.Unlock;
begin
  LeaveCriticalsection(flock);
end;

end.

