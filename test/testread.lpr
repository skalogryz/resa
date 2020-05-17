program testread;

{$mode objfpc}{$H+}

uses
  heaptrc,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Math,
  Classes, SysUtils, resa_cintf, resa, resa_filesys, resa_providers, resa_loaders;

procedure TestAllocation;
var
  mn  : TResManagerHandle;
  err : TResError;
  res : TResHandle;
  f   : LongBool;
begin
  err:=ResManAlloc(mn);
  if err<>0 then begin
    writelN('AllocManager: ', err);
    Exit;
  end;
  try
    err:=ResHndAlloc(mn, 'test', res);
    if err<>0 then begin
      writelN('ResHndAlloc: ', err);
      Exit;
    end;
    ResHndGetFixed(res, f);
    writeln('f=',f);
    ResHndSetFixed(res, true);
    ResHndGetFixed(res, f);
    writeln('f=',f);

    ResHndRelease(res);
  finally
    ResManRelease(mn);
  end;
end;

procedure {%H-}TestProvider;
var
  fn : string;
  u  : UnicodeString;
begin
  fn := ExtractFileName(ParamStr(0));
  u := fn;
  writeln('check existance of ',fn,': ', ResExists(PUnicodeChar(u)));
  ResSourceAddDir('.');
  writeln('check existance of ',fn,': ', ResExists(PUnicodeChar(u)));
end;

procedure canLoadRes(LoaderData: Pointer;
    const refName: PChar;
    const streamRef: Pointer;
    var CanLoad: Integer
  ); cdecl;
begin
  CanLoad := 1;
end;

procedure LoadRes(LoaderData: Pointer;
    const refName: PChar;
    const streamRef: Pointer;
    var Size: Int64;
    var Resource: Pointer;
    var ResRefNum: Integer
  ); cdecl;
var
  szLeft : Int64;
  p : PByte;
  rd : integer;
begin
  Size := StreamGetSize(streamRef);
  Resource := AllocMem(Size);
  szLeft := Size;
  p:=Resource;
  while szLeft>0 do begin
    rd:=StreamRead(streamRef, p, Max(szLeft, MaxInt));
    if rd<=0 then Break;
    dec(szLeft, rd);
    p:=p+szLeft;
  end;
  writeln('loaded at: ', PtrUInt(Resource));
end;

procedure UnloadRes(LoaderData: Pointer; Resource: Pointer; ResRefNum: Integer); cdecl;
begin
  FreeMem(Resource);
end;

procedure RegisterDefaults;
var
  st : TResourceLoaderSt;
begin
  st.canLoadProc := @canLoadRes;
  st.loadProc := @loadRes;
  st.unloadProc := @unloadRes;

  ResSourceAddDir('.');
  ResLoaderRegister(nil, st);
  //RegisterLoader(TBufLoader.Create);
end;

function EvenToStr(event: LongWord): string;
begin
  case event of
    EVENT_START_LOAD      : Result := 'EVENT_START_LOAD';
    EVENT_START_RELOAD    : Result := 'EVENT_START_RELOAD';
    EVENT_LOAD_SUCCESS    : Result := 'EVENT_LOAD_SUCCESS';
    EVENT_SWAPPED         : Result := 'EVENT_SWAPPED';
    EVENT_UNLOAD_START    : Result := 'EVENT_UNLOAD_START';
    EVENT_UNLOADED_RES    : Result := 'EVENT_UNLOADED_RES';
    EVENT_W_FAIL_TOLOAD   : Result := 'EVENT_W_FAIL_TOLOAD';
    EVENT_W_ABNORMAL_LOAD : Result := 'EVENT_W_ABNORMAL_LOAD';
  else
    Result:=Format('UNKEV(%d)',[event]);
  end;
end;

procedure MsgLog(man: TResManagerHandle;
    event: LongWord;
    const resRef: PChar;
    const param1, param2: Int64;
    UserData: Pointer
  ); cdecl;
begin
  writeln('[',GetCurrentThreadId,'] ev=',EvenToStr(event),'; res=',resRef, '; p1=',param1, '; p2=',param2);
end;

procedure SetLog(Man: TResManagerHandle);
begin
  ResManSetCallback(Man, @MsgLog, nil);
