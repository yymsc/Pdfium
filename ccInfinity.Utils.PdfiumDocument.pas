// ==================================================================================
//
//   CLARC(R) INFINITY(TM)
//   Copyright(C) CTO Balzuweit GmbH
//   All rights reserved
//
// ----------------------------------------------------------------------------------
// File...............: ccInfinity.Utils.PdfiumDocument
// Info...............: CLARC INFINITY PdfiumDocument
// ----------------------------------------------------------------------------------
// Author.............: Matthias Schneider
// Changed............: 21.04.2026
// ----------------------------------------------------------------------------------
// 12.03.2026 - 1.0.0 : (MSC) Creation
// 17.03.2026 - 1.1.0 : TIFF-Export (Einzel-/Multipage, LZW/PackBits/None)
// 21.04.2026 - 1.2.0 : WebP-Import/Export (Lossy/Lossless, Einzel-/Multipage)
// ==================================================================================
unit ccInfinity.Utils.PdfiumDocument;

{$INCLUDE ccInfinity.inc}

// ==================================================================================
interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Classes,
  System.Types,
  System.Math,

  {$IFDEF MSWINDOWS}
    Winapi.Windows,
  {$ENDIF}

  ccInfinity.Types.Core,
  ccInfinity.Types.Exceptions,
  ccInfinity.Types.Exceptions.Core,
  ccInfinity.Types.Messages;

// ==================================================================================
  const
// ----------------------------------------------------------------------------------
{$IFDEF MSWINDOWS}
  PDFIUM_LIB = 'pdfium.dll';
  WEBP_LIB   = 'libwebp.dll';
{$ELSE}
  PDFIUM_LIB = 'libpdfium.so';
  WEBP_LIB   = 'libwebp.so';
{$ENDIF}

  // Render-Flags
  FPDF_ANNOT                    = $01;
  FPDF_LCD_TEXT                 = $02;
  FPDF_NO_NATIVETEXT            = $04;
  FPDF_GRAYSCALE                = $08;
  FPDF_DEBUG_INFO               = $80;
  FPDF_NO_CATCH                 = $100;
  FPDF_RENDER_LIMITEDIMAGECACHE = $200;
  FPDF_RENDER_FORCEHALFTONE     = $400;
  FPDF_PRINTING                 = $800;
  FPDF_REVERSE_BYTE_ORDER       = $10;

  // Bitmap-Formate
  FPDFBitmap_Unknown = 0;
  FPDFBitmap_Gray    = 1;
  FPDFBitmap_BGR     = 2;
  FPDFBitmap_BGRx    = 3;
  FPDFBitmap_BGRA    = 4;

  // Fehler-Codes
  FPDF_ERR_SUCCESS  = 0;
  FPDF_ERR_UNKNOWN  = 1;
  FPDF_ERR_FILE     = 2;
  FPDF_ERR_FORMAT   = 3;
  FPDF_ERR_PASSWORD = 4;
  FPDF_ERR_SECURITY = 5;
  FPDF_ERR_PAGE     = 6;

  // Save-Flags für FPDF_SaveAsCopy / FPDF_SaveWithVersion
  FPDF_INCREMENTAL     = 1;
  FPDF_NO_INCREMENTAL  = 2;
  FPDF_REMOVE_SECURITY = 3;

// ==================================================================================
type

  FPDF_DOCUMENT   = Pointer;
  FPDF_PAGE       = Pointer;
  FPDF_BITMAP     = Pointer;
  FPDF_ATTACHMENT = Pointer;

  PFPDF_DOCUMENT   = ^FPDF_DOCUMENT;
  PFPDF_PAGE       = ^FPDF_PAGE;
  PFPDF_BITMAP     = ^FPDF_BITMAP;
  PFPDF_ATTACHMENT = ^FPDF_ATTACHMENT;

  // ---------------------------------------------------------------------------
  // FPDF_FILEWRITE - Callback-Struktur fuer FPDF_SaveAsCopy.
  //
  // PDFium uebergibt als erstes Argument des Callbacks (pThis) einen Zeiger
  // auf diesen Record selbst. Wir haengen UserStream direkt dahinter, damit
  // der Callback ohne globale Variablen an den TStream kommt.
  //
  // NICHT packed - normales Alignment sichert korrekte Pointer-Ausrichtung.
  // PDFium liest nur: version (Offset 0) + WriteBlock (Offset 4 oder 8).
  // ---------------------------------------------------------------------------
  TFPDF_WriteBlock = function(pThis : Pointer; pData : Pointer; size : UInt32) : Integer; cdecl;
  TFPDF_FILEWRITE = record
    version    : Integer;           // Muss = 1 sein
    WriteBlock : TFPDF_WriteBlock;  // Callback-Zeiger
    UserStream : Pointer;           // Eigene Erweiterung: TStream-Zeiger
  end;

  PFPDF_FILEWRITE = ^TFPDF_FILEWRITE;

  // ------------------------------------------------------------------
  // Seiteninformation
  // ------------------------------------------------------------------
  TccPdfPageInfo = record
    Index    : Integer;
    WidthPt  : Single;   // Breite  in PDF-Punkten (1/72 Zoll)
    HeightPt : Single;   // Höhe    in PDF-Punkten
    WidthMM  : Single;   // Breite  in Millimetern
    HeightMM : Single;   // Höhe    in Millimetern
  end;

  // ------------------------------------------------------------------
  // Anhang-Information
  // ------------------------------------------------------------------
  TccPdfAttachmentInfo = record
    Index : Integer;
    Name  : String;
    Size  : Int64;   // Größe in Bytes (-1 = unbekannt)
  end;

  // ------------------------------------------------------------------
  // TIFF-Kompression
  // ------------------------------------------------------------------
  TccTiffCompression = (
    tcNone,         // Keine Kompression (Tag 1)
    tcLZW,          // LZW-Kompression  (Tag 5)
    tcPackBits      // PackBits / RLE   (Tag 32773)
  );

  // ------------------------------------------------------------------
  // Optionen für BMP → PDF Konvertierung
  // ------------------------------------------------------------------
  TccBmpToPdfFitMode = (
    bfmStretchToPage,    // BMP auf volle Seitengröße strecken
    bfmKeepAspectRatio,  // Seitenverhältnis beibehalten, zentriert
    bfmOriginalSize      // Originalgröße (1 Pixel = 1/DPI Zoll)
  );

  // ==================================================================================
  TccBmpToPdfOptions = record
    PageWidthMM   : Double;       // Seitenbreite  in mm (0 = aus BMP ableiten)
    PageHeightMM  : Double;       // Seitenhöhe    in mm (0 = aus BMP ableiten)
    MarginMM      : Double;       // Rand rundum   in mm (Standard: 0)
    FitMode       : TccBmpToPdfFitMode;
    SourceDPI     : Integer;      // DPI des Quell-BMP (wichtig für OriginalSize, Standard: 96)
    class function Default : TccBmpToPdfOptions; static;
    class function A4Portrait : TccBmpToPdfOptions; static;
    class function A4Landscape : TccBmpToPdfOptions; static;
  end;

  // ------------------------------------------------------------------
  // WebP-Kompressionsmodus
  // ------------------------------------------------------------------
  TccWebpMode = (
    wmLossy,       // verlustbehaftete Kompression (Quality 0..100)
    wmLossless     // verlustfreie Kompression (Quality wird ignoriert)
  );

  // ------------------------------------------------------------------
  // Optionen für WebP-Export (PDF → WebP)
  // ------------------------------------------------------------------
  TccWebpOptions = record
    Mode    : TccWebpMode;  // Standard: wmLossy
    Quality : Single;       // 0..100 – nur bei wmLossy relevant (Standard: 80)
    class function Default  : TccWebpOptions; static;
    class function Lossless : TccWebpOptions; static;
    class function Lossy(AQuality : Single) : TccWebpOptions; static;
  end;

// ----------------------------------------------------------------------------------
// Pdfium helper class
// ----------------------------------------------------------------------------------
  TccPdfiumLibHelper = class sealed
  {$REGION 'Internal declarations'}
  private class var
    FInitialized : Boolean;
    FModule      : HMODULE;
    FLock        : TCriticalSection;
  private class var
    {$REGION 'Pdfium API declation'}
    // Init / Destroy
    FPDF_InitLibrary    : procedure(); cdecl;
    FPDF_DestroyLibrary : procedure(); cdecl;

    // Dokument
    FPDF_LoadDocument    : function(file_path: PAnsiChar; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
    FPDF_LoadMemDocument : function(data_buf: Pointer; size: Integer; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
    FPDF_CloseDocument   : procedure(document: FPDF_DOCUMENT); cdecl;
    FPDF_GetLastError    : function(): UInt32; cdecl;
    FPDF_GetPageCount    : function(document: FPDF_DOCUMENT): Integer; cdecl;
    FPDF_GetMetaText     : function(document: FPDF_DOCUMENT; tag: PAnsiChar; buffer: Pointer; buflen: UInt32): UInt32; cdecl;

    // Seiten
    FPDF_LoadPage       : function(document: FPDF_DOCUMENT; page_index: Integer): FPDF_PAGE; cdecl;
    FPDF_ClosePage      : procedure(page: FPDF_PAGE); cdecl;
    FPDF_GetPageWidthF  : function(page: FPDF_PAGE): Single; cdecl;
    FPDF_GetPageHeightF : function(page: FPDF_PAGE): Single; cdecl;

    // Bitmap
    FPDFBitmap_Create     : function(width, height, alpha: Integer): FPDF_BITMAP; cdecl;
    FPDFBitmap_CreateEx   : function(width, height, format: Integer; first_scan: Pointer; stride: Integer): FPDF_BITMAP; cdecl;
    FPDFBitmap_FillRect   : procedure(bitmap: FPDF_BITMAP; left, top, width, height: Integer; color: UInt32); cdecl;
    FPDFBitmap_GetBuffer  : function(bitmap: FPDF_BITMAP): Pointer; cdecl;
    FPDFBitmap_GetWidth   : function(bitmap: FPDF_BITMAP): Integer; cdecl;
    FPDFBitmap_GetHeight  : function(bitmap: FPDF_BITMAP): Integer; cdecl;
    FPDFBitmap_GetStride  : function(bitmap: FPDF_BITMAP): Integer; cdecl;
    FPDFBitmap_Destroy    : procedure(bitmap: FPDF_BITMAP); cdecl;
    FPDF_RenderPageBitmap : procedure(bitmap: FPDF_BITMAP; page: FPDF_PAGE; start_x, start_y, size_x, size_y: Integer; rotate, flags: Integer); cdecl;

    // Attachments (Eingebettete Dateien)
    FPDFDoc_GetAttachmentCount : function(document: FPDF_DOCUMENT): Integer; cdecl;
    FPDFDoc_GetAttachment      : function(document: FPDF_DOCUMENT; index: Integer): FPDF_ATTACHMENT; cdecl;
    FPDFAttachment_GetName     : function(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: UInt32): UInt32; cdecl;
    FPDFAttachment_GetFile     : function(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: UInt32; out_buflen: PUInt32): LongBool; cdecl;

    // Dokument erstellen / speichern
    FPDF_CreateNewDocument : function(): FPDF_DOCUMENT; cdecl;
    FPDF_SaveAsCopy        : function(document: FPDF_DOCUMENT; pFileWrite: PFPDF_FILEWRITE; flags: UInt32): LongBool; cdecl;
    FPDF_SaveWithVersion   : function(document: FPDF_DOCUMENT; pFileWrite: PFPDF_FILEWRITE; flags: UInt32; fileVersion: Integer): LongBool; cdecl;

    // Seiten importieren
    FPDF_ImportPages : function(dest_doc: FPDF_DOCUMENT; src_doc: FPDF_DOCUMENT; pagerange: PAnsiChar; index: Integer): LongBool; cdecl;

    // Seiten erstellen
    FPDFPage_New     : function(document: FPDF_DOCUMENT; page_index: Integer; width, height: Double): FPDF_PAGE; cdecl;
    FPDFPage_Delete  : procedure(document: FPDF_DOCUMENT; page_index: Integer); cdecl;

    // Seiten-Objekte / Generierung
    FPDFPage_GenerateContent : function(page: FPDF_PAGE): LongBool; cdecl;
    FPDFPage_InsertObject    : procedure(page: FPDF_PAGE; page_obj: Pointer); cdecl;

    // Image-Objekte
    FPDFPageObj_NewImageObj    : function(document: FPDF_DOCUMENT): Pointer; cdecl;
    FPDFImageObj_LoadJpegFile  : function(pages: Pointer; nCount: Integer; image_object: Pointer; fileAccess: Pointer): LongBool; cdecl;
    FPDFImageObj_LoadJpegFileInline : function(pages: Pointer; nCount: Integer; image_object: Pointer; fileAccess: Pointer): LongBool; cdecl;
    FPDFImageObj_SetBitmap     : function(pages: Pointer; nCount: Integer; image_object: Pointer; bitmap: FPDF_BITMAP): LongBool; cdecl;
    FPDFImageObj_GetBitmap     : function(image_object: Pointer): FPDF_BITMAP; cdecl;
    FPDFPageObj_Transform      : procedure(page_object: Pointer; a, b, c, d, e, f: Double); cdecl;
    FPDFPageObj_SetBlendMode   : procedure(page_object: Pointer; blend_mode: PAnsiChar); cdecl;
    {$ENDREGION}  private
    class procedure Finalize;
  public
    class constructor Create;
    class destructor Destroy;
  {$ENDREGION}
  public
    class function TryInitialize : Boolean;
  end;

// ----------------------------------------------------------------------------------
// Webp helper class – dynamischer Loader für libwebp (Encode + Decode)
// ----------------------------------------------------------------------------------
  TccWebpLibHelper = class sealed
  {$REGION 'Internal declarations'}
  private class var
    FInitialized : Boolean;
    FModule      : HMODULE;
    FLock        : TCriticalSection;
  private class var
    {$REGION 'libwebp API declaration'}
    // --- Decode ---
    WebPGetInfo        : function(data: Pointer; data_size: NativeUInt;
                          width: PInteger; height: PInteger): Integer; cdecl;
    WebPDecodeBGRAInto : function(data: Pointer; data_size: NativeUInt;
                          output_buffer: Pointer; output_buffer_size: NativeUInt;
                          output_stride: Integer): Pointer; cdecl;

    // --- Encode ---
    WebPEncodeBGRA         : function(bgra: Pointer; width, height, stride: Integer;
                              quality_factor: Single; output: PPointer): NativeUInt; cdecl;
    WebPEncodeLosslessBGRA : function(bgra: Pointer; width, height, stride: Integer;
                              output: PPointer): NativeUInt; cdecl;

    // --- Speicher-Freigabe für von libwebp alloziiertes Encode-Output ---
    WebPFree : procedure(ptr: Pointer); cdecl;
    {$ENDREGION}
  private
    class procedure Finalize;
  public
    class constructor Create;
    class destructor Destroy;
  {$ENDREGION}
  public
    class function TryInitialize : Boolean;
  end;

// ==================================================================================
  TccPdfiumDocument = class
  {$REGION 'Internal declarations'}
  private
    FDocument  : FPDF_DOCUMENT;
    FFileName  : String;
    FLoaded    : Boolean;
    FPageCount : Integer;
    FStreamBuffer : TMemoryStream; // haelt den Puffer fuer FPDF_LoadMemDocument am Leben
    FLock : TCriticalSection;   // ← neu: schützt PDFium-Zugriff auf FDocument

    procedure CheckLoaded;
    procedure CheckPageIndex(AIndex : Integer);
    function  RenderPage(AStream : TStream; APage : FPDF_PAGE; ADpi : Integer) : Boolean;
    function  BuildBmpStream(AStream : TStream; ABitmapData : Pointer; AWidth, AHeight, AStride : Integer; ADPI: Integer) : Boolean;

    // TIFF-Hilfs-Funktionen
    function  RenderPageToRaw(APage : FPDF_PAGE; ADpi : Integer;
                out AWidth, AHeight : Integer; out ABuf : TBytes) : Boolean;
    class procedure WriteTiffToStream(AStream : TStream;
                const APages : array of TBytes;
                const AWidths, AHeights : array of Integer;
                ADpi : Integer; ACompression : TccTiffCompression;
                AGrayscale : Boolean); static;
    // Schreibt TIFF aus bereits komprimierten Puffern (für parallele Kompression)
    class procedure WriteTiffPrecompressedToStream(AStream : TStream;
                const ACompPages : array of TBytes;
                const AWidths, AHeights : array of Integer;
                const ASamplesPerPx, ABitsPerSample, APhotometric : array of Word;
                ADpi : Integer; ACompression : TccTiffCompression); static;

    // BMP-Lese-Hilfsfunktionen (für BMP → PDF)
    class function  ReadBmpInfo(AStream : TStream; out AWidth, AHeight, ABitCount : Integer; out ADataOffset : Int64) : Boolean; static;
    class function  BmpStreamToPdfiumBitmap(AStream : TStream) : FPDF_BITMAP; static;
    class procedure SaveDocumentToStream(ADocument : FPDF_DOCUMENT; AStream : TStream); static;
    class procedure SaveDocumentToFile(ADocument : FPDF_DOCUMENT; const AFileName : String); static;

    // TIFF-Lese-Hilfsfunktion (für TIFF → PDF)
    class function  TiffStreamToPdfiumBitmap(AStream : TStream; APageIndex : Integer;
                      out AImgW, AImgH, ADPI : Integer) : FPDF_BITMAP; static;

    // WebP-Lese-Hilfsfunktion (für WebP → PDF)
    //  Liefert einen BGRA-PDFium-Bitmap zurück; Caller muss FPDFBitmap_Destroy aufrufen.
    class function  WebpStreamToPdfiumBitmap(AStream : TStream;
                      out AImgW, AImgH : Integer) : FPDF_BITMAP; static;
    private class var
      FParallelDepth : Integer;   // ← neu: verhindert verschachtelte TParallel.For
  {$ENDREGION}
  public
    constructor Create;
    destructor  Destroy; override;

    // ---- Laden / Schließen -------------------------------------------
    procedure OpenFile(const AFileName : String; const APassword : String = '');
    procedure OpenStream(AStream : TStream; const APassword : String = '');
    procedure Close;

    // ---- Dokument-Eigenschaften --------------------------------------
    property Loaded    : Boolean read FLoaded;
    property FileName  : String  read FFileName;
    property PageCount : Integer read FPageCount;

    // PDF-Metadaten auslesen
    // ATag: 'Title', 'Author', 'Subject', 'Keywords', 'Creator', 'Producer',
    //       'CreationDate', 'ModDate'
    // Gibt den Wert als String zurück, oder '' wenn nicht vorhanden.
    function GetMetaText(const ATag : String) : String;

    // ---- Seiten ------------------------------------------------------
    function GetPageInfo(APageIndex : Integer) : TccPdfPageInfo;

    // Seite rendern → BMP als TMemoryStream
    function RenderPageToBmp(AStream : TStream; APageIndex : Integer; ADpi : Integer) : Boolean;

    // Seite direkt als BMP-Datei speichern
    procedure SavePageAsBmpFile(APageIndex : Integer; const AFileName : String; ADpi : Integer = 200);

    // Alle Seiten als BMP in ein Verzeichnis exportieren
    procedure ExportAllPagesToBmp(const ADirectory : String; const ABaseName : String = 'page'; ADpi : Integer = 200);

    // ---- PDF → WebP Export --------------------------------------------
    // Kein zusätzliches Setup nötig. Benötigt libwebp.dll im Suchpfad.

    // Einzelne Seite als WebP in Stream rendern
    function  RenderPageToWebp(AStream : TStream; APageIndex : Integer;
                ADpi : Integer; const AOptions : TccWebpOptions) : Boolean; overload;
    function  RenderPageToWebp(AStream : TStream; APageIndex : Integer;
                ADpi : Integer = 200) : Boolean; overload;

    // Einzelne Seite als WebP-Datei speichern
    procedure SavePageAsWebpFile(APageIndex : Integer; const AFileName : String;
                ADpi : Integer; const AOptions : TccWebpOptions); overload;
    procedure SavePageAsWebpFile(APageIndex : Integer; const AFileName : String;
                ADpi : Integer = 200); overload;

    // Alle Seiten als einzelne WebP-Dateien in ein Verzeichnis exportieren
    procedure ExportAllPagesToWebp(const ADirectory : String;
                const ABaseName : String; ADpi : Integer;
                const AOptions : TccWebpOptions); overload;
    procedure ExportAllPagesToWebp(const ADirectory : String;
                const ABaseName : String = 'page';
                ADpi : Integer = 200); overload;

    // ---- TIFF-Export ---------------------------------------------------
    // Einzelne Seite als TIFF in Stream rendern
    function  RenderPageToTiff(AStream : TStream; APageIndex : Integer;
                ADpi : Integer = 200;
                ACompression : TccTiffCompression = tcLZW;
                AGrayscale : Boolean = False) : Boolean;

    // Einzelne Seite als TIFF-Datei speichern
    procedure SavePageAsTiffFile(APageIndex : Integer; const AFileName : String;
                ADpi : Integer = 200;
                ACompression : TccTiffCompression = tcLZW;
                AGrayscale : Boolean = False);

    // Alle Seiten als mehrseitiges TIFF (Multi-Page TIFF) in Stream schreiben
    procedure SaveAllPagesAsTiff(AStream : TStream;
                ADpi : Integer = 200;
                ACompression : TccTiffCompression = tcLZW;
                AGrayscale : Boolean = False);

    // Alle Seiten als mehrseitiges TIFF (Multi-Page TIFF) als Datei speichern
    procedure SaveAllPagesAsTiffFile(const AFileName : String;
                ADpi : Integer = 200;
                ACompression : TccTiffCompression = tcLZW;
                AGrayscale : Boolean = False);

    // Alle Seiten als einzelne TIFF-Dateien in ein Verzeichnis exportieren
    procedure ExportAllPagesToTiff(const ADirectory : String;
                const ABaseName : String = 'page';
                ADpi : Integer = 200;
                ACompression : TccTiffCompression = tcLZW;
                AGrayscale : Boolean = False);

    // ---- Anhänge (Attachments) ----------------------------------------
    function AttachmentCount : Integer;
    function GetAttachmentInfo(AIndex : Integer) : TccPdfAttachmentInfo;

    // Anhang in Stream extrahieren
    function  ExtractAttachmentToStream(AStream : TStream; AIndex : Integer) : Boolean;

    // Anhang direkt in Datei speichern
    //  ADirectory = '' → aktuelles Verzeichnis
    //  Gibt den vollständigen Pfad zur gespeicherten Datei zurück
    function  ExtractAttachmentToFile(AIndex : Integer; const ADirectory : String = '') : String;

    // Alle Anhänge extrahieren
    procedure ExtractAllAttachments(const ADirectory : String = '');

    // ---- BMP → PDF Konvertierung (statische Klassenmethoden) ----------
    // Kein geladenes Dokument nötig – arbeiten eigenständig.

    // Eine einzelne BMP-Datei → PDF-Datei
    class procedure BmpToPdf(const ABmpFile : String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure BmpToPdf(const ABmpFile : String; const APdfFile : String); overload; static;

    // Eine BMP-Datei → PDF als TMemoryStream (Caller gibt frei)
    class function  BmpToPdf(const ABmpFile : String; const AOptions : TccBmpToPdfOptions) : TMemoryStream; overload; static;
    class function  BmpToPdf(const ABmpFile : String) : TMemoryStream; overload; static;

    // BMP aus Stream → PDF als TMemoryStream
    class function  BmpToPdf(ABmpStream : TStream; const AOptions : TccBmpToPdfOptions) : TMemoryStream; overload; static;
    class function  BmpToPdf(ABmpStream : TStream) : TMemoryStream; overload; static;

    // Mehrere BMP-Dateien → ein mehrseitiges PDF
    // ABmpFiles: Liste von BMP-Dateipfaden, werden als aufeinanderfolgende Seiten eingefügt
    class procedure BmpToPdf(const ABmpFiles : array of String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure BmpToPdf(const ABmpFiles : array of String; const APdfFile : String); overload; static;


    // ---- WebP → PDF Konvertierung (statische Klassenmethoden) ---------
    // Kein geladenes Dokument nötig – arbeiten eigenständig.
    // Unterstützt Lossy- und Lossless-WebP mit und ohne Alpha-Kanal.

    // Eine einzelne WebP-Datei → PDF-Datei
    class procedure WebpToPdf(const AWebpFile : String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure WebpToPdf(const AWebpFile : String; const APdfFile : String); overload; static;

    // Eine WebP-Datei → PDF als TMemoryStream (Caller gibt frei)
    class function  WebpToPdf(const AWebpFile : String; const AOptions : TccBmpToPdfOptions) : TMemoryStream; overload; static;
    class function  WebpToPdf(const AWebpFile : String) : TMemoryStream; overload; static;

    // WebP aus Stream → PDF als TMemoryStream
    class function  WebpToPdf(AWebpStream : TStream; const AOptions : TccBmpToPdfOptions) : TMemoryStream; overload; static;
    class function  WebpToPdf(AWebpStream : TStream) : TMemoryStream; overload; static;

    // Mehrere WebP-Dateien → ein mehrseitiges PDF
    class procedure WebpToPdf(const AWebpFiles : array of String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure WebpToPdf(const AWebpFiles : array of String; const APdfFile : String); overload; static;


    // ---- TIFF → PDF Konvertierung (statische Klassenmethoden) ---------
    // Kein geladenes Dokument nötig – arbeiten eigenständig.
    // Unterstützt Single- und Multi-Page-TIFFs.
    // Kompression: Unkomprimiert, LZW, PackBits (1/8/24/32 Bit).

    // Eine TIFF-Datei → PDF-Datei (alle TIFF-Seiten → PDF-Seiten)
    class procedure TiffToPdf(const ATiffFile : String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure TiffToPdf(const ATiffFile : String; const APdfFile : String); overload; static;

    // Eine TIFF-Datei → PDF als TMemoryStream (Caller gibt frei)
    class function  TiffToPdf(const ATiffFile : String; ATarget : TStream; const AOptions : TccBmpToPdfOptions) : Integer; overload; static;
    class function  TiffToPdf(const ATiffFile : String; ATarget : TStream) : Integer; overload; static;

    // TIFF aus Stream → PDF als TMemoryStream
    class function  TiffToPdf(ASource, ATarget : TStream; const AOptions : TccBmpToPdfOptions) : Integer; overload; static;
    class function  TiffToPdf(ATiffStream : TStream; ATarget : TStream) : Integer; overload; static;

    // Mehrere TIFF-Dateien → ein mehrseitiges PDF
    class procedure TiffToPdf(const ATiffFiles : array of String; const APdfFile : String; const AOptions : TccBmpToPdfOptions); overload; static;
    class procedure TiffToPdf(const ATiffFiles : array of String; const APdfFile : String); overload; static;

    // Mehrere TIFF-Dateien → ein mehrseitiges PDF als TMemoryStream
    class function  TiffToPdf(const ATiffFiles : array of String; ATarget : TStream; const AOptions : TccBmpToPdfOptions) : Boolean; overload; static;
    class function  TiffToPdf(const ATiffFiles : array of String; ATarget : TStream) : Boolean overload; static;

    // Mehrere TIFF-Streams → ein mehrseitiges PDF als TMemoryStream
    class function  TiffToPdf(const ATiffStreams : array of TStream; ATarget : TStream; const AOptions : TccBmpToPdfOptions) : Boolean; overload; static;
    class function  TiffToPdf(const ATiffStreams : array of TStream; ATarget : TStream) : Boolean; overload; static;

    // ---- PDF zusammenfügen (Merge) ----------------------------------------
    // Kein geladenes Dokument nötig – arbeiten eigenständig.
    // Verwendet FPDF_ImportPages um Seiten seitengetreu zu übernehmen.

    // Mehrere PDF-Streams → zusammengefügtes PDF in Ziel-Stream
    class procedure MergePdf(const ASources : array of TStream; ATarget : TStream); overload; static;

    // Mehrere PDF-Dateien → zusammengefügtes PDF in Ziel-Stream
    class procedure MergePdf(const AFiles : array of String; ATarget : TStream); overload; static;

    // Mehrere PDF-Dateien → zusammengefügtes PDF als Datei
    class procedure MergePdf(const AFiles : array of String; const ATargetFile : String); overload; static;

    // Mehrere PDF-Streams → zusammengefügtes PDF als TMemoryStream (Caller gibt frei)
    class function  MergePdfToStream(const ASources : array of TStream) : TMemoryStream; static;
  end;

implementation

uses
  System.Threading;   // TParallel – für parallele Seiten-Kompression

// ==================════════════════════════════════════════
//  BMP-Hilfs-Strukturen (plattformunabhängig, inline geschrieben)
// ==================================================================================
type
  TccBmpFileHeader = packed record
    bfType      : Word;    // 'BM'
    bfSize      : Integer;
    bfReserved1 : Word;
    bfReserved2 : Word;
    bfOffBits   : Integer;
  end;

  TccBmpInfoHeader = packed record
    biSize          : Integer;
    biWidth         : Integer;
    biHeight        : Integer;  // negativ = Top-Down
    biPlanes        : Word;
    biBitCount      : Word;
    biCompression   : Integer;
    biSizeImage     : Integer;
    biXPelsPerMeter : Integer;
    biYPelsPerMeter : Integer;
    biClrUsed       : Integer;
    biClrImportant  : Integer;
  end;

// ==================================================================================
{ TccPdfiumDocument }

// ----------------------------------------------------------------------------------
procedure TccPdfiumDocument.CheckLoaded;
begin
  if not FLoaded
    then raise EccException.Create(CCI_MSG_ERR_PIU_NODOCLOADED);
end;

procedure TccPdfiumDocument.CheckPageIndex(AIndex : Integer);
begin
  CheckLoaded;
  if (AIndex < 0) or (AIndex >= FPageCount)
    then raise EccException.Create(CCI_MSG_ERR_PIU_PAGEINDEXINVALID.Format([AIndex, FPageCount - 1]));
end;

// ---------------------------------------------------------------------------
//  BuildBmpStream
//  Erzeugt einen vollständigen BMP-Stream aus rohen BGR(x)-Pixeldaten.
//  PDFium liefert immer BGR (24-bit reicht, BGRx = 32-bit mit Padding).
//  Wir schreiben ein sauberes 24-Bit-BMP.
// ---------------------------------------------------------------------------
function TccPdfiumDocument.BuildBmpStream(AStream : TStream; ABitmapData : Pointer; AWidth, AHeight, AStride : Integer; ADPI: Integer) : Boolean;
var
  FileHdr        : TccBmpFileHeader;
  InfoHdr        : TccBmpInfoHeader;
  BmpStride      : Integer;
  SrcRow         : PByte;
  DstRow         : array of Byte;
  x,y            : Integer;
  OrgPos         : Integer;
  PixelsPerMeter : Integer;
begin
  // BMP-Zeilen müssen auf 4 Byte ausgerichtet sein
  BmpStride := ((AWidth * 3) + 3) and (not 3);

  // Exakte Umrechnung: 1 Zoll = 0.0254 Meter  =>  ppm = DPI / 0.0254
  // Beispiele: 72 DPI -> 2835, 96 DPI -> 3780, 150 DPI -> 5906, 300 DPI -> 11811
  PixelsPerMeter := Round(ADPI / 0.0254);

  FillChar(FileHdr, SizeOf(FileHdr), 0);
  FileHdr.bfType    := $4D42; // 'BM'
  FileHdr.bfOffBits := SizeOf(TccBmpFileHeader) + SizeOf(TccBmpInfoHeader);
  FileHdr.bfSize    := UInt32(FileHdr.bfOffBits) + UInt32(BmpStride * AHeight);

  FillChar(InfoHdr, SizeOf(InfoHdr), 0);
  InfoHdr.biSize          := SizeOf(TccBmpInfoHeader);
  InfoHdr.biWidth         := AWidth;
  InfoHdr.biHeight        := -AHeight; // negativ = Top-Down (PDFium ist Top-Down)
  InfoHdr.biPlanes        := 1;
  InfoHdr.biBitCount      := 24;
  InfoHdr.biCompression   := 0;  // BI_RGB
  InfoHdr.biSizeImage     := UInt32(BmpStride * AHeight);
  InfoHdr.biXPelsPerMeter := PixelsPerMeter;
  InfoHdr.biYPelsPerMeter := PixelsPerMeter;

  OrgPos := AStream.Position;
  AStream.Write(FileHdr, SizeOf(FileHdr));
  AStream.Write(InfoHdr, SizeOf(InfoHdr));

  SetLength(DstRow, BmpStride);

  for y := 0 to AHeight - 1 do
  begin
    // Quell-Zeile (PDFium BGRx = 4 Bytes pro Pixel)
    SrcRow := PByte(ABitmapData) + y * AStride;
    FillChar(DstRow[0], BmpStride, 0);

    for x := 0 to AWidth - 1 do
    begin
      // BGR kopieren (Byte 0=B, 1=G, 2=R, Byte 3 ignorieren)
      DstRow[x * 3 + 0] := SrcRow[x * 4 + 0]; // B
      DstRow[x * 3 + 1] := SrcRow[x * 4 + 1]; // G
      DstRow[x * 3 + 2] := SrcRow[x * 4 + 2]; // R
    end;

    AStream.Write(DstRow[0], BmpStride);
  end;

  AStream.Position := OrgPos;
  Result := true;
end;

// ---------------------------------------------------------------------------
//  RenderPage – eigentliche Render-Logik
// ---------------------------------------------------------------------------
function TccPdfiumDocument.RenderPage(AStream : TStream; APage : FPDF_PAGE; ADpi : Integer) : Boolean;
const
  POINTS_PER_INCH = 72.0;
var
  PageW, PageH : Single;
  BmpW, BmpH   : Integer;
  Bitmap       : FPDF_BITMAP;
  BufPtr       : Pointer;
  Stride       : Integer;
begin
  PageW := TccPdfiumLibHelper.FPDF_GetPageWidthF(APage);
  PageH := TccPdfiumLibHelper.FPDF_GetPageHeightF(APage);

  // Punkte → Pixel umrechnen
  BmpW := Max(1, Round(PageW * ADPI / POINTS_PER_INCH));
  BmpH := Max(1, Round(PageH * ADPI / POINTS_PER_INCH));

  // BGRx-Bitmap anlegen
  Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(BmpW, BmpH, 0 {kein Alpha});
  if Bitmap = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_CREATEFAILED);
  try
    // Weißen Hintergrund füllen (ARGB: $FFFFFFFF)
    TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, BmpW, BmpH, $FFFFFFFF);

    // Seite rendern
    TccPdfiumLibHelper.FPDF_RenderPageBitmap(
      Bitmap, APage,
      0, 0, BmpW, BmpH,
      0,                        // Rotation (0 = keine)
      FPDF_ANNOT               // Annotationen mit rendern
    );

    BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
    Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);

    Result := BuildBmpStream(AStream, BufPtr, BmpW, BmpH, Stride, ADpi);
  finally
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
  end;
end;

// ==================================================================================
{ TccPdfiumDocument }

// ----------------------------------------------------------------------------------
constructor TccPdfiumDocument.Create;
begin
  inherited Create;

  FDocument  := nil;
  FLoaded    := False;
  FPageCount := 0;
  FFileName  := '';
  FLock := TCriticalSection.Create;

  if TccPdfiumLibHelper.TryInitialize = false
    then raise EccException.Create(CCI_MSG_ERR_PIU_UNABLETOLOAD);
end;

// ----------------------------------------------------------------------------------
destructor TccPdfiumDocument.Destroy;
begin
  Close;               // Dokument schließen bevor FLock freigegeben wird
  FreeAndNil(FLock);
  inherited;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.Close;
begin
  if FLoaded and Assigned(TccPdfiumLibHelper.FPDF_CloseDocument) then
  begin
    TccPdfiumLibHelper.FPDF_CloseDocument(FDocument);
    FDocument  := nil;
    FLoaded    := False;
    FPageCount := 0;
    FFileName  := '';
  end;
  // Puffer NACH CloseDocument freigeben - PDFium darf ihn bis dahin noch lesen
  FreeAndNil(FStreamBuffer);
end;


// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.OpenFile(const AFileName : String; const APassword : String);
var
  ErrCode : UInt32;
begin
  if FLoaded then Close;

  FDocument := TccPdfiumLibHelper.FPDF_LoadDocument(PAnsiChar(AnsiString(AFileName)), PAnsiChar(AnsiString(APassword)));

  if FDocument = nil then
  begin
    ErrCode := TccPdfiumLibHelper.FPDF_GetLastError();
    raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENFILE.Format([ErrCode,AFileName]));
  end;

  FFileName  := AFileName;
  FPageCount := TccPdfiumLibHelper.FPDF_GetPageCount(FDocument);
  FLoaded    := True;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.OpenStream(AStream : TStream; const APassword : String);
begin
  if FLoaded then Close;
  if AStream = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_EMPTYSTREAM);

  // FPDF_LoadMemDocument haelt nur einen Zeiger auf den Puffer - keine interne Kopie.
  // FStreamBuffer muss deshalb so lange leben wie das Dokument geoeffnet ist.
  // Close() gibt FStreamBuffer erst NACH FPDF_CloseDocument frei.
  // Wir kopieren den Inhalt immer in einen eigenen Puffer, unabhaengig davon
  // ob AStream bereits ein TMemoryStream ist - der Aufrufer kann seinen Stream
  // danach jederzeit schliessen.
  FStreamBuffer := TMemoryStream.Create;
  AStream.Position := 0;
  FStreamBuffer.CopyFrom(AStream, 0);

  FDocument := TccPdfiumLibHelper.FPDF_LoadMemDocument(
    FStreamBuffer.Memory,
    FStreamBuffer.Size,
    PAnsiChar(AnsiString(APassword))
  );

  if FDocument = nil then
  begin
    TccPdfiumLibHelper.FPDF_GetLastError();
    FreeAndNil(FStreamBuffer);
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Fehler beim Öffnen aus Stream']));
  end;

  FFileName  := '<Stream>';
  FPageCount := TccPdfiumLibHelper.FPDF_GetPageCount(FDocument);
  FLoaded    := True;
end;

// ---------------------------------------------------------------------------
//  GetMetaText – PDF-Metadaten auslesen via FPDF_GetMetaText
//  Unterstützte Tags: Title, Author, Subject, Keywords, Creator, Producer,
//                     CreationDate, ModDate
// ---------------------------------------------------------------------------
function TccPdfiumDocument.GetMetaText(const ATag : String) : String;
var
  BufLen : UInt32;
  Buf    : array of Byte;
begin
  Result := '';
  CheckLoaded;

  FLock.Acquire;
  try
    // Erste Abfrage: benötigte Puffergröße (Bytes, UTF-16LE inkl. Null-Terminator)
    BufLen := TccPdfiumLibHelper.FPDF_GetMetaText(FDocument, PAnsiChar(AnsiString(ATag)), nil, 0);
    if BufLen <= 2 then
      Exit; // Leer oder nur Null-Terminator

    SetLength(Buf, BufLen);
    TccPdfiumLibHelper.FPDF_GetMetaText(FDocument, PAnsiChar(AnsiString(ATag)), @Buf[0], BufLen);
  finally
    FLock.Release;
  end;

  // UTF-16LE → Delphi-String (außerhalb des Locks – reine Speicheroperation)
  Result := WideCharToString(PWideChar(@Buf[0]));

end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.GetPageInfo(APageIndex : Integer) : TccPdfPageInfo;
var
  Page : FPDF_PAGE;
begin
  CheckPageIndex(APageIndex);
  FLock.Acquire;
  try
    Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, APageIndex);
    if Page = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE.Format([APageIndex]));
    try
      Result.Index    := APageIndex;
      Result.WidthPt  := TccPdfiumLibHelper.FPDF_GetPageWidthF(Page);
      Result.HeightPt := TccPdfiumLibHelper.FPDF_GetPageHeightF(Page);
      // Punkte → Millimeter: 1 Punkt = 25.4 / 72 mm
      Result.WidthMM  := Result.WidthPt  * 25.4 / 72.0;
      Result.HeightMM := Result.HeightPt * 25.4 / 72.0;
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    FLock.Release;
  end;
