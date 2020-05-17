unit resa_cintf;

{$mode delphi}{$H+}

interface

uses
  resa, resa_filesys, resa_providers, classes, sysutils, resa_loaders;

type
  TResManagerHandle = PtrUInt;
  TResHandle = PtrUInt;
  TResError = type Integer;
  TResManCallBack = procedure(
    man: TResManagerHandle;
    event: LongWord;
    const resRef: PChar;
    const param1, param2: Int64;
    UserData: Pointer
  ); cdecl;

function ResManAlloc(out man: TResManagerHandle): TResError; cdecl;
function ResManRelease(var man: TResManagerHandle): TResError; cdecl;
function ResManSetCallback(man: TResManagerHandle; logproc: TResManCallBack; userData: Pointer): TResError; cdecl;
function ResHndAlloc(man: TResManagerHandle; const arefName: PUnicodeChar; var res: TResHandle): TResError; cdecl;
function ResHndRelease(var res: TResHandle): TResError; cdecl;
function ResHndGetFixed(res: TResHandle; var isFixed:LongBool): TResError; cdecl;
function ResHndSetFixed(res: TResHandle; isFixed: LongBool): TResError; cdecl;
function ResHndLoadSync(ahnd: TResHandle): TResError; cdecl;
function ResHndGetObj(res: TResHandle; var resource: Pointer; var resRefNumber: Integer; wantReloadedObj: Integer): TResError; cdecl;

function ResSourceAddDir(const dir: PUnicodeChar): TResError; cdecl;
function ResExists(const arefName: PUnicodeChar): TResError; cdecl;

const
  RES_SCHEDULED     = 1;
  RES_NO_ERROR      = 0;
  RES_SUCCESS       = RES_NO_ERROR;
  RES_INV_PARAMS    = -1;
  RES_INT_ERROR     = -100;  // internal errors
  RES_NO_RESOURCE   = -2;    // the requested refName doesn't exist
  RES_NO_FILE       = -3;    // the resource file doesn't exist, or cannot be found by its refName
  RES_UNK_FILE      = -4;    // the resource file doesn't have a loader that can load it
  RES_FAIL_LOAD     = -5;    // the resource file was not loaded, due to some problems with the loader
  RES_NOT_LOADED    = -6;    // the resource has not been loaded yet
  RES_INVALID_FMT   = -101;  // the resource was loaded, but the internal format is not recognizable. (internal error)
  RES_NO_SOURCES    = -300;  // no sources were registered
  RES_NO_SOURCEROOT = -301;  // the specified directory cannot be found for directory source

const
  EVENT_START_LOAD      = 10;
  EVENT_START_RELOAD    = 11;
  EVENT_LOAD_SUCCESS    = 12;
  EVENT_UNLOADED_RES    = 13;
  EVENT_W_FAIL_TOLOAD   = 1000;
  EVENT_W_ABNORMAL_LOAD = 1001;


type
  TStreamRef = Pointer;

  TLoadProc = procedure(
    LoaderData: Pointer;
    const refName: PChar;
    const streamRef: Pointer;
    var Size: Int64;
    var Resource: Pointer;
    var ResRefNum: Integer
  ); cdecl;

  TUnloadProc = procedure (
    LoaderData: Pointer;
    Resource: Pointer;
    ResRefNum: Integer
  ); cdecl;

  TCanLoadProc = procedure (
    LoaderData: Pointer;
    const refName: PChar;
    const streamRef: Pointer;
    var CanLoad: Integer
  ); cdecl;


  TResourceLoaderSt = packed record
    canLoadProc : TCanLoadProc;
    loadProc    : TLoadProc;
    unloadProc  : TUnloadProc;
  end;

function ResLoaderRegister(loaderData: Pointer; const procRef: TResourceLoaderSt): TResError; cdecl;
function ResLoaderUnregister(loaderData: Pointer): TResError; cdecl;

function StreamRead(streamRef: TStreamRef; dst: PByte; dstSize: Integer): Integer; cdecl;
function StreamGetSize(streamRef: TStreamRef): Int64; cdecl;
function StreamSetPos(streamRef: TStreamRef; apos: Int64): LongBool; cdecl;
function StreamGetPos(streamRef: TStreamRef): Int64; cdecl;

implementation

