unit resa_providers;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, resa;

var
  providers : TList = nil;

procedure RegisterProvider(p: TResourceProvider);
procedure UnregisterProvider(p: TResourceProvider);
function FindProvider(const refName: string; out p: TResourceProvider): Boolean; overload;
function FindProvider(const refName: string; plist: TList): Boolean; overload;

implementation

procedure RegisterProvider(p: TResourceProvider);
begin
  if p = nil then Exit;
  if providers.IndexOf(p)>=0 then Exit;
  providers.Add(p);
end;

procedure UnregisterProvider(p: TResourceProvider);
begin
  providers.Remove(p);
end;

function FindProvider(const refName: string; out p: TResourceProvider): Boolean; overload;
var
  pl : TList;
begin
  pl := TList.Create;
  try
    Result := FindProvider(refName, pl);
    if Result then
      p := TResourceProvider(pl[0])
    else
      p := nil;
  finally
    pl.Free;
  end;
end;

function FindProvider(const refName: string; plist: TList): Boolean; overload;
var
  i : integer;
  p : TResourceProvider;
begin
  Result:=false;
  if (refName = '') or (plist = nil) then Exit;
  for i:=0 to providers.Count-1 do begin
    p := TResourceProvider(providers[i]);
    if p.Exists(refName) then begin
      Result:=true;
      plist.Add(p);
    end;
  end;
end;

procedure FreeProviders;
var
  i : integer;
begin
  if not Assigned(providers) then Exit;
  for i:=0 to providers.Count-1 do
    TObject(providers[i]).Free;
  providers.Free;
end;

initialization
  providers := TList.create;

finalization
  FreeProviders;

end.

