# One-time setup: makes Good Frames' release signing key, and the
# android\key.properties file that tells the build where the key is.
#
# Run it from the project folder:
#   powershell -ExecutionPolicy Bypass -File tool\make_release_key.ps1
#
# You choose the password. It's never shown on screen or put on a command
# line; it's written only into android\key.properties, which git ignores.

$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
$keyFile = Join-Path $env:USERPROFILE 'keys\goodframes-release.jks'
$propertiesFile = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\android\key.properties'))

if (-not (Test-Path $keytool)) {
    throw "keytool isn't at $keytool. It comes with Android Studio."
}
# Never replace an existing key: it might be the only copy.
if (Test-Path $keyFile) {
    throw "$keyFile already exists, so there's a key already. Nothing was changed."
}
if (Test-Path $propertiesFile) {
    throw "android\key.properties already exists. Nothing was changed."
}

Write-Host ''
Write-Host 'This makes the key that proves Good Frames updates come from you.'
Write-Host ''
$name = Read-Host 'Your name (it goes in every APK, where anyone can read it)'
# Drop characters that mean something special in a certificate's name.
$name = ($name -replace '[,+="<>#;\\]', '').Trim()
if ($name -eq '') { throw 'A name is needed. Nothing was created.' }

function Read-Password([string]$prompt) {
    $secure = Read-Host $prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host ''
Write-Host 'Now choose a password. Nothing appears while you type; that is normal.'
$password = Read-Password 'Password (at least 8 characters)'
if ($password -ne (Read-Password 'Same password again')) {
    throw "The two passwords don't match. Nothing was created."
}
if ($password.Length -lt 8) {
    throw 'The password needs at least 8 characters. Nothing was created.'
}
# key.properties is read as plain text in which a backslash is special, so
# keep to keyboard letters, digits and symbols, without spaces or backslash.
if ($password -notmatch '^[\x21-\x7E]+$' -or $password.Contains('\')) {
    throw 'Use only letters, digits and keyboard symbols (no spaces or \). Nothing was created.'
}

New-Item -ItemType Directory -Force (Split-Path $keyFile) | Out-Null
# Hand keytool the password in an environment variable rather than on its
# command line, where other programs could read it.
$env:GOODFRAMES_KEY_PASSWORD = $password
try {
    & $keytool -genkeypair -keystore $keyFile -alias goodframes `
        -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=$name" `
        -storepass:env GOODFRAMES_KEY_PASSWORD -keypass:env GOODFRAMES_KEY_PASSWORD
    $made = $LASTEXITCODE -eq 0
} finally {
    Remove-Item Env:GOODFRAMES_KEY_PASSWORD
}
if (-not $made) { throw 'keytool failed (see above). Nothing was saved.' }

# Forward slashes, because a backslash is special in this file format.
[IO.File]::WriteAllLines($propertiesFile, [string[]]@(
    '# Made by tool\make_release_key.ps1. Holds a password: never commit it.',
    "storeFile=$($keyFile.Replace('\', '/'))",
    "storePassword=$password",
    'keyAlias=goodframes',
    "keyPassword=$password"
))

Write-Host ''
Write-Host 'Done. Two files were made:'
Write-Host "  The key itself:       $keyFile"
Write-Host "  Where the key is:     $propertiesFile"
& git -C (Split-Path $propertiesFile) check-ignore -q key.properties
if ($LASTEXITCODE -eq 0) {
    Write-Host '  (git ignores key.properties, so it can never be committed.)'
} else {
    Write-Warning 'git is NOT ignoring android\key.properties. Do not commit it!'
}
Write-Host ''
Write-Host 'Last step: back up the key file AND the password somewhere safe'
Write-Host '(a USB stick or cloud drive for the file, a password manager or paper'
Write-Host 'for the password). Without both, phones can never update the app.'
