{
******************************************************
  Monkey Island Music Extractor
  Copyright (c) 2011 Bgbennyboy
  Http://quick.mixnmojo.com
******************************************************
}

program MonkeyIsland_MusicExtractor;

{$R *.dres}

uses
  Forms,
  formMain in 'formMain.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Monkey Island Music Extractor';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