end;

procedure TestLoad(withLog: Boolean = false);
var
  fn  : string;
  u   : UnicodeString;
  man : TResManagerHandle;
  res : TResManagerHandle;
  p   : Pointer;
  ref : Integer;
begin
  fn := ExtractFileName(ParamStr(0));
  u := fn;
  RegisterDefaults;
  writeln('ResManAlloc      = ', ResManAlloc(man));
  if withLog then SetLog(man);
  writeln('ResHndAlloc      = ', ResHndAlloc(man, PUnicodeChar(u), res));
  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));

  writeln('ResHndLoadSync   = ', ResHndLoadSync(res));

  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));

  writeln('ResHndUnloadSync = ', ResHndUnloadSync(res, 0));

  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));

  writeln('ResHndRelease    = ', ResHndRelease(res));
  writeln('ResManRelease    = ', ResManRelease(man));
end;


procedure ResCb1(
    man : TResManagerHandle;
    event : LongWord;
    const resRef: PChar;
    const param1, param2: Int64;
    userData: Pointer
  ); cdecl;
begin
  writeln('CB1 [',GetCurrentThreadId,'] ev=',EvenToStr(event),'; res=',resRef, '; p1=',param1, '; p2=',param2);
end;

procedure ResCb2(
    man : TResManagerHandle;
    event : LongWord;
    const resRef: PChar;
    const param1, param2: Int64;
    userData: Pointer
  ); cdecl;
begin
  writeln('CB2 [',GetCurrentThreadId,'] ev=',EvenToStr(event),'; res=',resRef, '; p1=',param1, '; p2=',param2);
end;

procedure TestLoadCallback(withLog: Boolean = false);
var
  fn  : string;
  u   : UnicodeString;
  man : TResManagerHandle;
  res : TResManagerHandle;
  p   : Pointer;
  ref : Integer;
begin
  fn := ExtractFileName(ParamStr(0));
  u := fn;
  RegisterDefaults;
  writeln('ResManAlloc      = ', ResManAlloc(man));
  if withLog then SetLog(man);
  writeln('ResHndAlloc      = ', ResHndAlloc(man, PUnicodeChar(u), res));

  ResHndAddCallback(res, @ResCb1, EVENTRES_AFTER_LOAD or EVENTRES_BEFORE_UNLOAD, nil);
  ResHndAddCallback(res, @ResCb2, EVENTRES_BEFORE_UNLOAD, nil);

  writeln('ResHndLoadSync   = ', ResHndLoadSync(res));
  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));
  writeln('ResHndUnloadSync = ', ResHndUnloadSync(res, 0));
  writeln('ResHndRelease    = ', ResHndRelease(res));
  writeln('ResManRelease    = ', ResManRelease(man));
end;

procedure TestSwap;
var
  fn  : string;
  u   : UnicodeString;
  man : TResManagerHandle;
  res : TResManagerHandle;
  p   : Pointer;
  ref : Integer;
begin
  fn := ExtractFileName(ParamStr(0));
  u := {%H-}fn;
  RegisterDefaults;
  writeln('ResManAlloc      = ', ResManAlloc(man));
  SetLog(man);
  writeln('ResHndAlloc      = ', ResHndAlloc(man, PUnicodeChar(u), res));
  writeln('ResHndLoadSync   = ', ResHndLoadSync(res));
  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));
  writeln('ResHndLoadSync   = ', ResHndReloadSync(res));
  writeln('ResHndGetObj[0]  = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));
  writeln('ResHndGetObj[1]  = ', ResHndGetObj(res, p, ref, 1));
  writeln('  loaded obj = ', PtrUInt(p));

  writeln('ResHndLoadSync   = ', ResHndSwap(res));
  writeln('ResHndGetObj     = ', ResHndGetObj(res, p, ref, 0));
  writeln('  loaded obj = ', PtrUInt(p));

  writeln('ResHndUnloadSync = ', ResHndUnloadSync(res, 0));
  writeln('ResHndRelease    = ', ResHndRelease(res));
  writeln('ResManRelease    = ', ResManRelease(man));
end;

begin
  //TestAllocation;
  //TestProvider;
  //TestLoad(true);
  //TestLoadCallback(true);
  TestSwap;
end.

