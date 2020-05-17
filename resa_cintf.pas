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
function ResHndLoadSync(ahnd: TResHandle): TResError;  cdecl;

function ResSourceAddDir(const dir: PUnicodeChar): TResError; cdecl;
function ResExists(const arefName: PUnicodeChar): TResError; cdecl;

const
  RES_SCHEDULED     = 1;
  RES_NO_ERROR      = 0;
  RES_SUCCESS       = RES_NO_ERROR;
  RES_INV_PARAMS    = -1;
  RES_INT_ERROR     = -100;
  RES_NO_RESOURCE   = -2;
  RES_NO_FILE       = -3;
  RES_UNK_FILE      = -4;
  RES_FAIL_LOAD     = -5;
  RES_NO_SOURCES    = -300;
  RES_NO_SOURCEROOT = -301;

const
  EVENT_START_LOAD      = 10;
  EVENT_START_RELOAD    = 11;
  EVENT_LOAD_SUCCESS    = 12;
  EVENT_UNLOADED_RES    = 13;
  EVENT_W_FAIL_TOLOAD   = 1000;
  EVENT_W_ABNORMAL_LOAD = 1001;

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

{ TResManHandle }


const
  ResouceManagerLogToEvent : array [TResouceManagerLog] of LongWord = (
    EVENT_START_LOAD,      // noteStartLoading,
    EVENT_START_RELOAD,    // noteStartReloading,
    EVENT_W_FAIL_TOLOAD,   // wantFailToLoad,
    EVENT_W_ABNORMAL_LOAD, // warnAbnormalLoad, // function returned true, but no object was provided
    EVENT_LOAD_SUCCESS,    // noteLoadSuccess,
    EVENT_UNLOADED_RES     // noteUnloadedResObj
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

end.


