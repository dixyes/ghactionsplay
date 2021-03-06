# php dev-pack downloader
function provedir(){
    if (-Not (Test-Path -Path $env:TOOLS_PATH -PathType Container)){
        New-Item -Path $env:TOOLS_PATH -ItemType Container
    }
}

function dlwithhash{
    param (
        $Uri, $Dest, $Hash, $Hashmethod
    )

    for ($i=0; $i -lt $env:MAX_TRY; $i++){
        try{
            Invoke-WebRequest -Uri $Uri -OutFile $Dest
        }catch [System.Net.WebException],[System.IO.IOException]{
            Write-Warning "Failed download ${uri}, try again."
            continue
        }
        
        if($Hashmethod -And -Not $Hash -Eq (Get-FileHash $Dest -Algorithm $Hashmethod).Hash ){
            Write-Warning "Bad checksum, try again."
            continue
        }
        break
    }
    if ($hashmethod -And -Not $hash -Eq (Get-FileHash $dest -Algorithm $Hashmethod).Hash ){
        Write-Warning "Cannot download ${uri}: bad checksum."
        return "failed"
    }
    return "ok"
}
function fetchdevpack(){
    if ($info.$phpver.$phpvar) {
        Write-Host "Found target version on releases, try using latest devpack."
        $latest = $info.$phpver.$phpvar."devel_pack"
        if($latest.sha1){
            $hash = $latest.sha1
            $hashmethod = "SHA1"
        }elseif($latest.sha256){
            $hash = $latest.sha256
            $hashmethod = "SHA256"
        }else{
            Write-Warning "No hash for this file provided or not supported."
        }
        $dest = "$env:TOOLS_PATH\" + ($latest.path)

        if($hashmethod -And (Test-Path $dest -PathType Leaf)){
            if($hashmethod -And $hash -Eq (Get-FileHash $dest -Algorithm $Hashmethod).Hash){
                Write-Host "$dest is already provided, skipping downloading."
                return $dest
            }
        }
        
        provedir
        $ret = dlwithhash -Uri ("https://windows.php.net/downloads/releases/" + ($latest.path)) -Dest $dest -Hash $hash -Hashmethod $hashmethod
        if ("ok" -Eq $ret){
            return $dest
        }
    } else {
        Write-Host "Target version is not active release or failed to download releases info, try fetch instantly."
        $fn = php -r "echo 'php-devel-pack-' . PHP_VERSION . '-' . (PHP_ZTS?'nts-':'') . 'Win32-$phpvcver-$phparch.zip' . PHP_EOL;"
        provedir
        $ret = dlwithhash -Uri "https://windows.php.net/downloads/releases/archives/$fn" -Dest "$env:TOOLS_PATH\$fn"
        if ("ok" -Eq $ret){
            return "$env:TOOLS_PATH\$fn"
        }
    }
}

$phpver = php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION . PHP_EOL;"
$phpvcver = (php -i | Select-String -Pattern 'PHP Extension Build => .+,(.+)' -CaseSensitive -List).Matches.Groups[1]
$phparch = (php -i | Select-String -Pattern 'Architecture => (.+)' -CaseSensitive -List).Matches.Groups[1]
$phpvar = php -r "echo (PHP_ZTS?:'n') . 'ts-$phpvcver-$phparch' . PHP_EOL;"
for ($i=0; $i -lt $env:MAX_TRY; $i++){
    try{
        $info = Invoke-WebRequest -Uri "https://windows.php.net/downloads/releases/releases.json" | ConvertFrom-Json
    }catch [System.Net.WebException],[System.IO.IOException]{
        Write-Warning "Failed to fetch php releases info from windows.php.net, try again."
        continue
    }
    #$info = Invoke-WebRequest -Uri "https://on" | ConvertFrom-Json
    if($info){
        break
    }
}
if(!$info){
    Write-Warning "Cannot fetch php releases info from windows.php.net."
}
$zip = fetchdevpack
if (-Not $zip){
    exit 1
}

Write-Host "Done downloading devpack, unzip it."
try{
    # if possible should we use -PassThru to get file list?
    #Expand-Archive -Path $zip -Destination $env:TOOLS_PATH -Force
}catch {
    Write-Warning "Cannot unzip downloaded zip, that's strange".
    exit 1
}
$sa = New-Object -ComObject Shell.Application
$dirname = ($sa.NameSpace($zip).Items() | Select-Object -Index 0).Name

Write-Host "Done unzipping devpack, generate env.bat."

$content="@echo off
set PATH=$env:TOOLS_PATH\$dirname;%PATH%
call $env:TOOLS_PATH\php-sdk-binary-tools\phpsdk-starter.bat -c $phpvcver -a $phparch %0
"
$content | Out-File -Encoding UTF8 -FilePath $env:TOOLS_PATH\env.bat

Write-Host "Done."
