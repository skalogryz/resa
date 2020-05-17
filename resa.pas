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
    function SwapLoads: Boolean;
    procedure ClearLoad(i: integer);
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
    wantFailToLoad,
    warnAbnormalLoad  // function returned true, but no object was provided
  );

  { TResourceManager }

  TResourceManager = class(TObject)
  private
    resList : THashedStringListEx;
    function GetResource(const refName: string; forced: Boolean): TResourceObject;

    function FindLoader(p: TResourceProvider; const refName: string; out st: TStream;
       out ld: TResourceLoader): TLoadResult;

    function PerformLoad(p: TResourceProvider; res: TResourceObject; isReload: Boolean): TLoadResult;

    procedure Log(const logMsg: TResouceManagerLog; const refName: string; param1: Int64 = 0; param2: Int64 = 0);
    procedure UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader; isReloadObj: Boolean);
  public
    LogProc   : procedure (Sender: TResourceManager;
                  const logMsg: TResouceManagerLog;
                  const refName: string;
                  param1: Int64 = 0; param2: Int64 = 0) of object;
    lock      : TRTLCriticalSection;
    maxMem    : QWord;
    maxThread : LongWord;
    constructor Create;
    destructor Destroy; override;
    function RegisterResource(const refName: string): TResourceObject;
    function ResourceExists(const refName: string): TResourceObject;

    function LoadResourceSync(res: TResourceObject; Reload: Boolean): TLoadResult;
    function UnloadResourceSync(res: TResourceObject; isReloadObj: Boolean): Boolean;
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

function CheckNeedsLoad(flags: TResourceFlags): Boolean;
begin
  Result := (flags *[rfLoading, rfLoaded, rfReloading, rfReloaded]) = [];
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
const
  ReloadIdx : array [boolean] of integer = (IDX_LOAD, IDX_RELOAD);
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
          res.AddFlags(loadedFlag);
        finally
          res.Unlock;
        end;
        Log(noteLoadSuccess, res.RefName, idx);
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

procedure TResourceManager.UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader; isReloadObj: Boolean);
var
  paramUnload : array [Boolean] of Int64 = (IDX_LOAD, IDX_RELOAD);
begin
  if ASsigned(loadedWith) and Assigned(obj) then begin
    Log(noteUnloadingResObj, refName, paramUnload[isReloadObj]);
    loadedWith.UnloadResource(refName, obj);
    Log(noteUnloadedResObj, refName, paramUnload[isReloadObj]);
  end;
end;

constructor TResourceManager.Create;
begin
  inherited Create;
  InitCriticalSection(lock);
  resList:=THashedStringListEx.Create;
  maxMem:=High(Int64);
  maxThread:=4;
end;

destructor TResourceManager.Destroy;
var
  i : integer;
begin
  for i:=0 to resList.Count-1 do
    TObject(resList.Objects[i]).Free;
  resList.Free;
  DoneCriticalsection(lock);
  inherited Destroy;
end;

function TResourceManager.RegisterResource(const refName: string): TResourceObject;
begin
  EnterCriticalsection(lock);
  try
    Result := GetResource(refName, true);
  finally
    LeaveCriticalsection(lock);
  end;
end;

function TResourceManager.ResourceExists(const refName: string): TResourceObject;
begin
  EnterCriticalsection(lock);
  try
    Result := GetResource(refName, true);
  finally
    LeaveCriticalsection(lock);
  end;
end;


function TResourceManager.LoadResourceSync(res: TResourceObject; Reload: Boolean): TLoadResult;
var
  p : TResourceProvider;
  isReload: Boolean;
begin
  res.Lock;
  try
    if Reload then begin
      if res.Flags * [rfLoaded, rfLoading] = [] then
        Reload := false; // the file has not been loaded yet
    end;

    if not Reload and (res.Flags * [rfLoaded, rfLoading] <> []) then begin
      Result:=lrAlreadyLoaded;
      Exit;
    end else if Reload and (res.Flags * [rfReloading] <> []) then begin
      // it's ok to reload already loaded object
      Result:=lrAlreadyLoaded; // don't interrupt reloading
      Exit;
    end;
  finally
    res.Unlock;
  end;

  FindProvider(res.RefName, p);
  if p = nil then begin
    Result:=lrErrNoPhysResource;
    Exit;
  end;

  Result := PerformLoad(p, res, Reload);
end;

function TResourceManager.UnloadResourceSync(res: TResourceObject; isReloadObj: Boolean): Boolean;
var
  idx : integer;
  cnFlag : TResourceFlags;
  clrFlag : TResourceFlags;
begin
  if not Assigned(res) then begin
    Result:=false;
    Exit;
  end;

  res.Lock;
  try
    if isReloadObj then begin
      idx := IDX_RELOAD;
      cnFlag := [rfReloadingCancel];
      clrFlag := [rfReloaded];
    end else begin
      idx := IDX_LOAD;
      cnFlag := [rfLoadingCancel];
      clrFlag := [rfLoaded];
    end;

    if not Assigned(res.resObj[idx].obj) then begin
      res.Flags := res.Flags + cnFlag;
      Result := true;
    end else if Assigned(res.ResObj[idx].obj) and Assigned(res.ResObj[idx].loader) then begin
      UnloadResObj(res.RefName, res.ResObj[idx].obj, res.ResObj[idx].loader, isReloadObj);
      res.ClearLoad(idx);
      res.Flags := res.Flags - clrFlag;
      Result := true;
    end else
      Result := false;
  finally
    res.Unlock;
  end;

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
    manager.UnloadResObj(refName, inf.obj, inf.loader, isReloadObj);
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