type

  { TResManHandle }

  TResManHandle = class(TObject)
    manager    : TResourceManager;
    logCallback: TResManCallBack;
    logUserData: Pointer;
    procedure ManLog(Sender: TResourceManager;
      const logMsg: TResouceManagerLog;
      const refName: string;
      param1: Int64 = 0; param2: Int64 = 0);
    constructor Create;
    destructor Destroy; override;
  end;


function GetResName(const nm: PUnicodeChar): string;
var
  us : UnicodeString;
begin
  if (nm = nil) or (nm='') then Result:=''
  else begin
    us := nm;
    Result := UTF8Encode(us);
  end;
end;

function SanityCheckManHandle(ahandle: TResManagerHandle;
  out handleObj: TResManHandle;
  out resError: TResError): Boolean; inline;
begin
  Result := (Ahandle<>0)
    and (TObject(Ahandle) is TResManHandle);
  if not Result then resError := RES_INV_PARAMS
  else resError := RES_SUCCESS;
  handleObj := TResManHandle(AHandle);
end;

function ResManAlloc(out man: TResManagerHandle): TResError; cdecl;
begin
  try
    man:=TResManagerHandle(TResManHandle.Create);
    Result:=RES_SUCCESS;
  except
    man:=0;
    Result:=RES_INT_ERROR;
  end;
end;

function ResManRelease(var man: TResManagerHandle): TResError; cdecl;
var
  h: TResManHandle;
begin
  if not SanityCheckManHandle(man, h, Result) then Exit;
  try
    h.Free;
    Result:=RES_SUCCESS;
  except
    Result:=RES_INT_ERROR;
  end;
end;

function ResManSetCallback(man: TResManagerHandle; logproc: TResManCallBack; userData: Pointer): TResError; cdecl;
var
  h: TResManHandle;
begin
  if not SanityCheckManHandle(man, h, Result) then Exit;
  //todo: need a lock here
  h.logCallback:=logproc;
  h.logUserData:=userData;
  if Assigned(logproc) then
    h.manager.LogProc := h.ManLog
  else
    h.manager.LogProc := nil;
end;

function ResHndAlloc(man: TResManagerHandle; const arefName: PUnicodeChar; var res: TResHandle): TResError; cdecl;
var
  ro : TResourceObject;
  refName : string;
begin
  if (man = 0) or (arefName = nil) or (arefName='') or (@res = nil) then begin
    Result:=RES_INV_PARAMS;
    Exit;
  end;
  refName := GetResName(arefName);
  ro := TResManHandle(man).manager.RegisterResource(refName);
  if ro = nil then begin
    Result:=RES_INT_ERROR;
    Exit;
  end;
  res := TResHandle(ro.AllocHandle);
  Result := RES_SUCCESS;
end;

function ResHndSanityCheck(res: TResHandle; out resCode: TResError): Boolean; inline;
begin
  Result := res <> 0;
  if not Result then resCode:=RES_INV_PARAMS
  else resCode:=RES_SUCCESS;
end;

function ResHndRelease(var res: TResHandle): TResError; cdecl;
var
  h : TResourceHandler;
begin
  if not ResHndSanityCheck(res, Result) then Exit;
  try
    h := TResourceHandler(res);
    h.Owner.ReleaseHandle(h);
    res:=0;
    Result:=RES_SUCCESS;
  except
    Result:=RES_INT_ERROR;
  end;
end;

function ResHndGetFixed(res: TResHandle; var isFixed:LongBool): TResError; cdecl;
var
  hnd : TResourceHandler;
begin
  if not ResHndSanityCheck(res, Result) then Exit;
  hnd := TResourceHandler(res);
  isFixed := rfFixed in hnd.Owner.GetFlags;
end;

function ResHndSetFixed(res: TResHandle; isFixed:LongBool): TResError; cdecl;
var
  hnd : TResourceHandler;
begin
  if not ResHndSanityCheck(res, Result) then Exit;
  hnd := TResourceHandler(res);
  hnd.Owner.AddFlags([rfFixed]);
end;

function ResSourceAddDir(const dir: PUnicodeChar): TResError; cdecl;
var
  pth : UnicodeString;
  i   : integer;
  pl  : TList;
  p   : TResourceProvider;
  fp  : TFileResourceProvider;
  cmp : UnicodeString;
