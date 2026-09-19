param([string]$Family = 'phone')
$ErrorActionPreference = 'Stop'
$adb = Join-Path $PSScriptRoot '../../android-sdk/platform-tools/adb.exe'
$output = Join-Path $PSScriptRoot '../build'
function Read-UI {
    & $adb shell uiautomator dump /sdcard/parity-ui.xml | Out-Null
    & $adb pull /sdcard/parity-ui.xml "$output/android-active-ui.xml" 2>&1 | Out-Null
    [xml](Get-Content "$output/android-active-ui.xml" -Raw -Encoding utf8)
}
function Tap-Node([string]$Selector) {
    $ui = Read-UI
    $node = $ui.SelectSingleNode($Selector)
    if (!$node) { throw "Missing Android node: $Selector" }
    $bounds = [regex]::Matches($node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
    & $adb shell input tap ([int](($bounds[0] + $bounds[2]) / 2)) ([int](($bounds[1] + $bounds[3]) / 2))
}
function Capture([string]$Scene) {
    $null = Read-UI
    Copy-Item "$output/android-active-ui.xml" "$output/android-$Scene-$Family-ui.xml"
    & $adb shell screencap -p /sdcard/parity.png
    & $adb pull /sdcard/parity.png "$output/android-$Scene-$Family.png" 2>&1 | Out-Null
    Write-Output "Captured Android $Family $Scene"
}
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/gb_hudong"]'
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/my_cmds_12"]'
Capture 'common'
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/my_cmds_1"]'
Capture 'inventory'
Tap-Node '//node[@text="布衣"]'
Capture 'item'
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/gb_hudong"]'
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/my_cmds_14"]'
Capture 'player'
Tap-Node '//node[@resource-id="com.zwyouto.localtest:id/gb_hudong"]'
Tap-Node '//node[@text="老村长"]'
Capture 'npc'
