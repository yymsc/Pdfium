unit PdfiumDoc;

{
  TPdfDocument – Öffnen von PDF-Dateien mit PDFium
    - Seiten rendern
    - Anhänge (Embedded Files) extrahieren
    - PDF nach TIFF konvertieren (MultiPage, unkomprimiert oder LZW/PackBits)

  Plattformen: Windows (Win32/Win64) und Linux (x64)
  Delphi 13+, kein Interface-Einsatz
}

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  PdfiumApi;

// ============================================================
//  Hilfstypen
// ============================================================

type
  EPdfiumError = class(Exception);

  TPdfAttachment = record
    Name : string;       // Dateiname des Anhangs
    Data : TBytes;       // Rohdaten
  end;

  TPdfAttachmentArray = array of TPdfAttachment;

  TTiffCompression = (
    tcNone,       // unkomprimiert (TIFF Typ 1)
    tcPackBits,   // PackBits RLE  (TIFF Typ 32773)
    tcLZW         // LZW           (TIFF Typ 5)
  );

  TTiffOptions = record
    DPI         : Integer;          // Auflösung in DPI (Standard: 150)
    Compression : TTiffCompression; // Komprimierung
    Grayscale   : Boolean;          // Graustufen statt Farbe
    ScaleFactor : Double;           // Zoomfaktor (Standard: 1.0)
  end;

// ============================================================
//  TPdfDocument
// ============================================================

  TPdfDocument = class
  private
    FDocument : FPDF_DOCUMENT;
    FFileName : string;
    FPassword : string;
    FLoaded   : Boolean;

    procedure CheckLoaded;
    function  GetPageCount: Integer;
    function  GetLastErrorText: string;

    // TIFF-Hilfsmethoden
    procedure WriteTiffIFD(Stream: TStream; PageIndex, PageCount,
                           ImageWidth, ImageHeight, DPI: Integer;
                           Compression: TTiffCompression; Grayscale: Boolean;
                           DataOffset: Cardinal; DataSize: Cardinal;
                           NextIFDOffset: Cardinal);
    function  CompressPackBits(const Input: TBytes): TBytes;
    function  CompressLZW(const Input: TBytes): TBytes;

    function  RenderPageToBGRBytes(PageIndex: Integer;
                                   out Width, Height: Integer;
                                   ScaleFactor: Double;
                                   Grayscale: Boolean): TBytes;
  public
    constructor Create;
    destructor  Destroy; override;

    // Dokument öffnen / schließen
    procedure Open(const AFileName: string; const APassword: string = '');
    procedure OpenFromStream(Stream: TStream; const APassword: string = '');
    procedure Close;

    // Seiten
    property PageCount: Integer read GetPageCount;
    procedure GetPageSize(PageIndex: Integer; out WidthPt, HeightPt: Double);

    // Anhänge extrahieren
    function  GetAttachmentCount: Integer;
    function  GetAttachment(Index: Integer): TPdfAttachment;
    function  GetAllAttachments: TPdfAttachmentArray;
    procedure ExtractAttachment(Index: Integer; const DestPath: string);
    procedure ExtractAllAttachments(const DestFolder: string);

    // TIFF-Export
    procedure SaveToTiff(const TiffFile: string; const Options: TTiffOptions); overload;
    procedure SaveToTiff(const TiffFile: string); overload;
    procedure SavePageToTiff(const TiffFile: string; PageIndex: Integer;
                             const Options: TTiffOptions);

    property FileName: string  read FFileName;
    property Loaded  : Boolean read FLoaded;
  end;

// Standardoptionen erzeugen
function DefaultTiffOptions: TTiffOptions;

// PDFium-Bibliothek explizit initialisieren / freigeben
procedure PdfiumInit;
procedure PdfiumDone;

implementation

// ============================================================
//  Bibliotheks-Lebenszyklus
// ============================================================

var
  GInitCount: Integer = 0;

procedure PdfiumInit;
begin
  if GInitCount = 0 then
    FPDF_InitLibrary;
  Inc(GInitCount);
end;

procedure PdfiumDone;
begin
  Dec(GInitCount);
  if GInitCount <= 0 then
  begin
    GInitCount := 0;
    FPDF_DestroyLibrary;
  end;
end;

// ============================================================
//  Hilfsfunktionen
// ============================================================

function DefaultTiffOptions: TTiffOptions;
begin
  Result.DPI         := 150;
  Result.Compression := tcPackBits;
  Result.Grayscale   := False;
  // ScaleFactor = DPI / 72, damit die gerenderten Pixel zu den
  // DPI-Metadaten im TIFF-Header passen (1 PDF-Point = 1/72 Inch)
  Result.ScaleFactor := Result.DPI / 72.0;
