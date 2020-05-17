unit resa;

{$ifdef fpc}{$mode delphi}{$H+}{$endif}

interface

uses
  Classes, SysUtils, HashClasses;

type
  TResourceFlags = set of (
    rfLoading,    // loading in progress
    rfLoaded,     // loaded
    rfReloading,  // is reloading
    rfReloaded,   // reloaded version is ready
    rfFixed       // cannot be unloaded
  );

  TResourceHandler = class;
  TResourceLoader = class;
  TResourceManager = class;

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
  public
    Flags      : TResourceFlags;
    loadedWith : TResourceLoader;
    loadObj    : TObject;
    reloadedWith : TResourceLoader;
    reloadObj  : TObject;

    constructor Create(const ARefName: string; AManager: TResourceManager);
    destructor Destroy; override;
    function AllocHandle: TResourceHandler;
    procedure ReleaseHandle(var AHnd: TResourceHandler);
    procedure Lock;
    procedure Unlock;
    function GetFlags: TResourceFlags;
    procedure AddFlags(fl: TResourceFlags);
    procedure RemoveFlags(fl: TResourceFlags);
    function SwapLoads(unloadLoaded: Boolean): Boolean;
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
    lrErrNoPhysResource,
    lrErrNoStream,
    lrErrUnkResource,
    lrErrFailToLoad
  );

  TResouceManagerLog = (
    noteStartLoading,
    noteStartReloading,
    noteLoadSuccess,
    noteUnloadedResObj,
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
    procedure UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader);
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

    function LoadResourceSync(hnd: TResourceHandler): TLoadResult;
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

function CheckNeedsLoad(hnd : TResourceHandler): Boolean;

implementation

uses
  resa_providers, resa_loaders;

function CheckNeedsLoad(hnd : TResourceHandler): Boolean;
begin
  Result := (hnd.Owner.GetFlags *[rfLoading, rfLoaded, rfReloading, rfReloaded]) = [];
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

  loadingFlag : TResourceFlags;
  loadedFlag  : TResourceFlags;
  loadLog     : TResouceManagerLog;
begin
  Result := FindLoader(p, res.RefName, st, ld);
  if Result<>lrSuccess then Exit;
  try
    if isReload then begin
      loadedFlag := [rfReloaded];
      loadingFlag := [rfReloading];
      loadLog := noteStartReloading;
    end else begin
      loadedFlag := [rfLoaded];
      loadingFlag := [rfLoading];
      loadLog := noteStartLoading;
    end;

    res.AddFlags(loadingFlag);
    try
      Log(loadLog, res.RefName);

      if not ld.LoadResource(res.RefName, st, sz, obj) then begin
        Log(wantFailToLoad, res.RefName);
        Result:=lrErrFailToLoad;
        Exit;
      end;
      if not Assigned(obj) then begin
        Log(warnAbnormalLoad, res.RefName);
        Result:=lrErrFailToLoad;
        Exit;
      end;

      res.Lock;
      try
        if isReload then begin
          res.reloadedWith := ld;
          res.reloadObj := obj;
        end else begin
          res.loadedWith := ld;
          res.loadObj := obj;
        end;
        res.AddFlags(loadedFlag);
      finally
        res.Unlock;
      end;
      Log(noteLoadSuccess, res.RefName);
      Result := lrLoaded;
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

procedure TResourceManager.UnloadResObj(const refName: string; obj: TObject; loadedWith: TResourceLoader);
begin
  if ASsigned(loadedWith) and Assigned(obj) then begin
    loadedWith.UnloadResource(refName, obj);
    Log(noteUnloadedResObj, refName);
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


function TResourceManager.LoadResourceSync(hnd: TResourceHandler): TLoadResult;
var
  p : TResourceProvider;
begin
  hnd.OwnerLock;
  try
    if not CheckNeedsLoad(hnd) then begin
      Result:=lrAlreadyLoaded;
      Exit;
    end;
    FindResource(hnd.Owner.RefName, p);
    if p = nil then begin
      Result:=lrErrNoPhysResource;
      Exit;
    end;

    Result := PerformLoad(p, hnd.Owner, false);
  finally
    hnd.OwnerUnlock;
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

function TResourceObject.SwapLoads(unloadLoaded: Boolean): Boolean;
var
  un  : TObject;
  unl : TResourceLoader;
begin
  Result:=Assigned(loadObj) and Assigned(reloadObj);
  if not Result then Exit;

  Lock;
  try
    un := loadObj;
    unl := loadedWith;
    loadObj := reloadObj;
    loadedWith := reloadedWith;
    reloadObj := nil;
    reloadedWith := nil;
  finally
    Unlock;
  end;
  manager.UnloadResObj(refName, un, unl);
end;

procedure TResourceObject.UnloadAll;
begin
  if Assigned(loadObj) and Assigned(loadedWith) then
    manager.UnloadResObj(refName, loadObj, loadedWith);

  if Assigned(reloadObj) and Assigned(reloadedWith) then
    manager.UnloadResObj(refName, reloadObj, reloadedWith);
end;

constructor TResourceObject.Create(const ARefName: string; AManager: TResourceManager);
begin
  inherited Create;
  InitCriticalSection(flock);
  Handlers := TList.Create;
  fRefName := ARefName;
  fManager := AManager;
end;

destructor TResourceObject.Destroy;
begin
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

