program testread;

{$mode objfpc}{$H+}

uses
  heaptrc,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, resa_cintf;

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
end.