begin
  if not ((dir<>nil) and (dir<>'')) then begin
    Result:=RES_INV_PARAMS;
    Exit;
  end;

  pth := ExpandFileName(dir);
  if not DirectoryExists(pth) then begin
    Result:=RES_NO_SOURCEROOT;
    Exit;
  end;

  cmp := GetDirForCompare(pth);
  for i:=0 to providers.Count-1 do begin
    p := TResourceProvider(providers[i]);
    if not (p is TFileResourceProvider) then continue;
    fp := TFileResourceProvider(p);
    if fp.isSameDir(cmp) then begin
      Result:=RES_SUCCESS;
      Exit;
    end;
  end;
  RegisterProvider( TFileResourceProvider.Create(pth, cmp));
  Result:=RES_SUCCESS;
end;

function ResExists(const arefName: PUnicodeChar): TResError; cdecl;
var
  refName : string;
  p : TResourceProvider;
begin
  if (providers = nil) or (providers.Count=0) then begin
    Result:=RES_NO_SOURCES;
    Exit;
  end;

  refName := GetResName(arefName);
  if not FindResource(refName, p) then
    Result:=RES_NO_RESOURCE
  else
    Result:=RES_SUCCESS;
end;

const
  LoadErrorToResError : array [TLoadResult] of  TResError = (
   RES_SUCCESS,     // lrSuccess,
   RES_SUCCESS,     // lrLoaded,
   RES_SUCCESS,     // lrAlreadyLoaded,
   RES_SCHEDULED,   // lrLoadScheduled,
   RES_NO_RESOURCE, // lrErrNoPhysResource,
   RES_NO_FILE,     // lrErrNoStream,
   RES_UNK_FILE,    // lrErrUnkResource,
   RES_FAIL_LOAD    // lrErrFailToLoad
  );

function ResHndLoadSync(ahnd: TResHandle): TResError; cdecl;
var
  hnd : TResourceHandler;
  p   : TResourceProvider;
  res : TLoadResult;
begin
  if not ResHndSanityCheck(ahnd, Result) then Exit;
  hnd := TResourceHandler(ahnd);
  res := hnd.Owner.manager.LoadResourceSync(hnd);
  Result := LoadErrorToResError[res];
end;

function ResHndGetObj(res: TResHandle; var resource: Pointer;
  var resRefNumber: Integer; wantReloadedObj: Integer): TResError; cdecl;
var
  neededFlag : TResourceFlags;
  hnd : TResourceHandler;
  obj : TObject;
  idx : integer;
  er  : TExternalResource;
begin
  resource:=nil;
  resRefNumber:=0;
  if not ResHndSanityCheck(res, Result) then Exit;

  hnd := TResourceHandler(res);
  if wantReloadedObj <> 0 then wantReloadedObj := 1;

  if wantReloadedObj = 0 then neededFlag := [rfLoaded]
  else neededFlag := [rfReloaded];

  if hnd.Owner.GetFlags * neededFlag = [] then
    Result:= RES_NOT_LOADED
  else begin
    hnd.Owner.Lock;
    try
      idx := wantReloadedObj;
      obj:=hnd.Owner.resObj[idx].obj;
      if not (obj is TExternalResource) then
        Result := RES_INVALID_FMT
      else begin
        er := TExternalResource(obj);
        Resource := er.resRef;
        resRefNumber := er.resRefNum;
        Result := RES_SUCCESS;
      end;
    finally
      hnd.Owner.Unlock;
    end;
  end;
end;

{ TResManHandle }


const
  ResouceManagerLogToEvent : array [TResouceManagerLog] of LongWord = (
    EVENT_START_LOAD,      // noteStartLoading,
    EVENT_START_RELOAD,    // noteStartReloading,
    EVENT_LOAD_SUCCESS,    // noteLoadSuccess,
    EVENT_UNLOADED_RES,    // noteUnloadedResObj
    EVENT_W_FAIL_TOLOAD,   // wantFailToLoad,
    EVENT_W_ABNORMAL_LOAD  // warnAbnormalLoad, // function returned true, but no object was provided
  );

procedure TResManHandle.ManLog(Sender: TResourceManager;
  const logMsg: TResouceManagerLog; const refName: string; param1: Int64;
  param2: Int64);
begin
  if not Assigned(logCallback) then Exit;
  logCallback(
    TResManagerHandle(Self),
    ResouceManagerLogToEvent[logMsg],
    PChar(refName),
    param1, param2,
    logUserData
  );
end;

constructor TResManHandle.Create;
begin
  inherited Create;
  manager := TResourceManager.Create;
end;

