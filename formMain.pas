{
******************************************************
  Monkey Island Music Extractor
  Copyright (c) 2011 Bgbennyboy
  Http://quick.mixnmojo.com
******************************************************
}

unit formMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms, Generics.collections,
  Dialogs, StdCtrls, JvBaseDlg, JvBrowseFolder, ExtCtrls, pngimage, ACS_Misc, inifiles, jclsysinfo;

type
  TfrmMain = class(TForm)
    btnOpen: TButton;
    OpenDialog1: TOpenDialog;
    JvBrowseForFolderDialog1: TJvBrowseForFolderDialog;
    RadioGroup1: TRadioGroup;
    Image1: TImage;
    MemoOutput: TMemo;
    TagEditor1: TTagEditor;
    procedure btnOpenClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    function CheckValidPAKFile(PAKFile: TFilestream): boolean;
    function ExtractFileFromPAKToStream(PAKFile: TFilestream; FileName: String; var MemStream: TMemoryStream): boolean;
    function GetInfoFromAWBFile(MemStream: TMemoryStream; var Offsets: TList<Integer>; var StringList: TStringList): boolean;
    procedure DumpOggsFromStream(SourceStream: TMemoryStream; DestDir: string; FileNames: TStringList; FileOffsets: TList<Integer>);
    procedure Output(Text: string);
    procedure TagMusic(FileName, SectionName: string);
    procedure ExtractTempResourcesAndInitIniFile;
    procedure DeleteTempResources;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;
  IniFile: TMemInifile;

type
  TIntArray = array of integer;

const
  strAppName              = 'Monkey Island Music Extractor';
  strAppVersion           = '1.1';
  strAuthor               = 'By bgbennyboy';
  strWebsite              = 'Http://quick.mixnmojo.com';
  strDumpingBegin         = 'Beginning music extraction...';
  strDumpingComplete      = '...done!';
  strCommentTag           = 'Created with Monkey Island Music Extractor ';
  strErrorInvalidPakFile  = 'Not a valid .PAK file!';
  strErrorPAKExtract      = 'Couldn''t extract music from .PAK file!';
  strErrorNotInPAK        = 'Couldnt''t find file inside the .PAK!';
  strNoFilesIs0           = 'Number of music files is 0 ???';
  DefaultFileName         = 'audio/default.aws';
  DefaultInfoFileName     = 'audio/default.awb';
  UiFileName              = 'audio/ui.aws';
  UIInfoFileName          = 'audio/ui.awb';

implementation

{$R *.dfm}

function ReadString(TheStream: TStream; Length: integer): string;
var
  n: longword;
  t: byte;
begin
  SetLength(result,length);
  for n:=1 to length do
  begin
    TheStream.Read(t, 1);
    result[n]:=Chr(t);
  end;
end;

function ReadNullTerminatedString(TheStream: TStream; MaxLength: longword): string;
var
  n: longword;
  TempByte: byte;
  TempChar: char;
begin
  result:='';
  for n:=1 to MaxLength do
  begin
    TheStream.Read(TempByte, 1);
    TempChar:=Chr(TempByte);
    if TempChar=#0 then
      Exit;
    result:=result+TempChar;
  end;
end;

procedure TfrmMain.Output(Text: string);
begin
  MemoOutput.Lines.Add(Text);
end;

procedure TfrmMain.btnOpenClick(Sender: TObject);
var
  PAKFile: TFileStream;
  MusicStream, InfoStream: TMemoryStream;
  FileNames: TStringList;
  FileOffsets: TList<integer>;
  MusicFileName, InfoFileName: string;
