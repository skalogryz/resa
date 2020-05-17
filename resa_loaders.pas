unit resa_loaders;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils,
  resa;

procedure RegisterLoader(aloader: TResourceLoader);
procedure UnregisterLoader(aloader: TResourceLoader);

var
  loaders: TList;

type
  { TBufLoader }

  TBufLoader = class(TResourceLoader)
    function CanLoad(const refName: string; stream: TStream): Boolean; override;
    function EstimateMem(const refName: string; stream: TStream; var ExpectedMem: QWord): Boolean; override;
    function LoadResource(
      const refName: string; stream: TStream;
      out Size: QWord; out resObject: TObject
    ): Boolean; override;
    function UnloadResource(const refName: string; var resObject: TObject): Boolean; override;
  end;

type
  TExternalResource = class(TObject)
    resRef    : Pointer;
    resRefNum : Integer;
  end;

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


type

  { TMemBuf }

  TMemBuf = class(TObject)
    mem : Pointer;
  end;

{ TBufLoader }

function TBufLoader.CanLoad(const refName: string; stream: TStream): Boolean;
begin
  Result := true; // yeah... anything can be pushed to RAM!
end;

function TBufLoader.EstimateMem(const refName: string; stream: TStream;
  var ExpectedMem: QWord): Boolean;
begin
  ExpectedMem := stream.Size;
  Result := true;
end;

function TBufLoader.LoadResource(const refName: string; stream: TStream; out
  Size: QWord; out resObject: TObject): Boolean;
var
  buf : TMemBuf;
begin
  buf := TMemBuf.Create;
  buf.mem := AllocMem(stream.Size);
  try
    Size := stream.Read(buf.mem^, stream.size);
    resObject := buf;
    Result := Size = stream.size;
  except
    FreeMem(buf.mem);
    buf.Free;
    resObject := nil;
    Result:=false;
  end;
end;

function TBufLoader.UnloadResource(const refName: string; var resObject: TObject): Boolean;
begin
  Result := resObject is TMemBuf;
  if not Result then Exit;
  FreeMem(TMemBuf(resObject).mem);
  TMemBuf(resObject).mem:=nil;
  resObject.Free;
  resObject := nil;
end;

initialization
  loaders := TList.Create;

finalization
  FreeLoaders;


end.