end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.RenderPageToBmp(AStream : TStream; APageIndex : Integer; ADpi : Integer) : Boolean;
var
  Page : FPDF_PAGE;
begin
  CheckPageIndex(APageIndex);
  FLock.Acquire;
  try
    Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, APageIndex);
    if Page = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE1.Format([APageIndex]));
    try
      Result := RenderPage(AStream, Page, ADPI);
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    FLock.Release;
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SavePageAsBmpFile(APageIndex : Integer; const AFileName : String; ADpi : Integer);
var
  Stream : TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    RenderPageToBmp(Stream,APageIndex,ADpi);
    Stream.SaveToFile(AFileName);
  finally
    FreeAndNil(Stream);
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.ExportAllPagesToBmp(const ADirectory : String; const ABaseName : String; ADpi : Integer);
var
  Dir     : String;
  i       : Integer;
  OutFile : String;
  Digits  : Integer;
begin
  CheckLoaded;
  if ADirectory <> ''
    then Dir := ADirectory
    else Dir := GetCurrentDir;

  Dir := IncludeTrailingPathDelimiter(Dir);

  if not DirectoryExists(Dir)
    then  ForceDirectories(Dir);

  // Anzahl Ziffern für Nummerierung ermitteln
  Digits := Length(IntToStr(FPageCount));

  for i := 0 to FPageCount - 1 do
  begin
    OutFile := Dir + ABaseName + Format('%.' + IntToStr(Digits) + 'd', [i + 1]) + '.bmp';
    SavePageAsBmpFile(i, OutFile, ADpi);
  end;
end;

// =========================================================================
//  WebP-Export Implementierung (PDF → WebP)
// =========================================================================

// ---------------------------------------------------------------------------
//  EncodeBgraToWebpStream (lokale Hilfsroutine)
//
//  Uebergibt einen BGRA/BGRx-Puffer (4 Bytes pro Pixel) an libwebp und
//  schreibt den erzeugten WebP-Datenstrom in AStream.
//
//  Hinweis zum Alpha-Kanal: Ein von TccPdfiumDocument.RenderPage erzeugter
//  BGRx-Puffer enthaelt nach FillRect($FFFFFFFF) im 4. Byte stets $FF –
//  daher ist er byte-identisch zu opakem BGRA und kann direkt an
//  WebPEncodeBGRA uebergeben werden. Es entsteht ein opakes WebP.
// ---------------------------------------------------------------------------
function EncodeBgraToWebpStream(AStream : TStream; ABuf : Pointer;
  AWidth, AHeight, AStride : Integer;
  const AOptions : TccWebpOptions) : Boolean;
var
  OutPtr  : Pointer;
  OutSize : NativeUInt;
  Quality : Single;
begin
  if not TccWebpLibHelper.TryInitialize
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['libwebp konnte nicht geladen werden']));

  if (AWidth <= 0) or (AHeight <= 0) or (AStride <= 0) or (ABuf = nil)
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungueltiger Bitmap-Puffer fuer WebP-Encoder']));

  OutPtr := nil;
  if AOptions.Mode = wmLossless then
    OutSize := TccWebpLibHelper.WebPEncodeLosslessBGRA(ABuf, AWidth, AHeight, AStride, @OutPtr)
  else
  begin
    Quality := AOptions.Quality;
    if Quality <   0 then Quality :=   0;
    if Quality > 100 then Quality := 100;
    OutSize := TccWebpLibHelper.WebPEncodeBGRA(ABuf, AWidth, AHeight, AStride, Quality, @OutPtr);
  end;

  if (OutSize = 0) or (OutPtr = nil) then
  begin
    if (OutPtr <> nil) and Assigned(TccWebpLibHelper.WebPFree) then
      TccWebpLibHelper.WebPFree(OutPtr);
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['WebP-Kodierung fehlgeschlagen']));
  end;

  try
    AStream.Write(OutPtr^, Longint(OutSize));
    Result := True;
  finally
    if Assigned(TccWebpLibHelper.WebPFree)
      then TccWebpLibHelper.WebPFree(OutPtr);
  end;
end;

// ---------------------------------------------------------------------------
//  RenderPageToWebp (Hauptvariante mit Optionen)
// ---------------------------------------------------------------------------
function TccPdfiumDocument.RenderPageToWebp(AStream : TStream; APageIndex : Integer;
  ADpi : Integer; const AOptions : TccWebpOptions) : Boolean;
const
  POINTS_PER_INCH = 72.0;
var
  Page   : FPDF_PAGE;
  Bitmap : FPDF_BITMAP;
  PageW, PageH : Single;
  BmpW, BmpH   : Integer;
  BufPtr : Pointer;
  Stride : Integer;
begin
  CheckPageIndex(APageIndex);

  if not TccWebpLibHelper.TryInitialize
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['libwebp konnte nicht geladen werden']));

  FLock.Acquire;
  try
    Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, APageIndex);
    if Page = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE1.Format([APageIndex]));
    try
      PageW := TccPdfiumLibHelper.FPDF_GetPageWidthF(Page);
      PageH := TccPdfiumLibHelper.FPDF_GetPageHeightF(Page);

      BmpW := Max(1, Round(PageW * ADpi / POINTS_PER_INCH));
      BmpH := Max(1, Round(PageH * ADpi / POINTS_PER_INCH));

      Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(BmpW, BmpH, 0 {kein Alpha -> BGRx});
      if Bitmap = nil
        then raise EccException.Create(CCI_MSG_ERR_PIU_CREATEFAILED);
      try
        // Weisser Hintergrund – setzt auch das Padding-Byte auf $FF, wodurch der
        // BGRx-Puffer wie opakes BGRA aussieht (Alpha=$FF) und direkt an
        // WebPEncodeBGRA uebergeben werden kann.
        TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, BmpW, BmpH, $FFFFFFFF);

        TccPdfiumLibHelper.FPDF_RenderPageBitmap(Bitmap, Page,
          0, 0, BmpW, BmpH,
          0, FPDF_ANNOT
        );

        BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
        Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);
      finally
        TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
      end;
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    FLock.Release;
  end;

  // WebP-Encoding außerhalb des Locks – arbeitet nur auf dem lokalen Puffer
  Result := EncodeBgraToWebpStream(AStream, BufPtr, BmpW, BmpH, Stride, AOptions);
end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.RenderPageToWebp(AStream : TStream; APageIndex : Integer;
  ADpi : Integer) : Boolean;
begin
  Result := RenderPageToWebp(AStream, APageIndex, ADpi, TccWebpOptions.Default);
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SavePageAsWebpFile(APageIndex : Integer;
  const AFileName : String; ADpi : Integer; const AOptions : TccWebpOptions);
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    RenderPageToWebp(FS, APageIndex, ADpi, AOptions);
  finally
    FS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SavePageAsWebpFile(APageIndex : Integer;
  const AFileName : String; ADpi : Integer);
begin
  SavePageAsWebpFile(APageIndex, AFileName, ADpi, TccWebpOptions.Default);
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.ExportAllPagesToWebp(const ADirectory : String;
  const ABaseName : String; ADpi : Integer; const AOptions : TccWebpOptions);
var
  Dir     : String;
  i       : Integer;
  OutFile : String;
  Digits  : Integer;
begin
  CheckLoaded;
  if ADirectory <> ''
    then Dir := ADirectory
    else Dir := GetCurrentDir;

  Dir := IncludeTrailingPathDelimiter(Dir);

  if not DirectoryExists(Dir)
    then ForceDirectories(Dir);

  Digits := Length(IntToStr(FPageCount));

  for i := 0 to FPageCount - 1 do
  begin
    OutFile := Dir + ABaseName + Format('%.' + IntToStr(Digits) + 'd', [i + 1]) + '.webp';
    SavePageAsWebpFile(i, OutFile, ADpi, AOptions);
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.ExportAllPagesToWebp(const ADirectory : String;
  const ABaseName : String; ADpi : Integer);
begin
  ExportAllPagesToWebp(ADirectory, ABaseName, ADpi, TccWebpOptions.Default);
end;

// =========================================================================
//  WebP-Import Implementierung (WebP → PDF)
// =========================================================================

// ---------------------------------------------------------------------------
//  WebpStreamToPdfiumBitmap
//  Liest einen kompletten WebP-Datenstrom und dekodiert ihn direkt in einen
//  frisch erzeugten PDFium-Bitmap (BGRA, Top-Down).  Der Decode erfolgt ohne
//  Zwischenkopie via WebPDecodeBGRAInto.
//  Caller muss FPDFBitmap_Destroy auf dem Ergebnis aufrufen.
// ---------------------------------------------------------------------------
class function TccPdfiumDocument.WebpStreamToPdfiumBitmap(AStream : TStream;
  out AImgW, AImgH : Integer) : FPDF_BITMAP;
var
  WebpData : TBytes;
  SrcSize  : NativeUInt;
  Bitmap   : FPDF_BITMAP;
  BufPtr   : Pointer;
  Stride   : Integer;
  SavePos  : Int64;