end;

// Liest einen PDFium-UTF-16LE-Puffer und liefert einen Delphi-String
function Utf16BufToString(GetFunc: TFunc<Pointer, LongWord, LongWord>): string;
var
  Len : LongWord;
  Buf : TBytes;
begin
  Len := GetFunc(nil, 0);
  if Len = 0 then Exit('');
  SetLength(Buf, Len);
  GetFunc(Pointer(Buf), Len);
  // letztes Null-Word entfernen, falls vorhanden
  if (Len >= 2) and (Buf[Len-2] = 0) and (Buf[Len-1] = 0) then
    SetLength(Buf, Len - 2);
  Result := TEncoding.Unicode.GetString(Buf);
end;

// ============================================================
//  Little-Endian-Schreibhilfen für TIFF
// ============================================================

procedure WriteWord(S: TStream; V: Word);
begin
  S.WriteBuffer(V, 2);
end;

procedure WriteDWord(S: TStream; V: Cardinal);
begin
  S.WriteBuffer(V, 4);
end;

// Schreibt ein TIFF-IFD-Tag (12 Byte)
procedure WriteTiffTag(S: TStream; Tag, DataType: Word; Count, Value: Cardinal);
begin
  WriteWord(S, Tag);
  WriteWord(S, DataType);
  WriteDWord(S, Count);
  WriteDWord(S, Value);
end;

// ============================================================
//  TPdfDocument – private Methoden
// ============================================================

procedure TPdfDocument.CheckLoaded;
begin
  if not FLoaded then
    raise EPdfiumError.Create('Kein PDF-Dokument geöffnet.');
end;

function TPdfDocument.GetPageCount: Integer;
begin
  CheckLoaded;
  Result := FPDF_GetPageCount(FDocument);
end;

function TPdfDocument.GetLastErrorText: string;
begin
  case FPDF_GetLastError of
    FPDF_ERR_SUCCESS  : Result := 'Kein Fehler';
    FPDF_ERR_FILE     : Result := 'Datei nicht gefunden oder nicht lesbar';
    FPDF_ERR_FORMAT   : Result := 'Ungültiges PDF-Format';
    FPDF_ERR_PASSWORD : Result := 'Falsches Passwort';
    FPDF_ERR_SECURITY : Result := 'Sicherheitseinschränkung';
    FPDF_ERR_PAGE     : Result := 'Seitenfehler';
  else
    Result := 'Unbekannter Fehler (' + IntToStr(FPDF_GetLastError) + ')';
  end;
end;

// ---------------------------------------------------------------------------
//  Seite in BGR-Bytes rendern
// ---------------------------------------------------------------------------
function TPdfDocument.RenderPageToBGRBytes(PageIndex: Integer;
  out Width, Height: Integer; ScaleFactor: Double; Grayscale: Boolean): TBytes;
var
  Page    : FPDF_PAGE;
  Bitmap  : FPDF_BITMAP;
  Flags   : Integer;
  Stride  : Integer;
  Src     : PByte;
  SrcRow  : PByte;
  Row, Col: Integer;
begin
  Result := nil;
  Page := FPDF_LoadPage(FDocument, PageIndex);
  if Page = nil then
    raise EPdfiumError.CreateFmt('Seite %d konnte nicht geladen werden.', [PageIndex]);
  try
    Width  := Round(FPDF_GetPageWidthF(Page)  * ScaleFactor);
    Height := Round(FPDF_GetPageHeightF(Page) * ScaleFactor);
    if Width  < 1 then Width  := 1;
    if Height < 1 then Height := 1;

    // PDFium rendert intern immer mit BGRx (4 Bytes/Pixel).
    // FPDFBitmap_BGR ist zwar spezifiziert, aber der interne Stride
    // entspricht in manchen Versionen trotzdem Width*4 – das erzeugt
    // horizontal verschobene Zeilen im Ergebnis.
    // Lösung: immer BGRx anfordern und das Padding-Byte danach
    // pixelweise manuell entfernen. Stride ist dann immer = Width*4.
    Bitmap := FPDFBitmap_Create(Width, Height, 0);  // BGRx, alpha=0
    if Bitmap = nil then
      raise EPdfiumError.Create('FPDFBitmap_Create fehlgeschlagen.');
    try
      FPDFBitmap_FillRect(Bitmap, 0, 0, Width, Height, $FFFFFFFF);

      Flags := FPDF_PRINTING;
      if Grayscale then
        Flags := Flags or FPDF_GRAYSCALE;

      FPDF_RenderPageBitmap(Bitmap, Page, 0, 0, Width, Height, 0, Flags);

      Stride := FPDFBitmap_GetStride(Bitmap);  // = Width*4 für BGRx
      Src    := FPDFBitmap_GetBuffer(Bitmap);

      if Grayscale then
      begin
        // Bei FPDF_GRAYSCALE gilt B = G = R; wir nehmen Byte 0 (= B)
        SetLength(Result, Width * Height);
        for Row := 0 to Height - 1 do
        begin
          SrcRow := Src + Row * Stride;
          for Col := 0 to Width - 1 do
            Result[Row * Width + Col] := SrcRow[Col * 4]; // B = G = R
        end;
      end
      else
      begin
        // BGRx → BGR: x-Byte (Byte 3) überspringen
        SetLength(Result, Width * Height * 3);
        for Row := 0 to Height - 1 do
        begin
          SrcRow := Src + Row * Stride;
          for Col := 0 to Width - 1 do
          begin
            Result[Row * Width * 3 + Col * 3 + 0] := SrcRow[Col * 4 + 0]; // B
            Result[Row * Width * 3 + Col * 3 + 1] := SrcRow[Col * 4 + 1]; // G
            Result[Row * Width * 3 + Col * 3 + 2] := SrcRow[Col * 4 + 2]; // R
          end;
        end;
      end;
    finally
      FPDFBitmap_Destroy(Bitmap);
    end;
  finally
    FPDF_ClosePage(Page);
  end;
