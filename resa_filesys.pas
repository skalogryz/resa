unit resa_filesys;

{$mode objfpc}{$H+}

interface

uses
  {$ifdef MSWIndows}
  Windows, // TFileStream doesn't support unicode names :(
  {$endif}
  Classes, SysUtils, resa
  ;


type
  { TFileResourceProvider }

  TFileResourceProvider = class(TResourceProvider)
  private
    lowBasePath : UnicodeString;
  public
    basePath: UnicodeString;
    constructor Create(const abaseDir: UnicodeString; const compareDir: UnicodeString = '');
    function Exists(const refName: string): Boolean; override;
    function AllocStream(const refName: string): TStream; override;
    procedure StreamDone(str: TStream); override;
    // comparedir must be a result of GetDirForCompare() for valid comparison
    function isSameDir(const comparedir: UnicodeString): Boolean;
  end;

function GetDirForCompare(const dir: UnicodeString): UnicodeString;

implementation

function GetDirForCompare(const dir: UnicodeString): UnicodeString;
begin
  Result := LowerCase(IncludeTrailingPathDelimiter(dir));
end;

{ TFileResourceProvider }

constructor TFileResourceProvider.Create(const abaseDir: UnicodeString; const compareDir: UnicodeString);
begin
  inherited Create;
  basePath := IncludeTrailingPathDelimiter(abaseDir);
  if (compareDir = '') then
    lowBasePath := GetDirForCompare(basePath)
  else
    lowBasePath := compareDir;
end;

function TFileResourceProvider.isSameDir(const comparedir: UnicodeString): Boolean;
begin
  Result := lowBasePath = comparedir;
end;

function TFileResourceProvider.Exists(const refName: string): Boolean;
var
  pth : UnicodeString;
begin
  pth := basePath + UTF8Decode(refName);
  Result := FileExists(refName);
end;

{$ifdef mswindows}
type

  { TWinReadonlyFileStream }

  TWinReadonlyFileStream = class (THandleStream)
  public
    ownHandle: Boolean;
    constructor Create(const afilename: UnicodeString; const AOwnHandle: Boolean = true);
    destructor Destroy; override;
  end;

{ TWinReadonlyFileStream }

constructor TWinReadonlyFileStream.Create(const afilename: UnicodeString; const AOwnHandle: Boolean);
var
  hnd : Windows.THANDLE;
begin
  hnd := CreateFileW(PWideChar(afilename)
    , GENERIC_READ
    , FILE_SHARE_DELETE or FILE_SHARE_WRITE
    , nil
    , OPEN_EXISTING
    , 0
    , 0);
  if hnd = INVALID_HANDLE_VALUE then
    raise EFOpenError.createfmt('failed to create: %d',[Windows.GetLastError]);
  OwnHandle:=AOwnHandle;
  inherited Create(hnd);
end;

destructor TWinReadonlyFileStream.Destroy;
begin
  if OwnHandle then CloseHandle(Self.Handle);
  inherited Destroy;
end;

{$endif}

function TFileResourceProvider.AllocStream(const refName: string): TStream;
begin
  try
    {$ifdef MSWindows}
    Result:=TWinReadonlyFileStream.Create(basePath + UTF8Decode(refName));
    {$else}
    Result:=TFileStream.Create( UTF8Encode(basePath)+refName, fmOpenRead or fmShareDenyNone);
    {$endif}
  except
    Result:=nil;
  end;
end;

procedure TFileResourceProvider.StreamDone(str: TStream);
begin
 // do nothing
end;

end.