begin
  if OpenDialog1.Execute = false then exit;
  if JVBrowseForFolderDialog1.Execute = false then exit;

  case RadioGroup1.ItemIndex of
    0: begin
        MusicFileName := DefaultFileName;
        InfoFileName := DefaultInfoFileName;
       end;
    1: begin
        MusicFileName := UiFileName;
        InfoFileName := UiInfoFileName;
       end;
  end;

  PAKFile := TFileStream.Create(OpenDialog1.FileName, fmOpenRead);
  try
    if CheckValidPAKFile(PAKFile) = false then
    begin
      Output( strErrorInvalidPakFile );
      exit;
    end;

    MusicStream := TMemoryStream.Create;
    try
      if ExtractFileFromPAKToStream(PAKFile, MusicFileName, MusicStream) = false then exit;

      InfoStream := TMemoryStream.Create;
      try
        if ExtractFileFromPAKToStream(PAKFile, InfoFileName, InfoStream) = false then exit;

        FileNames := TStringList.Create;
        try
          FileOffsets := TList<integer>.Create;
          try
            if GetInfoFromAWBFile(InfoStream, FileOffsets, FileNames) = false then exit;
            //All ok so dump the files
            Output( strDumpingBegin );
            DumpOggsFromStream(MusicStream, JVBrowseForFolderDialog1.Directory, FileNames, FileOffsets);
            OutPut( strDumpingComplete );
            Beep;
          finally
            FileOffsets.Free;
          end;
        finally
          FileNames.Free;
        end;
      finally
        InfoStream.Free;
      end;


    finally
      MusicStream.Free;
    end;

  finally
    PAKFile.Free;
  end;
end;

function TfrmMain.CheckValidPAKFile(PAKFile: TFilestream): boolean;
var
  TempDWord: DWord;
begin
  //Check header
  PAKFile.Position := 0;
  PakFile.Read(TempDWord, 4);
  if TempDWord <> 1280328011 then //KAPL
    result := false
  else
    result := true;
end;

function TfrmMain.ExtractFileFromPAKToStream(PAKFile: TFilestream; FileName: String;
  var MemStream: TMemoryStream): boolean;
const
  sizeOfFileRecord: integer = 20;
var
  Tempstr: string;
  startOfFileEntries : DWord;
  startOfFileNames   : DWord;
  startOfData        : DWord;
  sizeOfIndex        : DWord;
  sizeOfFileEntries  : DWord;
  sizeOfFileNames    : DWord;
  sizeOfData         : DWord;
  i, currNameOffset, SearchFileIndex, SearchFileSize, SearchFileOffset: integer;
begin
  PAKFile.Position := 0;
  MemStream.Clear;

  PakFile.Position := 12;
  PakFile.read( startOfFileEntries, 4 );
  PakFile.read( startOfFileNames, 4 );
  PakFile.read( startOfData, 4 );
  PakFile.read( sizeOfIndex, 4 );
  PakFile.read( sizeOfFileEntries, 4 );
  PakFile.read( sizeOfFileNames, 4 );
  PakFile.read( sizeOfData, 4 );

  //In MI2 NameOffs is broken - luckily filenames are stored in the same order as the entries in the file records
  //Parse the filenames and find the index of the file we're searching for


  //Read FileNames and see if any match
  CurrNameOffset := 0;
  SearchFileIndex := -1;
  for I := 0 to sizeOfFileEntries div sizeOfFileRecord - 1 do
  begin
    PakFile.Position  := startOfFileNames + currNameOffset;
    TempStr :=  PChar( ReadString(PakFile, 255) );
    inc(currNameOffset, length(TempStr) + 1); //+1 because each filename is null terminated

    if (SearchFileIndex <> -1) and (SearchFileIndex <> -1) then
        break;

    if  TempStr = FileName then
      SearchFileIndex := i
  end;


  if SearchFileIndex = -1 then //file not found
  begin
    Output( strErrorNotInPAK );
    result := false;
    exit;
  end;

  //Get offset + size of files
  PakFile.Position  := startOfFileEntries + (sizeOfFileRecord * SearchFileIndex);
  PakFile.Read(SearchFileOffset, 4);
  Inc(SearchFileOffset, startOfData);
  PakFile.Seek(4, soFromCurrent);
  PakFile.Read(SearchFileSize, 4);


  //Dump the file to the memory stream
  PakFile.Position := SearchFileOffset;
  MemStream.CopyFrom(PakFile, SearchFileSize);
  MemStream.Position := 0;
  Result := true;

end;

procedure TfrmMain.ExtractTempResourcesAndInitIniFile;
var
  rStream: TResourceStream;
begin
  rStream := TResourceStream.Create(hInstance, 'MI_MUSIC', RT_RCDATA);
  try
    rStream.SaveToFile( IncludeTrailingPathDelimiter( Getwindowstempfolder)  + 'MI_MUSIC.ini' );
    IniFile := TMemIniFile.Create(IncludeTrailingPathDelimiter( Getwindowstempfolder)  + 'MI_MUSIC.ini');
  finally
    rStream.Free;
  end;
end;

