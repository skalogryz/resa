unit resa_cintf;

{$mode objfpc}{$H+}

interface

uses
  resa;

type
  TResManagerHandle = PtrUInt;
  TResHandle = PtrUInt;
  TResError = type Integer;

function ResManAlloc(out man: TResManagerHandle): TResError; cdecl;
function ResManRelease(var man: TResManagerHandle): TResError; cdecl;
function ResHndAlloc(man: TResManagerHandle; const refName: PUnicodeChar; var res: TResHandle): TResError; cdecl;
function ResHndRelease(var res: TResHandle): TResError; cdecl;
function ResHndGetFixed(res: TResHandle; var isFixed:LongBool): TResError; cdecl;
function ResHndSetFixed(res: TResHandle; isFixed:LongBool): TResError; cdecl;

const
  RES_NO_ERROR   = 0;
  RES_SUCCESS    = RES_NO_ERROR;
  RES_INV_PARAMS = -1;
  RES_INT_ERROR  = -100;

implementation

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

function ResHndAlloc(man: TResManagerHandle; const refName: PUnicodeChar; var res: TResHandle): TResError; cdecl;
var
  ro : TResourceObject;
begin
  if (man = 0) or (refName = nil) or (refName='') or (@res = nil) then begin
    Result:=RES_INV_PARAMS;
    Exit;
  end;
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

end.