end;

// ============================================================
//  TIFF-Komprimierung: PackBits
// ============================================================
function TPdfDocument.CompressPackBits(const Input: TBytes): TBytes;
var
  InPos, OutPos : Integer;
  RunStart      : Integer;
  RunLen        : Integer;
  Literal       : array[0..127] of Byte;
  LitCount      : Integer;

  procedure FlushLiterals;
  var i: Integer;
  begin
    if LitCount = 0 then Exit;
    SetLength(Result, OutPos + 1 + LitCount);
    Result[OutPos] := Byte(LitCount - 1);
    Inc(OutPos);
    for i := 0 to LitCount - 1 do
    begin
      Result[OutPos] := Literal[i];
      Inc(OutPos);
    end;
    LitCount := 0;
  end;

begin
  SetLength(Result, Length(Input) * 2 + 8);
  InPos   := 0;
  OutPos  := 0;
  LitCount := 0;

  while InPos < Length(Input) do
  begin
    // Lauflänge prüfen
    RunStart := InPos;
    RunLen   := 1;
    while (InPos + RunLen < Length(Input)) and
          (RunLen < 128) and
          (Input[InPos + RunLen] = Input[RunStart]) do
      Inc(RunLen);

    if RunLen >= 2 then
    begin
      FlushLiterals;
      SetLength(Result, OutPos + 2);
      Result[OutPos]     := Byte(-(RunLen - 1) + 256);  // negatives Byte
      Result[OutPos + 1] := Input[RunStart];
      Inc(OutPos, 2);
      Inc(InPos, RunLen);
    end
    else
    begin
      if LitCount = 128 then
        FlushLiterals;
      Literal[LitCount] := Input[InPos];
      Inc(LitCount);
      Inc(InPos);
    end;
  end;
  FlushLiterals;
  SetLength(Result, OutPos);
end;

// ============================================================
//  TIFF-Komprimierung: LZW (GIF/TIFF-Variante, 9-12 Bit)
// ============================================================
function TPdfDocument.CompressLZW(const Input: TBytes): TBytes;
const
  CLEAR_CODE   = 256;
  EOI_CODE     = 257;
  MAX_CODE     = 4095;
type
  TLZWEntry = record
    Prefix : Integer;
    Suffix : Byte;
  end;
var
  Table    : array[0..MAX_CODE] of TLZWEntry;
  TableSize: Integer;
  BitWidth : Integer;

  OutBuf   : TBytes;
  OutPos   : Integer;
  BitBuf   : Cardinal;
  BitCount : Integer;

  procedure WriteCode(Code: Integer);
  var Mask: Cardinal;
  begin
    BitBuf   := (BitBuf shl BitWidth) or Cardinal(Code);
    Inc(BitCount, BitWidth);
    while BitCount >= 8 do
    begin
      Dec(BitCount, 8);
      if OutPos >= Length(OutBuf) then
        SetLength(OutBuf, Length(OutBuf) + 4096);
      OutBuf[OutPos] := (BitBuf shr BitCount) and $FF;
      Inc(OutPos);
    end;
    // Tabellenbreite anpassen
    if (Code <> CLEAR_CODE) and (Code <> EOI_CODE) then
    begin
      if TableSize > (1 shl BitWidth) - 1 then
        if BitWidth < 12 then Inc(BitWidth);
    end;
  end;

  procedure ResetTable;
  var i: Integer;
  begin
    for i := 0 to 255 do
    begin
      Table[i].Prefix := -1;
      Table[i].Suffix := Byte(i);
    end;
    TableSize := 258;
    BitWidth  := 9;
  end;

  function FindCode(Prefix: Integer; Suffix: Byte): Integer;
  var i: Integer;
  begin
    for i := 258 to TableSize - 1 do
      if (Table[i].Prefix = Prefix) and (Table[i].Suffix = Suffix) then
        Exit(i);
    Result := -1;
  end;

