# 检查是否以管理员权限运行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "请以管理员权限运行此脚本。"
#    Start-Sleep -Seconds 5
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-File", $MyInvocation.MyCommand.Path)
    exit
}

function Convert-PrefixLengthToSubnetMask {
    param (
        [int]$PrefixLength
    )

    # 初始化子网掩码数组
    $subnetMask = @(0, 0, 0, 0)

    # 根据前缀长度设置子网掩码的值
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

    # 将子网掩码数组转换为子网掩码字符串
    $subnetMaskString = $subnetMask -join '.'
    return $subnetMaskString
}



function Convert-SubnetMaskToPrefixLength {
    param (
        [string]$SubnetMask
    )

    # 将子网掩码转换为前缀长度
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

function Confirm-IPAddress {
    param (
        [string]$IPAddress,
        [string]$SubnetMask
    )

    $ipInteger = Convert-IPAddressToInteger -IPAddress $IPAddress
    $subnetInteger = Convert-IPAddressToInteger -IPAddress $SubnetMask

    # 计算网络地址和广播地址
    $networkAddress = $ipInteger -band $subnetInteger
    $broadcastAddress = $networkAddress -bor -bnot $subnetInteger

    # 计算主机地址范围
    $hostAddressMin = $networkAddress + 1
    $hostAddressMax = $broadcastAddress - 1

    # 判断IP地址是否在主机地址范围内
    if ($ipInteger -ge $hostAddressMin -and $ipInteger -le $hostAddressMax) {
        return $true
    }
    return $false
}

do {
    # 列出所有网卡
    $networkAdapters = Get-NetAdapter | Select-Object -Property Name, InterfaceDescription, InterfaceIndex, Status

    # 显示网卡列表供选择
    Write-Host "请选择要修改的网卡："
    for ($i = 0; $i -lt $networkAdapters.Count; $i++) {
        Write-Host "$($i + 1): $($networkAdapters[$i].Name) - $($networkAdapters[$i].InterfaceDescription)"
    }
    Write-Host "q: 退出脚本"

    # 选择网卡
    $selectedIndex = Read-Host "请输入要修改的网卡的序号"
    
    #输入q退出脚本
    if ($selectedIndex -eq "q") {
        exit
    }
    else {
        #输入其他无效值重复循环
        if ($selectedIndex -lt 1 -or $selectedIndex -gt $networkAdapters.Count ) {
        Write-Host "无效的选择。"
        continue
        }
    }
    
    # 获取选择的网卡对象
    $selectedAdapter = $networkAdapters[$selectedIndex - 1]

    # 检查网卡是否已启用
    if ($selectedAdapter.Status -ne 'Up') {
        Write-Host "选择的网卡未启用。"
        continue
    }

    # 获取选择的网卡的 InterfaceIndex
    $interfaceIndex = $selectedAdapter.InterfaceIndex

    # 显示菜单供选择
    Write-Host "选择操作："
    Write-Host "1. 修改网卡"
    Write-Host "2. 恢复网卡"
    Write-Host "3. 添加静态路由"
    Write-Host "q. 退出脚本"

    # 选择操作
    $action = Read-Host "请输入要执行的操作"

    # 执行选择的操作
    switch ($action) {
        1 {
            # 执行修改网卡操作
            # 清除网卡的所有配置
            Get-NetIPAddress -InterfaceIndex $interfaceIndex | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $interfaceIndex | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue

            # 获取要设置的新 IP 地址和子网前缀长度或子网掩码
            $newIPAddress = Read-Host "请输入新的 IP 地址"
            $newSubnetOrPrefix = Read-Host "请输入子网前缀长度或子网掩码"

            # 判断输入的是前缀长度还是子网掩码
            if ($newSubnetOrPrefix -match '^\d+$') {
                # 输入为前缀长度
                $newPrefixLength = [int]$newSubnetOrPrefix
                $newSubnetMask = Convert-PrefixLengthToSubnetMask -PrefixLength $newPrefixLength
            }
            else {
                # 输入为子网掩码
                $newSubnetMask = $newSubnetOrPrefix
                $newPrefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $newSubnetMask
            }

            # 验证 IP 地址和子网掩码是否匹配
            while (-not (Confirm-IPAddress -IPAddress $newIPAddress -SubnetMask $newSubnetMask)) {
                Write-Host "IP 地址不在子网范围内，请重新输入。"
                $newIPAddress = Read-Host "请输入新的 IP 地址"
                $newSubnetOrPrefix = Read-Host "请输入子网前缀长度或子网掩码"

                # 判断输入的是前缀长度还是子网掩码
                if ($newSubnetOrPrefix -match '^\d+$') {
                    # 输入为前缀长度
                    $newPrefixLength = [int]$newSubnetOrPrefix
                    $newSubnetMask = Convert-PrefixLengthToSubnetMask -PrefixLength $newPrefixLength
                }
                else {
                    # 输入为子网掩码
                    $newSubnetMask = $newSubnetOrPrefix
                    $newPrefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $newSubnetMask
                }
            }

            # 获取要设置的新网关
            $newGateway = Read-Host "请输入新的网关 (可选)"

            # 使用新 IP 地址和子网掩码配置网卡
            New-NetIPAddress -InterfaceIndex $interfaceIndex -IPAddress $newIPAddress -PrefixLength $newPrefixLength | Out-Null

            # 如果有输入网关，则进行检查并设置网关
            while ($true) {
                if ($newGateway -eq "") {
                    break
                }

                # 获取IP地址、子网掩码、网关的整数表示形式
                $ipInteger = Convert-IPAddressToInteger -IPAddress $newIPAddress
                $subnetInteger = Convert-IPAddressToInteger -IPAddress $newSubnetMask
                $gatewayInteger = Convert-IPAddressToInteger -IPAddress $newGateway

                # 获取网络地址的整数表示形式
                $networkAddressInteger = $ipInteger -band $subnetInteger

                # 计算网关的网络地址
                $gatewayNetworkAddressInteger = $gatewayInteger -band $subnetInteger

                # 检查网关是否与 IP 地址在同一子网中，并且确保网关不是输入的IP地址
                if ($networkAddressInteger -ne $gatewayNetworkAddressInteger -or $gatewayInteger -eq $ipInteger) {
                    Write-Host "输入的网关与 IP 地址不在同一子网中或者与 IP 地址相同，请重新输入。"
                    $newGateway = Read-Host "请输入新的网关"
                } else {
                    Write-Host "1. 设置默认路由"
                    Write-Host "2. 设置静态路由"
                    # 选择操作
                    $action = Read-Host "请输入要执行的操作"

                    # 执行选择的操作
                    switch ($action) {
                        1 {
                            # 设置网关
                            New-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix "0.0.0.0/0" -NextHop $newGateway
                            
                            break
                        }
                        2 {
                            # 设置静态路由
                            $staticRouteSelected = "Y"
                            while ($staticRouteSelected -eq "Y") {
                                $destinationNetwork = Read-Host "请输入目标网络地址和前缀长度 (例如：192.168.1.0/24)"

                                # 添加静态路由
                                New-NetRoute -DestinationPrefix $destinationNetwork -InterfaceIndex $interfaceIndex -NextHop $newGateway

                                Write-Host "静态路由已配置。"
                                $staticRouteSelected = Read-Host "是否继续添加(Y/N,default=N)?"
                                }
                            break
                        }               
                        default {
                            Write-Host "输入的值无效"
                        }
                    }
                    break
                }
            }


            # 获取要设置的新 DNS 地址
            $newDNS = Read-Host "请输入多个 DNS 地址，以空格分隔 (可选)"

            # 将输入的 DNS 地址字符串分割为数组
            $newDNS = $newDNS.Split(" ")

            # 如果有输入 DNS 地址，则设置 DNS
            if ($newDNS -ne "") {
                Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $newDNS
            }

            Write-Host "网卡配置已更新。"

            #查看更新后的配置
            Start-Sleep -Seconds 4
            netsh interface ipv4 show config name=$interfaceIndex
        
            break
        }
        2 {
            # 恢复网卡至默认设置

            # 清除网卡的所有配置
            Get-NetIPAddress -InterfaceIndex $interfaceIndex | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $interfaceIndex | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue

            Write-Host "网卡配置已恢复至默认设置。"

            #查看恢复后的配置
            Start-Sleep -Seconds 4
            netsh interface ipv4 show config name=$interfaceIndex

            break
        }
        3 {

            # 配置静态路由

            # 获取要设置的目标网络和网关
            $staticRouteSelected = "Y"
            while ($staticRouteSelected -eq "Y") {
                $destinationNetwork = Read-Host "请输入目标网络地址和前缀长度 (例如：192.168.1.0/24)"
                $gateway = Read-Host "请输入网关地址"
                # 添加静态路由
                New-NetRoute -DestinationPrefix $destinationNetwork -InterfaceIndex $interfaceIndex -NextHop $gateway

                Write-Host "静态路由已配置。"
                $staticRouteSelected = Read-Host "是否继续添加(Y/N,default=N)?"
                }
            
            # 输出路由表
            Get-NetRoute -InterfaceIndex $interfaceIndex

            break
        }
        q {
            #退出脚本
            exit
        }
        default {
            Write-Host "无效的选择，请重输入。"
        }
    }
} while ($true)