begin
  AImgW := 0;
  AImgH := 0;

  if not TccWebpLibHelper.TryInitialize
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['libwebp konnte nicht geladen werden']));

  if AStream = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['WebP-Stream ist nil']));

  // Kompletten Stream in eigenen Puffer kopieren (libwebp braucht einen
  // zusammenhaengenden Byte-Block, kein Stream-API).
  SavePos := AStream.Position;
  try
    AStream.Position := 0;
    SetLength(WebpData, AStream.Size);
    if Length(WebpData) < 12 then     // minimaler RIFF/WEBP-Header ist 12 Bytes
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['WebP-Stream zu klein / leer']));
    AStream.ReadBuffer(WebpData[0], Length(WebpData));
  finally
    AStream.Position := SavePos;
  end;

  SrcSize := NativeUInt(Length(WebpData));

  if TccWebpLibHelper.WebPGetInfo(@WebpData[0], SrcSize, @AImgW, @AImgH) = 0 then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungueltige WebP-Datei (WebPGetInfo)']));

  if (AImgW <= 0) or (AImgH <= 0) then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungueltige WebP-Dimensionen']));

  // BGRA-Bitmap (alpha=1 -> Format BGRA).  Wir fuellen bewusst NICHT mit Weiss:
  // WebPDecodeBGRAInto ueberschreibt den Puffer komplett.  Transparente WebPs
  // behalten ihren Alpha-Kanal und PDFium kann damit Soft-Masken erzeugen.
  Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(AImgW, AImgH, 1);
  if Bitmap = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFBitmap_Create fehlgeschlagen (WebP->PDF)']));
  try
    BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
    Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);

    if TccWebpLibHelper.WebPDecodeBGRAInto(
         @WebpData[0], SrcSize,
         BufPtr, NativeUInt(Int64(Stride) * Int64(AImgH)), Stride) = nil then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['WebP-Dekodierung fehlgeschlagen']));

    Result := Bitmap;
  except
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    raise;
  end;
end;

// ---------------------------------------------------------------------------
//  AddWebpPageToDocument (lokale Hilfsroutine, analog zu AddBmpPageToDocument)
//  APageIndex = -1 -> ans Ende anfuegen
// ---------------------------------------------------------------------------
procedure AddWebpPageToDocument(ADocument : FPDF_DOCUMENT; AWebpStream : TStream;
  APageIndex : Integer; const AOptions : TccBmpToPdfOptions);
const
  MM_TO_PT = 72.0 / 25.4;
var
  Bitmap         : FPDF_BITMAP;
  ImgW, ImgH     : Integer;
  PageW, PageH   : Double;
  ImgWidthPt     : Double;
  ImgHeightPt    : Double;
  DrawX, DrawY   : Double;
  DrawW, DrawH   : Double;
  MarginPt       : Double;
  AvailW, AvailH : Double;
  ScaleX, ScaleY : Double;
  Scale          : Double;
  Page           : FPDF_PAGE;
  ImageObj       : Pointer;
  PageCount      : Integer;
  InsertIdx      : Integer;
  DPI            : Integer;
begin
  // WebP dekodieren -> PDFium-Bitmap.  Liefert ImgW, ImgH.
  Bitmap := TccPdfiumDocument.WebpStreamToPdfiumBitmap(AWebpStream, ImgW, ImgH);
  try
    DPI := AOptions.SourceDPI;
    if DPI <= 0 then DPI := 96;

    ImgWidthPt  := ImgW * 72.0 / DPI;
    ImgHeightPt := ImgH * 72.0 / DPI;

    if (AOptions.PageWidthMM > 0) and (AOptions.PageHeightMM > 0) then
    begin
      PageW := AOptions.PageWidthMM  * MM_TO_PT;
      PageH := AOptions.PageHeightMM * MM_TO_PT;
    end
    else
    begin
      PageW := ImgWidthPt;
      PageH := ImgHeightPt;
    end;

    MarginPt := AOptions.MarginMM * MM_TO_PT;
    AvailW   := PageW - 2 * MarginPt;
    AvailH   := PageH - 2 * MarginPt;
    if AvailW < 1 then AvailW := PageW;
    if AvailH < 1 then AvailH := PageH;

    case AOptions.FitMode of
      bfmStretchToPage:
        begin DrawW := AvailW; DrawH := AvailH; end;
      bfmKeepAspectRatio:
        begin
          ScaleX := AvailW / ImgWidthPt;
          ScaleY := AvailH / ImgHeightPt;
          Scale  := Min(ScaleX, ScaleY);
          DrawW  := ImgWidthPt  * Scale;
          DrawH  := ImgHeightPt * Scale;
        end;
    else // bfmOriginalSize
      DrawW := Min(ImgWidthPt,  AvailW);
      DrawH := Min(ImgHeightPt, AvailH);
    end;

    DrawX := MarginPt + (AvailW - DrawW) / 2.0;
    DrawY := MarginPt + (AvailH - DrawH) / 2.0;

    PageCount := TccPdfiumLibHelper.FPDF_GetPageCount(ADocument);
    if (APageIndex < 0) or (APageIndex >= PageCount) then
      InsertIdx := PageCount
    else
      InsertIdx := APageIndex;

    Page := TccPdfiumLibHelper.FPDFPage_New(ADocument, InsertIdx, PageW, PageH);
    if Page = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_New fehlgeschlagen (WebP)']));
    try
      ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
      if ImageObj = nil
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPageObj_NewImageObj fehlgeschlagen (WebP)']));

      if not TccPdfiumLibHelper.FPDFImageObj_SetBitmap(nil, 0, ImageObj, Bitmap)
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFImageObj_SetBitmap fehlgeschlagen (WebP)']));

      TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj,
        DrawW, 0,
        0,     DrawH,
        DrawX, DrawY
      );

      TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
      // ImageObj gehoert nun der Seite - nicht freigeben!

      if not TccPdfiumLibHelper.FPDFPage_GenerateContent(Page)
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_GenerateContent fehlgeschlagen (WebP)']));
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
  end;
end;

// =========================================================================
//  Oeffentliche WebP -> PDF Methoden
// =========================================================================

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.WebpToPdf(AWebpStream : TStream;
  const AOptions : TccBmpToPdfOptions) : TMemoryStream;
var
  Doc : FPDF_DOCUMENT;
begin
  if not TccPdfiumLibHelper.TryInitialize
    then raise EccException.Create(CCI_MSG_ERR_PIU_UNABLETOLOAD);

  Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if Doc = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    AWebpStream.Position := 0;
    AddWebpPageToDocument(Doc, AWebpStream, -1, AOptions);

    Result := TMemoryStream.Create;
    try
      SaveDocumentToStream(Doc, Result);
      Result.Position := 0;
    except
      Result.Free;
      raise;
    end;
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
  end;
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.WebpToPdf(AWebpStream : TStream) : TMemoryStream;
begin
  Result := WebpToPdf(AWebpStream, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.WebpToPdf(const AWebpFile : String;
  const AOptions : TccBmpToPdfOptions) : TMemoryStream;
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(AWebpFile, fmOpenRead or fmShareDenyNone);
  try
    Result := WebpToPdf(FS, AOptions);
  finally
    FS.Free;
  end;
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.WebpToPdf(const AWebpFile : String) : TMemoryStream;
begin
  Result := WebpToPdf(AWebpFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WebpToPdf(const AWebpFile : String;
  const APdfFile : String; const AOptions : TccBmpToPdfOptions);
var
  Stream : TMemoryStream;
begin
  Stream := WebpToPdf(AWebpFile, AOptions);
  try
    Stream.SaveToFile(APdfFile);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WebpToPdf(const AWebpFile : String;
  const APdfFile : String);
begin
  WebpToPdf(AWebpFile, APdfFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WebpToPdf(const AWebpFiles : array of String;
  const APdfFile : String; const AOptions : TccBmpToPdfOptions);
var
  Doc : FPDF_DOCUMENT;
  i   : Integer;
  FS  : TFileStream;
begin
  if Length(AWebpFiles) = 0
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Keine WebP-Dateien angegeben']));

  if not TccPdfiumLibHelper.TryInitialize
    then raise EccException.Create(CCI_MSG_ERR_PIU_UNABLETOLOAD);

  Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if Doc = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    for i := 0 to High(AWebpFiles) do
    begin
      if not FileExists(AWebpFiles[i])
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['WebP-Datei nicht gefunden: ' + AWebpFiles[i]]));

      FS := TFileStream.Create(AWebpFiles[i], fmOpenRead or fmShareDenyNone);
      try
        AddWebpPageToDocument(Doc, FS, -1, AOptions);
      finally
        FS.Free;
      end;
    end;
    SaveDocumentToFile(Doc, APdfFile);
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
  end;
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WebpToPdf(const AWebpFiles : array of String;
  const APdfFile : String);
begin
  WebpToPdf(AWebpFiles, APdfFile, TccBmpToPdfOptions.Default);
end;

// =========================================================================
//  TIFF-Export Implementierung
// =========================================================================

// ---------------------------------------------------------------------------
//  RenderPageToRaw
//  Rendert eine Seite in ein rohes RGB-Byte-Array (3 Bytes pro Pixel, Top-Down).
//  Wird intern für die TIFF-Erzeugung verwendet.
// ---------------------------------------------------------------------------
function TccPdfiumDocument.RenderPageToRaw(APage : FPDF_PAGE; ADpi : Integer;
            out AWidth, AHeight : Integer; out ABuf : TBytes) : Boolean;
// Opt: FPDFBitmap_BGR (Format 2) – PDFium rendert direkt in ABuf (3 Bytes/Px,
// kein Padding, keine interne Kopie). Danach nur noch R↔B in-place tauschen.
const
  POINTS_PER_INCH = 72.0;
var
  PageW, PageH : Single;
  Bitmap       : FPDF_BITMAP;
  Total        : Integer;
  i            : Integer;
  Px           : PByte;
  Tmp          : Byte;
begin
  PageW := TccPdfiumLibHelper.FPDF_GetPageWidthF(APage);
  PageH := TccPdfiumLibHelper.FPDF_GetPageHeightF(APage);
  AWidth  := Max(1, Round(PageW * ADpi / POINTS_PER_INCH));
  AHeight := Max(1, Round(PageH * ADpi / POINTS_PER_INCH));

  SetLength(ABuf, AWidth * AHeight * 3);

  Bitmap := TccPdfiumLibHelper.FPDFBitmap_CreateEx(
              AWidth, AHeight, FPDFBitmap_BGR, @ABuf[0], AWidth * 3);

  if Bitmap = nil then
  begin
    // Fallback: BGRx mit Kopie
    Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(AWidth, AHeight, 0);
    if Bitmap = nil then raise EccException.Create(CCI_MSG_ERR_PIU_CREATEFAILED);
    try
      TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, AWidth, AHeight, $FFFFFFFF);
      TccPdfiumLibHelper.FPDF_RenderPageBitmap(Bitmap, APage, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT);
      var BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
      var Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);
      var Dst : PByte := @ABuf[0];
      var Row : PByte;
      var x, y : Integer;
      {$R-}{$Q-}
      for y := 0 to AHeight - 1 do
      begin
        Row := PByte(BufPtr) + y * Stride;
        for x := 0 to AWidth - 1 do
        begin
          Dst^ := (Row+2)^; Inc(Dst);
          Dst^ := (Row+1)^; Inc(Dst);
          Dst^ :=  Row^;    Inc(Dst);
          Inc(Row, 4);
        end;
      end;
      {$R+}{$Q+}
    finally
      TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    end;
    Result := True; Exit;
  end;

  try
    TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, AWidth, AHeight, $FFFFFFFF);
    TccPdfiumLibHelper.FPDF_RenderPageBitmap(Bitmap, APage, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT);
    Total := AWidth * AHeight;
    Px    := @ABuf[0];
    {$R-}{$Q-}
    for i := 0 to Total - 1 do
    begin
      Tmp := Px^; Px^ := (Px+2)^; (Px+2)^ := Tmp;
      Inc(Px, 3);
    end;
    {$R+}{$Q+}
    Result := True;
  finally
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
  end;
end;

// ---------------------------------------------------------------------------
//  TIFF-Hilfsroutinen (lokal, nicht in der Klasse)
// ---------------------------------------------------------------------------

// ----------------------------------------------------------------------------------
// Schreibt einen 16-Bit-Wert (Little-Endian)
procedure TiffWrite16(AStream : TStream; AValue : Word);
begin
  AStream.Write(AValue, 2);
end;

// ----------------------------------------------------------------------------------
// Schreibt einen 32-Bit-Wert (Little-Endian)
procedure TiffWrite32(AStream : TStream; AValue : UInt32);
begin
  AStream.Write(AValue, 4);
end;

// ----------------------------------------------------------------------------------
// TIFF-Kompression-Tag-Wert
function TiffCompressionTag(AComp : TccTiffCompression) : Word;
begin
  case AComp of
    tcNone     : Result := 1;
    tcLZW      : Result := 5;
    tcPackBits : Result := 32773;
  else
    Result := 1;
  end;
end;

// ---------------------------------------------------------------------------
//  PackBits-Kompression (Apple-PackBits / TIFF Tag 32773)
// ---------------------------------------------------------------------------
function CompressPackBits(const ASrc : TBytes; AOffset, ALength : Integer) : TBytes;
var
  // Worst case: every byte is a literal → 1 header + 1 data = 2× input.
  // Pre-allocate generously to avoid re-allocations.
  Dst     : TBytes;
  DstPos  : Integer;
  i, Run  : Integer;
  Limit   : Integer;
  Literal : Integer;
  LitStart: Integer;

  procedure EnsureRoom(ANeeded : Integer);
  begin
    if DstPos + ANeeded > Length(Dst) then
      SetLength(Dst, Length(Dst) * 2 + ANeeded);
  end;

  procedure WriteByte(V : Byte);
  begin
    Dst[DstPos] := V;
    Inc(DstPos);
  end;

begin
  SetLength(Dst, ALength * 2 + 2);
  DstPos := 0;
  i      := AOffset;
  Limit  := AOffset + ALength;

  {$R-}{$Q-}
  while i < Limit do
  begin
    // Prüfe auf Run (gleiche Bytes)
    Run := 1;
    while (i + Run < Limit) and (Run < 128) and (ASrc[i + Run] = ASrc[i]) do
      Inc(Run);

    if Run >= 3 then
    begin
      // Wiederholungs-Run: -(Run-1), Byte
      EnsureRoom(2);
      WriteByte((257 - Run) and $FF);
      WriteByte(ASrc[i]);
      Inc(i, Run);
    end
    else
    begin
      // Literal-Run sammeln
      LitStart := i;
      Literal := 0;
      while (i < Limit) and (Literal < 128) do
      begin
        // Vorausschauen: Kommt ein Run >= 3?
        Run := 1;
        while (i + Run < Limit) and (Run < 128) and (ASrc[i + Run] = ASrc[i]) do
          Inc(Run);
        if (Run >= 3) and (Literal > 0) then
          Break;
        if Run >= 3 then
          Break;
        Inc(i);
        Inc(Literal);
      end;
      if Literal > 0 then
      begin
        EnsureRoom(1 + Literal);
        WriteByte((Literal - 1) and $FF);
        Move(ASrc[LitStart], Dst[DstPos], Literal);
        Inc(DstPos, Literal);
      end;
    end;
  end;
  {$R+}{$Q+}

  SetLength(Result, DstPos);
  if DstPos > 0 then
    Move(Dst[0], Result[0], DstPos);
end;

// ---------------------------------------------------------------------------
//  LZW-Kompression für TIFF
//  Opt: Direkt-adressierte Tabelle (4096×256 Slots, 4 MB Heap).
//  Schlüssel = (Prefix shl 8) or Suffix → O(1) Lookup, O(1) Reset
//  via 16-Bit Generationszähler statt FillChar.
// ---------------------------------------------------------------------------
function CompressLZW(const ASrc : TBytes; AOffset, ALength : Integer) : TBytes;
const
  CLEAR_CODE  = 256;
  EOI_CODE    = 257;
  FIRST_CODE  = 258;
  MAX_BITS    = 12;
  MAX_CODE    = (1 shl MAX_BITS) - 1;
  TABLE_SLOTS = 4096 * 256;   // 1.048.576 Einträge × 4 Bytes = 4 MB
var
  OutBuf   : TBytes;
  OutPos   : Integer;
  BitBuf   : UInt32;
  BitCount : Integer;
  CodeSize : Integer;
  NextCode : Integer;
  Table    : array of UInt32;   // high 16 = Gen, low 16 = Code
  CurGen   : Word;
  i        : Integer;
  CurCode  : Integer;
  C        : Byte;
  Slot     : UInt32;
  Idx      : Integer;

  procedure GrowOut;
  begin SetLength(OutBuf, Length(OutBuf) * 2); end;

  procedure WriteBits(ACode, ABits : Integer);
  begin
    BitBuf := BitBuf or (UInt32(ACode) shl (32 - BitCount - ABits));
    Inc(BitCount, ABits);
    while BitCount >= 8 do
    begin
      if OutPos >= Length(OutBuf) then GrowOut;
      OutBuf[OutPos] := Byte(BitBuf shr 24); Inc(OutPos);
      BitBuf := BitBuf shl 8; Dec(BitCount, 8);
    end;
  end;

  procedure FlushBits;
  begin
    if BitCount > 0 then
    begin
      if OutPos >= Length(OutBuf) then GrowOut;
      OutBuf[OutPos] := Byte(BitBuf shr 24); Inc(OutPos);
      BitBuf := 0; BitCount := 0;
    end;
  end;

  procedure ResetTable;   // O(1) – nur Generationszähler erhöhen
  begin
    Inc(CurGen);
    if CurGen = 0 then   // Überlauf nach 65535 Resets (>250 MB Input)
    begin
      CurGen := 1;
      FillChar(Table[0], TABLE_SLOTS * SizeOf(UInt32), 0);
    end;
    NextCode := FIRST_CODE;
    CodeSize := 9;
  end;

begin
  SetLength(Table, TABLE_SLOTS);
  FillChar(Table[0], TABLE_SLOTS * SizeOf(UInt32), 0);
  CurGen   := 1;
  SetLength(OutBuf, ALength + (ALength shr 2) + 1024);
  OutPos   := 0; BitBuf := 0; BitCount := 0;
  NextCode := FIRST_CODE; CodeSize := 9;

  {$R-}{$Q-}
  WriteBits(CLEAR_CODE, CodeSize);

  if ALength = 0 then
  begin
    WriteBits(EOI_CODE, CodeSize); FlushBits;
    SetLength(Result, OutPos);
    if OutPos > 0 then Move(OutBuf[0], Result[0], OutPos);
    Exit;
  end;

  CurCode := ASrc[AOffset];

  for i := AOffset + 1 to AOffset + ALength - 1 do
  begin
    C    := ASrc[i];
    Idx  := (CurCode shl 8) or C;
    Slot := Table[Idx];
    if Slot shr 16 = CurGen then
      CurCode := Slot and $FFFF
    else
    begin
      WriteBits(CurCode, CodeSize);
      if NextCode <= MAX_CODE then
      begin
        Table[Idx] := (UInt32(CurGen) shl 16) or UInt32(NextCode);
        Inc(NextCode);
        if (NextCode = (1 shl CodeSize)) and (CodeSize < MAX_BITS) then
          Inc(CodeSize);
        if NextCode > MAX_CODE then
        begin
          WriteBits(CLEAR_CODE, CodeSize); ResetTable;
        end;
      end
      else
      begin
        WriteBits(CLEAR_CODE, CodeSize); ResetTable;
      end;
      CurCode := C;
    end;
  end;

  WriteBits(CurCode, CodeSize);
  WriteBits(EOI_CODE, CodeSize);
  FlushBits;
  {$R+}{$Q+}

  SetLength(Result, OutPos);
  if OutPos > 0 then Move(OutBuf[0], Result[0], OutPos);
end;

// ---------------------------------------------------------------------------
//  RGB → Grayscale (1 Byte pro Pixel)
// ---------------------------------------------------------------------------
function RGBToGray(const ARGB : TBytes; AWidth, AHeight : Integer) : TBytes;
var
  Total  : Integer;
  i      : Integer;
  SrcPtr : PByte;
  DstPtr : PByte;
begin
  Total := AWidth * AHeight;
  SetLength(Result, Total);
  if Total = 0 then Exit;
  SrcPtr := @ARGB[0];
  DstPtr := @Result[0];
  // ITU-R BT.601: Y = 0.299R + 0.587G + 0.114B  (integer approx: *77 + *150 + *29) >> 8
  {$R-}{$Q-}
  for i := 0 to Total - 1 do
  begin
    DstPtr^ := (SrcPtr^ * 77 + (SrcPtr + 1)^ * 150 + (SrcPtr + 2)^ * 29) shr 8;
    Inc(DstPtr);
    Inc(SrcPtr, 3);
  end;
  {$R+}{$Q+}
end;

// ---------------------------------------------------------------------------
//  Grayscale → 1-Bit (Schwellwert 128), gepackt MSB-first
// ---------------------------------------------------------------------------
function GrayTo1Bit(const AGray : TBytes; AWidth, AHeight : Integer) : TBytes;
// Opt: linearer Pointer-Walk, 8 Pixel pro Ausgabe-Byte – kein y*AWidth+x Multiply.
var
  BytesPerRow : Integer;
  x, y        : Integer;
  SrcPtr      : PByte;
  DstPtr      : PByte;
  OutByte     : Byte;
  Tail        : Integer;
begin
  BytesPerRow := (AWidth + 7) shr 3;
  SetLength(Result, BytesPerRow * AHeight);
  if Length(Result) = 0 then Exit;
  FillChar(Result[0], Length(Result), 0);

  SrcPtr := @AGray[0];
  DstPtr := @Result[0];
  Tail   := AWidth and 7;
  {$R-}{$Q-}
  for y := 0 to AHeight - 1 do
  begin
    // Vollständige 8-Pixel-Gruppen
    for x := 0 to (AWidth shr 3) - 1 do
    begin
      OutByte := 0;
      if SrcPtr^ < 128 then OutByte := OutByte or $80; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $40; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $20; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $10; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $08; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $04; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $02; Inc(SrcPtr);
      if SrcPtr^ < 128 then OutByte := OutByte or $01; Inc(SrcPtr);
      DstPtr^ := OutByte; Inc(DstPtr);
    end;
    // Rest-Bits am Zeilenende
    if Tail > 0 then
    begin
      OutByte := 0;
      for x := 7 downto 8 - Tail do
      begin
        if SrcPtr^ < 128 then OutByte := OutByte or (1 shl x);
        Inc(SrcPtr);
      end;
      DstPtr^ := OutByte; Inc(DstPtr);
    end;
  end;
  {$R+}{$Q+}
end;

// ---------------------------------------------------------------------------
//  WriteTiffToStream
//  Schreibt ein (ggf. mehrseitiges) TIFF in einen Stream.
//  APages[]: RGB-Daten pro Seite (3 Bytes/Pixel für Farbe, oder wird
//            intern in Graustufen/1-Bit konvertiert).
//
//  Aufbau der erzeugten Datei:
//    [TIFF-Header 8 Bytes]
//    Pro Seite:
//      [IFD: TagCount(2) + Tags(N*12) + NextIFDOffset(4)]
//      [Extra-Daten: XRes(8) + YRes(8) + ggf. BPS(6)]
//      [Strip-Daten (komprimiert)]
// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WriteTiffToStream(AStream : TStream;
            const APages : array of TBytes;
            const AWidths, AHeights : array of Integer;
            ADpi : Integer; ACompression : TccTiffCompression;
            AGrayscale : Boolean);
const
  TIFF_BYTE     = 1;
  TIFF_SHORT    = 3;
  TIFF_LONG     = 4;
  TIFF_RATIONAL = 5;
var
  i              : Integer;
  PageData       : TBytes;
  GrayData       : TBytes;
  CompressedData : TBytes;
  BitsPerSample  : Word;
  SamplesPerPx   : Word;
  Photometric    : Word;
  Comp           : TccTiffCompression;
  TagCount       : Word;
  IFDSize        : UInt32;   // TagCount(2) + N*12 + NextIFD(4)
  ExtraSize      : UInt32;   // XRes(8) + YRes(8) + ggf. BPS(6)
  IFDOffset      : UInt32;   // Wo das IFD dieser Seite beginnt
  StripOffset    : UInt32;   // Wo die Bilddaten dieser Seite beginnen
  XResOffset     : UInt32;   // Wo die XRes RATIONAL-Daten liegen
  YResOffset     : UInt32;   // Wo die YRes RATIONAL-Daten liegen
  BPSOffset      : UInt32;   // Wo die BitsPerSample-Daten liegen (nur RGB)
  NextIFDFieldPos: Int64;      // Stream-Position des NextIFD-Felds (zum Patchen)
  PrevNextIFDPos : Int64;      // Vorheriges NextIFD-Feld (oder Header-Offset)

  procedure WriteTag(ATag, AType : Word; ACount, AValue : UInt32);
  begin
    TiffWrite16(AStream, ATag);
    TiffWrite16(AStream, AType);
    TiffWrite32(AStream, ACount);
    TiffWrite32(AStream, AValue);
  end;

