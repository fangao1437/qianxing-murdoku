# preview.ps1 — render labelled previews of candidate sprites and tile them into one contact sheet.
# Magenta padding makes transparent regions obvious; 3x upscale makes small sprites legible.
$FF = "C:\Users\18182\AppData\Local\Temp\ffs\node_modules\ffmpeg-static\ffmpeg.exe"
$ids = @(107001,107003,107007,107062,107231,107236,107239,107241,107249,107303,107304,107402)
$outDir = "tools\qx\out\preview"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Remove-Item "$outDir\*.png" -ErrorAction SilentlyContinue

foreach ($id in $ids) {
  $src = "tools\qx\sprites\2\$id.png"
  $vf = "scale=iw*3:ih*3:flags=neighbor,scale=w=300:h=300:force_original_aspect_ratio=decrease:flags=lanczos," +
        "pad=320:320:(ow-iw)/2:(oh-ih)/2:color=magenta," +
        "drawtext=fontfile='C\:/Windows/Fonts/arial.ttf':text='$id':x=8:y=8:fontsize=30:fontcolor=yellow:box=1:boxcolor=black@0.7"
  & $FF -y -loglevel error -i $src -vf $vf "$outDir\$id.png"
}

# tile 4x3 into a single sheet (glob input is sorted, so column order == id ascending)
& $FF -y -loglevel error -pattern_type glob -i "$outDir/*.png" -vf "tile=4x3" "tools\qx\out\contact_sheet.png"
Write-Output "sheet: $((Get-Item 'tools\qx\out\contact_sheet.png').Length) bytes"
