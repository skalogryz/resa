program testread;

{$mode objfpc}{$H+}

uses
  heaptrc,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
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

procedure RegisterDefaults;
begin
  ResSourceAddDir('.');
  RegisterLoader(TBufLoader.Create);
end;

function EvenToStr(event: LongWord): string;
begin
  case event of
    EVENT_START_LOAD      : Result := 'EVENT_START_LOAD';
    EVENT_START_RELOAD    : Result := 'EVENT_START_RELOAD';
    EVENT_LOAD_SUCCESS    : Result := 'EVENT_LOAD_SUCCESS';
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
begin
  fn := ExtractFileName(ParamStr(0));
  u := fn;
  RegisterDefaults;
  writeln('ResManAlloc     = ', ResManAlloc(man));
  if withLog then SetLog(man);
  writeln('ResHndAlloc     = ', ResHndAlloc(man, PUnicodeChar(u), res));
  writeln('ResHndLoadSync  = ', ResHndLoadSync(res));
  writeln('ResHndRelease   = ', ResHndRelease(res));
  writeln('ResManRelease   = ', ResManRelease(man));
end;

begin
  //TestAllocation;
  //TestProvider;
  TestLoad;
end.