var
  InPos   : Integer;
  Current : Integer;
  Next    : Byte;
  Found   : Integer;
begin
  SetLength(OutBuf, Length(Input) + 4096);
  OutPos   := 0;
  BitBuf   := 0;
  BitCount := 0;

  ResetTable;
  WriteCode(CLEAR_CODE);

  if Length(Input) = 0 then
  begin
    WriteCode(EOI_CODE);
    SetLength(OutBuf, OutPos);
    Result := OutBuf;
    Exit;
  end;

  Current := Integer(Input[0]);
  InPos   := 1;

  while InPos < Length(Input) do
  begin
    Next  := Input[InPos];
    Found := FindCode(Current, Next);
    if Found >= 0 then
      Current := Found
    else
    begin
      WriteCode(Current);
      if TableSize <= MAX_CODE then
      begin
        Table[TableSize].Prefix := Current;
        Table[TableSize].Suffix := Next;
        Inc(TableSize);
      end
      else
      begin
        WriteCode(CLEAR_CODE);
        ResetTable;
      end;
      Current := Integer(Next);
    end;
    Inc(InPos);
  end;
  WriteCode(Current);
  WriteCode(EOI_CODE);

  // verbleibende Bits auffüllen
  if BitCount > 0 then
  begin
    if OutPos >= Length(OutBuf) then
      SetLength(OutBuf, Length(OutBuf) + 1);
    OutBuf[OutPos] := (BitBuf shl (8 - BitCount)) and $FF;
    Inc(OutPos);
  end;

  SetLength(OutBuf, OutPos);
  Result := OutBuf;
end;

// ============================================================
//  TIFF IFD schreiben
// ============================================================

const
  // TIFF Tag IDs
  TIFF_IMAGEWIDTH      = 256;
  TIFF_IMAGELENGTH     = 257;
  TIFF_BITSPERSAMPLE   = 258;
  TIFF_COMPRESSION     = 259;
  TIFF_PHOTOMETRIC     = 262;
  TIFF_STRIPOFFSETS    = 273;
  TIFF_SAMPLESPERPIXEL = 277;
  TIFF_ROWSPERSTRIP    = 278;
  TIFF_STRIPBYTECOUNTS = 279;
  TIFF_XRESOLUTION     = 282;
  TIFF_YRESOLUTION     = 283;
  TIFF_RESOLUTIONUNIT  = 296;
  TIFF_PAGENUMBER      = 297;

  // TIFF Datentypen
  TIFF_SHORT  = 3;
  TIFF_LONG   = 4;
  TIFF_RATIONAL = 5;

  // Photometric
  TIFF_PHOTO_MINISBLACK = 1;
  TIFF_PHOTO_RGB        = 2;

  // Komprimierung
  TIFF_COMPR_NONE      = 1;
  TIFF_COMPR_LZW       = 5;
  TIFF_COMPR_PACKBITS  = 32773;

procedure TPdfDocument.WriteTiffIFD(Stream: TStream; PageIndex, PageCount,
  ImageWidth, ImageHeight, DPI: Integer; Compression: TTiffCompression;
  Grayscale: Boolean; DataOffset: Cardinal; DataSize: Cardinal;
  NextIFDOffset: Cardinal);
{
  IFD-Layout (Little-Endian):
    2 Bytes  TagCount
    TagCount × 12 Bytes  Tag-Einträge
    4 Bytes  NextIFDOffset
    [6 Bytes  BitsPerSample 8/8/8  – nur Farbe]
    8 Bytes  XResolution  RATIONAL
    8 Bytes  YResolution  RATIONAL

  Inline-Daten liegen unmittelbar nach dem NextIFD-DWORD.
  IFDEnd zeigt auf den ersten Byte der Inline-Daten.
}
var
  TagCount      : Word;
  ComprValue    : Cardinal;
  PhotoValue    : Cardinal;
  SamplesPerPix : Cardinal;
  IFDEnd        : Cardinal;  // Offset des ersten Inline-Datenbytes
  BPSOffset     : Cardinal;  // Offset BitsPerSample-Extra  (nur Farbe)
  XResOffset    : Cardinal;  // Offset XResolution RATIONAL
  YResOffset    : Cardinal;  // Offset YResolution RATIONAL