destructor TResManHandle.Destroy;
begin
  manager.Free;
  inherited Destroy;
end;

function StreamRead(streamRef: TStreamRef; dst: PByte; dstSize: Integer): Integer; cdecl;
begin
  if not Assigned(streamRef) or not Assigned(dst) then begin
    Result:=-1;
    Exit;
  end;
  try
    Result := TStream(streamRef).Read(dst^, dstSize);
  except
    Result:=-1;
  end;
end;

function StreamGetSize(streamRef: TStreamRef): Int64;
begin
  try
    if not Assigned(streamRef) then Result:=-1
    else Result:=TStream(streamRef).Size;
  except
    Result:=-1;
  end;
end;

function StreamSetPos(streamRef: TStreamRef; apos: Int64): LongBool;
begin
  try
    TStream(streamRef).Position:=apos;
    Result:=true;
  except
    Result:=false;
  end;
end;

function StreamGetPos(streamRef: TStreamRef): Int64; cdecl;
begin
  Result:=TStream(streamRef).Position;
end;

type

  { TExternalLoader }

  TExternalLoader = class(TResourceLoader)
    LoaderData: Pointer;
    LoadProc: TLoadProc;
    UnloadProc: TUnloadProc;
    CanLoadProc: TCanLoadProc;
    function CanLoad(const refName: string; stream: TStream): Boolean;
      override;
    function LoadResource(
      const refName: string; stream: TStream;
      out Size: QWord; out resObject: TObject
    ): Boolean; override;
    function UnloadResource(const refName: string; var resObject: TObject): Boolean;
      override;
  end;


function ResLoaderRegister(loaderData: Pointer; const procRef: TResourceLoaderSt): TResError;
var
  ldr : TExternalLoader;
begin
  if not Assigned(procRef.canLoadProc)
    or not Assigned(procRef.unloadProc)
    or not Assigned(procRef.loadProc) then
  begin
    Result:=RES_INV_PARAMS;
    Exit;
  end;

  ldr := TExternalLoader.Create;
  ldr.LoaderData := loaderData;
  ldr.LoadProc := procRef.loadProc;
  ldr.CanLoadProc := procRef.canLoadProc;
  ldr.UnloadProc := procRef.unloadProc;
  RegisterLoader(ldr);
  Result:=RES_SUCCESS;
end;

function ResLoaderUnregister(loaderData: Pointer): TResError;
var
  i : integer;
  ld : TExternalLoader;
begin
  for i:=0 to loaders.Count-1 do
    if (TObject(loaders[i]) is TExternalLoader) then begin
      ld := TExternalLoader(TObject(loaders[i]));
      if (ld.LoaderData = loaderData) then
      begin
        UnregisterLoader(TExternalLoader(TObject(loaders[i])));
        Result:=RES_SUCCESS;
        Exit;
      end;
    end;
  Result:=RES_INV_PARAMS;
end;

{ TExternalLoader }

function TExternalLoader.CanLoad(const refName: string; stream: TStream
  ): Boolean;
var
 resI: integer;
begin
  if not Assigned(CanLoadProc) then begin
    Result:=false;
    Exit;
  end;
  resI:=0;
  CanLoadProc(LoaderData, PChar(refName), TStreamRef(stream), resI);
  Result:=resI<>0;
end;

function TExternalLoader.LoadResource(const refName: string; stream: TStream;
  out Size: QWord; out resObject: TObject): Boolean;
var
  resRef : Pointer;
  resNum : integer;
  ext    : TExternalResource;
begin
  Size:=0;
  resObject:=nil;
  Result := Assigned(LoadProc);
  if not Result then Exit;

  resRef := nil;
  resNum := 0;
  LoadProc(LoaderData,
    PChar(refName),
    TStreamRef(Stream),
    Size, resRef, resNum);
  Result := resRef<>nil;
  if not Result then Exit;

  ext := TExternalResource.Create;
  ext.resRef := resRef;
  ext.resRefNum := resNum;
  resObject := ext;
end;

function TExternalLoader.UnloadResource(const refName: string;
  var resObject: TObject): Boolean;
var
  er : TExternalResource;
begin
  Result := Assigned(UnloadProc) and (resObject is TExternalResource);
  if not Result then Exit;

  er := TExternalResource(resObject);
  UnloadProc(LoaderData, er.resRef, er.resRefNum);
  resObject.Free;
  Result:=true;
end;

end.


