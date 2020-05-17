unit resa_loaders;

interface

uses
  Classes, SysUtils,
  resa;

procedure RegisterLoader(aloader: TResourceLoader);
procedure UnregisterLoader(aloader: TResourceLoader);

var
  loaders: TList;

implementation

procedure RegisterLoader(aloader: TResourceLoader);
begin
  if not Assigned(aloader) then Exit;
  if loaders.IndexOf(aloader)>=0 then Exit;
  loaders.Add(aloader);
end;

procedure UnregisterLoader(aloader: TResourceLoader);
begin
  loaders.Remove(aloader);
end;

procedure FreeLoaders;
var
  i : integer;
begin
  for i:=0 to loaders.Count-1 do begin
    TObject(loaders[i]).Free;
  end;
  loaders.Free;
end;

initialization
  loaders := TList.Create;

finalization
  FreeLoaders;


end.
