unit PdfiumApi;

{
  PDFium API-Bindungen für Delphi (Windows und Linux)
  Unterstützte Plattformen: Win32, Win64, Linux64
}

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils;

const
{$IF Defined(MSWINDOWS)}
  PDFIUM_LIB = 'pdfium.dll';
{$ELSEIF Defined(LINUX)}
  PDFIUM_LIB = 'libpdfium.so';
{$ELSE}
  {$MESSAGE Fatal 'Unsupported platform'}
{$ENDIF}

  // FPDF_ERR_*
  FPDF_ERR_SUCCESS  = 0;
  FPDF_ERR_UNKNOWN  = 1;
  FPDF_ERR_FILE     = 2;
  FPDF_ERR_FORMAT   = 3;
  FPDF_ERR_PASSWORD = 4;
  FPDF_ERR_SECURITY = 5;
  FPDF_ERR_PAGE     = 6;

  // Rendering flags
  FPDF_ANNOT           = $01;
  FPDF_LCD_TEXT        = $02;
  FPDF_NO_NATIVETEXT   = $04;
  FPDF_GRAYSCALE       = $08;
  FPDF_REVERSE_BYTE_ORDER = $10;
  FPDF_PRINTING        = $800;

  // Bitmap formats
  FPDFBitmap_Unknown = 0;
  FPDFBitmap_Gray    = 1;
  FPDFBitmap_BGR     = 2;
  FPDFBitmap_BGRx    = 3;
  FPDFBitmap_BGRA    = 4;

type
  FPDF_BOOL        = Integer;
  FPDF_DOCUMENT    = Pointer;
  FPDF_PAGE        = Pointer;
  FPDF_BITMAP      = Pointer;
  FPDF_ATTACHMENT  = Pointer;
  FPDF_FILEWRITE   = Pointer;

  PFS_MATRIX = ^FS_MATRIX;
  FS_MATRIX = record
    a, b, c, d, e, f: Single;
  end;

  PFS_RECTF = ^FS_RECTF;
  FS_RECTF = record
    left, top, right, bottom: Single;
  end;

  // Schreibstruktur für FPDF_SaveAsCopy
  PFPDF_FILEWRITE = ^TFPDF_FILEWRITE;
  TFPDF_FILEWRITE = record
    version: Integer;
    WriteBlock: function(pThis: PFPDF_FILEWRITE; pData: Pointer; size: LongWord): Integer; cdecl;
  end;

// ---------------------------------------------------------------------------
// Bibliothek initialisieren / freigeben
// ---------------------------------------------------------------------------
procedure FPDF_InitLibrary; cdecl; external PDFIUM_LIB;
procedure FPDF_DestroyLibrary; cdecl; external PDFIUM_LIB;

// ---------------------------------------------------------------------------
// Dokument öffnen / schließen
// ---------------------------------------------------------------------------
function  FPDF_LoadDocument(file_path: PAnsiChar; password: PAnsiChar): FPDF_DOCUMENT; cdecl; external PDFIUM_LIB;
function  FPDF_LoadMemDocument(data_buf: Pointer; size: Integer; password: PAnsiChar): FPDF_DOCUMENT; cdecl; external PDFIUM_LIB;
procedure FPDF_CloseDocument(document: FPDF_DOCUMENT); cdecl; external PDFIUM_LIB;
function  FPDF_GetLastError: LongWord; cdecl; external PDFIUM_LIB;
function  FPDF_GetPageCount(document: FPDF_DOCUMENT): Integer; cdecl; external PDFIUM_LIB;

// ---------------------------------------------------------------------------
// Seiten
// ---------------------------------------------------------------------------
function  FPDF_LoadPage(document: FPDF_DOCUMENT; page_index: Integer): FPDF_PAGE; cdecl; external PDFIUM_LIB;
procedure FPDF_ClosePage(page: FPDF_PAGE); cdecl; external PDFIUM_LIB;
function  FPDF_GetPageWidthF(page: FPDF_PAGE): Single; cdecl; external PDFIUM_LIB;
function  FPDF_GetPageHeightF(page: FPDF_PAGE): Single; cdecl; external PDFIUM_LIB;

// ---------------------------------------------------------------------------
// Bitmap
// ---------------------------------------------------------------------------
function  FPDFBitmap_Create(width, height, alpha: Integer): FPDF_BITMAP; cdecl; external PDFIUM_LIB;
function  FPDFBitmap_CreateEx(width, height, format: Integer; first_scan: Pointer; stride: Integer): FPDF_BITMAP; cdecl; external PDFIUM_LIB;
procedure FPDFBitmap_FillRect(bitmap: FPDF_BITMAP; left, top, width, height: Integer; color: LongWord); cdecl; external PDFIUM_LIB;
procedure FPDF_RenderPageBitmap(bitmap: FPDF_BITMAP; page: FPDF_PAGE; start_x, start_y, size_x, size_y: Integer; rotate: Integer; flags: Integer); cdecl; external PDFIUM_LIB;
function  FPDFBitmap_GetBuffer(bitmap: FPDF_BITMAP): Pointer; cdecl; external PDFIUM_LIB;
function  FPDFBitmap_GetWidth(bitmap: FPDF_BITMAP): Integer; cdecl; external PDFIUM_LIB;
function  FPDFBitmap_GetHeight(bitmap: FPDF_BITMAP): Integer; cdecl; external PDFIUM_LIB;
function  FPDFBitmap_GetStride(bitmap: FPDF_BITMAP): Integer; cdecl; external PDFIUM_LIB;
procedure FPDFBitmap_Destroy(bitmap: FPDF_BITMAP); cdecl; external PDFIUM_LIB;

// ---------------------------------------------------------------------------
// Anhänge (Embedded Files / Attachments)
// ---------------------------------------------------------------------------
function  FPDFDoc_GetAttachmentCount(document: FPDF_DOCUMENT): Integer; cdecl; external PDFIUM_LIB;
function  FPDFDoc_GetAttachment(document: FPDF_DOCUMENT; index: Integer): FPDF_ATTACHMENT; cdecl; external PDFIUM_LIB;
function  FPDFAttachment_GetName(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: LongWord): LongWord; cdecl; external PDFIUM_LIB;
function  FPDFAttachment_GetFile(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: LongWord; out_buflen: PLongWord): FPDF_BOOL; cdecl; external PDFIUM_LIB;

implementation

end.