begin
  // TagCount:
  //   12 feste Tags + 1 PageNumber (nur wenn Mehrseiten-TIFF)
  TagCount := 12;
  if PageCount > 1 then Inc(TagCount);

  // IFDEnd = Byte unmittelbar nach IFD-Block (2 + TagCount*12 + 4)
  IFDEnd := Cardinal(Stream.Position) + 2 + TagCount * 12 + 4;

  // Inline-Datenoffsets
  if Grayscale then
  begin
    // Kein BitsPerSample-Extra (1 × SHORT passt in den Tag-Value)
    XResOffset := IFDEnd;
    YResOffset := IFDEnd + 8;
  end
  else
  begin
    BPSOffset  := IFDEnd;        // 3 × SHORT = 6 Bytes
    XResOffset := IFDEnd + 6;
    YResOffset := IFDEnd + 14;
  end;

  case Compression of
    tcNone : ComprValue := TIFF_COMPR_NONE;
    tcLZW  : ComprValue := TIFF_COMPR_LZW;
  else
    ComprValue := TIFF_COMPR_PACKBITS;
  end;

  if Grayscale then
  begin
    PhotoValue    := TIFF_PHOTO_MINISBLACK;
    SamplesPerPix := 1;
  end
  else
  begin
    PhotoValue    := TIFF_PHOTO_RGB;
    SamplesPerPix := 3;
  end;

  // Tags schreiben – Tags MÜSSEN aufsteigend nach Tag-ID sortiert sein
  WriteWord(Stream, TagCount);
  WriteTiffTag(Stream, TIFF_IMAGEWIDTH,      TIFF_LONG,     1, Cardinal(ImageWidth));
  WriteTiffTag(Stream, TIFF_IMAGELENGTH,     TIFF_LONG,     1, Cardinal(ImageHeight));
  if Grayscale then
    WriteTiffTag(Stream, TIFF_BITSPERSAMPLE, TIFF_SHORT,    1, 8)
  else
    WriteTiffTag(Stream, TIFF_BITSPERSAMPLE, TIFF_SHORT,    3, BPSOffset);
  WriteTiffTag(Stream, TIFF_COMPRESSION,     TIFF_SHORT,    1, ComprValue);
  WriteTiffTag(Stream, TIFF_PHOTOMETRIC,     TIFF_SHORT,    1, PhotoValue);
  WriteTiffTag(Stream, TIFF_STRIPOFFSETS,    TIFF_LONG,     1, DataOffset);
  WriteTiffTag(Stream, TIFF_SAMPLESPERPIXEL, TIFF_SHORT,    1, SamplesPerPix);
  WriteTiffTag(Stream, TIFF_ROWSPERSTRIP,    TIFF_LONG,     1, Cardinal(ImageHeight));
  WriteTiffTag(Stream, TIFF_STRIPBYTECOUNTS, TIFF_LONG,     1, DataSize);
  WriteTiffTag(Stream, TIFF_XRESOLUTION,     TIFF_RATIONAL, 1, XResOffset);
  WriteTiffTag(Stream, TIFF_YRESOLUTION,     TIFF_RATIONAL, 1, YResOffset);
  WriteTiffTag(Stream, TIFF_RESOLUTIONUNIT,  TIFF_SHORT,    1, 2); // 2 = Inch
  if PageCount > 1 then
    WriteTiffTag(Stream, TIFF_PAGENUMBER,    TIFF_SHORT,    2,
                 Cardinal(PageIndex) or (Cardinal(PageCount) shl 16));

  WriteDWord(Stream, NextIFDOffset);

  // Inline-Daten: BitsPerSample (nur Farbe: 3 × 8-Bit)
  if not Grayscale then
  begin
    WriteWord(Stream, 8);
    WriteWord(Stream, 8);
    WriteWord(Stream, 8);
  end;

  // XResolution RATIONAL  (DPI / 1)
  WriteDWord(Stream, Cardinal(DPI));
  WriteDWord(Stream, 1);
  // YResolution RATIONAL  (DPI / 1)
  WriteDWord(Stream, Cardinal(DPI));
  WriteDWord(Stream, 1);
end;

// ============================================================
//  TPdfDocument – public Methoden
// ============================================================

constructor TPdfDocument.Create;
begin
  inherited;
  FDocument := nil;
  FLoaded   := False;
  PdfiumInit;
end;

destructor TPdfDocument.Destroy;
begin
  Close;
  PdfiumDone;
  inherited;
end;

procedure TPdfDocument.Open(const AFileName: string; const APassword: string);
var
  Pwd: PAnsiChar;