begin
  // === TIFF-Header (8 Bytes) ===
  TiffWrite16(AStream, $4949);     // 'II' = Little-Endian
  TiffWrite16(AStream, 42);        // TIFF Magic Number
  PrevNextIFDPos := AStream.Position;
  TiffWrite32(AStream, 0);         // Offset zum ersten IFD – wird gleich gepatcht

  for i := 0 to High(APages) do
  begin
    Comp := ACompression;

  if AGrayscale then
    begin
      GrayData       := RGBToGray(APages[i], AWidths[i], AHeights[i]);
      PageData       := GrayData;
      BitsPerSample  := 8;
      SamplesPerPx   := 1;
      Photometric    := 1; // MinIsBlack
    end
    else
    begin
      PageData       := APages[i];
      BitsPerSample  := 8;
      SamplesPerPx   := 3;
      Photometric    := 2; // RGB
    end;

    // Komprimieren
    case Comp of
      tcLZW      : CompressedData := CompressLZW(PageData, 0, Length(PageData));
      tcPackBits : CompressedData := CompressPackBits(PageData, 0, Length(PageData));
    else
      CompressedData := PageData;
    end;

    // --- Größen vorausberechnen ---
    // Tags: ImageWidth(256), ImageLength(257), BitsPerSample(258),
    //       Compression(259), PhotometricInterpretation(262),
    //       StripOffsets(273), SamplesPerPixel(277), RowsPerStrip(278),
    //       StripByteCounts(279), XResolution(282), YResolution(283),
    //       ResolutionUnit(296)
    // = immer 12 Tags (SamplesPerPixel ist auch bei Grayscale/1-Bit sinnvoll)
    TagCount  := 12;
    IFDSize   := 2 + UInt32(TagCount) * 12 + 4;  // TagCount + Tags + NextIFD
    ExtraSize := 8 + 8;  // XRes(8) + YRes(8)
    if SamplesPerPx > 1 then
      Inc(ExtraSize, SamplesPerPx * 2);  // BitsPerSample-Array (3 × SHORT = 6 Bytes)

    // Word-Alignment sicherstellen (IFD muss auf Word-Grenze liegen)
    if (AStream.Position mod 2) <> 0 then
    begin
      var PadByte : Byte := 0;
      AStream.Write(PadByte, 1);
    end;

    // Layout: [IFD] [Extra-Daten] [Strip-Daten]
    // Alle Offsets können wir jetzt vorausberechnen.
    IFDOffset   := UInt32(AStream.Position);
    XResOffset  := IFDOffset + IFDSize;
    YResOffset  := XResOffset + 8;
    if SamplesPerPx > 1 then
      BPSOffset := YResOffset + 8
    else
      BPSOffset := 0;
    StripOffset := IFDOffset + IFDSize + ExtraSize;

    // --- Vorheriges NextIFD-Feld auf dieses IFD patchen ---
    var SavePos := AStream.Position;
    AStream.Position := PrevNextIFDPos;
    TiffWrite32(AStream, IFDOffset);
    AStream.Position := SavePos;

    // === IFD schreiben ===
    TiffWrite16(AStream, TagCount);

    // TIFF-Spec: Tags MÜSSEN in aufsteigender Tag-ID-Reihenfolge stehen!
    // 256, 257, 258, 259, 262, 273, 277, 278, 279, 282, 283, 296

    // Tag 256: ImageWidth
    WriteTag(256, TIFF_LONG, 1, UInt32(AWidths[i]));

    // Tag 257: ImageLength (Height)
    WriteTag(257, TIFF_LONG, 1, UInt32(AHeights[i]));

    // Tag 258: BitsPerSample
    if SamplesPerPx = 1 then
      // Count=1: Wert passt direkt ins 4-Byte Value-Feld
      WriteTag(258, TIFF_SHORT, 1, UInt32(BitsPerSample))
    else
      // Count=3 (RGB): Daten passen nicht in 4 Bytes → Offset auf Extra-Daten
      WriteTag(258, TIFF_SHORT, SamplesPerPx, BPSOffset);

    // Tag 259: Compression
    WriteTag(259, TIFF_SHORT, 1, UInt32(TiffCompressionTag(Comp)));

    // Tag 262: PhotometricInterpretation
    WriteTag(262, TIFF_SHORT, 1, UInt32(Photometric));

    // Tag 273: StripOffsets (ein Strip pro Seite)
    WriteTag(273, TIFF_LONG, 1, StripOffset);

    // Tag 277: SamplesPerPixel
    WriteTag(277, TIFF_SHORT, 1, UInt32(SamplesPerPx));

    // Tag 278: RowsPerStrip (gesamte Bildhöhe = ein Strip)
    WriteTag(278, TIFF_LONG, 1, UInt32(AHeights[i]));

    // Tag 279: StripByteCounts
    WriteTag(279, TIFF_LONG, 1, UInt32(Length(CompressedData)));

    // Tag 282: XResolution → Offset auf RATIONAL-Daten
    WriteTag(282, TIFF_RATIONAL, 1, XResOffset);

    // Tag 283: YResolution → Offset auf RATIONAL-Daten
    WriteTag(283, TIFF_RATIONAL, 1, YResOffset);

    // Tag 296: ResolutionUnit = 2 (Inch)
    WriteTag(296, TIFF_SHORT, 1, 2);

    // NextIFD Offset – 0 = letzte Seite (wird ggf. bei nächster Seite gepatcht)
    NextIFDFieldPos := AStream.Position;
    TiffWrite32(AStream, 0);

    // === Extra-Daten schreiben (direkt nach dem IFD) ===
    // XResolution: RATIONAL = Numerator(4) + Denominator(4)
    TiffWrite32(AStream, UInt32(ADpi));
    TiffWrite32(AStream, 1);

    // YResolution: RATIONAL
    TiffWrite32(AStream, UInt32(ADpi));
    TiffWrite32(AStream, 1);

    // BitsPerSample-Array (nur bei RGB, 3 × SHORT)
    if SamplesPerPx > 1 then
    begin
      var s : Word;
      for s := 1 to SamplesPerPx do
        TiffWrite16(AStream, BitsPerSample);
    end;

    // === Strip-Daten schreiben ===
    Assert(UInt32(AStream.Position) = StripOffset,
           'TIFF-Writer: Strip-Offset Mismatch');
    if Length(CompressedData) > 0 then
      AStream.Write(CompressedData[0], Length(CompressedData));

    PrevNextIFDPos := NextIFDFieldPos;
  end;
end;

// ---------------------------------------------------------------------------
//  WriteTiffPrecompressedToStream
//  Schreibt TIFF aus fertigen (extern komprimierten) Seiten-Puffern.
//  Opt: IFD + ExtraData in 200-Byte-Lokalpuffer → ein Write-Aufruf pro Seite.
//       TMemoryStream wird auf Endgröße vorbelegt (keine Reallokationen).
// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.WriteTiffPrecompressedToStream(AStream : TStream;
            const ACompPages : array of TBytes;
            const AWidths, AHeights : array of Integer;
            const ASamplesPerPx, ABitsPerSample, APhotometric : array of Word;
            ADpi : Integer; ACompression : TccTiffCompression);
const
  TAG_COUNT  = 12;
  TIFF_SHORT = 3;
  TIFF_LONG  = 4;
  TIFF_RAT   = 5;
var
  i               : Integer;
  n               : Integer;
  IFDSize         : UInt32;
  ExtraSize       : UInt32;
  IFDOffset       : UInt32;
  StripOffset     : UInt32;
  XResOffset      : UInt32;
  YResOffset      : UInt32;
  BPSOffset       : UInt32;
  NextIFDFieldPos : Int64;
  PrevNextIFDPos  : Int64;
  SavePos         : Int64;
  Meta    : array[0..199] of Byte;
  MetaPos : Integer;
  CompTag : Word;

  procedure PutW16(V : Word);
  begin PWord(@Meta[MetaPos])^ := V; Inc(MetaPos, 2); end;

  procedure PutW32(V : UInt32);
  begin PUInt32(@Meta[MetaPos])^ := V; Inc(MetaPos, 4); end;

  procedure PutTag(ATag, AType : Word; ACount, AValue : UInt32);
  begin PutW16(ATag); PutW16(AType); PutW32(ACount); PutW32(AValue); end;

begin
  n := Length(ACompPages);
  if n = 0 then Exit;

  // TMemoryStream vorab auf Endgröße setzen → keine internen Reallokationen
  if AStream is TMemoryStream then
  begin
    var Est : Int64 := 8;
    for i := 0 to n-1 do
      Inc(Est, 2 + TAG_COUNT*12 + 4 + 8 + 8 + ASamplesPerPx[i]*2 + Length(ACompPages[i]) + 1);
    TMemoryStream(AStream).SetSize(AStream.Position + Est);
  end;

  CompTag := TiffCompressionTag(ACompression);
  TiffWrite16(AStream, $4949); TiffWrite16(AStream, 42);
  PrevNextIFDPos := AStream.Position;
  TiffWrite32(AStream, 0);

  for i := 0 to n - 1 do
  begin
    IFDSize   := 2 + UInt32(TAG_COUNT) * 12 + 4;
    ExtraSize := 16; // XRes(8) + YRes(8)
    if ASamplesPerPx[i] > 1 then Inc(ExtraSize, UInt32(ASamplesPerPx[i]) * 2);

    if (AStream.Position and 1) <> 0 then
    begin var Pad : Byte := 0; AStream.Write(Pad, 1); end;

    IFDOffset  := UInt32(AStream.Position);
    XResOffset := IFDOffset + IFDSize;
    YResOffset := XResOffset + 8;
    BPSOffset  := YResOffset + 8;   // nur relevant wenn SamplesPerPx > 1
    StripOffset := IFDOffset + IFDSize + ExtraSize;

    SavePos := AStream.Position;
    AStream.Position := PrevNextIFDPos;
    TiffWrite32(AStream, IFDOffset);
    AStream.Position := SavePos;

    // ── Metadaten-Block lokal aufbauen ──────────────────────────────────
    MetaPos := 0;
    PutW16(TAG_COUNT);
    PutTag(256, TIFF_LONG,  1, UInt32(AWidths[i]));
    PutTag(257, TIFF_LONG,  1, UInt32(AHeights[i]));
    if ASamplesPerPx[i] = 1
      then PutTag(258, TIFF_SHORT, 1, UInt32(ABitsPerSample[i]))
      else PutTag(258, TIFF_SHORT, ASamplesPerPx[i], BPSOffset);
    PutTag(259, TIFF_SHORT, 1, UInt32(CompTag));
    PutTag(262, TIFF_SHORT, 1, UInt32(APhotometric[i]));
    PutTag(273, TIFF_LONG,  1, StripOffset);
    PutTag(277, TIFF_SHORT, 1, UInt32(ASamplesPerPx[i]));
    PutTag(278, TIFF_LONG,  1, UInt32(AHeights[i]));
    PutTag(279, TIFF_LONG,  1, UInt32(Length(ACompPages[i])));
    PutTag(282, TIFF_RAT,   1, XResOffset);
    PutTag(283, TIFF_RAT,   1, YResOffset);
    PutTag(296, TIFF_SHORT, 1, 2);
    NextIFDFieldPos := Int64(IFDOffset) + MetaPos;
    PutW32(0);                    // NextIFD – wird im nächsten Durchlauf gepatcht
    // ExtraData
    PutW32(UInt32(ADpi)); PutW32(1);   // XResolution
    PutW32(UInt32(ADpi)); PutW32(1);   // YResolution
    if ASamplesPerPx[i] > 1 then
    begin
      var s : Word;
      for s := 1 to ASamplesPerPx[i] do PutW16(ABitsPerSample[i]);
    end;
    // Einziger Write-Aufruf für alle Metadaten dieser Seite
    AStream.Write(Meta[0], MetaPos);

    // Strip-Daten
    Assert(UInt32(AStream.Position) = StripOffset, 'TIFF: Strip-Offset Mismatch');
    if Length(ACompPages[i]) > 0 then
      AStream.Write(ACompPages[i][0], Length(ACompPages[i]));

    PrevNextIFDPos := NextIFDFieldPos;
  end;

  if AStream is TMemoryStream then
    TMemoryStream(AStream).SetSize(AStream.Position);
end;

// ---------------------------------------------------------------------------
//  Öffentliche TIFF-Methoden
// ---------------------------------------------------------------------------

// ----------------------------------------------------------------------------------
function TccPdfiumDocument.RenderPageToTiff(AStream : TStream; APageIndex : Integer;
            ADpi : Integer; ACompression : TccTiffCompression; AGrayscale : Boolean) : Boolean;
var
  Page   : FPDF_PAGE;
  W, H   : Integer;
  Buf    : TBytes;
  Widths : array[0..0] of Integer;
  Heights: array[0..0] of Integer;
  Pages  : array[0..0] of TBytes;
begin
  Result := False;
  CheckPageIndex(APageIndex);
  FLock.Acquire;
  try
    Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, APageIndex);
    if Page = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE1.Format([APageIndex]));
    try
      if not RenderPageToRaw(Page, ADpi, W, H, Buf) then Exit;
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    FLock.Release;
  end;

  // TIFF-Encoding außerhalb des Locks – arbeitet nur auf lokalen Puffern
  Pages[0]   := Buf;
  Widths[0]  := W;
  Heights[0] := H;
  WriteTiffToStream(AStream, Pages, Widths, Heights, ADpi, ACompression, AGrayscale);
  AStream.Position := 0;
  Result := True;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SavePageAsTiffFile(APageIndex : Integer;
            const AFileName : String; ADpi : Integer;
            ACompression : TccTiffCompression; AGrayscale : Boolean);
var
  Stream : TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    RenderPageToTiff(Stream, APageIndex, ADpi, ACompression, AGrayscale);
    Stream.SaveToFile(AFileName);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SaveAllPagesAsTiff(AStream : TStream;
            ADpi : Integer; ACompression : TccTiffCompression;
            AGrayscale : Boolean);
//  Phase 1 – Seriell:  PDFium-Seiten rendern (nicht thread-sicher pro Dokument)
//  Phase 2 – Parallel: Gray-Konvertierung + Kompression auf allen CPU-Kernen
//  Phase 3 – Seriell:  TIFF schreiben via WriteTiffPrecompressedToStream
var
  n             : Integer;
  i             : Integer;
  Page          : FPDF_PAGE;
  AllRaw        : array of TBytes;
  AllWidths     : array of Integer;
  AllHeights    : array of Integer;
  AllCompressed : array of TBytes;
  AllSPP        : array of Word;   // SamplesPerPixel
  AllBPS        : array of Word;   // BitsPerSample
  AllPhoto      : array of Word;   // PhotometricInterpretation
  UseParallel   : Boolean;
begin
  CheckLoaded;
  n := FPageCount;
  if n = 0 then Exit;

  SetLength(AllRaw,        n); SetLength(AllWidths,  n);
  SetLength(AllHeights,    n); SetLength(AllCompressed, n);
  SetLength(AllSPP,        n); SetLength(AllBPS,     n);
  SetLength(AllPhoto,      n);

  // Phase 1: Serielles PDFium-Rendering
  FLock.Acquire;
  try
    for i := 0 to n - 1 do
    begin
      Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, i);
      if Page = nil then
        raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE1.Format([i]));
      try
        if not RenderPageToRaw(Page, ADpi, AllWidths[i], AllHeights[i], AllRaw[i]) then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['RenderPageToRaw Seite ' + IntToStr(i)]));
      finally
        TccPdfiumLibHelper.FPDF_ClosePage(Page);
      end;
    end;
  finally
    Flock.Release;
  end;

  // Phase 2: Parallele Gray-Konvertierung + Kompression
  // TParallel.For darf NICHT verschachtelt werden → Tiefenschutz
  UseParallel := TInterlocked.Increment(FParallelDepth) = 1;
  try
    if UseParallel = true
      then TParallel.For(0, n - 1,
        procedure(i : Integer)
        var PD : TBytes;
        begin
          if AGrayscale then
          begin
            PD          := RGBToGray(AllRaw[i], AllWidths[i], AllHeights[i]);
            AllRaw[i]   := nil;
            AllSPP[i]   := 1; AllBPS[i] := 8; AllPhoto[i] := 1;
          end
          else
          begin
            PD          := AllRaw[i];
            AllRaw[i]   := nil;
            AllSPP[i]   := 3; AllBPS[i] := 8; AllPhoto[i] := 2;
          end;
          case ACompression of
            tcLZW      : AllCompressed[i] := CompressLZW(PD, 0, Length(PD));
            tcPackBits : AllCompressed[i] := CompressPackBits(PD, 0, Length(PD));
          else
            AllCompressed[i] := PD; PD := nil; Exit;
          end;
          PD := nil;
        end)
    else
      for i := 0 to n - 1 do
        begin
          var PD : TBytes;
          if AGrayscale then
          begin
            PD        := RGBToGray(AllRaw[i], AllWidths[i], AllHeights[i]);
            AllRaw[i] := nil;
            AllSPP[i] := 1; AllBPS[i] := 8; AllPhoto[i] := 1;
          end
          else
          begin
            PD        := AllRaw[i]; AllRaw[i] := nil;
            AllSPP[i] := 3; AllBPS[i] := 8; AllPhoto[i] := 2;
          end;
          case ACompression of
            tcLZW      : AllCompressed[i] := CompressLZW(PD, 0, Length(PD));
            tcPackBits : AllCompressed[i] := CompressPackBits(PD, 0, Length(PD));
          else
            AllCompressed[i] := PD;
          end;
        end;
  finally
    TInterlocked.Decrement(FParallelDepth);
  end;


  // Phase 3: Serielles TIFF-Schreiben
  WriteTiffPrecompressedToStream(
    AStream, AllCompressed, AllWidths, AllHeights,
    AllSPP, AllBPS, AllPhoto, ADpi, ACompression);

  for i := 0 to n-1 do AllCompressed[i] := nil;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.SaveAllPagesAsTiffFile(const AFileName : String;
            ADpi : Integer; ACompression : TccTiffCompression;
            AGrayscale : Boolean);
var
  Stream : TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    SaveAllPagesAsTiff(Stream, ADpi, ACompression, AGrayscale);
    Stream.SaveToFile(AFileName);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.ExportAllPagesToTiff(const ADirectory : String;
            const ABaseName : String; ADpi : Integer;
            ACompression : TccTiffCompression; AGrayscale : Boolean);
//  Phase 1 – Seriell:  Alle Seiten rendern
//  Phase 2 – Parallel: Gray + Kompression
//  Phase 3 – Parallel: Jede Seite in eigene TIFF-Datei schreiben
var
  Dir           : String;
  n, i          : Integer;
  Digits        : Integer;
  OutFiles      : array of String;
  AllRaw        : array of TBytes;
  AllWidths     : array of Integer;
  AllHeights    : array of Integer;
  AllCompressed : array of TBytes;
  AllSPP        : array of Word;
  AllBPS        : array of Word;
  AllPhoto      : array of Word;
  Page          : FPDF_PAGE;
begin
  CheckLoaded;
  n := FPageCount;
  if n = 0 then Exit;

  if ADirectory <> ''
    then Dir := ADirectory
    else Dir := GetCurrentDir;
  Dir := IncludeTrailingPathDelimiter(Dir);
  if not DirectoryExists(Dir) then ForceDirectories(Dir);
  Digits := Length(IntToStr(n));

  SetLength(OutFiles,      n); SetLength(AllRaw,        n);
  SetLength(AllWidths,     n); SetLength(AllHeights,    n);
  SetLength(AllCompressed, n); SetLength(AllSPP,        n);
  SetLength(AllBPS,        n); SetLength(AllPhoto,      n);

  for i := 0 to n-1 do
    OutFiles[i] := Dir + ABaseName + Format('%.' + IntToStr(Digits) + 'd', [i+1]) + '.tiff';

  // Phase 1: Serielles Rendering
  FLock.Acquire;
  try
    for i := 0 to n - 1 do
    begin
      Page := TccPdfiumLibHelper.FPDF_LoadPage(FDocument, i);
      if Page = nil then
        raise EccException.Create(CCI_MSG_ERR_PIU_ERROROPENPAGE1.Format([i]));
      try
        if not RenderPageToRaw(Page, ADpi, AllWidths[i], AllHeights[i], AllRaw[i]) then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['RenderPageToRaw Seite ' + IntToStr(i)]));
      finally
        TccPdfiumLibHelper.FPDF_ClosePage(Page);
      end;
    end;
  finally
    FLock.Release;
  end;

  // Phase 2: Parallele Kompression
  TParallel.For(0, n - 1,
    procedure(i : Integer)
    var PD : TBytes;
    begin
      if AGrayscale then
      begin
        PD := RGBToGray(AllRaw[i], AllWidths[i], AllHeights[i]);
        AllRaw[i] := nil;
        AllSPP[i] := 1; AllBPS[i] := 8; AllPhoto[i] := 1;
      end
      else
      begin
        PD := AllRaw[i]; AllRaw[i] := nil;
        AllSPP[i] := 3; AllBPS[i] := 8; AllPhoto[i] := 2;
      end;
      case ACompression of
        tcLZW      : AllCompressed[i] := CompressLZW(PD, 0, Length(PD));
        tcPackBits : AllCompressed[i] := CompressPackBits(PD, 0, Length(PD));
      else
        AllCompressed[i] := PD; PD := nil; Exit;
      end;
      PD := nil;
    end);

  // Phase 3: Paralleles Schreiben (je Seite eine eigene Datei)
  TParallel.For(0, n - 1,
    procedure(i : Integer)
    var
      MS   : TMemoryStream;
      Comp : array[0..0] of TBytes;
      Ws   : array[0..0] of Integer;
      Hs   : array[0..0] of Integer;
      SP   : array[0..0] of Word;
      BP   : array[0..0] of Word;
      Ph   : array[0..0] of Word;
    begin
      Comp[0] := AllCompressed[i];
      Ws[0]   := AllWidths[i];   Hs[0]  := AllHeights[i];
      SP[0]   := AllSPP[i];      BP[0]  := AllBPS[i];
      Ph[0]   := AllPhoto[i];
      MS := TMemoryStream.Create;
      try
        WriteTiffPrecompressedToStream(MS, Comp, Ws, Hs, SP, BP, Ph, ADpi, ACompression);
        MS.SaveToFile(OutFiles[i]);
      finally
        MS.Free;
      end;
      AllCompressed[i] := nil;
    end);
end;

function TccPdfiumDocument.AttachmentCount: Integer;
begin
  CheckLoaded;
  if not Assigned(TccPdfiumLibHelper.FPDFDoc_GetAttachmentCount)
    then raise EccException.Create(CCI_MSG_ERR_PIU_GETATTACHMENTERROR);
  FLock.Acquire;
  try
    Result := TccPdfiumLibHelper.FPDFDoc_GetAttachmentCount(FDocument);
  finally
    FLock.Release;
  end;
end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.GetAttachmentInfo(AIndex : Integer) : TccPdfAttachmentInfo;
var
  Att     : FPDF_ATTACHMENT;
  BufLen  : UInt32;
  WBuf    : array of WideChar;
  DataLen : LongWord;
begin
  CheckLoaded;
  if (AIndex < 0) or (AIndex >= AttachmentCount)
    then raise EccException.Create(CCI_MSG_ERR_PIU_INVALIDATTACHMENTINDEX.Format([AIndex, AttachmentCount - 1]));

  FLock.Acquire;
  try
    Att := TccPdfiumLibHelper.FPDFDoc_GetAttachment(FDocument, AIndex);
    if Att = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ATTACHMENTNOTAVAILABLE.Format([AIndex]));

    Result.Index := AIndex;

    // Name abrufen (UTF-16LE)
    BufLen := TccPdfiumLibHelper.FPDFAttachment_GetName(Att, nil, 0);
    if BufLen > 0 then
    begin
      SetLength(WBuf, BufLen div 2 + 1);
      TccPdfiumLibHelper.FPDFAttachment_GetName(Att, @WBuf[0], BufLen);
      Result.Name := WideCharToString(@WBuf[0]);
    end
    else
      Result.Name := Format('attachment_%d', [AIndex]);

    // Größe ermitteln (nur Länge abfragen, kein Puffer)
    DataLen := 0;
    if TccPdfiumLibHelper.FPDFAttachment_GetFile(Att, nil, 0, @DataLen) then
      Result.Size := DataLen
    else
      Result.Size := -1;
  finally
    FLock.Release;
  end;