procedure TfrmMain.DeleteTempResources;
begin
  if IniFile <> nil then IniFile.Free;

  DeleteFile( IncludeTrailingPathDelimiter( Getwindowstempfolder)  + 'MI_MUSIC.ini');
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  frmMain.Caption := strAppName + ' ' + strAppVersion;
  Output(strAppName);
  Output('Version ' + strAppVersion);
  Output(strAuthor);
  Output(strWebsite);
  Output('');

  ExtractTempResourcesAndInitIniFile;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  DeleteTempResources;
end;

function TfrmMain.GetInfoFromAWBFile(MemStream: TMemoryStream;
  var Offsets: TList<Integer>; var StringList: TStringList): boolean;
var
  TempDword, NoFiles, NameOffs: Dword;
  i: integer;
begin
  result := false;
  MemStream.Position := 4;

  MemStream.Read(NoFiles, 4);

  if NoFiles = 0 then
  begin
    Output(strNoFilesIs0);
    exit;
  end;

  MemStream.Read(TempDWord, 4);
  MemStream.Seek(TempDword -4, soFromCurrent);

  //Parse the files
  for I := 0 to NoFiles - 1 do
  begin

    MemStream.Read(NameOffs, 4);
    MemStream.Read(TempDword, 4); //offset to start of 52 byte header relative to start of file
    MemStream.Seek(4, sofromcurrent); //some other offset
    Offsets.Add(TempDword);

    //Not efficent but just get the name now
    TempDword := MemStream.Position; //store current position
    MemStream.Seek(NameOffs - 12, soFromCurrent); //seek to the filename
    StringList.Add( ReadNullTerminatedString(MemStream, 24) ); //Read the string

    MemStream.Position := TempDword; //seek back
  end;

  result :=true;
end;

procedure TfrmMain.DumpOggsFromStream(SourceStream: TMemoryStream; DestDir: string; FileNames: TStringList; FileOffsets: TList<Integer>);
var
  OggSize: Dword;
  SaveFile: TFileStream;
  i, GameNo: integer;
  newFileName, NewDestDir: string;
begin
  SourceStream.Position := 0;

  for I := 0 to FileNames.Count - 1 do
  begin
    //Work out from the old filename if file is from MI1 or 2
    GameNo := strtoint(FileNames[i][3]);
    case GameNo of
      1: NewDestDir := IncludeTrailingPathDelimiter(DestDir) + 'Monkey Island 1';
      2: NewDestDir := IncludeTrailingPathDelimiter(DestDir) + 'Monkey Island 2';
    end;
    ForceDirectories(NewDestDir);

    NewFileName := IniFile.ReadString( FileNames[i] + '.ogg', 'NewFileName', FileNames[i] + '.ogg' );
    SourceStream.Position := FileOffsets[i] + 48; //just before filesize
    SourceStream.Read(OggSize, 4);
    SaveFile:=TFileStream.Create(IncludeTrailingPathDelimiter(NewDestDir) +  NewFileName , fmOpenWrite or fmCreate);
    try
      SaveFile.CopyFrom(SourceStream, OggSize);
    finally
      SaveFile.Free;
    end;

    TagMusic( IncludeTrailingPathDelimiter(NewDestDir) + NewFileName, FileNames[i] + '.ogg' ); //Need sectionname to match old name in ini
  end;
end;

procedure TfrmMain.TagMusic(FileName, SectionName: string);
begin
  TagEditor1.FileName := Ansistring(FileName);
                                                 //WHAT about album artist?
  if TagEditor1.Valid = false then exit;

  TagEditor1.Title    := IniFile.ReadString( SectionName, 'Title', ''  );
  TagEditor1.Album    := IniFile.ReadString( SectionName, 'Album', ''  );
  TagEditor1.Artist   := IniFile.ReadString( SectionName, 'Artist', ''  );
  TagEditor1.Genre    := IniFile.ReadString( SectionName, 'Genre', ''  );
  TagEditor1.Track    := IniFile.ReadString( SectionName, 'TrackNo', ''  );
  TagEditor1.Year     := IniFile.ReadString( SectionName, 'Year', ''  );
  TagEditor1.Comment  := strCommentTag + strAppVersion + ' ' + strWebsite;

  TagEditor1.Save;

  {if CoverArt <> '' then
  begin
    SourceCover := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName) + strSoundTrackDir) + Coverart;
    if FileExists(SourceCover) then
      FileCopy( SourceCover, ExtractFilePath(FileName) + Coverart, false);
  end; }

end;

end.
