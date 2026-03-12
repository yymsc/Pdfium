program PdfiumExample;

{
  Beispielprogramm für TPdfDocument
  Zeigt: Öffnen, Anhänge extrahieren, PDF nach TIFF konvertieren
}

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  PdfiumApi,
  PdfiumDoc;

procedure DemoOeffnenUndInfo(const PdfPfad: string);
var
  Doc : TPdfDocument;
  I   : Integer;
  W, H: Double;
begin
  Doc := TPdfDocument.Create;
  try
    Doc.Open(PdfPfad);
    Writeln('Datei:     ', Doc.FileName);
    Writeln('Seiten:    ', Doc.PageCount);
    Writeln('Anhänge:   ', Doc.GetAttachmentCount);
    Writeln;
    for I := 0 to Doc.PageCount - 1 do
    begin
      Doc.GetPageSize(I, W, H);
      Writeln(Format('  Seite %d: %.1f x %.1f pt  (%.1f x %.1f mm)',
        [I + 1, W, H, W * 25.4 / 72, H * 25.4 / 72]));
    end;
  finally
    Doc.Free;
  end;
end;

procedure DemoAnhaengeExtrahieren(const PdfPfad, ZielOrdner: string);
var
  Doc  : TPdfDocument;
  Atts : TPdfAttachmentArray;
  I    : Integer;
begin
  Doc := TPdfDocument.Create;
  try
    Doc.Open(PdfPfad);
    Atts := Doc.GetAllAttachments;
    if Length(Atts) = 0 then
    begin
      Writeln('Keine Anhänge vorhanden.');
      Exit;
    end;
    Writeln('Extrahiere ', Length(Atts), ' Anhang/Anhänge nach: ', ZielOrdner);
    for I := 0 to High(Atts) do
      Writeln('  [', I, '] ', Atts[I].Name, '  (', Length(Atts[I].Data), ' Bytes)');

    Doc.ExtractAllAttachments(ZielOrdner);
    Writeln('Fertig.');
  finally
    Doc.Free;
  end;
end;

procedure DemoNachTiffKonvertieren(const PdfPfad, TiffPfad: string);
var
  Doc  : TPdfDocument;
  Opts : TTiffOptions;
begin
  Doc := TPdfDocument.Create;
  try
    Doc.Open(PdfPfad);

    Opts             := DefaultTiffOptions;
    Opts.DPI         := 200;
    Opts.Compression := tcPackBits;  // tcNone / tcLZW / tcPackBits
    Opts.Grayscale   := False;
    Opts.ScaleFactor := 200 / 72;    // 200 DPI bei 72 pt/Zoll

    Writeln('Konvertiere ', Doc.PageCount, ' Seite(n) nach TIFF: ', TiffPfad);
    Doc.SaveToTiff(TiffPfad, Opts);
    Writeln('Fertig.');
  finally
    Doc.Free;
  end;
end;

procedure DemoEineSeiteTiff(const PdfPfad, TiffPfad: string; Seite: Integer);
var
  Doc  : TPdfDocument;
  Opts : TTiffOptions;
begin
  Doc := TPdfDocument.Create;
  try
    Doc.Open(PdfPfad);
    Opts := DefaultTiffOptions;
    Opts.DPI         := 150;
    Opts.Compression := tcLZW;
    Opts.ScaleFactor := 150 / 72;
    Doc.SavePageToTiff(TiffPfad, Seite, Opts);
    Writeln('Seite ', Seite + 1, ' gespeichert als: ', TiffPfad);
  finally
    Doc.Free;
  end;
end;

// ---------------------------------------------------------------------------
begin
  try
    if ParamCount < 1 then
    begin
      Writeln('Verwendung:');
      Writeln('  PdfiumExample <pdf-datei>');
      Writeln('  PdfiumExample <pdf-datei> --tiff <ausgabe.tiff>');
      Writeln('  PdfiumExample <pdf-datei> --extract <ziel-ordner>');
      Halt(1);
    end;

    var PdfPfad := ParamStr(1);

    if ParamCount >= 3 then
    begin
      if ParamStr(2) = '--tiff' then
        DemoNachTiffKonvertieren(PdfPfad, ParamStr(3))
      else if ParamStr(2) = '--extract' then
        DemoAnhaengeExtrahieren(PdfPfad, ParamStr(3));
    end
    else
      DemoOeffnenUndInfo(PdfPfad);

  except
    on E: EPdfiumError do
    begin
      Writeln('PDFium-Fehler: ', E.Message);
      Halt(2);
    end;
    on E: Exception do
    begin
      Writeln('Fehler: ', E.Message);
      Halt(2);
    end;
  end;
end.
