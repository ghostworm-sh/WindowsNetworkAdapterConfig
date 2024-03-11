# ����Ƿ��Թ���ԱȨ������
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "���Թ���ԱȨ�����д˽ű���"
#    Start-Sleep -Seconds 5
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-File", $MyInvocation.MyCommand.Path)
    exit
}

function Convert-PrefixLengthToSubnetMask {
    param (
        [int]$PrefixLength
    )

    # ��ʼ��������������
    $subnetMask = @(0, 0, 0, 0)

    # ����ǰ׺�����������������ֵ
    for ($i = 0; $i -lt 4; $i++) {
        if ($PrefixLength -ge 8) {
            $subnetMask[$i] = 255
            $PrefixLength -= 8
        }
        elseif ($PrefixLength -gt 0) {
            $subnetMask[$i] = ([Math]::Pow(2, 8) - [Math]::Pow(2, 8 - $PrefixLength))
            $PrefixLength = 0
        }
    }

    # ��������������ת��Ϊ���������ַ���
    $subnetMaskString = $subnetMask -join '.'
    return $subnetMaskString
}



function Convert-SubnetMaskToPrefixLength {
    param (
        [string]$SubnetMask
    )

    # ����������ת��Ϊǰ׺����
    $subnetParts = $SubnetMask.Split('.')
    $prefixLength = 0
    foreach ($part in $subnetParts) {
        $partValue = [int]$part
        $binaryPart = [Convert]::ToString($partValue, 2)
        $prefixLength += $binaryPart.Replace('0', '').Length
    }
    return $prefixLength
}


function Convert-IPAddressToInteger {
    param (
        [string]$IPAddress
    )

    $ipParts = $IPAddress.Split('.')
    $ipInteger = 0
    for ($i = 0; $i -lt 4; $i++) {
        $ipInteger = $ipInteger -bor ($ipParts[$i] -shl ((3 - $i) * 8))
    }
    return $ipInteger
}

function Validate-IPAddress {
    param (
        [string]$IPAddress,
        [string]$SubnetMask
    )

    $ipInteger = Convert-IPAddressToInteger -IPAddress $IPAddress
    $subnetInteger = Convert-IPAddressToInteger -IPAddress $SubnetMask

    # ���������ַ�͹㲥��ַ
    $networkAddress = $ipInteger -band $subnetInteger
    $broadcastAddress = $networkAddress -bor -bnot $subnetInteger

    # ����������ַ��Χ
    $hostAddressMin = $networkAddress + 1
    $hostAddressMax = $broadcastAddress - 1

    # �ж�IP��ַ�Ƿ���������ַ��Χ��
    if ($ipInteger -ge $hostAddressMin -and $ipInteger -le $hostAddressMax) {
        return $true
    }
    return $false
}

