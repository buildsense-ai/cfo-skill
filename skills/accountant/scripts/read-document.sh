#!/usr/bin/env bash
# read-document.sh — Extract text from PDF or image files
# Usage: bash scripts/read-document.sh <file_path>
# Supports: PDF, PNG, JPG, JPEG, TIFF, BMP

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: read-document.sh <file_path>"
  echo "Supports: PDF, PNG, JPG, JPEG, TIFF, BMP"
  exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
  echo "ERROR: File not found: $FILE_PATH"
  exit 1
fi

EXT="${FILE_PATH##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

echo "Processing: $FILE_PATH"
echo "Type: $EXT_LOWER"
echo "---"

case "$EXT_LOWER" in
  pdf)
    # Try pdftotext first (poppler-utils)
    if command -v pdftotext &>/dev/null; then
      pdftotext -layout "$FILE_PATH" -
    # Fallback to python
    elif command -v python3 &>/dev/null; then
      python3 -c "
try:
    import subprocess
    result = subprocess.run(
        ['python3', '-m', 'pymupdf', 'convert', '-output', '/dev/stdout', '$FILE_PATH'],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(result.stdout)
    else:
        raise Exception('pymupdf failed')
except:
    try:
        from PyPDF2 import PdfReader
        reader = PdfReader('$FILE_PATH')
        for page in reader.pages:
            text = page.extract_text()
            if text:
                print(text)
    except ImportError:
        print('ERROR: No PDF reader available.')
        print('Install one: brew install poppler  OR  pip install PyPDF2')
"
    else
      echo "ERROR: No PDF reader available."
      echo "Install: brew install poppler"
      exit 1
    fi
    ;;

  png|jpg|jpeg|tiff|bmp|webp)
    # Try tesseract OCR first
    if command -v tesseract &>/dev/null; then
      tesseract "$FILE_PATH" stdout 2>/dev/null
    # Fallback to python with pytesseract or easyocr
    elif command -v python3 &>/dev/null; then
      python3 -c "
try:
    from PIL import Image
    import pytesseract
    img = Image.open('$FILE_PATH')
    text = pytesseract.image_to_string(img)
    print(text)
except ImportError:
    try:
        import easyocr
        reader = easyocr.Reader(['en','ch_sim'])
        results = reader.readtext('$FILE_PATH')
        for (_, text, _) in results:
            print(text)
    except ImportError:
        print('ERROR: No OCR engine available.')
        print('Install: brew install tesseract  OR  pip install pytesseract pillow')
"
    else
      echo "ERROR: No OCR engine available."
      echo "Install: brew install tesseract"
      exit 1
    fi
    ;;

  *)
    echo "ERROR: Unsupported file type: $EXT_LOWER"
    echo "Supported: pdf, png, jpg, jpeg, tiff, bmp, webp"
    exit 1
    ;;
esac
