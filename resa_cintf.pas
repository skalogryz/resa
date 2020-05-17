unit resa_cintf;

{$mode objfpc}{$H+}

interface

uses
  resa, resa_filesys, resa_providers, classes, sysutils;

type
  TResManagerHandle = PtrUInt;
  TResHandle = PtrUInt;
  TResError = type Integer;

function ResManAlloc(out man: TResManagerHandle): TResError; cdecl;
function ResManRelease(var man: TResManagerHandle): TResError; cdecl;
function ResHndAlloc(man: TResManagerHandle; const arefName: PUnicodeChar; var res: TResHandle): TResError; cdecl;
function ResHndRelease(var res: TResHandle): TResError; cdecl;
function ResHndGetFixed(res: TResHandle; var isFixed:LongBool): TResError; cdecl;
function ResHndSetFixed(res: TResHandle; isFixed: LongBool): TResError; cdecl;

function ResSourceAddDir(const dir: PUnicodeChar): Boolean;
function ResExists(const arefName: PUnicodeChar): Boolean;

const
  RES_NO_ERROR   = 0;
  RES_SUCCESS    = RES_NO_ERROR;
  RES_INV_PARAMS = -1;
  RES_INT_ERROR  = -100;

implementation

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

function ResManAlloc(out man: TResManagerHandle): TResError; cdecl;
begin
  try
    man:=TResManagerHandle(TResourceManager.Create);
    Result:=RES_SUCCESS;
  except
    man:=0;
    Result:=RES_INT_ERROR;
  end;
end;

function ResManRelease(var man: TResManagerHandle): TResError; cdecl;
begin
  if man = 0 then begin
    Result:=RES_INV_PARAMS;
    Exit;
  end;
  try
    TResourceManager(man).Free;
    Result:=RES_SUCCESS;
  except
    Result:=RES_INT_ERROR;
  end;
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
  ro := TResourceManager(man).RegisterResource(refName);
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
  isFixed := rfFixed in hnd.GetFlags;
end;

function ResHndSetFixed(res: TResHandle; isFixed:LongBool): TResError; cdecl;
var
  hnd : TResourceHandler;
begin
  if not ResHndSanityCheck(res, Result) then Exit;
  hnd := TResourceHandler(res);
  hnd.AddFlags([rfFixed]);
end;

function ResSourceAddDir(const dir: PUnicodeChar): Boolean;
var
  pth : UnicodeString;
  i   : integer;
  pl  : TList;
  p   : TResourceProvider;
  fp  : TFileResourceProvider;
  cmp : UnicodeString;
begin
  Result:=(dir<>nil) and (dir<>'');
  if not Result then Exit;
  pth := ExpandFileName(dir);
  Result := DirectoryExists(pth);
  if not Result then Exit;

  cmp := GetDirForCompare(pth);
  for i:=0 to providers.Count-1 do begin
    p := TResourceProvider(providers[i]);
    if not (p is TFileResourceProvider) then continue;
    fp := TFileResourceProvider(p);
    if fp.isSameDir(cmp) then begin
      Result:=true;
      Exit;
    end;
  end;
  RegisterProvider( TFileResourceProvider.Create(pth, cmp));
end;

function ResExists(const arefName: PUnicodeChar): Boolean;
var
  refName : string;
  p : TResourceProvider;
begin
  Result:=false;
  if providers = nil then Exit;

  refName := GetResName(arefName);
  Result := FindResource(refName, p);
end;

end.