end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.ExtractAttachmentToStream(AStream : TStream; AIndex : Integer) : Boolean;
var
  Att       : FPDF_ATTACHMENT;
  DataLen   : LongWord;
  ActualLen : LongWord;
  Buffer    : TBytes;
begin
  Result := false;
  CheckLoaded;
  if (AIndex < 0) or (AIndex >= AttachmentCount)
    then raise EccException.Create(CCI_MSG_ERR_PIU_INVALIDATTACHMENTINDEX1.Format([AIndex, AttachmentCount - 1]));

  FLock.Acquire;
  try
    Att := TccPdfiumLibHelper.FPDFDoc_GetAttachment(FDocument, AIndex);
    if Att = nil
      then raise EccException.Create(CCI_MSG_ERR_PIU_ATTACHMENTNOTAVAILABLE1.Format([AIndex]));

    // Größe ermitteln
    DataLen := 0;
    if not TccPdfiumLibHelper.FPDFAttachment_GetFile(Att, nil, 0, @DataLen)
      then raise EccException.Create(CCI_MSG_ERR_PIU_ATTACHMENTSIZEERROR.Format([AIndex]));

    if DataLen = 0
      then Exit;

    SetLength(Buffer, DataLen);
    ActualLen := DataLen;
    if not TccPdfiumLibHelper.FPDFAttachment_GetFile(Att, Buffer, DataLen, @ActualLen)
      then raise EccException.Create(CCI_MSG_ERR_PIU_ATTACHMENTREADERROR.Format([AIndex]));
  finally
    FLock.Release;
  end;

  // Stream-Write außerhalb des Locks – arbeitet nur auf dem lokalen Buffer
  AStream.WriteBuffer(Buffer[0], ActualLen);
  AStream.Position := 0;
  Result := True;
end;

// ---------------------------------------------------------------------------
function TccPdfiumDocument.ExtractAttachmentToFile(AIndex : Integer; const ADirectory : String) : String;
var
  Info     : TccPdfAttachmentInfo;
  Stream   : TMemoryStream;
  Dir      : String;
  SafeName : String;
  c        : Char;
  i        : Integer;
begin
  Info := GetAttachmentInfo(AIndex);

  // Dateiname sicherheitshalber bereinigen
  SafeName := '';
  for i := 1 to Length(Info.Name) do
  begin
    c := Info.Name[i];
    if CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', ' ', '(', ')'])
      then SafeName := SafeName + c
      else SafeName := SafeName + '_';
  end;
  if SafeName = ''
    then SafeName := Format('attachment_%d', [AIndex]);

  if ADirectory <> ''
    then Dir := ADirectory
    else Dir := GetCurrentDir;

  Dir := IncludeTrailingPathDelimiter(Dir);
  if not DirectoryExists(Dir)
    then ForceDirectories(Dir);

  Result := Dir + SafeName;

  Stream := TMemoryStream.Create;
  try
    ExtractAttachmentToStream(Stream,AIndex);
    Stream.SaveToFile(Result);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TccPdfiumDocument.ExtractAllAttachments(const ADirectory : String);
var
  i   : Integer;
  Cnt : Integer;
begin
  CheckLoaded;
  Cnt := AttachmentCount;
  for i := 0 to Cnt - 1 do
    ExtractAttachmentToFile(i, ADirectory);
end;

// =========================================================================
//  BMP-Lese-Hilfsroutinen
// =========================================================================

// Liest BITMAPFILEHEADER + BITMAPINFOHEADER aus einem Stream.
// Gibt True zurück wenn gültiges BMP, füllt AWidth/AHeight/ABitCount/ADataOffset.
class function TccPdfiumDocument.ReadBmpInfo(AStream : TStream; out AWidth, AHeight, ABitCount : Integer; out ADataOffset : Int64) : Boolean;
var
  FileHdr : TccBmpFileHeader;
  InfoHdr : TccBmpInfoHeader;
  SavePos : Int64;
begin
  Result := False;
  AWidth := 0; AHeight := 0; ABitCount := 0; ADataOffset := 0;
  SavePos := AStream.Position;
  try
    if AStream.Read(FileHdr, SizeOf(FileHdr)) <> SizeOf(FileHdr) then Exit;
    if FileHdr.bfType <> $4D42 then Exit; // 'BM'

    if AStream.Read(InfoHdr, SizeOf(InfoHdr)) <> SizeOf(InfoHdr) then Exit;

    AWidth      := Abs(InfoHdr.biWidth);
    AHeight     := Abs(InfoHdr.biHeight);
    ABitCount   := InfoHdr.biBitCount;
    ADataOffset := FileHdr.bfOffBits;
    Result      := (AWidth > 0) and (AHeight > 0);
  except
    AStream.Position := SavePos;
  end;
end;

// ---------------------------------------------------------------------------
// Liest BMP-Stream und erzeugt einen PDFium-Bitmap (BGRx, Top-Down).
// Unterstützt 24-Bit und 32-Bit BMP.
// Caller muss FPDFBitmap_Destroy aufrufen.
// ---------------------------------------------------------------------------
class function TccPdfiumDocument.BmpStreamToPdfiumBitmap(AStream : TStream) : FPDF_BITMAP;
// Opt 1: Alle Pixeldaten in einem einzigen AStream.Read → keine per-Zeile Seeks.
// Opt 2: 4-Byte-Schreib-Trick: ein UInt32-Zugriff pro Pixel statt 4 Byte-Zugriffe.
//   BGR(A) → BGRx: (PUInt32(Src)^ and $00FFFFFF) or $FF000000
//   funktioniert für 24-Bit (mit BMP-Row-Padding sicher) und 32-Bit gleichermaßen.
var
  ImgW, ImgH, BitCount : Integer;
  DataOffset           : Int64;
  Bitmap               : FPDF_BITMAP;
  BufPtr               : PByte;
  Stride               : Integer;
  SrcStride            : Integer;
  IsBottomUp           : Boolean;
  BytesPerPixel        : Integer;
  ActualHeight         : Integer;
  RawInfoHdr           : TccBmpInfoHeader;
  SavePos              : Int64;
  PixelData            : TBytes;
  SrcRow, DstPx, SrcPx : PByte;
  x, y                 : Integer;
begin
  SavePos := AStream.Position;

  if not ReadBmpInfo(AStream, ImgW, ImgH, BitCount, DataOffset)
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungültiges BMP-Format']));
  if not (BitCount in [24, 32])
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Nur 24-Bit und 32-Bit BMP unterstützt']));

  AStream.Position := SavePos + SizeOf(TccBmpFileHeader);
  AStream.Read(RawInfoHdr, SizeOf(RawInfoHdr));
  IsBottomUp    := RawInfoHdr.biHeight > 0;
  ActualHeight  := Abs(RawInfoHdr.biHeight);
  BytesPerPixel := BitCount div 8;
  SrcStride     := ((ImgW * BytesPerPixel) + 3) and (not 3);

  // Alle Pixeldaten auf einmal lesen → keine per-Zeile Seeks mehr
  SetLength(PixelData, SrcStride * ActualHeight);
  AStream.Position := DataOffset;
  AStream.Read(PixelData[0], Length(PixelData));

  Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(ImgW, ActualHeight, 0);
  if Bitmap = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFBitmap_Create fehlgeschlagen (BMP→PDF)']));
  try
    BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
    Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);

    {$R-}{$Q-}
    for y := 0 to ActualHeight - 1 do
    begin
      if IsBottomUp
        then SrcRow := @PixelData[(ActualHeight - 1 - y) * SrcStride]
        else SrcRow := @PixelData[y * SrcStride];
      DstPx := BufPtr + y * Stride;
      SrcPx := SrcRow;
      // 4-Byte-Trick: liest 3 (oder 4) Bytes, maskiert oberes Byte, setzt Alpha=$FF.
      // Für 24-Bit sicher: BMP-Zeilen sind auf 4 Bytes aufgefüllt.
      if BytesPerPixel = 3 then
        for x := 0 to ImgW - 1 do
        begin
          PUInt32(DstPx)^ := (PUInt32(SrcPx)^ and $00FFFFFF) or $FF000000;
          Inc(SrcPx, 3); Inc(DstPx, 4);
        end
      else
        for x := 0 to ImgW - 1 do
        begin
          PUInt32(DstPx)^ := (PUInt32(SrcPx)^ and $00FFFFFF) or $FF000000;
          Inc(SrcPx, 4); Inc(DstPx, 4);
        end;
    end;
    {$R+}{$Q+}
    Result := Bitmap;
  except
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    raise;
  end;
end;

// =========================================================================
//  FPDF_FILEWRITE Callback-Mechanismus für Stream-Ausgabe
// =========================================================================
type
  // Erweiterter FILEWRITE-Record mit Stream-Zeiger hinter dem offiziellen Teil
  TPdfSaveContext = packed record
    FileWrite : TFPDF_FILEWRITE;  // muss ERSTER Eintrag sein (PDFium zeigt hierauf)
    Stream    : TStream;          // unser Zeiger – PDFium kennt den nicht
  end;
  PPdfSaveContext = ^TPdfSaveContext;

// ----------------------------------------------------------------------------------
function PdfWriteCallback(pThis: Pointer; pData: Pointer; size: UInt32): Integer; cdecl;
var
  FW: PFPDF_FILEWRITE;
begin
  // pThis zeigt auf den TFPDF_FILEWRITE-Record selbst.
  // UserStream ist das dritte Feld in TFPDF_FILEWRITE (nach version + WriteBlock).
  FW := PFPDF_FILEWRITE(pThis);
  try
    TStream(FW^.UserStream).Write(pData^, size);
    Result := 1;
  except
    Result := 0;
  end;
end;

class procedure TccPdfiumDocument.SaveDocumentToStream(ADocument: FPDF_DOCUMENT;
                                                      AStream: TStream);
var
  FW: PFPDF_FILEWRITE;
begin
  // Heap-Allokation - Stack wuerde bei manchen PDFium-Versionen zu AV fuehren
  New(FW);
  try
    FillChar(FW^, SizeOf(TFPDF_FILEWRITE), 0);
    FW^.version    := 1;
    FW^.WriteBlock := @PdfWriteCallback;
    FW^.UserStream := Pointer(AStream);

    if not TccPdfiumLibHelper.FPDF_SaveAsCopy(ADocument, FW, FPDF_NO_INCREMENTAL) then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_SaveAsCopy fehlgeschlagen']));
  finally
    Dispose(FW);
  end;
end;

// ----------------------------------------------------------------------------------
class procedure TccPdfiumDocument.SaveDocumentToFile(ADocument : FPDF_DOCUMENT; const AFileName : string);
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    SaveDocumentToStream(ADocument, FS);
  finally
    FS.Free;
  end;
end;

// =========================================================================
//  Kern-Routine: Fügt eine BMP als neue Seite in ADocument ein
//  APageIndex = -1 → ans Ende anfügen
// =========================================================================
procedure AddBmpPageToDocument(ADocument : FPDF_DOCUMENT; ABmpStream : TStream; APageIndex : Integer; const AOptions : TccBmpToPdfOptions);
const
  MM_TO_PT  = 72.0 / 25.4;
  PT_TO_MM  = 25.4 / 72.0;
var
  Bitmap         : FPDF_BITMAP;
  ImgW, ImgH     : Integer;
  BitCount       : Integer;
  DataOffset     : Int64;
  PageW, PageH   : Double;   // in PDF-Punkten
  ImgWidthPt     : Double;
  ImgHeightPt    : Double;
  DrawX, DrawY   : Double;   // Position des Bildes (PDF-Koordinaten, Ursprung unten links)
  DrawW, DrawH   : Double;   // Zeichengröße in Punkten
  MarginPt       : Double;
  AvailW, AvailH : Double;
  ScaleX, ScaleY : Double;
  Scale          : Double;
  Page           : FPDF_PAGE;
  ImageObj       : Pointer;
  PageCount      : Integer;
  InsertIdx      : Integer;
  DPI            : Integer;
begin
  // BMP-Maße lesen (Stream-Position wird intern gerettet/restauriert)
  if not TccPdfiumDocument.ReadBmpInfo(ABmpStream, ImgW, ImgH, BitCount, DataOffset)
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungültiges BMP in AddBmpPageToDocument']));

  DPI := AOptions.SourceDPI;
  if DPI <= 0 then DPI := 96;

  // Bildgröße in Punkten (bei OriginalSize relevant)
  ImgWidthPt  := ImgW * 72.0 / DPI;
  ImgHeightPt := ImgH * 72.0 / DPI;

  // Seitengröße bestimmen
  if (AOptions.PageWidthMM > 0) and (AOptions.PageHeightMM > 0) then
  begin
    PageW := AOptions.PageWidthMM  * MM_TO_PT;
    PageH := AOptions.PageHeightMM * MM_TO_PT;
  end
  else
  begin
    // Seite = Bildgröße (bei OriginalSize) bzw. aus BMP ableiten
    PageW := ImgWidthPt;
    PageH := ImgHeightPt;
  end;

  MarginPt := AOptions.MarginMM * MM_TO_PT;
  AvailW   := PageW - 2 * MarginPt;
  AvailH   := PageH - 2 * MarginPt;
  if AvailW < 1 then AvailW := PageW;
  if AvailH < 1 then AvailH := PageH;

  // Zeichengröße je nach FitMode berechnen
  case AOptions.FitMode of
    bfmStretchToPage:
    begin
      DrawW := AvailW;
      DrawH := AvailH;
    end;
    bfmKeepAspectRatio:
    begin
      ScaleX := AvailW / ImgWidthPt;
      ScaleY := AvailH / ImgHeightPt;
      Scale  := Min(ScaleX, ScaleY);
      DrawW  := ImgWidthPt  * Scale;
      DrawH  := ImgHeightPt * Scale;
    end;
  else // bfmOriginalSize
    DrawW := Min(ImgWidthPt,  AvailW);
    DrawH := Min(ImgHeightPt, AvailH);
  end;

  // Bild zentrieren
  DrawX := MarginPt + (AvailW - DrawW) / 2.0;
  DrawY := MarginPt + (AvailH - DrawH) / 2.0;

  // Seite einfügen
  PageCount := TccPdfiumLibHelper.FPDF_GetPageCount(ADocument);
  if (APageIndex < 0) or (APageIndex >= PageCount) then
    InsertIdx := PageCount
  else
    InsertIdx := APageIndex;

  Page := TccPdfiumLibHelper.FPDFPage_New(ADocument, InsertIdx, PageW, PageH);
  if Page = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_New fehlgeschlagen']));
  try
    // BMP → PDFium-Bitmap
    ABmpStream.Position := 0;
    Bitmap := TccPdfiumDocument.BmpStreamToPdfiumBitmap(ABmpStream);
    try
      // Image-Objekt anlegen und Bitmap setzen
      ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
      if ImageObj = nil
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPageObj_NewImageObj fehlgeschlagen']));

      if not TccPdfiumLibHelper.FPDFImageObj_SetBitmap(nil, 0, ImageObj, Bitmap)
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFImageObj_SetBitmap fehlgeschlagen']));

      // Transformation: PDF-Koordinatensystem hat Ursprung links unten.
      // Matrix: [a b c d e f]
      //   a = ScaleX, d = ScaleY, e = TranslateX, f = TranslateY
      TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj,
        DrawW, 0,      // a, b
        0,     DrawH,  // c, d
        DrawX, DrawY   // e (X), f (Y)
      );

      TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
      // ImageObj gehört nun der Seite – nicht freigeben!
    finally
      TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    end;

    if not TccPdfiumLibHelper.FPDFPage_GenerateContent(Page)
      then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_GenerateContent fehlgeschlagen']));
  finally
    TccPdfiumLibHelper.FPDF_ClosePage(Page);
  end;
end;

// =========================================================================
//  Öffentliche BMP → PDF Methoden
// =========================================================================

// ----------------------------------------------------------------------------------
class function TccPdfiumDocument.BmpToPdf(ABmpStream : TStream; const AOptions : TccBmpToPdfOptions) : TMemoryStream;
var
  Doc : FPDF_DOCUMENT;
begin
  Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if Doc = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    ABmpStream.Position := 0;
    AddBmpPageToDocument(Doc, ABmpStream, -1, AOptions);

    Result := TMemoryStream.Create;
    try
      SaveDocumentToStream(Doc, Result);
      Result.Position := 0;
    except
      Result.Free;
      raise;
    end;
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
  end;
end;

class function TccPdfiumDocument.BmpToPdf(ABmpStream : TStream) : TMemoryStream;
begin
  Result := BmpToPdf(ABmpStream, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.BmpToPdf(const ABmpFile : string; const AOptions : TccBmpToPdfOptions) : TMemoryStream;
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(ABmpFile, fmOpenRead or fmShareDenyNone);
  try
    Result := BmpToPdf(FS, AOptions);
  finally
    FS.Free;
  end;
end;

class function TccPdfiumDocument.BmpToPdf(const ABmpFile : string) : TMemoryStream;
begin
  Result := BmpToPdf(ABmpFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.BmpToPdf(const ABmpFile : string; const APdfFile : string; const AOptions : TccBmpToPdfOptions);
var
  Stream : TMemoryStream;
begin
  Stream := BmpToPdf(ABmpFile, AOptions);
  try
    Stream.SaveToFile(APdfFile);
  finally
    Stream.Free;
  end;
end;

// ----------------------------------------------------------------------------------
class procedure TccPdfiumDocument.BmpToPdf(const ABmpFile : string; const APdfFile : string);
begin
  BmpToPdf(ABmpFile, APdfFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.BmpToPdf(const ABmpFiles : array of string; const APdfFile : string; const AOptions : TccBmpToPdfOptions);
var
  Doc : FPDF_DOCUMENT;
  i   : Integer;
  FS  : TFileStream;
begin
  if Length(ABmpFiles) = 0
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Keine BMP-Dateien angegeben']));

  Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if Doc = nil
    then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    for i := 0 to High(ABmpFiles) do
    begin
      if not FileExists(ABmpFiles[i])
        then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['BMP-Datei nicht gefunden']));

      FS := TFileStream.Create(ABmpFiles[i], fmOpenRead or fmShareDenyNone);
      try
        AddBmpPageToDocument(Doc, FS, -1, AOptions);
      finally
        FS.Free;
      end;
    end;
    SaveDocumentToFile(Doc, APdfFile);
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
  end;
end;

class procedure TccPdfiumDocument.BmpToPdf(const ABmpFiles : array of string; const APdfFile : string);
begin
  BmpToPdf(ABmpFiles, APdfFile, TccBmpToPdfOptions.Default);
end;

// =========================================================================
//  TIFF-Lese-Routinen (für TIFF → PDF)
// =========================================================================

// ---------------------------------------------------------------------------
//  LZW-Dekompression für TIFF (MSB-first Bit-Packing)
// ---------------------------------------------------------------------------
function DecompressLZW(const ASrc : TBytes; AExpectedSize : Integer) : TBytes;
// Opt: klassischer Prefix/Suffix-Decoder – keine per-Eintrag TBytes-Allokation,
//      keine TMemoryStream-Writes. Ausgabe in vorallokiertes TBytes.
//      Prefix[code] = Eltern-Code (-1 für 1-Byte-Einträge)
//      Suffix[code] = letztes Byte des durch diesen Code repräsentierten Strings.
//      Decode via Rückwärtslauf durch Prefix-Kette → Stack-Umkehrung → Ausgabe.

  function DoDecompress(AEarlyChange : Boolean) : TBytes;
  const
    CLEAR_CODE = 256; EOI_CODE = 257; FIRST_CODE = 258;
    MAX_BITS = 12; MAX_TABLE = 4096;
  var
    Prefix  : array[0..MAX_TABLE-1] of SmallInt; // Eltern-Code (-1 = Basis)
    Suffix  : array[0..MAX_TABLE-1] of Byte;     // letztes Byte des Strings
    Stack   : array[0..MAX_TABLE-1] of Byte;     // Decode-Stack (umgekehrt)
    Out     : TBytes;
    OutPos  : Integer;
    TblSize : Integer;
    CdSize  : Integer;
    BitPos  : Integer;
    PrevCd  : Integer;
    Cd      : Integer;
    StackTop: Integer;
    p       : Integer;
    FirstByte : Byte;

    procedure InitTable;
    var j : Integer;
    begin
      for j := 0 to 255 do begin Prefix[j] := -1; Suffix[j] := Byte(j); end;
      TblSize := FIRST_CODE; CdSize := 9;
    end;

    function ReadCode : Integer;
    var BL, BI, BIdx, Tk, Shift : Integer;
    begin
      Result := 0; BL := CdSize; Shift := CdSize;
      while BL > 0 do
      begin
        BI := BitPos shr 3; BIdx := BitPos and 7;
        if BI >= Length(ASrc) then begin Result := EOI_CODE; Exit; end;
        Tk := 8 - BIdx; if Tk > BL then Tk := BL;
        Dec(Shift, Tk);
        Result := Result or (((ASrc[BI] shr (8 - BIdx - Tk)) and ((1 shl Tk) - 1)) shl Shift);
        Inc(BitPos, Tk); Dec(BL, Tk);
      end;
    end;

    // Dekodiert 'code' auf den Stack, gibt das erste Byte des Strings zurück.
    function DecodeToStack(code : Integer) : Byte;
    begin
      StackTop := 0;
      p := code;
      while Prefix[p] >= 0 do
      begin
        Stack[StackTop] := Suffix[p]; Inc(StackTop);
        p := Prefix[p];
      end;
      Stack[StackTop] := Suffix[p]; Inc(StackTop);
      Result := Suffix[p];
      // Stack jetzt umgekehrt in Out schreiben
      if OutPos + StackTop > Length(Out) then
        SetLength(Out, (Length(Out) + StackTop) * 2);
      while StackTop > 0 do
      begin
        Dec(StackTop);
        Out[OutPos] := Stack[StackTop]; Inc(OutPos);
      end;
    end;

  begin
    SetLength(Out, Max(AExpectedSize + 64, 256));
    OutPos := 0; BitPos := 0; PrevCd := -1;
    InitTable;
    {$R-}{$Q-}
    while True do
    begin
      Cd := ReadCode;
      if Cd = EOI_CODE then Break;
      if Cd = CLEAR_CODE then begin InitTable; PrevCd := -1; Continue; end;

      if Cd < TblSize then
        FirstByte := DecodeToStack(Cd)
      else if Cd = TblSize then
      begin
        // KwKwK-Fall: string(PrevCd) + PrevCd[0]
        if PrevCd < 0 then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['LZW_FAIL']));
        FirstByte := DecodeToStack(PrevCd);
        if OutPos >= Length(Out) then SetLength(Out, Length(Out) * 2 + 1);
        Out[OutPos] := FirstByte; Inc(OutPos);
      end
      else raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['LZW_FAIL']));

      if (PrevCd >= 0) and (TblSize < MAX_TABLE) then
      begin
        Prefix[TblSize] := SmallInt(PrevCd);
        Suffix[TblSize] := FirstByte;
        Inc(TblSize);
        if AEarlyChange then begin
          if ((TblSize + 1) = (1 shl CdSize)) and (CdSize < MAX_BITS) then Inc(CdSize);
        end else begin
          if (TblSize = (1 shl CdSize)) and (CdSize < MAX_BITS) then Inc(CdSize);
        end;
      end;
      PrevCd := Cd;
      if OutPos >= AExpectedSize then Break;
    end;
    {$R+}{$Q+}
    SetLength(Out, OutPos);
    Result := Out;
  end;

begin
  try Result := DoDecompress(True); Exit; except end;
  try Result := DoDecompress(False);
  except on E: Exception do raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['LZW-Dekompression fehlgeschlagen: ' + E.Message])); end;
end;

// ---------------------------------------------------------------------------
//  PackBits-Dekompression
// ---------------------------------------------------------------------------
function DecompressPackBits(const ASrc : TBytes; AExpectedSize : Integer) : TBytes;
// Opt: pre-allokiertes TBytes statt TMemoryStream.
//      Literal-Runs: Move statt per-Byte-Write.
//      Repeat-Runs:  FillChar statt per-Byte-Write-Schleife.
var
  Out    : TBytes;
  OutPos : Integer;
  i, N, Count : Integer;
  B : Byte;