begin
  Close;
  FFileName := AFileName;
  FPassword := APassword;
  if APassword <> '' then
    Pwd := PAnsiChar(AnsiString(APassword))
  else
    Pwd := nil;

  FDocument := FPDF_LoadDocument(PAnsiChar(AnsiString(AFileName)), Pwd);
  if FDocument = nil then
    raise EPdfiumError.CreateFmt(
      'PDF konnte nicht geöffnet werden: %s'#13#10'Datei: %s',
      [GetLastErrorText, AFileName]);
  FLoaded := True;
end;

procedure TPdfDocument.OpenFromStream(Stream: TStream; const APassword: string);
var
  Buf : TBytes;
  Pwd : PAnsiChar;
begin
  Close;
  FFileName := '<Stream>';
  FPassword := APassword;
  SetLength(Buf, Stream.Size);
  Stream.Position := 0;
  Stream.ReadBuffer(Buf[0], Length(Buf));

  if APassword <> '' then
    Pwd := PAnsiChar(AnsiString(APassword))
  else
    Pwd := nil;

  FDocument := FPDF_LoadMemDocument(Pointer(Buf), Length(Buf), Pwd);
  if FDocument = nil then
    raise EPdfiumError.CreateFmt(
      'PDF aus Stream konnte nicht geöffnet werden: %s', [GetLastErrorText]);
  FLoaded := True;
end;

procedure TPdfDocument.Close;
begin
  if FLoaded and (FDocument <> nil) then
  begin
    FPDF_CloseDocument(FDocument);
    FDocument := nil;
  end;
  FLoaded := False;
end;

procedure TPdfDocument.GetPageSize(PageIndex: Integer;
  out WidthPt, HeightPt: Double);
var
  Page: FPDF_PAGE;
begin
  CheckLoaded;
  Page := FPDF_LoadPage(FDocument, PageIndex);
  if Page = nil then
    raise EPdfiumError.CreateFmt('Seite %d nicht ladbar.', [PageIndex]);
  try
    WidthPt  := FPDF_GetPageWidthF(Page);
    HeightPt := FPDF_GetPageHeightF(Page);
  finally
    FPDF_ClosePage(Page);
  end;
end;

// ============================================================
//  Anhänge
// ============================================================

function TPdfDocument.GetAttachmentCount: Integer;
begin
  CheckLoaded;
  Result := FPDFDoc_GetAttachmentCount(FDocument);
end;

function TPdfDocument.GetAttachment(Index: Integer): TPdfAttachment;
var
  Att    : FPDF_ATTACHMENT;
  BufLen : LongWord;
  NameBuf: TBytes;
  DataBuf: TBytes;
begin
  CheckLoaded;
  Att := FPDFDoc_GetAttachment(FDocument, Index);
  if Att = nil then
    raise EPdfiumError.CreateFmt('Anhang %d nicht gefunden.', [Index]);

  // Name lesen (UTF-16LE)
  BufLen := FPDFAttachment_GetName(Att, nil, 0);
  if BufLen > 0 then
  begin
    SetLength(NameBuf, BufLen);
    FPDFAttachment_GetName(Att, Pointer(NameBuf), BufLen);
    // letztes Null-Word abschneiden
    if (BufLen >= 2) and (NameBuf[BufLen-2] = 0) and (NameBuf[BufLen-1] = 0) then
      SetLength(NameBuf, BufLen - 2);
    Result.Name := TEncoding.Unicode.GetString(NameBuf);
  end
  else
    Result.Name := 'Anhang_' + IntToStr(Index);

  // Daten lesen
  BufLen := 0;
  if FPDFAttachment_GetFile(Att, nil, 0, @BufLen) = 0 then
    raise EPdfiumError.CreateFmt('Anhangdaten %d nicht lesbar.', [Index]);

  SetLength(DataBuf, BufLen);
  if BufLen > 0 then
  begin
    if FPDFAttachment_GetFile(Att, Pointer(DataBuf), BufLen, @BufLen) = 0 then
      raise EPdfiumError.CreateFmt('Anhangdaten %d konnten nicht geladen werden.', [Index]);
  end;
  Result.Data := DataBuf;
end;

function TPdfDocument.GetAllAttachments: TPdfAttachmentArray;
var
  i, Count: Integer;
begin
  Count := GetAttachmentCount;
  SetLength(Result, Count);
  for i := 0 to Count - 1 do
    Result[i] := GetAttachment(i);
end;

procedure TPdfDocument.ExtractAttachment(Index: Integer; const DestPath: string);
var
  Att : TPdfAttachment;
  FS  : TFileStream;