do {
    # �г���������
    $networkAdapters = Get-NetAdapter | Select-Object -Property Name, InterfaceDescription, InterfaceIndex, Status

    # ��ʾ�����б�ѡ��
    Write-Host "��ѡ��Ҫ�޸ĵ�������"
    for ($i = 0; $i -lt $networkAdapters.Count; $i++) {
        Write-Host "$($i + 1): $($networkAdapters[$i].Name) - $($networkAdapters[$i].InterfaceDescription)"
    }
    Write-Host "q: �˳��ű�"

    # ѡ������
    $selectedIndex = Read-Host "������Ҫ�޸ĵ����������"
    
    #����q�˳��ű�
    if ($selectedIndex -eq "q") {
        exit
    }
    else {
        #����������Чֵ�ظ�ѭ��
        if ($selectedIndex -lt 1 -or $selectedIndex -gt $networkAdapters.Count ) {
        Write-Host "��Ч��ѡ��"
        continue
        }
    }
    
    # ��ȡѡ�����������
    $selectedAdapter = $networkAdapters[$selectedIndex - 1]

    # ��������Ƿ�������
    if ($selectedAdapter.Status -ne 'Up') {
        Write-Host "ѡ�������δ���á�"
        continue
    }

    # ��ȡѡ��������� InterfaceIndex
    $interfaceIndex = $selectedAdapter.InterfaceIndex

    # ��ʾ�˵���ѡ��
    Write-Host "ѡ�������"
    Write-Host "1. �޸�����"
    Write-Host "2. �ָ�����"
    Write-Host "3. ��Ӿ�̬·��"
    Write-Host "q. �˳��ű�"

    # ѡ�����
    $action = Read-Host "������Ҫִ�еĲ���"

    # ִ��ѡ��Ĳ���
    switch ($action) {
        1 {
            # ִ���޸���������
            # �����������������
            Get-NetIPAddress -InterfaceIndex $interfaceIndex | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $interfaceIndex | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue

            # ��ȡҪ���õ��� IP ��ַ������ǰ׺���Ȼ���������
            $newIPAddress = Read-Host "�������µ� IP ��ַ"
            $newSubnetOrPrefix = Read-Host "����������ǰ׺���Ȼ���������"

            # �ж��������ǰ׺���Ȼ�����������
            if ($newSubnetOrPrefix -match '^\d+$') {
                # ����Ϊǰ׺����
                $newPrefixLength = [int]$newSubnetOrPrefix
                $newSubnetMask = Convert-PrefixLengthToSubnetMask -PrefixLength $newPrefixLength
            }
            else {
                # ����Ϊ��������
                $newSubnetMask = $newSubnetOrPrefix
                $newPrefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $newSubnetMask
            }

            # ��֤ IP ��ַ�����������Ƿ�ƥ��
            while (-not (Validate-IPAddress -IPAddress $newIPAddress -SubnetMask $newSubnetMask)) {
                Write-Host "IP ��ַ����������Χ�ڣ����������롣"
                $newIPAddress = Read-Host "�������µ� IP ��ַ"
                $newSubnetOrPrefix = Read-Host "����������ǰ׺���Ȼ���������"

                # �ж��������ǰ׺���Ȼ�����������
                if ($newSubnetOrPrefix -match '^\d+$') {
                    # ����Ϊǰ׺����
                    $newPrefixLength = [int]$newSubnetOrPrefix
                    $newSubnetMask = Convert-PrefixLengthToSubnetMask -PrefixLength $newPrefixLength
                }
                else {
                    # ����Ϊ��������
                    $newSubnetMask = $newSubnetOrPrefix
                    $newPrefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $newSubnetMask
                }
            }

            # ��ȡҪ���õ�������
            $newGateway = Read-Host "�������µ����� (��ѡ)"

            # ʹ���� IP ��ַ������������������
            New-NetIPAddress -InterfaceIndex $interfaceIndex -IPAddress $newIPAddress -PrefixLength $newPrefixLength | Out-Null

            # ������������أ�����м�鲢��������
            while ($true) {
                if ($newGateway -eq "") {
                    break
                }

                # ��ȡIP��ַ���������롢���ص�������ʾ��ʽ
                $ipInteger = Convert-IPAddressToInteger -IPAddress $newIPAddress
                $subnetInteger = Convert-IPAddressToInteger -IPAddress $newSubnetMask
                $gatewayInteger = Convert-IPAddressToInteger -IPAddress $newGateway

                # ��ȡ�����ַ��������ʾ��ʽ
                $networkAddressInteger = $ipInteger -band $subnetInteger

                # �������ص������ַ
                $gatewayNetworkAddressInteger = $gatewayInteger -band $subnetInteger

                # ��������Ƿ��� IP ��ַ��ͬһ�����У�����ȷ�����ز��������IP��ַ
                if ($networkAddressInteger -ne $gatewayNetworkAddressInteger -or $gatewayInteger -eq $ipInteger) {
                    Write-Host "����������� IP ��ַ����ͬһ�����л����� IP ��ַ��ͬ�����������롣"
                    $newGateway = Read-Host "�������µ�����"
                } else {
                    Write-Host "1. ����Ĭ��·��"
                    Write-Host "2. ���þ�̬·��"
                    # ѡ�����
                    $action = Read-Host "������Ҫִ�еĲ���"

                    # ִ��ѡ��Ĳ���
                    switch ($action) {
                        1 {
                            # ��������
                            New-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix "0.0.0.0/0" -NextHop $newGateway
                            
                            break
                        }
                        2 {
                            # ���þ�̬·��
                            $staticRouteSelected = "Y"
                            while ($staticRouteSelected -eq "Y") {
                                $destinationNetwork = Read-Host "������Ŀ�������ַ��ǰ׺���� (���磺192.168.1.0/24)"

                                # ��Ӿ�̬·��
                                New-NetRoute -DestinationPrefix $destinationNetwork -InterfaceIndex $interfaceIndex -NextHop $newGateway

                                Write-Host "��̬·�������á�"
                                $staticRouteSelected = Read-Host "�Ƿ�������(Y/N,default=N)?"
                                }
                            break
                        }               
                        default {
                            Write-Host "�����ֵ��Ч"
                        }
                    }
                    break
                }
            }


            # ��ȡҪ���õ��� DNS ��ַ
            $newDNS = Read-Host "�������� DNS ��ַ���Կո�ָ� (��ѡ)"

            # ������� DNS ��ַ�ַ����ָ�Ϊ����
            $newDNS = $newDNS.Split(" ")

            # ��������� DNS ��ַ�������� DNS
            if ($newDNS -ne "") {
                Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $newDNS
            }

            Write-Host "���������Ѹ��¡�"

            #�鿴���º������
            Start-Sleep -Seconds 4
            netsh interface ipv4 show config name=$interfaceIndex
        
            break
        }
        2 {
            # �ָ�������Ĭ������

            # �����������������
            Get-NetIPAddress -InterfaceIndex $interfaceIndex | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $interfaceIndex | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue

            Write-Host "���������ѻָ���Ĭ�����á�"

            #�鿴�ָ��������
            Start-Sleep -Seconds 4
            netsh interface ipv4 show config name=$interfaceIndex

            break
        }
        3 {

            # ���þ�̬·��

            # ��ȡҪ���õ�Ŀ�����������
            $staticRouteSelected = "Y"
            while ($staticRouteSelected -eq "Y") {
                $destinationNetwork = Read-Host "������Ŀ�������ַ��ǰ׺���� (���磺192.168.1.0/24)"
                $gateway = Read-Host "���������ص�ַ"
                # ��Ӿ�̬·��
                New-NetRoute -DestinationPrefix $destinationNetwork -InterfaceIndex $interfaceIndex -NextHop $gateway

                Write-Host "��̬·�������á�"
                $staticRouteSelected = Read-Host "�Ƿ�������(Y/N,default=N)?"
                }
            
            # ���·�ɱ�
            Get-NetRoute -InterfaceIndex $interfaceIndex

            break
        }
        q {
            #�˳��ű�
            exit
        }
        default {
            Write-Host "��Ч��ѡ���������롣"
        }
    }
} while ($true)