begin
  SetLength(Out, Max(AExpectedSize + 64, Length(ASrc)));
  OutPos := 0;
  i := 0;
  {$R-}{$Q-}
  while (i < Length(ASrc)) and (OutPos < AExpectedSize) do
  begin
    if ASrc[i] < 128 then N := ASrc[i] else N := Integer(ASrc[i]) - 256;
    Inc(i);
    if N >= 0 then
    begin
      // Literal: N+1 Bytes folgen
      Count := N + 1;
      if i + Count > Length(ASrc) then Count := Length(ASrc) - i;
      if Count > 0 then
      begin
        if OutPos + Count > Length(Out) then SetLength(Out, (Length(Out) + Count) * 2);
        Move(ASrc[i], Out[OutPos], Count);
        Inc(OutPos, Count); Inc(i, Count);
      end;
    end
    else if N > -128 then
    begin
      // Repeat: 1-N Wiederholungen
      Count := 1 - N;
      if i < Length(ASrc) then
      begin
        B := ASrc[i]; Inc(i);
        if OutPos + Count > Length(Out) then SetLength(Out, (Length(Out) + Count) * 2);
        FillChar(Out[OutPos], Count, B);
        Inc(OutPos, Count);
      end;
    end;
    // N = -128 → No-Op
  end;
  {$R+}{$Q+}
  SetLength(Out, OutPos);
  Result := Out;
end;

// ---------------------------------------------------------------------------
//  TIFF Byte-Order Hilfsfunktionen
// ---------------------------------------------------------------------------
function SwapWord(V : Word) : Word; inline;
var
  T : UInt32;
begin T := V; Result := Word(((T shr 8) and $FF) or ((T shl 8) and $FF00)); end;

// ----------------------------------------------------------------------------------
function SwapLong(V : UInt32) : UInt32; inline;
begin
  Result := ((V and $FF) shl 24) or ((V and $FF00) shl 8) or ((V shr 8) and $FF00) or ((V shr 24) and $FF);
end;

// ----------------------------------------------------------------------------------
procedure TiffReadW(AStream : TStream; out AVal : Word; ABE : Boolean); inline;
begin
  AStream.Read(AVal, 2); if ABE then AVal := SwapWord(AVal);
end;

// ----------------------------------------------------------------------------------
procedure TiffReadL(AStream : TStream; out AVal : UInt32; ABE : Boolean); inline;
begin
  AStream.Read(AVal, 4); if ABE then AVal := SwapLong(AVal);
end;

// ---------------------------------------------------------------------------
//  TIFF IFD Tag-Leser
// ---------------------------------------------------------------------------
type
  TccTiffTag = record
    TagID   : Word;
    DataType: Word;
    Count   : UInt32;
    Value   : UInt32;
  end;

  TccTiffPageInfo = record
    Width, Height      : Integer;
    BitsPerSample      : Integer;
    SamplesPerPixel    : Integer;
    Compression        : Integer;
    Photometric        : Integer;
    RowsPerStrip       : Integer;
    StripOffsets       : array of UInt32;
    StripByteCounts    : array of UInt32;
    ColorMap           : array of Word;   // Palette (3 * 2^BitsPerSample Einträge)
    XResDPI, YResDPI   : Integer;
    NextIFDOffset      : UInt32;
    // JPEG-in-TIFF (Compression=7): Tag 347
    JPEGTablesOffset   : UInt32;
    JPEGTablesSize     : UInt32;
    // Tiles (alternativ zu Strips bei JPEG-in-TIFF)
    TileWidth          : Integer;
    TileHeight         : Integer;
    Predictor          : Integer;   // 1=None, 2=Horizontal Differencing
  end;

// ----------------------------------------------------------------------------------
function ReadTiffPage(AStream : TStream; AIFDOffset : UInt32; ABigEndian : Boolean; out APageInfo : TccTiffPageInfo) : Boolean;
var
  TagCount  : Word;
  Tag       : TccTiffTag;
  i         : Integer;
  SavePos   : Int64;
  NumStrips : Integer;
  RawBPS    : Word;
  BE        : Boolean;
begin
  BE := ABigEndian;
  FillChar(APageInfo, SizeOf(APageInfo), 0);
  APageInfo.BitsPerSample    := 1;
  APageInfo.SamplesPerPixel  := 1;
  APageInfo.RowsPerStrip     := MaxInt;
  APageInfo.XResDPI          := 200;
  APageInfo.YResDPI          := 200;
  APageInfo.Predictor        := 1;

  AStream.Position := AIFDOffset;
  TiffReadW(AStream, TagCount, BE);

  for i := 0 to TagCount - 1 do
  begin
    TiffReadW(AStream, Tag.TagID, BE);
    TiffReadW(AStream, Tag.DataType, BE);
    TiffReadL(AStream, Tag.Count, BE);
    // Value-Feld: 4 Bytes, Interpretation hängt von DataType ab.
    // Bei SHORT (DataType=3) mit Count<=2: Wert(e) stehen linksbündig.
    // Wir lesen immer als UInt32 mit Swap, dann korrigieren für SHORT.
    TiffReadL(AStream, Tag.Value, BE);
    // Bei BigEndian + SHORT(Count=1): der 16-Bit-Wert steht nach SwapLong
    // in den oberen 16 Bit. Korrektur: shr 16.
    // Bei LittleEndian + SHORT(Count=1): steht korrekt in den unteren 16 Bit.
    if (Tag.DataType = 3) and (Tag.Count <= 2) and BE then
      Tag.Value := Tag.Value shr 16;

    case Tag.TagID of
      256: begin if Tag.DataType = 3 then APageInfo.Width := Tag.Value and $FFFF else APageInfo.Width := Tag.Value; end;
      257: begin if Tag.DataType = 3 then APageInfo.Height := Tag.Value and $FFFF else APageInfo.Height := Tag.Value; end;
      258: // BitsPerSample
        begin
          if (Tag.DataType = 3) and (Tag.Count = 1) then
            APageInfo.BitsPerSample := Tag.Value and $FFFF
          else if Tag.Count >= 1 then
          begin
            // Werte stehen an Offset (wenn > 2 Werte)
            SavePos := AStream.Position;
            if Tag.Count <= 2 then
              APageInfo.BitsPerSample := Tag.Value and $FFFF
            else
            begin
              AStream.Position := Tag.Value;
              TiffReadW(AStream, RawBPS, BE);
              APageInfo.BitsPerSample := RawBPS;
            end;
            AStream.Position := SavePos;
          end;
        end;
      259: begin if Tag.DataType = 3 then APageInfo.Compression := Tag.Value and $FFFF else APageInfo.Compression := Tag.Value; end;
      262: begin if Tag.DataType = 3 then APageInfo.Photometric := Tag.Value and $FFFF else APageInfo.Photometric := Tag.Value; end;
      273: // StripOffsets
        begin
          NumStrips := Tag.Count;
          SetLength(APageInfo.StripOffsets, NumStrips);
          if NumStrips = 1 then
          begin if Tag.DataType = 3 then APageInfo.StripOffsets[0] := Tag.Value and $FFFF else APageInfo.StripOffsets[0] := Tag.Value; end
          else
          begin
            SavePos := AStream.Position;
            AStream.Position := Tag.Value;
            for var s := 0 to NumStrips - 1 do
            begin
              if Tag.DataType = 3 then // SHORT
              begin
                var W16 : Word;
                TiffReadW(AStream, W16, BE);
                APageInfo.StripOffsets[s] := W16;
              end
              else // LONG
                begin var L32 : UInt32; TiffReadL(AStream, L32, BE); APageInfo.StripOffsets[s] := L32; end;
            end;
            AStream.Position := SavePos;
          end;
        end;
      277: APageInfo.SamplesPerPixel := Tag.Value and $FFFF;
      278: begin if Tag.DataType = 3 then APageInfo.RowsPerStrip := Tag.Value and $FFFF else APageInfo.RowsPerStrip := Tag.Value; end;
      279: // StripByteCounts
        begin
          NumStrips := Tag.Count;
          SetLength(APageInfo.StripByteCounts, NumStrips);
          if NumStrips = 1 then
          begin if Tag.DataType = 3 then APageInfo.StripByteCounts[0] := Tag.Value and $FFFF else APageInfo.StripByteCounts[0] := Tag.Value; end
          else
          begin
            SavePos := AStream.Position;
            AStream.Position := Tag.Value;
            for var s := 0 to NumStrips - 1 do
            begin
              if Tag.DataType = 3 then
              begin
                var W16 : Word;
                TiffReadW(AStream, W16, BE);
                APageInfo.StripByteCounts[s] := W16;
              end
              else
                begin var L32 : UInt32; TiffReadL(AStream, L32, BE); APageInfo.StripByteCounts[s] := L32; end;
            end;
            AStream.Position := SavePos;
          end;
        end;
      282: // XResolution (RATIONAL)
        begin
          SavePos := AStream.Position;
          AStream.Position := Tag.Value;
          var Num282, Den282 : UInt32;
          TiffReadL(AStream, Num282, BE);
          TiffReadL(AStream, Den282, BE);
          if Den282 > 0 then APageInfo.XResDPI := Num282 div Den282;
          AStream.Position := SavePos;
        end;
      283: // YResolution (RATIONAL)
        begin
          SavePos := AStream.Position;
          AStream.Position := Tag.Value;
          var Num283, Den283 : UInt32;
          TiffReadL(AStream, Num283, BE);
          TiffReadL(AStream, Den283, BE);
          if Den283 > 0 then APageInfo.YResDPI := Num283 div Den283;
          AStream.Position := SavePos;
        end;
      317: // Predictor
        begin if Tag.DataType = 3 then APageInfo.Predictor := Tag.Value and $FFFF else APageInfo.Predictor := Tag.Value; end;
      320: // ColorMap (Palette)
        begin
          // Tag.Count = 3 * 2^BitsPerSample SHORT-Werte
          // Tag.Value = Offset auf die Palette-Daten
          if Tag.Count > 0 then
          begin
            SavePos := AStream.Position;
            AStream.Position := Tag.Value;
            SetLength(APageInfo.ColorMap, Tag.Count);
            for var cm := 0 to Integer(Tag.Count) - 1 do
              TiffReadW(AStream, APageInfo.ColorMap[cm], BE);
            AStream.Position := SavePos;
          end;
        end;
      322: // TileWidth
        begin if Tag.DataType = 3 then APageInfo.TileWidth := Tag.Value and $FFFF else APageInfo.TileWidth := Tag.Value; end;
      323: // TileLength (TileHeight)
        begin if Tag.DataType = 3 then APageInfo.TileHeight := Tag.Value and $FFFF else APageInfo.TileHeight := Tag.Value; end;
      324: // TileOffsets → in StripOffsets speichern
        begin
          NumStrips := Tag.Count;
          SetLength(APageInfo.StripOffsets, NumStrips);
          if NumStrips = 1 then
          begin
            if Tag.DataType = 3 then APageInfo.StripOffsets[0] := Tag.Value and $FFFF
            else APageInfo.StripOffsets[0] := Tag.Value;
          end
          else
          begin
            SavePos := AStream.Position;
            AStream.Position := Tag.Value;
            for var s := 0 to NumStrips - 1 do
            begin
              if Tag.DataType = 3 then
              begin var W16 : Word; TiffReadW(AStream, W16, BE); APageInfo.StripOffsets[s] := W16; end
              else
              begin var L32 : UInt32; TiffReadL(AStream, L32, BE); APageInfo.StripOffsets[s] := L32; end;
            end;
            AStream.Position := SavePos;
          end;
        end;
      325: // TileByteCounts → in StripByteCounts speichern
        begin
          NumStrips := Tag.Count;
          SetLength(APageInfo.StripByteCounts, NumStrips);
          if NumStrips = 1 then
          begin
            if Tag.DataType = 3 then APageInfo.StripByteCounts[0] := Tag.Value and $FFFF
            else APageInfo.StripByteCounts[0] := Tag.Value;
          end
          else
          begin
            SavePos := AStream.Position;
            AStream.Position := Tag.Value;
            for var s := 0 to NumStrips - 1 do
            begin
              if Tag.DataType = 3 then
              begin var W16 : Word; TiffReadW(AStream, W16, BE); APageInfo.StripByteCounts[s] := W16; end
              else
              begin var L32 : UInt32; TiffReadL(AStream, L32, BE); APageInfo.StripByteCounts[s] := L32; end;
            end;
            AStream.Position := SavePos;
          end;
        end;
      347: // JPEGTables (für Compression=7)
        begin
          APageInfo.JPEGTablesOffset := Tag.Value;
          APageInfo.JPEGTablesSize   := Tag.Count;
        end;
    end;
  end;

  TiffReadL(AStream, APageInfo.NextIFDOffset, BE);

  Result := (APageInfo.Width > 0) and (APageInfo.Height > 0) and
            (Length(APageInfo.StripOffsets) > 0);
end;

// ---------------------------------------------------------------------------
//  TiffStreamToPdfiumBitmap
//  Liest eine Seite (APageIndex) aus einem TIFF-Stream und erzeugt
//  einen PDFium-Bitmap (BGRx, Top-Down).
//  Unterstützt: 1-Bit, 8-Bit Graustufen, 24-Bit RGB, 32-Bit RGBA.
//  Kompressionen: None(1), LZW(5), PackBits(32773).
// ---------------------------------------------------------------------------
class function TccPdfiumDocument.TiffStreamToPdfiumBitmap(AStream : TStream;
            APageIndex : Integer; out AImgW, AImgH, ADPI : Integer) : FPDF_BITMAP;
var
  Magic       : Word;
  FirstIFD    : UInt32;
  BigEndian   : Boolean;
  PageInfo    : TccTiffPageInfo;
  CurIFD      : UInt32;
  PageIdx     : Integer;
  StripData   : TBytes;
  RawData     : TBytes;
  Decompressed: TBytes;
  StripSize   : Integer;
  BitsPerPx   : Integer;
  BytesPerRow : Integer;
  Bitmap      : FPDF_BITMAP;
  BufPtr      : PByte;
  Stride      : Integer;
  x, y        : Integer;
  GrayVal     : Byte;
  BitVal      : Boolean;
  i           : Integer;
begin
  Result := nil;
  AImgW := 0; AImgH := 0; ADPI := 200;

  AStream.Position := 0;
  AStream.Read(Magic, 2);
  if Magic = $4949 then BigEndian := False
  else if Magic = $4D4D then BigEndian := True
  else raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungültiges TIFF-Format (weder II noch MM)']));
  TiffReadW(AStream, Magic, BigEndian);
  if Magic <> 42 then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungültiges TIFF-Format (Magic <> 42)']));
  TiffReadL(AStream, FirstIFD, BigEndian);

  // Zur gewünschten Seite navigieren
  CurIFD := FirstIFD;
  for PageIdx := 0 to APageIndex - 1 do
  begin
    if not ReadTiffPage(AStream, CurIFD, BigEndian, PageInfo) then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF-Seite' + IntToStr(PageIdx) + ' nicht lesbar']));
    CurIFD := PageInfo.NextIFDOffset;
    if CurIFD = 0 then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF hat nur ' + IntToStr(PageIdx+1) + ' Seite(n), Seite ' + IntToStr(APageIndex) + ' angefordert']));
  end;

  if not ReadTiffPage(AStream, CurIFD, BigEndian, PageInfo) then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF-Seite ' + IntToStr(APageIndex) + ' nicht lesbar']));

  // Unterstützte Kompressionen prüfen
  if not ((PageInfo.Compression=1) or (PageInfo.Compression=5) or
          (PageInfo.Compression=7) or (PageInfo.Compression=32773)) then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF-Kompression ' + IntToStr(PageInfo.Compression) + ' nicht unterstützt (nur None/LZW/JPEG/PackBits)']));

  // JPEG-komprimierte TIFFs: Strips werden in AddTiffPageToDocument
  // über FPDFImageObj_LoadJpegFileInline direkt als JPEG eingefügt.
  // BuildJpegForStrip fügt einen Adobe APP14 Marker ein der sicherstellt
  // dass der Decoder die Daten korrekt als RGB (nicht YCbCr) behandelt.
  if PageInfo.Compression = 7 then
  begin
    AImgW := PageInfo.Width;
    AImgH := PageInfo.Height;
    ADPI  := PageInfo.XResDPI;
    if ADPI <= 0 then ADPI := 200;
    Result := nil;
    Exit;
  end;

  AImgW := PageInfo.Width;
  AImgH := PageInfo.Height;
  ADPI  := PageInfo.XResDPI;
  if ADPI <= 0 then ADPI := 200;

  BitsPerPx := PageInfo.BitsPerSample * PageInfo.SamplesPerPixel;

  // Erwartete dekomprimierte Größe berechnen
  if BitsPerPx = 1 then
    BytesPerRow := (AImgW + 7) div 8
  else
    BytesPerRow := AImgW * (BitsPerPx div 8);

  // Strips dekomprimieren – direkte TBytes-Akkumulation (kein TMemoryStream)
  var RawPos : Integer := 0;
  SetLength(RawData, BytesPerRow * AImgH + 16);  // leichte Überallokation
  for i := 0 to High(PageInfo.StripOffsets) do
  begin
    StripSize := PageInfo.StripByteCounts[i];
    if StripSize <= 0 then Continue;
    SetLength(StripData, StripSize);
    AStream.Position := PageInfo.StripOffsets[i];
    AStream.ReadBuffer(StripData[0], StripSize);
    var StripRows : Integer;
    if i < High(PageInfo.StripOffsets) then StripRows := PageInfo.RowsPerStrip
    else StripRows := AImgH - i * PageInfo.RowsPerStrip;
    if (StripRows <= 0) or (StripRows > AImgH) then StripRows := AImgH;
    var StripExpected : Integer := BytesPerRow * StripRows;
    case PageInfo.Compression of
      1:     Decompressed := StripData;
      5:     Decompressed := DecompressLZW(StripData, StripExpected);
      32773: Decompressed := DecompressPackBits(StripData, StripExpected);
    else     Decompressed := StripData;
    end;
    if Length(Decompressed) > 0 then
    begin
      if RawPos + Length(Decompressed) > Length(RawData) then
        SetLength(RawData, (Length(RawData) + Length(Decompressed)) * 2);
      Move(Decompressed[0], RawData[RawPos], Length(Decompressed));
      Inc(RawPos, Length(Decompressed));
    end;
  end;
  SetLength(RawData, RawPos);

  // Predictor=2 (Horizontal Differencing): Jedes Sample ist als Differenz
  // zum vorherigen Sample in derselben Zeile gespeichert.
  // Entdifferenzierung: sample[x] := sample[x] + sample[x-1]
  if (PageInfo.Predictor = 2) and (Length(RawData) > 0) then
  begin
    var BytesPerSample : Integer := (PageInfo.BitsPerSample + 7) div 8;
    var SamplesPerRow  : Integer := AImgW * PageInfo.SamplesPerPixel;
    var RowBytes       : Integer := SamplesPerRow * BytesPerSample;
    for y := 0 to AImgH - 1 do
    begin
      var RowOfs : Integer := y * RowBytes;
      if RowOfs + RowBytes > Length(RawData) then Break;
      // Erstes Pixel bleibt, ab dem zweiten Sample addieren
      if BytesPerSample = 1 then
      begin
        for x := PageInfo.SamplesPerPixel to SamplesPerRow - 1 do
          RawData[RowOfs + x] := (RawData[RowOfs + x] + RawData[RowOfs + x - PageInfo.SamplesPerPixel]) and $FF;
      end
      else if BytesPerSample = 2 then
      begin
        for x := PageInfo.SamplesPerPixel to SamplesPerRow - 1 do
        begin
          var Cur : Integer := RowOfs + x * 2;
          var Prv : Integer := RowOfs + (x - PageInfo.SamplesPerPixel) * 2;
          var V : Integer := (RawData[Cur] or (RawData[Cur+1] shl 8)) +
                             (RawData[Prv] or (RawData[Prv+1] shl 8));
          RawData[Cur]   := V and $FF;
          RawData[Cur+1] := (V shr 8) and $FF;
        end;
      end;
    end;
  end;

  // PDFium-Bitmap anlegen (BGRx)
  Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(AImgW, AImgH, 0);
  if Bitmap = nil then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFBitmap_Create fehlgeschlagen (TIFF→PDF)']));

  try
    BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
    Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);

    // Weißen Hintergrund füllen
    TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, AImgW, AImgH, $FFFFFFFF);

    // Pixel-Loops – Pointer-Walk, kein x*4/y*BytesPerRow Multiply pro Pixel
    {$R-}{$Q-}
    var SrcRowPtr : PByte := @RawData[0];
    var DstRowPtr : PByte := BufPtr;
    var SrcPx2    : PByte;
    var DstPx2    : PByte;
    case BitsPerPx of
      1: // 1-Bit S/W: bit-by-bit pointer walk
        begin
          for y := 0 to AImgH - 1 do
          begin
            SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
            var SrcByte2 : Byte := SrcPx2^;
            var BitMask2 : Byte := $80;
            for x := 0 to AImgW - 1 do
            begin
              BitVal := (SrcByte2 and BitMask2) <> 0;
              if PageInfo.Photometric <> 0 then BitVal := not BitVal;
              if BitVal then GrayVal := 0 else GrayVal := 255;
              PUInt32(DstPx2)^ := UInt32(GrayVal) or (UInt32(GrayVal) shl 8) or (UInt32(GrayVal) shl 16) or $FF000000;
              Inc(DstPx2, 4);
              BitMask2 := BitMask2 shr 1;
              if BitMask2 = 0 then begin BitMask2 := $80; Inc(SrcPx2); SrcByte2 := SrcPx2^; end;
            end;
            Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
          end;
        end;
      8: // 8-Bit Graustufen oder Palette
        begin
          var NumColors2 : Integer := Length(PageInfo.ColorMap) div 3;
          var IsPalette  : Boolean := (PageInfo.Photometric = 3) and (NumColors2 > 0);
          var MinIsWhite : Boolean := (PageInfo.Photometric = 0) and not IsPalette;
          for y := 0 to AImgH - 1 do
          begin
            SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
            for x := 0 to AImgW - 1 do
            begin
              GrayVal := SrcPx2^; Inc(SrcPx2);
              if IsPalette then
              begin
                if GrayVal < NumColors2 then
                  PUInt32(DstPx2)^ := (UInt32(PageInfo.ColorMap[2*NumColors2+GrayVal] shr 8)) or
                                      (UInt32(PageInfo.ColorMap[NumColors2+GrayVal]    shr 8) shl 8) or
                                      (UInt32(PageInfo.ColorMap[GrayVal]               shr 8) shl 16) or
                                      $FF000000
                else
                  PUInt32(DstPx2)^ := $FF000000;
              end
              else
              begin
                if MinIsWhite then GrayVal := 255 - GrayVal;
                PUInt32(DstPx2)^ := UInt32(GrayVal) or (UInt32(GrayVal) shl 8) or (UInt32(GrayVal) shl 16) or $FF000000;
              end;
              Inc(DstPx2, 4);
            end;
            Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
          end;
        end;
      24: // 24-Bit RGB → BGRx
        // 4-Byte-Trick: R|G<<8|B<<16 → B|G<<8|R<<16|$FF<<24 via byte-swap
        begin
          for y := 0 to AImgH - 1 do
          begin
            SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
            for x := 0 to AImgW - 1 do
            begin
              var v : UInt32 := PUInt32(SrcPx2)^ and $00FFFFFF; // R|G<<8|B<<16
              PUInt32(DstPx2)^ := ((v shr 16) and $FF) or (v and $FF00) or ((v shl 16) and $FF0000) or $FF000000;
              Inc(SrcPx2, 3); Inc(DstPx2, 4);
            end;
            Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
          end;
        end;
      32: // 32-Bit RGBA → BGRx (gleicher Byte-Swap, Alpha ignorieren)
        begin
          for y := 0 to AImgH - 1 do
          begin
            SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
            for x := 0 to AImgW - 1 do
            begin
              var v : UInt32 := PUInt32(SrcPx2)^;
              PUInt32(DstPx2)^ := ((v shr 16) and $FF) or (v and $FF00) or ((v shl 16) and $FF0000) or $FF000000;
              Inc(SrcPx2, 4); Inc(DstPx2, 4);
            end;
            Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
          end;
        end;
    else
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF-Pixelformat ' + IntToStr(BitsPerPx) + ' Bits/Pixel nicht unterstützt']));
    end;
    {$R+}{$Q+}

    Result := Bitmap;
  except
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    raise;
  end;
