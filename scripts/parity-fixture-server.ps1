param([int]$Port = 16666)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
$esc = [char]27
function Send-Line([string]$line) {
    $writer.WriteLine($line)
    $writer.Flush()
    Start-Sleep -Milliseconds 150
}
function Send-World {
    Send-Line "${esc}002未明谷"
    Send-Line "${esc}004这里是未明谷。清溪沿着山脚流过，石阶通向村中。"
    Send-Line "${esc}005老村长:look elder`$zj#村民:look villager"
    Send-Line "${esc}003south:青石桥:south`$zj#north:山路:north"
    Send-Line "${esc}012`$2,2,22,35#气血:80/100:#aa3300:hp║内力:50/100:#0000aa:hp"
    Send-Line "${esc}[2J你来到未明谷。"
    Send-Line '老村长向你点了点头。'
}
try {
    Write-Output "Fixture listening on loopback:$Port"
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        try {
            Send-Line 'ver1.0,parity'
            $null = $reader.ReadLine()
            Send-Line '版本验证成功'
            $null = $reader.ReadLine()
            Send-Line "${esc}0000007"
            Start-Sleep -Seconds 2
            Send-World
            while ($null -ne ($command = $reader.ReadLine())) {
                if ($command -in @('look', 'l', 'north', 'south')) { Send-World }
                elseif ($command -eq 'look elder') {
                    Send-Line "${esc}007${esc}[1;32m老村长${esc}[0m`$br#你想打听什么？"
                    Send-Line "${esc}008`$2,3,9,30#交谈|未明谷的故事:ask elder`$zj#交易|查看随身物品:list elder"
                }
                elseif ($command -eq 'ask elder') { Send-Line "${esc}001你想对老村长说些什么？`$zj#say `$txt#" }
                elseif ($command -eq 'score') {
                    Send-Line "${esc}010#ffffff你获得了村长赠送的礼物。`$br#`$exp#经验 100`$br#`$god#银两 10`$br#`$obj#gift,missing,2`$dh#ok11.accept`$dh#no11.cancel"
                }
            }
        } finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
