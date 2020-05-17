unit resa;

{$ifdef fpc}{$mode delphi}{$H+}{$endif}

interface

uses
  Classes, SysUtils, HashClasses;

type
  TResourceFlags = set of (
    rfLoading,    // loading in progress
    rfLoaded,     // loaded
    rfReloading,  // is reloading
    rfReloaded,   // reloaded version is ready
    rfFixed       // cannot be unloaded
  );

  TResourceHandler = class;

  { TResourceObject }

  TResourceObject = class(TObject)
  // object of the no interface
  private
    RefCount : Integer;
    Handlers : TList;
    Flags    : TResourceFlags;
    flock    : TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    function AllocHandle: TResourceHandler;
    procedure ReleaseHandle(var AHnd: TResourceHandler);
    procedure Lock;
    procedure Unlock;
  end;

  { TResourceHandler }

  TResourceHandler = class(TObject)
  private
    fOwner : TResourceObject;
  public
    // call the constructor only while TResourceObject is locked
    constructor Create(AOwner: TResourceObject);
    destructor Destroy; override;
    procedure FreeInstance; override;
    property Owner: TResourceObject read fOwner;

    function GetFlags: TResourceFlags;
    procedure AddFlags(fl: TResourceFlags);
    procedure RemoveFlags(fl: TResourceFlags);
  end;

  TResourceTypeDef = class(TObject)
  end;

  { TResourceManager }

  TResourceManager = class(TObject)
  private
    resList : THashedStringListEx;
    function GetResource(const refName: string; forced: Boolean): TResourceObject;
  public
    lock      : TRTLCriticalSection;
    maxMem    : QWord;
    maxThread : LongWord;
    constructor Create;
    destructor Destroy; override;
    function RegisterResource(const refName: string): TResourceObject;
    function ResourceExists(const refName: string): TResourceObject;
  end;

  TResourceProvider = class(TObject)
    function Exists(const refName: string): Boolean; virtual; abstract;
    function AllocStream(const refName: string): TStream; virtual; abstract;
    procedure StreamDone(str: TStream); virtual; abstract;
  end;

  TResourceLoader = class(TObject)
  public
    procedure LoadResource(
      const refName: string; stream: TStream;
      out Size: QWord; out resObject: Pointer
    ); virtual; abstract;
    procedure UnloadResource(const refName: string; resObject: Pointer);
      virtual; abstract;
  end;

  { TBufLoader }

  TBufLoader = class(TResourceLoader)
    procedure LoadResource(
      const refName: string; stream: TStream;
      out Size: QWord; out resObject: Pointer
    ); override;
    procedure UnloadResource(const refName: string; resObject: Pointer); override;
  end;

implementation

{ TBufLoader }

procedure TBufLoader.LoadResource(const refName: string; stream: TStream; out
  Size: QWord; out resObject: Pointer);
begin
  resObject := AllocMem(stream.Size);
  Size := stream.Read(resObject, stream.size);
end;

procedure TBufLoader.UnloadResource(const refName: string; resObject: Pointer);
begin
  Freemem(resObject);
end;

{ TResourceHandler }

constructor TResourceHandler.Create(AOwner: TResourceObject);
begin
  inherited Create;
  fOwner:=AOwner;
end;

destructor TResourceHandler.Destroy;
begin
  if Assigned(fOwner) then
    fOwner.ReleaseHandle(Self)
  else
    inherited Destroy;
end;

procedure TResourceHandler.FreeInstance;
begin
  inherited FreeInstance;
end;

function TResourceHandler.GetFlags: TResourceFlags;
begin
  Owner.Lock;
  try
    Result:=Owner.Flags;
  finally
    Owner.Unlock;;
  end;
end;

procedure TResourceHandler.AddFlags(fl: TResourceFlags);
begin
  Owner.Lock;
  try
    Owner.Flags:=Owner.Flags+fl;
  finally
    Owner.Unlock;
  end;
end;

procedure TResourceHandler.RemoveFlags(fl: TResourceFlags);
begin
  Owner.lock;
  try
    Owner.Flags:=Owner.Flags-fl;
  finally
    Owner.Unlock;
  end;
end;

{ TResourceManager }

function TResourceManager.GetResource(const refName: string; forced: Boolean): TResourceObject;
var
  i : integer;
begin
  i:=resList.IndexOf(refName);
  if (i>=0) then begin
    Result:=TResourceObject(resList.Objects[i]);
    Exit;
  end;
  if forced then begin
    Result:=TResourceObject.Create;
    resList.AddObject(refName, Result);
  end else
    Result:=nil;
end;

constructor TResourceManager.Create;
begin
  inherited Create;
  InitCriticalSection(lock);
  resList:=THashedStringListEx.Create;
  maxMem:=High(Int64);
  maxThread:=4;
end;

destructor TResourceManager.Destroy;
var
  i : integer;
begin
  for i:=0 to resList.Count-1 do
    TObject(resList.Objects[i]).Free;
  resList.Free;
  DoneCriticalsection(lock);
  inherited Destroy;
end;

function TResourceManager.RegisterResource(const refName: string): TResourceObject;
begin
  EnterCriticalsection(lock);
  try
    Result := GetResource(refName, true);
  finally
    LeaveCriticalsection(lock);
  end;
end;

function TResourceManager.ResourceExists(const refName: string): TResourceObject;
begin
  EnterCriticalsection(lock);
  try
    Result := GetResource(refName, true);
  finally
    LeaveCriticalsection(lock);
  end;
end;

{ TResourceObject }

constructor TResourceObject.Create;
begin
  inherited Create;
  InitCriticalSection(flock);
  Handlers := TList.Create;
end;

destructor TResourceObject.Destroy;
begin
  DoneCriticalsection(flock);
  Handlers.free;
  inherited Destroy;
end;

function TResourceObject.AllocHandle: TResourceHandler;
begin
  Lock;
  try
    Result:=TResourceHandler.Create(Self);
    inc(RefCount);
    Handlers.Add(Result);
  finally
    Unlock;
  end;
end;

procedure TResourceObject.ReleaseHandle(var AHnd: TResourceHandler);
begin
  if not Assigned(AHnd) then Exit;
  Lock;
  try
    if AHnd.fOwner<>self then Exit;
    Handlers.Remove(AHnd);
    dec(RefCount);
    AHnd.fOwner:=nil; // must nil-out the owner first!
    AHnd.Free;
  finally
    Unlock;
  end;
end;

procedure TResourceObject.Lock;
begin
  EnterCriticalsection(flock);
end;

procedure TResourceObject.Unlock;
begin
  LeaveCriticalsection(flock);
end;

end.