end;

// ---------------------------------------------------------------------------
//  Zählt die Anzahl der Seiten in einem TIFF-Stream
// ---------------------------------------------------------------------------
function TiffPageCount(AStream : TStream) : Integer;
var
  Magic    : Word;
  IFDOfs   : UInt32;
  TagCount : Word;
  BE       : Boolean;
begin
  Result := 0;
  AStream.Position := 0;
  AStream.Read(Magic, 2);
  if Magic = $4949 then BE := False else if Magic = $4D4D then BE := True else Exit;
  TiffReadW(AStream, Magic, BE); if Magic <> 42 then Exit;
  TiffReadL(AStream, IFDOfs, BE);
  while IFDOfs <> 0 do begin
    Inc(Result); AStream.Position := IFDOfs;
    TiffReadW(AStream, TagCount, BE);
    AStream.Position := IFDOfs + 2 + UInt32(TagCount) * 12;
    TiffReadL(AStream, IFDOfs, BE);
  end;
end;

// ---------------------------------------------------------------------------
//  Baut ein vollständiges JPEG aus JPEGTables + Strip zusammen.
//  Bei Photometric=2 (RGB) wird ein Adobe APP14 Marker mit ColorTransform=0
//  eingefügt, damit JPEG-Decoder die Daten als RGB behandeln (keine
//  YCbCr→RGB-Konvertierung).
// ---------------------------------------------------------------------------
function BuildJpegForStrip(ATiffStream : TStream; const APageInfo : TccTiffPageInfo;
            AStripIndex : Integer) : TBytes;
const
  // Adobe APP14 Marker: Teilt dem Decoder mit dass ColorTransform=0 (RGB)
  ADOBE_APP14 : array[0..15] of Byte = (
    $FF, $EE,                          // APP14 Marker
    $00, $0E,                          // Länge = 14
    $41, $64, $6F, $62, $65,          // 'Adobe'
    $00, $64,                          // Version 100
    $00, $00,                          // Flags0
    $00, $00,                          // Flags1
    $00                                // ColorTransform: 0=RGB, 1=YCbCr
  );
var
  Tables    : TBytes;
  Strip     : TBytes;
  Dst       : TMemoryStream;
  StripSize : Integer;
  HasTables : Boolean;
  TabLen    : Integer;
  StripOfs  : Integer;
  NeedApp14 : Boolean;
  SOI       : array[0..1] of Byte;
begin
  SetLength(Result, 0);
  if (AStripIndex < 0) or (AStripIndex > High(APageInfo.StripOffsets)) then Exit;

  StripSize := APageInfo.StripByteCounts[AStripIndex];
  if StripSize <= 0 then Exit;
  SetLength(Strip, StripSize);
  ATiffStream.Position := APageInfo.StripOffsets[AStripIndex];
  ATiffStream.Read(Strip[0], StripSize);

  // Bei Photometric=2 (RGB) muss Adobe APP14 mit Transform=0 eingefügt werden,
  // damit der JPEG-Decoder keine YCbCr→RGB-Konvertierung macht.
  // Bei Photometric=6 (YCbCr) ist keine Korrektur nötig.
  NeedApp14 := (APageInfo.Photometric = 2) and (APageInfo.SamplesPerPixel >= 3);

  HasTables := (APageInfo.JPEGTablesSize > 2) and (APageInfo.JPEGTablesOffset > 0);

  if not HasTables then
  begin
    // Strip ist ein eigenständiges JPEG
    if NeedApp14 and (StripSize >= 2) and (Strip[0] = $FF) and (Strip[1] = $D8) then
    begin
      // SOI + APP14 + Rest
      Dst := TMemoryStream.Create;
      try
        Dst.Write(Strip[0], 2);             // SOI
        Dst.Write(ADOBE_APP14, SizeOf(ADOBE_APP14)); // APP14
        Dst.Write(Strip[2], StripSize - 2); // Rest ohne SOI
        SetLength(Result, Dst.Size);
        Dst.Position := 0;
        Dst.Read(Result[0], Dst.Size);
      finally
        Dst.Free;
      end;
      Exit;
    end;
    Result := Strip;
    Exit;
  end;

  // JPEGTables + Strip zusammenbauen
  SetLength(Tables, APageInfo.JPEGTablesSize);
  ATiffStream.Position := APageInfo.JPEGTablesOffset;
  ATiffStream.Read(Tables[0], APageInfo.JPEGTablesSize);

  TabLen := APageInfo.JPEGTablesSize;
  if (TabLen >= 2) and (Tables[TabLen - 2] = $FF) and (Tables[TabLen - 1] = $D9) then
    Dec(TabLen, 2);

  StripOfs := 0;
  if (StripSize >= 2) and (Strip[0] = $FF) and (Strip[1] = $D8) then
    StripOfs := 2;

  Dst := TMemoryStream.Create;
  try
    // SOI
    SOI[0] := $FF; SOI[1] := $D8;
    Dst.Write(SOI, 2);

    // Adobe APP14 für RGB
    if NeedApp14 then
      Dst.Write(ADOBE_APP14, SizeOf(ADOBE_APP14));

    // Tabellen (ohne SOI)
    if TabLen > 2 then
      Dst.Write(Tables[2], TabLen - 2);

    // Strip-Daten (ohne SOI)
    if StripSize - StripOfs > 0 then
      Dst.Write(Strip[StripOfs], StripSize - StripOfs);

    if Dst.Size > 0 then
    begin
      SetLength(Result, Dst.Size);
      Dst.Position := 0;
      Dst.Read(Result[0], Dst.Size);
    end;
  finally
    Dst.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  FPDF_FILEACCESS für JPEG-in-TIFF (ohne VCL)
// ---------------------------------------------------------------------------
type
  TFPDF_ReadBlock = function(param: Pointer; position: UInt32;
                             pBuf: PByte; size: UInt32): Integer; cdecl;
  TFPDF_FILEACCESS = record
    m_FileLen  : UInt32;
    m_GetBlock : TFPDF_ReadBlock;
    m_Param    : Pointer;
  end;
  PFPDF_FILEACCESS = ^TFPDF_FILEACCESS;

  PJpegMemBlock = ^TJpegMemBlock;
  TJpegMemBlock = record
    Data : PByte;
    Len  : Integer;
  end;

function JpegReadBlock(param: Pointer; position: UInt32;
                       pBuf: PByte; size: UInt32): Integer; cdecl;
var
  Blk : PJpegMemBlock;
begin
  Blk := PJpegMemBlock(param);
  if Integer(position + size) <= Blk^.Len then
  begin
    Move(Blk^.Data[position], pBuf^, size);
    Result := 1;
  end
  else
    Result := 0;
end;

// ---------------------------------------------------------------------------
//  Kern-Routine: Fügt eine TIFF-Seite als neue Seite in ADocument ein
// ---------------------------------------------------------------------------
procedure AddTiffPageToDocument(ADocument : FPDF_DOCUMENT;
            ATiffStream : TStream; ATiffPageIndex : Integer;
            APdfPageIndex : Integer; const AOptions : TccBmpToPdfOptions);
const
  MM_TO_PT = 72.0 / 25.4;
var
  Bitmap         : FPDF_BITMAP;
  ImgW, ImgH     : Integer;
  TiffDPI        : Integer;
  PageW, PageH   : Double;
  ImgWidthPt     : Double;
  ImgHeightPt    : Double;
  DrawX, DrawY   : Double;
  DrawW, DrawH   : Double;
  MarginPt       : Double;
  AvailW, AvailH : Double;
  ScaleX, ScaleY : Double;
  Scale          : Double;
  Page           : FPDF_PAGE;
  ImageObj       : Pointer;
  PageCount      : Integer;
  InsertIdx      : Integer;
  DPI            : Integer;
  // JPEG-Pfad
  IsJPEG         : Boolean;
  JpegData       : TBytes;
  FileAccess     : TFPDF_FILEACCESS;
  JpegBlock      : TJpegMemBlock;
  Magic          : Word;
  FirstIFD       : UInt32;
  BigEndian      : Boolean;
  CurIFD         : UInt32;
  TiffPageInfo   : TccTiffPageInfo;
  TiffPageIdx    : Integer;
  StripIdx       : Integer;
  StripH         : Integer;
  StripDrawH     : Double;
  StripY         : Double;
  CurPixelY      : Integer;
begin
  // Prüfe ob diese Seite JPEG-komprimiert ist
  IsJPEG := False;
  ATiffStream.Position := 0;
  ATiffStream.Read(Magic, 2);
  if Magic = $4949 then BigEndian := False
  else if Magic = $4D4D then BigEndian := True
  else raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Ungültiges TIFF']));
  TiffReadW(ATiffStream, Magic, BigEndian);
  TiffReadL(ATiffStream, FirstIFD, BigEndian);
  CurIFD := FirstIFD;
  for TiffPageIdx := 0 to ATiffPageIndex - 1 do
  begin
    if not ReadTiffPage(ATiffStream, CurIFD, BigEndian, TiffPageInfo) then Break;
    CurIFD := TiffPageInfo.NextIFDOffset;
    if CurIFD = 0 then Break;
  end;
  if ReadTiffPage(ATiffStream, CurIFD, BigEndian, TiffPageInfo) then
    IsJPEG := (TiffPageInfo.Compression = 7);

  if IsJPEG then
  begin
    ImgW    := TiffPageInfo.Width;
    ImgH    := TiffPageInfo.Height;
    TiffDPI := TiffPageInfo.XResDPI;
    if TiffDPI <= 0 then TiffDPI := 200;
    Bitmap := nil;
  end
  else
  begin
    Bitmap := TccPdfiumDocument.TiffStreamToPdfiumBitmap(ATiffStream, ATiffPageIndex,
                                                         ImgW, ImgH, TiffDPI);
  end;

  try
    DPI := AOptions.SourceDPI;
    if DPI <= 0 then DPI := TiffDPI;
    if DPI <= 0 then DPI := 200;

    ImgWidthPt  := ImgW * 72.0 / DPI;
    ImgHeightPt := ImgH * 72.0 / DPI;

    if (AOptions.PageWidthMM > 0) and (AOptions.PageHeightMM > 0) then
    begin
      PageW := AOptions.PageWidthMM  * MM_TO_PT;
      PageH := AOptions.PageHeightMM * MM_TO_PT;
    end
    else
    begin
      PageW := ImgWidthPt;
      PageH := ImgHeightPt;
    end;

    MarginPt := AOptions.MarginMM * MM_TO_PT;
    AvailW   := PageW - 2 * MarginPt;
    AvailH   := PageH - 2 * MarginPt;
    if AvailW < 1 then AvailW := PageW;
    if AvailH < 1 then AvailH := PageH;

    case AOptions.FitMode of
      bfmStretchToPage:
        begin DrawW := AvailW; DrawH := AvailH; end;
      bfmKeepAspectRatio:
        begin
          ScaleX := AvailW / ImgWidthPt;
          ScaleY := AvailH / ImgHeightPt;
          Scale  := Min(ScaleX, ScaleY);
          DrawW  := ImgWidthPt  * Scale;
          DrawH  := ImgHeightPt * Scale;
        end;
    else
      DrawW := Min(ImgWidthPt,  AvailW);
      DrawH := Min(ImgHeightPt, AvailH);
    end;

    DrawX := MarginPt + (AvailW - DrawW) / 2.0;
    DrawY := MarginPt + (AvailH - DrawH) / 2.0;

    PageCount := TccPdfiumLibHelper.FPDF_GetPageCount(ADocument);
    if (APdfPageIndex < 0) or (APdfPageIndex >= PageCount) then
      InsertIdx := PageCount
    else
      InsertIdx := APdfPageIndex;

    Page := TccPdfiumLibHelper.FPDFPage_New(ADocument, InsertIdx, PageW, PageH);
    if Page = nil then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_New fehlgeschlagen']));
    try
      if IsJPEG then
      begin
        // JPEG-Pfad: Jeder Strip als eigenständiges JPEG-Bild einfügen
        CurPixelY := 0;
        for StripIdx := 0 to High(TiffPageInfo.StripOffsets) do
        begin
          JpegData := BuildJpegForStrip(ATiffStream, TiffPageInfo, StripIdx);
          if Length(JpegData) < 4 then Continue;

          // Strip-Höhe berechnen
          StripH := TiffPageInfo.RowsPerStrip;
          if (StripH <= 0) or (StripH > ImgH) then StripH := ImgH;
          if CurPixelY + StripH > ImgH then
            StripH := ImgH - CurPixelY;

          ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
          if ImageObj = nil then Continue;

          JpegBlock.Data := @JpegData[0];
          JpegBlock.Len  := Length(JpegData);
          FillChar(FileAccess, SizeOf(FileAccess), 0);
          FileAccess.m_FileLen  := Length(JpegData);
          FileAccess.m_GetBlock := @JpegReadBlock;
          FileAccess.m_Param    := @JpegBlock;

          if TccPdfiumLibHelper.FPDFImageObj_LoadJpegFileInline(nil, 0, ImageObj, @FileAccess) then
          begin
            // Position: PDF Y=0 ist unten
            StripDrawH := DrawH * StripH / ImgH;
            StripY     := DrawY + DrawH * (ImgH - CurPixelY - StripH) / ImgH;

            TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj,
              DrawW,      0,
              0,          StripDrawH,
              DrawX,      StripY);
            TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
          end;

          Inc(CurPixelY, StripH);
        end;
      end
      else
      begin
        // Bitmap-Pfad (alle anderen Kompressionstypen)
        ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
        if ImageObj = nil then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPageObj_NewImageObj fehlgeschlagen']));

        if not TccPdfiumLibHelper.FPDFImageObj_SetBitmap(nil, 0, ImageObj, Bitmap) then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFImageObj_SetBitmap fehlgeschlagen']));

        TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj, DrawW, 0, 0, DrawH, DrawX, DrawY);
        TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
      end;

      if not TccPdfiumLibHelper.FPDFPage_GenerateContent(Page) then
        raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_GenerateContent fehlgeschlagen']));
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    if Bitmap <> nil then
      TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
  end;
end;

// =========================================================================
//  Öffentliche TIFF → PDF Methoden
// =========================================================================

// ---------------------------------------------------------------------------
//  ParseAllTiffPageInfos
//  Liest alle IFDs in einem einzigen Vorwärts-Durchlauf.
//  Gibt die geparsten TccTiffPageInfo-Strukturen zurück.
// ---------------------------------------------------------------------------
function ParseAllTiffPageInfos(AStream : TStream) : TArray<TccTiffPageInfo>;
var
  Magic     : Word;
  FirstIFD  : UInt32;
  BigEndian : Boolean;
  CurIFD    : UInt32;
  PageInfo  : TccTiffPageInfo;
  Count     : Integer;
begin
  SetLength(Result, 0);
  AStream.Position := 0;
  AStream.Read(Magic, 2);
  if Magic = $4949 then BigEndian := False
  else if Magic = $4D4D then BigEndian := True
  else Exit;
  TiffReadW(AStream, Magic, BigEndian);
  if Magic <> 42 then Exit;
  TiffReadL(AStream, FirstIFD, BigEndian);
  CurIFD := FirstIFD;
  Count  := 0;
  while CurIFD <> 0 do
  begin
    if not ReadTiffPage(AStream, CurIFD, BigEndian, PageInfo) then Break;
    SetLength(Result, Count + 1);
    Result[Count] := PageInfo;
    Inc(Count);
    CurIFD := PageInfo.NextIFDOffset;
  end;
end;

// ---------------------------------------------------------------------------
//  TiffBitmapFromInfo
//  Erzeugt einen PDFium-Bitmap aus einer bereits geparsten TccTiffPageInfo.
//  Vermeidet das erneute Lesen von TIFF-Header und IFD-Kette.
// ---------------------------------------------------------------------------
function TiffBitmapFromInfo(AStream : TStream; const APageInfo : TccTiffPageInfo;
             out AImgW, AImgH, ADPI : Integer) : FPDF_BITMAP;
var
  BitsPerPx    : Integer;
  BytesPerRow  : Integer;
  StripData    : TBytes;
  Decompressed : TBytes;
  RawData      : TBytes;
  RawPos       : Integer;
  StripSize    : Integer;
  Bitmap       : FPDF_BITMAP;
  BufPtr       : PByte;
  Stride       : Integer;
  x, y         : Integer;
  GrayVal      : Byte;
  BitVal       : Boolean;
  i            : Integer;
begin
  Result := nil;
  AImgW := APageInfo.Width;
  AImgH := APageInfo.Height;
  ADPI  := APageInfo.XResDPI;
  if ADPI <= 0 then ADPI := 200;

  if not ((APageInfo.Compression=1) or (APageInfo.Compression=5) or
          (APageInfo.Compression=7) or (APageInfo.Compression=32773)) then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Kompression ' + IntToStr(APageInfo.Compression) + ' nicht unterstützt']));
  if APageInfo.Compression = 7 then Exit; // JPEG: caller handles

  BitsPerPx   := APageInfo.BitsPerSample * APageInfo.SamplesPerPixel;
  if BitsPerPx = 1 then BytesPerRow := (AImgW + 7) shr 3
  else                    BytesPerRow := AImgW * (BitsPerPx shr 3);

  // Strips direkt in TBytes akkumulieren (kein TMemoryStream)
  RawPos := 0;
  SetLength(RawData, BytesPerRow * AImgH + 16);
  for i := 0 to High(APageInfo.StripOffsets) do
  begin
    StripSize := APageInfo.StripByteCounts[i];
    if StripSize <= 0 then Continue;
    SetLength(StripData, StripSize);
    AStream.Position := APageInfo.StripOffsets[i];
    AStream.ReadBuffer(StripData[0], StripSize);
    var StripRows : Integer;
    if i < High(APageInfo.StripOffsets) then StripRows := APageInfo.RowsPerStrip
    else StripRows := AImgH - i * APageInfo.RowsPerStrip;
    if (StripRows <= 0) or (StripRows > AImgH) then StripRows := AImgH;
    case APageInfo.Compression of
      1:     Decompressed := StripData;
      5:     Decompressed := DecompressLZW(StripData, BytesPerRow * StripRows);
      32773: Decompressed := DecompressPackBits(StripData, BytesPerRow * StripRows);
    else     Decompressed := StripData;
    end;
    if Length(Decompressed) > 0 then
    begin
      if RawPos + Length(Decompressed) > Length(RawData) then
        SetLength(RawData, (Length(RawData) + Length(Decompressed)) * 2);
      Move(Decompressed[0], RawData[RawPos], Length(Decompressed));
      Inc(RawPos, Length(Decompressed));
    end;
  end;
  SetLength(RawData, RawPos);

  // Predictor=2
  if (APageInfo.Predictor = 2) and (RawPos > 0) then
  begin
    var BytesPerSample := (APageInfo.BitsPerSample + 7) shr 3;
    var SamplesPerRow  := AImgW * APageInfo.SamplesPerPixel;
    var RowBytes       := SamplesPerRow * BytesPerSample;
    {$R-}{$Q-}
    for y := 0 to AImgH - 1 do
    begin
      var RowOfs := y * RowBytes;
      if RowOfs + RowBytes > Length(RawData) then Break;
      if BytesPerSample = 1 then
        for x := APageInfo.SamplesPerPixel to SamplesPerRow - 1 do
          RawData[RowOfs+x] := (RawData[RowOfs+x] + RawData[RowOfs+x-APageInfo.SamplesPerPixel]) and $FF;
    end;
    {$R+}{$Q+}
  end;

  Bitmap := TccPdfiumLibHelper.FPDFBitmap_Create(AImgW, AImgH, 0);
  if Bitmap = nil then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFBitmap_Create (TIFF→PDF)']));
  try
    BufPtr := TccPdfiumLibHelper.FPDFBitmap_GetBuffer(Bitmap);
    Stride := TccPdfiumLibHelper.FPDFBitmap_GetStride(Bitmap);
    TccPdfiumLibHelper.FPDFBitmap_FillRect(Bitmap, 0, 0, AImgW, AImgH, $FFFFFFFF);

    {$R-}{$Q-}
    var SrcRowPtr : PByte := @RawData[0];
    var DstRowPtr : PByte := BufPtr;
    var SrcPx2, DstPx2 : PByte;
    case BitsPerPx of
      1:
        for y := 0 to AImgH - 1 do
        begin
          SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
          var SrcByte2 : Byte := SrcPx2^; var BitMask2 : Byte := $80;
          for x := 0 to AImgW - 1 do
          begin
            BitVal := (SrcByte2 and BitMask2) <> 0;
            if APageInfo.Photometric <> 0 then BitVal := not BitVal;
            if BitVal then GrayVal := 0 else GrayVal := 255;
            PUInt32(DstPx2)^ := UInt32(GrayVal) or (UInt32(GrayVal) shl 8) or (UInt32(GrayVal) shl 16) or $FF000000;
            Inc(DstPx2, 4);
            BitMask2 := BitMask2 shr 1;
            if BitMask2 = 0 then begin BitMask2 := $80; Inc(SrcPx2); SrcByte2 := SrcPx2^; end;
          end;
          Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
        end;
      8:
        begin
          var NC := Length(APageInfo.ColorMap) div 3;
          var IP := (APageInfo.Photometric = 3) and (NC > 0);
          var MW := (APageInfo.Photometric = 0) and not IP;
          for y := 0 to AImgH - 1 do
          begin
            SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
            for x := 0 to AImgW - 1 do
            begin
              GrayVal := SrcPx2^; Inc(SrcPx2);
              if IP then
              begin
                if GrayVal < NC then
                  PUInt32(DstPx2)^ := (UInt32(APageInfo.ColorMap[2*NC+GrayVal] shr 8)) or
                                      (UInt32(APageInfo.ColorMap[NC+GrayVal]   shr 8) shl 8) or
                                      (UInt32(APageInfo.ColorMap[GrayVal]      shr 8) shl 16) or $FF000000
                else PUInt32(DstPx2)^ := $FF000000;
              end else begin
                if MW then GrayVal := 255 - GrayVal;
                PUInt32(DstPx2)^ := UInt32(GrayVal) or (UInt32(GrayVal) shl 8) or (UInt32(GrayVal) shl 16) or $FF000000;
              end;
              Inc(DstPx2, 4);
            end;
            Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
          end;
        end;
      24:
        for y := 0 to AImgH - 1 do
        begin
          SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
          for x := 0 to AImgW - 1 do
          begin
            var v : UInt32 := PUInt32(SrcPx2)^ and $00FFFFFF;
            PUInt32(DstPx2)^ := ((v shr 16) and $FF) or (v and $FF00) or ((v shl 16) and $FF0000) or $FF000000;
            Inc(SrcPx2, 3); Inc(DstPx2, 4);
          end;
          Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
        end;
      32:
        for y := 0 to AImgH - 1 do
        begin
          SrcPx2 := SrcRowPtr; DstPx2 := DstRowPtr;
          for x := 0 to AImgW - 1 do
          begin
            var v : UInt32 := PUInt32(SrcPx2)^;
            PUInt32(DstPx2)^ := ((v shr 16) and $FF) or (v and $FF00) or ((v shl 16) and $FF0000) or $FF000000;
            Inc(SrcPx2, 4); Inc(DstPx2, 4);
          end;
          Inc(SrcRowPtr, BytesPerRow); Inc(DstRowPtr, Stride);
        end;
    else
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Pixelformat ' + IntToStr(BitsPerPx) + ' Bits nicht unterstützt']));
    end;
    {$R+}{$Q+}
    Result := Bitmap;
  except
    TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
    raise;
  end;
end;

// ---------------------------------------------------------------------------
//  AddTiffPageFromInfo
//  Fügt eine TIFF-Seite aus einer bereits geparsten TccTiffPageInfo ein.
//  Kein erneutes Parsen von TIFF-Header oder IFD-Kette.
// ---------------------------------------------------------------------------
procedure AddTiffPageFromInfo(ADocument : FPDF_DOCUMENT;
            ATiffStream : TStream; const APageInfo : TccTiffPageInfo;
            APdfPageIndex : Integer; const AOptions : TccBmpToPdfOptions);
const
  MM_TO_PT = 72.0 / 25.4;
var
  Bitmap         : FPDF_BITMAP;
  ImgW, ImgH     : Integer;
  TiffDPI        : Integer;
  PageW, PageH   : Double;
  ImgWidthPt     : Double;
  ImgHeightPt    : Double;
  DrawX, DrawY   : Double;
  DrawW, DrawH   : Double;
  MarginPt       : Double;
  AvailW, AvailH : Double;
  Scale          : Double;
  Page           : FPDF_PAGE;
  ImageObj       : Pointer;
  InsertIdx      : Integer;
  DPI            : Integer;
  IsJPEG         : Boolean;
  JpegData       : TBytes;
  FileAccess     : TFPDF_FILEACCESS;
  JpegBlock      : TJpegMemBlock;
  StripIdx       : Integer;
  StripH         : Integer;
  StripDrawH     : Double;
  StripY         : Double;
  CurPixelY      : Integer;
