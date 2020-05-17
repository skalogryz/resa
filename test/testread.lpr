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

procedure TestLoad;
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

