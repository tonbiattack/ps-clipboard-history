[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\tray-icon.ico')
)

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

# Draws a simple clipboard glyph so the tray icon is easy to spot among other apps.
function New-ClipboardGlyphBitmap {
    param([Parameter(Mandatory = $true)][int] $Size)

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $scale = $Size / 32.0
        $boardColor = [System.Drawing.Color]::FromArgb(255, 37, 99, 176)
        $paperColor = [System.Drawing.Color]::FromArgb(255, 247, 249, 252)
        $clipColor  = [System.Drawing.Color]::FromArgb(255, 24, 66, 128)
        $lineColor  = [System.Drawing.Color]::FromArgb(255, 120, 150, 190)

        $boardRect = [System.Drawing.RectangleF]::new(4 * $scale, 6 * $scale, 24 * $scale, 23 * $scale)
        $boardRadius = 3 * $scale
        $boardPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $boardPath.AddArc($boardRect.X, $boardRect.Y, $boardRadius * 2, $boardRadius * 2, 180, 90)
        $boardPath.AddArc($boardRect.Right - $boardRadius * 2, $boardRect.Y, $boardRadius * 2, $boardRadius * 2, 270, 90)
        $boardPath.AddArc($boardRect.Right - $boardRadius * 2, $boardRect.Bottom - $boardRadius * 2, $boardRadius * 2, $boardRadius * 2, 0, 90)
        $boardPath.AddArc($boardRect.X, $boardRect.Bottom - $boardRadius * 2, $boardRadius * 2, $boardRadius * 2, 90, 90)
        $boardPath.CloseFigure()
        $graphics.FillPath([System.Drawing.SolidBrush]::new($boardColor), $boardPath)

        $paperRect = [System.Drawing.RectangleF]::new(7 * $scale, 9 * $scale, 18 * $scale, 18 * $scale)
        $graphics.FillRectangle([System.Drawing.SolidBrush]::new($paperColor), $paperRect)

        $clipRect = [System.Drawing.RectangleF]::new(11 * $scale, 3 * $scale, 10 * $scale, 6 * $scale)
        $graphics.FillRectangle([System.Drawing.SolidBrush]::new($clipColor), $clipRect)

        $pen = [System.Drawing.Pen]::new($lineColor, [Math]::Max(1.0, 1.6 * $scale))
        $y = 13 * $scale
        for ($i = 0; $i -lt 3; $i++) {
            $graphics.DrawLine($pen, 9 * $scale, $y, 21 * $scale, $y)
            $y += 4 * $scale
        }
    }
    finally {
        $graphics.Dispose()
    }
    return $bitmap
}

# Windows Vista+ .ico files may embed PNG-encoded frames, which keeps this pure PowerShell.
function New-IconFile {
    param(
        [Parameter(Mandatory = $true)][int[]] $Sizes,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $pngFrames = foreach ($size in $Sizes) {
        $bitmap = New-ClipboardGlyphBitmap -Size $size
        try {
            $stream = [System.IO.MemoryStream]::new()
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
        }
        finally {
            $bitmap.Dispose()
        }
    }

    $headerSize = 6
    $entrySize = 16
    $offset = $headerSize + ($entrySize * $pngFrames.Count)

    $fileStream = [System.IO.File]::Create($Path)
    try {
        $writer = [System.IO.BinaryWriter]::new($fileStream)
        $writer.Write([uint16]0)   # reserved
        $writer.Write([uint16]1)   # type: icon
        $writer.Write([uint16]$pngFrames.Count)

        foreach ($frame in $pngFrames) {
            $dimensionByte = if ($frame.Size -ge 256) { 0 } else { [byte]$frame.Size }
            $writer.Write([byte]$dimensionByte) # width
            $writer.Write([byte]$dimensionByte) # height
            $writer.Write([byte]0)              # color palette
            $writer.Write([byte]0)              # reserved
            $writer.Write([uint16]1)            # color planes
            $writer.Write([uint16]32)            # bits per pixel
            $writer.Write([uint32]$frame.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }

        foreach ($frame in $pngFrames) {
            $writer.Write($frame.Bytes)
        }
        $writer.Flush()
    }
    finally {
        $fileStream.Dispose()
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

New-IconFile -Sizes @(16, 32, 48, 256) -Path $OutputPath
Write-Host "Created tray icon: $OutputPath"