begin
  Att := GetAttachment(Index);
  FS  := TFileStream.Create(DestPath, fmCreate);
  try
    if Length(Att.Data) > 0 then
      FS.WriteBuffer(Att.Data[0], Length(Att.Data));
  finally
    FS.Free;
  end;
end;

procedure TPdfDocument.ExtractAllAttachments(const DestFolder: string);
var
  i     : Integer;
  Count : Integer;
  Att   : TPdfAttachment;
  Path  : string;
  SafeName: string;
  C     : Char;
begin
  Count := GetAttachmentCount;
  if Count = 0 then Exit;

  ForceDirectories(DestFolder);

  for i := 0 to Count - 1 do
  begin
    Att := GetAttachment(i);
    // Dateinamen bereinigen
    SafeName := '';
    for C in Att.Name do
      if CharInSet(C, ['a'..'z','A'..'Z','0'..'9','_','-','.',' ']) then
        SafeName := SafeName + C
      else
        SafeName := SafeName + '_';
    if SafeName = '' then
      SafeName := 'Anhang_' + IntToStr(i);

    Path := IncludeTrailingPathDelimiter(DestFolder) + SafeName;
    ExtractAttachment(i, Path);
  end;
end;

// ============================================================
//  TIFF-Export
// ============================================================

procedure TPdfDocument.SavePageToTiff(const TiffFile: string;
  PageIndex: Integer; const Options: TTiffOptions);
{
  Einzelseite-TIFF, kein PageNumber-Tag (TagCount = 12).

  IFD-Größen (TagCount=12):
    Farbe:  2 + 12*12 + 4 + 6 (BPS) + 16 (2 RATIONALs) = 172 Bytes
    Grau:   2 + 12*12 + 4 + 0       + 16               = 166 Bytes
  DataOffset = 8 (Header) + IFDSize
}
const
  IFD_SIZE_COLOR_SINGLE = 2 + 12 * 12 + 4 + 6 + 16; // 172
  IFD_SIZE_GRAY_SINGLE  = 2 + 12 * 12 + 4 + 16;      // 166
var
  MS         : TMemoryStream;
  PixData    : TBytes;
  CompData   : TBytes;
  PW, PH     : Integer;
  Scale      : Double;
  DataOffset : Cardinal;
  i          : Integer;
  Tmp        : Byte;
begin
  CheckLoaded;

  Scale := Options.ScaleFactor;
  if Scale <= 0 then Scale := 1.0;

  PixData := RenderPageToBGRBytes(PageIndex, PW, PH, Scale, Options.Grayscale);

  // BGR → RGB umwandeln (TIFF erwartet RGB)
  if not Options.Grayscale then
  begin
    i := 0;
    while i < Length(PixData) - 2 do
    begin
      Tmp            := PixData[i];
      PixData[i]     := PixData[i + 2];
      PixData[i + 2] := Tmp;
      Inc(i, 3);
    end;
  end;

  case Options.Compression of
    tcPackBits : CompData := CompressPackBits(PixData);
    tcLZW      : CompData := CompressLZW(PixData);
  else
    CompData := PixData;
  end;

  // DataOffset korrekt vor dem Schreiben berechnen
  if Options.Grayscale then
    DataOffset := 8 + IFD_SIZE_GRAY_SINGLE
  else
    DataOffset := 8 + IFD_SIZE_COLOR_SINGLE;

  MS := TMemoryStream.Create;
  try
    // TIFF-Header (8 Bytes): Byte-Order 'II' (LE), Magic 42, IFD-Offset
    // WICHTIG: WriteBuffer(AnsiString('II'), 2) wäre FALSCH – Delphi würde
    // den 4/8-Byte-Heap-Pointer der AnsiString-Variable übergeben, nicht
    // die Zeichen. WriteWord($4949) schreibt exakt die Bytes $49 $49 = 'II'.
    WriteWord(MS, $4949);   // 'II' = Little-Endian-Marker
    WriteWord(MS, 42);      // TIFF Magic Number
    WriteDWord(MS, 8);      // IFD beginnt unmittelbar nach dem Header

    WriteTiffIFD(MS, 0, 1 {single page}, PW, PH, Options.DPI,
                 Options.Compression, Options.Grayscale,
                 DataOffset, Cardinal(Length(CompData)),
                 0 {kein nächstes IFD});

    // Sicherstellen, dass Stream-Position mit DataOffset übereinstimmt
    Assert(Cardinal(MS.Size) = DataOffset,
           Format('TIFF DataOffset-Mismatch: erwartet %d, tatsächlich %d',
                  [DataOffset, MS.Size]));

    MS.WriteBuffer(CompData[0], Length(CompData));
    MS.SaveToFile(TiffFile);
  finally
    MS.Free;
  end;