begin
  IsJPEG := (APageInfo.Compression = 7);

  if IsJPEG then
  begin
    ImgW    := APageInfo.Width;
    ImgH    := APageInfo.Height;
    TiffDPI := APageInfo.XResDPI;
    if TiffDPI <= 0 then TiffDPI := 200;
    Bitmap  := nil;
  end
  else
    Bitmap := TiffBitmapFromInfo(ATiffStream, APageInfo, ImgW, ImgH, TiffDPI);

  try
    DPI := AOptions.SourceDPI;
    if DPI <= 0 then DPI := TiffDPI;
    if DPI <= 0 then DPI := 200;

    ImgWidthPt  := ImgW * 72.0 / DPI;
    ImgHeightPt := ImgH * 72.0 / DPI;

    if (AOptions.PageWidthMM > 0) and (AOptions.PageHeightMM > 0) then
    begin
      PageW := AOptions.PageWidthMM * MM_TO_PT;
      PageH := AOptions.PageHeightMM * MM_TO_PT;
    end
    else
    begin
      PageW := ImgWidthPt;
      PageH := ImgHeightPt;
    end;

    MarginPt := AOptions.MarginMM * MM_TO_PT;
    AvailW   := PageW - 2 * MarginPt; if AvailW < 1 then AvailW := PageW;
    AvailH   := PageH - 2 * MarginPt; if AvailH < 1 then AvailH := PageH;

    case AOptions.FitMode of
      bfmStretchToPage:
        begin DrawW := AvailW; DrawH := AvailH; end;
      bfmKeepAspectRatio:
        begin
          Scale := Min(AvailW / ImgWidthPt, AvailH / ImgHeightPt);
          DrawW := ImgWidthPt * Scale; DrawH := ImgHeightPt * Scale;
        end;
    else
      DrawW := Min(ImgWidthPt, AvailW); DrawH := Min(ImgHeightPt, AvailH);
    end;

    DrawX := MarginPt + (AvailW - DrawW) / 2.0;
    DrawY := MarginPt + (AvailH - DrawH) / 2.0;

    InsertIdx := TccPdfiumLibHelper.FPDF_GetPageCount(ADocument);
    if (APdfPageIndex >= 0) and (APdfPageIndex < InsertIdx) then InsertIdx := APdfPageIndex;

    Page := TccPdfiumLibHelper.FPDFPage_New(ADocument, InsertIdx, PageW, PageH);
    if Page = nil then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_New fehlgeschlagen']));
    try
      if IsJPEG then
      begin
        CurPixelY := 0;
        for StripIdx := 0 to High(APageInfo.StripOffsets) do
        begin
          JpegData := BuildJpegForStrip(ATiffStream, APageInfo, StripIdx);
          if Length(JpegData) < 4 then Continue;
          StripH := APageInfo.RowsPerStrip;
          if (StripH <= 0) or (StripH > ImgH) then StripH := ImgH;
          if CurPixelY + StripH > ImgH then StripH := ImgH - CurPixelY;
          ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
          if ImageObj = nil then Continue;
          JpegBlock.Data := @JpegData[0]; JpegBlock.Len := Length(JpegData);
          FillChar(FileAccess, SizeOf(FileAccess), 0);
          FileAccess.m_FileLen  := Length(JpegData);
          FileAccess.m_GetBlock := @JpegReadBlock;
          FileAccess.m_Param    := @JpegBlock;
          if TccPdfiumLibHelper.FPDFImageObj_LoadJpegFileInline(nil, 0, ImageObj, @FileAccess) then
          begin
            StripDrawH := DrawH * StripH / ImgH;
            StripY     := DrawY + DrawH * (ImgH - CurPixelY - StripH) / ImgH;
            TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj, DrawW, 0, 0, StripDrawH, DrawX, StripY);
            TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
          end;
          Inc(CurPixelY, StripH);
        end;
      end
      else
      begin
        ImageObj := TccPdfiumLibHelper.FPDFPageObj_NewImageObj(ADocument);
        if ImageObj = nil then raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPageObj_NewImageObj fehlgeschlagen']));
        if not TccPdfiumLibHelper.FPDFImageObj_SetBitmap(nil, 0, ImageObj, Bitmap) then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFImageObj_SetBitmap fehlgeschlagen']));
        TccPdfiumLibHelper.FPDFPageObj_Transform(ImageObj, DrawW, 0, 0, DrawH, DrawX, DrawY);
        TccPdfiumLibHelper.FPDFPage_InsertObject(Page, ImageObj);
      end;
      if not TccPdfiumLibHelper.FPDFPage_GenerateContent(Page) then
        raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDFPage_GenerateContent fehlgeschlagen']));
    finally
      TccPdfiumLibHelper.FPDF_ClosePage(Page);
    end;
  finally
    if Bitmap <> nil then TccPdfiumLibHelper.FPDFBitmap_Destroy(Bitmap);
  end;
end;

// ----------------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(ASource, ATarget : TStream; const AOptions : TccBmpToPdfOptions) : Integer;
// Opt: Stream in TMemoryStream laden (schnelle Seeks), alle IFDs in EINEM
//      Vorwärts-Durchlauf parsen → O(N) statt O(N²) IFD-Lesevorgänge.
var
  Doc       : FPDF_DOCUMENT;
  PageInfos : TArray<TccTiffPageInfo>;
  MS        : TMemoryStream;
  SrcStream : TStream;
  OwnMS     : Boolean;
  i         : Integer;
begin
  MS := nil;
  // TMemoryStream sicherstellen (schnelle Random-Access-Seeks)
  if ASource is TMemoryStream then
  begin
    SrcStream := ASource; OwnMS := False;
  end
  else
  begin
    MS := TMemoryStream.Create;
    ASource.Position := 0; MS.CopyFrom(ASource, 0);
    SrcStream := MS; OwnMS := True;
  end;

  try
    // Alle IFDs in einem einzigen Vorwärts-Durchlauf parsen
    PageInfos := ParseAllTiffPageInfos(SrcStream);
    if Length(PageInfos) = 0 then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF enthält keine Seiten']));

    Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
    if Doc = nil then
      raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
    try
      for i := 0 to High(PageInfos) do
        AddTiffPageFromInfo(Doc, SrcStream, PageInfos[i], -1, AOptions);

      ATarget.Size := 0;
      SaveDocumentToStream(Doc, ATarget);
      ATarget.Position := 0;
    finally
      TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
    end;
  finally
    if OwnMS then MS.Free;
  end;
  Result := Length(PageInfos);
end;

class function TccPdfiumDocument.TiffToPdf(ATiffStream : TStream; ATarget : TStream) : Integer;
begin
  Result := TiffToPdf(ATiffStream, ATarget, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffFile : String; ATarget : TStream;
            const AOptions : TccBmpToPdfOptions) : Integer;
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(ATiffFile, fmOpenRead or fmShareDenyNone);
  try
    Result := TiffToPdf(FS, ATarget, AOptions);
  finally
    FS.Free;
  end;
end;

// ----------------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffFile : String; ATarget : TStream) : Integer;
begin
  Result := TiffToPdf(ATiffFile, ATarget, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.TiffToPdf(const ATiffFile : String;
            const APdfFile : String; const AOptions : TccBmpToPdfOptions);
var
  Stream : TFileStream;
begin
  Stream := TFileStream.Create(APdfFile, fmCreate);
  try
    TiffToPdf(ATiffFile, Stream, AOptions);
  finally
    FreeAndNil(Stream);
  end;
end;

// ----------------------------------------------------------------------------------
class procedure TccPdfiumDocument.TiffToPdf(const ATiffFile : String;
            const APdfFile : String);
begin
  TiffToPdf(ATiffFile, APdfFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.TiffToPdf(const ATiffFiles : array of String;
            const APdfFile : String; const AOptions : TccBmpToPdfOptions);
var
  Stream : TFileStream;
begin
  Stream := TFileStream.Create(APdfFile, fmCreate);
  try
    TiffToPdf(ATiffFiles, Stream, AOptions);
  finally
    FreeAndNil(Stream);
  end;
end;

// ----------------------------------------------------------------------------------
class procedure TccPdfiumDocument.TiffToPdf(const ATiffFiles : array of String;
            const APdfFile : String);
begin
  TiffToPdf(ATiffFiles, APdfFile, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffFiles : array of String; ATarget : TStream;
            const AOptions : TccBmpToPdfOptions) : Boolean;
var
  Streams : array of TStream;
  i       : Integer;
begin
  if Length(ATiffFiles) = 0 then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Keine TIFF-Dateien angegeben']));

  SetLength(Streams, Length(ATiffFiles));
  for i := 0 to High(ATiffFiles) do
    Streams[i] := nil;
  try
    for i := 0 to High(ATiffFiles) do
    begin
      if not FileExists(ATiffFiles[i]) then
        raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['TIFF-Datei nicht gefunden: ' + ATiffFiles[i]]));
      Streams[i] := TFileStream.Create(ATiffFiles[i], fmOpenRead or fmShareDenyNone);
    end;
    Result := TiffToPdf(Streams, ATarget, AOptions);
  finally
    for i := 0 to High(Streams) do
      Streams[i].Free;
  end;
end;

// ----------------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffFiles : array of String; ATarget : TStream) : Boolean;
begin
  Result := TiffToPdf(ATiffFiles, ATarget, TccBmpToPdfOptions.Default);
end;

// ---------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffStreams : array of TStream; ATarget : TStream;
            const AOptions : TccBmpToPdfOptions) : Boolean;
var
  Doc       : FPDF_DOCUMENT;
  PageInfos : TArray<TccTiffPageInfo>;
  i, p      : Integer;
begin
  if Length(ATiffStreams) = 0 then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Keine TIFF-Streams angegeben']));

  Doc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if Doc = nil then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    for i := 0 to High(ATiffStreams) do
    begin
      // IFDs jedes Streams in einem Durchlauf parsen
      PageInfos := ParseAllTiffPageInfos(ATiffStreams[i]);
      for p := 0 to High(PageInfos) do
        AddTiffPageFromInfo(Doc, ATiffStreams[i], PageInfos[p], -1, AOptions);
    end;
    SaveDocumentToStream(Doc, ATarget);
    ATarget.Position := 0;
    Result := True;
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(Doc);
  end;
end;

// ----------------------------------------------------------------------------------
class function TccPdfiumDocument.TiffToPdf(const ATiffStreams : array of TStream; ATarget : TStream) : Boolean;
begin
  Result := TiffToPdf(ATiffStreams, ATarget, TccBmpToPdfOptions.Default);
end;

// =========================================================================
//  PDF zusammenfügen (Merge)
//  Kern-Methode: MergePdf(array of TStream, TStream)
//  Alle anderen Overloads delegieren hierher.
// =========================================================================

// ---------------------------------------------------------------------------
//  Mehrere PDF-Streams → zusammengefügtes PDF in Ziel-Stream
// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.MergePdf(const ASources : array of TStream; ATarget : TStream);
var
  DestDoc, SrcDoc : FPDF_DOCUMENT;
  SrcBuf          : TMemoryStream;
  i               : Integer;
begin
  if Length(ASources) = 0 then
    exit;

  if not TccPdfiumLibHelper.TryInitialize then
    raise EccException.Create(CCI_MSG_ERR_PIU_UNABLETOLOAD);

  DestDoc := TccPdfiumLibHelper.FPDF_CreateNewDocument();
  if DestDoc = nil then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_CreateNewDocument fehlgeschlagen']));
  try
    for i := 0 to High(ASources) do
    begin
      if ASources[i] = nil then
        raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['PDF-Stream an Index ' + IntToStr(i) + ' ist nil']));

      // Quell-PDF in eigenen Puffer kopieren (FPDF_LoadMemDocument haelt nur
      // einen Zeiger; der Puffer muss bis CloseDocument leben)
      SrcBuf := TMemoryStream.Create;
      try
        ASources[i].Position := 0;
        SrcBuf.CopyFrom(ASources[i], 0);

        SrcDoc := TccPdfiumLibHelper.FPDF_LoadMemDocument(SrcBuf.Memory, SrcBuf.Size, nil);
        if SrcDoc = nil then
          raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Fehler beim Öffnen von PDF-Stream '+IntToStr(i)]));
        try
          // nil = alle Seiten importieren, Index 0-basiert → ans Ende anhängen
          if not TccPdfiumLibHelper.FPDF_ImportPages(DestDoc, SrcDoc, nil,
              TccPdfiumLibHelper.FPDF_GetPageCount(DestDoc)) then
            raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['FPDF_ImportPages fehlgeschlagen']));
        finally
          TccPdfiumLibHelper.FPDF_CloseDocument(SrcDoc);
        end;
      finally
        SrcBuf.Free;
      end;
    end;

    SaveDocumentToStream(DestDoc, ATarget);
    ATarget.Position := 0;
  finally
    TccPdfiumLibHelper.FPDF_CloseDocument(DestDoc);
  end;
end;

// ---------------------------------------------------------------------------
//  Mehrere PDF-Dateien → zusammengefügtes PDF in Ziel-Stream
// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.MergePdf(const AFiles : array of String; ATarget : TStream);
var
  Streams : array of TStream;
  i       : Integer;
begin
  if Length(AFiles) = 0 then
    raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['Keine PDF-Dateien angegeben']));

  SetLength(Streams, Length(AFiles));
  for i := 0 to High(Streams) do
    Streams[i] := nil;
  try
    for i := 0 to High(AFiles) do
    begin
      if not FileExists(AFiles[i]) then
        raise EccException.Create(CCI_MSG_ERR_PIU_INTERNAL.Format(['PDF-Datei nicht gefunden: ' + AFiles[i]]));
      Streams[i] := TFileStream.Create(AFiles[i], fmOpenRead or fmShareDenyNone);
    end;
    MergePdf(Streams, ATarget);
  finally
    for i := 0 to High(Streams) do
      Streams[i].Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Mehrere PDF-Dateien → zusammengefügtes PDF als Datei
// ---------------------------------------------------------------------------
class procedure TccPdfiumDocument.MergePdf(const AFiles : array of String; const ATargetFile : String);
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(ATargetFile, fmCreate);
  try
    MergePdf(AFiles, FS);
  finally
    FS.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Mehrere PDF-Streams → zusammengefügtes PDF als TMemoryStream (Caller gibt frei)
// ---------------------------------------------------------------------------
class function TccPdfiumDocument.MergePdfToStream(const ASources : array of TStream) : TMemoryStream;
begin
  Result := TMemoryStream.Create;
  try
    MergePdf(ASources, Result);
  except
    Result.Free;
    raise;
  end;
end;

// =========================================================================
{ TBmpToPdfOptions }

// ----------------------------------------------------------------------------------
class function TccBmpToPdfOptions.Default : TccBmpToPdfOptions;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FitMode   := bfmKeepAspectRatio;
  Result.SourceDPI := 96;
end;

// ----------------------------------------------------------------------------------
class function TccBmpToPdfOptions.A4Portrait : TccBmpToPdfOptions;
begin
  Result              := Default;
  Result.PageWidthMM  := 210.0;
  Result.PageHeightMM := 297.0;
  Result.MarginMM     := 10.0;
  Result.FitMode      := bfmKeepAspectRatio;
end;

// ----------------------------------------------------------------------------------
class function TccBmpToPdfOptions.A4Landscape : TccBmpToPdfOptions;
begin
  Result              := Default;
  Result.PageWidthMM  := 297.0;
  Result.PageHeightMM := 210.0;
  Result.MarginMM     := 10.0;
  Result.FitMode      := bfmKeepAspectRatio;
end;

// =========================================================================
{ TccWebpOptions }

// ----------------------------------------------------------------------------------
class function TccWebpOptions.Default : TccWebpOptions;
begin
  Result.Mode    := wmLossy;
  Result.Quality := 80.0;
end;

// ----------------------------------------------------------------------------------
class function TccWebpOptions.Lossless : TccWebpOptions;
begin
  Result.Mode    := wmLossless;
  Result.Quality := 100.0;  // bei Lossless ignoriert, aber zur Sicherheit gesetzt
end;

// ----------------------------------------------------------------------------------
class function TccWebpOptions.Lossy(AQuality : Single) : TccWebpOptions;
begin
  Result.Mode    := wmLossy;
  if AQuality <   0 then AQuality :=   0;
  if AQuality > 100 then AQuality := 100;
  Result.Quality := AQuality;
end;

// ==================================================================================
{ TccPdfiumLibHelper }

// ----------------------------------------------------------------------------------
class constructor TccPdfiumLibHelper.Create;
begin
  FLock        := TCriticalSection.Create;
  FInitialized := false;
  FModule      := 0;
end;

// ----------------------------------------------------------------------------------
class destructor TccPdfiumLibHelper.Destroy;
begin
  Finalize;
  FreeAndNil(FLock);
end;

// ----------------------------------------------------------------------------------
class procedure TccPdfiumLibHelper.Finalize;
begin
  FLock.Acquire;
  try
    if FInitialized = true then
    begin
      if Assigned(FPDF_DestroyLibrary)
        then FPDF_DestroyLibrary();

      FreeLibrary(FModule);
      FInitialized := false;
    end;
  finally
    FLock.Release;
  end;
end;

// ----------------------------------------------------------------------------------
class function TccPdfiumLibHelper.TryInitialize: Boolean;

  procedure Bind(var FuncPtr; const Name: string);
  begin
    Pointer(FuncPtr) := GetProcAddress(FModule, PChar(Name));
  end;

begin
  FLock.Acquire;
  try
    if not(FInitialized = true) then
    begin
      FModule := LoadLibrary(PChar(PDFIUM_LIB));
      Result  := FModule <> 0;

      if Result = true then
      begin
        {$REGION 'load Pdfium API using GetProcAddress'}
        Bind(FPDF_InitLibrary,           'FPDF_InitLibrary');
        Bind(FPDF_DestroyLibrary,        'FPDF_DestroyLibrary');
        Bind(FPDF_LoadDocument,          'FPDF_LoadDocument');
        Bind(FPDF_LoadMemDocument,       'FPDF_LoadMemDocument');
        Bind(FPDF_CloseDocument,         'FPDF_CloseDocument');
        Bind(FPDF_GetMetaText,           'FPDF_GetMetaText');
        Bind(FPDF_GetLastError,          'FPDF_GetLastError');
        Bind(FPDF_GetPageCount,          'FPDF_GetPageCount');
        Bind(FPDF_LoadPage,              'FPDF_LoadPage');
        Bind(FPDF_ClosePage,             'FPDF_ClosePage');
        Bind(FPDF_GetPageWidthF,         'FPDF_GetPageWidthF');
        Bind(FPDF_GetPageHeightF,        'FPDF_GetPageHeightF');
        Bind(FPDFBitmap_Create,          'FPDFBitmap_Create');
        Bind(FPDFBitmap_CreateEx,        'FPDFBitmap_CreateEx');
        Bind(FPDFBitmap_FillRect,        'FPDFBitmap_FillRect');
        Bind(FPDFBitmap_GetBuffer,       'FPDFBitmap_GetBuffer');
        Bind(FPDFBitmap_GetWidth,        'FPDFBitmap_GetWidth');
        Bind(FPDFBitmap_GetHeight,       'FPDFBitmap_GetHeight');
        Bind(FPDFBitmap_GetStride,       'FPDFBitmap_GetStride');
        Bind(FPDFBitmap_Destroy,         'FPDFBitmap_Destroy');
        Bind(FPDF_RenderPageBitmap,      'FPDF_RenderPageBitmap');
        Bind(FPDFDoc_GetAttachmentCount, 'FPDFDoc_GetAttachmentCount');
        Bind(FPDFDoc_GetAttachment,      'FPDFDoc_GetAttachment');
        Bind(FPDFAttachment_GetName,     'FPDFAttachment_GetName');
        Bind(FPDFAttachment_GetFile,     'FPDFAttachment_GetFile');
        // Erstellen / Speichern
        Bind(FPDF_CreateNewDocument,          'FPDF_CreateNewDocument');
        Bind(FPDF_SaveAsCopy,                 'FPDF_SaveAsCopy');
        Bind(FPDF_SaveWithVersion,            'FPDF_SaveWithVersion');
        Bind(FPDF_ImportPages,                 'FPDF_ImportPages');
        Bind(FPDFPage_New,                    'FPDFPage_New');
        Bind(FPDFPage_Delete,                 'FPDFPage_Delete');
        Bind(FPDFPage_GenerateContent,        'FPDFPage_GenerateContent');
        Bind(FPDFPage_InsertObject,           'FPDFPage_InsertObject');
        Bind(FPDFPageObj_NewImageObj,         'FPDFPageObj_NewImageObj');
        Bind(FPDFImageObj_LoadJpegFile,       'FPDFImageObj_LoadJpegFile');
        Bind(FPDFImageObj_LoadJpegFileInline, 'FPDFImageObj_LoadJpegFileInline');
        Bind(FPDFImageObj_SetBitmap,          'FPDFImageObj_SetBitmap');
        Bind(FPDFImageObj_GetBitmap,          'FPDFImageObj_GetBitmap');
        Bind(FPDFPageObj_Transform,           'FPDFPageObj_Transform');
        Bind(FPDFPageObj_SetBlendMode,        'FPDFPageObj_SetBlendMode');

        FPDF_InitLibrary;
        {$ENDREGION}

        FInitialized := true;
      end;
    end else Result := true;
  finally
    FLock.Release;
  end;
end;

// ==================================================================================
{ TccWebpLibHelper }

// ----------------------------------------------------------------------------------
class constructor TccWebpLibHelper.Create;
begin
  FLock        := TCriticalSection.Create;
  FInitialized := false;
  FModule      := 0;
end;

// ----------------------------------------------------------------------------------
class destructor TccWebpLibHelper.Destroy;
begin
  Finalize;
  FreeAndNil(FLock);
end;

// ----------------------------------------------------------------------------------
class procedure TccWebpLibHelper.Finalize;
begin
  FLock.Acquire;
  try
    if FInitialized = true then
    begin
      if FModule <> 0 then FreeLibrary(FModule);
      FModule      := 0;
      FInitialized := false;
    end;
  finally
    FLock.Release;
  end;
end;

// ----------------------------------------------------------------------------------
//  Lazy-Init für libwebp.  Liefert True wenn Bibliothek geladen und alle
//  benoetigten Funktionen gebunden sind.  Ein fehlender WebPFree-Eintrag wird
//  toleriert (aeltere libwebp-Versionen exportierten diesen Namen nicht), dann
//  wird stattdessen free() via Windows-CRT verwendet – das ist hier nicht noetig,
//  denn wir koennen den Puffer einfach "leaken lassen" bis der Prozess endet.
//  Praktisch: alle seit 2015 ausgelieferten libwebp-Versionen exportieren WebPFree.
// ----------------------------------------------------------------------------------
class function TccWebpLibHelper.TryInitialize : Boolean;

  procedure Bind(var FuncPtr; const Name : string);
  begin
    Pointer(FuncPtr) := GetProcAddress(FModule, PChar(Name));
  end;

begin
  FLock.Acquire;
  try
    if not(FInitialized = true) then
    begin
      FModule := LoadLibrary(PChar(WEBP_LIB));
      Result  := FModule <> 0;

      if Result = true then
      begin
        {$REGION 'load libwebp API using GetProcAddress'}
        Bind(WebPGetInfo,             'WebPGetInfo');
        Bind(WebPDecodeBGRAInto,      'WebPDecodeBGRAInto');
        Bind(WebPEncodeBGRA,          'WebPEncodeBGRA');
        Bind(WebPEncodeLosslessBGRA,  'WebPEncodeLosslessBGRA');
        Bind(WebPFree,                'WebPFree');
        {$ENDREGION}

        // Pflicht-Exports pruefen.  WebPFree ist optional (s.o.).
        Result := Assigned(WebPGetInfo)
              and Assigned(WebPDecodeBGRAInto)
              and Assigned(WebPEncodeBGRA)
              and Assigned(WebPEncodeLosslessBGRA);

        if not Result then
        begin
          FreeLibrary(FModule);
          FModule := 0;
          Exit;   // FInitialized bleibt false
        end;
      end;

      FInitialized := Result;
    end else Result := true;
  finally
    FLock.Release;
  end;
end;

end.