end;

procedure TPdfDocument.SaveToTiff(const TiffFile: string;
  const Options: TTiffOptions);
var
  Count     : Integer;
  PageIdx   : Integer;
  Scale     : Double;
  PW, PH    : Integer;
  PixData   : TBytes;
  CompData  : TBytes;
  // Für Multi-Page TIFF sammeln wir alle Bild-Blöcke
  PageWidths  : array of Integer;
  PageHeights : array of Integer;
  PageData    : array of TBytes;
  MS          : TMemoryStream;
  IFDOffsets  : array of Cardinal;
  DataOffsets : array of Cardinal;
  I           : Integer;
  Cur         : Cardinal;
begin
  CheckLoaded;
  Count := GetPageCount;
  if Count = 0 then
    raise EPdfiumError.Create('Das Dokument enthält keine Seiten.');

  if Count = 1 then
  begin
    SavePageToTiff(TiffFile, 0, Options);
    Exit;
  end;

  Scale := Options.ScaleFactor;
  if Scale <= 0 then Scale := 1.0;

  SetLength(PageWidths,  Count);
  SetLength(PageHeights, Count);
  SetLength(PageData,    Count);
  SetLength(IFDOffsets,  Count);
  SetLength(DataOffsets, Count);

  // alle Seiten rendern und komprimieren
  for PageIdx := 0 to Count - 1 do
  begin
    PixData := RenderPageToBGRBytes(PageIdx, PW, PH, Scale, Options.Grayscale);
    PageWidths[PageIdx]  := PW;
    PageHeights[PageIdx] := PH;

    // BGR → RGB
    if not Options.Grayscale then
    begin
      var SwapI := 0;
      while SwapI < Length(PixData) - 2 do
      begin
        var SwapTmp     := PixData[SwapI];
        PixData[SwapI]  := PixData[SwapI + 2];
        PixData[SwapI + 2] := SwapTmp;
        Inc(SwapI, 3);
      end;
    end;

    case Options.Compression of
      tcPackBits : PageData[PageIdx] := CompressPackBits(PixData);
      tcLZW      : PageData[PageIdx] := CompressLZW(PixData);
    else
      PageData[PageIdx] := PixData;
    end;
  end;

  // Layout berechnen:
  // TIFF-Header = 8 Bytes
  // Für jede Seite: IFD-Block (berechnet in WriteTiffIFD) + Bilddaten
  // Wir berechnen Offsets in zwei Schritten.

  // IFD-Größen für Mehrseiten-TIFF (TagCount=13, inkl. PageNumber):
  //   Farbe: 2 + 13*12 + 4 + 6 (BPS) + 16 (2 RATIONALs) = 184
  //   Grau:  2 + 13*12 + 4 + 0       + 16               = 178
  const IFD_SIZE_COLOR_MULTI = 2 + 13 * 12 + 4 + 6 + 16; // 184
  const IFD_SIZE_GRAY_MULTI  = 2 + 13 * 12 + 4 + 16;     // 178

  var IFDSize: Integer;
  if Options.Grayscale then
    IFDSize := IFD_SIZE_GRAY_MULTI
  else
    IFDSize := IFD_SIZE_COLOR_MULTI;

  Cur := 8; // nach TIFF-Header
  for I := 0 to Count - 1 do
  begin
    IFDOffsets[I] := Cur;
    Inc(Cur, IFDSize);
    DataOffsets[I] := Cur;
    Inc(Cur, Length(PageData[I]));
  end;

  MS := TMemoryStream.Create;
  try
    // TIFF-Header (siehe Kommentar in SavePageToTiff)
    WriteWord(MS, $4949);   // 'II' = Little-Endian-Marker
    WriteWord(MS, 42);      // TIFF Magic Number
    WriteDWord(MS, IFDOffsets[0]);

    for I := 0 to Count - 1 do
    begin
      var NextIFD: Cardinal := 0;
      if I < Count - 1 then
        NextIFD := IFDOffsets[I + 1];

      WriteTiffIFD(MS, I, Count,
                   PageWidths[I], PageHeights[I],
                   Options.DPI, Options.Compression, Options.Grayscale,
                   DataOffsets[I], Cardinal(Length(PageData[I])),
                   NextIFD);

      // Bilddaten dieser Seite
      if Length(PageData[I]) > 0 then
        MS.WriteBuffer(PageData[I][0], Length(PageData[I]));
    end;

    MS.SaveToFile(TiffFile);
  finally
    MS.Free;
  end;
end;

procedure TPdfDocument.SaveToTiff(const TiffFile: string);
begin
  SaveToTiff(TiffFile, DefaultTiffOptions);
end;

end.
